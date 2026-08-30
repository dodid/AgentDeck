import Foundation

struct ExecApprovalMetadata: Codable, Equatable, Sendable {
    let approvalID: String
    let approvalKind: String
    let title: String
    let body: String?
    let allowedDecisions: [String]
}

struct ExecApprovalResolution: Codable, Equatable, Sendable {
    let decision: String
}

struct MessageID: Hashable, Codable, Equatable, Identifiable, Sendable {
    let rawValue: String
    var id: String { rawValue }
}

enum MessageSender: Equatable, Sendable {
    case user(deviceID: String)
    case assistant(gatewayID: GatewayID)
}

enum MessageDeliveryState: Equatable, Sendable {
    case localOnly
    case sending
    case sentToRelay
    case confirmed
    case failed(String)
}

enum MessageStreamState: Equatable, Sendable {
    case none
    case partial(streamID: String, sequence: Int)
    case complete
}

enum AttachmentKind: String, Codable, Equatable, Sendable {
    case image
    case video
    case audio
    case file
    case unknown
}

enum AttachmentTransferState: String, Codable, Equatable, Sendable {
    case pending
    case uploaded
    case available
    case failed
}

struct ChatAttachment: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let objectKey: String
    let previewObjectKey: String?
    let fileName: String?
    let mimeType: String?
    let sizeBytes: Int?
    let sha256: String?
    let kind: AttachmentKind
    let width: Int?
    let height: Int?
    let durationMS: Int?
    let transferState: AttachmentTransferState
    let localCacheURL: String?
    let previewCacheURL: String?
}

struct DraftAttachment: Equatable, Identifiable, Sendable {
    let id: String
    let fileName: String?
    let mimeType: String?
    let sizeBytes: Int?
    let kind: AttachmentKind
    let localURL: String?
}

struct ChatMessage: Equatable, Identifiable, Sendable {
    let id: MessageID
    let sessionID: SessionID
    let sender: MessageSender
    let text: String
    let attachments: [ChatAttachment]
    let sentAt: Date
    var deliveryState: MessageDeliveryState
    var streamState: MessageStreamState
    var streamID: String?
    var remoteObjectKey: String?
    var remoteMessageID: String?
    var execApproval: ExecApprovalMetadata?
    var execApprovalResolution: ExecApprovalResolution?
}

struct TranscriptPage: Equatable, Sendable {
    var messages: [ChatMessage]
    var canLoadMore: Bool
}

struct StorageStats: Equatable, Sendable {
    var threadCount: Int
    var messageCount: Int
    var sessionDataSizeBytes: Int64
    var attachmentDataSizeBytes: Int64

    var totalFileSizeBytes: Int64 {
        sessionDataSizeBytes + attachmentDataSizeBytes
    }
}
