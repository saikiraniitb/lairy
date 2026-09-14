import XCTest
@testable import Core

final class IntentResourceExtractorTests: XCTestCase {
    func testExtractsFigmaURL() {
        let resources = IntentResourceExtractor.extractResources(from: "Please review this flow: https://www.figma.com/design/example and let me know.")
        XCTAssertEqual(resources.count, 1)
        XCTAssertEqual(resources.first?.type, .figma)
        XCTAssertEqual(resources.first?.url, "https://www.figma.com/design/example")
    }

    func testClassifiesKnownHosts() {
        XCTAssertEqual(IntentResourceExtractor.resourceType(forHost: "github.com"), .github)
        XCTAssertEqual(IntentResourceExtractor.resourceType(forHost: "docs.google.com"), .googleDocs)
        XCTAssertEqual(IntentResourceExtractor.resourceType(forHost: "drive.google.com"), .googleDrive)
        XCTAssertEqual(IntentResourceExtractor.resourceType(forHost: "acme.atlassian.net"), .jira)
        XCTAssertEqual(IntentResourceExtractor.resourceType(forHost: "www.notion.so"), .notion)
        XCTAssertEqual(IntentResourceExtractor.resourceType(forHost: "example.com"), .genericURL)
    }

    func testStripsTrailingSentencePunctuation() {
        let resources = IntentResourceExtractor.extractResources(from: "See https://example.com/a.")
        XCTAssertEqual(resources.first?.url, "https://example.com/a")
    }

    func testStripsUnmatchedTrailingParenthesis() {
        let resources = IntentResourceExtractor.extractResources(from: "(see https://example.com/a)")
        XCTAssertEqual(resources.first?.url, "https://example.com/a")
    }

    func testDeduplicatesRepeatedURLs() {
        let resources = IntentResourceExtractor.extractResources(from: "https://example.com/a and again https://example.com/a")
        XCTAssertEqual(resources.count, 1)
    }

    func testNoURLProducesNoResources() {
        XCTAssertTrue(IntentResourceExtractor.extractResources(from: "Please review this.").isEmpty)
    }

    func testMultipleDistinctURLsPreserveOrder() {
        let resources = IntentResourceExtractor.extractResources(from: "First https://a.example.com then https://b.example.com")
        XCTAssertEqual(resources.map(\.url), ["https://a.example.com", "https://b.example.com"])
    }
}

final class TemporalPhraseExtractorTests: XCTestCase {
    func testFindsTomorrow() {
        XCTAssertEqual(TemporalPhraseExtractor.extractPhrases(from: "Please review this tomorrow."), ["tomorrow"])
    }

    func testFindsClockTime() {
        XCTAssertTrue(TemporalPhraseExtractor.extractPhrases(from: "Can we have a session at 5pm??").contains("5pm"))
    }

    func testFindsExplicitDate() {
        XCTAssertTrue(TemporalPhraseExtractor.extractPhrases(from: "Due September 21, 2026.").contains { $0.lowercased().contains("september 21") })
    }

    func testEmptyWhenNoTemporalLanguage() {
        XCTAssertTrue(TemporalPhraseExtractor.extractPhrases(from: "Please review this.").isEmpty)
    }

    func testIsGroundedRequiresBothVerbatimMatchAndEvidence() {
        XCTAssertTrue(TemporalPhraseExtractor.isGrounded(phrase: "tomorrow", in: "Please review this tomorrow."))
        XCTAssertFalse(TemporalPhraseExtractor.isGrounded(phrase: "15th Sept 2026", in: "Please review this flow and let me know if any changes are needed."))
    }
}
