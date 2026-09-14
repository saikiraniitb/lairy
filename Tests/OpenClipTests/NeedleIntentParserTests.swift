import XCTest
@testable import Core
@testable import OpenClip

final class NeedleIntentParserTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeedleIntentParserTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testHighConfidenceCallBuildsGroundedDraft() async throws {
        let parser = try makeParser(response: """
        {"ok":true,"predicted_intent_type":"do","predicted_fields":{"summary":"Send the revised deck to Rahul","action":"send","object":"revised deck","target":"Rahul","deadline_text":"Friday"},"confidence":0.94,"latency_ms":112.5,"prefill_tps":700,"decode_tps":650,"peak_ram_mb":62,"multiple_calls":false}
        """)
        let source = "I'll send the revised deck to Rahul by Friday."
        let result = try await parser.parseIntent(
            from: source,
            context: IntentParsingContext(
                sourceApplicationName: "Notes",
                sourceApplicationBundleIdentifier: "com.apple.Notes"
            )
        )

        guard case .intent(let draft) = result else { return XCTFail("Expected intent") }
        XCTAssertEqual(draft.type, .doAction)
        XCTAssertEqual(draft.action, "send")
        XCTAssertEqual(draft.object, "revised deck")
        XCTAssertEqual(draft.target, "Rahul")
        XCTAssertEqual(draft.deadlineText, "Friday")
        XCTAssertEqual(draft.sourceText, source)
        XCTAssertEqual(draft.sourceApplicationName, "Notes")
        XCTAssertEqual(draft.parser, "needle2-base")
    }

    func testLowConfidenceCallIsUncertainAndRetainsCandidate() async throws {
        let parser = try makeParser(response: """
        {"ok":true,"predicted_intent_type":"follow_up","predicted_fields":{"summary":"follow up with Priya","action":"follow up","target":"Priya","deadline_text":"Wednesday","trigger":"Finance doesn't approve this"},"confidence":0.21,"latency_ms":90}
        """)

        let result = try await parser.parseIntent(
            from: "If Finance doesn't approve this by Wednesday, follow up with Priya.",
            context: IntentParsingContext()
        )

        guard case .uncertain(let draft, let confidence, _) = result else {
            return XCTFail("Expected uncertain")
        }
        XCTAssertEqual(confidence, 0.21)
        XCTAssertEqual(draft?.type, .followUp)
        XCTAssertEqual(draft?.trigger, "Finance doesn't approve this")
    }

    func testEmptyCallIsNoIntent() async throws {
        let parser = try makeParser(response: """
        {"ok":true,"predicted_intent_type":null,"predicted_fields":{},"confidence":0.91,"latency_ms":75}
        """)

        let result = try await parser.parseIntent(
            from: "The weather is good today.",
            context: IntentParsingContext()
        )
        guard case .noIntent(let diagnostics) = result else { return XCTFail("Expected no intent") }
        XCTAssertEqual(diagnostics?.confidence, 0.91)
    }

    private func makeParser(response: String) throws -> NeedleIntentParser {
        let script = temporaryDirectory.appendingPathComponent("fake-helper.sh")
        let shellResponse = response.replacingOccurrences(of: "'", with: "'\"'\"'")
        let source = """
        printf '%s\\n' '{"type":"ready","parser":"needle2-base","load_ms":1}'
        while IFS= read -r request; do
          printf '%s\\n' '\(shellResponse)'
        done
        """
        try source.write(to: script, atomically: true, encoding: .utf8)
        return NeedleIntentParser(
            confidenceThreshold: 0.75,
            pythonURL: URL(fileURLWithPath: "/bin/sh"),
            helperScriptURL: script
        )
    }
}
