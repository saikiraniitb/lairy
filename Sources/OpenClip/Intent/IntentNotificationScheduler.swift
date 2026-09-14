// IntentNotificationScheduler.swift
// OpenClip
//
// Thin system adapter over UNUserNotificationCenter. All scheduling *decisions* (whether/when/
// what) live in the pure, unit-tested `IntentReminderPlanner` (Core) — this file only ever asks
// "what does the planner say" and executes it. Views never call UNUserNotificationCenter directly;
// they express intent (track / edit / mark done / delete) through IntentCaptureCoordinator and
// IntentInboxStore, which call this service.
import Foundation
import UserNotifications
import Core

public protocol IntentNotificationScheduling: Sendable {
    /// Cancels any existing reminder for this intent, then schedules a new one if the planner
    /// says one is due — replace semantics, so callers never have to cancel first themselves.
    func scheduleReminder(for intent: CapturedIntent) async
    func cancelReminder(for intentID: UUID) async
}

/// Requests notification authorization lazily, the first time a reminder is actually needed
/// (never at app launch) — see `scheduleReminder`.
public actor UNUserNotificationIntentScheduler: IntentNotificationScheduling {
    public static let shared = UNUserNotificationIntentScheduler()

    private let center: UNUserNotificationCenter
    private var hasRequestedAuthorization = false

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func scheduleReminder(for intent: CapturedIntent) async {
        center.removePendingNotificationRequests(withIdentifiers: [intent.id.uuidString])

        guard let plan = IntentReminderPlanner.plan(for: intent), plan.fireDate > Date() else { return }

        await requestAuthorizationIfNeeded()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: plan.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: intent.id.uuidString, content: content, trigger: trigger)
        try? await center.add(request)
    }

    public func cancelReminder(for intentID: UUID) async {
        center.removePendingNotificationRequests(withIdentifiers: [intentID.uuidString])
    }

    private func requestAuthorizationIfNeeded() async {
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }
}
