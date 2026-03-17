import AppKit
import TinyKit

/// Lightweight regex-based Markdown syntax highlighter for NSTextView.
/// Designed to be called on every text change — keeps it fast by only
/// doing a single pass of regex matches over the full string.
final class MarkdownHighlighter: SyntaxHighlighting {
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

    /// Syntax punctuation at ~50% contrast so formatting characters recede
    /// while the actual text stays at full contrast.
    private let syntaxColor = NSColor.textColor.withAlphaComponent(0.5)

    private func dimRange(_ range: NSRange, in storage: NSTextStorage) {
        storage.addAttribute(.foregroundColor, value: syntaxColor, range: range)
    }

    private func dimDelimiters(start: Int, end: Int, in storage: NSTextStorage, matchRange: NSRange) {
        if start > 0 {
            dimRange(NSRange(location: matchRange.location, length: start), in: storage)
        }
        if end > 0 {
            dimRange(NSRange(location: matchRange.location + matchRange.length - end, length: end), in: storage)
        }
    }

    private func applyStyle(_ style: Style, to storage: NSTextStorage, range: NSRange, match: NSTextCheckingResult? = nil, isDark: Bool) {
        switch style {
        case .heading:
            let headingFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize * 1.15, weight: .bold)
            storage.addAttributes([
                .font: headingFont,
                .foregroundColor: NSColor.labelColor,
            ], range: range)
            // Dim the #{1,6} prefix
            let str = (storage.string as NSString).substring(with: range)
            var prefixLen = 0
            for ch in str {
                if ch == "#" { prefixLen += 1 }
                else { break }
            }
            // Include trailing spaces after #
            for ch in str.dropFirst(prefixLen) {
                if ch == " " || ch == "\t" { prefixLen += 1 }
                else { break }
            }
            if prefixLen > 0 {
                dimRange(NSRange(location: range.location, length: prefixLen), in: storage)
            }

        case .bold:
            let boldFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .bold)
            storage.addAttribute(.font, value: boldFont, range: range)
            dimDelimiters(start: 2, end: 2, in: storage, matchRange: range)

        case .italic:
            if let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask) as NSFont? {
                storage.addAttribute(.font, value: italicFont, range: range)
            }
            dimDelimiters(start: 1, end: 1, in: storage, matchRange: range)

        case .strikethrough:
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            dimDelimiters(start: 2, end: 2, in: storage, matchRange: range)

        case .inlineCode:
            let codeColor = isDark ? NSColor(white: 1.0, alpha: 0.15) : NSColor(white: 0.0, alpha: 0.06)
            storage.addAttributes([
                .backgroundColor: codeColor,
                .foregroundColor: isDark ? NSColor.systemPink : NSColor.systemRed,
            ], range: range)
            // Dim the ` delimiters
            dimDelimiters(start: 1, end: 1, in: storage, matchRange: range)

        case .codeBlock:
            let bgColor = isDark ? NSColor(white: 1.0, alpha: 0.08) : NSColor(white: 0.0, alpha: 0.04)
            storage.addAttributes([
                .backgroundColor: bgColor,
                .foregroundColor: NSColor.secondaryLabelColor,
            ], range: range)
            // Dim the ``` fence lines
            let str = (storage.string as NSString).substring(with: range)
            let lines = str.components(separatedBy: "\n")
            if lines.count >= 2 {
                // Opening ``` line
                let openLen = lines.first!.count
                dimRange(NSRange(location: range.location, length: openLen), in: storage)
                // Closing ``` line
                let closeLen = lines.last!.count
                dimRange(NSRange(location: range.location + range.length - closeLen, length: closeLen), in: storage)
            }

        case .link:
            // Link text in accent color
            if let match, match.numberOfRanges >= 3 {
                let titleRange = match.range(at: 1)
                if titleRange.location != NSNotFound {
                    storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: titleRange)
                }
                let urlRange = match.range(at: 2) // (url) part
                if urlRange.location != NSNotFound {
                    storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: urlRange)
                }
            }
            // Dim [ and ] brackets
            dimRange(NSRange(location: range.location, length: 1), in: storage)
            if let match, match.numberOfRanges >= 2 {
                let titleRange = match.range(at: 1)
                if titleRange.location != NSNotFound {
                    // ] is right after title
                    dimRange(NSRange(location: titleRange.location + titleRange.length, length: 1), in: storage)
                }
            }

        case .image:
            // alt text in accent color
            if let match, match.numberOfRanges >= 4 {
                let altRange = match.range(at: 2)
                if altRange.location != NSNotFound {
                    storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: altRange)
                }
                let urlRange = match.range(at: 3) // (url) part
                if urlRange.location != NSNotFound {
                    storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: urlRange)
                }
            }
            // Dim ![ and ] brackets
            dimRange(NSRange(location: range.location, length: 2), in: storage)
            if let match, match.numberOfRanges >= 3 {
                let bangBracketRange = match.range(at: 1) // ![alt]
                if bangBracketRange.location != NSNotFound {
                    // ] at end of ![alt]
                    dimRange(NSRange(location: bangBracketRange.location + bangBracketRange.length - 1, length: 1), in: storage)
                }
            }

        case .blockquote:
            // Dim only the > prefix, leave text at full contrast
            let str = (storage.string as NSString).substring(with: range)
            var prefixLen = 0
            for ch in str {
                if ch == ">" || ch == " " { prefixLen += 1 }
                else { break }
            }
            if prefixLen > 0 {
                dimRange(NSRange(location: range.location, length: prefixLen), in: storage)
            }

        case .listMarker:
            storage.addAttribute(.foregroundColor, value: syntaxColor, range: range)

        case .horizontalRule:
            storage.addAttribute(.foregroundColor, value: NSColor.separatorColor, range: range)
        }
    }
}
