import Foundation

actor RelaySyncEngine {
    private let connectionRepository: ConnectionRepository
    private let deviceRepository: DeviceRepository
    private let chatRepository: DefaultChatRepository
    private let database: AppDatabase

    init(
        connectionRepository: ConnectionRepository,
        deviceRepository: DeviceRepository,
        chatRepository: DefaultChatRepository,
        database: AppDatabase
    ) {
        self.connectionRepository = connectionRepository
        self.deviceRepository = deviceRepository
        self.chatRepository = chatRepository
        self.database = database
    }

    func sendMessage(_ text: String, attachments: [DraftAttachment] = [], to sessionID: SessionID) async throws {
        let localMessageID = try await chatRepository.sendMessageLocally(text, attachments: attachments, to: sessionID)
        guard let localMessageID else { return }
        try await sendExistingLocalMessage(text, messageID: localMessageID, to: sessionID)
    }

    func sendExistingLocalMessage(_ text: String, messageID: MessageID, to sessionID: SessionID) async throws {
        guard let config = try await connectionRepository.loadConnectionConfig() else {
            throw ConnectionRepositoryError.incompleteConfiguration
        }
        let device = try await deviceRepository.loadDeviceProfile()
        guard let target = try database.relaySendTarget(for: sessionID) else {
            throw RelaySyncEngineError.missingSession
        }

        let messaging = RelayMessagingService(config: config)
        let uploader = RelayAttachmentUploadService(config: config)

        do {
            let draftAttachments = try database.draftAttachmentsForMessage(messageID: messageID)
            if !draftAttachments.isEmpty {
                let now = Date().timeIntervalSince1970 * 1000
                let uploadedAttachments = try await uploader.uploadDraftAttachments(
                    draftAttachments,
                    recipient: target.gatewayPeer,
                    messageID: messageID,
                    timestampMS: now
                )
                try database.updateUploadedAttachments(messageID: messageID, attachments: uploadedAttachments)
            }
            let attachments = try database.relayAttachmentsForMessage(messageID: messageID)
            _ = try await messaging.sendMessage(
                from: device.clientID,
                target: target,
                text: text,
                messageID: messageID.rawValue,
                attachments: attachments
            )
            try database.markMessageSent(messageID: messageID)
            await chatRepository.publishTranscript(for: sessionID, limit: 50)
            try await syncNow()
        } catch {
            try? database.markMessageFailed(messageID: messageID, error: error.localizedDescription)
            await chatRepository.publishTranscript(for: sessionID, limit: 50)
            throw error
        }
    }

    func sendApprovalResponse(approvalID: String, decision: String, to sessionID: SessionID) async throws {
        guard let config = try await connectionRepository.loadConnectionConfig() else {
            throw ConnectionRepositoryError.incompleteConfiguration
        }
        let device = try await deviceRepository.loadDeviceProfile()
        guard let target = try database.relaySendTarget(for: sessionID) else {
            throw RelaySyncEngineError.missingSession
        }

        let messaging = RelayMessagingService(config: config)
        _ = try await messaging.sendApprovalResponse(
            from: device.clientID,
            target: target,
            approvalID: approvalID,
            decision: decision,
            messageID: UUID().uuidString
        )
        try database.markExecApprovalResolved(
            sessionID: sessionID,
            approvalID: approvalID,
            decision: decision
        )
        await chatRepository.publishTranscript(for: sessionID, limit: 50)
        try await syncNow()
    }

    func sendExistingLocalMessage(messageID: MessageID, to sessionID: SessionID) async throws {
        guard let text = try database.messageText(messageID: messageID) else {
            throw RelaySyncEngineError.missingMessage
        }
        try await sendExistingLocalMessage(text, messageID: messageID, to: sessionID)
    }

    func syncNow() async throws {
        guard let config = try await connectionRepository.loadConnectionConfig() else {
            throw ConnectionRepositoryError.incompleteConfiguration
        }
        let device = try await deviceRepository.loadDeviceProfile()
        let messaging = RelayMessagingService(config: config)
        let lastSeenKey = try database.loadLastSeenInboxKey(clientID: device.clientID)
        let batch = try await messaging.collectInboxMessages(clientID: device.clientID, lastSeenKey: lastSeenKey)
        let touched = try database.ingestInboxEntries(batch.messages, clientID: device.clientID)
        try database.saveInboxHead(clientID: device.clientID, head: batch.head)
        for sessionID in touched {
            await chatRepository.publishTranscript(for: SessionID(rawValue: sessionID), limit: 50)
        }
    }

    func backfill(sessionID: SessionID, limit: Int) async throws {
        guard let config = try await connectionRepository.loadConnectionConfig() else {
            throw ConnectionRepositoryError.incompleteConfiguration
        }
        guard let session = try database.session(sessionID: sessionID) else {
            throw RelaySyncEngineError.missingSession
        }
        let device = try await deviceRepository.loadDeviceProfile()
        let messaging = RelayMessagingService(config: config)
        guard let conversationID = session.route.conversationID else {
            return
        }
        let entries = try await messaging.loadThreadBackfill(
            clientID: device.clientID,
            gatewayPeer: session.gatewayID.rawValue,
            conversationID: conversationID,
            limit: limit
        )
        _ = try database.ingestInboxEntries(entries, clientID: device.clientID)
        await chatRepository.publishTranscript(for: sessionID, limit: limit)
    }
}

enum RelaySyncEngineError: LocalizedError {
    case missingSession
    case missingMessage

    var errorDescription: String? {
        switch self {
        case .missingSession:
            return String(localized: "The selected session could not be resolved for relay sending.")
        case .missingMessage:
            return String(localized: "The selected message could not be retried.")
        }
    }
}
