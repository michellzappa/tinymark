import SwiftUI

struct ContentView: View {
    @Bindable var state: AppState
    @AppStorage("wordWrap") private var wordWrap = true
    @AppStorage("previewUserPref") private var previewUserPref = true
    @AppStorage("fontSize") private var fontSize: Double = 14
    @State private var showQuickOpen = false
    @AppStorage("syncScroll") private var syncScroll = true
    @AppStorage("showLineNumbers") private var showLineNumbers = false
    @State private var scrollBridge = ScrollBridge()
    @State private var eventMonitor: Any?

    /// Preview is shown only when user wants it AND the file is markdown/svg
    private var showPreview: Bool {
        previewUserPref && (state.isMarkdownFile || state.isSVGFile)
    }

    var body: some View {
        NavigationSplitView {
            FileListView(state: state)
                .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 300)
        } detail: {
            VStack(spacing: 0) {
                if showPreview {
                    EditorSplitView {
                        MarkdownEditorView(text: $state.content, wordWrap: $wordWrap, fontSize: $fontSize, showLineNumbers: $showLineNumbers, isMarkdown: state.isMarkdownFile, fileDirectory: state.selectedFile?.deletingLastPathComponent(), scrollBridge: scrollBridge)
                    } right: {
                        MarkdownPreviewView(html: state.renderedHTML, baseURL: state.selectedFile?.deletingLastPathComponent(), scrollBridge: scrollBridge, syncScroll: syncScroll)
                    }
                } else {
                    MarkdownEditorView(text: $state.content, wordWrap: $wordWrap, fontSize: $fontSize, showLineNumbers: $showLineNumbers, isMarkdown: state.isMarkdownFile, fileDirectory: state.selectedFile?.deletingLastPathComponent(), scrollBridge: scrollBridge)
                }

                // Status bar
                StatusBarView(text: state.content)
            }
        }
        .onDisappear {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }
        .onAppear {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let chars = event.charactersIgnoringModifiers ?? ""

                // Opt+Z toggles word wrap
                if flags == .option && chars == "z" {
                    wordWrap.toggle()
                    return nil
                }
                // Opt+P toggles preview
                if flags == .option && chars == "p" {
                    previewUserPref.toggle()
                    return nil
                }
                // Opt+L toggles line numbers
                if flags == .option && chars == "l" {
                    showLineNumbers.toggle()
                    return nil
                }
                // Cmd+P quick open
                if flags == .command && chars == "p" {
                    showQuickOpen.toggle()
                    return nil
                }
                // Cmd+= / Cmd++ zoom in
                if flags == .command && (chars == "=" || chars == "+") {
                    fontSize = min(fontSize + 1, 32)
                    return nil
                }
                // Cmd+- zoom out
                if flags == .command && chars == "-" {
                    fontSize = max(fontSize - 1, 9)
                    return nil
                }
                // Cmd+0 reset zoom
                if flags == .command && chars == "0" {
                    fontSize = 14
                    return nil
                }
                // Cmd+F — let it pass through to NSTextView's find bar
                // Cmd+G — find next, Cmd+Shift+G — find previous
                if flags == .command && (chars == "f" || chars == "g") {
                    return event
                }
                if flags == [.command, .shift] && chars == "g" {
                    return event
                }
                return event
            }
        }
        .sheet(isPresented: $showQuickOpen) {
            QuickOpenView(state: state, isPresented: $showQuickOpen)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 12) {
                    Button {
                        wordWrap.toggle()
                    } label: {
                        Image(systemName: wordWrap ? "text.word.spacing" : "arrow.left.and.right.text.vertical")
                    }
                    .help("Toggle Word Wrap (⌥Z)")
                    Button {
                        showLineNumbers.toggle()
                    } label: {
                        Image(systemName: showLineNumbers ? "list.number" : "list.bullet")
                    }
                    .help("Toggle Line Numbers (⌥L)")
                    if state.isMarkdownFile || state.isSVGFile {
                        Button {
                            withAnimation { previewUserPref.toggle() }
                        } label: {
                            Image(systemName: showPreview ? "rectangle.righthalf.filled" : "rectangle.righthalf.inset.filled")
                        }
                        .help("Toggle Preview (⌥P)")
                        if showPreview {
                            Toggle(isOn: Binding(
                                get: { syncScroll },
                                set: { syncScroll = $0 }
                            )) {
                                Image(systemName: "arrow.up.arrow.down")
                            }
                            .toggleStyle(.button)
                            .help("Sync Scroll")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Status Bar

struct StatusBarView: View {
    let text: String
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

    var body: some View {
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
            // Debounce: wait a beat before recomputing stats
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

// MARK: - Quick Open

struct QuickOpenView: View {
    @Bindable var state: AppState
    @Binding var isPresented: Bool
    @State private var query = ""
    @FocusState private var isFocused: Bool

    private var filtered: [URL] {
        if query.isEmpty { return state.files }
        let q = query.lowercased()
        return state.files.filter { $0.lastPathComponent.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Open file…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .padding(16)
                .focused($isFocused)
                .onSubmit {
                    if let first = filtered.first {
                        state.selectFile(first)
                        isPresented = false
                    }
                }

            Divider()

            List(filtered, id: \.self, selection: Binding(
                get: { nil as URL? },
                set: { url in
                    if let url {
                        state.selectFile(url)
                        isPresented = false
                    }
                }
            )) { file in
                HStack {
                    Image(systemName: file.pathExtension.lowercased() == "svg" ? "photo" : "doc.text")
                        .foregroundStyle(.secondary)
                    Text(file.lastPathComponent)
                }
                .tag(file)
            }
            .listStyle(.plain)
        }
        .frame(width: 400, height: 300)
        .onAppear { isFocused = true }
        .onExitCommand { isPresented = false }
    }
}
