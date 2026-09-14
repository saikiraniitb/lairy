// AccessibilitySourceContextResolver.swift
// OpenClip
//
// Provider-neutral, app-agnostic resolver for `IntentSourceContext`. Never coupled to a specific
// app: it walks a SMALL, BOUNDED neighborhood around the currently focused UI element (the one the
// user just selected text in) looking for structural signals — nearby short static-text elements
// that look like a person's name or a timestamp, and the focused window's title as a conversation
// hint. It never reads anything outside that bounded neighborhood: no conversation history, no
// contact list, no hidden page text.
//
// This is deliberately a heuristic, not a per-app scraper: Google Chat (running as a web app in
// Chrome) is the first real target, reached generically through the same AX structure any
// message-like UI tends to expose (a short name/time label near the selected message body), not
// through any Chrome- or Google-specific string matching. If a future app's structure defeats
// these heuristics, the fix is a narrower, purpose-built `SourceContextResolving` conformer for
// that app — not broadening this one's reach.
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
        var context = IntentSourceContext(
            applicationName: selection.sourceApp.localizedName,
            bundleIdentifier: selection.sourceApp.bundleIdentifier,
            selectedText: selection.text
        )

        // V1 scope: only browsers (the first real case, Google Chat, is a web app). A native
        // app's AX structure varies too much to safely apply the same heuristics without its own
        // calibration — see the file header.
        guard let bundleID = selection.sourceApp.bundleIdentifier, Self.isSupportedBrowser(bundleID) else {
            return context
        }

        let target = AXElementInspector.inspect()
        guard let focusedElement = target.focusedElement else {
            IntentSourceContextLog.debug("no focused element; nothing to enrich")
            return context
        }

        context.conversationTitle = Self.windowTitle(for: target.focusedApp)
        IntentSourceContextLog.debug("startRole=\(target.role ?? "nil") conversationTitle=\(context.conversationTitle ?? "nil")")

        let found = Self.findMessageMetadata(
            near: focusedElement,
            maxAncestorDepth: maxAncestorDepth,
            maxDescendantDepth: maxDescendantDepth,
            maxChildrenPerLevel: maxChildrenPerLevel,
            excluding: selection.text
        )
        context.sender = found.sender
        context.timestampText = found.timestampText
        context.direction = found.direction

        return context
    }

    // MARK: - Bounded neighborhood walk

    private static func findMessageMetadata(
        near element: AXUIElement,
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

            IntentSourceContextLog.debug(
                "level=\(level) role=\(AXElementInspector.read(parent, kAXRoleAttribute) as? String ?? "nil") candidates=\(filtered.count) sender=\(sender ?? "nil") timestamp=\(timestamp ?? "nil")"
            )

            if sender != nil || timestamp != nil {
                let isSelf = sender?.caseInsensitiveCompare("you") == .orderedSame
                let direction: MessageDirection = isSelf ? .outgoing : (sender != nil ? .incoming : .unknown)
                return (isSelf ? nil : sender, timestamp, direction)
            }
            current = parent
        }
        return (nil, nil, .unknown)
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

    private static func windowTitle(for app: AXUIElement?) -> String? {
        guard let app,
              let windowValue = AXElementInspector.read(app, kAXFocusedWindowAttribute),
              CFGetTypeID(windowValue) == AXUIElementGetTypeID() else {
            return nil
        }
        // swiftlint:disable:next force_cast
        let window = windowValue as! AXUIElement
        return AXElementInspector.read(window, kAXTitleAttribute) as? String
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
