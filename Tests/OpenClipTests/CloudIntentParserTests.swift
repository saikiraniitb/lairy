import XCTest
@testable import Core
@testable import OpenClip

@MainActor
final class CloudIntentParserTests: XCTestCase {
    func testCloudParserDecodesOneStructuredIntent() async throws {
        let provider = FixedCloudProvider(output: """
        {"type":"follow_up","summary":"send the proposal to Priya","action":"send","object":"proposal","target":"Priya","deadline_text":null,"trigger":"Finance confirms the budget"}
        """)
        let parser = CloudIntentParser(provider: provider, parserName: "cloud.openai")
        let source = "Once Finance confirms the budget, send the proposal to Priya."

        let result = try await parser.parseIntent(
            from: source,
            context: IntentParsingContext(sourceApplicationName: "Safari")
        )

        guard case .intent(let draft) = result else { return XCTFail("Expected intent") }
        XCTAssertEqual(draft.type, .followUp)
        XCTAssertEqual(draft.trigger, "Finance confirms the budget")
        XCTAssertEqual(draft.target, "Priya")
        XCTAssertEqual(draft.sourceText, source)
        XCTAssertEqual(draft.parser, "cloud.openai")
        XCTAssertNil(draft.parserConfidence)
    }

    func testCloudParserAcceptsExplicitNoIntent() async throws {
        let parser = CloudIntentParser(
            provider: FixedCloudProvider(output: "{\"type\":null}"),
            parserName: "cloud.openai"
        )
        let result = try await parser.parseIntent(
            from: "The weather is good today.",
            context: IntentParsingContext()
        )
        guard case .noIntent = result else { return XCTFail("Expected no intent") }
    }
}

@MainActor
private final class FixedCloudProvider: AIProvider {
    let type: AIProviderType = .cloud
    let output: String

    init(output: String) { self.output = output }

    func process(prompt: String, text: String) async throws -> String { output }

    func processStream(prompt: String, text: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(output)
            continuation.finish()
        }
    }
}
