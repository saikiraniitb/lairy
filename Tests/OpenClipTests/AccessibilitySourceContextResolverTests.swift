import XCTest
@testable import Core
@testable import OpenClip

/// Exercises the deterministic candidate heuristics directly, independent of any live
/// accessibility tree — these are the same fail-closed rules the bounded AX neighborhood walk
/// applies to each candidate string it finds. The live AX walk itself (`resolve(from:)`) needs a
/// real focused UI element and is exercised manually against Google Chat — see
/// docs/intentos/manual-test.md and the DEBUG INTENTOS_SOURCE_CONTEXT log output.
final class AccessibilitySourceContextResolverTests: XCTestCase {
    func testUncalibratedBrowserDoesNotBorrowFrontmostAppMetadata() async {
        let selection = SelectionContext(text: "Please review this", sourceApp: AppIdentity(bundleIdentifier: "com.apple.Safari", localizedName: "Safari", processIdentifier: 999999))
        let context = await AccessibilitySourceContextResolver().resolve(from: selection)
        XCTAssertNil(context.sender)
        XCTAssertNil(context.oneOnOneParticipant)
        XCTAssertNil(context.conversationTitle)
        XCTAssertEqual(context.direction, .unknown)
        XCTAssertEqual(context.selectedText, selection.text)
    }
    func testRecognizesPlausiblePersonName() {
        XCTAssertTrue(AccessibilitySourceContextResolver.looksLikePersonName("Sai Siddeeswara Naidu Gurram"))
        XCTAssertTrue(AccessibilitySourceContextResolver.looksLikePersonName("Ravi Kumar"))
    }

    func testRecognizesYouAsSelfMarker() {
        XCTAssertTrue(AccessibilitySourceContextResolver.looksLikePersonName("You"))
        XCTAssertTrue(AccessibilitySourceContextResolver.looksLikePersonName("you"))
    }

    func testRejectsSingleWordUILabels() {
        XCTAssertFalse(AccessibilitySourceContextResolver.looksLikePersonName("Send"))
        XCTAssertFalse(AccessibilitySourceContextResolver.looksLikePersonName("Reply"))
        XCTAssertFalse(AccessibilitySourceContextResolver.looksLikePersonName("Edit"))
    }

    func testRejectsTextContainingDigits() {
        XCTAssertFalse(AccessibilitySourceContextResolver.looksLikePersonName("Room 204"))
    }

    func testRejectsAllCapsLabels() {
        XCTAssertFalse(AccessibilitySourceContextResolver.looksLikePersonName("SEND MESSAGE"))
    }

    func testRejectsOverlyLongText() {
        let longText = Array(repeating: "Word", count: 20).joined(separator: " ")
        XCTAssertFalse(AccessibilitySourceContextResolver.looksLikePersonName(longText))
    }

    func testRecognizesTimestampLikeText() {
        XCTAssertTrue(AccessibilitySourceContextResolver.looksLikeTimestamp("10:45 AM"))
        XCTAssertTrue(AccessibilitySourceContextResolver.looksLikeTimestamp("Yesterday"))
    }

    func testRejectsLongTextAsTimestamp() {
        XCTAssertFalse(AccessibilitySourceContextResolver.looksLikeTimestamp("This is a much longer message body that happens to mention Friday at some point"))
    }

    func testRejectsPlainProseAsTimestamp() {
        XCTAssertFalse(AccessibilitySourceContextResolver.looksLikeTimestamp("Please review this"))
    }

    func testSupportedBrowserGate() {
        XCTAssertTrue(AccessibilitySourceContextResolver.isSupportedBrowser("com.google.Chrome"))
        XCTAssertTrue(AccessibilitySourceContextResolver.isSupportedBrowser("com.apple.Safari"))
        XCTAssertFalse(AccessibilitySourceContextResolver.isSupportedBrowser("com.apple.Notes"))
        XCTAssertFalse(AccessibilitySourceContextResolver.isSupportedBrowser("com.tinyspeck.slackmacgap"))
    }

    /// Non-browser apps get a safe no-op context (nothing beyond app identity/selected text) —
    /// this is the "document the limitation rather than adding broad scraping code" path for any
    /// app the generic resolver doesn't yet know how to enrich.
    func testNonBrowserAppReturnsUnenrichedContext() async {
        let resolver = AccessibilitySourceContextResolver()
        let selection = SelectionContext(
            text: "Some note text",
            sourceApp: AppIdentity(bundleIdentifier: "com.apple.Notes", localizedName: "Notes")
        )
        let context = await resolver.resolve(from: selection)
        XCTAssertNil(context.sender)
        XCTAssertNil(context.conversationTitle)
        XCTAssertNil(context.timestampText)
        XCTAssertEqual(context.direction, .unknown)
        XCTAssertEqual(context.selectedText, "Some note text")
        XCTAssertEqual(context.bundleIdentifier, "com.apple.Notes")
    }

    // MARK: - Structural (never wording-based) direction fallback

    private let windowFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)

    func testRightAlignedBubbleIsOutgoing() {
        let messageFrame = CGRect(x: 700, y: 100, width: 250, height: 60)
        XCTAssertEqual(AccessibilitySourceContextResolver.directionFromPosition(messageFrame: messageFrame, windowFrame: windowFrame), .outgoing)
    }

    func testLeftAlignedBubbleIsIncoming() {
        let messageFrame = CGRect(x: 50, y: 100, width: 250, height: 60)
        XCTAssertEqual(AccessibilitySourceContextResolver.directionFromPosition(messageFrame: messageFrame, windowFrame: windowFrame), .incoming)
    }

    func testFullWidthRowNearCenterIsUnknown() {
        let messageFrame = CGRect(x: 0, y: 100, width: 1000, height: 60)
        XCTAssertEqual(AccessibilitySourceContextResolver.directionFromPosition(messageFrame: messageFrame, windowFrame: windowFrame), .unknown)
    }

    func testZeroWidthWindowIsUnknown() {
        let messageFrame = CGRect(x: 700, y: 100, width: 250, height: 60)
        XCTAssertEqual(AccessibilitySourceContextResolver.directionFromPosition(messageFrame: messageFrame, windowFrame: .zero), .unknown)
    }

    // MARK: - 1:1 participant heuristic (drives IntentSourceContext.oneOnOneParticipant)

    func testPersonShapedConversationTitleIsUsableAsParticipant() {
        XCTAssertTrue(AccessibilitySourceContextResolver.looksLikePersonName("Shreya Guptha Vutukuri"))
    }

    func testGroupChatTitleIsNotUsableAsParticipant() {
        // Typical group titles: not Title-Case-word-shaped, or contain punctuation/numbers/all caps.
        XCTAssertFalse(AccessibilitySourceContextResolver.looksLikePersonName("Engineering, Design & Product"))
        XCTAssertFalse(AccessibilitySourceContextResolver.looksLikePersonName("Q3 Planning"))
    }
}
