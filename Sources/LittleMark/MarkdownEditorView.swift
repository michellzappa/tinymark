import SwiftUI
import AppKit

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var wordWrap: Bool
    @Binding var fontSize: Double
    @Binding var showLineNumbers: Bool
    var isMarkdown: Bool
    var fileDirectory: URL?
    var scrollBridge: ScrollBridge

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = LittleMarkTextView()

        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .textColor
        textView.textContainerInset = NSSize(width: 24, height: 100)
        textView.delegate = context.coordinator
        textView.string = text

        // Word wrap setup
        configureWordWrap(textView: textView, scrollView: scrollView, enabled: wordWrap)

        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = !wordWrap

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = !wordWrap
        scrollView.drawsBackground = false

        textView.fileDirectory = fileDirectory
        textView.registerForDraggedTypes([.fileURL])
        textView.updateBottomPadding()

        // Line number gutter
        let gutter = LineNumberGutter(textView: textView)
        scrollView.verticalRulerView = gutter
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = showLineNumbers

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.gutter = gutter
        context.coordinator.isMarkdown = isMarkdown
        context.coordinator.highlighter.baseFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        context.coordinator.applyHighlighting()

        // Observe scroll position
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        context.coordinator.parent = self

        textView.fileDirectory = fileDirectory
        textView.updateBottomPadding()
        scrollView.rulersVisible = showLineNumbers
        context.coordinator.isMarkdown = isMarkdown
        context.coordinator.gutter?.needsDisplay = true

        let fontChanged = context.coordinator.highlighter.baseFont.pointSize != fontSize
        if fontChanged {
            let newFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            context.coordinator.highlighter.baseFont = newFont
            textView.font = newFont
        }

        var textChanged = false
        if textView.string != text {
            textChanged = true
            let selectedRanges = textView.selectedRanges
            textView.string = text
            // Clamp restored ranges to new string length to avoid crash
            let len = (text as NSString).length
            let clamped = selectedRanges.compactMap { value -> NSValue? in
                let r = value.rangeValue
                let loc = min(r.location, len)
                let end = min(r.location + r.length, len)
                return NSValue(range: NSRange(location: loc, length: end - loc))
            }
            if !clamped.isEmpty {
                textView.selectedRanges = clamped
            }
        }

        if fontChanged || textChanged {
            context.coordinator.applyHighlighting()
        }

        configureWordWrap(textView: textView, scrollView: scrollView, enabled: wordWrap)
    }

    private func configureWordWrap(textView: NSTextView, scrollView: NSScrollView, enabled: Bool) {
        // Skip if already in the correct state
        let currentlyWrapping = textView.textContainer?.widthTracksTextView ?? true
        guard currentlyWrapping != enabled else { return }

        if enabled {
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            textView.isHorizontallyResizable = false
            scrollView.hasHorizontalScroller = false
        } else {
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.isHorizontallyResizable = true
            scrollView.hasHorizontalScroller = true
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditorView
        var textView: LittleMarkTextView?
        var scrollView: NSScrollView?
        var gutter: LineNumberGutter?
        var isMarkdown: Bool = true
        let highlighter = SyntaxHighlighter()
        private var highlightDebounce: DispatchWorkItem?

        init(_ parent: MarkdownEditorView) {
            self.parent = parent
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            scheduleHighlighting()
            gutter?.needsDisplay = true
        }

        func applyHighlighting() {
            guard let textView, let storage = textView.textStorage else { return }
            if isMarkdown {
                highlighter.highlight(storage)
            } else {
                // Reset to plain monospaced text for non-markdown files
                let fullRange = NSRange(location: 0, length: (storage.string as NSString).length)
                storage.beginEditing()
                storage.addAttributes([
                    .font: highlighter.baseFont,
                    .foregroundColor: NSColor.textColor,
                    .backgroundColor: NSColor.clear,
                    .strikethroughStyle: 0,
                ], range: fullRange)
                storage.endEditing()
            }
        }

        @objc func scrollViewDidScroll(_ notification: Notification) {
            guard let scrollView, let docView = scrollView.documentView else { return }
            let contentHeight = docView.frame.height - scrollView.contentSize.height
            guard contentHeight > 0 else { return }
            let fraction = min(max(scrollView.contentView.bounds.origin.y / contentHeight, 0), 1)
            parent.scrollBridge.fraction = fraction
            parent.scrollBridge.onScroll?(fraction)
        }

        private func scheduleHighlighting() {
            highlightDebounce?.cancel()
            let task = DispatchWorkItem { [weak self] in
                self?.applyHighlighting()
            }
            highlightDebounce = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: task)
        }
    }
}

