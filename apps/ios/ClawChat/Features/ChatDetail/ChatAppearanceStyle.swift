import SwiftUI
import UIKit

final class ChatAppearanceStyle {
    let appearance: AppearanceSettings

    init(_ appearance: AppearanceSettings) {
        self.appearance = appearance
    }

    var chatStyle: ChatStyle { appearance.chatStyle }
    var chatFont: ChatFontPreference { appearance.chatFont }
    var fontSize: FontSizePreference { appearance.fontSize }
    var isTerminal: Bool { appearance.chatStyle == .terminal }
    var renderKey: String {
        "style-\(appearance.chatStyle.rawValue)-font-\(appearance.chatFont.rawValue)-size-\(appearance.fontSize.rawValue)"
    }

    var dateSeparatorFont: Font { font(base: 12, weight: .semibold) }
    var metadataFont: Font { font(base: 12, weight: .semibold) }
    var timestampFont: Font { font(base: 11) }
    var statusFont: Font { font(base: 11) }
    var composerFont: Font { font(base: 15) }
    var composerActionIconFont: Font { font(base: 28, family: .system) }
    var jumpToBottomIconFont: Font { font(base: 16, family: .system, weight: .semibold) }
    var statusIconFont: Font { font(base: 10, family: .system, weight: .semibold) }
    var suggestionSectionFont: Font { font(base: 12) }
    var suggestionCommandTitleFont: Font { font(base: 15, family: .monospace, weight: .semibold) }
    var suggestionModelTitleFont: Font { font(base: 12, family: .monospace) }
    var suggestionSubtitleFont: Font { font(base: 12) }
    var suggestionHintFont: Font { font(base: 12, family: .monospace) }
    var composerCornerRadius: CGFloat { 18 }
    var bubbleCornerRadius: CGFloat {
        switch fontSize {
        case .small: return 16
        case .medium: return 18
        case .large: return 20
        }
    }
    var codeBlockCornerRadius: CGFloat { 12 }

    var userBubbleMaxWidth: CGFloat {
        switch fontSize {
        case .small: return 308
        case .medium: return 320
        case .large: return 340
        }
    }

    var assistantBubbleMaxWidth: CGFloat {
        switch fontSize {
        case .small: return 610
        case .medium: return 640
        case .large: return 680
        }
    }

    var assistantStreamingMaxWidth: CGFloat {
        switch fontSize {
        case .small: return 590
        case .medium: return 620
        case .large: return 660
        }
    }

    var sideSpacerWidth: CGFloat {
        switch fontSize {
        case .small: return 28
        case .medium: return 30
        case .large: return 34
        }
    }

    var transcriptBlockSpacing: CGFloat {
        switch fontSize {
        case .small: return 4
        case .medium: return 5
        case .large: return 6
        }
    }

    var markdownParagraphSpacing: CGFloat {
        switch fontSize {
        case .small: return 3
        case .medium: return 4
        case .large: return 5
        }
    }

    var markdownBlankLineHeight: CGFloat {
        switch fontSize {
        case .small: return 5
        case .medium: return 6
        case .large: return 8
        }
    }

    var listItemSpacing: CGFloat {
        switch fontSize {
        case .small: return 5
        case .medium: return 6
        case .large: return 8
        }
    }

    var quoteSpacing: CGFloat {
        switch fontSize {
        case .small: return 5
        case .medium: return 6
        case .large: return 8
        }
    }

    var headingAccentSpacing: CGFloat {
        switch fontSize {
        case .small: return 4
        case .medium: return 5
        case .large: return 6
        }
    }

    var codeBlockInnerSpacing: CGFloat {
        switch fontSize {
        case .small: return 5
        case .medium: return 6
        case .large: return 8
        }
    }

    var codeBlockHorizontalPadding: CGFloat {
        switch fontSize {
        case .small: return 11
        case .medium: return 12
        case .large: return 14
        }
    }

    var codeBlockVerticalPadding: CGFloat {
        switch fontSize {
        case .small: return 7
        case .medium: return 8
        case .large: return 10
        }
    }

    var markdownBlockSpacing: CGFloat {
        switch fontSize {
        case .small: return 3
        case .medium: return 4
        case .large: return 5
        }
    }

    var markdownListParagraphSpacing: CGFloat {
        switch fontSize {
        case .small: return 1
        case .medium: return 2
        case .large: return 3
        }
    }

    var markdownQuoteVerticalPadding: CGFloat {
        switch fontSize {
        case .small: return 2
        case .medium: return 3
        case .large: return 4
        }
    }

    var markdownQuoteIndent: CGFloat {
        switch fontSize {
        case .small: return 10
        case .medium: return 12
        case .large: return 14
        }
    }

    var markdownCodeBlockIndent: CGFloat {
        switch fontSize {
        case .small: return 8
        case .medium: return 10
        case .large: return 12
        }
    }

    var markdownCodeBlockTopSpacing: CGFloat {
        switch fontSize {
        case .small: return 4
        case .medium: return 5
        case .large: return 6
        }
    }

    var markdownCodeBlockBottomSpacing: CGFloat {
        switch fontSize {
        case .small: return 5
        case .medium: return 6
        case .large: return 7
        }
    }

    var markdownRuleWidth: CGFloat {
        switch fontSize {
        case .small: return 132
        case .medium: return 148
        case .large: return 164
        }
    }

