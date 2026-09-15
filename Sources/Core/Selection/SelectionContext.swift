// SelectionContext.swift
// OpenClip
//
// Represents the full context of a text selection event, including selected text, source application, screen coordinates, and app policy.
import Foundation
import CoreGraphics

public struct SelectionContext: Sendable {
    public let captureID: UUID
    public let text: String
    public let sourceApp: AppIdentity
    public let cursorPosition: CGPoint
    public let mouseDownLocation: CGPoint?
    public let selectionBounds: CGRect?
    public let timestamp: Date
    public let appPolicy: AppPolicyContext
    /// True when the text came from the clipboard (shortcut triggered with no selection), not from a live selection.
    public let isClipboardFallback: Bool
    public let html: String?
    public let rtf: String?
    /// Source context resolved EARLY, while `sourceApp` was still frontmost — see
    /// `SourceContextSnapshot`'s file header. `IntentCaptureCoordinator` prefers this (once
    /// `SourceContextSnapshotValidator` confirms it still matches this exact selection) over
    /// re-resolving after the popup has taken focus. Nil for a selection no such snapshot was
    /// resolved for; never required.
    public let sourceContextSnapshot: SourceContextSnapshot?

    public init(
        text: String,
        sourceApp: AppIdentity = AppIdentity(bundleIdentifier: "com.openclip.unknown", localizedName: "Unknown"),
        cursorPosition: CGPoint = .zero,
        mouseDownLocation: CGPoint? = nil,
        selectionBounds: CGRect? = nil,
        timestamp: Date = Date(),
        appPolicy: AppPolicyContext = .default,
        isClipboardFallback: Bool = false,
        html: String? = nil,
        rtf: String? = nil,
        sourceContextSnapshot: SourceContextSnapshot? = nil,
        captureID: UUID = UUID()
    ) {
        self.captureID = captureID
        self.text = text
        self.sourceApp = sourceApp
        self.cursorPosition = cursorPosition
        self.mouseDownLocation = mouseDownLocation
        self.selectionBounds = selectionBounds
        self.timestamp = timestamp
        self.appPolicy = appPolicy
        self.isClipboardFallback = isClipboardFallback
        self.html = html
        self.rtf = rtf
        self.sourceContextSnapshot = sourceContextSnapshot
    }

    /// Returns a copy carrying the given early-resolved snapshot — used once, right after
    /// resolution completes, by whatever delivers the selection (still while the source app is
    /// frontmost). Every other field is unchanged.
    public func withSourceContextSnapshot(_ snapshot: SourceContextSnapshot?) -> SelectionContext {
        SelectionContext(
            text: text,
            sourceApp: sourceApp,
            cursorPosition: cursorPosition,
            mouseDownLocation: mouseDownLocation,
            selectionBounds: selectionBounds,
            timestamp: timestamp,
            appPolicy: appPolicy,
            isClipboardFallback: isClipboardFallback,
            html: html,
            rtf: rtf,
            sourceContextSnapshot: snapshot,
            captureID: captureID
        )
    }
}
