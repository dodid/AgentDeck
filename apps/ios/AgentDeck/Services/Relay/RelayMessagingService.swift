import Foundation

struct RelayMessagingService: Sendable {
    private let store: R2ObjectStore

    nonisolated init(config: ConnectionConfig) {
        self.store = R2S3ObjectStore(
            endpoint: config.endpoint,
            bucket: config.bucket,
            region: config.region,
            accessKeyID: config.accessKeyID,
            secretAccessKey: config.secretAccessKey,
            forcePathStyle: config.forcePathStyle
        )
    }

    init(store: R2ObjectStore) {
        self.store = store
    }

    func sendMessage(from clientID: String, target: RelaySendTarget, text: String, messageID: String, attachments: [RelayAttachment] = []) async throws -> String {
        try await appendMessage(
            from: clientID,
            target: target,
            messageID: messageID,
            content: .text(RelayTextContent(
                type: "text",
                text: text,
                attachments: attachments.isEmpty ? nil : attachments
            ))
        )
    }

    func sendApprovalResponse(
        from clientID: String,
        target: RelaySendTarget,
        approvalID: String,
        decision: String,
        messageID: String
    ) async throws -> String {
        try await appendMessage(
            from: clientID,
            target: target,
            messageID: messageID,
            content: .approvalResponse(RelayApprovalResponseContent(
                type: "approval_response",
                approvalID: approvalID,
                decision: decision,
                metadata: nil
            ))
        )
    }

    private func appendMessage(
        from clientID: String,
        target: RelaySendTarget,
        messageID: String,
        content: RelayContent
    ) async throws -> String {
        let now = Date().timeIntervalSince1970 * 1000
        let headKey = Self.makeHeadKey(recipient: target.gatewayPeer)
        let encoder = JSONEncoder()

        for _ in 0..<8 {
            let currentHead = try await getHeadState(peer: target.gatewayPeer)
            let key = Self.makeMessageKey(recipient: target.gatewayPeer, timestampMS: Date().timeIntervalSince1970 * 1000)

            let message = RelayMessage(
                msgID: messageID,
                from: clientID,
                to: target.gatewayPeer,
                tsSent: now,
                prevKey: currentHead?.doc.headKey,
                route: target.route,
                content: content,
                delivery: nil,
                status: nil,
                size: nil
            )

            try await storePut(key: key, payload: encoder.encode(message), ifMatch: nil, ifNoneMatch: "*")

            let headDoc = RelayHeadDoc(headKey: key, headMsgID: messageID, headTS: Date().timeIntervalSince1970 * 1000)
            do {
                try await storePut(
                    key: headKey,
                    payload: encoder.encode(headDoc),
                    ifMatch: normalizedCASMatchETag(currentHead?.etag),
                    ifNoneMatch: currentHead == nil ? "*" : nil
                )
                return messageID
            } catch {
                try await Task.sleep(for: .milliseconds(Int.random(in: 20...80)))
                continue
            }
        }

        throw RelayMessagingError.casRetryFailed
    }

    func collectInboxMessages(clientID: String, lastSeenKey: String?) async throws -> (head: RelayHeadDoc?, messages: [RelayInboxEntry]) {
        guard let head = try await getHead(peer: clientID) else {
            return (nil, [])
        }
        if head.headKey == lastSeenKey {
            return (head, [])
        }

        let entries = try await walkInboxChain(startKey: head.headKey, stopBeforeKey: lastSeenKey, limit: 200)
        return (head, entries.reversed())
    }

    func loadThreadBackfill(clientID: String, gatewayPeer: String, conversationID: String, limit: Int = 80) async throws -> [RelayInboxEntry] {
        let incomingHead = try await getHead(peer: clientID)?.headKey
        let outgoingHead = try await getHead(peer: gatewayPeer)?.headKey

        let incomingEntries = try await walkFilteredChain(startKey: incomingHead, limit: limit * 2) { entry in
            let msg = entry.message
            return msg.to == clientID && msg.from == gatewayPeer && msg.route.conversationID == conversationID
        }
        let outgoingEntries = try await walkFilteredChain(startKey: outgoingHead, limit: limit * 2) { entry in
            let msg = entry.message
            return msg.to == gatewayPeer && msg.route.conversationID == conversationID
        }

        var merged: [RelayInboxEntry] = []
        var seen = Set<String>()
        for entry in (incomingEntries + outgoingEntries).sorted(by: { $0.message.tsSent < $1.message.tsSent }) {
            if seen.insert(entry.message.msgID).inserted {
                merged.append(entry)
            }
        }
        return Array(merged.suffix(limit))
    }

