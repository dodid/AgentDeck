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
    private var fetchBeganAt: Date?
    private var endFetchIndicatorTask: Task<Void, Never>?
    private let minimumFetchIndicatorDuration: TimeInterval = 0.35

    func beginFetch() {
        if activeFetchCount == 0 {
            fetchBeganAt = Date()
        }
        endFetchIndicatorTask?.cancel()
        endFetchIndicatorTask = nil
        activeFetchCount += 1
        isFetchingMessages = true
    }

    func endFetch(succeeded: Bool, errorMessage: String? = nil) {
        activeFetchCount = max(0, activeFetchCount - 1)
        if succeeded {
            lastFetchAt = Date()
            lastFetchErrorMessage = nil
        } else if let errorMessage {
            lastFetchErrorMessage = errorMessage
        }

        guard activeFetchCount == 0 else { return }
        let elapsed = fetchBeganAt.map { Date().timeIntervalSince($0) } ?? minimumFetchIndicatorDuration
        let remaining = max(0, minimumFetchIndicatorDuration - elapsed)
        fetchBeganAt = nil
        guard remaining > 0 else {
            isFetchingMessages = false
            return
        }

        endFetchIndicatorTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled, let self, self.activeFetchCount == 0 else { return }
            self.isFetchingMessages = false
            self.endFetchIndicatorTask = nil
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
