import XCTest
@testable import Core
@testable import OpenClip

final class GoogleChatSourceContextResolverTests: XCTestCase {
    func testSearchResultWrapperHasExplicitOutgoingAuthorAndSpaceNotPerson() {
        let result = GoogleChatSourceContextResolver.outgoingEvidence(label: "Product Team Space You: Coding Assessment Questions should be generated…", selectedFragment: "Coding Assessment")
        XCTAssertTrue(result.outgoing)
        XCTAssertEqual(result.spaceTitle, "Product Team")
    }

    func testOrdinaryOutgoingRow() {
        XCTAssertTrue(GoogleChatSourceContextResolver.outgoingEvidence(label: "You so please update the doc accordingly , 26 Aug, 10:28 ,", selectedFragment: "so please update the doc accordingly").outgoing)
    }

    func testUnrelatedSelectionAndBodyWordingAreNotAuthorEvidence() {
        XCTAssertFalse(GoogleChatSourceContextResolver.outgoingEvidence(label: "Product Team Space You: Different message", selectedFragment: "Coding Assessment").outgoing)
        XCTAssertFalse(GoogleChatSourceContextResolver.outgoingEvidence(label: "You should update the document", selectedFragment: "You should update the document").outgoing)
    }

    func testEmptyAXAttributeDoesNotMaskUsefulAttribute() {
        XCTAssertEqual(GoogleChatSourceContextResolver.nonempty(["", "  ", nil, "You"]), "You")
    }
}
