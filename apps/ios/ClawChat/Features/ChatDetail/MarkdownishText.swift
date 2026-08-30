import SwiftUI
import UIKit

struct MarkdownishText: View {
    let text: String
    let font: Font
    let codeFont: Font
    let style: ChatAppearanceStyle
    let isUserMessage: Bool

    private static let attributedCache = NSCache<NSString, NSAttributedString>()

    private var normalizedText: String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
    }

    private var lines: [String] {
        normalizedText.components(separatedBy: "\n")
    }

    var body: some View {
        let segments = buildSegments()
        VStack(alignment: .leading, spacing: style.markdownBlockSpacing) {
            ForEach(segments.indices, id: \.self) { i in
                switch segments[i] {
                case .text(let attributed, let key):
                    NativeAttributedTextView(attributedText: attributed, cacheKey: key)
                        .fixedSize(horizontal: false, vertical: true)
                case .code(let language, let content):
                    CodeCardView(language: language, content: content, style: style)
                }
            }
        }
    }

    private func cacheKey() -> String {
        "\(style.renderKey)|\(isUserMessage ? "user" : "assistant")|\(text)"
    }

    private func buildSegments() -> [MarkdownSegment] {
        let blocks = renderBlocks()
        var segments: [MarkdownSegment] = []
        var pendingBlocks: [MarkdownBlock] = []

        func flushPending() {
            guard !pendingBlocks.isEmpty else { return }
            let key = "\(cacheKey())|seg\(segments.count)"
            if let cached = Self.attributedCache.object(forKey: key as NSString) {
                segments.append(.text(cached, key))
            } else {
                let built = makeAttributedText(from: pendingBlocks)
                Self.attributedCache.setObject(built, forKey: key as NSString)
                segments.append(.text(built, key))
            }
            pendingBlocks = []
        }

        for block in blocks {
            if case .code(let language, let content) = block {
                flushPending()
                segments.append(.code(language, content))
            } else {
                pendingBlocks.append(block)
            }
        }
        flushPending()
        return segments
    }

    private func makeAttributedText(from blocks: [MarkdownBlock]) -> NSAttributedString {
        let output = NSMutableAttributedString()

        for (index, block) in blocks.enumerated() {
            switch block {
            case .code:
                break // handled as standalone card
            case .list(let listLines):
                appendListBlock(listLines, to: output)
            case .quote(let quoteLines):
                appendQuoteBlock(quoteLines, to: output)
            case .lines(let blockLines):
                appendLinesBlock(blockLines, to: output)
            }

            if index < blocks.count - 1 {
                output.append(blockSeparator())
            }
        }

        return output
    }

    private func appendQuoteBlock(_ quoteLines: [String], to output: NSMutableAttributedString) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = style.scaled(1.2)
        paragraph.paragraphSpacingBefore = style.markdownQuoteVerticalPadding
        paragraph.paragraphSpacing = style.markdownQuoteVerticalPadding

        for (index, line) in quoteLines.enumerated() {
            let content = String(line.trimmingCharacters(in: .whitespaces).dropFirst(2))
            output.append(NSAttributedString(
                string: "▍ ",
                attributes: [
                    .font: style.bodyUIFont(isUser: false),
                    .foregroundColor: UIColor(AppTheme.assistantAccent).withAlphaComponent(0.90),
                    .paragraphStyle: paragraph
                ]
            ))
            output.append(styledInlineAttributedText(
                content,
                font: style.bodyUIFont(isUser: false),
                color: UIColor(AppTheme.dim).withAlphaComponent(0.94),
                isItalicBase: true,
                paragraph: paragraph
            ))

            if index < quoteLines.count - 1 {
                output.append(NSAttributedString(string: "\n", attributes: [
                    .font: style.bodyUIFont(isUser: false),
                    .paragraphStyle: minimalParagraph()
                ]))
            }
        }
    }

    private func appendListBlock(_ listLines: [String], to output: NSMutableAttributedString) {
        for (index, line) in listLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lineParagraph = NSMutableParagraphStyle()
            lineParagraph.lineSpacing = style.scaled(1.0)
            lineParagraph.paragraphSpacing = style.markdownListParagraphSpacing

            if let ordered = orderedListContent(from: trimmed) {
                let markerAttributes: [NSAttributedString.Key: Any] = [
                    .font: style.listMarkerUIFont,
                    .foregroundColor: UIColor(AppTheme.dim),
                    .paragraphStyle: lineParagraph
                ]
                output.append(NSAttributedString(string: ordered.marker + " ", attributes: markerAttributes))
                output.append(styledInlineAttributedText(ordered.content, font: style.bodyUIFont(isUser: isUserMessage), paragraph: lineParagraph))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let markerAttributes: [NSAttributedString.Key: Any] = [
                    .font: style.listMarkerUIFont,
                    .foregroundColor: UIColor(AppTheme.dim),
                    .paragraphStyle: lineParagraph
                ]
                output.append(NSAttributedString(string: "• ", attributes: markerAttributes))
                output.append(styledInlineAttributedText(String(trimmed.dropFirst(2)), font: style.bodyUIFont(isUser: isUserMessage), paragraph: lineParagraph))
            }

            if index < listLines.count - 1 {
                output.append(NSAttributedString(string: "\n"))
            }
        }
    }

    private func appendLinesBlock(_ blockLines: [String], to output: NSMutableAttributedString) {
        for (index, line) in blockLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let heading = headingSpec(from: trimmed) {
                let paragraph = NSMutableParagraphStyle()
                paragraph.paragraphSpacing = heading.bottomPadding
                paragraph.paragraphSpacingBefore = heading.topPadding
                output.append(styledInlineAttributedText(heading.text, font: heading.uiFont, color: heading.uiColor, paragraph: paragraph))
            } else if isHorizontalRule(trimmed) {
                output.append(horizontalRuleAttributedString())
            } else if trimmed.isEmpty {
                output.append(blankLineSpacer())
            } else {
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineSpacing = style.lineSpacing(isUser: isUserMessage)
                paragraph.paragraphSpacing = style.markdownBlockSpacing
                output.append(styledInlineAttributedText(line, font: style.bodyUIFont(isUser: isUserMessage), paragraph: paragraph))
            }

            if index < blockLines.count - 1 {
                output.append(NSAttributedString(string: "\n", attributes: [
                    .font: style.bodyUIFont(isUser: isUserMessage),
                    .paragraphStyle: minimalParagraph()
                ]))
            }
        }
    }

    private func blockSeparator() -> NSAttributedString {
        NSAttributedString(string: "\n", attributes: [
            .font: UIFont.systemFont(ofSize: max(1, style.markdownBlockSpacing)),
            .paragraphStyle: minimalParagraph()
        ])
    }

    private func blankLineSpacer() -> NSAttributedString {
        NSAttributedString(string: "\u{200B}", attributes: [
            .font: UIFont.systemFont(ofSize: max(1, style.markdownBlankLineHeight)),
            .foregroundColor: UIColor.clear,
            .paragraphStyle: minimalParagraph()
        ])
    }

    private func minimalParagraph() -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 0
        paragraph.paragraphSpacing = 0
        paragraph.paragraphSpacingBefore = 0
        return paragraph
    }

    private func spacerParagraph(after spacing: CGFloat) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 0
        paragraph.paragraphSpacing = spacing
        paragraph.paragraphSpacingBefore = 0
        return paragraph
    }

    private func horizontalRuleAttributedString() -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.image = horizontalRuleImage(
            width: style.markdownRuleWidth,
            color: UIColor(AppTheme.border).withAlphaComponent(0.32)
        )
        attachment.bounds = CGRect(x: 0, y: -style.scaled(2), width: style.markdownRuleWidth, height: 1)

        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacingBefore = style.scaled(6)
        paragraph.paragraphSpacing = style.scaled(6)

        let result = NSMutableAttributedString(attachment: attachment)
        result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
        return result
    }

    private func horizontalRuleImage(width: CGFloat, color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: 1))
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: 1))
        }
    }

    private func renderBlocks() -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var currentLines: [String] = []
        var currentListLines: [String] = []
        var currentQuoteLines: [String] = []
        var inCodeBlock = false
        var codeLines: [String] = []
        var codeLanguage: String?

        func flushLines() {
            if !currentLines.isEmpty { blocks.append(.lines(currentLines)); currentLines = [] }
        }
        func flushList() {
            if !currentListLines.isEmpty { blocks.append(.list(currentListLines)); currentListLines = [] }
        }
        func flushQuote() {
            if !currentQuoteLines.isEmpty { blocks.append(.quote(currentQuoteLines)); currentQuoteLines = [] }
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    blocks.append(.code(language: codeLanguage, content: codeLines.joined(separator: "\n")))
                    codeLines = []
                    codeLanguage = nil
                    inCodeBlock = false
                } else {
                    flushLines()
                    flushList()
                    flushQuote()
                    let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                    codeLanguage = language.isEmpty ? nil : language
                    inCodeBlock = true
                }
                continue
            }

            if inCodeBlock {
                codeLines.append(line)
            } else if isListLine(trimmed) {
                flushLines()
                flushQuote()
                currentListLines.append(line)
            } else if isQuoteLine(trimmed) {
                flushLines()
                flushList()
                currentQuoteLines.append(line)
            } else {
                flushList()
                flushQuote()
                currentLines.append(line)
            }
        }

        if inCodeBlock {
            blocks.append(.code(language: codeLanguage, content: codeLines.joined(separator: "\n")))
        }
        flushList()
        flushQuote()
        flushLines()

        return blocks
    }

    private func isListLine(_ trimmed: String) -> Bool {
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") { return true }
        return orderedListContent(from: trimmed) != nil
    }

    private func isQuoteLine(_ trimmed: String) -> Bool {
        trimmed.hasPrefix("> ")
    }

    private func headingSpec(from trimmed: String) -> HeadingSpec? {
        if trimmed.hasPrefix("#### ") {
            return HeadingSpec(
                text: String(trimmed.dropFirst(5)),
                uiFont: style.headingUIFont(level: 4),
                uiColor: UIColor(AppTheme.dim),
                topPadding: style.headingTopPadding(level: 4),
                bottomPadding: style.headingBottomPadding(level: 4),
                showsAccent: false
            )
        }
        if trimmed.hasPrefix("### ") {
            return HeadingSpec(
                text: String(trimmed.dropFirst(4)),
                uiFont: style.headingUIFont(level: 3),
                uiColor: UIColor(AppTheme.text),
                topPadding: style.headingTopPadding(level: 3),
                bottomPadding: style.headingBottomPadding(level: 3),
                showsAccent: false
            )
        }
        if trimmed.hasPrefix("## ") {
            return HeadingSpec(
                text: String(trimmed.dropFirst(3)),
                uiFont: style.headingUIFont(level: 2),
                uiColor: UIColor(AppTheme.text),
                topPadding: style.headingTopPadding(level: 2),
                bottomPadding: style.headingBottomPadding(level: 2),
                showsAccent: true,
                accentWidth: 22
            )
        }
        if trimmed.hasPrefix("# ") {
            return HeadingSpec(
                text: String(trimmed.dropFirst(2)),
                uiFont: style.headingUIFont(level: 1),
                uiColor: UIColor(AppTheme.text),
                topPadding: style.headingTopPadding(level: 1),
                bottomPadding: style.headingBottomPadding(level: 1),
                showsAccent: true
            )
        }
        return nil
    }

    private func orderedListContent(from trimmed: String) -> (marker: String, content: String)? {
        guard let dotIndex = trimmed.firstIndex(of: ".") else { return nil }
        let prefix = String(trimmed[..<dotIndex])
        guard !prefix.isEmpty, prefix.allSatisfy(\.isNumber) else { return nil }
        let remainder = trimmed[trimmed.index(after: dotIndex)...].trimmingCharacters(in: .whitespaces)
        guard !remainder.isEmpty else { return nil }
        return ("\(prefix).", remainder)
    }

    private func styledInlineAttributedText(
        _ string: String,
        font: UIFont,
        color: UIColor = UIColor(AppTheme.text),
        isItalicBase: Bool = false,
        paragraph: NSParagraphStyle
    ) -> NSAttributedString {
        let baseFont: UIFont
        if isItalicBase, let descriptor = font.fontDescriptor.withSymbolicTraits(.traitItalic) {
            baseFont = UIFont(descriptor: descriptor, size: font.pointSize)
        } else {
            baseFont = font
        }

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]

        guard let regex = try? NSRegularExpression(pattern: "(\\[([^\\]]+)\\]\\((https?:\\/\\/[^\\s)]+)\\))|(\\*\\*([^*]+)\\*\\*)|(`([^`]+)`)|(?<!\\*)(\\*([^*\\n]+)\\*)(?!\\*)|(?<!_)(_([^_\\n]+)_)(?!_)") else {
            return NSAttributedString(string: string, attributes: baseAttributes)
        }

        let nsString = string as NSString
        let matches = regex.matches(in: string, range: NSRange(location: 0, length: nsString.length))
        if matches.isEmpty {
            return NSAttributedString(string: string, attributes: baseAttributes)
        }

        let result = NSMutableAttributedString()
        var currentLocation = 0

        for match in matches {
            let fullRange = match.range(at: 0)
            if fullRange.location > currentLocation {
                let plain = nsString.substring(with: NSRange(location: currentLocation, length: fullRange.location - currentLocation))
                result.append(NSAttributedString(string: plain, attributes: baseAttributes))
            }

            if match.range(at: 2).location != NSNotFound, match.range(at: 3).location != NSNotFound {
                let title = nsString.substring(with: match.range(at: 2))
                let urlString = nsString.substring(with: match.range(at: 3))
                let linkAttributes: [NSAttributedString.Key: Any] = [
                    .font: baseFont,
                    .foregroundColor: UIColor(AppTheme.blue),
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .link: URL(string: urlString) as Any,
                    .paragraphStyle: paragraph
                ]
                result.append(NSAttributedString(string: title, attributes: linkAttributes))
            } else if match.range(at: 5).location != NSNotFound {
                let bold = nsString.substring(with: match.range(at: 5))
                let boldFont = UIFont.systemFont(ofSize: baseFont.pointSize, weight: .bold)
                result.append(NSAttributedString(string: bold, attributes: [
                    .font: boldFont,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph
                ]))
            } else if match.range(at: 7).location != NSNotFound {
                let code = nsString.substring(with: match.range(at: 7))
                result.append(NSAttributedString(string: "\u{2009}\(code)\u{2009}", attributes: [
                    .font: style.codeUIFont,
                    .foregroundColor: UIColor(AppTheme.blue),
                    .backgroundColor: UIColor(AppTheme.blue).withAlphaComponent(0.07),
                    .paragraphStyle: paragraph
                ]))
            } else if match.range(at: 9).location != NSNotFound {
                let italic = nsString.substring(with: match.range(at: 9))
                result.append(NSAttributedString(string: italic, attributes: [
                    .font: italicFont(from: baseFont),
                    .foregroundColor: color,
                    .paragraphStyle: paragraph
                ]))
            } else if match.range(at: 11).location != NSNotFound {
                let italic = nsString.substring(with: match.range(at: 11))
                result.append(NSAttributedString(string: italic, attributes: [
                    .font: italicFont(from: baseFont),
                    .foregroundColor: color,
                    .paragraphStyle: paragraph
                ]))
            }

            currentLocation = fullRange.location + fullRange.length
        }

        if currentLocation < nsString.length {
            let trailing = nsString.substring(from: currentLocation)
            result.append(NSAttributedString(string: trailing, attributes: baseAttributes))
        }

        return result
    }

    private func italicFont(from font: UIFont) -> UIFont {
        if let descriptor = font.fontDescriptor.withSymbolicTraits(.traitItalic) {
            return UIFont(descriptor: descriptor, size: font.pointSize)
        }
        return font
    }
}

