import Foundation
import Core

public actor FileIntentRepository: IntentRepository {
    public static let shared = FileIntentRepository()

    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)

        let encoder = JSONEncoder()
        // Preserve Date's native Double exactly. Adding the epoch offset before encoding can
        // lose a bit of fractional precision and break preview/save/reload equality.
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.container(keyedBy: StoredDateKey.self)
            try container.encode(date.timeIntervalSinceReferenceDate, forKey: .referenceSeconds)
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            if let keyed = try? decoder.container(keyedBy: StoredDateKey.self),
               let seconds = try keyed.decodeIfPresent(Double.self, forKey: .referenceSeconds) {
                return Date(timeIntervalSinceReferenceDate: seconds)
            }
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: seconds)
            }

            let value = try container.decode(String.self)
            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractionalFormatter.date(from: value) {
                return date
            }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unsupported intent date: \(value)"
                )
            }
            return date
        }
        self.decoder = decoder
    }

    public func save(_ intent: CapturedIntent) async throws {
        var intents = try load()
        guard !intents.contains(where: { $0.id == intent.id }) else {
            throw IntentRepositoryError.duplicateID(intent.id)
        }
        intents.append(intent)
        try persist(intents)
    }

    public func fetchAll() async throws -> [CapturedIntent] {
        let loaded = try load()
        for intent in loaded {
            if let captureID = intent.captureID {
                IntentCaptureTrace.record(stage: "reloaded", captureID: captureID, type: intent.type, sourceContext: intent.sourceContext)
            }
        }
        return loaded.sorted { lhs, rhs in
            if lhs.status == rhs.status {
                return lhs.updatedAt > rhs.updatedAt
            }
            return Self.statusRank(lhs.status) < Self.statusRank(rhs.status)
        }
    }

    public func update(_ intent: CapturedIntent) async throws {
        var intents = try load()
        guard let index = intents.firstIndex(where: { $0.id == intent.id }) else {
            throw IntentRepositoryError.intentNotFound(intent.id)
        }
        intents[index] = intent
        try persist(intents)
    }

    public func delete(id: UUID) async throws {
        var intents = try load()
        guard intents.contains(where: { $0.id == id }) else {
            throw IntentRepositoryError.intentNotFound(id)
        }
        intents.removeAll { $0.id == id }
        try persist(intents)
    }

    private func load() throws -> [CapturedIntent] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        do {
            return try decoder.decode([CapturedIntent].self, from: Data(contentsOf: fileURL))
        } catch {
            throw IntentRepositoryError.invalidStorage
        }
    }

    private func persist(_ intents: [CapturedIntent]) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(intents).write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return support
            .appendingPathComponent("IntentOS", isDirectory: true)
            .appendingPathComponent("intents.json", isDirectory: false)
    }

    private static func statusRank(_ status: IntentStatus) -> Int {
        switch status {
        case .open: return 0
        case .waiting: return 1
        case .done: return 2
        case .cancelled: return 3
        }
    }

    private enum StoredDateKey: String, CodingKey { case referenceSeconds }
}
