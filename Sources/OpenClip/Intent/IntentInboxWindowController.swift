import AppKit
import SwiftUI

@MainActor
public final class IntentInboxWindowController: NSObject, NSWindowDelegate {
    public static let shared = IntentInboxWindowController()
    private var window: NSWindow?

    public func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            Task { await IntentInboxStore.shared.reload() }
            return
        }

        let controller = NSHostingController(rootView: IntentInboxView())
        let window = NSWindow(contentViewController: controller)
        window.title = String(localized: "Intent Inbox")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 820, height: 560))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        Task {
            await IntentMetricsRecorder.shared.record(IntentMetricEvent(parser: "none", outcome: .inboxOpened))
            await IntentInboxStore.shared.reload()
        }
    }

    public func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
