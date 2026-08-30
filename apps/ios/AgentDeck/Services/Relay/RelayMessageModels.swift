import Foundation

// MARK: - v3 Route

struct RelayRoute: Codable, Equatable, Sendable {
    let agentID: String
    let conversationID: String?
    let instanceID: String?

    enum CodingKeys: String, CodingKey {
        case agentID = "agent_id"
        case conversationID = "conversation_id"
        case instanceID = "instance_id"
    }
}

// MARK: - v3 Content

enum RelayContent: Codable, Equatable, Sendable {
    case text(RelayTextContent)
    case reaction(RelayReactionContent)
    case approvalRequest(RelayApprovalRequestContent)
    case approvalResponse(RelayApprovalResponseContent)
    case system(RelaySystemContent)
    case unknown(type: String)

    private enum TypeKey: String, CodingKey { case type }

    init(from decoder: Decoder) throws {
        let typeContainer = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try typeContainer.decode(String.self, forKey: .type)
        switch type_ {
        case "text":
            self = .text(try RelayTextContent(from: decoder))
        case "reaction":
            self = .reaction(try RelayReactionContent(from: decoder))
        case "approval_request":
            self = .approvalRequest(try RelayApprovalRequestContent(from: decoder))
        case "approval_response":
            self = .approvalResponse(try RelayApprovalResponseContent(from: decoder))
        case "system":
            self = .system(try RelaySystemContent(from: decoder))
        default:
            self = .unknown(type: type_)
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let v): try v.encode(to: encoder)
        case .reaction(let v): try v.encode(to: encoder)
        case .approvalRequest(let v): try v.encode(to: encoder)
        case .approvalResponse(let v): try v.encode(to: encoder)
        case .system(let v): try v.encode(to: encoder)
        case .unknown(let t):
            var c = encoder.container(keyedBy: TypeKey.self)
            try c.encode(t, forKey: .type)
        }
    }
}

struct RelayTextContent: Codable, Equatable, Sendable {
    let type: String
    let text: String
    let attachments: [RelayAttachment]?
}

struct RelayReactionContent: Codable, Equatable, Sendable {
    let type: String
    let targetMsgID: String
    let emoji: String
    let remove: Bool?

    enum CodingKeys: String, CodingKey {
        case type
        case targetMsgID = "target_msg_id"
        case emoji
        case remove
    }
}

struct RelayApprovalRequestContent: Codable, Equatable, Sendable {
    let type: String
    let approvalID: String
    let approvalKind: String
    let title: String
    let body: String?
    let allowedDecisions: [String]
    let metadata: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case type
        case approvalID = "approval_id"
        case approvalKind = "approval_kind"
        case title
        case body
        case allowedDecisions = "allowed_decisions"
        case metadata
    }
}

struct RelayApprovalResponseContent: Codable, Equatable, Sendable {
    let type: String
    let approvalID: String
    let decision: String
    let metadata: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case type
        case approvalID = "approval_id"
        case decision
        case metadata
    }
}

struct RelaySystemContent: Codable, Equatable, Sendable {
    let type: String
    let event: String
    let data: [String: JSONValue]?
}

// MARK: - v3 Delivery

struct RelayDeliveryStream: Codable, Equatable, Sendable {
    let streamID: String
    let seq: Int
    let state: String

    enum CodingKeys: String, CodingKey {
        case streamID = "stream_id"
        case seq
        case state
    }
}

struct RelayDelivery: Codable, Equatable, Sendable {
    let stream: RelayDeliveryStream?
}

// MARK: - v3 Message Status

struct RelayMessageStatus: Codable, Equatable, Sendable {
    let state: String
    let processedAt: TimeInterval?
    let processedBy: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case state
        case processedAt = "processed_at"
        case processedBy = "processed_by"
        case error
    }
}

// MARK: - Attachment

enum RelayAttachmentKind: String, Codable, Sendable {
    case image
    case video
    case audio
    case file
    case unknown
}

struct RelayAttachment: Codable, Equatable, Sendable {
    var id: String
    var key: String
    var fileName: String?
    var contentType: String?
    var size: Int?
    var sha256: String?
    var kind: RelayAttachmentKind
    var width: Int?
    var height: Int?
    var durationMS: Int?
    var previewImageKey: String?
    var previewImageType: String?
    var previewSize: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case key
        case fileName = "file_name"
        case contentType = "content_type"
        case size
        case sha256
        case kind
        case width
        case height
        case durationMS = "duration_ms"
        case previewImageKey = "preview_image_key"
        case previewImageType = "preview_image_type"
        case previewSize = "preview_size"
    }
}

// MARK: - v3 Message

struct RelayMessage: Codable, Sendable {
    var msgID: String
    var from: String
    var to: String
    var tsSent: TimeInterval
    var prevKey: String?
    var route: RelayRoute
    var content: RelayContent
    var delivery: RelayDelivery?
    var status: RelayMessageStatus?
    var size: Int?

    enum CodingKeys: String, CodingKey {
        case msgID = "msg_id"
        case from
        case to
        case tsSent = "ts_sent"
        case prevKey = "prev_key"
        case route
        case content
        case delivery
        case status
        case size
    }
}

struct RelayHeadDoc: Codable, Sendable {
    var headKey: String
    var headMsgID: String
    var headTS: TimeInterval

    enum CodingKeys: String, CodingKey {
        case headKey = "head_key"
        case headMsgID = "head_msg_id"
        case headTS = "head_ts"
    }
}

struct RelayInboxEntry: Sendable {
    let key: String
    let message: RelayMessage
}

struct RelaySendTarget: Sendable {
    let gatewayPeer: String
    let route: RelayRoute
}
