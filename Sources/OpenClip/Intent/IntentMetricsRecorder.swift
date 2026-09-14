import Foundation
import Core

public struct IntentMetricEvent: Codable, Sendable {
    public enum Outcome: String, Codable, Sendable {
        case parsed
        case noIntent = "no_intent"
        case uncertain
        case accepted
        case edited
        case ignored
        case cloudFallbackRequested = "cloud_fallback_requested"
        case inboxOpened = "inbox_opened"
        case markedDone = "marked_done"
        case reopened
        case cancelled
        case deleted
    }

    public let timestamp: Date
    public let parser: String
    public let latencyMilliseconds: Double?
    public let confidence: Double?
    public let intentClass: IntentType?
    public let outcome: Outcome

    public init(
        timestamp: Date = Date(),
        parser: String,
        latencyMilliseconds: Double? = nil,
        confidence: Double? = nil,
        intentClass: IntentType? = nil,
        outcome: Outcome
    ) {
        self.timestamp = timestamp
        self.parser = parser
        self.latencyMilliseconds = latencyMilliseconds
        self.confidence = confidence
        self.intentClass = intentClass
        self.outcome = outcome
    }
}

/// Local JSONL event sink. Its schema deliberately has no source-text or arbitrary-string field.
public actor IntentMetricsRecorder {
    public static let shared = IntentMetricsRecorder()

    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
            self.fileURL = support
                .appendingPathComponent("IntentOS", isDirectory: true)
                .appendingPathComponent("metrics.jsonl")
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
    }

    public func record(_ event: IntentMetricEvent) {
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var data = try encoder.encode(event)
            data.append(0x0A)
            if !fileManager.fileExists(atPath: fileURL.path) {
                try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
                return
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            Log.intent.error("Failed to persist IntentOS metric: \(error.localizedDescription)")
        }
    }
}
