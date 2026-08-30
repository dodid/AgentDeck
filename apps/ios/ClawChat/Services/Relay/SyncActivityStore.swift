import Foundation
import Observation

@MainActor
@Observable
final class SyncActivityStore {
    var isFetchingMessages = false
    private(set) var lastFetchAt: Date?
    private(set) var lastOutgoingSendAt: Date?
    var hasVisibleChat = false
    var hasActiveStreaming = false

    func setFetching(_ value: Bool) {
        isFetchingMessages = value
        if !value {
            lastFetchAt = Date()
        }
    }

    func markOutgoingSend() {
        lastOutgoingSendAt = Date()
    }

    var didRecentlyFetchMessages: Bool {
        guard let lastFetchAt else { return false }
        return Date().timeIntervalSince(lastFetchAt) < 8
    }

    var didRecentlySendMessage: Bool {
        guard let lastOutgoingSendAt else { return false }
        return Date().timeIntervalSince(lastOutgoingSendAt) < 20
    }

    var preferredPollingIntervalSeconds: Int {
        if hasActiveStreaming { return 3 }
        if didRecentlySendMessage { return 4 }
        if hasVisibleChat && didRecentlyFetchMessages { return 6 }
        if hasVisibleChat { return 10 }
        return 16
    }
}
