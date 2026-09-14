import Foundation
import Core

@MainActor
public final class IntentInboxStore: ObservableObject {
    public static let shared = IntentInboxStore(repository: FileIntentRepository.shared)

    @Published public private(set) var intents: [CapturedIntent] = []
    @Published public var selectedID: UUID?
    @Published public var errorMessage: String?
    private let repository: any IntentRepository
    private let metrics: IntentMetricsRecorder

    public init(repository: any IntentRepository, metrics: IntentMetricsRecorder = .shared) {
        self.repository = repository
        self.metrics = metrics
    }

    public var selectedIntent: CapturedIntent? {
        intents.first { $0.id == selectedID }
    }

    public func intents(with status: IntentStatus) -> [CapturedIntent] {
        intents.filter { $0.status == status }
    }

    public func reload() async {
        do {
            intents = try await repository.fetchAll()
            if let selectedID, !intents.contains(where: { $0.id == selectedID }) {
                self.selectedID = nil
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func setStatus(_ status: IntentStatus, for id: UUID) {
        guard var intent = intents.first(where: { $0.id == id }) else { return }
        intent.status = status
        intent.updatedAt = Date()
        Task { @MainActor in
            do {
                try await repository.update(intent)
                await reload()
                let outcome: IntentMetricEvent.Outcome
                switch status {
                case .open: outcome = .reopened
                case .done: outcome = .markedDone
                case .cancelled: outcome = .cancelled
                }
                await metrics.record(IntentMetricEvent(
                    parser: intent.parser,
                    confidence: intent.parserConfidence,
                    intentClass: intent.type,
                    outcome: outcome
                ))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func delete(_ id: UUID) {
        Task { @MainActor in
            do {
                let deleted = intents.first { $0.id == id }
                try await repository.delete(id: id)
                selectedID = nil
                await reload()
                await metrics.record(IntentMetricEvent(
                    parser: deleted?.parser ?? "unknown",
                    confidence: deleted?.parserConfidence,
                    intentClass: deleted?.type,
                    outcome: .deleted
                ))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

