import Foundation

enum SyncReason: Equatable {
    case appLaunch
    case foreground
    case manualRefresh
    case sessionOpened(SessionID)
    case messageSent(SessionID)
}

protocol SyncRepository: Sendable {
    func startPolling() async
    func stopPolling() async
    func requestImmediateSync(reason: SyncReason) async
    func refreshNow() async throws
    func sendMessage(_ text: String, attachments: [DraftAttachment], to sessionID: SessionID) async throws
    func sendApprovalResponse(approvalID: String, decision: String, to sessionID: SessionID) async throws
    func backfill(sessionID: SessionID, limit: Int) async throws
}
