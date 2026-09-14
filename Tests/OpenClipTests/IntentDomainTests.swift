import XCTest
@testable import Core

final class IntentDomainTests: XCTestCase {
    func testCapturedIntentPreservesDraftAndSourceText() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let draft = IntentDraft(
            type: .doAction,
            summary: "Send revised deck to Rahul",
            action: "send",
            object: "revised deck",
            target: "Rahul",
            deadlineText: "Friday",
            sourceText: "I'll send the revised deck to Rahul by Friday.",
            sourceApplicationName: "Notes",
            sourceApplicationBundleIdentifier: "com.apple.Notes",
            parser: "needle2-base",
            parserConfidence: 0.94
        )

        let captured = CapturedIntent(draft: draft, now: now)

        XCTAssertEqual(captured.status, .open)
        XCTAssertEqual(captured.type, .doAction)
        XCTAssertEqual(captured.sourceText, draft.sourceText)
        XCTAssertEqual(captured.sourceApplicationBundleIdentifier, "com.apple.Notes")
        XCTAssertEqual(captured.createdAt, now)
        XCTAssertEqual(captured.updatedAt, now)
    }

    func testDeadlineResolverPreservesAmbiguity() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 14)))

        XCTAssertNil(IntentDeadlineResolver.resolve("next week", relativeTo: now, calendar: calendar))
        XCTAssertEqual(
            IntentDeadlineResolver.resolve("tomorrow", relativeTo: now, calendar: calendar),
            calendar.date(byAdding: .day, value: 1, to: now)
        )
        XCTAssertEqual(
            IntentDeadlineResolver.resolve("Friday", relativeTo: now, calendar: calendar),
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 18))
        )
        XCTAssertEqual(
            IntentDeadlineResolver.resolve("next Monday", relativeTo: now, calendar: calendar),
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 21))
        )

        let tuesday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 15)))
        XCTAssertEqual(
            IntentDeadlineResolver.resolve("next Monday", relativeTo: tuesday, calendar: calendar),
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 21))
        )
    }

    func testParseResultCanCarryNoIntentDiagnostics() {
        let diagnostics = IntentParserDiagnostics(toolSelected: nil, confidence: 0.92)
        let result = IntentParseResult.noIntent(diagnostics: diagnostics)
        XCTAssertEqual(result, .noIntent(diagnostics: diagnostics))
    }
}
