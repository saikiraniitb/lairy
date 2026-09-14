import Foundation

public struct IntentParsingContext: Sendable {
    public let sourceApplicationName: String?
    public let sourceApplicationBundleIdentifier: String?
    public let currentDate: Date

    public init(
        sourceApplicationName: String? = nil,
        sourceApplicationBundleIdentifier: String? = nil,
        currentDate: Date = Date()
    ) {
        self.sourceApplicationName = sourceApplicationName
        self.sourceApplicationBundleIdentifier = sourceApplicationBundleIdentifier
        self.currentDate = currentDate
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

