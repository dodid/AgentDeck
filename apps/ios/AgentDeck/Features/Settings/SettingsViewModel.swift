import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    let environment: AppEnvironment

    var appearance: AppearanceSettings {
        get { environment.chatAppearanceController.appearance }
        set { environment.chatAppearanceController.appearance = newValue }
    }
    var storageStats = StorageStats(threadCount: 0, messageCount: 0, sessionDataSizeBytes: 0, attachmentDataSizeBytes: 0)
    var errorMessage: String?
    var cleanupResultMessage: String?
    var isWorking = false
    var bucketSummary: String = String(localized: "Not configured")
    var endpointSummary: String = String(localized: "Not configured")
    var deviceSummary: String = ""
    var messageFetchPreset: MessageFetchPreset = .balanced

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func load() async {
        do {
            await environment.chatAppearanceController.load()
            messageFetchPreset = try await environment.settingsRepository.loadMessageFetchPreset()
            environment.syncActivityStore.messageFetchPreset = messageFetchPreset
            storageStats = try await environment.chatRepository.storageStats()
            if let config = try await environment.connectionRepository.loadConnectionConfig() {
                bucketSummary = config.bucket.isEmpty ? String(localized: "Not configured") : config.bucket
                endpointSummary = config.endpoint.isEmpty ? String(localized: "Not configured") : config.endpoint
            }
            let device = try await environment.deviceRepository.loadDeviceProfile()
            deviceSummary = device.displayName
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateTheme(_ value: AppThemePreference) async {
        await environment.chatAppearanceController.setTheme(value)
    }

    func updateChatStyle(_ value: ChatStyle) async {
        await environment.chatAppearanceController.setChatStyle(value)
    }

    func updateFontSize(_ value: FontSizePreference) async {
        await environment.chatAppearanceController.setFontSize(value)
    }

    func updateChatFont(_ value: ChatFontPreference) async {
        await environment.chatAppearanceController.setChatFont(value)
    }

    func updateMessageFetchPreset(_ value: MessageFetchPreset) async {
        do {
            try await environment.settingsRepository.saveMessageFetchPreset(value)
            messageFetchPreset = value
            environment.syncActivityStore.messageFetchPreset = value
            await environment.syncRepository.requestImmediateSync(reason: .manualRefresh)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshSessions() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await environment.discoveryRepository.refreshGateways(force: true)
            try await environment.syncRepository.refreshNow()
            storageStats = try await environment.chatRepository.storageStats()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cleanupAttachmentData(olderThan age: LocalDataAgeOption) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let freedBytes = try await environment.chatRepository.cleanupAttachmentData(olderThan: age)
            storageStats = try await environment.chatRepository.storageStats()
            errorMessage = nil
            cleanupResultMessage = Self.cleanupResultCopy(freedBytes: freedBytes)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cleanupAllAttachmentData() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let freedBytes = try await environment.chatRepository.cleanupAllAttachmentData()
            storageStats = try await environment.chatRepository.storageStats()
            errorMessage = nil
            cleanupResultMessage = Self.cleanupResultCopy(freedBytes: freedBytes)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func cleanupResultCopy(freedBytes: Int64) -> String {
        let freedSize = ByteCountFormatter.string(fromByteCount: freedBytes, countStyle: .file)
        return String.localizedStringWithFormat(
            String(localized: "Freed %@ from attachment cache."),
            freedSize
        )
    }
}
