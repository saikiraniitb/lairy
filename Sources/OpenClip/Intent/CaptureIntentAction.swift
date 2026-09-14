import Foundation
import Core

public struct CaptureIntentAction: Action, Sendable {
    public let id = "builtin.captureIntent"
    public let title = String(localized: "Capture Intent")
    public let icon: ActionIcon = .symbol("scope")
    public let chrome = ActionChrome(
        requiresLiveSelection: true,
        showsLoading: true,
        loadingMessage: String(localized: "Understanding intent locally…")
    )

    private let coordinator: IntentCaptureCoordinator

    @MainActor
    public init(coordinator: IntentCaptureCoordinator = .shared) {
        self.coordinator = coordinator
    }

    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        !context.selection.isClipboardFallback
            && !context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        guard isEnabled(for: context) else {
            return .toast(StatusFeedback(message: String(localized: "Select text before capturing an intent."), style: .info))
        }
        return try await coordinator.capture(selection: context.selection)
    }
}

