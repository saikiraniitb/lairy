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

    // MARK: - Source context grounding (requestedBy / trusted sender)

    private let realCaseSource = """
    Hi @Sai Kiran Cherakam Sir, This is the updated landing page for Employer with our latest \
    color pallet. Please have a look and let me know any changes that need to be made. Thankyou
    """

    /// The exact real case: a trusted sender always wins over an @mention the model may have
    /// latched onto inside the message body, even when the model's own guess also happens to
    /// verbatim-match text elsewhere.
    func testTrustedSenderOverridesProvidersOwnGuess() {
        let context = IntentSourceContext(sender: "Sai Siddeeswara Naidu Gurram", direction: .incoming, selectedText: realCaseSource)
        let proposed = IntentUnderstanding(hasTrackableIntent: true, requestedBy: "Sai Kiran Cherakam")

        let result = IntentGroundingValidator.validate(proposed, sourceText: realCaseSource, sourceContext: context)

        XCTAssertEqual(result.understanding.requestedBy, "Sai Siddeeswara Naidu Gurram")
        XCTAssertTrue(result.rejections.contains { $0.field == "requestedBy" && $0.value == "Sai Kiran Cherakam" })
    }

    /// A trusted sender is valid even though it never appears anywhere in the selected text.
    func testTrustedSenderNotInSourceTextStillGrounds() {
        let context = IntentSourceContext(sender: "Sai Siddeeswara Naidu Gurram", direction: .incoming, selectedText: realCaseSource)
        let proposed = IntentUnderstanding(hasTrackableIntent: true)

        let result = IntentGroundingValidator.validate(proposed, sourceText: realCaseSource, sourceContext: context)

        XCTAssertEqual(result.understanding.requestedBy, "Sai Siddeeswara Naidu Gurram")
        XCTAssertFalse(realCaseSource.contains("Sai Siddeeswara"))
    }

    /// No trusted sender at all -> requestedBy stays null rather than trusting the model's guess,
    /// unless that guess is itself grounded in the source text.
    func testUnknownSenderStaysNull() {
        let proposed = IntentUnderstanding(hasTrackableIntent: true, requestedBy: "Someone")
        let result = IntentGroundingValidator.validate(proposed, sourceText: "Please review this.", sourceContext: nil)
        XCTAssertNil(result.understanding.requestedBy)
        XCTAssertTrue(result.rejections.contains { $0.field == "requestedBy" })
    }

    /// A person named by the model that appears in neither the source text nor trusted context is
    /// removed, even when a (different) trusted sender exists.
    func testProviderPersonAbsentFromBothSourcesIsRemoved() {
        let context = IntentSourceContext(sender: "Sai Siddeeswara Naidu Gurram", direction: .incoming, selectedText: realCaseSource)
        let proposed = IntentUnderstanding(hasTrackableIntent: true, target: "Completely Invented Person")
        let result = IntentGroundingValidator.validate(proposed, sourceText: realCaseSource, sourceContext: context)
        XCTAssertNil(result.understanding.target)
        XCTAssertTrue(result.rejections.contains { $0.field == "target" && $0.value == "Completely Invented Person" })
    }

    /// A name grounded via trusted `conversationTitle` (not just `sender`) also survives for
    /// non-requestedBy person fields.
    func testWaitingForGroundedByOneOnOneParticipant() {
        let context = IntentSourceContext(conversationTitle: "Ravi Kumar", oneOnOneParticipant: "Ravi Kumar", selectedText: "Can you check with him?")
        let proposed = IntentUnderstanding(hasTrackableIntent: true, waitingFor: "Ravi Kumar")
        let result = IntentGroundingValidator.validate(proposed, sourceText: "Can you check with him?", sourceContext: context)
        XCTAssertEqual(result.understanding.waitingFor, "Ravi Kumar")
    }

    /// A group chat's title must never ground a person field — only a reliably-determined 1:1
    /// participant may (see IntentSourceContext.oneOnOneParticipant).
    func testGroupChatConversationTitleNeverGroundsAPerson() {
        let context = IntentSourceContext(conversationTitle: "Engineering Team", selectedText: "Can you check with him?")
        let proposed = IntentUnderstanding(hasTrackableIntent: true, waitingFor: "Engineering Team")
        let result = IntentGroundingValidator.validate(proposed, sourceText: "Can you check with him?", sourceContext: context)
        XCTAssertNil(result.understanding.waitingFor)
    }

    /// No regression: existing resource/date grounding is unaffected by adding sourceContext.
    func testExistingResourceAndDateGroundingUnaffectedBySourceContext() {
        let context = IntentSourceContext(sender: "Someone Else", direction: .incoming, selectedText: "Please review this tomorrow.")
        let proposed = IntentUnderstanding(hasTrackableIntent: true, deadlineText: "tomorrow")
        let result = IntentGroundingValidator.validate(proposed, sourceText: "Please review this tomorrow.", sourceContext: context)
        XCTAssertEqual(result.understanding.deadlineText, "tomorrow")
    }

    /// A confused provider echoing the field label itself ("Waiting for") as if it were a real
    /// person's name must never survive grounding, even without a trusted override to correct it.
    func testWaitingForPlaceholderLabelIsRejected() {
        let proposed = IntentUnderstanding(hasTrackableIntent: true, waitingFor: "Waiting for")
        let result = IntentGroundingValidator.validate(proposed, sourceText: "Let's connect tomorrow at 8am")
        XCTAssertNil(result.understanding.waitingFor)
        XCTAssertTrue(result.rejections.contains { $0.field == "waitingFor" })
    }

    /// A trusted 1:1 participant still overrides a placeholder guess outright — the hard-override
    /// path never needs the provider's value to be sane in the first place.
    func testWaitingForPlaceholderOverriddenByTrustedParticipant() {
        let context = IntentSourceContext(oneOnOneParticipant: "Cherry", direction: .outgoing, selectedText: "Let's connect tomorrow at 8am")
        let proposed = IntentUnderstanding(hasTrackableIntent: true, speechAct: .request, direction: .outgoing, waitingFor: "Waiting for")
        let result = IntentGroundingValidator.validate(proposed, sourceText: "Let's connect tomorrow at 8am", sourceContext: context)
        XCTAssertEqual(result.understanding.waitingFor, "Cherry")
    }

    /// The real "Skill UP BY Sai Kiran" WhatsApp group regression: "everyone" appears verbatim in
    /// the broadcast itself ("Hi everyone... in this group"), so it would otherwise pass ordinary
    /// text grounding — but it names no ONE person and must never survive as waitingFor/target,
    /// same principle as the "Waiting for" UI-label placeholder.
    func testCollectiveAddressTermNeverGroundsAsAPerson() {
        let source = """
        Hi everyone
        See everyone in this group
        Are having zero knowledge on the coding and software
        So I've designed the course like that
        Please go through the phase 1 docs
        """
        let proposed = IntentUnderstanding(hasTrackableIntent: true, target: "everyone", waitingFor: "everyone")
        let result = IntentGroundingValidator.validate(proposed, sourceText: source)
        XCTAssertNil(result.understanding.waitingFor)
        XCTAssertNil(result.understanding.target)
    }
}
