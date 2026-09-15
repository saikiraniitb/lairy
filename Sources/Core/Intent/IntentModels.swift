import Foundation

/// IntentOS's final, provider-neutral intent taxonomy (Intent Intelligence V1). Replaces the
/// pre-Gemini `remember`/`do`/`follow_up` taxonomy — a follow-up is now expressed through
/// `IntentDraft.waitingFor`/`trigger`/`deadlineText` on an `.action`/`.request`/`.waiting` intent,
/// never as its own top-level type. `NO_INTENT` is deliberately not a case here: it is never a
/// trackable intent, so it is represented only by `IntentParseResult.noIntent`.
public enum IntentType: String, Codable, CaseIterable, Sendable {
    case action
    case request
    case waiting
    case remember

    /// Legacy raw values from the pre-Gemini taxonomy, mapped so intents parsed or persisted
    /// before this migration keep decoding correctly: `remember` is unchanged, `do` becomes the
    /// nearest new equivalent (a self-owned action), and `follow_up` (a pending action gated on
    /// someone/something else) becomes `waiting`.
    private static let legacyRawValues: [String: IntentType] = [
        "do": .action,
        "follow_up": .waiting
    ]

    /// Resolves either a current or a legacy raw value. Use this (not the `RawRepresentable`
    /// initializer) anywhere a raw string arrives outside of `Decodable` — e.g. a parser mapping
    /// its own wire format's type string onto `IntentType`.
    public static func resolve(rawValue raw: String) -> IntentType? {
        IntentType(rawValue: raw) ?? legacyRawValues[raw]
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = Self.resolve(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown intent type: \(raw)")
        }
        self = value
    }
}

public enum IntentStatus: String, Codable, CaseIterable, Sendable {
    case open
    case waiting
    case done
    case cancelled

    /// Sensible default workflow status for a freshly captured intent of `type` — always
    /// overridable afterward in the Intent Inbox. `.waiting`-type intents default to a `.waiting`
    /// status; everything else opens in `.open`.
    public static func defaultStatus(for type: IntentType) -> IntentStatus {
        type == .waiting ? .waiting : .open
    }
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
    public var captureID: UUID?
    public var sourceContext: IntentSourceContext?
    public var type: IntentType
    public var summary: String
    public var subject: String?
    public var action: String?
    public var object: String?
    public var target: String? {
        didSet { target = IntentGroundingValidator.personValue(target) }
    }
    public var deadlineText: String?
    public var deadline: Date?
    public var trigger: String?

    /// Who/what the user is waiting on (a REQUEST/WAITING intent's counterpart). Grounded: only
    /// ever set when the value appears verbatim in `sourceText`.
    public var waitingFor: String? {
        didSet { waitingFor = IntentGroundingValidator.personValue(waitingFor) }
    }
    /// Whether a reply/response is expected at all, per the provider's understanding.
    public var responseExpected: Bool?
    /// The outcome the user is seeking (e.g. "feedback or approval"), distinct from `action`.
    public var requestedOutcome: String?
    /// Who asked for this action. Trusted: either `IntentSourceContext.sender` (when a trusted
    /// sender was resolved) or a value grounded against source text — never an unverified provider
    /// guess. See `GeminiIntentParser` and `IntentGroundingValidator`.
    public var requestedBy: String? {
        didSet { requestedBy = IntentGroundingValidator.personValue(requestedBy) }
    }
    /// Deterministically extracted from `sourceText` — never provider-supplied. See
    /// `IntentResourceExtractor`.
    public var resources: [IntentResource]

    /// A self-owned/action deadline (e.g. "Review this by Friday").
    public var dueAt: IntentTemporalValue?
    /// A scheduled event/meeting time (e.g. "Let's meet Friday at 5").
    public var eventAt: IntentTemporalValue?
    /// When to check back on a WAITING intent (e.g. "Check again Monday").
    public var followUpAt: IntentTemporalValue?
    /// A clock time was mentioned (e.g. "5pm") but no date could be resolved — never silently
    /// paired with an invented date. The When control surfaces this so the user can resolve it.
    public var unresolvedTimeText: String?

    public var sourceText: String
    public var sourceApplicationName: String?
    public var sourceApplicationBundleIdentifier: String?

    public var parser: String
    public var parserConfidence: Double?
    public var diagnostics: IntentParserDiagnostics?

