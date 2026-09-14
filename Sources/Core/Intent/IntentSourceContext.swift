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
    /// The OTHER participant in a reliably-determined 1:1 conversation — set only when
    /// `conversationTitle` itself is shaped like a single person's name, never for a group chat.
    /// Safe to use as a grounding source and as the deterministic `waitingFor` for an outgoing
    /// request when the model didn't already name someone; never guessed for group chats, where
    /// this stays nil and exact sender attribution (or nothing) is required instead.
    public var oneOnOneParticipant: String?
    /// When the message was sent, per trusted UI metadata — source metadata only. Must never be
    /// used to populate a deadline/due/event/follow-up value; see `IntentGroundingValidator` and
    /// `GeminiIntentParser`'s prompt, which labels it explicitly as not a task deadline.
    public var timestampText: String?
    public var direction: MessageDirection

    public var selectedText: String

    public init(
        applicationName: String? = nil,
        bundleIdentifier: String? = nil,
        sender: String? = nil,
        conversationTitle: String? = nil,
        oneOnOneParticipant: String? = nil,
        timestampText: String? = nil,
        direction: MessageDirection = .unknown,
        selectedText: String
    ) {
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.sender = sender
        self.conversationTitle = conversationTitle
        self.oneOnOneParticipant = oneOnOneParticipant
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
