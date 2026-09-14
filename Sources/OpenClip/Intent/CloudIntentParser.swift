import Foundation
import Core

/// Explicit-only cloud adapter. Construction performs no network work; `parseIntent` is reached
/// only after the user clicks Try Cloud AI and the separate setting is enabled.
@MainActor
public final class CloudIntentParser: IntentParsing, Sendable {
    private struct Response: Decodable {
        let type: String?
        let summary: String?
        let subject: String?
        let action: String?
        let object: String?
        let target: String?
        let deadlineText: String?
        let trigger: String?

        enum CodingKeys: String, CodingKey {
            case type, summary, subject, action, object, target, trigger
            case deadlineText = "deadline_text"
        }
    }

    private let manager: AIServiceManager

    public init(manager: AIServiceManager = .shared) {
        self.manager = manager
    }

    public func parseIntent(
        from text: String,
        context: IntentParsingContext
    ) async throws -> IntentParseResult {
        let provider = CloudAPIProvider(
            apiKey: manager.cloudAPIKey,
            model: manager.effectiveCloudModel,
            serviceProvider: manager.cloudServiceProvider,
            customBaseURL: manager.cloudCustomURL
        )
        let started = ProcessInfo.processInfo.systemUptime
        let output = try await provider.process(prompt: Self.prompt, text: text)
        let latency = (ProcessInfo.processInfo.systemUptime - started) * 1_000
        guard let data = Self.jsonData(from: output) else { throw AIError.invalidResponse }
        let response = try JSONDecoder().decode(Response.self, from: data)
        let rawType = Self.nonEmpty(response.type)
        let diagnostics = IntentParserDiagnostics(
            rawResponse: output,
            toolSelected: rawType,
            confidence: nil,
            latencyMilliseconds: latency,
            validationResult: "cloud JSON decoded"
        )
        guard let rawType else { return .noIntent(diagnostics: diagnostics) }
        guard let type = IntentType(rawValue: rawType), let summary = Self.nonEmpty(response.summary) else {
            return .uncertain(nil, confidence: nil, diagnostics: diagnostics)
        }
        let deadlineText = Self.nonEmpty(response.deadlineText)
        return .intent(IntentDraft(
            type: type,
            summary: summary,
            subject: Self.nonEmpty(response.subject),
            action: Self.nonEmpty(response.action),
            object: Self.nonEmpty(response.object),
            target: Self.nonEmpty(response.target),
            deadlineText: deadlineText,
            deadline: IntentDeadlineResolver.resolve(deadlineText, relativeTo: context.currentDate),
            trigger: Self.nonEmpty(response.trigger),
            sourceText: text,
            sourceApplicationName: context.sourceApplicationName,
            sourceApplicationBundleIdentifier: context.sourceApplicationBundleIdentifier,
            parser: "cloud.\(manager.cloudServiceProvider.rawValue)",
            parserConfidence: nil,
            diagnostics: diagnostics
        ))
    }

    private static let prompt = """
    Classify the selected text as exactly one IntentOS intent or no intent. Return only one JSON object.
    Types are remember, do, and follow_up. remember requires an explicit request to preserve information.
    do requires the speaker's pending action/commitment or a direct imperative. follow_up requires a
    pending action gated by an event, condition, receipt, missing response, or future checkpoint.
    Return {"type":null} for descriptions, negation, cancellation, completed work, weak speculation,
    and clearly third-party commitments. Never invent fields. Preserve date language verbatim in
    deadline_text. For multiple actions return one primary intent with a combined summary. Allowed
    keys: type, summary, subject, action, object, target, deadline_text, trigger. Optional missing
    values must be null or omitted.
    """

    private static func jsonData(from output: String) -> Data? {
        guard let start = output.firstIndex(of: "{"), let end = output.lastIndex(of: "}"), start <= end else {
            return nil
        }
        return String(output[start...end]).data(using: .utf8)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.lowercased() == "null" || trimmed.lowercased() == "none" {
            return nil
        }
        return trimmed
    }
}

