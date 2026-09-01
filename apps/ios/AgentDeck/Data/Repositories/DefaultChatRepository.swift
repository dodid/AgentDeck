import Foundation

actor SessionListStore {
    private var continuations: [UUID: AsyncStream<[GatewaySection]>.Continuation] = [:]

    func stream(initial: [GatewaySection]) -> AsyncStream<[GatewaySection]> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.yield(initial)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id: id) }
            }
        }
    }

    func publish(_ sections: [GatewaySection]) {
        for continuation in continuations.values {
            continuation.yield(sections)
        }
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }
}

actor TranscriptStore {
    private var continuations: [String: [UUID: AsyncStream<TranscriptPage>.Continuation]] = [:]

    func stream(for sessionID: SessionID, initial: TranscriptPage) -> AsyncStream<TranscriptPage> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[sessionID.rawValue, default: [:]][id] = continuation
            continuation.yield(initial)
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeContinuation(id: id, sessionID: sessionID)
                }
            }
        }
    }

    func publish(_ page: TranscriptPage, for sessionID: SessionID) {
        for continuation in continuations[sessionID.rawValue]?.values ?? [:].values {
            continuation.yield(page)
        }
    }

    private func removeContinuation(id: UUID, sessionID: SessionID) {
        continuations[sessionID.rawValue]?.removeValue(forKey: id)
        if continuations[sessionID.rawValue]?.isEmpty == true {
            continuations.removeValue(forKey: sessionID.rawValue)
        }
    }
}

final class DefaultChatRepository: ChatRepository, @unchecked Sendable {
    let database: AppDatabase
    private let deviceRepository: DeviceRepository
    private let sessionListStore: SessionListStore
    private let transcriptStore: TranscriptStore

    init(
        database: AppDatabase = AppDatabase(),
        deviceRepository: DeviceRepository = DefaultDeviceRepository(),
        sessionListStore: SessionListStore = SessionListStore(),
        transcriptStore: TranscriptStore = TranscriptStore()
    ) {
        self.database = database
        self.deviceRepository = deviceRepository
        self.sessionListStore = sessionListStore
        self.transcriptStore = transcriptStore
    }

    func observeSessionSections() -> AsyncStream<[GatewaySection]> {
        let initial = (try? database.sessionSections()) ?? []
        return AsyncStream { continuation in
            Task {
                let stream = await sessionListStore.stream(initial: initial)
                for await sections in stream {
                    continuation.yield(sections)
                }
                continuation.finish()
            }
        }
    }

    func observeTranscript(sessionID: SessionID, limit: Int) -> AsyncStream<TranscriptPage> {
        let initial = (try? database.transcript(sessionID: sessionID, limit: limit)) ?? TranscriptPage(messages: [], canLoadMore: false)
        return AsyncStream { continuation in
            Task {
                let stream = await transcriptStore.stream(for: sessionID, initial: initial)
                for await page in stream {
                    continuation.yield(page)
                }
                continuation.finish()
            }
        }
    }

    func sendMessage(_ text: String, attachments: [DraftAttachment], to sessionID: SessionID) async throws {
        let device = try await deviceRepository.loadDeviceProfile()
        _ = try database.insertLocalOutgoingMessage(text: text, sessionID: sessionID, deviceID: device.clientID, attachments: attachments)
        let page = try database.transcript(sessionID: sessionID, limit: 50)
        await transcriptStore.publish(page, for: sessionID)
        await publishSessionSections()
    }

    func sendMessageLocally(_ text: String, to sessionID: SessionID) async throws -> MessageID? {
        try await sendMessageLocally(text, attachments: [], to: sessionID)
    }

    func sendMessageLocally(_ text: String, attachments: [DraftAttachment], to sessionID: SessionID) async throws -> MessageID? {
        let device = try await deviceRepository.loadDeviceProfile()
        let messageID = try database.insertLocalOutgoingMessage(text: text, sessionID: sessionID, deviceID: device.clientID, attachments: attachments)
        let page = try database.transcript(sessionID: sessionID, limit: 50)
        await transcriptStore.publish(page, for: sessionID)
        await publishSessionSections()
        return messageID
    }

    func loadOlderMessages(for sessionID: SessionID, currentLimit: Int) async throws -> Int {
        let newLimit = min(currentLimit + 50, 500)
        let page = try database.transcript(sessionID: sessionID, limit: newLimit)
        await transcriptStore.publish(page, for: sessionID)
        return newLimit
    }

    func session(_ sessionID: SessionID) async throws -> ChatSession? {
        try database.session(sessionID: sessionID)
    }

    func refreshSession(_ sessionID: SessionID) async throws {
        let page = try database.transcript(sessionID: sessionID, limit: 50)
        await transcriptStore.publish(page, for: sessionID)
        await publishSessionSections()
    }

