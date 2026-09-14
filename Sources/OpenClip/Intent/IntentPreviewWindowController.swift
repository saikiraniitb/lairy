import AppKit
import SwiftUI
import Core

@MainActor
public final class IntentPreviewWindowController {
    private var panel: PopupPanel?
    private var model: IntentPreviewModel?

    public init() {}

    public func show(
        draft: IntentDraft,
        isUncertain: Bool,
        cloudEnabled: Bool,
        anchor: CGPoint,
        onTrack: @escaping @MainActor (IntentDraft, Bool) async throws -> Void,
        onIgnore: @escaping @MainActor (IntentDraft) async -> Void,
        onCloud: @escaping @MainActor (IntentDraft) async -> Void
    ) {
        dismiss()
        let model = IntentPreviewModel(
            draft: draft,
            isUncertain: isUncertain,
            cloudEnabled: cloudEnabled,
            onTrack: onTrack,
            onIgnore: onIgnore,
            onCloud: onCloud,
            onDismiss: { [weak self] in self?.dismiss() }
        )
        self.model = model

        let view = IntentPreviewView(model: model)
        let hosting = NSHostingView(rootView: view)
        let panel = PopupPanel()
        panel.allowsKey = true
        panel.level = .floating
        panel.heightCap = 720
        panel.contentView = hosting
        let size = NSSize(width: 440, height: isUncertain ? 420 : 470)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let origin = NSPoint(
            x: min(max(anchor.x - size.width / 2, visible.minX + 12), visible.maxX - size.width - 12),
            y: min(max(anchor.y - size.height - 18, visible.minY + 12), visible.maxY - size.height - 12)
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.makeKey()
        self.panel = panel
    }

    public func showMessage(_ message: String) {
        model?.message = message
        model?.isBusy = false
    }

    public func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        model = nil
    }
}

@MainActor
public final class IntentPreviewModel: ObservableObject {
    @Published public var draft: IntentDraft
    @Published public var isEditing: Bool
    @Published public var isBusy = false
    @Published public var message: String?
    public let isUncertain: Bool
    public let cloudEnabled: Bool

    private let onTrack: @MainActor (IntentDraft, Bool) async throws -> Void
    private let onIgnore: @MainActor (IntentDraft) async -> Void
    private let onCloud: @MainActor (IntentDraft) async -> Void
    private let onDismiss: @MainActor () -> Void
    private var wasEdited = false

    public init(
        draft: IntentDraft,
        isUncertain: Bool,
        cloudEnabled: Bool,
        onTrack: @escaping @MainActor (IntentDraft, Bool) async throws -> Void,
        onIgnore: @escaping @MainActor (IntentDraft) async -> Void,
        onCloud: @escaping @MainActor (IntentDraft) async -> Void,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        self.draft = draft
        self.isUncertain = isUncertain
        self.cloudEnabled = cloudEnabled
        self.isEditing = isUncertain
        self.onTrack = onTrack
        self.onIgnore = onIgnore
        self.onCloud = onCloud
        self.onDismiss = onDismiss
    }

    public func markEdited() {
        wasEdited = true
    }

    public func track() {
        guard !isBusy, !draft.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isBusy = true
        Task { @MainActor in
            do {
                try await onTrack(draft, wasEdited)
                onDismiss()
            } catch {
                message = error.localizedDescription
                isBusy = false
            }
        }
    }

    public func ignore() {
        guard !isBusy else { return }
        Task { @MainActor in
            await onIgnore(draft)
            onDismiss()
        }
    }

    public func tryCloud() {
        guard !isBusy else { return }
        isBusy = true
        message = cloudEnabled ? String(localized: "Sending selected text to the configured cloud provider…") : nil
        Task { @MainActor in await onCloud(draft) }
    }

    public func dismiss() { onDismiss() }
}
