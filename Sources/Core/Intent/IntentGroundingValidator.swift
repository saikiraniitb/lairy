// IntentGroundingValidator.swift
// Core
//
// Gemini (or any other provider) proposes structured understanding; IntentOS is authoritative.
// This validator deterministically strips any factual claim that cannot be traced back to the
// selected source text, before that understanding is allowed to become a trackable IntentDraft.
//
// Grounding policy (deliberately asymmetric):
//   - deadlineText, trigger, waitingFor, target: these are meant to be short, quotable, factual
//     spans (a date/time phrase, a named person, a literal condition clause) — each must appear
//     verbatim (case-insensitive, whitespace-normalized) in the source text, or it is nulled.
//     deadlineText additionally requires independently-recognized temporal evidence to exist in
//     the source at all (see `TemporalPhraseExtractor`), so a claimed date can never survive on a
//     coincidental substring match alone.
//   - subject, requestedAction, requestedOutcome, summary: these are allowed to be the provider's
//     own concise paraphrase of the source (e.g. "Review the Figma flow and respond with feedback
///    or approval" is not a verbatim quote, but is exactly the desired output) — they are not
//     verbatim-grounded, since doing so would reject every legitimate summarization.
//   - Resource URLs are never taken from the provider at all: they come only from
//     `IntentResourceExtractor` running directly over the source text. A provider-suggested label
//     is kept only when it names a URL that was actually extracted.
import Foundation

public struct IntentGroundingRejection: Equatable, Sendable {
    public let field: String
    public let value: String
    public let reason: String

    public init(field: String, value: String, reason: String) {
        self.field = field
        self.value = value
        self.reason = reason
    }
}

public struct IntentGroundingResult: Sendable {
    /// The provider's understanding with every ungrounded claim replaced by nil.
    public let understanding: IntentUnderstanding
    /// Deterministically extracted from source text; never provider-supplied.
    public let resources: [IntentResource]
    /// What was stripped and why — surfaced in Debug mode as GROUNDING_REJECTED.
    public let rejections: [IntentGroundingRejection]

    public init(understanding: IntentUnderstanding, resources: [IntentResource], rejections: [IntentGroundingRejection]) {
        self.understanding = understanding
        self.resources = resources
        self.rejections = rejections
    }
}

public enum IntentGroundingValidator {
    public static func validate(_ proposed: IntentUnderstanding, sourceText: String) -> IntentGroundingResult {
        var understanding = proposed
        var rejections: [IntentGroundingRejection] = []

        if let deadline = normalized(understanding.deadlineText) {
            if TemporalPhraseExtractor.isGrounded(phrase: deadline, in: sourceText) {
                understanding.deadlineText = deadline
            } else {
                rejections.append(IntentGroundingRejection(
                    field: "deadlineText",
                    value: deadline,
                    reason: "not present in source"
                ))
                understanding.deadlineText = nil
            }
        }

        groundVerbatimField(\.trigger, on: &understanding, sourceText: sourceText, field: "trigger", rejections: &rejections)
        groundVerbatimField(\.waitingFor, on: &understanding, sourceText: sourceText, field: "waitingFor", rejections: &rejections)
        groundVerbatimField(\.target, on: &understanding, sourceText: sourceText, field: "target", rejections: &rejections)

        let extracted = IntentResourceExtractor.extractResources(from: sourceText)
        let extractedURLs = Set(extracted.map(\.url))
        let resources = extracted.map { resource -> IntentResource in
            var grounded = resource
            if let suggestion = understanding.resourceLabels.first(where: { $0.url == resource.url }) {
                grounded.label = suggestion.label
            }
            return grounded
        }
        for suggestion in understanding.resourceLabels where !extractedURLs.contains(suggestion.url) {
            rejections.append(IntentGroundingRejection(
                field: "resourceLabels",
                value: suggestion.url,
                reason: "URL not found in source; providers never supply resource URLs directly"
            ))
        }
        understanding.resourceLabels = []

        return IntentGroundingResult(understanding: understanding, resources: resources, rejections: rejections)
    }

    private static func groundVerbatimField(
        _ keyPath: WritableKeyPath<IntentUnderstanding, String?>,
        on understanding: inout IntentUnderstanding,
        sourceText: String,
        field: String,
        rejections: inout [IntentGroundingRejection]
    ) {
        guard let value = normalized(understanding[keyPath: keyPath]) else {
            understanding[keyPath: keyPath] = nil
            return
        }
        if TextGrounding.containsVerbatim(value, in: sourceText) {
            understanding[keyPath: keyPath] = value
        } else {
            rejections.append(IntentGroundingRejection(field: field, value: value, reason: "not present in source"))
            understanding[keyPath: keyPath] = nil
        }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
