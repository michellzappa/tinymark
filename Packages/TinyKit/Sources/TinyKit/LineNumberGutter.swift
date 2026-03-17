import AppKit

/// A ruler view that draws line numbers for an NSTextView.
public final class LineNumberGutter: NSRulerView {

    private var textView: NSTextView? { clientView as? NSTextView }

    public init(textView: NSTextView) {
        super.init(scrollView: textView.enclosingScrollView!, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 36
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let string = textView.string as NSString
        let visibleRect = scrollView?.contentView.bounds ?? rect
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let textColor = isDark ? NSColor(white: 1, alpha: 0.25) : NSColor(white: 0, alpha: 0.3)
        let font = NSFont.monospacedDigitSystemFont(ofSize: max(textView.font?.pointSize ?? 14 - 2, 9), weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
        ]

        let origin = textView.textContainerOrigin

        var lineNumber = 1
        // Count lines before visible range
        var idx = 0
        while idx < visibleCharRange.location {
            let lineRange = string.lineRange(for: NSRange(location: idx, length: 0))
            idx = NSMaxRange(lineRange)
            lineNumber += 1
        }

        // Draw line numbers for visible lines
        idx = visibleCharRange.location
        while idx <= NSMaxRange(visibleCharRange) {
            let lineRange = string.lineRange(for: NSRange(location: idx, length: 0))
            let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            var lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            lineRect.origin.y += origin.y

            let numStr = "\(lineNumber)" as NSString
            let size = numStr.size(withAttributes: attrs)
            let x = ruleThickness - size.width - 8
            let y = lineRect.origin.y + (lineRect.height - size.height) / 2

            numStr.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)

            lineNumber += 1
            idx = NSMaxRange(lineRange)
            if idx == NSMaxRange(visibleCharRange) && idx == string.length {
                break // avoid infinite loop at end of text
            }
        }
    }
}
