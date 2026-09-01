import Foundation

actor DefaultSyncRepository: SyncRepository {
    private let engine: RelaySyncEngine
    let activityStore: SyncActivityStore
    private let pollingCoordinator = RelayPollingCoordinator()

    init(engine: RelaySyncEngine, activityStore: SyncActivityStore) {
        self.engine = engine
        self.activityStore = activityStore
    }

    func startPolling() async {
        await pollingCoordinator.start(
            pollingIntervalProvider: { [activityStore] in
                await MainActor.run {
                    activityStore.preferredPollingIntervalSeconds
                }
            },
            fetchOperation: { [engine, activityStore] in
                await MainActor.run { activityStore.beginFetch() }
                do {
                    try await engine.syncNow()
                    await MainActor.run { activityStore.endFetch(succeeded: true) }
                    return true
                } catch {
                    await MainActor.run {
                        activityStore.endFetch(succeeded: false, errorMessage: error.localizedDescription)
                    }
                    return false
                }
            }
        )
    }

    func stopPolling() async {
        await pollingCoordinator.stop()
    }

    func requestImmediateSync(reason: SyncReason) async {
        await pollingCoordinator.requestImmediatePoll()
    }

    func refreshNow() async throws {
        await MainActor.run { activityStore.beginFetch() }
        do {
            try await engine.syncNow()
            await MainActor.run { activityStore.endFetch(succeeded: true) }
        } catch {
            await MainActor.run {
                activityStore.endFetch(succeeded: false, errorMessage: error.localizedDescription)
            }
            throw error
        }
    }

    func sendMessage(_ text: String, attachments: [DraftAttachment] = [], to sessionID: SessionID) async throws {
        await MainActor.run { activityStore.markOutgoingSend() }
        try await engine.sendMessage(text, attachments: attachments, to: sessionID)
    }

    func sendApprovalResponse(approvalID: String, decision: String, to sessionID: SessionID) async throws {
        await MainActor.run { activityStore.markOutgoingSend() }
        try await engine.sendApprovalResponse(approvalID: approvalID, decision: decision, to: sessionID)
    }

    func sendExistingLocalMessage(_ text: String, messageID: MessageID, to sessionID: SessionID) async throws {
        await MainActor.run { activityStore.markOutgoingSend() }
        try await engine.sendExistingLocalMessage(text, messageID: messageID, to: sessionID)
    }

    func sendExistingLocalMessage(messageID: MessageID, to sessionID: SessionID) async throws {
        await MainActor.run { activityStore.markOutgoingSend() }
        try await engine.sendExistingLocalMessage(messageID: messageID, to: sessionID)
    }

    func backfill(sessionID: SessionID, limit: Int) async throws {
        try await engine.backfill(sessionID: sessionID, limit: limit)
    }
}
