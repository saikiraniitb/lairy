import XCTest
@testable import Core

final class IntentReminderPlannerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func intent(
        type: IntentType = .action,
        status: IntentStatus? = nil,
        dueAt: IntentTemporalValue? = nil,
        eventAt: IntentTemporalValue? = nil,
        followUpAt: IntentTemporalValue? = nil
    ) -> CapturedIntent {
        CapturedIntent(
            type: type,
            status: status,
            summary: "Review the doc",
            dueAt: dueAt,
            eventAt: eventAt,
            followUpAt: followUpAt,
            sourceText: "Review the doc",
            sourceApplicationName: "Google Chat",
            parser: "test"
        )
    }

    /// Date-only deadline -> notification scheduled for 9 AM local time.
    func testDateOnlyDeadlineFiresAtNineAM() throws {
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20))!
        let value = IntentTemporalValue(date: date, hasTime: false, provenance: .modelGrounded)
        let plan = IntentReminderPlanner.plan(for: intent(dueAt: value), calendar: calendar)
        let components = calendar.dateComponents([.hour, .minute], from: try XCTUnwrap(plan?.fireDate))
        XCTAssertEqual(components.hour, IntentReminderPolicy.dateOnlyReminderHour)
        XCTAssertEqual(components.minute, IntentReminderPolicy.dateOnlyReminderMinute)
    }

    /// Timed deadline/event -> notification 30 minutes before.
    func testTimedDeadlineFiresThirtyMinutesBefore() {
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 17, minute: 0))!
        let value = IntentTemporalValue(date: date, hasTime: true, provenance: .modelGrounded)
        let plan = IntentReminderPlanner.plan(for: intent(dueAt: value), calendar: calendar)
        XCTAssertEqual(plan?.fireDate, calendar.date(byAdding: .minute, value: -IntentReminderPolicy.timedReminderLeadMinutes, to: date))
    }

    func testTimedEventFiresThirtyMinutesBefore() {
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 17, minute: 0))!
        let value = IntentTemporalValue(date: date, hasTime: true, provenance: .modelGrounded)
        let plan = IntentReminderPlanner.plan(for: intent(eventAt: value), calendar: calendar)
        XCTAssertEqual(plan?.fireDate, calendar.date(byAdding: .minute, value: -30, to: date))
    }

    func testFollowUpFiresExactlyAtValue() {
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 9))!
        let value = IntentTemporalValue(date: date, hasTime: true, provenance: .modelGrounded)
        let plan = IntentReminderPlanner.plan(for: intent(type: .waiting, followUpAt: value), calendar: calendar)
        XCTAssertEqual(plan?.fireDate, date)
    }

    /// REMEMBER without any temporal value scheduled -> no notification.
    func testRememberWithoutTemporalValueHasNoPlan() {
        let plan = IntentReminderPlanner.plan(for: intent(type: .remember), calendar: calendar)
        XCTAssertNil(plan)
    }

    func testDoneStatusNeverProducesAPlan() {
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20))!
        let value = IntentTemporalValue(date: date, hasTime: false, provenance: .modelGrounded)
        let plan = IntentReminderPlanner.plan(for: intent(status: .done, dueAt: value), calendar: calendar)
        XCTAssertNil(plan)
    }

    func testCancelledStatusNeverProducesAPlan() {
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20))!
        let value = IntentTemporalValue(date: date, hasTime: false, provenance: .modelGrounded)
        let plan = IntentReminderPlanner.plan(for: intent(status: .cancelled, dueAt: value), calendar: calendar)
        XCTAssertNil(plan)
    }

    func testEventTakesPriorityOverDue() {
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20))!
        let value = IntentTemporalValue(date: date, hasTime: false, provenance: .modelGrounded)
        let plan = IntentReminderPlanner.plan(for: intent(dueAt: value, eventAt: value), calendar: calendar)
        XCTAssertNotNil(plan)
    }
}
