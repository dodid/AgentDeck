import XCTest
@testable import AgentDeck

final class RelayPollingCoordinatorTests: XCTestCase {
    func testStoppingPollingCancelsTheUnderlyingFetch() async throws {
        let coordinator = RelayPollingCoordinator()
        let probe = PollingCancellationProbe()

        await coordinator.start(
            pollingIntervalProvider: { 60 },
            fetchOperation: { await probe.fetch() }
        )
        try await waitUntil { await probe.didStart }

        await coordinator.stop()

        try await waitUntil { await probe.wasCancelled }
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Condition was not met before timeout")
    }
}

private actor PollingCancellationProbe {
    private(set) var didStart = false
    private(set) var wasCancelled = false

    func fetch() async -> Bool {
        didStart = true
        do {
            try await Task.sleep(for: .seconds(60))
        } catch is CancellationError {
            wasCancelled = true
        } catch {
            return false
        }
        return false
    }
}
