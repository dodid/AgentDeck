import Foundation
import XCTest
@testable import AgentDeck

@MainActor
final class ViewModelFlowTests: XCTestCase {
    func testCoordinatorRoutesNewAndReturningInstalls() async {
        let connection = MockConnectionRepository()
        let environment = makeEnvironment(connection: connection)
        let coordinator = AppCoordinatorViewModel(environment: environment)

        await coordinator.bootstrap()
        XCTAssertEqual(coordinator.rootRoute, .onboarding)

        connection.config = completeConfig
        await coordinator.bootstrap()
        XCTAssertEqual(coordinator.rootRoute, .main)
    }

    func testCoordinatorFallsBackToOnboardingWhenCredentialLoadFails() async {
        let connection = MockConnectionRepository()
        connection.error = MockRepositoryError.failed
        let coordinator = AppCoordinatorViewModel(environment: makeEnvironment(connection: connection))

        await coordinator.bootstrap()

        XCTAssertEqual(coordinator.rootRoute, .onboarding)
    }

    func testOnboardingNavigationAndSuccessfulSave() async {
        let connection = MockConnectionRepository()
        let environment = makeEnvironment(connection: connection)
        var completed = false
        let model = OnboardingViewModel(environment: environment) { completed = true }

        model.advance()
        XCTAssertEqual(model.step, .howItWorks)
        model.advance()
        model.advance()
        XCTAssertEqual(model.step, .connect)
        model.goBack()
        XCTAssertEqual(model.step, .createBucket)

        model.updateConfig(completeConfig)
        await model.verifyAndSave()

        XCTAssertEqual(connection.verified, completeConfig)
        XCTAssertEqual(connection.config, completeConfig)
        XCTAssertTrue(completed)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isWorking)
    }

    func testOnboardingKeepsUserInFlowWhenVerificationFails() async {
        let connection = MockConnectionRepository()
        connection.error = MockRepositoryError.failed
        var completed = false
        let model = OnboardingViewModel(environment: makeEnvironment(connection: connection)) { completed = true }
        model.updateConfig(completeConfig)

        await model.verifyAndSave()

        XCTAssertFalse(completed)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNil(connection.config)
    }

    func testSettingsRefreshRunsDiscoverySyncAndReloadsStats() async {
        let connection = MockConnectionRepository()
        connection.config = completeConfig
        let discovery = MockDiscoveryRepository()
        let sync = MockSyncRepository()
        let chat = MockChatRepository()
        chat.stats = StorageStats(threadCount: 2, messageCount: 3, sessionDataSizeBytes: 4, attachmentDataSizeBytes: 5)
        let model = SettingsViewModel(environment: makeEnvironment(
            connection: connection,
            discovery: discovery,
            chat: chat,
            sync: sync
        ))

        await model.load()
        await model.refreshSessions()

        XCTAssertEqual(model.bucketSummary, completeConfig.bucket)
        XCTAssertEqual(model.storageStats.messageCount, 3)
        XCTAssertEqual(discovery.refreshCalls, 1)
        XCTAssertEqual(sync.refreshCalls, 1)
        XCTAssertNil(model.errorMessage)
    }

    func testChatListRefreshSurfacesAndClearsDiscoveryFailures() async {
        let connection = MockConnectionRepository()
        let discovery = MockDiscoveryRepository()
        let model = ChatListViewModel(environment: makeEnvironment(connection: connection, discovery: discovery))

        discovery.error = MockRepositoryError.failed
        await model.refresh()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isRefreshing)

        discovery.error = nil
        await model.refresh()
        XCTAssertEqual(discovery.refreshCalls, 2)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isRefreshing)
    }

    func testConnectionEditorRequiresConfirmationBeforeReplacingRelayAndClearsLocalData() async {
        let connection = MockConnectionRepository()
        connection.config = completeConfig
        let chat = MockChatRepository()
        let model = ConnectionEditorViewModel(environment: makeEnvironment(connection: connection, chat: chat))
        var replacement = completeConfig
        replacement.bucket = "replacement"
        model.draft = replacement

        await model.verifyAndPrepareSave()

        XCTAssertTrue(model.showBucketChangedAlert)
        XCTAssertEqual(model.pendingConfig?.bucket, "replacement")
        XCTAssertEqual(connection.config?.bucket, "relay")
        XCTAssertEqual(chat.clearLocalDataCalls, 0)

        await model.confirmDestructiveSave()

        XCTAssertEqual(chat.clearLocalDataCalls, 1)
        XCTAssertEqual(connection.config?.bucket, "replacement")
        XCTAssertNil(model.pendingConfig)
        XCTAssertNil(model.errorMessage)
    }

    func testChatDetailSendsThroughSyncRepositoryAndClearsComposer() async {
        let connection = MockConnectionRepository()
        let sync = MockSyncRepository()
        let model = ChatDetailViewModel(
            environment: makeEnvironment(connection: connection, sync: sync),
            sessionID: SessionID(rawValue: "gateway::main::conversation")
        )
        model.setDraftText("  hello relay  ")

        await model.send()

        XCTAssertEqual(sync.sentMessages.map(\.text), ["hello relay"])
        XCTAssertEqual(model.draftText, "")
        XCTAssertFalse(model.isSending)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.scrollToBottomRequestToken, 1)
    }

    func testChatDetailKeepsDraftOnSendFailureAndLocksSubscribedAgents() async {
        let connection = MockConnectionRepository()
        let sync = MockSyncRepository()
        sync.error = MockRepositoryError.failed
        let model = ChatDetailViewModel(
            environment: makeEnvironment(connection: connection, sync: sync),
            sessionID: SessionID(rawValue: "gateway::main::conversation")
        )
        model.setDraftText("retry me")

        await model.send()
        XCTAssertEqual(model.draftText, "retry me")
        XCTAssertNotNil(model.errorMessage)

        sync.error = nil
        model.requiresAgentSubscription = true
        await model.send()
        XCTAssertTrue(model.showingPaywall)
        XCTAssertTrue(sync.sentMessages.isEmpty)
    }

    func testChatDetailBackfillUsesExpandedPageLimitAndReportsFailure() async {
        let connection = MockConnectionRepository()
        let sync = MockSyncRepository()
        let model = ChatDetailViewModel(
            environment: makeEnvironment(connection: connection, sync: sync),
            sessionID: SessionID(rawValue: "gateway::main::conversation")
        )
        model.canLoadOlder = true

        await model.loadOlder(topVisibleID: "message-1")
        XCTAssertEqual(sync.backfillLimits, [100])
        XCTAssertNil(model.errorMessage)

        sync.error = MockRepositoryError.failed
        await model.loadOlder(topVisibleID: "message-1")
        XCTAssertEqual(sync.backfillLimits, [100, 150])
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isLoadingOlder)
    }

    private var completeConfig: ConnectionConfig {
        ConnectionConfig(
            endpoint: "https://example.invalid",
            bucket: "relay",
            accessKeyID: "access",
            secretAccessKey: "secret",
            region: "auto",
            forcePathStyle: true
        )
    }

    private func makeEnvironment(
        connection: MockConnectionRepository,
        discovery: MockDiscoveryRepository = MockDiscoveryRepository(),
        chat: MockChatRepository = MockChatRepository(),
        sync: MockSyncRepository = MockSyncRepository()
    ) -> AppEnvironment {
        let settings = MockSettingsRepository()
        return AppEnvironment(
            connectionRepository: connection,
            settingsRepository: settings,
            deviceRepository: MockDeviceRepository(),
            discoveryRepository: discovery,
            chatRepository: chat,
            syncRepository: sync,
            syncActivityStore: SyncActivityStore(),
            chatAppearanceController: ChatAppearanceController(settingsRepository: settings),
            subscriptionController: SubscriptionController()
        )
    }
}

