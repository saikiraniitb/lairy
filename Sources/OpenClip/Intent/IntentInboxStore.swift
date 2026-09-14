import Foundation
import Core

/// Intent Inbox grouping — not the same axis as `IntentStatus`/`IntentType`. Mutually exclusive,
/// evaluated in this priority order so a cancelled item never leaks into another group, a
/// REMEMBER note always groups by content rather than by date, and TODAY/OPEN/LATER slice the
/// remaining open work only by whether (and when) it has a real, grounded deadline.
public enum IntentInboxGroup: String, CaseIterable, Sendable {
    case today = "TODAY"
    case open = "OPEN"
    case waiting = "WAITING"
    case later = "LATER"
    case remember = "REMEMBER"
    case done = "DONE"

    public var title: String { rawValue }

    public static func group(for intent: CapturedIntent, now: Date = Date()) -> IntentInboxGroup? {
        if intent.status == .cancelled { return nil }
        if intent.status == .done { return .done }
        if intent.type == .remember { return .remember }
        if intent.status == .waiting { return .waiting }
        guard let deadline = intent.deadline else { return .open }
        let calendar = Calendar.current
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return deadline < endOfToday ? .today : .later
    }
}

@MainActor
public final class IntentInboxStore: ObservableObject {
    public static let shared = IntentInboxStore(repository: FileIntentRepository.shared)

    @Published public private(set) var intents: [CapturedIntent] = []
    @Published public var selectedID: UUID?
    @Published public var errorMessage: String?
    private let repository: any IntentRepository
    private let metrics: IntentMetricsRecorder
    private let notificationScheduler: any IntentNotificationScheduling

    public init(
        repository: any IntentRepository,
        metrics: IntentMetricsRecorder = .shared,
        notificationScheduler: any IntentNotificationScheduling = UNUserNotificationIntentScheduler.shared
    ) {
        self.repository = repository
        self.metrics = metrics
        self.notificationScheduler = notificationScheduler
    }

    public var selectedIntent: CapturedIntent? {
        intents.first { $0.id == selectedID }
    }

    public func intents(with status: IntentStatus) -> [CapturedIntent] {
        intents.filter { $0.status == status }
    }

    public func intents(in group: IntentInboxGroup) -> [CapturedIntent] {
        intents.filter { IntentInboxGroup.group(for: $0) == group }
    }

    public func reload() async {
        do {
            intents = try await repository.fetchAll()
            if let selectedID, !intents.contains(where: { $0.id == selectedID }) {
                self.selectedID = nil
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func setStatus(_ status: IntentStatus, for id: UUID) {
        guard var intent = intents.first(where: { $0.id == id }) else { return }
        intent.status = status
        intent.updatedAt = Date()
        Task { await self.applyStatus(status, to: intent) }
    }

    private func applyStatus(_ status: IntentStatus, to intent: CapturedIntent) async {
        do {
            try await repository.update(intent)
            // DONE/CANCELLED must never fire a stale reminder; OPEN/WAITING reschedules
            // against whatever temporal value the intent still has.
            await notificationScheduler.scheduleReminder(for: intent)
            await reload()
            let outcome: IntentMetricEvent.Outcome
            switch status {
            case .open: outcome = .reopened
            case .waiting: outcome = .markedWaiting
            case .done: outcome = .markedDone
            case .cancelled: outcome = .cancelled
            }
            await metrics.record(IntentMetricEvent(
                parser: intent.parser,
                confidence: intent.parserConfidence,
                intentClass: intent.type,
                outcome: outcome
            ))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Persists an edited intent (e.g. from the When control) and reschedules its reminder to
    /// match — cancelling any stale one first. The one path both Capture Preview and Inbox detail
    /// editing funnel through; see `IntentWhenControl`.
    public func update(_ intent: CapturedIntent) {
        var updated = intent
        updated.updatedAt = Date()
        Task { await self.applyUpdate(updated) }
    }

    private func applyUpdate(_ updated: CapturedIntent) async {
        do {
            try await repository.update(updated)
            await notificationScheduler.scheduleReminder(for: updated)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func delete(_ id: UUID) {
        Task { await self.applyDelete(id) }
    }

    private func applyDelete(_ id: UUID) async {
        do {
            let deleted = intents.first { $0.id == id }
            try await repository.delete(id: id)
            await notificationScheduler.cancelReminder(for: id)
            selectedID = nil
            await reload()
            await metrics.record(IntentMetricEvent(
                parser: deleted?.parser ?? "unknown",
                confidence: deleted?.parserConfidence,
                intentClass: deleted?.type,
                outcome: .deleted
            ))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension IntentInboxStore {
    /// Test/programmatic seam: awaits full completion (persist + reschedule + reload), unlike the
    /// fire-and-forget `setStatus` SwiftUI actions call directly.
    public func setStatusAndWait(_ status: IntentStatus, for id: UUID) async {
        guard var intent = intents.first(where: { $0.id == id }) else { return }
        intent.status = status
        intent.updatedAt = Date()
        await applyStatus(status, to: intent)
    }

    public func updateAndWait(_ intent: CapturedIntent) async {
        var updated = intent
        updated.updatedAt = Date()
        await applyUpdate(updated)
    }

    public func deleteAndWait(_ id: UUID) async {
        await applyDelete(id)
    }
}
