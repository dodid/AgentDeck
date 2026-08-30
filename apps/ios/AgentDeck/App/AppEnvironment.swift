import Foundation

struct AppEnvironment {
    let connectionRepository: ConnectionRepository
    let settingsRepository: SettingsRepository
    let deviceRepository: DeviceRepository
    let discoveryRepository: DiscoveryRepository
    let chatRepository: ChatRepository
    let syncRepository: SyncRepository
    let syncActivityStore: SyncActivityStore
    let chatAppearanceController: ChatAppearanceController
    let subscriptionController: SubscriptionController

    static func makeDefault() -> AppEnvironment {
        let connectionRepository = DefaultConnectionRepository()
        let settingsRepository = DefaultSettingsRepository()
        let deviceRepository = DefaultDeviceRepository()
        let database = AppDatabase()
        let chatRepository = DefaultChatRepository(database: database, deviceRepository: deviceRepository)
        let discoveryRepository = DefaultDiscoveryRepository(connectionRepository: connectionRepository, chatRepository: chatRepository)
        let syncActivityStore = SyncActivityStore()
        let syncEngine = RelaySyncEngine(connectionRepository: connectionRepository, deviceRepository: deviceRepository, chatRepository: chatRepository, database: database)
        let syncRepository = DefaultSyncRepository(engine: syncEngine, activityStore: syncActivityStore)
        let chatAppearanceController = ChatAppearanceController(settingsRepository: settingsRepository)
        let subscriptionController = SubscriptionController()

        return AppEnvironment(
            connectionRepository: connectionRepository,
            settingsRepository: settingsRepository,
            deviceRepository: deviceRepository,
            discoveryRepository: discoveryRepository,
            chatRepository: chatRepository,
            syncRepository: syncRepository,
            syncActivityStore: syncActivityStore,
            chatAppearanceController: chatAppearanceController,
            subscriptionController: subscriptionController
        )
    }
}
