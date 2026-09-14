import XCTest
@testable import Core
@testable import OpenClip

@MainActor
final class IntentCaptureActionTests: XCTestCase {
    func testCaptureIntentRequiresExplicitLiveSelection() {
        let coordinator = IntentCaptureCoordinator(
            parser: NoIntentParser(),
            repository: MemoryIntentRepository()
        )
        let action = CaptureIntentAction(coordinator: coordinator)
        let live = ActionContext(selection: SelectionContext(text: "Review PR 182 tomorrow."))
        let clipboard = ActionContext(selection: SelectionContext(
            text: "Review PR 182 tomorrow.",
            isClipboardFallback: true
        ))
        let empty = ActionContext(selection: SelectionContext(text: "  \n"))

        XCTAssertTrue(action.isEnabled(for: live))
        XCTAssertFalse(action.isEnabled(for: clipboard))
        XCTAssertFalse(action.isEnabled(for: empty))
        XCTAssertTrue(action.chrome.requiresLiveSelection)
        XCTAssertTrue(action.chrome.showsLoading)
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