extension MarkdownishText {
    fileprivate func isHorizontalRule(_ trimmed: String) -> Bool {
        guard trimmed.count >= 3 else { return false }
        let stripped = trimmed.filter { $0 != " " }
        guard stripped.count >= 3 else { return false }
        let first = stripped.first!
        return (first == "-" || first == "*" || first == "_") && stripped.allSatisfy({ $0 == first })
    }
}

private struct HeadingSpec {
    let text: String
    let uiFont: UIFont
    let uiColor: UIColor
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let showsAccent: Bool
    var accentWidth: CGFloat = 34
}

private enum MarkdownBlock {
    case lines([String])
    case list([String])
    case quote([String])
    case code(language: String?, content: String)
}

private enum MarkdownSegment {
    case text(NSAttributedString, String)  // attributed text + cache key
    case code(String?, String)              // language + content
}

private struct CodeCardView: View {
    let language: String?
    let content: String
    let style: ChatAppearanceStyle

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: style.scaled(8)) {
                if let language, !language.isEmpty {
                    Text(language.uppercased())
                        .font(.system(size: style.scaled(10.5), weight: .semibold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(AppTheme.assistantAccent.opacity(0.90))
                }

                Spacer(minLength: 0)

                Button(action: copyCode) {
                    HStack(spacing: style.scaled(4)) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: style.scaled(10.5), weight: .semibold))
                        if copied {
                            Text(String(localized: "Copied"))
                                .font(.system(size: style.scaled(10.5), weight: .semibold))
                        }
                    }
                    .foregroundStyle(copied ? AppTheme.assistantAccent : AppTheme.dim.opacity(0.95))
                    .padding(.horizontal, style.scaled(7))
                    .padding(.vertical, style.scaled(4))
                    .background(
                        Capsule(style: .continuous)
                            .fill(AppTheme.panel.opacity(0.8))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .highPriorityGesture(
                    TapGesture().onEnded {
                        copyCode()
                    }
                )
                .accessibilityLabel(String(localized: copied ? "Copied code block." : "Copy code block."))
            }
            .padding(.horizontal, style.scaled(10))
            .padding(.top, style.scaled(7))
            .padding(.bottom, style.scaled(4))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(content)
                    .font(.system(size: style.scaled(12.5), design: .monospaced))
                    .foregroundStyle(AppTheme.text)
                    .lineSpacing(style.scaled(1.5))
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.horizontal, style.scaled(10))
                    .padding(.top, 0)
                    .padding(.bottom, style.scaled(8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: style.scaled(6), style: .continuous)
                .fill(AppTheme.panelAlt.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: style.scaled(6), style: .continuous)
                .stroke(AppTheme.border.opacity(0.25), lineWidth: 0.5)
        )
    }

    private func copyCode() {
        UIPasteboard.general.string = content
        withAnimation(.easeInOut(duration: 0.15)) {
            copied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.15)) {
                copied = false
            }
        }
    }
}

private struct NativeAttributedTextView: UIViewRepresentable {
    let attributedText: NSAttributedString
    let cacheKey: String

    final class Coordinator {
        var lastCacheKey: String?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        textView.dataDetectorTypes = []
        textView.linkTextAttributes = [
            .foregroundColor: UIColor(AppTheme.blue),
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        textView.setContentHuggingPriority(.required, for: .vertical)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if context.coordinator.lastCacheKey != cacheKey {
            uiView.attributedText = attributedText
            context.coordinator.lastCacheKey = cacheKey
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let targetWidth = proposal.width ?? UIScreen.main.bounds.width
        let fitting = uiView.sizeThatFits(CGSize(width: targetWidth, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: min(targetWidth, fitting.width), height: ceil(fitting.height))
    }
}
