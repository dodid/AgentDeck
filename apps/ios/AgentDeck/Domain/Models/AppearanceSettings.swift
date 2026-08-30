import Foundation

enum AppThemePreference: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case dark

    var localizedLabel: String {
        switch self {
        case .system: return String(localized: "System")
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        }
    }
}

enum ChatStyle: String, Codable, CaseIterable, Sendable {
    case bubble
    case terminal

    var localizedLabel: String {
        switch self {
        case .bubble: return String(localized: "Bubble")
        case .terminal: return String(localized: "Terminal")
        }
    }
}

enum FontSizePreference: String, Codable, CaseIterable, Sendable {
    case small
    case medium
    case large

    var localizedLabel: String {
        switch self {
        case .small: return String(localized: "Small")
        case .medium: return String(localized: "Medium")
        case .large: return String(localized: "Large")
        }
    }
}

enum ChatFontPreference: String, CaseIterable, Sendable {
    case system
    case serif
    case monospace

    var localizedLabel: String {
        switch self {
        case .system: return String(localized: "System")
        case .serif: return String(localized: "Serif")
        case .monospace: return String(localized: "Monospace")
        }
    }
}

extension ChatFontPreference: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self)) ?? "system"
        switch rawValue {
        case "system":
            self = .system
        case "rounded":
            self = .system
        case "serif":
            self = .serif
        case "monospace":
            self = .monospace
        case "monospaced":
            self = .monospace
        default:
            self = .system
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct AppearanceSettings: Equatable, Codable, Sendable {
    var theme: AppThemePreference
    var chatStyle: ChatStyle
    var fontSize: FontSizePreference
    var chatFont: ChatFontPreference

    static let `default` = AppearanceSettings(
        theme: .system,
        chatStyle: .bubble,
        fontSize: .medium,
        chatFont: .system
    )
}
