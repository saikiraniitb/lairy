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

    // MARK: - Source context enrichment (real case: trusted sender vs. @mention)

    private let realCaseSource = """
    Hi @Sai Kiran Cherakam Sir, This is the updated landing page for Employer with our latest \
    color pallet. Please have a look and let me know any changes that need to be made. Thankyou
    """

    /// The real case from the source-context milestone: Gemini (incorrectly) proposes the
    /// @mention as requestedBy/target; the trusted sender must win regardless, and the mention
    /// must never survive as a target either.
    func testRealCaseTrustedSenderWinsOverMention() async throws {
        let understanding = """
        {"hasTrackableIntent":true,"speechAct":"request","direction":"incoming","actor":"other","owner":"self","requestedAction":"Review the landing page and provide feedback","subject":"updated landing page for Employer","requestedBy":"Sai Kiran Cherakam","temporalState":"present","polarity":"positive","commitmentStrength":"requested","responseExpected":true,"confidence":0.9}
        """
        let transport = FixedGeminiTransport(data: envelope(understanding), statusCode: 200)
        let parser = makeParser(transport: transport)
        let sourceContext = IntentSourceContext(
            applicationName: "Google Chat",
            sender: "Sai Siddeeswara Naidu Gurram",
            conversationTitle: "Sai Siddeeswara Naidu Gurram",
            direction: .incoming,
            selectedText: realCaseSource
        )
        let context = IntentParsingContext(sourceApplicationName: "Google Chat", sourceContext: sourceContext)

        let result = try await parser.parseIntent(from: realCaseSource, context: context)

        guard case .intent(let draft) = result else { return XCTFail("Expected intent, got \(result)") }
        XCTAssertEqual(draft.type, .action)
        XCTAssertEqual(draft.requestedBy, "Sai Siddeeswara Naidu Gurram", "the trusted sender must win, never the @mention")
        XCTAssertNil(draft.deadlineText)
    }

    /// Trusted direction overrides whatever the model itself guessed.
    func testTrustedDirectionOverridesModelGuess() async throws {
        // The model wrongly proposes outgoing; trusted context says incoming.
        let understanding = """
        {"hasTrackableIntent":true,"speechAct":"request","direction":"outgoing","actor":"self","owner":"self","requestedAction":"Review the landing page","confidence":0.8}
        """
        let transport = FixedGeminiTransport(data: envelope(understanding), statusCode: 200)
        let parser = makeParser(transport: transport)
        let sourceContext = IntentSourceContext(sender: "Sai Siddeeswara Naidu Gurram", direction: .incoming, selectedText: realCaseSource)
        let context = IntentParsingContext(sourceContext: sourceContext)

        let result = try await parser.parseIntent(from: realCaseSource, context: context)
        guard case .intent(let draft) = result else { return XCTFail("Expected intent, got \(result)") }
        // Incoming + owner=self => ACTION (would have been REQUEST/ambiguous had outgoing won).
        XCTAssertEqual(draft.type, .action)
    }

    /// The request payload actually carries the trusted CONTEXT block ahead of the selected text,
    /// and never includes anything beyond the one selected message + its trusted metadata.
    func testRequestPayloadIncludesTrustedContext() async throws {
        let understanding = #"{"hasTrackableIntent":false,"speechAct":"statement","temporalState":"present","polarity":"positive"}"#
        let transport = FixedGeminiTransport(data: envelope(understanding), statusCode: 200)
        let parser = makeParser(transport: transport)
        let sourceContext = IntentSourceContext(sender: "Ravi Kumar", direction: .incoming, selectedText: "Please review this.")
        _ = try await parser.parseIntent(from: "Please review this.", context: IntentParsingContext(sourceContext: sourceContext))

        let body = await transport.lastRequestBodyString
        XCTAssertTrue(body?.contains("CONTEXT:") == true)
        XCTAssertTrue(body?.contains("Ravi Kumar") == true)
        XCTAssertTrue(body?.contains("SELECTED TEXT:") == true)
    }

    /// No source context at all -> no CONTEXT block, just the plain text (unchanged behavior).
    func testNoSourceContextOmitsContextBlock() async throws {
        let understanding = #"{"hasTrackableIntent":false,"speechAct":"statement","temporalState":"present","polarity":"positive"}"#
        let transport = FixedGeminiTransport(data: envelope(understanding), statusCode: 200)
        let parser = makeParser(transport: transport)
        _ = try await parser.parseIntent(from: "Please review this.", context: IntentParsingContext())

        let body = await transport.lastRequestBodyString
        XCTAssertFalse(body?.contains("CONTEXT:") == true)
    }
}

private actor FixedGeminiTransport: GeminiTransport {
    let data: Data
    let statusCode: Int
    private(set) var callCount = 0
    private(set) var lastRequestBodyString: String?

    init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        callCount += 1
        lastRequestBodyString = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
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
