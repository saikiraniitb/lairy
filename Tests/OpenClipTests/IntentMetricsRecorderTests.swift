import XCTest
@testable import Core
@testable import OpenClip

final class IntentMetricsRecorderTests: XCTestCase {
    func testMetricSchemaCannotPersistSourceText() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("IntentMetricsTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("metrics.jsonl")
        let recorder = IntentMetricsRecorder(fileURL: file)

        await recorder.record(IntentMetricEvent(
            parser: "needle2-base",
            latencyMilliseconds: 100,
            confidence: 0.2,
            intentClass: .action,
            outcome: .uncertain
        ))

        let persisted = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(persisted.contains("needle2-base"))
        XCTAssertFalse(persisted.contains("sourceText"))
        XCTAssertFalse(persisted.contains("source_text"))
    }
}
