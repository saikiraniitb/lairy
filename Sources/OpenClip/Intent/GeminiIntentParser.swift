// GeminiIntentParser.swift
// OpenClip
//
// Production/default V1 Intent Intelligence provider. Conforms to the provider-neutral
// `IntentParsing` abstraction — nothing outside this file references Gemini directly;
// `IntentCaptureCoordinator` only ever sees `any IntentParsing`. Which provider and model are
// active is an internal IntentOS decision (`IntentIntelligenceConfiguration`), never a user
// choice — see docs/intentos/intelligence-deployment.md.
//
// Deliberately NOT built on the shared `AIProvider`/`CloudAPIProvider` streaming-text abstraction
// (used by the AI Tools feature and the legacy `CloudIntentParser`): structured output needs its
// own request shape (`generationConfig.responseSchema`) and a JSON Schema contract, never
// freeform-prose parsing.
import Foundation
import Core

/// Product-facing vs. developer-facing copy for a failed Intent Intelligence call. Normal UI must
/// never name the provider or expose implementation details (`productMessage`); DEBUG builds show
/// the real reason (`errorDescription`) to make development useful.
public enum GeminiIntentParserError: LocalizedError, Sendable, Equatable {
    case missingAPIKey
    case invalidResponse
    case httpStatus(Int, String?)
    case timedOut

    /// Normal, non-DEBUG product copy. Never names "Gemini" or exposes HTTP/network detail.
    public var productMessage: String {
        switch self {
        case .missingAPIKey:
            return String(localized: "Intent Intelligence is not configured.")
        case .invalidResponse, .httpStatus, .timedOut:
            return String(localized: "Intent Intelligence is temporarily unavailable.")
        }
    }

    /// Developer-facing detail — surfaced only in DEBUG builds (see `IntentCaptureCoordinator`).
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Gemini API key not found. Set \(IntentIntelligenceConfiguration.geminiAPIKeyEnvironmentVariable) in the environment (see docs/intentos/intelligence-deployment.md)."
        case .invalidResponse:
            return "Gemini returned an unreadable response."
        case .httpStatus(let code, let body):
            if let body, !body.isEmpty {
                return "Gemini request failed (HTTP \(code)): \(body)"
            }
            return "Gemini request failed (HTTP \(code))."
        case .timedOut:
            return "Gemini request timed out."
        }
    }
}

/// Minimal transport seam so tests can exercise request building/response parsing without
/// hitting the real network.
public protocol GeminiTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionGeminiTransport: GeminiTransport {
    public init() {}
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GeminiIntentParserError.invalidResponse }
        return (data, http)
    }
}

