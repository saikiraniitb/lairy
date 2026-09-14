import XCTest
@testable import Core
@testable import OpenClip

@MainActor
final class IntentInboxStoreTests: XCTestCase {
    private func makeIntent(dueAt: IntentTemporalValue? = nil) -> CapturedIntent {
        CapturedIntent(
            type: .action,
            summary: "Review the doc",
            dueAt: dueAt,
            sourceText: "Review the doc",
            sourceApplicationName: "Google Chat",
            parser: "test"
        )
    }

    /// Mark done -> notification cancelled (via a reschedule that plans nothing for a done intent —
    /// see IntentReminderPlannerTests for the policy layer this relies on).
    func testMarkDoneReschedulesNotificationForDoneIntent() async throws {
        let intent = makeIntent(dueAt: IntentTemporalValue(date: Date().addingTimeInterval(3600), hasTime: true, provenance: .modelGrounded))
        let repository = MemoryIntentRepository(seed: [intent])
        let scheduler = RecordingNotificationScheduler()
        let store = IntentInboxStore(repository: repository, notificationScheduler: scheduler)
        await store.reload()

        await store.setStatusAndWait(.done, for: intent.id)

        let scheduledIntents = await scheduler.scheduledIntents
        let lastScheduled = try XCTUnwrap(scheduledIntents.last)
        XCTAssertEqual(lastScheduled.status, .done)
        XCTAssertEqual(store.intents.first(where: { $0.id == intent.id })?.status, .done)
    }

    /// Delete -> notification cancelled.
    func testDeleteCancelsNotification() async {
        let intent = makeIntent(dueAt: IntentTemporalValue(date: Date().addingTimeInterval(3600), hasTime: true, provenance: .modelGrounded))
        let repository = MemoryIntentRepository(seed: [intent])
        let scheduler = RecordingNotificationScheduler()
        let store = IntentInboxStore(repository: repository, notificationScheduler: scheduler)
        await store.reload()

        await store.deleteAndWait(intent.id)

        let cancelled = await scheduler.cancelledIDs
        XCTAssertTrue(cancelled.contains(intent.id))
        XCTAssertTrue(store.intents.isEmpty)
    }

    /// Changing the deadline -> old notification cancelled, new one scheduled (replace semantics:
    /// `scheduleReminder` always cancels first — see UNUserNotificationIntentScheduler).
    func testChangingDeadlineReschedules() async throws {
        let originalDue = IntentTemporalValue(date: Date().addingTimeInterval(3600), hasTime: true, provenance: .modelGrounded)
        let intent = makeIntent(dueAt: originalDue)
        let repository = MemoryIntentRepository(seed: [intent])
        let scheduler = RecordingNotificationScheduler()
        let store = IntentInboxStore(repository: repository, notificationScheduler: scheduler)
        await store.reload()

        let newDue = IntentTemporalValue(date: Date().addingTimeInterval(7200), hasTime: true, provenance: .userSelected)
        var updated = intent
        updated.dueAt = newDue
        await store.updateAndWait(updated)

        let scheduledIntents = await scheduler.scheduledIntents
        let lastScheduled = try XCTUnwrap(scheduledIntents.last)
        XCTAssertEqual(lastScheduled.dueAt, newDue)
        XCTAssertEqual(store.intents.first(where: { $0.id == intent.id })?.dueAt, newDue)
    }

    /// Persistence across relaunch: a fresh store reading the same repository sees the edit.
    func testUpdatePersistsAcrossFreshStoreInstance() async {
        let intent = makeIntent()
        let repository = MemoryIntentRepository(seed: [intent])
        let store = IntentInboxStore(repository: repository, notificationScheduler: RecordingNotificationScheduler())
        await store.reload()

        var updated = intent
        updated.dueAt = IntentTemporalValue(date: Date().addingTimeInterval(3600), hasTime: true, provenance: .userSelected)
        await store.updateAndWait(updated)

        let freshStore = IntentInboxStore(repository: repository, notificationScheduler: RecordingNotificationScheduler())
        await freshStore.reload()
        XCTAssertEqual(freshStore.intents.first?.dueAt?.provenance, .userSelected)
    }
}

private actor MemoryIntentRepository: IntentRepository {
    private var storage: [UUID: CapturedIntent]

    init(seed: [CapturedIntent] = []) {
        storage = Dictionary(uniqueKeysWithValues: seed.map { ($0.id, $0) })
    }

    func save(_ intent: CapturedIntent) async throws {
        guard storage[intent.id] == nil else { throw IntentRepositoryError.duplicateID(intent.id) }
        storage[intent.id] = intent
    }

    func fetchAll() async throws -> [CapturedIntent] { Array(storage.values) }

    func update(_ intent: CapturedIntent) async throws {
        guard storage[intent.id] != nil else { throw IntentRepositoryError.intentNotFound(intent.id) }
        storage[intent.id] = intent
    }

    func delete(id: UUID) async throws {
        guard storage.removeValue(forKey: id) != nil else { throw IntentRepositoryError.intentNotFound(id) }
    }
}

private actor RecordingNotificationScheduler: IntentNotificationScheduling {
    private(set) var scheduledIntents: [CapturedIntent] = []
    private(set) var cancelledIDs: [UUID] = []

    func scheduleReminder(for intent: CapturedIntent) async {
        scheduledIntents.append(intent)
    }

    func cancelReminder(for intentID: UUID) async {
        cancelledIDs.append(intentID)
    }
}