    public init(
        type: IntentType,
        summary: String,
        subject: String? = nil,
        action: String? = nil,
        object: String? = nil,
        target: String? = nil,
        deadlineText: String? = nil,
        deadline: Date? = nil,
        trigger: String? = nil,
        waitingFor: String? = nil,
        responseExpected: Bool? = nil,
        requestedOutcome: String? = nil,
        requestedBy: String? = nil,
        resources: [IntentResource] = [],
        dueAt: IntentTemporalValue? = nil,
        eventAt: IntentTemporalValue? = nil,
        followUpAt: IntentTemporalValue? = nil,
        unresolvedTimeText: String? = nil,
        sourceText: String,
        sourceApplicationName: String? = nil,
        sourceApplicationBundleIdentifier: String? = nil,
        parser: String,
        parserConfidence: Double? = nil,
        diagnostics: IntentParserDiagnostics? = nil
    ) {
        self.type = type
        self.summary = summary
        self.subject = subject
        self.action = action
        self.object = object
        self.target = IntentGroundingValidator.personValue(target)
        self.deadlineText = deadlineText
        self.deadline = deadline
        self.trigger = trigger
        self.waitingFor = IntentGroundingValidator.personValue(waitingFor)
        self.responseExpected = responseExpected
        self.requestedOutcome = requestedOutcome
        self.requestedBy = IntentGroundingValidator.personValue(requestedBy)
        self.resources = resources
        self.dueAt = dueAt
        self.eventAt = eventAt
        self.followUpAt = followUpAt
        self.unresolvedTimeText = unresolvedTimeText
        self.sourceText = sourceText
        self.sourceApplicationName = sourceApplicationName
        self.sourceApplicationBundleIdentifier = sourceApplicationBundleIdentifier
        self.parser = parser
        self.parserConfidence = parserConfidence
        self.diagnostics = diagnostics
    }

    /// Tolerates records written before `waitingFor`/`responseExpected`/`requestedOutcome`/
    /// `resources` existed: missing keys default to nil/empty rather than failing to decode.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        captureID = try container.decodeIfPresent(UUID.self, forKey: .captureID)
        sourceContext = try container.decodeIfPresent(IntentSourceContext.self, forKey: .sourceContext)
        type = try container.decode(IntentType.self, forKey: .type)
        summary = try container.decode(String.self, forKey: .summary)
        subject = try container.decodeIfPresent(String.self, forKey: .subject)
        action = try container.decodeIfPresent(String.self, forKey: .action)
        object = try container.decodeIfPresent(String.self, forKey: .object)
        target = IntentGroundingValidator.personValue(try container.decodeIfPresent(String.self, forKey: .target))
        deadlineText = try container.decodeIfPresent(String.self, forKey: .deadlineText)
        deadline = try container.decodeIfPresent(Date.self, forKey: .deadline)
        trigger = try container.decodeIfPresent(String.self, forKey: .trigger)
        waitingFor = IntentGroundingValidator.personValue(try container.decodeIfPresent(String.self, forKey: .waitingFor))
        responseExpected = try container.decodeIfPresent(Bool.self, forKey: .responseExpected)
        requestedOutcome = try container.decodeIfPresent(String.self, forKey: .requestedOutcome)
        requestedBy = IntentGroundingValidator.personValue(try container.decodeIfPresent(String.self, forKey: .requestedBy))
        resources = try container.decodeIfPresent([IntentResource].self, forKey: .resources) ?? []
        dueAt = try container.decodeIfPresent(IntentTemporalValue.self, forKey: .dueAt)
        eventAt = try container.decodeIfPresent(IntentTemporalValue.self, forKey: .eventAt)
        followUpAt = try container.decodeIfPresent(IntentTemporalValue.self, forKey: .followUpAt)
        unresolvedTimeText = try container.decodeIfPresent(String.self, forKey: .unresolvedTimeText)
        sourceText = try container.decode(String.self, forKey: .sourceText)
        sourceApplicationName = try container.decodeIfPresent(String.self, forKey: .sourceApplicationName)
        sourceApplicationBundleIdentifier = try container.decodeIfPresent(String.self, forKey: .sourceApplicationBundleIdentifier)
        parser = try container.decode(String.self, forKey: .parser)
        parserConfidence = try container.decodeIfPresent(Double.self, forKey: .parserConfidence)
        diagnostics = try container.decodeIfPresent(IntentParserDiagnostics.self, forKey: .diagnostics)
    }
}

