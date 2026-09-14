// IntentSourceContext.swift
// Core
//
// Trusted message/conversation metadata for the explicitly selected text, resolved
// deterministically from application/accessibility structure — never inferred by a language
// model. See `SourceContextResolving`.
import Foundation

/// Direction of the selected message relative to the user, established only when the
/// application/accessibility structure exposes it explicitly. `.unknown` — never a guess from
/// wording — is the safe default whenever it cannot be determined this way.
public enum MessageDirection: String, Codable, CaseIterable, Sendable {
    case incoming
    case outgoing
    case unknown

    /// Maps to the semantic-understanding schema's direction — `nil` for `.unknown`, since an
    /// absence of trusted signal should never override the provider's own (still-fallible) guess.
    public var asIntentDirection: IntentDirection? {
        switch self {
        case .incoming: return .incoming
        case .outgoing: return .outgoing
        case .unknown: return nil
        }
    }
}

/// Metadata attached to the ONE message the user explicitly selected — never the surrounding
/// conversation. Every field here must be either trusted (resolved deterministically from
/// app/accessibility structure) or nil; never a guess.
public struct IntentSourceContext: Sendable, Equatable {
    public var applicationName: String?
    public var bundleIdentifier: String?

    /// The message's author, when reliably resolved from trusted UI metadata. Never derived from
    /// the selected text itself (e.g. an @mention inside the message body is not a sender).
    public var sender: String?
    public var conversationTitle: String?
    public var timestampText: String?
    public var direction: MessageDirection

    public var selectedText: String

    public init(
        applicationName: String? = nil,
        bundleIdentifier: String? = nil,
        sender: String? = nil,
        conversationTitle: String? = nil,
        timestampText: String? = nil,
        direction: MessageDirection = .unknown,
        selectedText: String
    ) {
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.sender = sender
        self.conversationTitle = conversationTitle
        self.timestampText = timestampText
        self.direction = direction
        self.selectedText = selectedText
    }
}

/// Provider-neutral abstraction for resolving `IntentSourceContext`. Nothing in this protocol (or
/// its callers) may reference a specific application by name — app-specific tuning lives entirely
/// inside a conformer's implementation.
public protocol SourceContextResolving: Sendable {
    func resolve(from selection: SelectionContext) async -> IntentSourceContext
}

/// A resolver that never enriches anything — every field beyond the app identity/selected text
/// stays nil/unknown. The safe default, and a clean seam for tests.
public struct NullSourceContextResolver: SourceContextResolving {
    public init() {}
    public func resolve(from selection: SelectionContext) async -> IntentSourceContext {
        IntentSourceContext(
            applicationName: selection.sourceApp.localizedName,
            bundleIdentifier: selection.sourceApp.bundleIdentifier,
            selectedText: selection.text
        )
    }
}
