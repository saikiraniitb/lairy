import Foundation

public struct IntentParsingContext: Sendable {
    public let captureID: UUID
    public let sourceApplicationName: String?
    public let sourceApplicationBundleIdentifier: String?
    public let currentDate: Date
    /// Trusted message/conversation metadata, resolved deterministically before parsing — see
    /// `SourceContextResolving`. Nil when no resolver ran or nothing was reliably determined.
    public let sourceContext: IntentSourceContext?

    public init(
        sourceApplicationName: String? = nil,
        sourceApplicationBundleIdentifier: String? = nil,
        currentDate: Date = Date(),
        sourceContext: IntentSourceContext? = nil,
        captureID: UUID = UUID()
    ) {
        self.captureID = captureID
        self.sourceApplicationName = sourceApplicationName
        self.sourceApplicationBundleIdentifier = sourceApplicationBundleIdentifier
        self.currentDate = currentDate
        self.sourceContext = sourceContext
    }
}
public enum IntentParseResult: Equatable, Sendable {
    case intent(IntentDraft)
    case noIntent(diagnostics: IntentParserDiagnostics? = nil)
    case uncertain(IntentDraft?, confidence: Double?, diagnostics: IntentParserDiagnostics? = nil)
}

public protocol IntentParsing: Sendable {
    func parseIntent(
        from text: String,
        context: IntentParsingContext
    ) async throws -> IntentParseResult
}
