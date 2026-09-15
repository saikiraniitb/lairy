// SourceContextSnapshot.swift
// Core
//
// An `IntentSourceContext` resolved EARLY — while the source app was still frontmost — and
// carried forward on `SelectionContext` so `IntentCaptureCoordinator` doesn't have to re-resolve
// it later, after OpenClip's own popup has taken focus (by which point some apps, e.g. WhatsApp,
// have already collapsed most of their accessibility tree and can no longer be queried reliably).
//
// This is deliberately TRANSIENT: it rides along with a single selection delivery only. Nothing
// here is persisted merely because text was selected — a snapshot is only ever written to disk as
// part of an actually-tracked `CapturedIntent`, same as late-resolved source context always was.
import Foundation

public struct SourceContextSnapshot: Sendable, Equatable {
    /// Correlates this snapshot's `stage=captured` and `stage=consumed` debug log lines.
    public let captureID: UUID
    /// The resolved context itself — same trust rules as always (see `IntentSourceContext`).
    public let sourceContext: IntentSourceContext
    /// The exact selected text this snapshot was resolved for — required to match the selection
    /// it's later paired with; see `SourceContextSnapshotValidator`.
    public let selectedText: String
    public let bundleIdentifier: String?
    public let sourcePID: pid_t?
    /// Best-effort description of the source window (e.g. its AX title) — descriptive metadata
    /// only, not a cryptographically stable identity; never a substitute for the pid/bundle check.
    public let windowIdentifier: String?
    public let capturedAt: Date

    public init(
        captureID: UUID = UUID(),
        sourceContext: IntentSourceContext,
        selectedText: String,
        bundleIdentifier: String?,
        sourcePID: pid_t? = nil,
        windowIdentifier: String? = nil,
        capturedAt: Date = Date()
    ) {
        self.captureID = captureID
        self.sourceContext = sourceContext
        self.selectedText = selectedText
        self.bundleIdentifier = bundleIdentifier
        self.sourcePID = sourcePID
        self.windowIdentifier = windowIdentifier
        self.capturedAt = capturedAt
    }
}

/// Guards a `SourceContextSnapshot` against ever being consumed for a DIFFERENT selection than the
/// one it was resolved for — deliberately conservative (any mismatch or staleness rejects it
/// outright, falling back to late resolution) since a wrong trusted context is worse than none.
public enum SourceContextSnapshotValidator {
    public static func isValid(
        _ snapshot: SourceContextSnapshot,
        selectedText: String,
        bundleIdentifier: String?,
        sourcePID: pid_t?,
        now: Date,
        ttl: TimeInterval
    ) -> Bool {
        guard snapshot.selectedText == selectedText else { return false }
        guard snapshot.sourceContext.selectedText == selectedText else { return false }
        guard bundleIdentifier != nil || sourcePID != nil else { return false }
        guard snapshot.bundleIdentifier == bundleIdentifier else { return false }
        // Missing identity on only one side is also a mismatch. Both may be nil only when
        // the bundle identity is available (e.g. a test or clipboard construction path).
        guard snapshot.sourcePID == sourcePID else { return false }
        let age = now.timeIntervalSince(snapshot.capturedAt)
        guard age >= 0, age <= ttl else { return false }
        return true
    }
}
