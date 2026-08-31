import Foundation
@testable import AgentDeck

enum TestObjectStoreError: Error {
    case preconditionFailed
}

actor TestObjectStore: R2ObjectStore {
    private struct StoredObject {
        var data: Data
        var etag: String
    }

    private var objects: [String: StoredObject] = [:]
    private var revision = 0
    private var remainingHeadWriteFailures = 0

    func failNextHeadWrites(_ count: Int) {
        remainingHeadWriteFailures = count
    }

    func getData(key: String) async throws -> (data: Data, etag: String?)? {
        guard let object = objects[key] else { return nil }
        return (object.data, object.etag)
    }

    func putData(
        key: String,
        data: Data,
        contentType _: String?,
        ifMatch: String?,
        ifNoneMatch: String?
    ) async throws {
        if key.hasPrefix("head/"), remainingHeadWriteFailures > 0 {
            remainingHeadWriteFailures -= 1
            throw TestObjectStoreError.preconditionFailed
        }
        if ifNoneMatch == "*", objects[key] != nil {
            throw TestObjectStoreError.preconditionFailed
        }
        if let ifMatch {
            guard normalized(ifMatch) == objects[key].map({ normalized($0.etag) }) else {
                throw TestObjectStoreError.preconditionFailed
            }
        }
        revision += 1
        objects[key] = StoredObject(data: data, etag: "\"etag-\(revision)\"")
    }

    func listKeys(prefix: String) async throws -> [String] {
        objects.keys.filter { $0.hasPrefix(prefix) }.sorted()
    }

    func seedJSON<T: Encodable>(_ value: T, key: String) throws {
        revision += 1
        objects[key] = StoredObject(data: try JSONEncoder().encode(value), etag: "\"etag-\(revision)\"")
    }

    private func normalized(_ etag: String) -> String {
        etag.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }
}

func makeTestIdentity(
    peer: String,
    role: String = "server",
    protocolVersion: Int = 3,
    lastSeenMS: TimeInterval = Date().timeIntervalSince1970 * 1000,
    agents: [RemoteAgentDescriptor] = [],
    conversations: [RemoteConversationDescriptor] = []
) -> RemoteIdentityDoc {
    RemoteIdentityDoc(
        peer: peer,
        displayName: peer,
        role: role,
        protocol_: RemoteProtocolInfo(name: "r2-relay", version: protocolVersion),
        software: RemoteSoftwareInfo(id: "test-platform", name: "Test Platform", version: "1.0.0"),
        capabilities: RemoteRelayCapabilities(
            messaging: RemoteMessagingCapabilities(text: true, streaming: true, reactions: true, systemEvents: false),
            conversations: RemoteConversationCapabilities(list: true, create: false, reset: false, archive: false, threading: true),
            agents: RemoteAgentCapabilities(list: true, multiple: true, switch_: true, perAgentModels: true),
            attachments: RemoteAttachmentCapabilities(supported: true, kinds: ["image", "file"], maxBytesByKind: nil, oversizeBehavior: "reject"),
            approvals: RemoteApprovalCapabilities(exec: true, tool: false, custom: false),
            extensions: nil
        ),
        lastSeen: lastSeenMS,
        agents: agents,
        conversations: conversations,
        limits: nil
    )
}

func makeRelayMessage(
    id: String,
    from: String,
    to: String,
    timestamp: TimeInterval,
    previousKey: String? = nil,
    conversationID: String = "agent:main:main",
    content: RelayContent,
    delivery: RelayDelivery? = nil
) -> RelayMessage {
    RelayMessage(
        msgID: id,
        from: from,
        to: to,
        tsSent: timestamp,
        prevKey: previousKey,
        route: RelayRoute(agentID: "main", conversationID: conversationID, instanceID: nil),
        content: content,
        delivery: delivery,
        status: nil,
        size: nil
    )
}
