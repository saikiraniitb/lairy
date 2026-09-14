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
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
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
        try load().sorted { lhs, rhs in
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
        case .done: return 1
        case .cancelled: return 2
        }
    }
}
