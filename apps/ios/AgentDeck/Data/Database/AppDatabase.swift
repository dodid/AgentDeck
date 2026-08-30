import Foundation
import GRDB

struct GatewayRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "gateways"

    var gatewayID: String
    var displayName: String
    var softwareID: String
    var softwareName: String?
    var softwareVersion: String?
    var protocolVersion: Int64?
    var lastSeenMS: Int64?
    var availableModelsJSON: String
    var defaultModelID: String?
    var modifiedAtMS: Int64

    enum Columns: String, ColumnExpression {
        case gatewayID = "gateway_id"
        case displayName = "display_name"
        case softwareID = "software_id"
        case softwareName = "software_name"
        case softwareVersion = "software_version"
        case protocolVersion = "protocol_version"
        case lastSeenMS = "last_seen_ms"
        case availableModelsJSON = "available_models_json"
        case defaultModelID = "default_model_id"
        case modifiedAtMS = "modified_at_ms"
    }

    enum CodingKeys: String, CodingKey {
        case gatewayID = "gateway_id"
        case displayName = "display_name"
        case softwareID = "software_id"
        case softwareName = "software_name"
        case softwareVersion = "software_version"
        case protocolVersion = "protocol_version"
        case lastSeenMS = "last_seen_ms"
        case availableModelsJSON = "available_models_json"
        case defaultModelID = "default_model_id"
        case modifiedAtMS = "modified_at_ms"
    }
}

struct SessionRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "sessions"

    var sessionID: String
    var gatewayID: String
    var agentID: String
    var routeJSON: String
    var title: String
    var localTitle: String?
    var previewText: String
    var updatedAtMS: Int64?
    var unreadCount: Int
    var createdAtMS: Int64
    var modifiedAtMS: Int64

    enum Columns: String, ColumnExpression {
        case sessionID = "session_id"
        case gatewayID = "gateway_id"
        case agentID = "agent_id"
        case routeJSON = "route_json"
        case title = "title"
        case localTitle = "local_title"
        case previewText = "preview_text"
        case updatedAtMS = "updated_at_ms"
        case unreadCount = "unread_count"
        case createdAtMS = "created_at_ms"
        case modifiedAtMS = "modified_at_ms"
    }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case gatewayID = "gateway_id"
        case agentID = "agent_id"
        case routeJSON = "route_json"
        case title
        case localTitle = "local_title"
        case previewText = "preview_text"
        case updatedAtMS = "updated_at_ms"
        case unreadCount = "unread_count"
        case createdAtMS = "created_at_ms"
        case modifiedAtMS = "modified_at_ms"
    }
}

struct MessageRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "messages"

    var localID: Int64?
    var messageID: String
    var sessionID: String
    var senderKind: String
    var senderValue: String
    var text: String
    var sentAtMS: Int64
    var deliveryState: String
    var deliveryErrorText: String?
    var streamState: String
    var streamID: String?
    var streamSequence: Int?
    var remoteObjectKey: String?
    var remoteMessageID: String?
    var execApprovalJSON: String?
    var execApprovalStateJSON: String?
    var createdLocally: Bool
    var insertedAtMS: Int64

    enum Columns: String, ColumnExpression {
        case localID = "local_id"
        case messageID = "message_id"
        case sessionID = "session_id"
        case senderKind = "sender_kind"
        case senderValue = "sender_value"
        case text = "text"
        case sentAtMS = "sent_at_ms"
        case deliveryState = "delivery_state"
        case deliveryErrorText = "delivery_error_text"
        case streamState = "stream_state"
        case streamID = "stream_id"
        case streamSequence = "stream_sequence"
        case remoteObjectKey = "remote_object_key"
        case remoteMessageID = "remote_message_id"
        case execApprovalJSON = "exec_approval_json"
        case execApprovalStateJSON = "exec_approval_state_json"
        case createdLocally = "created_locally"
        case insertedAtMS = "inserted_at_ms"
    }

    enum CodingKeys: String, CodingKey {
        case localID = "local_id"
        case messageID = "message_id"
        case sessionID = "session_id"
        case senderKind = "sender_kind"
        case senderValue = "sender_value"
        case text
        case sentAtMS = "sent_at_ms"
        case deliveryState = "delivery_state"
        case deliveryErrorText = "delivery_error_text"
        case streamState = "stream_state"
        case streamID = "stream_id"
        case streamSequence = "stream_sequence"
        case remoteObjectKey = "remote_object_key"
        case remoteMessageID = "remote_message_id"
        case execApprovalJSON = "exec_approval_json"
        case execApprovalStateJSON = "exec_approval_state_json"
        case createdLocally = "created_locally"
        case insertedAtMS = "inserted_at_ms"
    }
}

struct InboxStateRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "inbox_state"

    var clientID: String
    var lastHeadKey: String?
    var lastHeadMessageID: String?
    var lastHeadTSMS: Int64?
    var updatedAtMS: Int64

    enum Columns: String, ColumnExpression {
        case clientID = "client_id"
        case lastHeadKey = "last_head_key"
        case lastHeadMessageID = "last_head_message_id"
        case lastHeadTSMS = "last_head_ts_ms"
        case updatedAtMS = "updated_at_ms"
    }

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case lastHeadKey = "last_head_key"
        case lastHeadMessageID = "last_head_message_id"
        case lastHeadTSMS = "last_head_ts_ms"
        case updatedAtMS = "updated_at_ms"
    }
}

