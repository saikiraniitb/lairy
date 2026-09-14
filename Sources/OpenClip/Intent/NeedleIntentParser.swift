import Foundation
import Core

public enum NeedleIntentParserError: LocalizedError, Sendable {
    case helperUnavailable(String)
    case helperFailed(String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .helperUnavailable(let reason): return "Needle helper is unavailable: \(reason)"
        case .helperFailed(let reason): return "Needle helper failed: \(reason)"
        case .invalidResponse: return "Needle returned an invalid response."
        }
    }
}

private struct NeedleHelperResponse: Decodable, Sendable {
    let ok: Bool
    let error: String?
    let predictedIntentType: String?
    let predictedFields: [String: String]?
    let confidence: Double?
    let latencyMilliseconds: Double?
    let prefillTokensPerSecond: Double?
    let decodeTokensPerSecond: Double?
    let peakRAMMegabytes: Double?
    let multipleCalls: Bool?
    let validationText: String?

    enum CodingKeys: String, CodingKey {
        case ok, error, confidence
        case predictedIntentType = "predicted_intent_type"
        case predictedFields = "predicted_fields"
        case latencyMilliseconds = "latency_ms"
        case prefillTokensPerSecond = "prefill_tps"
        case decodeTokensPerSecond = "decode_tps"
        case peakRAMMegabytes = "peak_ram_mb"
        case multipleCalls = "multiple_calls"
        case validationText = "validation_text"
    }
}

private struct NeedleHelperRequest: Encodable, Sendable {
    let id: UUID
    let text: String
    let currentDate: String

    enum CodingKeys: String, CodingKey {
        case id, text
        case currentDate = "current_date"
    }
}

/// Blocking pipe ownership is isolated behind a lock and invoked from a detached task. One helper
/// stays warm for the app's lifetime; requests are serialized because Needle 2 owns one KV session.
private final class NeedleHelperClient: @unchecked Sendable {
    private let lock = NSLock()
    private let pythonURL: URL
    private let scriptURL: URL
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?

    init(pythonURL: URL, scriptURL: URL) {
        self.pythonURL = pythonURL
        self.scriptURL = scriptURL
    }

    deinit {
        process?.terminate()
    }

    func request(_ encodedRequest: Data) throws -> Data {
        lock.lock()
        defer { lock.unlock() }

        try startIfNeeded()
        guard let input, let output else {
            throw NeedleIntentParserError.helperUnavailable("missing process pipes")
        }

        do {
            try input.write(contentsOf: encodedRequest)
            try input.write(contentsOf: Data([0x0A]))
            return try readLine(from: output)
        } catch {
            stop()
            throw NeedleIntentParserError.helperFailed(error.localizedDescription)
        }
    }

    private func startIfNeeded() throws {
        if process?.isRunning == true { return }
        stop()

        guard FileManager.default.isExecutableFile(atPath: pythonURL.path) else {
            throw NeedleIntentParserError.helperUnavailable("Python environment not found at \(pythonURL.path)")
        }
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw NeedleIntentParserError.helperUnavailable("helper script not found at \(scriptURL.path)")
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = pythonURL
        process.arguments = [scriptURL.path]
        process.currentDirectoryURL = scriptURL.deletingLastPathComponent()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.standardError
        var environment = ProcessInfo.processInfo.environment
        environment["NEEDLE_TELEMETRY"] = "0"
        environment["DO_NOT_TRACK"] = "1"
        process.environment = environment

        do {
            try process.run()
            self.process = process
            input = inputPipe.fileHandleForWriting
            output = outputPipe.fileHandleForReading
            let ready = try readLine(from: outputPipe.fileHandleForReading)
            guard let object = try JSONSerialization.jsonObject(with: ready) as? [String: Any],
                  object["type"] as? String == "ready" else {
                stop()
                throw NeedleIntentParserError.invalidResponse
            }
        } catch let error as NeedleIntentParserError {
            throw error
        } catch {
            stop()
            throw NeedleIntentParserError.helperUnavailable(error.localizedDescription)
        }
    }

    private func readLine(from handle: FileHandle) throws -> Data {
        var data = Data()
        while true {
            guard let byte = try handle.read(upToCount: 1), !byte.isEmpty else {
                throw NeedleIntentParserError.helperFailed("helper closed its output")
            }
            if byte[byte.startIndex] == 0x0A { return data }
            data.append(byte)
            guard data.count <= 1_048_576 else {
                throw NeedleIntentParserError.invalidResponse
            }
        }
    }

