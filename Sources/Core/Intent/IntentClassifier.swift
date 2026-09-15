// IntentClassifier.swift
// Core
//
// Deterministic mapping from a (grounded) IntentUnderstanding to IntentOS's final taxonomy.
// A provider (Gemini, Needle, ...) proposes understanding; it never proposes the final type
// directly — IntentOS decides. Returns nil for NO_INTENT (never a case of IntentType itself).
import Foundation

public enum IntentClassifier {
    public static func classify(_ understanding: IntentUnderstanding) -> IntentType? {
        guard understanding.hasTrackableIntent else { return nil }

        // False negatives are safer than hallucinated obligations: a negated instruction never
        // becomes a positive ACTION, and completed/past work is never re-tracked.
        if understanding.polarity == .negative { return nil }
        if understanding.temporalState == .past { return nil }

        if understanding.speechAct == .reminder { return .remember }

        switch understanding.speechAct {
        case .commitment:
            return classifyCommitment(understanding)
        case .request, .instruction:
            return classifyRequest(understanding)
        case .reminder:
            return .remember
        case .statement, .question, .unknown, .none:
            return classifyAmbiguous(understanding)
        }
    }

    /// "I'll call Arun tomorrow." (self-owned future commitment) vs.
    /// "Arun will send me the roadmap tomorrow." (third-party commitment; never a self-owned
    /// ACTION — at most WAITING when the user is clearly the counterpart).
    private static func classifyCommitment(_ u: IntentUnderstanding) -> IntentType? {
        if u.owner == .selfOwner || u.actor == .selfActor {
            return .action
        }
        if u.owner == .other || u.actor == .other {
            if u.waitingFor != nil || u.responseExpected == true {
                return .waiting
            }
            return nil
        }
        return nil
    }

    /// "Please review this Figma..." (incoming — someone else is asking the user) vs.
    /// "Can we have a session at 5pm?" (outgoing — the user is asking someone else).
    private static func classifyRequest(_ u: IntentUnderstanding) -> IntentType? {
        switch u.direction {
        case .incoming:
            return .action
        case .outgoing:
            // The outstanding request belongs to someone else even when a space does not
            // identify its recipient. Unknown person must not change ownership semantics.
            return .waiting
        case .selfDirected, .unknown, .none:
            if u.owner == .selfOwner { return .action }
            return u.waitingFor != nil ? .waiting : .request
        }
    }

    /// A bare statement/question with no explicit speech act still tracks as WAITING when the
    /// understanding clearly ties an outstanding response back to the user (e.g. "I sent Ravi the
    /// proposal and asked him to approve it."). Otherwise it's informational: NO_INTENT.
    private static func classifyAmbiguous(_ u: IntentUnderstanding) -> IntentType? {
        if u.waitingFor != nil || (u.commitmentStrength == .committed && u.owner == .other) {
            return .waiting
        }
        return nil
    }
}
