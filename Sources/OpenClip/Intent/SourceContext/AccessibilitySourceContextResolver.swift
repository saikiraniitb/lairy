// AccessibilitySourceContextResolver.swift
// OpenClip
//
// Conservative app-agnostic fallback. Identity, message authorship and bubble alignment require
// source-specific structural validation, supplied by the calibrated adapters in the composite
// resolver. The historical candidate helpers remain for regression/research only; they are not
// trusted runtime enrichment. In particular a name-shaped group title is not a participant.
import AppKit
import Core
@_exported import OpenSelection

public struct AccessibilitySourceContextResolver: SourceContextResolving {
    /// How many ancestor levels to walk up from the focused element, stopping at the first level
    /// whose descendants yield a confident candidate. Bounded so this can never approach scanning
    /// a whole conversation.
    private let maxAncestorDepth: Int
    /// How many levels deep to search each ancestor's descendants for static-text candidates.
    private let maxDescendantDepth: Int
    /// How many children to fan out into at each descendant level (bounds pathological trees).
    private let maxChildrenPerLevel: Int

    public init(maxAncestorDepth: Int = 6, maxDescendantDepth: Int = 3, maxChildrenPerLevel: Int = 24) {
        self.maxAncestorDepth = maxAncestorDepth
        self.maxDescendantDepth = maxDescendantDepth
        self.maxChildrenPerLevel = maxChildrenPerLevel
    }

    public func resolve(from selection: SelectionContext) async -> IntentSourceContext {
        // No universal AX convention establishes a chat author, a 1:1 participant, or
        // even that a left/right aligned element is a message. Keep generic capture
        // useful without asserting those identities. Calibrated source adapters enrich
        // this context; legacy candidate helpers below are not production evidence.
        // In particular, never inspect the *currently* focused app during late fallback.
        IntentSourceContext(
            applicationName: selection.sourceApp.localizedName,
            bundleIdentifier: selection.sourceApp.bundleIdentifier,
            selectedText: selection.text
        )
    }

    // MARK: - Bounded neighborhood walk

    private static func findMessageMetadata(
        near element: AXUIElement,
        windowFrame: CGRect?,
        maxAncestorDepth: Int,
        maxDescendantDepth: Int,
        maxChildrenPerLevel: Int,
        excluding selectedText: String
    ) -> (sender: String?, timestampText: String?, direction: MessageDirection) {
        var current = element
        for level in 0..<maxAncestorDepth {
            guard let parentValue = AXElementInspector.read(current, kAXParentAttribute),
                  CFGetTypeID(parentValue) == AXUIElementGetTypeID() else {
                break
            }
            // swiftlint:disable:next force_cast
            let parent = parentValue as! AXUIElement

            var candidates: [String] = []
            collectStaticTexts(in: parent, remainingDepth: maxDescendantDepth, maxChildrenPerLevel: maxChildrenPerLevel, into: &candidates)
            let filtered = candidates
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0 != selectedText && !selectedText.contains($0) }

            var sender: String?
            var timestamp: String?
            for text in filtered {
                if timestamp == nil, looksLikeTimestamp(text) { timestamp = text }
                else if sender == nil, looksLikePersonName(text) { sender = text }
            }

            let positionHint: MessageDirection? = elementFrame(parent).flatMap { frame in
                windowFrame.map { directionFromPosition(messageFrame: frame, windowFrame: $0) }
            }
            IntentSourceContextLog.debug(
                "level=\(level) role=\(AXElementInspector.read(parent, kAXRoleAttribute) as? String ?? "nil") candidates=\(filtered.count) sender=\(sender ?? "nil") timestamp=\(timestamp ?? "nil") positionHint=\(positionHint?.rawValue ?? "nil")"
            )

            if sender != nil || timestamp != nil {
                let isSelf = sender?.caseInsensitiveCompare("you") == .orderedSame
                let direction: MessageDirection
                if isSelf {
                    direction = .outgoing
                } else if sender != nil {
                    direction = .incoming
                } else {
                    // A timestamp was found but no name label — own messages in chat UIs
                    // conventionally carry no name badge at all, so fall back to the message
                    // bubble's on-screen position, never to reading the message's wording.
                    direction = positionHint ?? .unknown
                }
                return (isSelf ? nil : sender, timestamp, direction)
            }
            current = parent
        }

