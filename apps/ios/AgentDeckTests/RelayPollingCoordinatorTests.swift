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

    func testPollingIntervalStartsAfterPreviousFetchCompletes() async throws {
        let coordinator = RelayPollingCoordinator()
        let probe = PollingTimingProbe()

        await coordinator.start(
            pollingIntervalProvider: { 1 },
            fetchOperation: { await probe.fetch() }
        )

        try await waitUntil(timeout: .seconds(2)) { await probe.fetchCount >= 2 }
        await coordinator.stop()

        let delayAfterFirstFetch = await probe.delayFromFirstCompletionToSecondStart
        XCTAssertNotNil(delayAfterFirstFetch)
        XCTAssertGreaterThanOrEqual(delayAfterFirstFetch ?? 0, 0.9)
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

private actor PollingTimingProbe {
    private(set) var fetchCount = 0
    private var firstCompletionAt: Date?
    private var secondStartAt: Date?

    var delayFromFirstCompletionToSecondStart: TimeInterval? {
        guard let firstCompletionAt, let secondStartAt else { return nil }
        return secondStartAt.timeIntervalSince(firstCompletionAt)
    }

    func fetch() async -> Bool {
        fetchCount += 1
        if fetchCount == 2 {
            secondStartAt = Date()
        }
        try? await Task.sleep(for: .milliseconds(150))
        if fetchCount == 1 {
            firstCompletionAt = Date()
        }
        return true
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
