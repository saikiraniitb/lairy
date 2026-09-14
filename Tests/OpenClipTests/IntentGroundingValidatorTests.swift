import XCTest
@testable import Core

final class IntentGroundingValidatorTests: XCTestCase {
    /// The exact regression case from the milestone: Gemini claiming a deadline that never
    /// appeared in the source text must be nulled, not trusted.
    func testHallucinatedDeadlineIsRejected() {
        let source = """
        Hi Sir, This is the Updated Jobseeker profile creation flow (Unified Form).
        Please review this flow and let me know if any changes are needed.
        https://www.figma.com/design/example
        """
        let proposed = IntentUnderstanding(hasTrackableIntent: true, deadlineText: "15th Sept 2026")

        let result = IntentGroundingValidator.validate(proposed, sourceText: source)

        XCTAssertNil(result.understanding.deadlineText)
        XCTAssertEqual(result.rejections.count, 1)
        XCTAssertEqual(result.rejections.first?.field, "deadlineText")
    }

    func testGroundedDeadlineSurvives() {
        let source = "Please review this tomorrow."
        let proposed = IntentUnderstanding(hasTrackableIntent: true, deadlineText: "tomorrow")

        let result = IntentGroundingValidator.validate(proposed, sourceText: source)

        XCTAssertEqual(result.understanding.deadlineText, "tomorrow")
        XCTAssertTrue(result.rejections.isEmpty)
    }

    func testNoDeadlineWhenSourceHasNoTemporalEvidenceAtAll() {
        let source = "Please review this."
        let proposed = IntentUnderstanding(hasTrackableIntent: true, deadlineText: "next week")

        let result = IntentGroundingValidator.validate(proposed, sourceText: source)

        XCTAssertNil(result.understanding.deadlineText)
    }

    /// A hallucinated recipient (never grounded in source) must be nulled — this is exactly what
    /// stops a "Siddhu" from being invented for the Google Chat regression case.
    func testHallucinatedPersonNameIsRejected() {
        let source = "Please review this flow and let me know if any changes are needed."
        let proposed = IntentUnderstanding(hasTrackableIntent: true, target: "Siddhu")

        let result = IntentGroundingValidator.validate(proposed, sourceText: source)

        XCTAssertNil(result.understanding.target)
        XCTAssertEqual(result.rejections.first { $0.field == "target" }?.value, "Siddhu")
    }

    func testGroundedPersonNameSurvives() {
        let source = "Hi Rahman, can we have a session at 5pm??"
        let proposed = IntentUnderstanding(hasTrackableIntent: true, waitingFor: "Rahman")

        let result = IntentGroundingValidator.validate(proposed, sourceText: source)

        XCTAssertEqual(result.understanding.waitingFor, "Rahman")
    }

    func testGroundedTriggerSurvives() {
        let source = "Once Finance confirms the budget, send the proposal to Priya."
        let proposed = IntentUnderstanding(hasTrackableIntent: true, trigger: "Finance confirms the budget")

        let result = IntentGroundingValidator.validate(proposed, sourceText: source)

        XCTAssertEqual(result.understanding.trigger, "Finance confirms the budget")
    }

    /// Resource URLs are never taken from the provider — only from deterministic extraction.
    func testResourceURLsComeOnlyFromSourceText() {
        let source = "Please review this flow: https://www.figma.com/design/example and let me know."
        let proposed = IntentUnderstanding(
            hasTrackableIntent: true,
            resourceLabels: [
                IntentResourceLabelSuggestion(url: "https://www.figma.com/design/example", label: "Jobseeker profile creation flow"),
                IntentResourceLabelSuggestion(url: "https://evil.example.com/not-in-source", label: "Fake link")
            ]
        )

        let result = IntentGroundingValidator.validate(proposed, sourceText: source)

        XCTAssertEqual(result.resources.count, 1)
        XCTAssertEqual(result.resources.first?.url, "https://www.figma.com/design/example")
        XCTAssertEqual(result.resources.first?.type, .figma)
        XCTAssertEqual(result.resources.first?.label, "Jobseeker profile creation flow")
        XCTAssertTrue(result.rejections.contains { $0.field == "resourceLabels" && $0.value == "https://evil.example.com/not-in-source" })
    }

    func testNoResourcesWhenSourceHasNoURL() {
        let result = IntentGroundingValidator.validate(IntentUnderstanding(hasTrackableIntent: true), sourceText: "Please review this.")
        XCTAssertTrue(result.resources.isEmpty)
    }
}
