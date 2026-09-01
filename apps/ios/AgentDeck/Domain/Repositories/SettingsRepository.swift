import Foundation

protocol SettingsRepository: Sendable {
    func loadAppearanceSettings() async throws -> AppearanceSettings
    func saveAppearanceSettings(_ settings: AppearanceSettings) async throws
    func loadMessageFetchPreset() async throws -> MessageFetchPreset
    func saveMessageFetchPreset(_ preset: MessageFetchPreset) async throws
}
