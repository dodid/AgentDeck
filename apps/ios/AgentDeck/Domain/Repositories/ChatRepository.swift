import Foundation

protocol ChatRepository: Sendable {
    func observeTranscript(sessionID: SessionID, limit: Int) -> AsyncStream<TranscriptPage>
    func sendMessage(_ text: String, attachments: [DraftAttachment], to sessionID: SessionID) async throws
    func loadOlderMessages(for sessionID: SessionID, currentLimit: Int) async throws -> Int
    func refreshSession(_ sessionID: SessionID) async throws
    func clearLocalData() async throws
    func cleanupAttachmentData(olderThan age: LocalDataAgeOption) async throws -> Int64
    func cleanupAllAttachmentData() async throws -> Int64
    func storageStats() async throws -> StorageStats
}
