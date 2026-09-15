import XCTest
@testable import Core
@testable import OpenClip

final class GeminiIntentParserTests: XCTestCase {
    func testExactOriginalSelectionSurvivesNormalization() async throws {
        let source = "  Please review this tomorrow\n\n"
        let wire = #"{"hasTrackableIntent":true,"speechAct":"request","direction":"incoming","requestedAction":"Review this","deadlineText":"tomorrow","confidence":0.9}"#
        let parser = makeParser(transport: FixedGeminiTransport(data: envelope(wire), statusCode: 200))
        let context = IntentParsingContext(sourceContext: IntentSourceContext(sender: "Shreya", direction: .incoming, selectedText: source))
        guard case .intent(let draft) = try await parser.parseIntent(from: source, context: context) else { return XCTFail("Expected ACTION") }
        XCTAssertEqual(draft.sourceText, source)
        XCTAssertEqual(draft.type, .action)
        XCTAssertEqual(draft.requestedBy, "Shreya")
        XCTAssertNotNil(draft.dueAt)
        XCTAssertEqual(CapturedIntent(draft: draft).sourceContext, context.sourceContext)
    }
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

    /// The real Google Chat "Product Team" space regression: the user's own selection spans their
    /// outgoing "Coding Assessment" message plus Shreya's own reply bubble (sender label + inline
    /// rendered timestamp included, exactly as the real AX-extracted selection carried them) —
    /// must become WAITING for Shreya, subject "Coding Assessment", no deadline, and critically
    /// must NOT surface the embedded "26 Aug, 10:29" message timestamp as a mentioned time.
    func testGoogleChatCodingAssessmentWaitingRegression() async throws {
        let source = """
        Coding Assessment
        Questions should be generated by using JD
        Key params in the JD are Exp section, Job Title
        There will be three questions
        Duration of the assessment is max one hr but this can customised
        Questions will be dynamically generated (but in future it'll be question Bank)

        These are the changes discussed with pavan
        so please update the doc accordingly
        Shreya Guptha Vutukuri, 26 Aug, 10:29
        okay i will update
        """
        let understanding = """
        {"hasTrackableIntent":true,"speechAct":"request","direction":"outgoing","actor":"other","owner":"other","requestedAction":"update the doc accordingly","requestedOutcome":"Update the Coding Assessment document","subject":"Coding Assessment","waitingFor":"Shreya Guptha Vutukuri","temporalState":"future","polarity":"positive","commitmentStrength":"requested","responseExpected":false,"confidence":0.95}
        """
        let transport = FixedGeminiTransport(data: envelope(understanding), statusCode: 200)
        let parser = makeParser(transport: transport)
        // A group space, not a 1:1 — no oneOnOneParticipant available; waitingFor must ground
        // from the sender label present in the selected text itself instead.
        let sourceContext = IntentSourceContext(direction: .outgoing, selectedText: source)
        let context = IntentParsingContext(sourceApplicationName: "Google Chat", sourceContext: sourceContext)

        let result = try await parser.parseIntent(from: source, context: context)

        guard case .intent(let draft) = result else { return XCTFail("Expected intent, got \(result)") }
        XCTAssertEqual(draft.type, .waiting)
        XCTAssertEqual(draft.waitingFor, "Shreya Guptha Vutukuri")
        XCTAssertEqual(draft.subject, "Coding Assessment")
        XCTAssertEqual(draft.summary, "Update the Coding Assessment document")
        XCTAssertNil(draft.deadlineText)
        XCTAssertNil(draft.dueAt)
        XCTAssertNil(draft.eventAt)
        XCTAssertNil(draft.followUpAt)
        XCTAssertNil(draft.unresolvedTimeText, "the embedded '26 Aug, 10:29' timestamp must never become a follow-up prompt")
        XCTAssertEqual(draft.sourceText, source, "Original Source must preserve exactly what was selected, reply included")
    }

