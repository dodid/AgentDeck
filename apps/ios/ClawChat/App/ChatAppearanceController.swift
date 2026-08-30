import Foundation
import Observation

@MainActor
@Observable
final class ChatAppearanceController {
    private let settingsRepository: SettingsRepository
    var appearance: AppearanceSettings = .default

    init(settingsRepository: SettingsRepository) {
        self.settingsRepository = settingsRepository
    }

    func load() async {
        if let settings = try? await settingsRepository.loadAppearanceSettings() {
            appearance = settings
        }
    }

    func setTheme(_ value: AppThemePreference) async {
        var updated = appearance
        updated.theme = value
        await apply(updated)
    }

    func setChatStyle(_ value: ChatStyle) async {
        var updated = appearance
        updated.chatStyle = value
        await apply(updated)
    }

    func setFontSize(_ value: FontSizePreference) async {
        var updated = appearance
        updated.fontSize = value
        await apply(updated)
    }

    func setChatFont(_ value: ChatFontPreference) async {
        var updated = appearance
        updated.chatFont = value
        await apply(updated)
    }

    func apply(_ updated: AppearanceSettings) async {
        appearance = updated
        try? await settingsRepository.saveAppearanceSettings(updated)
        NotificationCenter.default.post(name: .clawChatThemeDidChange, object: updated.theme.rawValue)
        NotificationCenter.default.post(name: .clawChatAppearanceDidChange, object: updated)
    }
}