struct MessageAttachmentRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "message_attachments"

    var localID: Int64?
    var messageID: String
    var attachmentID: String
    var objectKey: String
    var previewObjectKey: String?
    var fileName: String?
    var mimeType: String?
    var sizeBytes: Int?
    var sha256: String?
    var kind: String
    var width: Int?
    var height: Int?
    var durationMS: Int?
    var sortIndex: Int
    var transferState: String
    var localCacheURL: String?
    var previewCacheURL: String?
    var createdAtMS: Int64

    enum Columns: String, ColumnExpression {
        case localID = "local_id"
        case messageID = "message_id"
        case attachmentID = "attachment_id"
        case objectKey = "object_key"
        case previewObjectKey = "preview_object_key"
        case fileName = "file_name"
        case mimeType = "mime_type"
        case sizeBytes = "size_bytes"
        case sha256
        case kind
        case width
        case height
        case durationMS = "duration_ms"
        case sortIndex = "sort_index"
        case transferState = "transfer_state"
        case localCacheURL = "local_cache_url"
        case previewCacheURL = "preview_cache_url"
        case createdAtMS = "created_at_ms"
    }

    enum CodingKeys: String, CodingKey {
        case localID = "local_id"
        case messageID = "message_id"
        case attachmentID = "attachment_id"
        case objectKey = "object_key"
        case previewObjectKey = "preview_object_key"
        case fileName = "file_name"
        case mimeType = "mime_type"
        case sizeBytes = "size_bytes"
        case sha256
        case kind
        case width
        case height
        case durationMS = "duration_ms"
        case sortIndex = "sort_index"
        case transferState = "transfer_state"
        case localCacheURL = "local_cache_url"
        case previewCacheURL = "preview_cache_url"
        case createdAtMS = "created_at_ms"
    }
}

final class AppDatabase: @unchecked Sendable {
    private let dbQueue: DatabaseQueue
    private let dbURL: URL

