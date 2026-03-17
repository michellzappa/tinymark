import SwiftUI

public struct StatusBarView: View {
    public let text: String

    public init(text: String) {
        self.text = text
    }

    @State private var stats = TextStats()

    private struct TextStats {
        var words: Int = 0
        var chars: Int = 0
        var lines: Int = 1
    }

    private var readingTime: String {
        let minutes = stats.words / 200
        if minutes == 0 { return "" }
        return "~\(minutes) min read"
    }

    public var body: some View {
        HStack(spacing: 16) {
            Text("\(stats.lines) lines")
            Text("\(stats.words) words")
            Text("\(stats.chars) chars")
            Text(readingTime)
            Spacer()
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(.bar)
        .task(id: text) {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let t = text
            let words = t.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            let chars = t.count
            let lines = max(t.components(separatedBy: "\n").count, 1)
            stats = TextStats(words: words, chars: chars, lines: lines)
        }
    }
}