    /// The real WhatsApp "Cherry" regression: an outgoing meeting proposal in a real 1:1, with the
    /// provider's own (wrong) guess of direction=incoming/actor=group exactly as Gemini returned it
    /// live — the trusted 1:1 participant must correct direction and ground waitingFor, and the
    /// grounded time must land as an event, never a due date or a bare "connect" ACTION.
    func testWhatsAppConnectWithCherryBecomesWaitingWithEventTime() async throws {
        let source = "Let's connect tomorrow at 8am"
        let understanding = """
        {"hasTrackableIntent":true,"speechAct":"request","direction":"incoming","actor":"group","owner":"shared","commitmentStrength":"suggested","deadlineText":"tomorrow at 8am","requestedAction":"connect","subject":"connect","temporalState":"future","polarity":"positive","responseExpected":true,"confidence":0.9}
        """
        let transport = FixedGeminiTransport(data: envelope(understanding), statusCode: 200)
        let parser = makeParser(transport: transport)
        let sourceContext = IntentSourceContext(
            conversationTitle: "Cherry",
            oneOnOneParticipant: "Cherry",
            direction: .outgoing,
            selectedText: source
        )
        let context = IntentParsingContext(
            sourceApplicationName: "WhatsApp",
            sourceApplicationBundleIdentifier: "net.whatsapp.WhatsApp",
            sourceContext: sourceContext
        )

        let result = try await parser.parseIntent(from: source, context: context)

        guard case .intent(let draft) = result else { return XCTFail("Expected intent, got \(result)") }
        XCTAssertEqual(draft.type, .waiting, "an outgoing proposal to a known 1:1 participant is WAITING, never a self-owned ACTION")
        XCTAssertEqual(draft.waitingFor, "Cherry")
        XCTAssertNil(draft.deadlineText)
        XCTAssertNil(draft.deadline)
        XCTAssertNil(draft.dueAt, "a proposed meeting time is an event, never a deadline")
        XCTAssertNotNil(draft.eventAt, "When: Tomorrow, 8:00 AM must be set")
        XCTAssertEqual(draft.eventAt?.hasTime, true)
        XCTAssertNil(draft.followUpAt)

        // Preview -> Track -> repository -> reload: nothing about type/waitingFor/eventAt may
        // shift once the draft becomes a persisted CapturedIntent and round-trips through the
        // exact JSON encoding FileIntentRepository uses on disk.
        let captured = CapturedIntent(draft: draft)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let reloaded = try decoder.decode(CapturedIntent.self, from: encoder.encode(captured))
        XCTAssertEqual(reloaded.type, .waiting)
        XCTAssertEqual(reloaded.waitingFor, "Cherry")
        XCTAssertNotNil(reloaded.eventAt)
        XCTAssertEqual(reloaded.eventAt?.hasTime, true)
        XCTAssertNil(reloaded.dueAt)
        XCTAssertNil(reloaded.deadline)
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

    // MARK: - Google Chat: outgoing 1:1 request, timestamp safety, group chats (A-E)

    private let shreyaMessage = """
    Coding Assessment
    Questions should be generated by using JD
    Key params in the JD are Exp section, Job Title
    There will be three questions
    Duration of the assessment is max one hr but this can customised
    Questions will be dynamically generated (but in future it'll be question Bank)

    These are the changes discussed with pavan

    so please update the doc accordingly
    """

    /// A) Outgoing 1:1 request: the real case. Must be WAITING/REQUEST with waitingFor=Shreya,
    /// never ACTION owned by self, even though the model is not given a waitingFor of its own.
    func testOutgoing1to1RequestRegression() async throws {
        let understanding = """
        {"hasTrackableIntent":true,"speechAct":"instruction","direction":"outgoing","actor":"self","owner":"self","requestedAction":"Update the Coding Assessment document with the discussed changes","subject":"Coding Assessment document","temporalState":"present","polarity":"positive","commitmentStrength":"requested","confidence":0.85}
        """
        let transport = FixedGeminiTransport(data: envelope(understanding), statusCode: 200)
        let parser = makeParser(transport: transport)
        let sourceContext = IntentSourceContext(
            applicationName: "Google Chat",
            conversationTitle: "Shreya Guptha Vutukuri",
            oneOnOneParticipant: "Shreya Guptha Vutukuri",
            timestampText: "26 Aug, 10:27",
            direction: .outgoing,
            selectedText: shreyaMessage
        )
        let context = IntentParsingContext(sourceApplicationName: "Google Chat", sourceContext: sourceContext)

        let result = try await parser.parseIntent(from: shreyaMessage, context: context)

        guard case .intent(let draft) = result else { return XCTFail("Expected intent, got \(result)") }
        XCTAssertTrue(draft.type == .waiting || draft.type == .request, "expected WAITING/REQUEST, got \(draft.type)")
        XCTAssertNotEqual(draft.type, .action, "must never be ACTION owned by self")
        XCTAssertEqual(draft.waitingFor, "Shreya Guptha Vutukuri")
        XCTAssertNil(draft.deadlineText, "the visible message timestamp must never become a deadline")
    }

    /// B) Incoming request: mirror case, ACTION owned by self with requestedBy=sender.
    func testIncomingRequestRegression() async throws {
        let understanding = """
        {"hasTrackableIntent":true,"speechAct":"instruction","direction":"incoming","actor":"other","owner":"self","requestedAction":"Update the document","confidence":0.85}
        """
        let transport = FixedGeminiTransport(data: envelope(understanding), statusCode: 200)
        let parser = makeParser(transport: transport)
        let sourceContext = IntentSourceContext(sender: "Shreya Guptha Vutukuri", direction: .incoming, selectedText: "Please update the document.")
        let context = IntentParsingContext(sourceContext: sourceContext)

        let result = try await parser.parseIntent(from: "Please update the document.", context: context)

        guard case .intent(let draft) = result else { return XCTFail("Expected intent, got \(result)") }
        XCTAssertEqual(draft.type, .action)
        XCTAssertEqual(draft.requestedBy, "Shreya Guptha Vutukuri")
    }

    /// C) The visible message timestamp must never become a deadline when the selected text
    /// itself contains no temporal phrase — even if the model (mis)behaves and echoes it back.
    func testMessageTimestampNeverBecomesDeadline() async throws {
        let understanding = """
        {"hasTrackableIntent":true,"speechAct":"instruction","direction":"outgoing","actor":"self","owner":"self","requestedAction":"Update the doc","deadlineText":"26 Aug","confidence":0.8}
        """
        let transport = FixedGeminiTransport(data: envelope(understanding), statusCode: 200)
        let parser = makeParser(transport: transport)
        let sourceContext = IntentSourceContext(
            oneOnOneParticipant: "Shreya Guptha Vutukuri",
            timestampText: "26 Aug, 10:27",
            direction: .outgoing,
            selectedText: "so please update the doc accordingly"
        )
        let context = IntentParsingContext(sourceContext: sourceContext)

        let result = try await parser.parseIntent(from: "so please update the doc accordingly", context: context)

        guard case .intent(let draft) = result else { return XCTFail("Expected intent, got \(result)") }
        XCTAssertNil(draft.deadlineText, "26 Aug never appeared in the selected text, only in message_timestamp metadata")
        XCTAssertNil(draft.dueAt)
        XCTAssertNil(draft.eventAt)
    }

    /// D) Group chat, no reliable sender: must never infer a person from the group's title.
    func testGroupChatUnknownSenderNeverInfersFromConversationTitle() async throws {
        let understanding = """
        {"hasTrackableIntent":true,"speechAct":"request","direction":"unknown","actor":"other","owner":"self","requestedAction":"Update the doc","waitingFor":"Engineering Team","confidence":0.7}
        """
        let transport = FixedGeminiTransport(data: envelope(understanding), statusCode: 200)
        let parser = makeParser(transport: transport)
        // A group chat's title is not a person's name, so the resolver would never set
        // oneOnOneParticipant for it — simulated directly here.
        let sourceContext = IntentSourceContext(conversationTitle: "Engineering Team", direction: .unknown, selectedText: "Can someone update the doc?")
        let context = IntentParsingContext(sourceContext: sourceContext)

        let result = try await parser.parseIntent(from: "Can someone update the doc?", context: context)

        guard case .intent(let draft) = result else { return XCTFail("Expected intent, got \(result)") }
        XCTAssertNil(draft.waitingFor, "must never infer a person from a group chat's title")
    }

    /// E) An @mention inside the message must never override trusted sender/conversation
    /// metadata — for both requestedBy (incoming) and waitingFor (outgoing 1:1).
    func testMentionNeverOverridesTrustedMetadataEitherDirection() async throws {
        // Outgoing: model latches onto some other name mentioned in the text as waitingFor.
        let outgoingUnderstanding = """
        {"hasTrackableIntent":true,"speechAct":"instruction","direction":"outgoing","actor":"self","owner":"self","requestedAction":"Update the doc","waitingFor":"Pavan","confidence":0.8}
        """
        let outgoingTransport = FixedGeminiTransport(data: envelope(outgoingUnderstanding), statusCode: 200)
        let outgoingParser = makeParser(transport: outgoingTransport)
        let outgoingContext = IntentParsingContext(sourceContext: IntentSourceContext(
            oneOnOneParticipant: "Shreya Guptha Vutukuri",
            direction: .outgoing,
            selectedText: shreyaMessage
        ))
        let outgoingResult = try await outgoingParser.parseIntent(from: shreyaMessage, context: outgoingContext)
        guard case .intent(let outgoingDraft) = outgoingResult else { return XCTFail("Expected intent") }
        XCTAssertEqual(outgoingDraft.waitingFor, "Shreya Guptha Vutukuri", "the trusted 1:1 participant must win over a name mentioned in the text")

        // Incoming: model latches onto the @mention as requestedBy (covered again here for
        // symmetry with the outgoing case above).
        let incomingUnderstanding = """
        {"hasTrackableIntent":true,"speechAct":"request","direction":"incoming","actor":"other","owner":"self","requestedAction":"Review the landing page","requestedBy":"Sai Kiran Cherakam","confidence":0.9}
        """
        let incomingTransport = FixedGeminiTransport(data: envelope(incomingUnderstanding), statusCode: 200)
        let incomingParser = makeParser(transport: incomingTransport)
        let realCase = """
        Hi @Sai Kiran Cherakam Sir, This is the updated landing page for Employer with our latest \
        color pallet. Please have a look and let me know any changes that need to be made.
        """
        let incomingContext = IntentParsingContext(sourceContext: IntentSourceContext(
            sender: "Sai Siddeeswara Naidu Gurram",
            direction: .incoming,
            selectedText: realCase
        ))
        let incomingResult = try await incomingParser.parseIntent(from: realCase, context: incomingContext)
        guard case .intent(let incomingDraft) = incomingResult else { return XCTFail("Expected intent") }
        XCTAssertEqual(incomingDraft.requestedBy, "Sai Siddeeswara Naidu Gurram", "the trusted sender must win over the @mention")
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