    func publishTranscript(for sessionID: SessionID, limit: Int) async {
        if let page = try? database.transcript(sessionID: sessionID, limit: limit) {
            await transcriptStore.publish(page, for: sessionID)
            await publishSessionSections()
        }
    }

    func clearLocalData() async throws {
        try database.clearAllData()
        try Self.removeAllItems(in: AttachmentDownloadManager.storageDirectories())
        await MainActor.run {
            AttachmentDownloadManager.shared.clearInMemoryCache()
        }
        await publishSessionSections()
    }

    func cleanupAttachmentData(olderThan age: LocalDataAgeOption) async throws -> Int64 {
        let beforeSize = try Self.totalSize(of: AttachmentDownloadManager.storageDirectories())
        let cutoffDate = age.cutoffDate()
        let managedRootPaths = Self.managedAttachmentRootPaths()
        let plan = try database.cleanupManagedAttachmentReferences(
            olderThan: cutoffDate,
            managedRootPaths: managedRootPaths
        )
        try Self.removeFiles(at: plan.localFilePaths)
        try Self.pruneFiles(olderThan: cutoffDate, in: AttachmentDownloadManager.storageDirectories())
        await MainActor.run {
            AttachmentDownloadManager.shared.clearInMemoryCache()
        }
        let afterSize = try Self.totalSize(of: AttachmentDownloadManager.storageDirectories())
        return max(beforeSize - afterSize, 0)
    }

    func cleanupAllAttachmentData() async throws -> Int64 {
        let beforeSize = try Self.totalSize(of: AttachmentDownloadManager.storageDirectories())
        let managedRootPaths = Self.managedAttachmentRootPaths()
        let plan = try database.cleanupAllManagedAttachmentReferences(managedRootPaths: managedRootPaths)
        try Self.removeFiles(at: plan.localFilePaths)
        try Self.removeAllItems(in: AttachmentDownloadManager.storageDirectories())
        await MainActor.run {
            AttachmentDownloadManager.shared.clearInMemoryCache()
        }
        let afterSize = try Self.totalSize(of: AttachmentDownloadManager.storageDirectories())
        return max(beforeSize - afterSize, 0)
    }

    func storageStats() async throws -> StorageStats {
        var stats = try database.storageStats()
        stats.attachmentDataSizeBytes = try Self.totalSize(of: AttachmentDownloadManager.storageDirectories())
        return stats
    }

    func upsertDiscoveredSections(_ sections: [GatewaySection]) async throws {
        try database.upsertSessions(sections)
        await publishSessionSections()
    }

    func sessionTitle(_ sessionID: SessionID) async throws -> String {
        try database.sessionTitle(sessionID: sessionID)
    }

    func renameSessionLocally(_ sessionID: SessionID, title: String?) async throws {
        try database.updateLocalSessionTitle(sessionID: sessionID, title: title)
        await publishSessionSections()
    }

    func publishSessionSections() async {
        if let sections = try? database.sessionSections() {
            await sessionListStore.publish(sections)
        }
    }

    private static func managedAttachmentRootPaths() -> [String] {
        AttachmentDownloadManager.storageDirectories().map { $0.standardizedFileURL.path }
    }

    private static func totalSize(of directories: [URL]) throws -> Int64 {
        try directories.reduce(into: Int64(0)) { partialResult, directory in
            partialResult += try directorySize(at: directory)
        }
    }

    private static func directorySize(at directory: URL) throws -> Int64 {
        guard FileManager.default.fileExists(atPath: directory.path) else { return 0 }
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )

        var total: Int64 = 0
        while let item = enumerator?.nextObject() as? URL {
            let values = try item.resourceValues(forKeys: resourceKeys)
            if values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }

    private static func pruneFiles(olderThan cutoffDate: Date, in directories: [URL]) throws {
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        let fileManager = FileManager.default

        for directory in directories where fileManager.fileExists(atPath: directory.path) {
            let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            )

            var staleFiles: [URL] = []
            while let item = enumerator?.nextObject() as? URL {
                let values = try item.resourceValues(forKeys: resourceKeys)
                guard values.isRegularFile == true else { continue }
                if let modifiedAt = values.contentModificationDate, modifiedAt < cutoffDate {
                    staleFiles.append(item)
                }
            }

            for fileURL in staleFiles {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }

    private static func removeFiles(at paths: [String]) throws {
        let fileManager = FileManager.default
        for path in paths {
            guard fileManager.fileExists(atPath: path) else { continue }
            try? fileManager.removeItem(atPath: path)
        }
    }

    private static func removeAllItems(in directories: [URL]) throws {
        let fileManager = FileManager.default
        for directory in directories where fileManager.fileExists(atPath: directory.path) {
            try? fileManager.removeItem(at: directory)
        }
    }
}
