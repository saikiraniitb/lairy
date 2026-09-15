import AppKit
import Core
@_exported import OpenSelection

/// WhatsApp metadata is read before the popup opens. Only the selected bubble and the
/// conversation navigation bar are inspected; message and sidebar lists are never scanned.
public struct WhatsAppSourceContextResolver: SourceContextResolving {
    public static let bundleIdentifier = "net.whatsapp.WhatsApp"

    public init(maxAncestorDepth: Int = 8, maxHeaderDepth: Int = 20, maxChildrenPerLevel: Int = 60) {}

    @MainActor public func resolve(from selection: SelectionContext) async -> IntentSourceContext {
        var context = IntentSourceContext(applicationName: selection.sourceApp.localizedName,
            bundleIdentifier: selection.sourceApp.bundleIdentifier, selectedText: selection.text)
        guard selection.sourceApp.bundleIdentifier == Self.bundleIdentifier,
              let pid = selection.sourceApp.processIdentifier else { return context }
        let app = AXUIElementCreateApplication(pid)
        guard let window = SourceAX.element(app, kAXFocusedWindowAttribute) else { return context }

        // Mouse-down stays inside the selected text even if the drag ends beyond the bubble.
        let selected = SourceAX.hitSelection(selection, app: app)
            ?? SourceAX.element(app, kAXFocusedUIElementAttribute)
        var current = selected
        for _ in 0..<8 {
            guard let element = current else { break }
            let identifier = SourceAX.string(element, kAXIdentifierAttribute)
            if identifier == "ChatMessagesTableView" || identifier == "ChatListView_TableView" { break }
            if identifier == "WAMessageBubbleTableViewCell" {
                let description = SourceAX.string(element, kAXDescriptionAttribute)
                    ?? SourceAX.string(element, kAXValueAttribute) ?? ""
                let evidence = Self.messageEvidence(description, selectedText: selection.text)
                context.direction = evidence.direction
                context.sender = evidence.sender
                context.timestampText = evidence.timestamp
                break
            }
            current = SourceAX.element(element, kAXParentAttribute)
        }

        // Known navigation identifiers, never "the first name-shaped text" in the window.
        let navigation = SourceAX.navigationElements(window, excluding: [
            "ChatMessagesTableView", "ChatListView_TableView", "ChatListSearchView_ChatResult"
        ])
        if let header = navigation.first(where: { SourceAX.string($0, kAXIdentifierAttribute) == "NavigationBar_HeaderViewButton" }) {
            let title = SourceAX.string(header, kAXDescriptionAttribute).map(Self.clean)
            context.conversationTitle = title
            if let title, let parent = SourceAX.element(header, kAXParentAttribute) {
                let labels = SourceAX.children(parent).compactMap { SourceAX.string($0, kAXDescriptionAttribute).map(Self.clean) }
                // The native 1:1 bar exposes separate voice and video actions for this contact.
                // Groups expose a call dropdown instead. Name shape alone is not 1:1 evidence.
                if labels.contains("Start voice call with " + title),
                   labels.contains("Start video call with " + title) {
                    context.oneOnOneParticipant = IntentGroundingValidator.personValue(title)
                }
            }
        }
        IntentSourceContextLog.debug("WHATSAPP direction=\(context.direction.rawValue) conversationTitle=\(context.conversationTitle ?? "nil") oneOnOneParticipant=\(context.oneOnOneParticipant ?? "nil")")
        return context
    }

    static func messageEvidence(_ description: String, selectedText: String) -> (direction: MessageDirection, sender: String?, timestamp: String?) {
        let text = clean(description)
        let selected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty, let selectedRange = text.range(of: selected) else { return (.unknown, nil, nil) }
        // Provenance must be outside the exact selected body, preventing quoted "Sent to" or
        // "Received from" text inside a message from becoming trusted sender evidence.
        let prefix = String(text[..<selectedRange.lowerBound])
        let suffix = String(text[selectedRange.upperBound...])
        let timestamp = suffix.range(of: #"\b\d{1,2}:\d{2}\s*[APap][Mm]\b"#, options: .regularExpression).map { String(suffix[$0]) }
        if prefix.hasPrefix("Your message,"), suffix.contains(", Sent to ") {
            return (.outgoing, nil, timestamp)
        }
        if let range = suffix.range(of: ", Received from ") {
            let name = suffix[range.upperBound...].split(separator: ",").first.map(String.init)
            return (.incoming, IntentGroundingValidator.personValue(name), timestamp)
        }
        if suffix.contains(", Received in ") { return (.incoming, nil, timestamp) }
        return (.unknown, nil, timestamp)
    }

    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{200e}", with: "").replacingOccurrences(of: "\u{200f}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func looksLikeContactName(_ text: String) -> Bool {
        guard let text = IntentGroundingValidator.personValue(text), (2...60).contains(text.count), !text.contains(where: \.isNumber) else { return false }
        return text.split(separator: " ").allSatisfy { $0.first?.isUppercase == true && $0.dropFirst().allSatisfy { $0.isLowercase || $0 == "'" || $0 == "-" } }
    }
}

/// Shared AX mechanics only. Application-specific trust decisions stay in their adapters.
enum SourceAX {
    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        AXElementInspector.read(element, attribute) as? String
    }
    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = AXElementInspector.read(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    static func children(_ element: AXUIElement) -> [AXUIElement] {
        AXElementInspector.read(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
    @MainActor static func hitSelection(_ selection: SelectionContext, app: AXUIElement) -> AXUIElement? {
        let anchor = selection.mouseDownLocation ?? selection.cursorPosition
        guard anchor != .zero else { return nil }
        let screenHeight = NSScreen.screens.first?.frame.maxY ?? 0
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(anchor.x), Float(screenHeight - anchor.y), &element) == .success else { return nil }
        return element
    }
    static func navigationElements(_ root: AXUIElement, excluding identifiers: Set<String>) -> [AXUIElement] {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var result: [AXUIElement] = []
        var index = 0
        while index < queue.count, index < 160 {
            let (element, depth) = queue[index]
            index += 1
            if identifiers.contains(string(element, kAXIdentifierAttribute) ?? "") { continue }
            result.append(element)
            guard depth < 12 else { continue }
            for child in children(element).prefix(24) { queue.append((child, depth + 1)) }
        }
        return result
    }
}