        // Nothing textual found anywhere in the bounded walk — last resort is the ORIGINAL
        // element's own position, still purely structural.
        let fallbackDirection = elementFrame(element).flatMap { messageFrame in
            windowFrame.map { directionFromPosition(messageFrame: messageFrame, windowFrame: $0) }
        } ?? .unknown
        IntentSourceContextLog.debug("no textual candidate found in \(maxAncestorDepth) levels; positionFallback=\(fallbackDirection.rawValue)")
        return (nil, nil, fallbackDirection)
    }

    private static func collectStaticTexts(
        in element: AXUIElement,
        remainingDepth: Int,
        maxChildrenPerLevel: Int,
        into accumulated: inout [String]
    ) {
        guard remainingDepth >= 0 else { return }
        if (AXElementInspector.read(element, kAXRoleAttribute) as? String) == "AXStaticText",
           let value = AXElementInspector.read(element, kAXValueAttribute) as? String {
            accumulated.append(value)
        }
        guard remainingDepth > 0,
              let children = AXElementInspector.read(element, kAXChildrenAttribute) as? [AXUIElement] else {
            return
        }
        for child in children.prefix(maxChildrenPerLevel) {
            collectStaticTexts(in: child, remainingDepth: remainingDepth - 1, maxChildrenPerLevel: maxChildrenPerLevel, into: &accumulated)
        }
    }

    private static func focusedWindow(for app: AXUIElement?) -> AXUIElement? {
        guard let app,
              let windowValue = AXElementInspector.read(app, kAXFocusedWindowAttribute),
              CFGetTypeID(windowValue) == AXUIElementGetTypeID() else {
            return nil
        }
        // swiftlint:disable:next force_cast
        return (windowValue as! AXUIElement)
    }

    private static func elementFrame(_ element: AXUIElement) -> CGRect? {
        guard let positionValue = AXElementInspector.read(element, kAXPositionAttribute),
              CFGetTypeID(positionValue) == AXValueGetTypeID() else {
            return nil
        }
        var point = CGPoint.zero
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &point) else { return nil }

        guard let sizeValue = AXElementInspector.read(element, kAXSizeAttribute),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }
        var size = CGSize.zero
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }

        return CGRect(origin: point, size: size)
    }

    // MARK: - Candidate heuristics (fail closed: never guess)

    static func looksLikePersonName(_ text: String) -> Bool {
        if text.caseInsensitiveCompare("you") == .orderedSame { return true }
        guard text.count >= 4, text.count <= 60, !text.contains(where: \.isNumber) else { return false }
        let words = text.split(separator: " ")
        guard (2...5).contains(words.count) else { return false }
        return words.allSatisfy { word in
            guard let first = word.first, first.isUppercase else { return false }
            return word.dropFirst().allSatisfy { $0.isLowercase || $0 == "'" || $0 == "-" || $0 == "." }
        }
    }

    static func looksLikeTimestamp(_ text: String) -> Bool {
        guard text.count <= 40 else { return false }
        return !TemporalPhraseExtractor.extractPhrases(from: text).isEmpty
    }

    static func isSupportedBrowser(_ bundleID: String) -> Bool {
        DefaultAppRules.matchesAny(
            DefaultAppRules.safariGroup + DefaultAppRules.chromiumGroup + DefaultAppRules.firefoxGroup + DefaultAppRules.arcGroup,
            bundleID: bundleID
        )
    }

    /// Pure, directly-testable structural signal: which side of the window a message bubble sits
    /// on. A chat UI convention (not universal), used only as a fallback when no explicit
    /// name/"You" label was found — never derived from the message's wording. `.unknown` inside a
    /// central margin band avoids false signals from full-width rows (e.g. system messages).
    static func directionFromPosition(messageFrame: CGRect, windowFrame: CGRect, centerMarginFraction: CGFloat = 0.08) -> MessageDirection {
        guard windowFrame.width > 0 else { return .unknown }
        let margin = windowFrame.width * centerMarginFraction
        let windowMidX = windowFrame.midX
        let messageMidX = messageFrame.midX
        if messageMidX > windowMidX + margin { return .outgoing }
        if messageMidX < windowMidX - margin { return .incoming }
        return .unknown
    }
}

/// DEBUG-only, dedicated log channel so a developer can see exactly which AX roles/attributes
/// produced (or failed to produce) source-context metadata, without wiring a new setting.
enum IntentSourceContextLog {
    static func debug(_ message: @autoclosure () -> String) {
        #if DEBUG
        Log.selection.debug("INTENTOS_SOURCE_CONTEXT \(message(), privacy: .public)")
        #endif
    }
}
