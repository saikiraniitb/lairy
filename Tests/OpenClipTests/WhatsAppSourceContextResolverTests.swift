import XCTest
@testable import Core
@testable import OpenClip

final class WhatsAppSourceContextResolverTests: XCTestCase {
    func testExplicitOutgoingProvenance() {
        let evidence = WhatsAppSourceContextResolver.messageEvidence("‎Your message, Let's connect tomorrow at 8am, 11:24 PM, ‎Sent to Cherry, ‎Delivered", selectedText: "Let's connect tomorrow at 8am")
        XCTAssertEqual(evidence.direction, .outgoing)
        XCTAssertNil(evidence.sender)
    }

    func testNoEvidenceMeansUnknown() {
        XCTAssertEqual(WhatsAppSourceContextResolver.messageEvidence("Let's connect tomorrow at 8am", selectedText: "Let's connect tomorrow at 8am").direction, .unknown)
    }

    func testIncomingAndForeignSelection() {
        let text = "‎message, Please review this tomorrow, 11:24 PM, ‎Received from Cherry"
        XCTAssertEqual(WhatsAppSourceContextResolver.messageEvidence(text, selectedText: "Please review this tomorrow").sender, "Cherry")
        XCTAssertEqual(WhatsAppSourceContextResolver.messageEvidence(text, selectedText: "Different selection").direction, .unknown)
    }
    /// The real regression case: WhatsApp headers are very often a single first name/nickname,
    /// unlike a browser tab title — the shared `looksLikePersonName` (built for full names) would
    /// reject this outright.
    func testSingleWordContactNameIsAccepted() {
        XCTAssertTrue(WhatsAppSourceContextResolver.looksLikeContactName("Cherry"))
        XCTAssertTrue(WhatsAppSourceContextResolver.looksLikeContactName("Shreya Guptha Vutukuri"))
    }

    func testNonNameShapedTextIsRejected() {
        // Lowercase-led words, a sentence, and a bare number are never name-shaped regardless of
        // word count. (A capitalized two-word UI label like "New Chat" is structurally
        // indistinguishable from a real name by shape alone — that false positive is instead
        // guarded against positionally, by hit-testing past the sidebar; see
        // `findHeaderParticipantByHitTest`.)
        XCTAssertFalse(WhatsAppSourceContextResolver.looksLikeContactName("connect tomorrow at 8am"))
        XCTAssertFalse(WhatsAppSourceContextResolver.looksLikeContactName(""))
        XCTAssertFalse(WhatsAppSourceContextResolver.looksLikeContactName("123"))
    }
}
