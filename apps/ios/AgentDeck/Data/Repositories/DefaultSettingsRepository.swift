import Foundation

struct DefaultSettingsRepository: SettingsRepository, Sendable {
    private let defaults: UserDefaults
    private let key = "AgentDeck.appearanceSettings"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadAppearanceSettings() async throws -> AppearanceSettings {
        guard let data = defaults.data(forKey: key) else { return .default }
        return try decoder.decode(AppearanceSettings.self, from: data)
    }

    func saveAppearanceSettings(_ settings: AppearanceSettings) async throws {
        let data = try encoder.encode(settings)
        defaults.set(data, forKey: key)
    }
}