    init(databaseURL: URL? = nil) {
        let fm = FileManager.default
        let baseURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let appDir = baseURL.appendingPathComponent("AgentDeck", isDirectory: true)
        let resolvedURL = databaseURL ?? appDir.appendingPathComponent("agentdeck-v3.sqlite")
        try? fm.createDirectory(at: resolvedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        self.dbURL = resolvedURL

        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        self.dbQueue = try! DatabaseQueue(path: dbURL.path, configuration: configuration)
        try? createSchema()
    }

    private func createSchema() throws {
        try dbQueue.write { db in
            try db.create(table: "gateways", ifNotExists: true) { t in
                t.column("gateway_id", .text).notNull().primaryKey()
                t.column("display_name", .text).notNull()
                t.column("software_id", .text).notNull().defaults(to: "unknown")
                t.column("software_name", .text)
                t.column("software_version", .text)
                t.column("protocol_version", .integer)
                t.column("last_seen_ms", .integer)
                t.column("available_models_json", .text).notNull().defaults(to: "[]")
                t.column("default_model_id", .text)
                t.column("modified_at_ms", .integer).notNull()
            }

            try db.create(table: "sessions", ifNotExists: true) { t in
                t.column("session_id", .text).notNull().primaryKey()
                t.column("gateway_id", .text).notNull().indexed().references("gateways", column: "gateway_id", onDelete: .cascade)
                t.column("agent_id", .text).notNull().defaults(to: "main")
                t.column("route_json", .text).notNull().defaults(to: "{}")
                t.column("title", .text).notNull()
                t.column("local_title", .text)
                t.column("preview_text", .text).notNull().defaults(to: "")
                t.column("updated_at_ms", .integer)
                t.column("unread_count", .integer).notNull().defaults(to: 0)
                t.column("created_at_ms", .integer).notNull()
                t.column("modified_at_ms", .integer).notNull()
            }
            try db.create(index: "idx_sessions_gateway_updated", on: "sessions", columns: ["gateway_id", "updated_at_ms"], ifNotExists: true)

            try db.create(table: "messages", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("local_id")
                t.column("message_id", .text).notNull().unique()
                t.column("session_id", .text).notNull().indexed().references("sessions", column: "session_id", onDelete: .cascade)
                t.column("sender_kind", .text).notNull()
                t.column("sender_value", .text).notNull()
                t.column("text", .text).notNull()
                t.column("sent_at_ms", .integer).notNull()
                t.column("delivery_state", .text).notNull()
                t.column("delivery_error_text", .text)
                t.column("stream_state", .text).notNull()
                t.column("stream_id", .text)
                t.column("stream_sequence", .integer)
                t.column("remote_object_key", .text)
                t.column("remote_message_id", .text)
                t.column("exec_approval_json", .text)
                t.column("exec_approval_state_json", .text)
                t.column("created_locally", .boolean).notNull().defaults(to: false)
                t.column("inserted_at_ms", .integer).notNull()
            }
            try db.create(index: "idx_messages_session_sent", on: "messages", columns: ["session_id", "sent_at_ms", "local_id"], ifNotExists: true)

            try db.create(table: "message_attachments", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("local_id")
                t.column("message_id", .text).notNull().indexed().references("messages", column: "message_id", onDelete: .cascade)
                t.column("attachment_id", .text).notNull()
                t.column("object_key", .text).notNull()
                t.column("preview_object_key", .text)
                t.column("file_name", .text)
                t.column("mime_type", .text)
                t.column("size_bytes", .integer)
                t.column("sha256", .text)
                t.column("kind", .text).notNull()
                t.column("width", .integer)
                t.column("height", .integer)
                t.column("duration_ms", .integer)
                t.column("sort_index", .integer).notNull().defaults(to: 0)
                t.column("transfer_state", .text).notNull().defaults(to: "available")
                t.column("local_cache_url", .text)
                t.column("preview_cache_url", .text)
                t.column("created_at_ms", .integer).notNull()
            }
            try db.create(index: "idx_message_attachments_message_sort", on: "message_attachments", columns: ["message_id", "sort_index", "local_id"], ifNotExists: true)
            try db.create(index: "idx_message_attachments_message_attachment", on: "message_attachments", columns: ["message_id", "attachment_id"], unique: true, ifNotExists: true)

            try db.create(table: "inbox_state", ifNotExists: true) { t in
                t.column("client_id", .text).notNull().primaryKey()
                t.column("last_head_key", .text)
                t.column("last_head_message_id", .text)
                t.column("last_head_ts_ms", .integer)
                t.column("updated_at_ms", .integer).notNull()
            }
        }
    }

    func upsertSessions(_ sections: [GatewaySection]) throws -> [SessionID] {
        let now = Self.nowMS()
        return try dbQueue.write { db in
            let discoveredGatewayIDs = Set(sections.map { $0.gateway.id.rawValue })
            let existingGatewayIDs = Set(try GatewayRecord.fetchAll(db).map(\.gatewayID))
            let removedGatewayIDs = existingGatewayIDs.subtracting(discoveredGatewayIDs)
            let removedSessionIDs: [SessionID]

            if removedGatewayIDs.isEmpty {
                removedSessionIDs = []
            } else {
                removedSessionIDs = try SessionRecord.fetchAll(db)
                    .filter { removedGatewayIDs.contains($0.gatewayID) }
                    .map { SessionID(rawValue: $0.sessionID) }

                for gatewayID in removedGatewayIDs {
                    if let gateway = try GatewayRecord.fetchOne(db, key: gatewayID) {
                        try gateway.delete(db)
                    }
                }
            }

            for section in sections {
                let modelsJSON = String(data: (try? JSONEncoder().encode(section.gateway.availableModels)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
                let gatewayRecord = GatewayRecord(
                    gatewayID: section.gateway.id.rawValue,
                    displayName: section.gateway.displayName,
                    softwareID: section.gateway.softwareID,
                    softwareName: section.gateway.softwareName,
                    softwareVersion: section.gateway.softwareVersion,
                    protocolVersion: section.gateway.protocolVersion.map(Int64.init),
                    lastSeenMS: section.gateway.lastSeenAt.map(Self.ms),
                    availableModelsJSON: modelsJSON,
                    defaultModelID: section.gateway.defaultModelID,
                    modifiedAtMS: now
                )
                try gatewayRecord.save(db)

                for session in section.sessions {
                    let existing = try SessionRecord.fetchOne(db, key: session.id.rawValue)
                    let record = SessionRecord(
                        sessionID: session.id.rawValue,
                        gatewayID: session.gatewayID.rawValue,
                        agentID: session.agentID,
                        routeJSON: Self.encodeRouteJSON(session.route),
                        title: session.title,
                        localTitle: existing?.localTitle,
                        previewText: existing?.previewText.isEmpty == false ? existing!.previewText : session.previewText,
                        updatedAtMS: existing?.updatedAtMS ?? session.updatedAt.map(Self.ms),
                        unreadCount: existing?.unreadCount ?? session.unreadCount,
                        createdAtMS: existing?.createdAtMS ?? now,
                        modifiedAtMS: now
                    )
                    try record.save(db)
                }
            }

            return removedSessionIDs
        }
    }

    func sessionSections() throws -> [GatewaySection] {
        try dbQueue.read { db in
            let sessionRecords = try SessionRecord
                .order(SessionRecord.Columns.updatedAtMS.desc)
                .fetchAll(db)
            let gatewayRecords = try GatewayRecord.fetchAll(db)
            let gatewayMap = Dictionary(uniqueKeysWithValues: gatewayRecords.map { ($0.gatewayID, $0) })

            var grouped: [String: [ChatSession]] = [:]
            for session in sessionRecords {
                let route = Self.decodeRouteJSON(session.routeJSON)
                grouped[session.gatewayID, default: []].append(
                    ChatSession(
                        id: SessionID(rawValue: session.sessionID),
                        gatewayID: GatewayID(rawValue: session.gatewayID),
                        agentID: session.agentID,
                        route: route,
                        title: session.title,
                        localTitle: session.localTitle,
                        previewText: session.previewText,
                        updatedAt: session.updatedAtMS.map(Self.date),
                        unreadCount: session.unreadCount
                    )
                )
            }

            return grouped.keys.sorted().map { gatewayID in
                let sessions = (grouped[gatewayID] ?? []).sorted {
                    ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
                }
                let gatewayRecord = gatewayMap[gatewayID]
                let availableModels: [ModelDescriptor] = {
                    guard let json = gatewayRecord?.availableModelsJSON.data(using: .utf8) else { return [] }
                    return (try? JSONDecoder().decode([ModelDescriptor].self, from: json)) ?? []
                }()
                let gateway = Gateway(
                    id: GatewayID(rawValue: gatewayID),
                    displayName: gatewayRecord?.displayName ?? gatewayID,
                    softwareID: gatewayRecord?.softwareID ?? "unknown",
                    softwareName: gatewayRecord?.softwareName,
                    softwareVersion: gatewayRecord?.softwareVersion,
                    protocolVersion: gatewayRecord?.protocolVersion.map(Int.init),
                    lastSeenAt: gatewayRecord?.lastSeenMS.map(Self.date) ?? sessions.compactMap(\.updatedAt).max(),
                    availableModels: availableModels,
                    defaultModelID: gatewayRecord?.defaultModelID
                )
                return GatewaySection(id: gateway.id, gateway: gateway, sessions: sessions)
            }
        }
    }

    func transcript(sessionID: SessionID, limit: Int) throws -> TranscriptPage {
        try dbQueue.read { db in
            let boundedLimit = max(limit, 1)
            let records = try MessageRecord
                .filter(MessageRecord.Columns.sessionID == sessionID.rawValue)
                .order(MessageRecord.Columns.sentAtMS.desc, MessageRecord.Columns.localID.desc)
                .limit(boundedLimit)
                .fetchAll(db)
                .reversed()

            let messageIDs = records.map(\.messageID)
            let attachmentsByMessageID = try Self.loadAttachmentsByMessageID(messageIDs: messageIDs, db: db)
            let messages = records.map { Self.mapMessage($0, attachments: attachmentsByMessageID[$0.messageID] ?? []) }
            let totalCount = try MessageRecord
                .filter(MessageRecord.Columns.sessionID == sessionID.rawValue)
                .fetchCount(db)

            return TranscriptPage(messages: messages, canLoadMore: totalCount > boundedLimit)
        }
    }

    @discardableResult
    func insertLocalOutgoingMessage(
        text: String,
        sessionID: SessionID,
        deviceID: String,
        attachments: [DraftAttachment] = []
    ) throws -> MessageID? {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty || !attachments.isEmpty else { return nil }
        let now = Self.nowMS()
        let messageID = MessageID(rawValue: UUID().uuidString.lowercased())

        try dbQueue.write { db in
            guard var session = try SessionRecord.fetchOne(db, key: sessionID.rawValue) else { return }

            let message = MessageRecord(
                localID: nil,
                messageID: messageID.rawValue,
                sessionID: sessionID.rawValue,
                senderKind: "user",
                senderValue: deviceID,
                text: body,
                sentAtMS: now,
                deliveryState: "sending",
                deliveryErrorText: nil,
                streamState: "none",
                streamID: nil,
                streamSequence: nil,
                remoteObjectKey: nil,
                remoteMessageID: nil,
                execApprovalJSON: nil,
                execApprovalStateJSON: nil,
                createdLocally: true,
                insertedAtMS: now
            )
            try message.insert(db)
            try Self.replaceAttachments(for: messageID.rawValue, from: attachments, db: db)

            session.previewText = Self.previewText(body: body, attachments: attachments)
            session.updatedAtMS = now
            session.modifiedAtMS = now
            try session.save(db)
        }

        return messageID
    }

    nonisolated func relaySendTarget(for sessionID: SessionID) throws -> RelaySendTarget? {
        try dbQueue.read { db in
            guard let session = try SessionRecord.fetchOne(db, key: sessionID.rawValue) else { return nil }
            return RelaySendTarget(
                gatewayPeer: session.gatewayID,
                route: Self.decodeRouteJSON(session.routeJSON)
            )
        }
    }

    nonisolated func relayAttachmentsForMessage(messageID: MessageID) throws -> [RelayAttachment] {
        try dbQueue.read { db in
            let records = try MessageAttachmentRecord
                .filter(MessageAttachmentRecord.Columns.messageID == messageID.rawValue)
                .order(MessageAttachmentRecord.Columns.sortIndex.asc, MessageAttachmentRecord.Columns.localID.asc)
                .fetchAll(db)

            return records.map { record in
                RelayAttachment(
                    id: record.attachmentID,
                    key: record.objectKey,
                    fileName: record.fileName,
                    contentType: record.mimeType,
                    size: record.sizeBytes,
                    sha256: record.sha256,
                    kind: RelayAttachmentKind(rawValue: record.kind) ?? .unknown,
                    width: record.width,
                    height: record.height,
                    durationMS: record.durationMS,
                    previewImageKey: record.previewObjectKey,
                    previewImageType: nil,
                    previewSize: nil
                )
            }
        }
    }

    nonisolated func draftAttachmentsForMessage(messageID: MessageID) throws -> [DraftAttachment] {
        try dbQueue.read { db in
            let records = try MessageAttachmentRecord
                .filter(MessageAttachmentRecord.Columns.messageID == messageID.rawValue)
                .order(MessageAttachmentRecord.Columns.sortIndex.asc, MessageAttachmentRecord.Columns.localID.asc)
                .fetchAll(db)

            return records.compactMap { record in
                let transferState = AttachmentTransferState(rawValue: record.transferState)
                guard transferState == .pending || transferState == .failed,
                      let localURL = record.localCacheURL, !localURL.isEmpty else {
                    return nil
                }
                return DraftAttachment(
                    id: record.attachmentID,
                    fileName: record.fileName,
                    mimeType: record.mimeType,
                    sizeBytes: record.sizeBytes,
                    kind: AttachmentKind(rawValue: record.kind) ?? .unknown,
                    localURL: localURL
                )
            }
        }
    }

    nonisolated func messageText(messageID: MessageID) throws -> String? {
        try dbQueue.read { db in
            try MessageRecord
                .filter(MessageRecord.Columns.messageID == messageID.rawValue)
                .fetchOne(db)?
                .text
        }
    }

    nonisolated func updateUploadedAttachments(messageID: MessageID, attachments: [RelayAttachment]) throws {
        try dbQueue.write { db in
            try Self.replaceAttachments(for: messageID.rawValue, from: attachments, transferState: .uploaded, db: db)
        }
    }

    nonisolated func markMessageSent(messageID: MessageID) throws {
        try dbQueue.write { db in
            guard var record = try MessageRecord.filter(MessageRecord.Columns.messageID == messageID.rawValue).fetchOne(db) else { return }
            record.deliveryState = "sentToRelay"
            record.deliveryErrorText = nil
            try record.save(db)
        }
    }

    nonisolated func markMessageFailed(messageID: MessageID, error: String) throws {
        try dbQueue.write { db in
            guard var record = try MessageRecord.filter(MessageRecord.Columns.messageID == messageID.rawValue).fetchOne(db) else { return }
            record.deliveryState = "failed"
            record.deliveryErrorText = error
            try record.save(db)

            let attachmentRecords = try MessageAttachmentRecord
                .filter(MessageAttachmentRecord.Columns.messageID == messageID.rawValue)
                .fetchAll(db)
            for var attachment in attachmentRecords {
                guard AttachmentTransferState(rawValue: attachment.transferState) == .pending else { continue }
                attachment.transferState = AttachmentTransferState.failed.rawValue
                try attachment.save(db)
            }
        }
    }

    nonisolated func prepareMessageForRetry(messageID: MessageID) throws {
        try dbQueue.write { db in
            guard var record = try MessageRecord.filter(MessageRecord.Columns.messageID == messageID.rawValue).fetchOne(db) else { return }
            record.deliveryState = "sending"
            record.deliveryErrorText = nil
            try record.save(db)

            let attachmentRecords = try MessageAttachmentRecord
                .filter(MessageAttachmentRecord.Columns.messageID == messageID.rawValue)
                .fetchAll(db)
            for var attachment in attachmentRecords {
                guard AttachmentTransferState(rawValue: attachment.transferState) == .failed else { continue }
                attachment.transferState = AttachmentTransferState.pending.rawValue
                try attachment.save(db)
            }
        }
    }

    nonisolated func markExecApprovalResolved(sessionID: SessionID, approvalID: String, decision: String) throws {
        try dbQueue.write { db in
            let records = try MessageRecord
                .filter(MessageRecord.Columns.sessionID == sessionID.rawValue)
                .fetchAll(db)
            for var record in records {
                guard let approval = Self.decodeExecApprovalJSON(record.execApprovalJSON), approval.approvalID == approvalID else {
                    continue
                }
                record.execApprovalStateJSON = Self.encodeExecApprovalResolutionJSON(
                    ExecApprovalResolution(decision: decision)
                )
                try record.save(db)
            }
        }
    }

    nonisolated func ingestInboxEntries(_ entries: [RelayInboxEntry], clientID: String) throws -> [String] {
        var touched = Set<String>()

        try dbQueue.write { db in
            for entry in entries {
                let message = entry.message
                let serverPeer = message.to == clientID ? message.from : message.to
                let agentID = message.route.agentID
                let sessionID = "\(serverPeer)::\(agentID)::\(message.route.conversationID ?? "default")"
                let directionIsOutgoing = message.from == clientID
                let senderKind = directionIsOutgoing ? "user" : "assistant"
                let senderValue = directionIsOutgoing ? clientID : serverPeer

                // v3: reactions used for delivery confirmation
                if case .reaction(let rc) = message.content, rc.emoji == "✅", rc.remove != true {
                    if let targetMessageID = rc.targetMsgID.isEmpty ? nil : rc.targetMsgID,
                       var targetRecord = try MessageRecord
                        .filter(MessageRecord.Columns.messageID == targetMessageID)
                        .fetchOne(db) {
                        targetRecord.deliveryState = "confirmed"
                        targetRecord.deliveryErrorText = nil
                        try targetRecord.save(db)
                        touched.insert(targetRecord.sessionID)

                        if var session = try SessionRecord.fetchOne(db, key: targetRecord.sessionID) {
                            session.modifiedAtMS = Self.nowMS()
                            try session.save(db)
                        }
                    }
                    continue
                }

                let body: String
                let relayAttachments: [RelayAttachment]
                let execApprovalJSON: String?
                switch message.content {
                case .text(let tc):
                    body = tc.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    relayAttachments = tc.attachments ?? []
                    execApprovalJSON = nil
                case .approvalRequest(let ar):
                    body = Self.approvalPreviewText(title: ar.title, body: ar.body)
                    relayAttachments = []
                    execApprovalJSON = Self.encodeExecApprovalJSON(
                        ExecApprovalMetadata(
                            approvalID: ar.approvalID,
                            approvalKind: ar.approvalKind,
                            title: ar.title,
                            body: ar.body,
                            allowedDecisions: ar.allowedDecisions
                        )
                    )
                case .approvalResponse(let response):
                    let resolvedSessionIDs = try Self.markMatchingExecApprovalResolved(
                        approvalID: response.approvalID,
                        decision: response.decision,
                        db: db
                    )
                    touched.formUnion(resolvedSessionIDs)
                    continue
                default:
                    continue
                }

                let hasAttachments = !relayAttachments.isEmpty
                guard !body.isEmpty || hasAttachments || execApprovalJSON != nil else {
                    continue
                }
                touched.insert(sessionID)

                let existingSession = try SessionRecord.fetchOne(db, key: sessionID)
                if existingSession == nil {
                    let now = Self.nowMS()
                    let session = SessionRecord(
                        sessionID: sessionID,
                        gatewayID: serverPeer,
                        agentID: agentID,
                        routeJSON: Self.encodeRouteJSON(message.route),
                        title: agentID,
                        localTitle: nil,
                        previewText: "",
                        updatedAtMS: Int64(message.tsSent),
                        unreadCount: 0,
                        createdAtMS: now,
                        modifiedAtMS: now
                    )
                    try session.insert(db)
                }

                // v3: stream fields come from delivery
                let streamInfo = message.delivery?.stream

                if directionIsOutgoing,
                   var optimistic = try MessageRecord
                    .filter(MessageRecord.Columns.sessionID == sessionID)
                    .filter(MessageRecord.Columns.createdLocally == true)
                    .filter(MessageRecord.Columns.text == body)
                    .filter(MessageRecord.Columns.remoteObjectKey == nil)
                    .order(MessageRecord.Columns.sentAtMS.desc)
                    .fetchOne(db) {
                    optimistic.remoteObjectKey = entry.key
                    optimistic.remoteMessageID = message.msgID
                    optimistic.sentAtMS = Int64(message.tsSent)  // use relay server timestamp for stable ordering
                    optimistic.deliveryState = "sentToRelay"
                    optimistic.deliveryErrorText = nil
                    optimistic.execApprovalJSON = execApprovalJSON
                    try optimistic.save(db)
                    try Self.replaceAttachments(for: optimistic.messageID, from: relayAttachments, transferState: .uploaded, db: db)
                } else {
                    let existingMessage = try MessageRecord
                        .filter(MessageRecord.Columns.messageID == message.msgID)
                        .fetchOne(db)
                    if existingMessage == nil {
                        let normalizedStreamState = Self.normalizedStreamState(streamInfo?.state)
                        let record = MessageRecord(
                            localID: nil,
                            messageID: message.msgID,
                            sessionID: sessionID,
                            senderKind: senderKind,
                            senderValue: senderValue,
                            text: body,
                            sentAtMS: Int64(message.tsSent),
                            deliveryState: directionIsOutgoing ? "sentToRelay" : "confirmed",
                            deliveryErrorText: nil,
                            streamState: normalizedStreamState,
                            streamID: streamInfo?.streamID,
                            streamSequence: streamInfo?.seq,
                            remoteObjectKey: entry.key,
                            remoteMessageID: message.msgID,
                            execApprovalJSON: execApprovalJSON,
                            execApprovalStateJSON: nil,
                            createdLocally: false,
                            insertedAtMS: Self.nowMS()
                        )
                        try record.insert(db)
                    }
                    try Self.replaceAttachments(for: message.msgID, from: relayAttachments, transferState: .available, db: db)
                }

                if var session = try SessionRecord.fetchOne(db, key: sessionID) {
                    session.previewText = Self.previewText(body: body, attachments: relayAttachments)
                    session.updatedAtMS = Int64(message.tsSent)
                    session.modifiedAtMS = Self.nowMS()
                    try session.save(db)
                }
            }
        }

        return Array(touched)
    }

    nonisolated func loadLastSeenInboxKey(clientID: String) throws -> String? {
        try dbQueue.read { db in
            try InboxStateRecord.fetchOne(db, key: clientID)?.lastHeadKey
        }
    }

    nonisolated func saveInboxHead(clientID: String, head: RelayHeadDoc?) throws {
        try dbQueue.write { db in
            let existing = try InboxStateRecord.fetchOne(db, key: clientID)
            let record = InboxStateRecord(
                clientID: clientID,
                lastHeadKey: head?.headKey ?? existing?.lastHeadKey,
                lastHeadMessageID: head?.headMsgID ?? existing?.lastHeadMessageID,
                lastHeadTSMS: head.map { Int64($0.headTS) } ?? existing?.lastHeadTSMS,
                updatedAtMS: Self.nowMS()
            )
            try record.save(db)
        }
    }

    nonisolated func session(sessionID: SessionID) throws -> ChatSession? {
        try dbQueue.read { db in
            guard let session = try SessionRecord.fetchOne(db, key: sessionID.rawValue) else { return nil }
            return ChatSession(
                id: SessionID(rawValue: session.sessionID),
                gatewayID: GatewayID(rawValue: session.gatewayID),
                agentID: session.agentID,
                route: Self.decodeRouteJSON(session.routeJSON),
                title: session.title,
                localTitle: session.localTitle,
                previewText: session.previewText,
                updatedAt: session.updatedAtMS.map(Self.date),
                unreadCount: session.unreadCount
            )
        }
    }

    nonisolated func updateLocalSessionTitle(sessionID: SessionID, title: String?) throws {
        try dbQueue.write { db in
            guard var session = try SessionRecord.fetchOne(db, key: sessionID.rawValue) else { return }
            let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            session.localTitle = trimmed.isEmpty ? nil : trimmed
            session.modifiedAtMS = Self.nowMS()
            try session.save(db)
        }
    }

    func sessionTitle(sessionID: SessionID) throws -> String {
        try dbQueue.read { db in
            if let session = try SessionRecord.fetchOne(db, key: sessionID.rawValue) {
                let viewData = ChatSession(
                    id: SessionID(rawValue: session.sessionID),
                    gatewayID: GatewayID(rawValue: session.gatewayID),
                    agentID: session.agentID,
                    route: Self.decodeRouteJSON(session.routeJSON),
                    title: session.title,
                    localTitle: session.localTitle,
                    previewText: session.previewText,
                    updatedAt: session.updatedAtMS.map(Self.date),
                    unreadCount: session.unreadCount
                )
                return viewData.displayLabel(gatewayDisplayName: nil)
            }
            return String(localized: "Chat")
        }
    }

    func storageStats() throws -> StorageStats {
        let counts = try dbQueue.read { db in
            let sessionCount = try SessionRecord.fetchCount(db)
            let messageCount = try MessageRecord.fetchCount(db)
            return (sessionCount, messageCount)
        }
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: dbURL.path)[.size] as? Int64) ?? 0
        return StorageStats(
            threadCount: counts.0,
            messageCount: counts.1,
            sessionDataSizeBytes: fileSize,
            attachmentDataSizeBytes: 0
        )
    }

    func clearAllData() throws {
        try dbQueue.write { db in
            try MessageAttachmentRecord.deleteAll(db)
            try MessageRecord.deleteAll(db)
            try SessionRecord.deleteAll(db)
            try GatewayRecord.deleteAll(db)
            try InboxStateRecord.deleteAll(db)
        }
    }

    func cleanupManagedAttachmentReferences(
        olderThan cutoffDate: Date,
        managedRootPaths: [String]
    ) throws -> AttachmentCleanupPlan {
        let cutoffMS = Self.ms(cutoffDate)
        let normalizedRootPaths = managedRootPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path }

        return try dbQueue.write { db in
            let records = try MessageAttachmentRecord
                .filter(MessageAttachmentRecord.Columns.createdAtMS < cutoffMS)
                .fetchAll(db)

            var managedPaths = Set<String>()

            for var record in records {
                var changed = false

                if let path = Self.normalizedManagedPath(record.localCacheURL, managedRootPaths: normalizedRootPaths) {
                    managedPaths.insert(path)
                    record.localCacheURL = nil
                    changed = true
                }

                if let path = Self.normalizedManagedPath(record.previewCacheURL, managedRootPaths: normalizedRootPaths) {
                    managedPaths.insert(path)
                    record.previewCacheURL = nil
                    changed = true
                }

                if changed {
                    try record.save(db)
                }
            }

            return AttachmentCleanupPlan(localFilePaths: managedPaths.sorted())
        }
    }

