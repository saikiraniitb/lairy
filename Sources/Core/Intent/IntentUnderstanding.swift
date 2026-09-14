// IntentUnderstanding.swift
// Core
//
// The rich internal semantic model an intelligence provider (Gemini, Needle, ...) proposes for a
// piece of selected text, before IntentOS's deterministic grounding validator and classifier turn
// it into a trackable IntentDraft. Provider-neutral: no provider may be referenced from here.
import Foundation

public enum SpeechAct: String, Codable, CaseIterable, Sendable {
    case request
    case commitment
    case reminder
    case statement
    case instruction
    case question
    case unknown
}

/// Conversational direction of the captured utterance itself, not the app it was captured from.
public enum IntentDirection: String, Codable, CaseIterable, Sendable {
    /// Someone else is addressing the reader (presumed to be the user) — e.g. "Please review this."
    case incoming
    /// The user is addressing someone else — e.g. "Can you send me the report?"
    case outgoing
    case selfDirected = "self"
    case unknown
}

public enum ActorType: String, Codable, CaseIterable, Sendable {
    case selfActor = "self"
    case other
    case group
    case unknown
}

public enum IntentOwner: String, Codable, CaseIterable, Sendable {
    case selfOwner = "self"
    case other
    case shared
    case unknown
}

public enum TemporalState: String, Codable, CaseIterable, Sendable {
    case past
    case present
    case future
    case conditional
    case unknown
}

public enum Polarity: String, Codable, CaseIterable, Sendable {
    case positive
    case negative
    case unknown
}

public enum CommitmentStrength: String, Codable, CaseIterable, Sendable {
    case committed
    case requested
    case suggested
    case possible
    case unknown
}

/// Semantic understanding of a captured piece of text, as proposed by an intelligence provider.
/// This is internal intelligence/debug state — never a source of truth on its own. IntentOS's
/// `IntentGroundingValidator` and `IntentClassifier` turn it into an authoritative `IntentDraft`.
public struct IntentUnderstanding: Codable, Equatable, Sendable {
    public var hasTrackableIntent: Bool

    public var speechAct: SpeechAct?
    public var direction: IntentDirection?

    public var actor: ActorType?
    public var owner: IntentOwner?

    public var requestedAction: String?
    public var subject: String?
    public var target: String?

    public var requestedOutcome: String?

    public var temporalState: TemporalState?
    public var polarity: Polarity?
    public var commitmentStrength: CommitmentStrength?

    public var deadlineText: String?
    public var trigger: String?
    public var waitingFor: String?

    public var responseExpected: Bool?

    /// URL → label suggestions only. The URLs themselves are never trusted from this field —
    /// `IntentGroundingValidator` accepts a label only when its URL matches one already extracted
    /// deterministically from the source text by `IntentResourceExtractor`.
    public var resourceLabels: [IntentResourceLabelSuggestion]

    public var confidence: Double?

    public init(
        hasTrackableIntent: Bool,
        speechAct: SpeechAct? = nil,
        direction: IntentDirection? = nil,
        actor: ActorType? = nil,
        owner: IntentOwner? = nil,
        requestedAction: String? = nil,
        subject: String? = nil,
        target: String? = nil,
        requestedOutcome: String? = nil,
        temporalState: TemporalState? = nil,
        polarity: Polarity? = nil,
        commitmentStrength: CommitmentStrength? = nil,
        deadlineText: String? = nil,
        trigger: String? = nil,
        waitingFor: String? = nil,
        responseExpected: Bool? = nil,
        resourceLabels: [IntentResourceLabelSuggestion] = [],
        confidence: Double? = nil
    ) {
        self.hasTrackableIntent = hasTrackableIntent
        self.speechAct = speechAct
        self.direction = direction
        self.actor = actor
        self.owner = owner
        self.requestedAction = requestedAction
        self.subject = subject
        self.target = target
        self.requestedOutcome = requestedOutcome
        self.temporalState = temporalState
        self.polarity = polarity
        self.commitmentStrength = commitmentStrength
        self.deadlineText = deadlineText
        self.trigger = trigger
        self.waitingFor = waitingFor
        self.responseExpected = responseExpected
        self.resourceLabels = resourceLabels
        self.confidence = confidence
    }
}

/// A provider's suggested label for a URL. Never authoritative on the URL itself — see
/// `IntentUnderstanding.resourceLabels`.
public struct IntentResourceLabelSuggestion: Codable, Equatable, Sendable {
    public var url: String
    public var label: String

    public init(url: String, label: String) {
        self.url = url
        self.label = label
    }
}
