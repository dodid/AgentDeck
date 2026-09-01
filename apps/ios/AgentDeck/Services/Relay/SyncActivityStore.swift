import Foundation
import Observation

@MainActor
@Observable
final class SyncActivityStore {
    var isFetchingMessages = false
    private(set) var lastFetchAt: Date?
    private(set) var lastFetchErrorMessage: String?
    private(set) var lastOutgoingSendAt: Date?
    var hasVisibleChat = false
    var hasActiveStreaming = false
    var messageFetchPreset: MessageFetchPreset = .balanced
    private var activeFetchCount = 0

    func beginFetch() {
        activeFetchCount += 1
        isFetchingMessages = true
    }

    func endFetch(succeeded: Bool, errorMessage: String? = nil) {
        activeFetchCount = max(0, activeFetchCount - 1)
        isFetchingMessages = activeFetchCount > 0
        if succeeded {
            lastFetchAt = Date()
            lastFetchErrorMessage = nil
        } else if let errorMessage {
            lastFetchErrorMessage = errorMessage
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
        messageFetchPreset.intervalSeconds
    }
}
