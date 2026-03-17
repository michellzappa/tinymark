import AppKit

/// Lightweight regex-based Markdown syntax highlighter for NSTextView.
/// Designed to be called on every text change — keeps it fast by only
/// doing a single pass of regex matches over the full string.
final class SyntaxHighlighter {
    var baseFont: NSFont = .monospacedSystemFont(ofSize: 14, weight: .regular)

    // Cached regex patterns (compiled once)
    private static let patterns: [(NSRegularExpression, Style)] = {
        let defs: [(String, Style)] = [
            // Fenced code blocks (``` ... ```) — must come before inline patterns
            (#"^```[\s\S]*?^```"#, .codeBlock),
            // Headings
            (#"^#{1,6}\s+.*$"#, .heading),
            // Bold **text** or __text__
            (#"\*\*(.+?)\*\*|__(.+?)__"#, .bold),
            // Italic *text* or _text_ — must not match inside **bold**
            (#"(?<!\*)\*(?!\*)(?!\s)(.+?)(?<!\s)(?<!\*)\*(?!\*)|(?<!\w)_(?!\s)(.+?)(?<!\s)_(?!\w)"#, .italic),
            // Strikethrough ~~text~~
            (#"~~(.+?)~~"#, .strikethrough),
            // Inline code `text`
            (#"`[^`\n]+`"#, .inlineCode),
            // Links [text](url) — full match, parts colored separately
            (#"\[([^\]]+)\](\([^\)]+\))"#, .link),
            // Images ![alt](url)
            (#"(!\[([^\]]*)\])(\([^\)]+\))"#, .image),
            // Block quotes
            (#"^>+\s.*$"#, .blockquote),
            // Unordered list markers
            (#"^[\t ]*[-*+]\s"#, .listMarker),
            // Ordered list markers
            (#"^\s*\d+\.\s"#, .listMarker),
            // Horizontal rules
            (#"^(---+|\*\*\*+|___+)\s*$"#, .horizontalRule),
        ]
        return defs.compactMap { pattern, style in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return nil }
            return (regex, style)
        }
    }()

    enum Style {
        case heading, bold, italic, strikethrough, inlineCode, codeBlock
        case link, image, blockquote, listMarker, horizontalRule
    }

    func highlight(_ textStorage: NSTextStorage) {
        let source = textStorage.string
        let fullRange = NSRange(location: 0, length: (source as NSString).length)

        textStorage.beginEditing()

        // Reset to base style
        let baseColor = NSColor.textColor
        textStorage.addAttributes([
            .font: baseFont,
            .foregroundColor: baseColor,
            .strikethroughStyle: 0,
            .backgroundColor: NSColor.clear,
        ], range: fullRange)

        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // First pass: collect code block and inline code ranges so other patterns skip them
        var codeRanges: [NSRange] = []
        for (regex, style) in Self.patterns where style == .codeBlock || style == .inlineCode {
            regex.enumerateMatches(in: source, range: fullRange) { match, _, _ in
                guard let match else { return }
                self.applyStyle(style, to: textStorage, range: match.range, match: match, isDark: isDark)
                codeRanges.append(match.range)
            }
        }

        // Second pass: apply remaining patterns, skipping code ranges
        for (regex, style) in Self.patterns where style != .codeBlock && style != .inlineCode {
            regex.enumerateMatches(in: source, range: fullRange) { match, _, _ in
                guard let match else { return }
                let range = match.range
                let insideCode = codeRanges.contains { codeRange in
                    codeRange.location <= range.location &&
                    codeRange.location + codeRange.length >= range.location + range.length
                }
                guard !insideCode else { return }
                self.applyStyle(style, to: textStorage, range: range, match: match, isDark: isDark)
            }
        }

        textStorage.endEditing()
    }

    private func applyStyle(_ style: Style, to storage: NSTextStorage, range: NSRange, match: NSTextCheckingResult? = nil, isDark: Bool) {
        switch style {
        case .heading:
            let headingFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize * 1.15, weight: .bold)
            storage.addAttributes([
                .font: headingFont,
                .foregroundColor: NSColor.labelColor,
            ], range: range)

        case .bold:
            let boldFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .bold)
            storage.addAttribute(.font, value: boldFont, range: range)

        case .italic:
            if let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask) as NSFont? {
                storage.addAttribute(.font, value: italicFont, range: range)
            }

        case .strikethrough:
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)

        case .inlineCode:
            let codeColor = isDark ? NSColor(white: 1.0, alpha: 0.15) : NSColor(white: 0.0, alpha: 0.06)
            storage.addAttributes([
                .backgroundColor: codeColor,
                .foregroundColor: isDark ? NSColor.systemPink : NSColor.systemRed,
            ], range: range)

        case .codeBlock:
            let bgColor = isDark ? NSColor(white: 1.0, alpha: 0.08) : NSColor(white: 0.0, alpha: 0.04)
            storage.addAttributes([
                .backgroundColor: bgColor,
                .foregroundColor: NSColor.secondaryLabelColor,
            ], range: range)

        case .link:
            // [title] in accent color, (url) in muted color
            storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: range)
            if let match, match.numberOfRanges >= 3 {
                let urlRange = match.range(at: 2) // (url) part
                if urlRange.location != NSNotFound {
                    storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: urlRange)
                }
            }

        case .image:
            // ![alt] in accent color, (url) in muted color
            storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: range)
            if let match, match.numberOfRanges >= 4 {
                let urlRange = match.range(at: 3) // (url) part
                if urlRange.location != NSNotFound {
                    storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: urlRange)
                }
            }

        case .blockquote:
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)

        case .listMarker:
            storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor.withAlphaComponent(0.7), range: range)

        case .horizontalRule:
            storage.addAttribute(.foregroundColor, value: NSColor.separatorColor, range: range)
        }
    }
}
