import XCTest
@testable import Core
@testable import OpenClip

/// Covers the early-`SourceContextSnapshot` mechanism (see `SourceContextSnapshot.swift` and
/// `IntentCaptureCoordinator.resolveSourceContext`): a trusted early snapshot resolved while the
/// source app was still frontmost must win over late (weaker/empty) resolution, but only when it
/// still genuinely matches the selection being captured — never a stale or foreign one.
@MainActor
final class IntentCaptureCoordinatorSourceContextSnapshotTests: XCTestCase {
    private let ttl = Constants.sourceContextSnapshotTTL

    private func makeCoordinator(lateResolverContext: IntentSourceContext) -> IntentCaptureCoordinator {
        IntentCaptureCoordinator(
            parser: NoIntentParser(),
            repository: MemoryIntentRepository(),
            sourceContextResolver: StubSourceContextResolver(context: lateResolverContext)
        )
    }

    private func snapshot(
        participant: String = "Cherry",
        selectedText: String = "Let's connect tomorrow at 8am",
        bundleIdentifier: String? = "net.whatsapp.WhatsApp",
        sourcePID: pid_t? = 4242,
        capturedAt: Date = Date()
    ) -> SourceContextSnapshot {
        SourceContextSnapshot(
            sourceContext: IntentSourceContext(
                conversationTitle: participant,
                oneOnOneParticipant: participant,
                direction: .outgoing,
                selectedText: selectedText
            ),
            selectedText: selectedText,
            bundleIdentifier: bundleIdentifier,
            sourcePID: sourcePID,
            capturedAt: capturedAt
        )
    }

    private func selection(
        text: String = "Let's connect tomorrow at 8am",
        bundleIdentifier: String? = "net.whatsapp.WhatsApp",
        processIdentifier: pid_t? = 4242,
        snapshot: SourceContextSnapshot?
    ) -> SelectionContext {
        SelectionContext(
            text: text,
            sourceApp: AppIdentity(bundleIdentifier: bundleIdentifier, localizedName: "WhatsApp", processIdentifier: processIdentifier),
            sourceContextSnapshot: snapshot
        )
    }

    /// 1 & 6: a valid early snapshot (participant resolved while frontmost) wins over late
    /// resolution, which here deliberately returns something empty/weaker to prove precedence.
    func testValidSnapshotTakesPrecedenceOverLateResolution() async {
        let coordinator = makeCoordinator(lateResolverContext: IntentSourceContext(selectedText: "late"))
        let context = await coordinator.resolveSourceContext(
            for: selection(snapshot: snapshot(participant: "Cherry"))
        )
        XCTAssertEqual(context.oneOnOneParticipant, "Cherry")
        XCTAssertEqual(context.direction, .outgoing)
    }

    /// 2: even if late resolution would come back empty (the WhatsApp-backgrounded case), the
    /// early snapshot's participant still reaches the final source context.
    func testLateResolverReturningNilStillYieldsSnapshotParticipant() async {
        let coordinator = makeCoordinator(lateResolverContext: IntentSourceContext(selectedText: "Let's connect tomorrow at 8am"))
        let context = await coordinator.resolveSourceContext(
            for: selection(snapshot: snapshot(participant: "Cherry"))
        )
        XCTAssertEqual(context.oneOnOneParticipant, "Cherry", "early snapshot must not be overwritten by empty late context")
    }

    /// 3: a snapshot resolved for one selection's text must never be consumed for another's.
    func testSnapshotForADifferentSelectionTextIsRejected() async {
        let coordinator = makeCoordinator(lateResolverContext: IntentSourceContext(conversationTitle: "LATE-RESOLVED", selectedText: "different text"))
        let mismatched = snapshot(participant: "Cherry", selectedText: "Let's connect tomorrow at 8am")
        let context = await coordinator.resolveSourceContext(
            for: selection(text: "different text", snapshot: mismatched)
        )
        XCTAssertNil(context.oneOnOneParticipant)
        XCTAssertEqual(context.conversationTitle, "LATE-RESOLVED", "must fall back to late resolution, not use the foreign snapshot")
    }

    /// 4: a snapshot older than the TTL is discarded even though everything else about it matches.
    func testExpiredSnapshotIsRejected() async {
        let coordinator = makeCoordinator(lateResolverContext: IntentSourceContext(conversationTitle: "LATE-RESOLVED", selectedText: "Let's connect tomorrow at 8am"))
        let stale = snapshot(capturedAt: Date().addingTimeInterval(-(ttl + 5)))
        let context = await coordinator.resolveSourceContext(for: selection(snapshot: stale))
        XCTAssertNil(context.oneOnOneParticipant)
        XCTAssertEqual(context.conversationTitle, "LATE-RESOLVED")
    }

    /// 5: a snapshot resolved for a different app (bundle identifier) is never trusted, even with
    /// matching text — e.g. two apps happening to have identical selected text.
    func testBundleIdentifierMismatchRejectsSnapshot() async {
        let coordinator = makeCoordinator(lateResolverContext: IntentSourceContext(conversationTitle: "LATE-RESOLVED", selectedText: "Let's connect tomorrow at 8am"))
        let foreign = snapshot(bundleIdentifier: "com.google.Chrome")
        let context = await coordinator.resolveSourceContext(
            for: selection(bundleIdentifier: "net.whatsapp.WhatsApp", snapshot: foreign)
        )
        XCTAssertNil(context.oneOnOneParticipant)
        XCTAssertEqual(context.conversationTitle, "LATE-RESOLVED")
    }

    /// PID protection: same bundle identifier, different process — e.g. a relaunch between
    /// snapshot capture and consumption — must also reject.
    func testProcessIdentifierMismatchRejectsSnapshot() async {
        let coordinator = makeCoordinator(lateResolverContext: IntentSourceContext(conversationTitle: "LATE-RESOLVED", selectedText: "Let's connect tomorrow at 8am"))
        let differentProcess = snapshot(sourcePID: 999)
        let context = await coordinator.resolveSourceContext(
            for: selection(processIdentifier: 4242, snapshot: differentProcess)
        )
        XCTAssertNil(context.oneOnOneParticipant)
        XCTAssertEqual(context.conversationTitle, "LATE-RESOLVED")
    }

    /// No snapshot at all (e.g. an app the early resolver never runs for) — unchanged late-
    /// resolution behavior, same as before this mechanism existed.
    func testNoSnapshotFallsBackToLateResolution() async {
        let coordinator = makeCoordinator(lateResolverContext: IntentSourceContext(conversationTitle: "LATE-RESOLVED", selectedText: "Let's connect tomorrow at 8am"))
        let context = await coordinator.resolveSourceContext(for: selection(snapshot: nil))
        XCTAssertEqual(context.conversationTitle, "LATE-RESOLVED")
    }
}

private actor NoIntentParser: IntentParsing {
    func parseIntent(from text: String, context: IntentParsingContext) async throws -> IntentParseResult {
        .noIntent()
    }
}

private actor MemoryIntentRepository: IntentRepository {
    private var intents: [CapturedIntent] = []
    func save(_ intent: CapturedIntent) async throws { intents.append(intent) }
    func fetchAll() async throws -> [CapturedIntent] { intents }
    func update(_ intent: CapturedIntent) async throws {}
    func delete(id: UUID) async throws {}
}

private struct StubSourceContextResolver: SourceContextResolving {
    let context: IntentSourceContext
    func resolve(from selection: SelectionContext) async -> IntentSourceContext { context }
}
