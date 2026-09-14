import XCTest
@testable import Core

/// Exercises the deterministic classifier directly against the milestone's required test cases
/// (A-J from the Intent Intelligence V1 spec), independent of any live Gemini call: these fixtures
/// simulate the *understanding* a correct provider call would have produced, so classification
/// logic is verified even without a real API key.
final class IntentClassifierTests: XCTestCase {
    private func understanding(
        trackable: Bool = true,
        speechAct: SpeechAct? = nil,
        direction: IntentDirection? = nil,
        actor: ActorType? = nil,
        owner: IntentOwner? = nil,
        temporalState: TemporalState? = nil,
        polarity: Polarity? = nil,
        commitmentStrength: CommitmentStrength? = nil,
        waitingFor: String? = nil,
        responseExpected: Bool? = nil
    ) -> IntentUnderstanding {
        IntentUnderstanding(
            hasTrackableIntent: trackable,
            speechAct: speechAct,
            direction: direction,
            actor: actor,
            owner: owner,
            temporalState: temporalState,
            polarity: polarity,
            commitmentStrength: commitmentStrength,
            waitingFor: waitingFor,
            responseExpected: responseExpected
        )
    }

    /// A) "I'll send Arun the roadmap tomorrow." -> ACTION, self-owned.
    func testSelfCommitmentIsAction() {
        let u = understanding(speechAct: .commitment, actor: .selfActor, owner: .selfOwner, temporalState: .future, polarity: .positive)
        XCTAssertEqual(IntentClassifier.classify(u), .action)
    }

    /// B) "Arun will send me the roadmap tomorrow." -> never ACTION owned by self.
    func testThirdPartyCommitmentIsNeverSelfOwnedAction() {
        let u = understanding(speechAct: .commitment, actor: .other, owner: .other, temporalState: .future, polarity: .positive, waitingFor: "Arun")
        XCTAssertNotEqual(IntentClassifier.classify(u), .action)
    }

    /// C) "I already sent Arun the roadmap yesterday." -> NO_INTENT.
    func testPastCommitmentIsNoIntent() {
        let u = understanding(speechAct: .commitment, actor: .selfActor, owner: .selfOwner, temporalState: .past, polarity: .positive)
        XCTAssertNil(IntentClassifier.classify(u))
    }

    /// D) "Don't send Arun the roadmap." -> no positive ACTION.
    func testNegatedInstructionIsNoIntent() {
        let u = understanding(speechAct: .instruction, direction: .selfDirected, owner: .selfOwner, temporalState: .future, polarity: .negative)
        XCTAssertNil(IntentClassifier.classify(u))
    }

    /// E) "We crossed a major milestone today." -> NO_INTENT (not trackable at all).
    func testInformationalStatementIsNoIntent() {
        let u = understanding(trackable: false, speechAct: .statement, temporalState: .present, polarity: .positive)
        XCTAssertNil(IntentClassifier.classify(u))
    }

    /// F) "Remember that Acme prefers quarterly billing." -> REMEMBER.
    func testReminderIsRemember() {
        let u = understanding(speechAct: .reminder, polarity: .positive)
        XCTAssertEqual(IntentClassifier.classify(u), .remember)
    }

    /// G) "Can we have a session at 5pm?" -> REQUEST or WAITING, never nil.
    func testOutgoingRequestIsRequestOrWaiting() {
        let u = understanding(speechAct: .request, direction: .outgoing, owner: .shared, polarity: .positive)
        let type = IntentClassifier.classify(u)
        XCTAssertTrue(type == .request || type == .waiting, "expected REQUEST or WAITING, got \(String(describing: type))")
    }

    /// H) "Please review this Figma and let me know if changes are needed." -> ACTION.
    func testIncomingRequestIsAction() {
        let u = understanding(speechAct: .request, direction: .incoming, owner: .selfOwner, polarity: .positive, responseExpected: true)
        XCTAssertEqual(IntentClassifier.classify(u), .action)
    }

    func testNoTrackableIntentAlwaysWins() {
        let u = understanding(trackable: false, speechAct: .commitment, actor: .selfActor, owner: .selfOwner, temporalState: .future, polarity: .positive)
        XCTAssertNil(IntentClassifier.classify(u))
    }
}
