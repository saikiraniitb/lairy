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
        center.removeDeliveredNotifications(withIdentifiers: [intent.id.uuidString])

        guard IntentReminderPlanner.plan(for: intent) != nil else {
            await logCancellation(for: intent.id)
            return
        }

        await requestAuthorizationIfNeeded()
        let settings = await center.notificationSettings()
        Log.intent.debug("notification intentID=\(intent.id.uuidString, privacy: .public) authorization=\(settings.authorizationStatus.rawValue, privacy: .public)")
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        // Authorization can take longer than the near-future lead window. Recompute afterward.
        guard let plan = IntentReminderPlanner.plan(for: intent) else { return }

        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: plan.fireDate)
        let delay = plan.fireDate.timeIntervalSinceNow
        let trigger: UNNotificationTrigger = delay < 60
            ? UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false)
            : UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: intent.id.uuidString, content: content, trigger: trigger)
        do {
            try await center.add(request)
            let pending = await center.pendingNotificationRequests()
            Log.intent.debug("notification intentID=\(intent.id.uuidString, privacy: .public) scheduled=\(pending.contains { $0.identifier == intent.id.uuidString }, privacy: .public) fireDate=\(plan.fireDate.description, privacy: .public)")
        } catch {
            Log.intent.error("notification intentID=\(intent.id.uuidString, privacy: .public) scheduling failed: \(error.localizedDescription)")
        }
    }

    public func cancelReminder(for intentID: UUID) async {
        center.removePendingNotificationRequests(withIdentifiers: [intentID.uuidString])
        center.removeDeliveredNotifications(withIdentifiers: [intentID.uuidString])
        await logCancellation(for: intentID)
    }

    private func logCancellation(for intentID: UUID) async {
        let pending = await center.pendingNotificationRequests()
        Log.intent.debug("notification intentID=\(intentID.uuidString, privacy: .public) cancelled=\(!pending.contains { $0.identifier == intentID.uuidString }, privacy: .public)")
    }

    private func requestAuthorizationIfNeeded() async {
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }
}
