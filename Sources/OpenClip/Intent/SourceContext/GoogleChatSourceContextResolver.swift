import AppKit
import Core
@_exported import OpenSelection

/// Reads only the selected message's author semantics and the enclosing Google Chat URL/title.
/// Space titles are never participants. Adjacent replies are not read to guess a recipient.
enum GoogleChatSourceContextResolver {
    @MainActor static func resolve(_ selection: SelectionContext) -> IntentSourceContext? {
        guard let pid = selection.sourceApp.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        guard let window = SourceAX.element(app, kAXFocusedWindowAttribute) else { return nil }
        let title = SourceAX.string(window, kAXTitleAttribute) ?? ""
        guard title.contains("Google Chat") || selection.sourceApp.bundleIdentifier?.contains("pommaclcbfghclhalboakcipcmmndhcj") == true else { return nil }
        var context = IntentSourceContext(applicationName: "Google Chat", bundleIdentifier: selection.sourceApp.bundleIdentifier, selectedText: selection.text)
        var current = SourceAX.hitSelection(selection, app: app) ?? SourceAX.element(app, kAXFocusedUIElementAttribute)
        let fragments = selection.text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.count >= 4 }
        // Chrome's PWA adds many empty layout ancestors. This walks only the selected
        // element's parent chain, never the conversation's message collection.
        for _ in 0..<40 {
            guard let element = current else { break }
            let role = SourceAX.string(element, kAXRoleAttribute)
            if role == "AXWebArea" {
                if context.conversationTitle == nil,
                   let pageTitle = nonempty([SourceAX.string(element, kAXTitleAttribute)]),
                   pageTitle.hasSuffix(" - Chat") {
                    context.conversationTitle = String(pageTitle.dropLast(" - Chat".count))
                }
                if let url = AXElementInspector.read(element, kAXURLAttribute) as? URL,
                   url.host == "chat.google.com", !url.path.contains("/topic/") {
                    context.sourceURL = url.absoluteString
                }
                break
            }
            if context.direction == .unknown, !fragments.isEmpty {
                let label = nonempty([SourceAX.string(element, kAXDescriptionAttribute), SourceAX.string(element, kAXTitleAttribute)]) ?? ""
                if let evidence = fragments.map({ outgoingEvidence(label: label, selectedFragment: $0) }).first(where: \.outgoing) {
                    context.direction = .outgoing
                    context.conversationTitle = evidence.spaceTitle
                }
                // Google Chat places an explicit author heading inside the message row.
                let children = SourceAX.children(element)
                let headings = children.flatMap { child in
                    SourceAX.string(child, kAXRoleAttribute) == "AXHeading" ? [child] : SourceAX.children(child).filter { SourceAX.string($0, kAXRoleAttribute) == "AXHeading" }
                }
                if fragments.contains(where: { label.contains($0) }), let heading = headings.first {
                    let author = nonempty([SourceAX.string(heading, kAXTitleAttribute), SourceAX.string(heading, kAXDescriptionAttribute)]
                        + SourceAX.children(heading).map { SourceAX.string($0, kAXValueAttribute) })
                    if author == "You" { context.direction = .outgoing }
                    else if let author = IntentGroundingValidator.personValue(author), label.hasPrefix(author + " ") {
                        context.direction = .incoming
                        context.sender = author
                    }
                }
            }
            current = SourceAX.element(element, kAXParentAttribute)
        }
        if context.conversationTitle == nil, !title.isEmpty {
            context.conversationTitle = title.replacingOccurrences(of: "Google Chat - ", with: "")
                .replacingOccurrences(of: " - Chat", with: "")
        }
        // Google Chat's URL alone does not distinguish group DMs from 1:1s. Keep participant nil.
        IntentSourceContextLog.debug("GOOGLE_CHAT direction=\(context.direction.rawValue) conversationTitle=\(context.conversationTitle ?? "nil") sender=\(context.sender ?? "nil")")
        return context
    }

    static func nonempty(_ values: [String?]) -> String? {
        values.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
    }

    /// AX author metadata before the selected body, not a guess from the body's wording.
    /// Search navigation wraps a space message as "<space> Space You: <body>".
    static func outgoingEvidence(label: String, selectedFragment: String) -> (outgoing: Bool, spaceTitle: String?) {
        guard selectedFragment.count >= 4, let range = label.range(of: selectedFragment) else { return (false, nil) }
        let prefix = String(label[..<range.lowerBound])
        if prefix == "You " { return (true, nil) }
        let marker = " Space You: "
        if prefix.hasSuffix(marker), let space = nonempty([String(prefix.dropLast(marker.count))]) {
            return (true, space)
        }
        return (false, nil)
    }
}
