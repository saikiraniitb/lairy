import XCTest
@testable import Core
@testable import OpenClip

final class GeminiIntentParserTests: XCTestCase {
    private func makeParser(apiKey: String? = "test-key", transport: any GeminiTransport) -> GeminiIntentParser {
        GeminiIntentParser(
            apiKeyProvider: { apiKey },
            modelProvider: { "gemini-3.8-flash" },
            transport: transport
        )
    }

    /// Wraps a raw JSON-Schema payload string the way the real Gemini API wraps a structured
    /// response: as a text part inside candidates[0].content.parts[0].text.
    private func envelope(_ understandingJSON: String) -> Data {
        let escaped = understandingJSON
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        let json = """
        {"candidates":[{"content":{"parts":[{"text":"\(escaped)"}],"role":"model"}}]}
        """
        return json.data(using: .utf8)!
    }

    /// The exact regression case from the milestone: no fabricated deadline, no invented person,
    /// URL comes from source, and the result is ACTION with responseExpected true.
    func testGoogleChatFigmaReviewRegression() async throws {
        let source = """
        Hi Sir, This is the Updated Jobseeker profile creation flow (Unified Form).
        Please review this flow and let me know if any changes are needed.
        https://www.figma.com/design/example
        """
        let understanding = """
        {"hasTrackableIntent":true,"speechAct":"request","direction":"incoming","actor":"other","owner":"self","requestedAction":"Review the Figma flow and respond with feedback or approval","subject":"Updated Jobseeker profile creation flow (Unified Form)","temporalState":"present","polarity":"positive","commitmentStrength":"requested","deadlineText":"15th Sept 2026","responseExpected":true,"resourceLabels":[{"url":"https://www.figma.com/design/example","label":"Jobseeker profile creation flow"}],"confidence":0.9}
        """
        let transport = FixedGeminiTransport(data: envelope(understanding), statusCode: 200)
        let parser = makeParser(transport: transport)

        let result = try await parser.parseIntent(from: source, context: IntentParsingContext(sourceApplicationName: "Google Chat"))

        guard case .intent(let draft) = result else { return XCTFail("Expected intent, got \(result)") }
        XCTAssertEqual(draft.type, .action)
        XCTAssertNil(draft.deadlineText, "the hallucinated date must be rejected by grounding")
        XCTAssertEqual(draft.resources.first?.type, .figma)
        XCTAssertEqual(draft.resources.first?.url, "https://www.figma.com/design/example")
        XCTAssertTrue(draft.responseExpected == true)
        XCTAssertNil(draft.target, "no person identity is grounded in the source; must never invent one")
    }

    /// The WhatsApp regression case: must not be "no actionable intent", must not invent a date.
    func testWhatsAppSessionRequestRegression() async throws {
        let source = "Hi Rahman, can we have a session at 5pm??"
        let understanding = """
        {"hasTrackableIntent":true,"speechAct":"request","direction":"outgoing","actor":"self","owner":"self","waitingFor":"Rahman","temporalState":"future","polarity":"positive","commitmentStrength":"requested","responseExpected":true,"confidence":0.85}
        """
        let transport = FixedGeminiTransport(data: envelope(understanding), statusCode: 200)
        let parser = makeParser(transport: transport)

        let result = try await parser.parseIntent(from: source, context: IntentParsingContext(sourceApplicationName: "WhatsApp"))

        guard case .intent(let draft) = result else { return XCTFail("Expected intent, got \(result)") }
        XCTAssertTrue(draft.type == .request || draft.type == .waiting)
        XCTAssertNil(draft.deadlineText, "no date was ever mentioned")
        XCTAssertEqual(draft.waitingFor, "Rahman")
    }

    func testNoTrackableIntentReturnsNoIntent() async throws {
        let understanding = #"{"hasTrackableIntent":false,"speechAct":"statement","temporalState":"past","polarity":"positive"}"#
        let transport = FixedGeminiTransport(data: envelope(understanding), statusCode: 200)
        let parser = makeParser(transport: transport)

        let result = try await parser.parseIntent(from: "We crossed a major milestone today.", context: IntentParsingContext())
        guard case .noIntent = result else { return XCTFail("Expected noIntent, got \(result)") }
    }

    func testMissingAPIKeyThrows() async throws {
        let parser = makeParser(apiKey: nil, transport: FixedGeminiTransport(data: Data(), statusCode: 200))
        await XCTAssertThrowsErrorAsync(try await parser.parseIntent(from: "Please review this.", context: IntentParsingContext())) { error in
            XCTAssertEqual(error as? GeminiIntentParserError, .missingAPIKey)
        }
    }

    func testHTTPFailureSurfacesAsError() async throws {
        let transport = FixedGeminiTransport(data: "rate limited".data(using: .utf8)!, statusCode: 429)
        let parser = makeParser(transport: transport)
        await XCTAssertThrowsErrorAsync(try await parser.parseIntent(from: "Please review this.", context: IntentParsingContext())) { error in
            guard case .httpStatus(let code, _) = error as? GeminiIntentParserError else {
                return XCTFail("Expected httpStatus error, got \(error)")
            }
            XCTAssertEqual(code, 429)
        }
    }

    func testEmptySelectionIsNoIntentWithoutNetworkCall() async throws {
        let transport = FixedGeminiTransport(data: Data(), statusCode: 200)
        let parser = makeParser(transport: transport)
        let result = try await parser.parseIntent(from: "   ", context: IntentParsingContext())
        guard case .noIntent = result else { return XCTFail("Expected noIntent") }
        let callCount = await transport.callCount
        XCTAssertEqual(callCount, 0)
    }

    func testUnreadableResponseThrowsInvalidResponse() async throws {
        let transport = FixedGeminiTransport(data: "not json".data(using: .utf8)!, statusCode: 200)
        let parser = makeParser(transport: transport)
        await XCTAssertThrowsErrorAsync(try await parser.parseIntent(from: "Please review this.", context: IntentParsingContext())) { error in
            XCTAssertEqual(error as? GeminiIntentParserError, .invalidResponse)
        }
    }
}

private actor FixedGeminiTransport: GeminiTransport {
    let data: Data
    let statusCode: Int
    private(set) var callCount = 0

    init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        callCount += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
