import Foundation
import UniformTypeIdentifiers

enum ApprovalDecision: String, Equatable, Sendable {
    case allowOnce = "allow-once"
    case allowAlways = "allow-always"
    case deny = "deny"
}

enum ApprovalCardState: Equatable, Sendable {
    case pending
    case sending(ApprovalDecision)
    case resolved(ApprovalDecision)
    case failed(ApprovalDecision, String)
}

enum TranscriptRowStyle: Equatable {
    case userSending
    case userSentToRelay
    case userConfirmed
    case userFailed(String?)
    case assistant
}

struct TranscriptAttachmentViewData: Identifiable, Equatable {
    let id: String
    let messageID: String
    let title: String
    let detail: String?
    let kind: AttachmentKind
    let transferState: AttachmentTransferState
    let isFromUser: Bool
    let objectKey: String
    let previewObjectKey: String?
    let localCacheURL: String?
    let mimeType: String?
    let sizeBytes: Int?
    let width: Int?
    let height: Int?
}

enum AttachmentTapAffordance: Equatable {
    case imageViewer
    case videoViewer
    case quickLook
    case share

    var symbolName: String {
        switch self {
        case .imageViewer:
            return "arrow.up.left.and.arrow.down.right"
        case .videoViewer:
            return "play.rectangle"
        case .quickLook:
            return "doc.text.magnifyingglass"
        case .share:
            return "square.and.arrow.up"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .imageViewer:
            return String(localized: "Open image")
        case .videoViewer:
            return String(localized: "Play video")
        case .quickLook:
            return String(localized: "Preview attachment")
        case .share:
            return String(localized: "Share attachment")
        }
    }
}

extension TranscriptAttachmentViewData {
    var primaryTapAffordance: AttachmentTapAffordance {
        switch kind {
        case .image:
            return .imageViewer
        case .video:
            return .videoViewer
        case .audio:
            return .quickLook
        case .file, .unknown:
            return isQuickLookPreferred ? .quickLook : .share
        }
    }

    private var isQuickLookPreferred: Bool {
        if let mimeType = mimeType?.trimmingCharacters(in: .whitespacesAndNewlines),
           !mimeType.isEmpty,
           let type = UTType(mimeType: mimeType) {
            if type.conforms(to: .pdf) || type.conforms(to: .plainText) || type.conforms(to: .text) || type.conforms(to: .rtf) || type.conforms(to: .json) || type.conforms(to: .xml) {
                return true
            }
        }

        let ext = (title as NSString).pathExtension.lowercased()
        return ["pdf", "txt", "md", "rtf", "json", "xml", "csv", "html", "htm"].contains(ext)
    }
}

struct TranscriptItemViewData: Identifiable, Equatable {
    let id: String
    let text: String
    let attachments: [TranscriptAttachmentViewData]
    let isFromUser: Bool
    let timestampText: String
    let style: TranscriptRowStyle
    let statusText: String?
    let showsHeader: Bool
    let showsDivider: Bool
    let showsDeliveryStatus: Bool
    let execApproval: ExecApprovalMetadata?
    let execApprovalResolution: ExecApprovalResolution?
}

struct TranscriptDateSeparatorViewData: Identifiable, Equatable {
    let id: String
    let title: String
}

struct StreamingTranscriptItemViewData: Identifiable, Equatable {
    let id: String
    let text: String
    let timestampText: String
    let isTerminalStyle: Bool
}

enum TranscriptDisplayItem: Identifiable, Equatable {
    case message(TranscriptItemViewData)
    case dateSeparator(TranscriptDateSeparatorViewData)
    case streaming(StreamingTranscriptItemViewData)

    var id: String {
        switch self {
        case .message(let item): return item.id
        case .dateSeparator(let item): return item.id
        case .streaming(let item): return item.id
        }
    }
}
