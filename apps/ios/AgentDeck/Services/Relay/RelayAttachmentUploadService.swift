import Foundation
import CryptoKit
import UniformTypeIdentifiers

struct RelayAttachmentUploadService: Sendable {
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

    func uploadDraftAttachments(
        _ attachments: [DraftAttachment],
        recipient: String,
        messageID: MessageID,
        timestampMS: TimeInterval
    ) async throws -> [RelayAttachment] {
        var uploaded: [RelayAttachment] = []
        uploaded.reserveCapacity(attachments.count)

        for (index, attachment) in attachments.enumerated() {
            guard let localURLString = attachment.localURL, !localURLString.isEmpty else {
                throw RelayAttachmentUploadError.missingLocalFile(attachment.fileName ?? attachment.id)
            }

            let fileURL = Self.fileURL(from: localURLString)
            let data: Data
            do {
                data = try Data(contentsOf: fileURL)
            } catch {
                throw RelayAttachmentUploadError.unreadableLocalFile(fileURL.lastPathComponent)
            }

            let objectKey = RelayMessagingService.makeAttachmentKey(
                recipient: recipient,
                messageID: messageID.rawValue,
                index: index + 1,
                fileName: attachment.fileName,
                timestampMS: timestampMS
            )
            let contentType = normalizedContentType(attachment.mimeType, for: attachment.kind, fileURL: fileURL)
            try await store.putData(
                key: objectKey,
                data: data,
                contentType: contentType,
                ifMatch: nil,
                ifNoneMatch: "*"
            )

            let metadata = await AttachmentMetadataExtractor.extractMetadata(fileURL: fileURL, kind: attachment.kind)

            var previewImageKey: String?
            var previewImageType: String?
            var previewSize: Int?

            if let preview = await AttachmentMetadataExtractor.generatePreview(fileURL: fileURL, kind: attachment.kind) {
                let previewKey = objectKey + ".preview.jpg"
                try await store.putData(
                    key: previewKey,
                    data: preview.jpegData,
                    contentType: "image/jpeg",
                    ifMatch: nil,
                    ifNoneMatch: "*"
                )
                previewImageKey = previewKey
                previewImageType = "image/jpeg"
                previewSize = preview.jpegData.count
            }

            uploaded.append(
                RelayAttachment(
                    id: attachment.id,
                    key: objectKey,
                    fileName: attachment.fileName,
                    contentType: contentType,
                    size: attachment.sizeBytes ?? data.count,
                    sha256: Self.sha256Hex(data),
                    kind: Self.relayKind(from: attachment.kind),
                    width: metadata.width,
                    height: metadata.height,
                    durationMS: metadata.durationMS,
                    previewImageKey: previewImageKey,
                    previewImageType: previewImageType,
                    previewSize: previewSize
                )
            )
        }

        return uploaded
    }

    private nonisolated static func fileURL(from raw: String) -> URL {
        if raw.hasPrefix("file://"), let url = URL(string: raw) {
            return url
        }
        return URL(fileURLWithPath: raw)
    }

    private nonisolated func normalizedContentType(_ mimeType: String?, for kind: AttachmentKind, fileURL: URL) -> String {
        if let mimeType = mimeType?.trimmingCharacters(in: .whitespacesAndNewlines), !mimeType.isEmpty {
            return mimeType
        }
        if let resourceType = try? fileURL.resourceValues(forKeys: [.contentTypeKey]).contentType,
           let resourceMimeType = resourceType.preferredMIMEType,
           !resourceMimeType.isEmpty {
            return resourceMimeType
        }
        let pathExtension = fileURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pathExtension.isEmpty,
           let inferredType = UTType(filenameExtension: pathExtension),
           let inferredMimeType = inferredType.preferredMIMEType,
           !inferredMimeType.isEmpty {
            return inferredMimeType
        }
        switch kind {
        case .image:
            return "image/jpeg"
        case .video:
            return "video/mp4"
        case .audio:
            return "audio/mpeg"
        case .file, .unknown:
            let ext = fileURL.pathExtension.lowercased()
            if ext == "pdf" {
                return "application/pdf"
            }
            return "application/octet-stream"
        }
    }

    private nonisolated static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func relayKind(from kind: AttachmentKind) -> RelayAttachmentKind {
        switch kind {
        case .image:
            return .image
        case .video:
            return .video
        case .audio:
            return .audio
        case .file:
            return .file
        case .unknown:
            return .unknown
        }
    }
}

enum RelayAttachmentUploadError: LocalizedError {
    case missingLocalFile(String)
    case unreadableLocalFile(String)

    var errorDescription: String? {
        switch self {
        case .missingLocalFile(let name):
            return String.localizedStringWithFormat(String(localized: "Attachment file is missing: %@"), name)
        case .unreadableLocalFile(let name):
            return String.localizedStringWithFormat(String(localized: "Attachment file could not be read: %@"), name)
        }
    }
}
