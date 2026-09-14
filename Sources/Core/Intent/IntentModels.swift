import Foundation

public enum IntentType: String, Codable, CaseIterable, Sendable {
    case remember
    case doAction = "do"
    case followUp = "follow_up"
}

public enum IntentStatus: String, Codable, CaseIterable, Sendable {
    case open
    case done
    case cancelled
}

public struct IntentParserDiagnostics: Codable, Equatable, Sendable {
    public var rawResponse: String?
    public var toolSelected: String?
    public var rawArguments: String?
    public var confidence: Double?
    public var latencyMilliseconds: Double?
    public var prefillTokensPerSecond: Double?
    public var decodeTokensPerSecond: Double?
    public var peakRAMMegabytes: Double?
    public var validationResult: String?

    public init(
        rawResponse: String? = nil,
        toolSelected: String? = nil,
        rawArguments: String? = nil,
        confidence: Double? = nil,
        latencyMilliseconds: Double? = nil,
        prefillTokensPerSecond: Double? = nil,
        decodeTokensPerSecond: Double? = nil,
        peakRAMMegabytes: Double? = nil,
        validationResult: String? = nil
    ) {
        self.rawResponse = rawResponse
        self.toolSelected = toolSelected
        self.rawArguments = rawArguments
        self.confidence = confidence
        self.latencyMilliseconds = latencyMilliseconds
        self.prefillTokensPerSecond = prefillTokensPerSecond
        self.decodeTokensPerSecond = decodeTokensPerSecond
        self.peakRAMMegabytes = peakRAMMegabytes
        self.validationResult = validationResult
    }
}

public struct IntentDraft: Codable, Equatable, Sendable {
    public var type: IntentType
    public var summary: String
    public var action: String?
    public var object: String?
    public var target: String?
    public var deadlineText: String?
    public var deadline: Date?
    public var trigger: String?

    public var sourceText: String
    public var sourceApplicationName: String?
    public var sourceApplicationBundleIdentifier: String?

    public var parser: String
    public var parserConfidence: Double?
    public var diagnostics: IntentParserDiagnostics?

    public init(
        type: IntentType,
        summary: String,
        action: String? = nil,
        object: String? = nil,
        target: String? = nil,
        deadlineText: String? = nil,
        deadline: Date? = nil,
        trigger: String? = nil,
        sourceText: String,
        sourceApplicationName: String? = nil,
        sourceApplicationBundleIdentifier: String? = nil,
        parser: String,
        parserConfidence: Double? = nil,
        diagnostics: IntentParserDiagnostics? = nil
    ) {
        self.type = type
        self.summary = summary
        self.action = action
        self.object = object
        self.target = target
        self.deadlineText = deadlineText
        self.deadline = deadline
        self.trigger = trigger
        self.sourceText = sourceText
        self.sourceApplicationName = sourceApplicationName
        self.sourceApplicationBundleIdentifier = sourceApplicationBundleIdentifier
        self.parser = parser
        self.parserConfidence = parserConfidence
        self.diagnostics = diagnostics
    }
}

public struct CapturedIntent: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID

    public var type: IntentType
    public var status: IntentStatus
    public var summary: String
    public var action: String?
    public var object: String?
    public var target: String?
    public var deadlineText: String?
    public var deadline: Date?
    public var trigger: String?

    public var sourceText: String
    public var sourceApplicationName: String?
    public var sourceApplicationBundleIdentifier: String?

    public var parser: String
    public var parserConfidence: Double?
    public var diagnostics: IntentParserDiagnostics?

    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        type: IntentType,
        status: IntentStatus = .open,
        summary: String,
        action: String? = nil,
        object: String? = nil,
        target: String? = nil,
        deadlineText: String? = nil,
        deadline: Date? = nil,
        trigger: String? = nil,
        sourceText: String,
        sourceApplicationName: String? = nil,
        sourceApplicationBundleIdentifier: String? = nil,
        parser: String,
        parserConfidence: Double? = nil,
        diagnostics: IntentParserDiagnostics? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.status = status
        self.summary = summary
        self.action = action
        self.object = object
        self.target = target
        self.deadlineText = deadlineText
        self.deadline = deadline
        self.trigger = trigger
        self.sourceText = sourceText
        self.sourceApplicationName = sourceApplicationName
        self.sourceApplicationBundleIdentifier = sourceApplicationBundleIdentifier
        self.parser = parser
        self.parserConfidence = parserConfidence
        self.diagnostics = diagnostics
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(draft: IntentDraft, id: UUID = UUID(), now: Date = Date()) {
        self.init(
            id: id,
            type: draft.type,
            summary: draft.summary,
            action: draft.action,
            object: draft.object,
            target: draft.target,
            deadlineText: draft.deadlineText,
            deadline: draft.deadline,
            trigger: draft.trigger,
            sourceText: draft.sourceText,
            sourceApplicationName: draft.sourceApplicationName,
            sourceApplicationBundleIdentifier: draft.sourceApplicationBundleIdentifier,
            parser: draft.parser,
            parserConfidence: draft.parserConfidence,
            diagnostics: draft.diagnostics,
            createdAt: now,
            updatedAt: now
        )
    }
}