// MARK: - LittleMarkTextView — handles keyboard shortcuts, smart pairs, tab indentation

final class LittleMarkTextView: NSTextView {

    /// The directory of the currently edited file (set by the coordinator)
    var fileDirectory: URL?

    // Extra bottom-only padding so end of text can scroll to the middle.
    // textContainerInset applies equally top & bottom, so we override
    // textContainerOrigin to keep the top inset small (20pt) while the
    // large inset value only adds space at the bottom.
    private var bottomPadding: CGFloat = 100

    func updateBottomPadding() {
        guard let scrollView = enclosingScrollView else { return }
        let half = max(scrollView.contentSize.height * 0.45, 100)
        if abs(bottomPadding - half) > 10 {
            bottomPadding = half
            textContainerInset = NSSize(width: 24, height: half)
        }
    }

    // Pin the top origin to a small value regardless of textContainerInset
    override var textContainerOrigin: NSPoint {
        return NSPoint(x: 24, y: 20)
    }

    // MARK: - Current line highlight

    private let lineHighlightColor: NSColor = {
        NSColor(calibratedWhite: 0.5, alpha: 0.06)
    }()

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        needsDisplay = true
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        guard let layoutManager = layoutManager, let textContainer = textContainer else { return }
        let selRange = selectedRange()
        let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: selRange.location, length: 0), actualCharacterRange: nil)
        var lineRect = layoutManager.lineFragmentRect(forGlyphAt: max(glyphRange.location, 0), effectiveRange: nil)
        lineRect.origin.x = 0
        lineRect.origin.y += textContainerOrigin.y
        lineRect.size.width = bounds.width

        lineHighlightColor.setFill()
        lineRect.fill()
    }

    // MARK: - Drag & Drop images

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if hasImageURLs(sender) { return .copy }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: ["public.image"]
        ]) as? [URL], !items.isEmpty else {
            return super.performDragOperation(sender)
        }

        var lines: [String] = []
        for url in items {
            let alt = url.deletingPathExtension().lastPathComponent
            let path: String
            if let dir = fileDirectory {
                // Compute relative path from file's directory to the image
                path = relativePath(from: dir, to: url)
            } else {
                path = url.path
            }
            lines.append("![\(alt)](\(path))")
        }

        insertText(lines.joined(separator: "\n"), replacementRange: selectedRange())
        return true
    }

    private func relativePath(from base: URL, to target: URL) -> String {
        let baseParts = base.standardizedFileURL.pathComponents
        let targetParts = target.standardizedFileURL.pathComponents

        // Find common prefix length
        var common = 0
        while common < baseParts.count && common < targetParts.count && baseParts[common] == targetParts[common] {
            common += 1
        }

        // Build relative path: go up from base, then down to target
        let ups = baseParts.count - common
        var parts = Array(repeating: "..", count: ups)
        parts += targetParts[common...]

        let result = parts.joined(separator: "/")
        return result.hasPrefix(".") ? result : "./\(result)"
    }

    private func hasImageURLs(_ info: NSDraggingInfo) -> Bool {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: ["public.image"]
        ]) as? [URL]
        return urls != nil && !urls!.isEmpty
    }

    // Smart pair mappings
    private static let smartPairs: [String: (String, String)] = [
        "*": ("*", "*"),
        "_": ("_", "_"),
        "`": ("`", "`"),
        "[": ("[", "]"),
        "(": ("(", ")"),
        "\"": ("\"", "\""),
    ]

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers ?? ""

        // Cmd+F → show find bar
        if flags == .command && chars == "f" {
            let item = NSMenuItem()
            item.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
            performFindPanelAction(item)
            return
        }
        // Opt+Cmd+F → show find & replace
        if flags == [.command, .option] && chars == "f" {
            let item = NSMenuItem()
            item.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
            performFindPanelAction(item)
            // Toggle the replace field visibility
            if let findBar = enclosingScrollView?.findBarView {
                // Try to show replace via the standard mechanism
                let sel = NSSelectorFromString("toggleReplaceBar:")
                if findBar.responds(to: sel) {
                    findBar.perform(sel, with: nil)
                }
            }
            return
        }
        // Cmd+G → find next
        if flags == .command && chars == "g" {
            let item = NSMenuItem()
            item.tag = Int(NSFindPanelAction.next.rawValue)
            performFindPanelAction(item)
            return
        }
        // Cmd+Shift+G → find previous
        if flags == [.command, .shift] && chars == "g" {
            let item = NSMenuItem()
            item.tag = Int(NSFindPanelAction.previous.rawValue)
            performFindPanelAction(item)
            return
        }

        // Cmd+B → bold
        if flags == .command && chars == "b" {
            wrapSelection(prefix: "**", suffix: "**"); return
        }
        // Cmd+I → italic
        if flags == .command && chars == "i" {
            wrapSelection(prefix: "_", suffix: "_"); return
        }
        // Cmd+K → link
        if flags == .command && chars == "k" {
            insertLink(); return
        }
        // Cmd+Shift+K → inline code
        if flags == [.command, .shift] && chars == "k" {
            wrapSelection(prefix: "`", suffix: "`"); return
        }

        // Opt+Up → move line up
        if flags == .option && event.keyCode == 126 {
            moveLineUp(); return
        }
        // Opt+Down → move line down
        if flags == .option && event.keyCode == 125 {
            moveLineDown(); return
        }
        // Cmd+Shift+D → duplicate line
        if flags == [.command, .shift] && chars == "d" {
            duplicateLine(); return
        }
        // Ctrl+Shift+K → delete line
        if flags == [.control, .shift] && chars == "k" {
            deleteLine(); return
        }
        // Cmd+L → select line
        if flags == .command && chars == "l" {
            selectLine(); return
        }
        // Cmd+Enter → insert line below (keyCode 36 = Return)
        if flags == .command && event.keyCode == 36 {
            insertLineBelow(); return
        }
        // Cmd+Shift+Enter → insert line above
        if flags == [.command, .shift] && event.keyCode == 36 {
            insertLineAbove(); return
        }
        // Cmd+/ → toggle comment (keyCode 44 = /)
        if flags == .command && event.keyCode == 44 {
            toggleComment(); return
        }

        // Tab / Shift+Tab for list indentation
        if chars == "\t" {
            if flags.contains(.shift) {
                outdentLines(); return
            } else if isOnListLine() {
                indentLines(); return
            }
        }

        // Enter → auto-indent (keyCode 36 = Return)
        if flags.isEmpty && event.keyCode == 36 {
            insertNewlineWithIndent(); return
        }

        // Smart pairs — only when there's a selection or at a word boundary
        if flags.isEmpty || flags == .shift {
            if let typed = event.characters, let pair = Self.smartPairs[typed] {
                let sel = selectedRange()
                if sel.length > 0 {
                    wrapSelection(prefix: pair.0, suffix: pair.1)
                    return
                }
            }
        }

        super.keyDown(with: event)
    }

    // MARK: - Markdown shortcuts

    private func wrapSelection(prefix: String, suffix: String) {
        let sel = selectedRange()
        guard let storage = textStorage else { return }
        let source = storage.string as NSString

        if sel.length > 0 {
            let selected = source.substring(with: sel)
            // Check if already wrapped — if so, unwrap
            let prefixLen = (prefix as NSString).length
            let suffixLen = (suffix as NSString).length
            if sel.location >= prefixLen && sel.location + sel.length + suffixLen <= source.length {
                let beforeRange = NSRange(location: sel.location - prefixLen, length: prefixLen)
                let afterRange = NSRange(location: sel.location + sel.length, length: suffixLen)
                if source.substring(with: beforeRange) == prefix && source.substring(with: afterRange) == suffix {
                    // Remove wrapping
                    let fullRange = NSRange(location: beforeRange.location, length: prefixLen + sel.length + suffixLen)
                    insertText(selected, replacementRange: fullRange)
                    setSelectedRange(NSRange(location: beforeRange.location, length: sel.length))
                    return
                }
            }
            let wrapped = prefix + selected + suffix
            insertText(wrapped, replacementRange: sel)
            setSelectedRange(NSRange(location: sel.location + prefixLen, length: sel.length))
        } else {
            let wrapped = prefix + suffix
            insertText(wrapped, replacementRange: sel)
            setSelectedRange(NSRange(location: sel.location + (prefix as NSString).length, length: 0))
        }
    }

    private func insertLink() {
        let sel = selectedRange()
        guard let storage = textStorage else { return }
        let source = storage.string as NSString

        if sel.length > 0 {
            let selected = source.substring(with: sel)
            let link = "[\(selected)](url)"
            insertText(link, replacementRange: sel)
            // Select "url"
            let urlStart = sel.location + (selected as NSString).length + 2
            setSelectedRange(NSRange(location: urlStart, length: 3))
        } else {
            insertText("[](url)", replacementRange: sel)
            setSelectedRange(NSRange(location: sel.location + 1, length: 0))
        }
    }

    // MARK: - List indentation

    private func isOnListLine() -> Bool {
        guard let storage = textStorage else { return false }
        let source = storage.string as NSString
        let lineRange = source.lineRange(for: selectedRange())
        let line = source.substring(with: lineRange)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ")
            || trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
    }

    private func indentLines() {
        modifySelectedLines { "    " + $0 }
    }

    private func outdentLines() {
        modifySelectedLines { line in
            if line.hasPrefix("    ") { return String(line.dropFirst(4)) }
            if line.hasPrefix("\t") { return String(line.dropFirst(1)) }
            return line
        }
    }

    // MARK: - Move line up/down

    private func moveLineUp() {
        guard let storage = textStorage else { return }
        let source = storage.string as NSString
        let sel = selectedRange()
        let lineRange = source.lineRange(for: sel)

        // Can't move first line up
        guard lineRange.location > 0 else { return }

        let prevLineRange = source.lineRange(for: NSRange(location: lineRange.location - 1, length: 0))
        let currentLine = source.substring(with: lineRange)
        let prevLine = source.substring(with: prevLineRange)

        let combined = NSRange(location: prevLineRange.location, length: prevLineRange.length + lineRange.length)

        // Ensure both lines end with newline for clean swap
        let currentTrimmed = currentLine.hasSuffix("\n") ? currentLine : currentLine + "\n"
        let prevTrimmed = prevLine.hasSuffix("\n") ? prevLine : prevLine + "\n"

        // If we're at the very last line (no trailing newline), adjust
        let replacement: String
        if !currentLine.hasSuffix("\n") && prevLine.hasSuffix("\n") {
            replacement = currentTrimmed + String(prevTrimmed.dropLast())
        } else {
            replacement = currentTrimmed + prevTrimmed
        }

        insertText(replacement, replacementRange: combined)
        // Place cursor at the moved line
        let newSelLoc = prevLineRange.location + (sel.location - lineRange.location)
        setSelectedRange(NSRange(location: newSelLoc, length: sel.length))
    }

    private func moveLineDown() {
        guard let storage = textStorage else { return }
        let source = storage.string as NSString
        let sel = selectedRange()
        let lineRange = source.lineRange(for: sel)

        let lineEnd = lineRange.location + lineRange.length
        // Can't move last line down
        guard lineEnd < source.length else { return }

        let nextLineRange = source.lineRange(for: NSRange(location: lineEnd, length: 0))
        let currentLine = source.substring(with: lineRange)
        let nextLine = source.substring(with: nextLineRange)

        let combined = NSRange(location: lineRange.location, length: lineRange.length + nextLineRange.length)

        let nextTrimmed = nextLine.hasSuffix("\n") ? nextLine : nextLine + "\n"
        let currentTrimmed = currentLine.hasSuffix("\n") ? currentLine : currentLine + "\n"

        let replacement: String
        if !nextLine.hasSuffix("\n") && currentLine.hasSuffix("\n") {
            replacement = nextTrimmed + String(currentTrimmed.dropLast())
        } else {
            replacement = nextTrimmed + currentTrimmed
        }

        insertText(replacement, replacementRange: combined)
        let newSelLoc = lineRange.location + (nextTrimmed as NSString).length + (sel.location - lineRange.location)
        setSelectedRange(NSRange(location: newSelLoc, length: sel.length))
    }

    // MARK: - Duplicate line

    private func duplicateLine() {
        guard let storage = textStorage else { return }
        let source = storage.string as NSString
        let sel = selectedRange()
        let lineRange = source.lineRange(for: sel)
        var lineText = source.substring(with: lineRange)

        if !lineText.hasSuffix("\n") {
            lineText = "\n" + lineText
        }

        // Insert duplicate after the current line
        let insertLoc = lineRange.location + lineRange.length
        insertText(lineText, replacementRange: NSRange(location: insertLoc, length: 0))
        // Move cursor to the duplicated line
        setSelectedRange(NSRange(location: insertLoc + (sel.location - lineRange.location) + (lineText.hasPrefix("\n") ? 1 : 0), length: sel.length))
    }

    // MARK: - Delete line

    private func deleteLine() {
        guard let storage = textStorage else { return }
        let source = storage.string as NSString
        let lineRange = source.lineRange(for: selectedRange())
        insertText("", replacementRange: lineRange)
    }

    // MARK: - Select line

    private func selectLine() {
        guard let storage = textStorage else { return }
        let source = storage.string as NSString
        let sel = selectedRange()
        let lineRange = source.lineRange(for: sel)

        // If already selecting this line, extend to next line
        if sel == lineRange && lineRange.location + lineRange.length < source.length {
            let nextLineRange = source.lineRange(for: NSRange(location: lineRange.location + lineRange.length, length: 0))
            setSelectedRange(NSRange(location: lineRange.location, length: lineRange.length + nextLineRange.length))
        } else {
            setSelectedRange(lineRange)
        }
    }

    // MARK: - Insert line below/above

    private func insertLineBelow() {
        guard let storage = textStorage else { return }
        let source = storage.string as NSString
        let lineRange = source.lineRange(for: selectedRange())
        let lineEnd = lineRange.location + lineRange.length

        // Get indentation of current line
        let line = source.substring(with: lineRange)
        let indent = leadingWhitespace(line)

        if lineEnd > 0 && source.character(at: lineEnd - 1) == UInt16(Character("\n").asciiValue!) {
            insertText(indent, replacementRange: NSRange(location: lineEnd, length: 0))
            setSelectedRange(NSRange(location: lineEnd + (indent as NSString).length, length: 0))
        } else {
            insertText("\n" + indent, replacementRange: NSRange(location: lineEnd, length: 0))
            setSelectedRange(NSRange(location: lineEnd + 1 + (indent as NSString).length, length: 0))
        }
    }

    private func insertLineAbove() {
        guard let storage = textStorage else { return }
        let source = storage.string as NSString
        let lineRange = source.lineRange(for: selectedRange())

        let line = source.substring(with: lineRange)
        let indent = leadingWhitespace(line)

        insertText(indent + "\n", replacementRange: NSRange(location: lineRange.location, length: 0))
        setSelectedRange(NSRange(location: lineRange.location + (indent as NSString).length, length: 0))
    }

    // MARK: - Toggle comment

    private func toggleComment() {
        modifySelectedLines { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("<!-- ") && trimmed.hasSuffix(" -->") {
                // Unwrap comment
                var result = line
                if let startRange = result.range(of: "<!-- ") {
                    result.removeSubrange(startRange)
                }
                if let endRange = result.range(of: " -->", options: .backwards) {
                    result.removeSubrange(endRange)
                }
                return result
            } else {
                // Wrap in comment
                let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
                let content = String(line.drop(while: { $0 == " " || $0 == "\t" }))
                return indent + "<!-- " + content + " -->"
            }
        }
    }

    // MARK: - Auto-indent on Enter

    private func insertNewlineWithIndent() {
        guard let storage = textStorage else { super.insertNewline(self); return }
        let source = storage.string as NSString
        let sel = selectedRange()
        let lineRange = source.lineRange(for: NSRange(location: sel.location, length: 0))
        let currentLine = source.substring(with: lineRange)

        // Match leading whitespace
        var indent = leadingWhitespace(currentLine)

        // If the line is a list item, continue the list
        let trimmed = currentLine.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            // If the list item is empty (just the marker), clear it instead of continuing
            let marker = String(trimmed.prefix(2))
            if trimmed == marker || trimmed == marker.trimmingCharacters(in: .whitespaces) {
                // Clear the empty list item
                insertText("\n", replacementRange: sel)
                return
            }
            indent += marker
        } else if let match = trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) {
            let numStr = trimmed[match].trimmingCharacters(in: .letters.union(.punctuationCharacters).union(.whitespaces))
            if let num = Int(numStr) {
                let nextMarker = "\(num + 1). "
                // If just the number marker with no content, clear it
                if trimmed.count <= (numStr.count + 2) {
                    insertText("\n", replacementRange: sel)
                    return
                }
                indent += nextMarker
            }
        }

        insertText("\n" + indent, replacementRange: sel)
    }

    private func leadingWhitespace(_ line: String) -> String {
        String(line.prefix(while: { $0 == " " || $0 == "\t" }))
    }

    // MARK: - Line helpers

    private func modifySelectedLines(transform: (String) -> String) {
        guard let storage = textStorage else { return }
        let source = storage.string as NSString
        let lineRange = source.lineRange(for: selectedRange())
        let linesText = source.substring(with: lineRange)
        let lines = linesText.components(separatedBy: "\n")

        // Don't transform the trailing empty element from trailing newline
        let transformed = lines.enumerated().map { i, line in
            (i == lines.count - 1 && line.isEmpty) ? line : transform(line)
        }
        let result = transformed.joined(separator: "\n")

        insertText(result, replacementRange: lineRange)
        setSelectedRange(NSRange(location: lineRange.location, length: (result as NSString).length))
    }
}
