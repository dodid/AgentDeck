import Foundation
import SwiftUI

@MainActor
@Observable
final class AttachmentDownloadManager {
    static let shared = AttachmentDownloadManager()
    static var defaultEnvironment: AppEnvironment?

    private var cache: [String: AttachmentCacheEntry] = [:]
    private let fileManager = FileManager.default
    private let decodedImages = NSCache<NSString, UIImage>()
    private var exportedFiles: [String: URL] = [:]

    enum AttachmentCacheEntry {
        case loading
        case loaded(Data, String?)
        case failed(String)
    }

    nonisolated static func persistedAttachmentsDirectory(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("relay-attachments", isDirectory: true)
    }

    nonisolated static func draftAttachmentsDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.temporaryDirectory.appendingPathComponent("agentdeck-drafts", isDirectory: true)
    }

    nonisolated static func exportsDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.temporaryDirectory.appendingPathComponent("agentdeck-exports", isDirectory: true)
    }

    nonisolated static func storageDirectories(fileManager: FileManager = .default) -> [URL] {
        [
            persistedAttachmentsDirectory(fileManager: fileManager),
            draftAttachmentsDirectory(fileManager: fileManager),
            exportsDirectory(fileManager: fileManager)
        ]
    }

    func state(for objectKey: String) -> AttachmentCacheEntry? {
        if let entry = cache[objectKey] {
            return entry
        }
        if let data = persistedData(for: objectKey) {
            return .loaded(data, guessMimeType(from: objectKey))
        }
        return nil
    }

    // MARK: - Seeding from local files

    /// Seed the cache from a local file path immediately, no network needed.
    /// Safe to call repeatedly — skips if already cached.
    func seedFromLocalFile(objectKey: String, localPath: String) {
        guard cache[objectKey] == nil, !localPath.isEmpty else { return }
        let fileURL = localPath.hasPrefix("file://")
            ? URL(string: localPath) ?? URL(fileURLWithPath: localPath)
            : URL(fileURLWithPath: localPath)
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let mimeType = guessMimeType(from: localPath)
        cache[objectKey] = .loaded(data, mimeType)
        persistData(data, for: objectKey)
    }

    // MARK: - Remote download

    func download(objectKey: String, environment: AppEnvironment) {
        guard cache[objectKey] == nil else { return }
        cache[objectKey] = .loading

        Task {
            do {
                guard let config = try await (environment.connectionRepository as? DefaultConnectionRepository)?.loadConnectionConfig() else {
                    cache[objectKey] = .failed("No connection config")
                    return
                }
                let store = R2S3ObjectStore(
                    endpoint: config.endpoint,
                    bucket: config.bucket,
                    region: config.region,
                    accessKeyID: config.accessKeyID,
                    secretAccessKey: config.secretAccessKey,
                    forcePathStyle: config.forcePathStyle
                )
                guard let (data, _) = try await store.getData(key: objectKey) else {
                    cache[objectKey] = .failed("Not found")
                    return
                }
                let mimeType = guessMimeType(from: objectKey)
                cache[objectKey] = .loaded(data, mimeType)
                persistData(data, for: objectKey)
            } catch {
                cache[objectKey] = .failed(error.localizedDescription)
            }
        }
    }

    func ensureDownloaded(objectKey: String) {
        guard cache[objectKey] == nil, let environment = Self.defaultEnvironment else { return }
        download(objectKey: objectKey, environment: environment)
    }

    // MARK: - Cache access

    func cachedImage(for objectKey: String) -> UIImage? {
        if let image = decodedImages.object(forKey: objectKey as NSString) {
            return image
        }
        guard let data = cachedData(for: objectKey) else { return nil }
        guard let image = UIImage(data: data) else { return nil }
        decodedImages.setObject(image, forKey: objectKey as NSString)
        return image
    }

    func cachedData(for objectKey: String) -> Data? {
        if case .loaded(let data, _) = cache[objectKey] {
            return data
        }
        return persistedData(for: objectKey)
    }

    func exportToTempFile(objectKey: String, fileName: String?) -> URL? {
        let name = fileName ?? objectKey.components(separatedBy: "/").last ?? "attachment"
        let exportKey = "\(objectKey)|\(name)"
        if let existing = exportedFiles[exportKey], fileManager.fileExists(atPath: existing.path) {
            return existing
        }

        let tempDir = Self.exportsDirectory(fileManager: fileManager)
            .appendingPathComponent(sanitizedFileComponent(objectKey), isDirectory: true)
        try? fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let url = tempDir.appendingPathComponent(name, isDirectory: false)

        if !fileManager.fileExists(atPath: url.path) {
            if let persistedURL = persistedFileURLIfExists(for: objectKey) {
                do {
                    try linkOrCopyItem(from: persistedURL, to: url)
                } catch {
                    guard let data = cachedData(for: objectKey) else { return nil }
                    try? data.write(to: url, options: .atomic)
                }
            } else {
                guard let data = cachedData(for: objectKey) else { return nil }
                try? data.write(to: url, options: .atomic)
            }
        }

        exportedFiles[exportKey] = url
        return url
    }

    func clearInMemoryCache() {
        cache.removeAll()
        exportedFiles.removeAll()
        decodedImages.removeAllObjects()
    }

    // MARK: - Private

    private func guessMimeType(from key: String) -> String? {
        let ext = (key as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/mp4"
        case "pdf": return "application/pdf"
        default: return nil
        }
    }

    private func persistedData(for objectKey: String) -> Data? {
        let url = persistedFileURL(for: objectKey)
        return try? Data(contentsOf: url)
    }

    private func persistedFileURLIfExists(for objectKey: String) -> URL? {
        let url = persistedFileURL(for: objectKey)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private func persistData(_ data: Data, for objectKey: String) {
        let url = persistedFileURL(for: objectKey)
        let directory = url.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private func persistedFileURL(for objectKey: String) -> URL {
        let safeName = objectKey.replacingOccurrences(of: "/", with: "__")
        return Self.persistedAttachmentsDirectory(fileManager: fileManager)
            .appendingPathComponent(safeName, isDirectory: false)
    }

    private func sanitizedFileComponent(_ value: String) -> String {
        value.replacingOccurrences(of: "/", with: "__")
    }

    private func linkOrCopyItem(from sourceURL: URL, to destinationURL: URL) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            return
        }
        do {
            try fileManager.linkItem(at: sourceURL, to: destinationURL)
        } catch {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
    }
}