public struct CapturedIntent: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var captureID: UUID?
    public var sourceContext: IntentSourceContext?

    public var type: IntentType
    public var status: IntentStatus
    public var summary: String
    public var subject: String?
    public var action: String?
    public var object: String?
    public var target: String? {
        didSet { target = IntentGroundingValidator.personValue(target) }
    }
    public var deadlineText: String?
    public var deadline: Date?
    public var trigger: String?

    public var waitingFor: String? {
        didSet { waitingFor = IntentGroundingValidator.personValue(waitingFor) }
    }
    public var responseExpected: Bool?
    public var requestedOutcome: String?
    public var requestedBy: String? {
        didSet { requestedBy = IntentGroundingValidator.personValue(requestedBy) }
    }
    public var resources: [IntentResource]

    public var dueAt: IntentTemporalValue?
    public var eventAt: IntentTemporalValue?
    public var followUpAt: IntentTemporalValue?
    public var unresolvedTimeText: String?

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
        status: IntentStatus? = nil,
        summary: String,
        subject: String? = nil,
        action: String? = nil,
        object: String? = nil,
        target: String? = nil,
        deadlineText: String? = nil,
        deadline: Date? = nil,
        trigger: String? = nil,
        waitingFor: String? = nil,
        responseExpected: Bool? = nil,
        requestedOutcome: String? = nil,
        requestedBy: String? = nil,
        resources: [IntentResource] = [],
        dueAt: IntentTemporalValue? = nil,
        eventAt: IntentTemporalValue? = nil,
        followUpAt: IntentTemporalValue? = nil,
        unresolvedTimeText: String? = nil,
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
        self.status = status ?? IntentStatus.defaultStatus(for: type)
        self.summary = summary
        self.subject = subject
        self.action = action
        self.object = object
        self.target = IntentGroundingValidator.personValue(target)
        self.deadlineText = deadlineText
        self.deadline = deadline
        self.trigger = trigger
        self.waitingFor = IntentGroundingValidator.personValue(waitingFor)
        self.responseExpected = responseExpected
        self.requestedOutcome = requestedOutcome
        self.requestedBy = IntentGroundingValidator.personValue(requestedBy)
        self.resources = resources
        self.dueAt = dueAt
        self.eventAt = eventAt
        self.followUpAt = followUpAt
        self.unresolvedTimeText = unresolvedTimeText
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
            subject: draft.subject,
            action: draft.action,
            object: draft.object,
            target: draft.target,
            deadlineText: draft.deadlineText,
            deadline: draft.deadline,
            trigger: draft.trigger,
            waitingFor: draft.waitingFor,
            responseExpected: draft.responseExpected,
            requestedOutcome: draft.requestedOutcome,
            requestedBy: draft.requestedBy,
            resources: draft.resources,
            dueAt: draft.dueAt,
            eventAt: draft.eventAt,
            followUpAt: draft.followUpAt,
            unresolvedTimeText: draft.unresolvedTimeText,
            sourceText: draft.sourceText,
            sourceApplicationName: draft.sourceApplicationName,
            sourceApplicationBundleIdentifier: draft.sourceApplicationBundleIdentifier,
            parser: draft.parser,
            parserConfidence: draft.parserConfidence,
            diagnostics: draft.diagnostics,
            createdAt: now,
            updatedAt: now
        )
        self.captureID = draft.captureID
        self.sourceContext = draft.sourceContext
    }

    /// Tolerates records written before `waitingFor`/`responseExpected`/`requestedOutcome`/
    /// `requestedBy`/`resources`/`dueAt`/`eventAt`/`followUpAt`/`unresolvedTimeText`/
    /// `IntentStatus.waiting` existed: missing keys default to nil/empty.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        captureID = try container.decodeIfPresent(UUID.self, forKey: .captureID)
        sourceContext = try container.decodeIfPresent(IntentSourceContext.self, forKey: .sourceContext)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(IntentType.self, forKey: .type)
        status = try container.decode(IntentStatus.self, forKey: .status)
        summary = try container.decode(String.self, forKey: .summary)
        subject = try container.decodeIfPresent(String.self, forKey: .subject)
        action = try container.decodeIfPresent(String.self, forKey: .action)
        object = try container.decodeIfPresent(String.self, forKey: .object)
        target = IntentGroundingValidator.personValue(try container.decodeIfPresent(String.self, forKey: .target))
        deadlineText = try container.decodeIfPresent(String.self, forKey: .deadlineText)
        deadline = try container.decodeIfPresent(Date.self, forKey: .deadline)
        trigger = try container.decodeIfPresent(String.self, forKey: .trigger)
        waitingFor = IntentGroundingValidator.personValue(try container.decodeIfPresent(String.self, forKey: .waitingFor))
        responseExpected = try container.decodeIfPresent(Bool.self, forKey: .responseExpected)
        requestedOutcome = try container.decodeIfPresent(String.self, forKey: .requestedOutcome)
        requestedBy = IntentGroundingValidator.personValue(try container.decodeIfPresent(String.self, forKey: .requestedBy))
        resources = try container.decodeIfPresent([IntentResource].self, forKey: .resources) ?? []
        dueAt = try container.decodeIfPresent(IntentTemporalValue.self, forKey: .dueAt)
        eventAt = try container.decodeIfPresent(IntentTemporalValue.self, forKey: .eventAt)
        followUpAt = try container.decodeIfPresent(IntentTemporalValue.self, forKey: .followUpAt)
        unresolvedTimeText = try container.decodeIfPresent(String.self, forKey: .unresolvedTimeText)
        sourceText = try container.decode(String.self, forKey: .sourceText)
        sourceApplicationName = try container.decodeIfPresent(String.self, forKey: .sourceApplicationName)
        sourceApplicationBundleIdentifier = try container.decodeIfPresent(String.self, forKey: .sourceApplicationBundleIdentifier)
        parser = try container.decode(String.self, forKey: .parser)
        parserConfidence = try container.decodeIfPresent(Double.self, forKey: .parserConfidence)
        diagnostics = try container.decodeIfPresent(IntentParserDiagnostics.self, forKey: .diagnostics)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}
