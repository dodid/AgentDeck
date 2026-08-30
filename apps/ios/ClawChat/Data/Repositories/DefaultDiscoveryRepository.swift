import Foundation

actor DiscoveryRefreshState {
    private let minimumRefreshInterval: Duration
    private var lastRefreshAt: ContinuousClock.Instant?

    init(minimumRefreshInterval: Duration) {
        self.minimumRefreshInterval = minimumRefreshInterval
    }

    func shouldRefresh(force: Bool, now: ContinuousClock.Instant) -> Bool {
        if force {
            lastRefreshAt = now
            return true
        }
        guard let lastRefreshAt else {
            self.lastRefreshAt = now
            return true
        }
        if now - lastRefreshAt >= minimumRefreshInterval {
            self.lastRefreshAt = now
            return true
        }
        return false
    }
}

actor DiscoveryStore {
    private var sections: [GatewaySection] = []
    private var continuations: [UUID: AsyncStream<[GatewaySection]>.Continuation] = [:]

    func setSections(_ sections: [GatewaySection]) {
        self.sections = sections
        for continuation in continuations.values {
            continuation.yield(sections)
        }
    }

    func stream() -> AsyncStream<[GatewaySection]> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.yield(sections)
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeContinuation(id: id)
                }
            }
        }
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }
}

final class DefaultDiscoveryRepository: DiscoveryRepository, @unchecked Sendable {
    private static let automaticRefreshInterval: Duration = .seconds(300)

    private let connectionRepository: ConnectionRepository
    private let chatRepository: DefaultChatRepository?
    private let store: DiscoveryStore
    private let refreshState: DiscoveryRefreshState
    private let refreshClock = ContinuousClock()

    init(
        connectionRepository: ConnectionRepository = DefaultConnectionRepository(),
        chatRepository: DefaultChatRepository? = nil,
        store: DiscoveryStore = DiscoveryStore(),
        refreshState: DiscoveryRefreshState? = nil
    ) {
        self.connectionRepository = connectionRepository
        self.chatRepository = chatRepository
        self.store = store
        self.refreshState = refreshState ?? DiscoveryRefreshState(minimumRefreshInterval: Self.automaticRefreshInterval)
    }

    func refreshGateways(force: Bool = false) async throws {
        let shouldRefresh = await refreshState.shouldRefresh(force: force, now: refreshClock.now)
        guard shouldRefresh else { return }
        guard let config = try await connectionRepository.loadConnectionConfig() else {
            throw ConnectionRepositoryError.incompleteConfiguration
        }
        let service = RelayDiscoveryService(config: config)
        do {
            let sections = try await service.discoverGateways()
            try await chatRepository?.upsertDiscoveredSections(sections)
            await store.setSections(sections)
        } catch RelayDiscoveryError.noGatewaysFound {
            try await chatRepository?.upsertDiscoveredSections([])
            await store.setSections([])
        }
    }

    func observeGatewayList() -> AsyncStream<[GatewaySection]> {
        AsyncStream { continuation in
            Task {
                let stream = await store.stream()
                for await sections in stream {
                    continuation.yield(sections)
                }
                continuation.finish()
            }
        }
    }
}