    func cleanupAllManagedAttachmentReferences(managedRootPaths: [String]) throws -> AttachmentCleanupPlan {
        let normalizedRootPaths = managedRootPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path }

        return try dbQueue.write { db in
            let records = try MessageAttachmentRecord.fetchAll(db)

            var managedPaths = Set<String>()

            for var record in records {
                var changed = false

                if let path = Self.normalizedManagedPath(record.localCacheURL, managedRootPaths: normalizedRootPaths) {
                    managedPaths.insert(path)
                    record.localCacheURL = nil
                    changed = true
                }

                if let path = Self.normalizedManagedPath(record.previewCacheURL, managedRootPaths: normalizedRootPaths) {
                    managedPaths.insert(path)
                    record.previewCacheURL = nil
                    changed = true
                }

                if changed {
                    try record.save(db)
                }
            }

            return AttachmentCleanupPlan(localFilePaths: managedPaths.sorted())
        }
    }


    private nonisolated static func mapMessage(_ record: MessageRecord, attachments: [ChatAttachment]) -> ChatMessage {
        let sender: MessageSender = {
            switch record.senderKind {
            case "user":
                return .user(deviceID: record.senderValue)
            default:
                return .assistant(gatewayID: GatewayID(rawValue: record.senderValue))
            }
        }()

        let deliveryState: MessageDeliveryState = {
            switch record.deliveryState {
            case "localOnly": return .localOnly
            case "sending": return .sending
            case "sentToRelay": return .sentToRelay
            case "confirmed": return .confirmed
            case "failed": return .failed(record.deliveryErrorText ?? "Send failed")
            default: return .localOnly
            }
        }()

        let streamState: MessageStreamState = {
            switch Self.normalizedStreamState(record.streamState) {
            case "partial":
                return .partial(streamID: record.streamID ?? "", sequence: record.streamSequence ?? 0)
            case "complete":
                return .complete
            default:
                return .none
            }
        }()

        return ChatMessage(
            id: MessageID(rawValue: record.messageID),
            sessionID: SessionID(rawValue: record.sessionID),
            sender: sender,
            text: record.text,
            attachments: attachments,
            sentAt: Self.date(record.sentAtMS),
            deliveryState: deliveryState,
            streamState: streamState,
            streamID: record.streamID,
            remoteObjectKey: record.remoteObjectKey,
            remoteMessageID: record.remoteMessageID,
            execApproval: decodeExecApprovalJSON(record.execApprovalJSON),
            execApprovalResolution: decodeExecApprovalResolutionJSON(record.execApprovalStateJSON)
        )
    }

    private nonisolated static func loadAttachmentsByMessageID(messageIDs: [String], db: Database) throws -> [String: [ChatAttachment]] {
        guard !messageIDs.isEmpty else { return [:] }
        let records = try MessageAttachmentRecord
            .filter(messageIDs.contains(MessageAttachmentRecord.Columns.messageID))
            .order(MessageAttachmentRecord.Columns.sortIndex.asc, MessageAttachmentRecord.Columns.localID.asc)
            .fetchAll(db)

        var grouped: [String: [ChatAttachment]] = [:]
        for record in records {
            grouped[record.messageID, default: []].append(mapAttachment(record))
        }
        return grouped
    }

    private nonisolated static func normalizedStreamState(_ rawValue: String?) -> String {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "partial":
            return "partial"
        case "complete", "final":
            return "complete"
        default:
            return "none"
        }
    }

    private nonisolated static func replaceAttachments(
        for messageID: String,
        from relayAttachments: [RelayAttachment],
        transferState: AttachmentTransferState,
        db: Database
    ) throws {
        // Preserve local cache URLs from any existing draft rows so the UI never loses
        // an already-visible image during the draft→uploaded→available transition.
        let existingRecords = try MessageAttachmentRecord
            .filter(MessageAttachmentRecord.Columns.messageID == messageID)
            .fetchAll(db)
        let existingLocalCacheByID: [String: String] = existingRecords.reduce(into: [:]) { acc, r in
            if let url = r.localCacheURL, !url.isEmpty { acc[r.attachmentID] = url }
        }

        try MessageAttachmentRecord
            .filter(MessageAttachmentRecord.Columns.messageID == messageID)
            .deleteAll(db)

        let now = Self.nowMS()
        for (index, attachment) in relayAttachments.enumerated() {
            let record = MessageAttachmentRecord(
                localID: nil,
                messageID: messageID,
                attachmentID: attachment.id,
                objectKey: attachment.key,
                previewObjectKey: attachment.previewImageKey,
                fileName: attachment.fileName,
                mimeType: attachment.contentType,
                sizeBytes: attachment.size,
                sha256: attachment.sha256,
                kind: attachment.kind.rawValue,
                width: attachment.width,
                height: attachment.height,
                durationMS: attachment.durationMS,
                sortIndex: index,
                transferState: transferState.rawValue,
                localCacheURL: existingLocalCacheByID[attachment.id],  // preserve local file path
                previewCacheURL: nil,
                createdAtMS: now
            )
            try record.insert(db)
        }
    }

    private nonisolated static func replaceAttachments(
        for messageID: String,
        from draftAttachments: [DraftAttachment],
        db: Database
    ) throws {
        try MessageAttachmentRecord
            .filter(MessageAttachmentRecord.Columns.messageID == messageID)
            .deleteAll(db)

        let now = Self.nowMS()
        for (index, attachment) in draftAttachments.enumerated() {
            let record = MessageAttachmentRecord(
                localID: nil,
                messageID: messageID,
                attachmentID: attachment.id,
                objectKey: attachment.localURL ?? "local://\(attachment.id)",
                previewObjectKey: nil,
                fileName: attachment.fileName,
                mimeType: attachment.mimeType,
                sizeBytes: attachment.sizeBytes,
                sha256: nil,
                kind: attachment.kind.rawValue,
                width: nil,
                height: nil,
                durationMS: nil,
                sortIndex: index,
                transferState: AttachmentTransferState.pending.rawValue,
                localCacheURL: attachment.localURL,
                previewCacheURL: nil,
                createdAtMS: now
            )
            try record.insert(db)
        }
    }

    private nonisolated static func mapAttachment(_ record: MessageAttachmentRecord) -> ChatAttachment {
        ChatAttachment(
            id: record.attachmentID,
            objectKey: record.objectKey,
            previewObjectKey: record.previewObjectKey,
            fileName: record.fileName,
            mimeType: record.mimeType,
            sizeBytes: record.sizeBytes,
            sha256: record.sha256,
            kind: AttachmentKind(rawValue: record.kind) ?? .unknown,
            width: record.width,
            height: record.height,
            durationMS: record.durationMS,
            transferState: AttachmentTransferState(rawValue: record.transferState) ?? .available,
            localCacheURL: record.localCacheURL,
            previewCacheURL: record.previewCacheURL
        )
    }

    private nonisolated static func previewText(body: String, attachments: [RelayAttachment]) -> String {
        previewText(body: body, labels: attachments.map(\.fileName))
    }

    private nonisolated static func previewText(body: String, attachments: [DraftAttachment]) -> String {
        previewText(body: body, labels: attachments.map(\.fileName))
    }

    private nonisolated static func previewText(body: String, labels: [String?]) -> String {
        if !body.isEmpty {
            return body
        }
        guard !labels.isEmpty else {
            return ""
        }
        if labels.count == 1 {
            let label = labels[0]?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let label, !label.isEmpty {
                return "📎 \(label)"
            }
            return "📎 Attachment"
        }
        return "📎 \(labels.count) attachments"
    }

    private nonisolated static func approvalPreviewText(title: String, body: String?) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedTitle.isEmpty, !trimmedBody.isEmpty {
            return "\(trimmedTitle)\n\(trimmedBody)"
        }
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }
        return trimmedBody
    }

    private nonisolated static func encodeExecApprovalJSON(_ approval: ExecApprovalMetadata?) -> String? {
        guard let approval else { return nil }
        var object: [String: Any] = [
            "approvalId": approval.approvalID,
            "approvalKind": approval.approvalKind,
            "title": approval.title,
            "allowedDecisions": approval.allowedDecisions
        ]
        if let body = approval.body {
            object["body"] = body
        }
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: []),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }

    private nonisolated static func encodeRouteJSON(_ route: RelayRoute) -> String {
        var object: [String: Any] = ["agent_id": route.agentID]
        if let cid = route.conversationID { object["conversation_id"] = cid }
        if let iid = route.instanceID { object["instance_id"] = iid }
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: []),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private nonisolated static func decodeRouteJSON(_ raw: String) -> RelayRoute {
        if let data = raw.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data, options: []),
           let dict = object as? [String: Any],
           let agentID = dict["agent_id"] as? String {
            return RelayRoute(
                agentID: agentID,
                conversationID: dict["conversation_id"] as? String,
                instanceID: dict["instance_id"] as? String
            )
        }
        return RelayRoute(agentID: "main", conversationID: nil, instanceID: nil)
    }

    private nonisolated static func decodeExecApprovalJSON(_ raw: String?) -> ExecApprovalMetadata? {
        guard let raw,
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = object as? [String: Any],
              let approvalID = dict["approvalId"] as? String,
              let approvalKind = dict["approvalKind"] as? String,
              let title = dict["title"] as? String,
              let allowedDecisions = dict["allowedDecisions"] as? [String] else {
            return nil
        }
        return ExecApprovalMetadata(
            approvalID: approvalID,
            approvalKind: approvalKind,
            title: title,
            body: dict["body"] as? String,
            allowedDecisions: allowedDecisions
        )
    }

    private nonisolated static func encodeExecApprovalResolutionJSON(_ resolution: ExecApprovalResolution?) -> String? {
        guard let resolution else { return nil }
        let object: [String: Any] = ["decision": resolution.decision]
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: []),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }

    private nonisolated static func markMatchingExecApprovalResolved(
        approvalID: String,
        decision: String,
        db: Database
    ) throws -> [String] {
        let records = try MessageRecord.fetchAll(db)
        var touched = Set<String>()
        for var record in records {
            guard let approval = decodeExecApprovalJSON(record.execApprovalJSON), approval.approvalID == approvalID else {
                continue
            }
            record.execApprovalStateJSON = encodeExecApprovalResolutionJSON(
                ExecApprovalResolution(decision: decision)
            )
            try record.save(db)
            touched.insert(record.sessionID)
        }
        return Array(touched)
    }

    private nonisolated static func decodeExecApprovalResolutionJSON(_ raw: String?) -> ExecApprovalResolution? {
        guard let raw,
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = object as? [String: Any],
              let decision = dict["decision"] as? String else {
            return nil
        }
        return ExecApprovalResolution(decision: decision)
    }

    private nonisolated static func nowMS() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private nonisolated static func ms(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1000)
    }

    private nonisolated static func date(_ ms: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
    }

    private nonisolated static func normalizedManagedPath(
        _ rawPath: String?,
        managedRootPaths: [String]
    ) -> String? {
        guard let rawPath, !rawPath.isEmpty else { return nil }

        let fileURL: URL?
        if rawPath.hasPrefix("file://") {
            fileURL = URL(string: rawPath)
        } else {
            fileURL = URL(fileURLWithPath: rawPath)
        }

        guard let standardizedPath = fileURL?.standardizedFileURL.path else { return nil }
        guard managedRootPaths.contains(where: { standardizedPath == $0 || standardizedPath.hasPrefix($0 + "/") }) else {
            return nil
        }
        return standardizedPath
    }
}
