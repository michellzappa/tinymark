import SwiftUI
import TinyKit

/// Markdown editor — wraps TinyEditorView with markdown-specific highlighting.
struct MarkdownEditorView: View {
    @Binding var text: String
    @Binding var wordWrap: Bool
    @Binding var fontSize: Double
    @Binding var showLineNumbers: Bool
    var isMarkdown: Bool
    var fileDirectory: URL?
    var scrollBridge: ScrollBridge
    var editorBridge: EditorBridge?

    var body: some View {
        TinyEditorView(
            text: $text,
            wordWrap: $wordWrap,
            fontSize: $fontSize,
            showLineNumbers: $showLineNumbers,
            shouldHighlight: isMarkdown,
            highlighterProvider: { MarkdownHighlighter() },
            commentStyle: .html,
            fileDirectory: fileDirectory,
            scrollBridge: scrollBridge,
            enableImageDrop: true,
            editorBridge: editorBridge
        )
    }
}
