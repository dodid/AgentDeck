import Foundation
import Observation

@MainActor
@Observable
final class ConnectionEditorViewModel {
    let environment: AppEnvironment
    var draft: ConnectionConfig = .empty
    var isWorking = false
    var errorMessage: String?
    var importErrorMessage: String?
    var showBucketChangedAlert = false
    var pendingConfig: ConnectionConfig?

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    var actualErrorMessage: String? {
        importErrorMessage ?? errorMessage
    }

    func verifyAndPrepareSave() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let normalized = normalizedDraft
            try await environment.connectionRepository.verify(normalized)
            let current = try await environment.connectionRepository.loadConnectionConfig() ?? .empty
            if connectivityChanged(from: current, to: normalized) {
                pendingConfig = normalized
                showBucketChangedAlert = true
            } else {
                try await environment.connectionRepository.saveConnectionConfig(normalized)
                errorMessage = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func confirmDestructiveSave() async {
        guard let pendingConfig else { return }
        do {
            try await environment.chatRepository.clearLocalData()
            try await environment.connectionRepository.saveConnectionConfig(pendingConfig)
            self.pendingConfig = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var normalizedDraft: ConnectionConfig {
        ConnectionConfig(
            endpoint: draft.endpoint,
            bucket: draft.bucket,
            accessKeyID: draft.accessKeyID,
            secretAccessKey: draft.secretAccessKey,
            region: draft.region,
            forcePathStyle: true
        )
    }

    private func connectivityChanged(from old: ConnectionConfig, to new: ConnectionConfig) -> Bool {
        old.endpoint != new.endpoint ||
        old.bucket != new.bucket ||
        old.accessKeyID != new.accessKeyID ||
        old.secretAccessKey != new.secretAccessKey
    }
}
