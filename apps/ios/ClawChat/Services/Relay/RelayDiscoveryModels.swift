import Foundation

// MARK: - v3 Remote Identity Doc

struct RemoteProtocolInfo: Codable, Equatable {
    var name: String
    var version: Int
}

struct RemoteSoftwareInfo: Codable, Equatable {
    var id: String
    var name: String?
    var version: String?
}

struct RemoteMessagingCapabilities: Codable, Equatable {
    var text: Bool
    var streaming: Bool
    var reactions: Bool
    var systemEvents: Bool

    enum CodingKeys: String, CodingKey {
        case text
        case streaming
        case reactions
        case systemEvents = "system_events"
    }
}

struct RemoteConversationCapabilities: Codable, Equatable {
    var list: Bool
    var create: Bool
    var reset: Bool
    var archive: Bool
    var threading: Bool
}

struct RemoteAgentCapabilities: Codable, Equatable {
    var list: Bool
    var multiple: Bool
    var switch_: Bool
    var perAgentModels: Bool

    enum CodingKeys: String, CodingKey {
        case list
        case multiple
        case switch_ = "switch"
        case perAgentModels = "per_agent_models"
    }
}

struct RemoteRelayCapabilities: Codable, Equatable {
    var messaging: RemoteMessagingCapabilities
    var conversations: RemoteConversationCapabilities
    var agents: RemoteAgentCapabilities
    var attachments: RemoteAttachmentCapabilities?
    var approvals: RemoteApprovalCapabilities?
    var extensions: [String: JSONValue]?
}

struct RemoteAttachmentCapabilities: Codable, Equatable {
    var supported: Bool
    var kinds: [String]
    var maxBytesByKind: [String: Int]?
    var oversizeBehavior: String?

    enum CodingKeys: String, CodingKey {
        case supported
        case kinds
        case maxBytesByKind = "max_bytes_by_kind"
        case oversizeBehavior = "oversize_behavior"
    }
}

struct RemoteApprovalCapabilities: Codable, Equatable {
    var exec: Bool
    var tool: Bool
    var custom: Bool
}

struct RemoteAgentDescriptor: Codable, Equatable {
    var id: String
    var displayName: String?
    var description: String?
    var isDefault: Bool
    var models: RemoteIdentityModelCapabilities?
    var defaultRoute: RelayRoute
    var capabilities: RemoteRelayCapabilities?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case description
        case isDefault = "is_default"
        case models
        case defaultRoute = "default_route"
        case capabilities
    }
}

struct RemoteConversationSource: Codable, Equatable {
    var channel: String
    var chatKind: String?
    var accountID: String?
    var accountDisplay: String?
    var spaceID: String?
    var spaceDisplay: String?
    var chatID: String?
    var chatDisplay: String?
    var participantID: String?
    var participantDisplay: String?
    var threadID: String?
    var threadDisplay: String?
    var sharing: String?

    enum CodingKeys: String, CodingKey {
        case channel
        case chatKind = "chat_kind"
        case accountID = "account_id"
        case accountDisplay = "account_display"
        case spaceID = "space_id"
        case spaceDisplay = "space_display"
        case chatID = "chat_id"
        case chatDisplay = "chat_display"
        case participantID = "participant_id"
        case participantDisplay = "participant_display"
        case threadID = "thread_id"
        case threadDisplay = "thread_display"
        case sharing
    }
}

struct RemoteConversationDescriptor: Codable, Equatable {
    var id: String
    var displayTitle: String?
    var route: RelayRoute
    var source: RemoteConversationSource?
    var updatedAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case id
        case displayTitle = "display_title"
        case route
        case source
        case updatedAt = "updated_at"
    }
}

struct RemoteIdentityDoc: Codable {
    var peer: String
    var displayName: String
    var role: String
    var protocol_: RemoteProtocolInfo
    var software: RemoteSoftwareInfo
    var capabilities: RemoteRelayCapabilities
    var lastSeen: TimeInterval
    var agents: [RemoteAgentDescriptor]
    var conversations: [RemoteConversationDescriptor]
    var limits: RemoteIdentityServerLimits?

    enum CodingKeys: String, CodingKey {
        case peer
        case displayName = "display_name"
        case role
        case protocol_ = "protocol"
        case software
        case capabilities
        case lastSeen = "last_seen"
        case agents
        case conversations
        case limits
    }
}

// MARK: - Shared support types

enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct RemoteIdentityModelInfo: Codable, Equatable {
    var id: String
    var label: String?
    var provider: String?
}

struct RemoteIdentityModelCapabilities: Codable, Equatable {
    var available: [RemoteIdentityModelInfo]
    var `default`: String?
}

struct RemoteIdentityAttachmentLimits: Codable, Equatable {
    var image: Int
    var video: Int
    var audio: Int
    var file: Int
}

struct RemoteIdentityServerLimits: Codable, Equatable {
    var inboundAttachmentMaxBytes: RemoteIdentityAttachmentLimits?
    var oversizeAttachmentBehavior: String?

    enum CodingKeys: String, CodingKey {
        case inboundAttachmentMaxBytes = "inbound_attachment_max_bytes"
        case oversizeAttachmentBehavior = "oversize_attachment_behavior"
    }
}

enum RelayDiscoveryError: LocalizedError {
    case discoveryUnavailable
    case noGatewaysFound
    case unsupportedProtocol

    var errorDescription: String? {
        switch self {
        case .discoveryUnavailable:
            return String(localized: "Relay discovery is unavailable.")
        case .noGatewaysFound:
            return String(localized: "Connected, but no gateways were discovered.")
        case .unsupportedProtocol:
            return String(localized: "The relay server does not support R2 Relay protocol v3.")
        }
    }
}
