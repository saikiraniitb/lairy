import Foundation

public protocol IntentRepository: Sendable {
    func save(_ intent: CapturedIntent) async throws
    func fetchAll() async throws -> [CapturedIntent]
    func update(_ intent: CapturedIntent) async throws
    func delete(id: UUID) async throws
}

public enum IntentRepositoryError: Error, Equatable, Sendable {
    case duplicateID(UUID)
    case intentNotFound(UUID)
    case invalidStorage
}

