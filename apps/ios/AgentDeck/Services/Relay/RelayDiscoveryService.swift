import Foundation

struct RelayDiscoveryService {
    static let protocolName = "r2-relay"
    static let protocolVersion = 3
    private let store: R2ObjectStore
    private static let staleIdentityInterval: TimeInterval = 12 * 60 * 60

    init(config: ConnectionConfig) {
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

    func discoverGateways() async throws -> [GatewaySection] {
        let keys = try await listIdentityKeys()
        let identities = try await fetchIdentities(keys: keys)
        let supportedIdentities = identities.filter(Self.isSupportedIdentity)
        let sections = supportedIdentities
            .filter(Self.isFreshServerIdentity)
            .map(Self.makeGatewaySection(from:))
            .sorted { ($0.gateway.lastSeenAt ?? .distantPast) > ($1.gateway.lastSeenAt ?? .distantPast) }

        if sections.isEmpty, !identities.isEmpty, supportedIdentities.isEmpty {
            throw RelayDiscoveryError.unsupportedProtocol
        }
        if sections.isEmpty {
            throw RelayDiscoveryError.noGatewaysFound
        }

        return sections
    }

    private func listIdentityKeys() async throws -> [String] {
        try await store.listKeys(prefix: "identity/")
            .filter { $0.hasPrefix("identity/") && $0.hasSuffix(".json") }
    }

    private func fetchIdentities(keys: [String]) async throws -> [RemoteIdentityDoc] {
        await withTaskGroup(of: RemoteIdentityDoc?.self) { group in
            for key in keys {
                group.addTask {
                    try? await fetchIdentity(key: key)
                }
            }

            var docs: [RemoteIdentityDoc] = []
            for await doc in group {
                guard let doc else { continue }
                docs.append(doc)
            }
            return docs
        }
    }

    private func fetchIdentity(key: String) async throws -> RemoteIdentityDoc {
        guard let (data, _) = try await store.getData(key: key) else {
            throw RelayDiscoveryError.discoveryUnavailable
        }
        return try JSONDecoder().decode(RemoteIdentityDoc.self, from: data)
    }

    private static func makeGatewaySection(from doc: RemoteIdentityDoc) -> GatewaySection {
        let gatewayID = GatewayID(rawValue: doc.peer)
        let displayName = normalizedDisplayName(doc.displayName, fallback: doc.peer)

        // Collect models from agents (first agent that has them) or legacy top-level
        let agentModels: RemoteIdentityModelCapabilities? = doc.agents.first(where: { $0.models != nil })?.models
        let models = (agentModels?.available ?? []).map {
            ModelDescriptor(id: $0.id, label: $0.label, provider: $0.provider)
        }
        let defaultModelID = agentModels?.default

        let gateway = Gateway(
            id: gatewayID,
            displayName: displayName,
            softwareID: doc.software.id,
            softwareName: doc.software.name,
            softwareVersion: doc.software.version,
            protocolVersion: doc.protocol_.version,
            lastSeenAt: decodedDate(from: doc.lastSeen),
            availableModels: models,
            defaultModelID: defaultModelID
        )
        let conversationSessions = doc.conversations.map { conversation in
            ChatSession(
                id: SessionID(rawValue: "\(doc.peer)::\(conversation.route.agentID)::\(conversation.route.conversationID ?? "default")"),
                gatewayID: gatewayID,
                agentID: conversation.route.agentID,
                route: conversation.route,
                title: conversation.displayTitle ?? conversation.id,
                localTitle: nil,
                previewText: "",
                updatedAt: decodedDate(from: conversation.updatedAt),
                unreadCount: 0,
                source: conversation.source
            )
        }
        var sessionsByID: [String: ChatSession] = [:]
        for session in conversationSessions {
            sessionsByID[session.id.rawValue] = session
        }

        for agent in doc.agents {
            let route = agent.defaultRoute
            let sessionID = "\(doc.peer)::\(route.agentID)::\(route.conversationID ?? "default")"
            guard sessionsByID[sessionID] == nil else { continue }
            sessionsByID[sessionID] = ChatSession(
                id: SessionID(rawValue: sessionID),
                gatewayID: gatewayID,
                agentID: route.agentID,
                route: route,
                title: agent.displayName ?? route.agentID,
                localTitle: nil,
                previewText: "",
                updatedAt: nil,
                unreadCount: 0,
                source: nil
            )
        }

        let sessions = Array(sessionsByID.values)
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }

        return GatewaySection(id: gatewayID, gateway: gateway, sessions: sessions)
    }

    private static func normalizedDisplayName(_ candidate: String?, fallback: String) -> String {
        let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        return fallback
            .replacingOccurrences(of: "[-_.]+", with: " ", options: .regularExpression)
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private static func isFreshServerIdentity(_ doc: RemoteIdentityDoc) -> Bool {
        guard doc.role.lowercased() == "server" else { return false }
        guard let lastSeen = decodedUnixTimestamp(from: doc.lastSeen) else { return false }
        return Date().timeIntervalSince1970 - lastSeen <= staleIdentityInterval
    }

    static func isSupportedIdentity(_ doc: RemoteIdentityDoc) -> Bool {
        doc.protocol_.name == protocolName && doc.protocol_.version == protocolVersion
    }

    private static func decodedDate(from rawValue: TimeInterval?) -> Date? {
        guard let unixSeconds = decodedUnixTimestamp(from: rawValue) else { return nil }
        return Date(timeIntervalSince1970: unixSeconds)
    }

    private static func decodedUnixTimestamp(from rawValue: TimeInterval?) -> TimeInterval? {
        guard let rawValue, rawValue > 10_000_000_000 else { return nil }
        return rawValue / 1000
    }
}