    var inlineCodeHorizontalPadding: CGFloat {
        switch fontSize {
        case .small: return 3
        case .medium: return 4
        case .large: return 5
        }
    }

    var inlineCodeVerticalPadding: CGFloat {
        switch fontSize {
        case .small: return 1
        case .medium: return 2
        case .large: return 2
        }
    }

    func headingTopPadding(level: Int) -> CGFloat {
        switch (fontSize, level) {
        case (.small, 1): return 6
        case (.medium, 1): return 8
        case (.large, 1): return 10
        case (.small, 2): return 4
        case (.medium, 2): return 5
        case (.large, 2): return 6
        case (.small, 3), (.small, 4): return 2
        case (.medium, 3), (.medium, 4): return 3
        case (.large, 3), (.large, 4): return 4
        default: return 3
        }
    }

    func headingBottomPadding(level: Int) -> CGFloat {
        switch (fontSize, level) {
        case (.small, 1): return 2
        case (.medium, 1): return 3
        case (.large, 1): return 4
        case (.small, 2): return 1
        case (.medium, 2): return 2
        case (.large, 2): return 3
        case (.small, 3), (.small, 4): return 0
        case (.medium, 3), (.medium, 4): return 1
        case (.large, 3), (.large, 4): return 2
        default: return 1
        }
    }

    func bodyFont(isUser: Bool) -> Font {
        font(base: 15, weight: isUser ? .medium : .regular)
    }

    var terminalBodyFont: Font {
        font(base: 15)
    }

    func headingFont(level: Int) -> Font {
        switch level {
        case 1:
            return font(base: 19, weight: .bold)
        case 2:
            return font(base: 17, weight: .semibold)
        case 3:
            return font(base: 15.5, weight: .semibold)
        default:
            return font(base: 15, weight: .medium)
        }
    }

    var listMarkerFont: Font { font(base: 15, weight: .semibold) }
    var codeLabelFont: Font { font(base: 10.5, weight: .semibold) }
    var codeFont: Font { font(base: 12.5, family: .monospace) }

    func lineSpacing(isUser: Bool) -> CGFloat {
        switch fontSize {
        case .small:
            return isUser ? 1.2 : 1.8
        case .medium:
            return isUser ? 1.5 : 2.4
        case .large:
            return isUser ? 1.8 : 3.0
        }
    }

    func headerTopPadding(showsHeader: Bool) -> CGFloat {
        if !showsHeader { return 2 }
        switch fontSize {
        case .small: return 6
        case .medium: return 8
        case .large: return 10
        }
    }

    func dividerBottomPadding(showsDivider: Bool) -> CGFloat {
        guard showsDivider else { return 0 }
        switch fontSize {
        case .small: return 5
        case .medium: return 6
        case .large: return 8
        }
    }

    func userBubbleVerticalPadding() -> CGFloat {
        switch fontSize {
        case .small: return 8
        case .medium: return 9
        case .large: return 11
        }
    }

    func assistantBubbleVerticalPadding() -> CGFloat {
        switch fontSize {
        case .small: return 9
        case .medium: return 10
        case .large: return 12
        }
    }

    func statusIconSize() -> CGFloat {
        scaled(12)
    }

    func font(base: CGFloat, family: ChatFontPreference? = nil, weight: Font.Weight = .regular) -> Font {
        let resolvedFamily = family ?? chatFont
        let size = scaled(base)
        switch resolvedFamily {
        case .system:
            return .system(size: size, weight: weight)
        case .serif:
            return .system(size: size, weight: weight, design: .serif)
        case .monospace:
            return .system(size: size, weight: weight, design: .monospaced)
        }
    }

    func scaled(_ base: CGFloat) -> CGFloat {
        switch fontSize {
        case .small: return base * 0.92
        case .medium: return base
        case .large: return base * 1.12
        }
    }

    func uiFont(base: CGFloat, family: ChatFontPreference? = nil, weight: UIFont.Weight = .regular) -> UIFont {
        let resolvedFamily = family ?? chatFont
        let size = scaled(base)
        let baseFont = UIFont.systemFont(ofSize: size, weight: weight)
        switch resolvedFamily {
        case .system:
            return baseFont
        case .serif:
            if let descriptor = baseFont.fontDescriptor.withDesign(.serif) {
                return UIFont(descriptor: descriptor, size: size)
            }
            return baseFont
        case .monospace:
            return UIFont.monospacedSystemFont(ofSize: size, weight: weight)
        }
    }

    func bodyUIFont(isUser: Bool) -> UIFont {
        uiFont(base: 15, weight: isUser ? .medium : .regular)
    }

    var terminalBodyUIFont: UIFont {
        uiFont(base: 15)
    }

    func headingUIFont(level: Int) -> UIFont {
        switch level {
        case 1:
            return uiFont(base: 19, weight: .bold)
        case 2:
            return uiFont(base: 17, weight: .semibold)
        case 3:
            return uiFont(base: 15.5, weight: .semibold)
        default:
            return uiFont(base: 15, weight: .medium)
        }
    }

    var listMarkerUIFont: UIFont { uiFont(base: 15, weight: .semibold) }
    var codeLabelUIFont: UIFont { uiFont(base: 10.5, weight: .semibold) }
    var codeUIFont: UIFont { uiFont(base: 12.5, family: .monospace) }
}