public actor GeminiIntentParser: IntentParsing {
    public static let parserPrefix = "gemini"

    private let apiKeyProvider: @Sendable () -> String?
    private let modelProvider: @Sendable () -> String
    private let transport: any GeminiTransport
    private let baseURL: String
    private let timeout: TimeInterval

    public init(
        apiKeyProvider: @escaping @Sendable () -> String? = { IntentIntelligenceConfiguration.geminiAPIKey() },
        modelProvider: @escaping @Sendable () -> String = { IntentIntelligenceConfiguration.defaultGeminiModel },
        transport: any GeminiTransport = URLSessionGeminiTransport(),
        baseURL: String = "https://generativelanguage.googleapis.com/v1beta",
        timeout: TimeInterval = 20
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.modelProvider = modelProvider
        self.transport = transport
        self.baseURL = baseURL
        self.timeout = timeout
    }

    public func parseIntent(from text: String, context: IntentParsingContext) async throws -> IntentParseResult {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return .noIntent() }
        guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else {
            throw GeminiIntentParserError.missingAPIKey
        }
        let model = modelProvider()

        let started = ProcessInfo.processInfo.systemUptime
        let rawJSONText = try await requestUnderstanding(source: source, apiKey: apiKey, model: model)
        let latency = (ProcessInfo.processInfo.systemUptime - started) * 1_000

        let proposed = Self.decodeUnderstanding(from: rawJSONText)
        let grounding = IntentGroundingValidator.validate(proposed, sourceText: source)
        let type = IntentClassifier.classify(grounding.understanding)
        let parserName = "\(Self.parserPrefix).\(model)"

        let diagnostics = IntentParserDiagnostics(
            rawResponse: rawJSONText,
            toolSelected: type?.rawValue,
            rawArguments: Self.encodeUnderstanding(grounding.understanding),
            confidence: grounding.understanding.confidence,
            latencyMilliseconds: latency,
            validationResult: Self.validationSummary(grounding.rejections)
        )

        guard let type else {
            return .noIntent(diagnostics: diagnostics)
        }

        let u = grounding.understanding
        let draft = IntentDraft(
            type: type,
            summary: Self.summary(for: u, fallback: source),
            subject: u.subject,
            action: u.requestedAction,
            target: u.target,
            deadlineText: u.deadlineText,
            deadline: IntentDeadlineResolver.resolve(u.deadlineText, relativeTo: context.currentDate),
            trigger: u.trigger,
            waitingFor: u.waitingFor,
            responseExpected: u.responseExpected,
            requestedOutcome: u.requestedOutcome,
            resources: grounding.resources,
            sourceText: source,
            sourceApplicationName: context.sourceApplicationName,
            sourceApplicationBundleIdentifier: context.sourceApplicationBundleIdentifier,
            parser: parserName,
            parserConfidence: u.confidence,
            diagnostics: diagnostics
        )

        if let confidence = u.confidence, confidence < 0.5 {
            return .uncertain(draft, confidence: confidence, diagnostics: diagnostics)
        }
        return .intent(draft)
    }

    // MARK: - Networking

    private func requestUnderstanding(source: String, apiKey: String, model: String) async throws -> String {
        let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
        guard let url = URL(string: "\(baseURL)/models/\(encodedModel):generateContent") else {
            throw GeminiIntentParserError.invalidResponse
        }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: Self.requestBody(systemPrompt: Self.systemPrompt, userText: source))

        let (data, http): (Data, HTTPURLResponse)
        do {
            (data, http) = try await transport.send(request)
        } catch is CancellationError {
            throw GeminiIntentParserError.timedOut
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw GeminiIntentParserError.timedOut
        }

        guard http.statusCode == 200 else {
            let body = String(data: data.prefix(500), encoding: .utf8)
            throw GeminiIntentParserError.httpStatus(http.statusCode, body)
        }

        guard let text = Self.extractResponseText(from: data) else {
            throw GeminiIntentParserError.invalidResponse
        }
        return text
    }

    /// Pulls `candidates[0].content.parts[0].text` — the JSON-Schema-constrained payload Gemini
    /// returns as a text part when `generationConfig.responseMimeType == "application/json"`.
    private static func extractResponseText(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = root["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            return nil
        }
        return text
    }

    // MARK: - Understanding decode

    private static func decodeUnderstanding(from jsonText: String) -> IntentUnderstanding {
        guard let data = jsonText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return IntentUnderstanding(hasTrackableIntent: false)
        }

        func str(_ key: String) -> String? {
            (object[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        }
        func enumValue<T: RawRepresentable>(_ key: String, _ type: T.Type) -> T? where T.RawValue == String {
            (object[key] as? String).flatMap(T.init(rawValue:))
        }
        let labels: [IntentResourceLabelSuggestion] = (object["resourceLabels"] as? [[String: Any]] ?? []).compactMap { entry in
            guard let url = entry["url"] as? String, let label = entry["label"] as? String else { return nil }
            return IntentResourceLabelSuggestion(url: url, label: label)
        }

        return IntentUnderstanding(
            hasTrackableIntent: (object["hasTrackableIntent"] as? Bool) ?? false,
            speechAct: enumValue("speechAct", SpeechAct.self),
            direction: enumValue("direction", IntentDirection.self),
            actor: enumValue("actor", ActorType.self),
            owner: enumValue("owner", IntentOwner.self),
            requestedAction: str("requestedAction"),
            subject: str("subject"),
            target: str("target"),
            requestedOutcome: str("requestedOutcome"),
            temporalState: enumValue("temporalState", TemporalState.self),
            polarity: enumValue("polarity", Polarity.self),
            commitmentStrength: enumValue("commitmentStrength", CommitmentStrength.self),
            deadlineText: str("deadlineText"),
            trigger: str("trigger"),
            waitingFor: str("waitingFor"),
            responseExpected: object["responseExpected"] as? Bool,
            resourceLabels: labels,
            confidence: object["confidence"] as? Double
        )
    }

    private static func summary(for u: IntentUnderstanding, fallback: String) -> String {
        u.requestedOutcome ?? u.requestedAction ?? u.subject ?? fallback
    }

    private static func encodeUnderstanding(_ u: IntentUnderstanding) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(u)).flatMap { String(data: $0, encoding: .utf8) }
    }

    private static func validationSummary(_ rejections: [IntentGroundingRejection]) -> String {
        rejections.isEmpty
            ? "grounded; no rejections"
            : rejections.map { "\($0.field)=\"\($0.value)\" rejected (\($0.reason))" }.joined(separator: "; ")
    }

    // MARK: - Request construction

    static func requestBody(systemPrompt: String, userText: String) -> [String: Any] {
        [
            "systemInstruction": ["parts": [["text": systemPrompt]]],
            "contents": [["parts": [["text": userText]]]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": understandingSchema,
                "temperature": 0.1
            ]
        ]
    }

    static var understandingSchema: [String: Any] { [
        "type": "OBJECT",
        "properties": [
            "hasTrackableIntent": ["type": "BOOLEAN"],
            "speechAct": ["type": "STRING", "enum": SpeechAct.allCases.map(\.rawValue)],
            "direction": ["type": "STRING", "enum": IntentDirection.allCases.map(\.rawValue)],
            "actor": ["type": "STRING", "enum": ActorType.allCases.map(\.rawValue)],
            "owner": ["type": "STRING", "enum": IntentOwner.allCases.map(\.rawValue)],
            "requestedAction": ["type": "STRING", "nullable": true],
            "subject": ["type": "STRING", "nullable": true],
            "target": ["type": "STRING", "nullable": true],
            "requestedOutcome": ["type": "STRING", "nullable": true],
            "temporalState": ["type": "STRING", "enum": TemporalState.allCases.map(\.rawValue)],
            "polarity": ["type": "STRING", "enum": Polarity.allCases.map(\.rawValue)],
            "commitmentStrength": ["type": "STRING", "enum": CommitmentStrength.allCases.map(\.rawValue)],
            "deadlineText": ["type": "STRING", "nullable": true, "description": "Verbatim date/time phrase copied from the source text, or omitted if none. Never inferred, never computed."],
            "trigger": ["type": "STRING", "nullable": true, "description": "Verbatim condition/event clause from the source text that gates the action, if any."],
            "waitingFor": ["type": "STRING", "nullable": true, "description": "Verbatim name of the person/party the user is waiting on, if any."],
            "responseExpected": ["type": "BOOLEAN", "nullable": true],
            "resourceLabels": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": ["url": ["type": "STRING"], "label": ["type": "STRING"]],
                    "required": ["url", "label"]
                ]
            ],
            "confidence": ["type": "NUMBER", "nullable": true]
        ],
        "required": ["hasTrackableIntent", "speechAct", "direction", "actor", "owner", "temporalState", "polarity", "commitmentStrength"]
    ] }

    static let systemPrompt = """
    You are IntentOS Intent Intelligence.

    Your task is to determine whether explicitly selected text represents something the user \
    should track, and to describe your understanding of it structurally. You never see anything \
    the user did not explicitly select and capture.

    Prefer NO_INTENT (hasTrackableIntent = false) over inventing an obligation. Never invent \
    dates, deadlines, people, actions, resources, recipients, or triggers not clearly supported \
    by the input text. Every date/time phrase, person name, or condition clause you report must \
    be copied verbatim from the input — never computed, resolved, or paraphrased. If the input \
    has no such phrase, omit that field entirely.

    Distinguish:
    - actions the user must perform
    - requests the user sent to others
    - things the user is waiting for
    - explicit information the user wants remembered
    - non-actionable statements

    Pay special attention to:
    - who is speaking, and who owns the next action
    - tense (past work is not trackable; only present/future/conditional obligations are)
    - negation ("don't send this" is never a positive action)
    - conditional language ("if Finance approves it, send the proposal")
    - completed work ("I already sent it") — not trackable
    - third-party commitments ("Arun will send me the roadmap") — never owned by the user
    - requests and whether the user is the one asking or the one being asked
    - direction: "incoming" means the text is addressed AT the reader (presumed to be the user) —
      e.g. "Please review this", "Can you send me X" said BY someone else TO the user. "outgoing"
      means the text is the user's OWN words addressed to someone else — e.g. "Can we have a
      session at 5pm?", "I'll send you the file." First-person subject pronouns ("I", "I'll",
      "I'm") without a direct question/request to the reader suggest outgoing/self; an imperative
      or a question with no first-person framing suggests incoming.
    - whether a response/reply is expected at all

    Return only structured data matching the provided schema.
    """
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
