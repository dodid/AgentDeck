import SwiftUI
import UIKit

enum AppTheme {
    static let bg = Color.dynamic(
        light: UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1),
        dark: UIColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1)
    )
    static let panel = Color.dynamic(
        light: UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1),
        dark: UIColor(red: 0.09, green: 0.10, blue: 0.13, alpha: 1)
    )
    static let panelAlt = Color.dynamic(
        light: UIColor(red: 0.89, green: 0.91, blue: 0.94, alpha: 1),
        dark: UIColor(red: 0.11, green: 0.12, blue: 0.16, alpha: 1)
    )
    static let border = Color.dynamic(
        light: UIColor(red: 0.74, green: 0.78, blue: 0.84, alpha: 1),
        dark: UIColor(red: 0.19, green: 0.22, blue: 0.28, alpha: 1)
    )
    static let text = Color.dynamic(
        light: UIColor(red: 0.12, green: 0.15, blue: 0.20, alpha: 1),
        dark: UIColor(red: 0.90, green: 0.93, blue: 0.97, alpha: 1)
    )
    static let dim = Color.dynamic(
        light: UIColor(red: 0.33, green: 0.39, blue: 0.49, alpha: 1),
        dark: UIColor(red: 0.68, green: 0.73, blue: 0.81, alpha: 1)
    )
    static let green = Color.dynamic(
        light: UIColor(red: 0.17, green: 0.63, blue: 0.32, alpha: 1),
        dark: UIColor(red: 0.47, green: 0.93, blue: 0.59, alpha: 1)
    )
    static let blue = Color.dynamic(
        light: UIColor(red: 0.15, green: 0.49, blue: 0.88, alpha: 1),
        dark: UIColor(red: 0.45, green: 0.75, blue: 1.00, alpha: 1)
    )
    static let yellow = Color.dynamic(
        light: UIColor(red: 0.76, green: 0.57, blue: 0.12, alpha: 1),
        dark: UIColor(red: 0.96, green: 0.82, blue: 0.45, alpha: 1)
    )
    static let assistantAccent = Color.dynamic(
        light: UIColor(red: 0.58, green: 0.49, blue: 0.24, alpha: 1),
        dark: UIColor(red: 0.90, green: 0.78, blue: 0.48, alpha: 1)
    )
    static let red = Color.dynamic(
        light: UIColor(red: 0.79, green: 0.25, blue: 0.25, alpha: 1),
        dark: UIColor(red: 1.00, green: 0.48, blue: 0.48, alpha: 1)
    )

    static func font(size: FontSizePreference, font: ChatFontPreference, weight: Font.Weight = .regular) -> Font {
        makeFont(baseSize: 15 * scale(for: size), family: font, weight: weight)
    }

    static func font(_ textStyle: Font.TextStyle, size: FontSizePreference, weight: Font.Weight = .regular) -> Font {
        let role = role(for: textStyle)
        return makeFont(baseSize: role.baseSize * scale(for: size), family: .system, weight: weight == .regular ? role.defaultWeight : weight)
    }

    static func bubbleBackground(for style: TranscriptRowStyle) -> Color {
        switch style {
        case .assistant:
            return panelAlt
        case .userSending:
            return blue.opacity(0.14)
        case .userSentToRelay, .userConfirmed:
            return blue.opacity(0.20)
        case .userFailed:
            return red.opacity(0.14)
        }
    }

    private static func scale(for size: FontSizePreference) -> CGFloat {
        switch size {
        case .small: return 0.92
        case .medium: return 1.0
        case .large: return 1.12
        }
    }

    private static func makeFont(baseSize: CGFloat, family: ChatFontPreference, weight: Font.Weight) -> Font {
        switch family {
        case .system:
            return .system(size: baseSize, weight: weight)
        case .serif:
            return .system(size: baseSize, weight: weight, design: .serif)
        case .monospace:
            return .system(size: baseSize, weight: weight, design: .monospaced)
        }
    }

    private static func role(for textStyle: Font.TextStyle) -> FontRole {
        switch textStyle {
        case .largeTitle, .title, .title2, .title3:
            return .title
        case .headline:
            return .headline
        case .subheadline:
            return .subheadline
        case .caption, .caption2:
            return .caption
        case .footnote:
            return .footnote
        default:
            return .body
        }
    }

    private enum FontRole {
        case title
        case headline
        case body
        case subheadline
        case caption
        case footnote

        var baseSize: CGFloat {
            switch self {
            case .title: return 28
            case .headline: return 17
            case .body: return 15
            case .subheadline: return 14
            case .caption: return 12
            case .footnote: return 11
            }
        }

        var defaultWeight: Font.Weight {
            switch self {
            case .title: return .bold
            case .headline: return .semibold
            case .body, .subheadline, .caption, .footnote: return .regular
            }
        }
    }
}

extension Color {
    static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}
