import XCTest
@testable import Core
@testable import OpenClip

final class FileIntentRepositoryTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var repository: FileIntentRepository!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("IntentRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        repository = FileIntentRepository(fileURL: temporaryDirectory.appendingPathComponent("intents.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
        repository = nil
    }

    func testCRUDPersistsAcrossRepositoryInstances() async throws {
        let fileURL = temporaryDirectory.appendingPathComponent("intents.json")
        let draft = IntentDraft(
            type: .action,
            summary: "Review PR 182",
            action: "review",
            object: "PR 182",
            deadlineText: "Friday",
            sourceText: "Review PR 182 Friday.",
            parser: "test"
        )
        var intent = CapturedIntent(draft: draft)
        try await repository.save(intent)

        let reopened = FileIntentRepository(fileURL: fileURL)
        let initiallyPersisted = try await reopened.fetchAll()
        XCTAssertEqual(initiallyPersisted, [intent])

        intent.status = .done
        intent.updatedAt = intent.updatedAt.addingTimeInterval(10)
        try await reopened.update(intent)
        let updatedIntents = try await repository.fetchAll()
        XCTAssertEqual(updatedIntents.first?.status, .done)

        try await repository.delete(id: intent.id)
        let remainingIntents = try await reopened.fetchAll()
        XCTAssertEqual(remainingIntents, [])
    }

    func testDuplicateAndMissingIDsAreRejected() async throws {
        let intent = CapturedIntent(
            type: .remember,
            summary: "Acme prefers annual contracts",
            sourceText: "Remember that Acme prefers annual contracts.",
            parser: "test"
        )
        try await repository.save(intent)
        await XCTAssertThrowsErrorAsync(try await repository.save(intent)) { error in
            XCTAssertEqual(error as? IntentRepositoryError, .duplicateID(intent.id))
        }
        await XCTAssertThrowsErrorAsync(try await repository.delete(id: UUID())) { error in
            guard case .intentNotFound = error as? IntentRepositoryError else {
                return XCTFail("Expected intentNotFound, got \(error)")
            }
        }
    }

    func testReadsLegacyISO8601Dates() async throws {
        let fileURL = temporaryDirectory.appendingPathComponent("intents.json")
        let intent = CapturedIntent(
            type: .remember,
            summary: "Acme prefers annual contracts",
            sourceText: "Remember that Acme prefers annual contracts.",
            parser: "test",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let legacyEncoder = JSONEncoder()
        legacyEncoder.dateEncodingStrategy = .iso8601
        try legacyEncoder.encode([intent]).write(to: fileURL)

        let persisted = try await repository.fetchAll()
        XCTAssertEqual(persisted, [intent])
    }

    /// Records written before the Gemini-era taxonomy (action/request/waiting/remember) used
    /// "do" and "follow_up" for `type`. They must keep decoding rather than corrupting the whole
    /// store — see `IntentType.resolve(rawValue:)`.
    func testReadsLegacyIntentTypeRawValues() async throws {
        let fileURL = temporaryDirectory.appendingPathComponent("intents.json")
        let legacyJSON = """
        [
          {
            "id": "5F1B2B2E-9B5B-4B9B-8B9B-000000000001",
            "type": "do",
            "status": "open",
            "summary": "Send the deck",
            "sourceText": "I'll send the deck.",
            "parser": "test",
            "createdAt": 1800000000,
            "updatedAt": 1800000000
          },
          {
            "id": "5F1B2B2E-9B5B-4B9B-8B9B-000000000002",
            "type": "follow_up",
            "status": "open",
            "summary": "Waiting on Priya",
            "sourceText": "Once Priya confirms, send the deck.",
            "parser": "test",
            "createdAt": 1800000000,
            "updatedAt": 1800000000
          }
        ]
        """
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try legacyJSON.data(using: .utf8)!.write(to: fileURL)

        let persisted = try await repository.fetchAll()
        XCTAssertEqual(persisted.count, 2)
        XCTAssertEqual(persisted.first { $0.summary == "Send the deck" }?.type, .action)
        XCTAssertEqual(persisted.first { $0.summary == "Waiting on Priya" }?.type, .waiting)
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