    private func walkInboxChain(startKey: String?, stopBeforeKey: String?, limit: Int? = nil) async throws -> [RelayInboxEntry] {
        var currentKey = startKey
        var entries: [RelayInboxEntry] = []

        while let key = currentKey, key != stopBeforeKey {
            if let limit, entries.count >= limit { break }
            guard let message = try await readMessage(key: key) else { break }
            entries.append(RelayInboxEntry(key: key, message: message))
            currentKey = message.prevKey
        }

        return entries
    }

    private func walkFilteredChain(startKey: String?, limit: Int, include: (RelayInboxEntry) -> Bool) async throws -> [RelayInboxEntry] {
        var currentKey = startKey
        var matches: [RelayInboxEntry] = []
        var scanned = 0
        let scanCap = max(limit * 6, 120)

        while let key = currentKey, matches.count < limit, scanned < scanCap {
            guard let message = try await readMessage(key: key) else { break }
            let entry = RelayInboxEntry(key: key, message: message)
            if include(entry) {
                matches.append(entry)
            }
            currentKey = message.prevKey
            scanned += 1
        }

        return matches.reversed()
    }

    private func getHead(peer: String) async throws -> RelayHeadDoc? {
        try await getHeadState(peer: peer)?.doc
    }

    private func getHeadState(peer: String) async throws -> (doc: RelayHeadDoc, etag: String?)? {
        let key = Self.makeHeadKey(recipient: peer)
        guard let (data, etag) = try await store.getData(key: key) else {
            return nil
        }
        let doc = try JSONDecoder().decode(RelayHeadDoc.self, from: data)
        return (doc, etag)
    }

    private func readMessage(key: String) async throws -> RelayMessage? {
        guard let (data, _) = try await store.getData(key: key) else { return nil }
        return try JSONDecoder().decode(RelayMessage.self, from: data)
    }

    nonisolated static func makeHeadKey(recipient: String) -> String {
        "head/\(recipient).json"
    }

    nonisolated static func makeMessageKey(recipient: String, timestampMS: TimeInterval) -> String {
        let maxMS = 9_999_999_999_999.0
        let reversed = Int(maxMS - timestampMS)
        let revString = leftPadded(String(reversed), toLength: 13, withPad: "0")
        return "msg/\(recipient)/\(revString)-\(shortID()).json"
    }

    nonisolated static func makeAttachmentKey(
        recipient: String,
        messageID: String,
        index: Int,
        fileName: String?,
        timestampMS: TimeInterval
    ) -> String {
        let maxMS = 9_999_999_999_999.0
        let reversed = Int(maxMS - timestampMS)
        let revString = leftPadded(String(reversed), toLength: 13, withPad: "0")
        let safeMessageID = messageID.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "", options: .regularExpression)
        let safeIndex = leftPadded(String(index), toLength: 2, withPad: "0")
        let safeName: String = {
            guard let fileName = fileName?.trimmingCharacters(in: .whitespacesAndNewlines), !fileName.isEmpty else {
                return ""
            }
            let cleaned = fileName.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "", options: .regularExpression)
            return cleaned.isEmpty ? "" : "-\(cleaned)"
        }()
        return "att/\(recipient)/\(revString)-\(safeMessageID)-\(safeIndex)\(safeName)"
    }

    private nonisolated static func shortID() -> String {
        String(UUID().uuidString.prefix(8)).lowercased()
    }

    private nonisolated static func leftPadded(_ value: String, toLength: Int, withPad character: Character) -> String {
        if value.count >= toLength { return value }
        return String(repeating: String(character), count: toLength - value.count) + value
    }

    private func normalizedCASMatchETag(_ value: String?) -> String? {
        guard var etag = value?.trimmingCharacters(in: .whitespacesAndNewlines), !etag.isEmpty else {
            return nil
        }
        if etag.hasPrefix("W/") {
            etag.removeFirst(2)
        }
        etag = etag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !etag.hasPrefix("\"") {
            etag = "\"\(etag.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))\""
        }
        return etag
    }

    private func storePut(key: String, payload: Data, ifMatch: String?, ifNoneMatch: String?) async throws {
        try await store.putData(key: key, data: payload, contentType: "application/json", ifMatch: ifMatch, ifNoneMatch: ifNoneMatch)
    }
}

enum RelayMessagingError: LocalizedError {
    case casRetryFailed

    var errorDescription: String? {
        switch self {
        case .casRetryFailed:
            return String(localized: "Failed to append message after relay CAS retries.")
        }
    }
}
