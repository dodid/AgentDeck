import Foundation

struct DefaultSettingsRepository: SettingsRepository, Sendable {
    private let defaults: UserDefaults
    private let appearanceKey = "AgentDeck.appearanceSettings"
    private let messageFetchPresetKey = "AgentDeck.messageFetchPreset"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadAppearanceSettings() async throws -> AppearanceSettings {
        guard let data = defaults.data(forKey: appearanceKey) else { return .default }
        return try decoder.decode(AppearanceSettings.self, from: data)
    }

    func saveAppearanceSettings(_ settings: AppearanceSettings) async throws {
        let data = try encoder.encode(settings)
        defaults.set(data, forKey: appearanceKey)
    }

    func loadMessageFetchPreset() async throws -> MessageFetchPreset {
        guard let rawValue = defaults.string(forKey: messageFetchPresetKey) else { return .balanced }
        return MessageFetchPreset(rawValue: rawValue) ?? .balanced
    }

    func saveMessageFetchPreset(_ preset: MessageFetchPreset) async throws {
        defaults.set(preset.rawValue, forKey: messageFetchPresetKey)
    }
}
