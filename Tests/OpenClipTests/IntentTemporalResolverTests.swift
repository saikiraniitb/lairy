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

    /// "Let's connect tomorrow at 8am" — a WAITING proposal with a genuine meeting time (per the
    /// real WhatsApp regression) must become an event, never a due date or a follow-up reminder.
    func testWaitingWithMeetingTimeProducesEventAtNotFollowUp() {
        let result = IntentTemporalResolver.resolve(
            type: .waiting,
            deadlineText: "tomorrow at 8am",
            sourceText: "Let's connect tomorrow at 8am",
            currentDate: referenceDate,
            calendar: calendar
        )
        XCTAssertNotNil(result.eventAt)
        XCTAssertEqual(result.eventAt?.hasTime, true)
        XCTAssertNil(result.dueAt)
        XCTAssertNil(result.followUpAt)
        let components = calendar.dateComponents([.hour], from: result.eventAt!.date)
        XCTAssertEqual(components.hour, 8)
    }

    /// A multi-message selection's plain text can carry an inline rendered timestamp between
    /// messages (a real Google Chat regression) — that must never surface as an "unresolved time
    /// mention" even though it matches the bare clock-time shape.
    func testMessageTimestampInSourceTextNeverBecomesUnresolvedTime() {
        let result = IntentTemporalResolver.resolve(
            type: .waiting,
            deadlineText: nil,
            sourceText: """
            These are the changes discussed with pavan
            so please update the doc accordingly
            Shreya Guptha Vutukuri, 26 Aug, 10:29
            okay i will update
            """,
            currentDate: referenceDate,
            calendar: calendar
        )
        XCTAssertNil(result.unresolvedTimeText, "26 Aug, 10:29 is a rendered message timestamp, not a phrase anyone wrote")
        XCTAssertNil(result.dueAt)
        XCTAssertNil(result.eventAt)
        XCTAssertNil(result.followUpAt)
    }

    /// Same shape, a weekday-abbreviation timestamp ("Fri 15:51") rather than day+month.
    func testWeekdayAbbreviatedTimestampNeverBecomesUnresolvedTime() {
        let result = IntentTemporalResolver.resolve(
            type: .action,
            deadlineText: nil,
            sourceText: "Shreya Guptha Vutukuri  Fri 15:51\nhere's the doc",
            currentDate: referenceDate,
            calendar: calendar
        )
        XCTAssertNil(result.unresolvedTimeText)
    }

    /// The real "Skill UP BY Sai Kiran" WhatsApp group regression: WhatsApp's own Cmd+C copy
    /// prepends "[DD/MM/YY, HH:MM:SS AM/PM] Sender: " to a copied message — that bracketed export
    /// timestamp must never surface as a mentioned meeting time either, even though it's a bare
    /// time with no weekday/month name of its own (only the bracketed date makes it recognizable
    /// as metadata rather than something the user wrote).
    func testWhatsAppCopyExportPrefixNeverBecomesUnresolvedTime() {
        let result = IntentTemporalResolver.resolve(
            type: .waiting,
            deadlineText: nil,
            sourceText: """
            [06/09/26, 11:00:31 PM] Saikiran: Hi everyone
            See everyone in this group
            Let's start our journey from 07/09/2026
            By end of everyday please keep your updates
            """,
            currentDate: referenceDate,
            calendar: calendar
        )
        XCTAssertNil(result.unresolvedTimeText, "11:00:31 PM is WhatsApp's own copy-export timestamp, not a mentioned meeting time")
    }

    /// A genuine in-message time mention must still surface as unresolved when it sits nowhere
    /// near a calendar-date token — the timestamp regex must not overreach into real content.
    func testGenuineBareTimeMentionNextToTimestampStillUnresolved() {
        let result = IntentTemporalResolver.resolve(
            type: .waiting,
            deadlineText: nil,
            sourceText: """
            Shreya Guptha Vutukuri, 26 Aug, 10:29
            can we push the call to 6pm instead
            """,
            currentDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(result.unresolvedTimeText, "6pm", "the real in-message time must still be found once the timestamp line is stripped")
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
