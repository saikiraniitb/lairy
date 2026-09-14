// IntentTemporalValue.swift
// Core
//
// A resolved date (optionally with a time-of-day) attached to an intent, plus where it came from.
// Not every intent has one "deadline" — see `IntentTemporalResolver` for how `dueAt`/`eventAt`/
// `followUpAt` are told apart.
import Foundation

/// Where a temporal value came from. The grounding validator only ever touches `.modelGrounded`
/// values at parse time — a `.userSelected` value (the user explicitly picked it in the When
/// control) must never be stripped by grounding, since the user themselves is the trust boundary.
public enum TemporalProvenance: String, Codable, Equatable, Sendable {
    case modelGrounded
    case userSelected
}

public struct IntentTemporalValue: Codable, Equatable, Sendable {
    public var date: Date
    /// False when only a calendar date is meaningful (e.g. "Friday"); true when a specific
    /// time-of-day is part of the value (e.g. "Friday at 5pm").
    public var hasTime: Bool
    /// The original phrase this was derived from, when grounded from model+source-text evidence.
    /// Nil for a user-selected value.
    public var sourceText: String?
    public var provenance: TemporalProvenance

    public init(date: Date, hasTime: Bool, sourceText: String? = nil, provenance: TemporalProvenance) {
        self.date = date
        self.hasTime = hasTime
        self.sourceText = sourceText
        self.provenance = provenance
    }
}
