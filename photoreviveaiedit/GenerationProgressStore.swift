import Combine
import SwiftUI
import UIKit

enum GenerationProgressContentKind: String {
    case image
    case video

    var historyKind: MeHistoryKind {
        switch self {
        case .image: .photo
        case .video: .video
        }
    }
}

enum GenerationProgressState {
    case submitting
    case processing
    case completed(URL)
    case failed(String)

    var needsHistoryRefresh: Bool {
        switch self {
        case .submitting, .processing, .completed:
            true
        case .failed:
            false
        }
    }
}

struct GenerationProgressRecord: Identifiable {
    let id: UUID
    let kind: GenerationProgressContentKind
    let title: String
    let subtitle: String
    let previewImage: UIImage?
    let createdAt: Date
    var serverTaskID: String?
    var state: GenerationProgressState
}

/// Owns both the work and its optimistic My Creations record. A record is
/// created before upload begins, so leaving and re-entering My Creations never
/// makes an in-flight image or video appear to have been lost.
@MainActor
final class BackgroundGenerationWorkStore: ObservableObject {
    static let shared = BackgroundGenerationWorkStore()

    @Published private(set) var records: [GenerationProgressRecord] = []
    private var tasks: [UUID: Task<Void, Never>] = [:]

    @discardableResult
    func register(
        kind: GenerationProgressContentKind,
        title: String,
        subtitle: String,
        previewImage: UIImage?,
        serverTaskID: String? = nil
    ) -> UUID {
        let id = UUID()
        records.insert(
            GenerationProgressRecord(
                id: id,
                kind: kind,
                title: title,
                subtitle: subtitle,
                previewImage: previewImage,
                createdAt: Date(),
                serverTaskID: serverTaskID,
                state: serverTaskID == nil ? .submitting : .processing
            ),
            at: 0
        )
        return id
    }

    func start(_ operation: @escaping @MainActor () async -> Void) {
        let id = UUID()
        tasks[id] = Task { @MainActor [weak self] in
            await operation()
            self?.tasks[id] = nil
        }
    }

    func markSubmitted(recordID: UUID?, serverTaskID: String) {
        update(recordID) { record in
            record.serverTaskID = serverTaskID
            record.state = .processing
        }
    }

    func markCompleted(recordID: UUID?, resultURL: URL) {
        update(recordID) { $0.state = .completed(resultURL) }
    }

    func markFailed(recordID: UUID?, message: String) {
        update(recordID) { $0.state = .failed(message) }
    }

    func remove(recordID: UUID) {
        records.removeAll { $0.id == recordID }
    }

    /// Once the same server task appears in history, the server-backed card is
    /// authoritative and replaces the optimistic local card without a gap.
    func reconcile(with historyTasks: [GenerationHistoryTask]) {
        let serverIDs = Set(historyTasks.map(\.id))
        records.removeAll { record in
            guard let serverTaskID = record.serverTaskID else { return false }
            return serverIDs.contains(serverTaskID)
        }
    }

    private func update(
        _ recordID: UUID?,
        mutation: (inout GenerationProgressRecord) -> Void
    ) {
        guard let recordID,
              let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        mutation(&records[index])
    }
}