private enum MockRepositoryError: LocalizedError {
    case failed

    var errorDescription: String? { "mock repository failure" }
}

private final class MockConnectionRepository: ConnectionRepository, @unchecked Sendable {
    var config: ConnectionConfig?
    var verified: ConnectionConfig?
    var error: Error?

    func loadConnectionConfig() async throws -> ConnectionConfig? {
        if let error { throw error }
        return config
    }

    func saveConnectionConfig(_ config: ConnectionConfig) async throws {
        if let error { throw error }
        self.config = config
    }

    func verify(_ config: ConnectionConfig) async throws {
        if let error { throw error }
        verified = config
    }
}

private final class MockSettingsRepository: SettingsRepository, @unchecked Sendable {
    var settings = AppearanceSettings.default

    func loadAppearanceSettings() async throws -> AppearanceSettings { settings }
    func saveAppearanceSettings(_ settings: AppearanceSettings) async throws { self.settings = settings }
}

private final class MockDeviceRepository: DeviceRepository, @unchecked Sendable {
    var profile = DeviceProfile(clientID: "ios", displayName: "Test iPhone", createdAt: Date())

    func loadDeviceProfile() async throws -> DeviceProfile { profile }
    func saveDeviceProfile(_ profile: DeviceProfile) async throws { self.profile = profile }
}

private final class MockDiscoveryRepository: DiscoveryRepository, @unchecked Sendable {
    var refreshCalls = 0
    var error: Error?

    func refreshGateways(force _: Bool) async throws {
        refreshCalls += 1
        if let error { throw error }
    }

    func observeGatewayList() -> AsyncStream<[GatewaySection]> {
        AsyncStream { $0.finish() }
    }
}

private final class MockChatRepository: ChatRepository, @unchecked Sendable {
    var stats = StorageStats(threadCount: 0, messageCount: 0, sessionDataSizeBytes: 0, attachmentDataSizeBytes: 0)
    var clearLocalDataCalls = 0

    func observeTranscript(sessionID _: SessionID, limit _: Int) -> AsyncStream<TranscriptPage> {
        AsyncStream { $0.finish() }
    }
    func sendMessage(_ text: String, attachments: [DraftAttachment], to sessionID: SessionID) async throws {}
    func loadOlderMessages(for sessionID: SessionID, currentLimit: Int) async throws -> Int { currentLimit }
    func refreshSession(_ sessionID: SessionID) async throws {}
    func clearLocalData() async throws { clearLocalDataCalls += 1 }
    func cleanupAttachmentData(olderThan age: LocalDataAgeOption) async throws -> Int64 { 0 }
    func cleanupAllAttachmentData() async throws -> Int64 { 0 }
    func storageStats() async throws -> StorageStats { stats }
}

private final class MockSyncRepository: SyncRepository, @unchecked Sendable {
    var refreshCalls = 0
    var sentMessages: [(text: String, sessionID: SessionID)] = []
    var backfillLimits: [Int] = []
    var error: Error?

    func startPolling() async {}
    func stopPolling() async {}
    func requestImmediateSync(reason: SyncReason) async {}
    func refreshNow() async throws {
        refreshCalls += 1
        if let error { throw error }
    }
    func sendMessage(_ text: String, attachments: [DraftAttachment], to sessionID: SessionID) async throws {
        if let error { throw error }
        sentMessages.append((text, sessionID))
    }
    func sendApprovalResponse(approvalID: String, decision: String, to sessionID: SessionID) async throws {}
    func backfill(sessionID: SessionID, limit: Int) async throws {
        backfillLimits.append(limit)
        if let error { throw error }
    }
}