    private func stop() {
        try? input?.close()
        try? output?.close()
        if process?.isRunning == true { process?.terminate() }
        input = nil
        output = nil
        process = nil
    }
}

public actor NeedleIntentParser: IntentParsing {
    public static let parserName = "needle2-base"

    private let confidenceThreshold: Double
    private let client: NeedleHelperClient
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let dateFormatter: ISO8601DateFormatter

    public init(
        confidenceThreshold: Double = 0.75,
        pythonURL: URL? = nil,
        helperScriptURL: URL? = nil
    ) {
        self.confidenceThreshold = min(max(confidenceThreshold, 0), 1)
        let locations = Self.resolveHelperLocations(pythonURL: pythonURL, scriptURL: helperScriptURL)
        self.client = NeedleHelperClient(pythonURL: locations.python, scriptURL: locations.script)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        self.dateFormatter = formatter
    }

    public func parseIntent(
        from text: String,
        context: IntentParsingContext
    ) async throws -> IntentParseResult {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return .noIntent() }

        let request = NeedleHelperRequest(
            id: UUID(),
            text: source,
            currentDate: dateFormatter.string(from: context.currentDate)
        )
        let encoded = try encoder.encode(request)
        let client = self.client
        let responseData = try await Task.detached(priority: .userInitiated) {
            try client.request(encoded)
        }.value

        let response = try decoder.decode(NeedleHelperResponse.self, from: responseData)
        guard response.ok else {
            throw NeedleIntentParserError.helperFailed(response.error ?? "unknown helper error")
        }
        let rawResponse = String(data: responseData, encoding: .utf8)
        let rawArguments = response.predictedFields.flatMap { fields -> String? in
            guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        let diagnostics = IntentParserDiagnostics(
            rawResponse: rawResponse,
            toolSelected: response.predictedIntentType,
            rawArguments: rawArguments,
            confidence: response.confidence,
            latencyMilliseconds: response.latencyMilliseconds,
            prefillTokensPerSecond: response.prefillTokensPerSecond,
            decodeTokensPerSecond: response.decodeTokensPerSecond,
            peakRAMMegabytes: response.peakRAMMegabytes,
            validationResult: [
                response.multipleCalls == true ? "multiple calls; first retained" : "single primary call",
                response.validationText
            ].compactMap { $0 }.joined(separator: "; ")
        )

        guard let rawType = response.predictedIntentType else {
            return .noIntent(diagnostics: diagnostics)
        }
        guard let type = IntentType(rawValue: rawType) else {
            return .uncertain(nil, confidence: response.confidence, diagnostics: diagnostics)
        }

        let fields = response.predictedFields ?? [:]
        let deadlineText = Self.nonEmpty(fields["deadline_text"])
        let draft = IntentDraft(
            type: type,
            summary: Self.nonEmpty(fields["summary"]) ?? source,
            subject: Self.nonEmpty(fields["subject"]),
            action: Self.nonEmpty(fields["action"]),
            object: Self.nonEmpty(fields["object"]),
            target: Self.nonEmpty(fields["target"]),
            deadlineText: deadlineText,
            deadline: IntentDeadlineResolver.resolve(deadlineText, relativeTo: context.currentDate),
            trigger: Self.nonEmpty(fields["trigger"]),
            sourceText: source,
            sourceApplicationName: context.sourceApplicationName,
            sourceApplicationBundleIdentifier: context.sourceApplicationBundleIdentifier,
            parser: Self.parserName,
            parserConfidence: response.confidence,
            diagnostics: diagnostics
        )

        guard let confidence = response.confidence, confidence >= confidenceThreshold else {
            return .uncertain(draft, confidence: response.confidence, diagnostics: diagnostics)
        }
        return .intent(draft)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func resolveHelperLocations(
        pythonURL: URL?,
        scriptURL: URL?
    ) -> (python: URL, script: URL) {
        let environment = ProcessInfo.processInfo.environment
        if let pythonURL, let scriptURL { return (pythonURL, scriptURL) }

        let sourceFile = URL(fileURLWithPath: #filePath)
        let projectRoot = sourceFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let spike = projectRoot.appendingPathComponent("tools/needle-spike", isDirectory: true)
        let resolvedPython = pythonURL
            ?? environment["INTENTOS_NEEDLE_PYTHON"].map(URL.init(fileURLWithPath:))
            ?? spike.appendingPathComponent(".venv/bin/python")
        let resolvedScript = scriptURL
            ?? environment["INTENTOS_NEEDLE_HELPER"].map(URL.init(fileURLWithPath:))
            ?? spike.appendingPathComponent("helper.py")
        return (resolvedPython, resolvedScript)
    }
}
