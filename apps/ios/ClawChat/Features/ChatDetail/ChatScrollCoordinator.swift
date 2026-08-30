import Foundation
import Observation

@MainActor
@Observable
final class ChatScrollCoordinator {
    enum Mode: Equatable {
        case followingLatest
        case readingHistory
    }

    var mode: Mode = .followingLatest
    var isNearBottom = true
    var preservedTopMessageID: String?
    var showJumpToBottom = false

    func willLoadOlder(topVisibleID: String?) {
        preservedTopMessageID = topVisibleID
        mode = .readingHistory
        isNearBottom = false
        showJumpToBottom = true
    }

    func didFinishLoadingOlder() {
        preservedTopMessageID = nil
    }

    func updateNearBottom(_ value: Bool) {
        isNearBottom = value
        if value {
            mode = .followingLatest
            showJumpToBottom = false
        } else {
            if mode == .followingLatest {
                mode = .readingHistory
            }
            showJumpToBottom = true
        }
    }

    func requestJumpToBottom() {
        mode = .followingLatest
        isNearBottom = true
        showJumpToBottom = false
    }

    func shouldAutoScrollAfterTranscriptUpdate() -> Bool {
        mode == .followingLatest || isNearBottom
    }
}
