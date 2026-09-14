import XCTest
@testable import Core

final class IntentTemporalResolverTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private var referenceDate: Date {
        // A Monday.
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 8))!
    }

    /// "Review this tomorrow." -> grounded due date.
    func testActionWithGroundedDeadlineProducesDueAt() {
        let result = IntentTemporalResolver.resolve(
            type: .action,
            deadlineText: "tomorrow",
            sourceText: "Review this tomorrow.",
            currentDate: referenceDate,
            calendar: calendar
        )
        XCTAssertNotNil(result.dueAt)
        XCTAssertEqual(result.dueAt?.provenance, .modelGrounded)
        XCTAssertEqual(result.dueAt?.hasTime, false)
        XCTAssertNil(result.eventAt)
        XCTAssertNil(result.followUpAt)
        XCTAssertNil(result.unresolvedTimeText)
    }

    /// "Review this." -> no date at all.
    func testNoDeadlineTextProducesNothing() {
        let result = IntentTemporalResolver.resolve(
            type: .action,
            deadlineText: nil,
            sourceText: "Review this.",
            currentDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(result, IntentTemporalResolver.Resolution())
    }

    /// "Can we have a session at 5pm?" -> time exists but no date is ever invented.
    func testBareClockTimeWithNoDateStaysUnresolved() {
        let result = IntentTemporalResolver.resolve(
            type: .waiting,
            deadlineText: nil,
            sourceText: "Can we have a session at 5pm?",
            currentDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(result.unresolvedTimeText, "5pm")
        XCTAssertNil(result.dueAt)
        XCTAssertNil(result.eventAt)
        XCTAssertNil(result.followUpAt)
    }

    func testMeetingWordingWithTimeProducesEventAt() {
        let result = IntentTemporalResolver.resolve(
            type: .action,
            deadlineText: "Friday at 5pm",
            sourceText: "Let's meet Friday at 5pm.",
            currentDate: referenceDate,
            calendar: calendar
        )
        XCTAssertNotNil(result.eventAt)
        XCTAssertEqual(result.eventAt?.hasTime, true)
        XCTAssertNil(result.dueAt)
        let components = calendar.dateComponents([.hour], from: result.eventAt!.date)
        XCTAssertEqual(components.hour, 17)
    }

    func testWaitingTypeProducesFollowUpAt() {
        let result = IntentTemporalResolver.resolve(
            type: .waiting,
            deadlineText: "Monday",
            sourceText: "I've asked Ravi for approval. Check again Monday.",
            currentDate: referenceDate,
            calendar: calendar
        )
        XCTAssertNotNil(result.followUpAt)
        XCTAssertNil(result.dueAt)
        XCTAssertNil(result.eventAt)
    }

    /// REMEMBER never gets a reminder by default, even if a date is mentioned in passing.
    func testRememberNeverProducesATemporalBucket() {
        let result = IntentTemporalResolver.resolve(
            type: .remember,
            deadlineText: "Friday",
            sourceText: "Remember the renewal is due Friday.",
            currentDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(result, IntentTemporalResolver.Resolution())
    }

    func testUnresolvableDatePhraseWithTimeStaysUnresolved() {
        let result = IntentTemporalResolver.resolve(
            type: .action,
            deadlineText: "next week",
            sourceText: "Let's sync next week at 3pm.",
            currentDate: referenceDate,
            calendar: calendar
        )
        XCTAssertNil(result.dueAt)
        XCTAssertNil(result.eventAt)
        XCTAssertEqual(result.unresolvedTimeText, "3pm")
    }
}
