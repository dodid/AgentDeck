import Foundation

actor RelaySyncEngine {
    private let connectionRepository: ConnectionRepository
    private let deviceRepository: DeviceRepository
    private let chatRepository: DefaultChatRepository
    private let database: AppDatabase
    private var sendSlotTaken = false
    private var sendWaiters: [CheckedContinuation<Void, Never>] = []

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
        await acquireSendSlot()

        do {
            try Task.checkCancellation()
            guard let config = try await connectionRepository.loadConnectionConfig() else {
                throw ConnectionRepositoryError.incompleteConfiguration
            }
            let device = try await deviceRepository.loadDeviceProfile()
            guard let target = try database.relaySendTarget(for: sessionID) else {
                throw RelaySyncEngineError.missingSession
            }
            guard let session = try database.session(sessionID: sessionID) else {
                throw RelaySyncEngineError.missingSession
            }
            let messaging = RelayMessagingService(config: config)
            let uploader = RelayAttachmentUploadService(config: config)
            let draftAttachments = try database.draftAttachmentsForMessage(messageID: messageID)
            if !draftAttachments.isEmpty {
                try validateAttachments(draftAttachments, capabilities: session.capabilities?.attachments)
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
        } catch {
            releaseSendSlot()
            try? database.markMessageFailed(messageID: messageID, error: error.localizedDescription)
            await chatRepository.publishTranscript(for: sessionID, limit: 50)
            throw error
        }
        releaseSendSlot()
        await chatRepository.publishTranscript(for: sessionID, limit: 50)
        try? await syncNow()
    }

    func sendApprovalResponse(approvalID: String, decision: String, to sessionID: SessionID) async throws {
        await acquireSendSlot()
        do {
            try Task.checkCancellation()
            guard let config = try await connectionRepository.loadConnectionConfig() else {
                throw ConnectionRepositoryError.incompleteConfiguration
            }
            let device = try await deviceRepository.loadDeviceProfile()
            guard let target = try database.relaySendTarget(for: sessionID) else {
                throw RelaySyncEngineError.missingSession
            }
            guard let session = try database.session(sessionID: sessionID) else {
                throw RelaySyncEngineError.missingSession
            }
            let approvalKind = try database.approvalKind(sessionID: sessionID, approvalID: approvalID) ?? "exec"
            guard supportsApproval(kind: approvalKind, capabilities: session.capabilities?.approvals) else {
                throw RelaySyncEngineError.approvalKindUnsupported(approvalKind)
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
        } catch {
            releaseSendSlot()
            throw error
        }
        releaseSendSlot()
        await chatRepository.publishTranscript(for: sessionID, limit: 50)
        try? await syncNow()
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

    private func acquireSendSlot() async {
        if !sendSlotTaken {
            sendSlotTaken = true
            return
        }
        await withCheckedContinuation { continuation in
            sendWaiters.append(continuation)
        }
    }

    private func releaseSendSlot() {
        guard !sendWaiters.isEmpty else {
            sendSlotTaken = false
            return
        }
        sendWaiters.removeFirst().resume()
    }

    private func validateAttachments(
        _ attachments: [DraftAttachment],
        capabilities: RemoteAttachmentCapabilities?
    ) throws {
        guard let capabilities, capabilities.supported else {
            throw RelaySyncEngineError.attachmentsUnsupported
        }
        let supportedKinds = Set(capabilities.kinds)
        for attachment in attachments {
            guard supportedKinds.contains(attachment.kind.rawValue) else {
                throw RelaySyncEngineError.attachmentKindUnsupported(attachment.kind.rawValue)
            }
            if let size = attachment.sizeBytes,
               let maxBytes = capabilities.maxBytesByKind?[attachment.kind.rawValue],
               size > maxBytes {
                throw RelaySyncEngineError.attachmentTooLarge(attachment.fileName ?? attachment.id, maxBytes)
            }
        }
    }

    private func supportsApproval(kind: String, capabilities: RemoteApprovalCapabilities?) -> Bool {
        guard let capabilities else { return false }
        switch kind.lowercased() {
        case "exec": return capabilities.exec
        case "tool", "plugin": return capabilities.tool
        case "custom": return capabilities.custom
        default: return false
        }
    }
}

enum RelaySyncEngineError: LocalizedError {
    case missingSession
    case missingMessage
    case attachmentsUnsupported
    case attachmentKindUnsupported(String)
    case attachmentTooLarge(String, Int)
    case approvalKindUnsupported(String)

    var errorDescription: String? {
        switch self {
        case .missingSession:
            return String(localized: "The selected session could not be resolved for relay sending.")
        case .missingMessage:
            return String(localized: "The selected message could not be retried.")
        case .attachmentsUnsupported:
            return String(localized: "Attachments are not supported by this session.")
        case .attachmentKindUnsupported(let kind):
            return String.localizedStringWithFormat(String(localized: "This session does not support %@ attachments."), kind)
        case .attachmentTooLarge(let name, let maxBytes):
            return String.localizedStringWithFormat(
                String(localized: "%@ exceeds this session's attachment limit of %@."),
                name,
                ByteCountFormatter.string(fromByteCount: Int64(maxBytes), countStyle: .file)
            )
        case .approvalKindUnsupported(let kind):
            return String.localizedStringWithFormat(String(localized: "This session does not support %@ approvals."), kind)
        }
    }
}
