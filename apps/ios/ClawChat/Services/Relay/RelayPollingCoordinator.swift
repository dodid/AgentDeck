import Foundation

actor RelayPollingCoordinator {
    private var pollingTask: Task<Void, Never>?
    private var sleepTask: Task<Void, Never>?
    private var inFlightFetchTask: Task<Void, Never>?
    private var shouldPollImmediately = false
    private var isForegroundActive = true
    private var fetchOperation: (() async -> Bool)?
    private var pollingIntervalProvider: (() async -> Int)?
    private var lastSuccessfulFetchAt: Date?

    func start(
        pollingIntervalProvider: @escaping () async -> Int,
        fetchOperation: @escaping () async -> Bool
    ) {
        stop()
        self.pollingIntervalProvider = pollingIntervalProvider
        self.fetchOperation = fetchOperation
        pollingTask = Task { [weak self] in
            await self?.runPollingLoop()
        }
    }

    func ensureFresh(maxAge: TimeInterval) async {
        let age = lastSuccessfulFetchAt.map { Date().timeIntervalSince($0) } ?? .infinity
        if age <= maxAge { return }
        await runFetch()
    }

    func requestImmediatePoll() {
        shouldPollImmediately = true
        sleepTask?.cancel()
        sleepTask = nil
    }

    func setForegroundActive(_ active: Bool) {
        let wasForegroundActive = isForegroundActive
        isForegroundActive = active
        if active {
            if !wasForegroundActive {
                shouldPollImmediately = true
                sleepTask?.cancel()
                sleepTask = nil
            }
        } else {
            sleepTask?.cancel()
            sleepTask = nil
        }
    }

    func stop() {
        sleepTask?.cancel()
        sleepTask = nil
        pollingTask?.cancel()
        pollingTask = nil
        inFlightFetchTask?.cancel()
        inFlightFetchTask = nil
        shouldPollImmediately = false
        fetchOperation = nil
        pollingIntervalProvider = nil
        lastSuccessfulFetchAt = nil
    }

    private func runPollingLoop() async {
        while !Task.isCancelled {
            guard isForegroundActive else {
                let sleeper = Task<Void, Never> {
                    try? await Task.sleep(for: .seconds(32))
                }
                sleepTask = sleeper
                await sleeper.value
                sleepTask = nil
                continue
            }

            await runFetch()
            guard !Task.isCancelled else { break }

            if shouldPollImmediately {
                shouldPollImmediately = false
                continue
            }

            let nextInterval = max(1, await pollingIntervalProvider?() ?? 16)
            let sleeper = Task<Void, Never> {
                try? await Task.sleep(for: .seconds(nextInterval))
            }
            sleepTask = sleeper
            await sleeper.value
            sleepTask = nil
        }
    }

    private func runFetch() async {
        if let inFlightFetchTask {
            await inFlightFetchTask.value
            return
        }

        guard let fetchOperation else { return }
        let task = Task<Bool, Never> {
            await fetchOperation()
        }
        inFlightFetchTask = Task<Void, Never> {
            _ = await task.value
        }
        let didSucceed = await task.value
        if didSucceed {
            lastSuccessfulFetchAt = Date()
        }
        inFlightFetchTask = nil
    }
}
