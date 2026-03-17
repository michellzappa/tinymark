import SwiftUI
import TinyKit

struct ContentView: View {
    @Bindable var state: AppState
    @Binding var columnVisibility: NavigationSplitViewVisibility
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
        NavigationSplitView(columnVisibility: $columnVisibility) {
            TinyFileList(state: state)
                .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 300)
        } detail: {
            VStack(spacing: 0) {
                if state.tabs.count > 1 {
                    TinyTabBar(state: state)
                    Divider()
                }
                if showPreview {
                    EditorSplitView {
                        MarkdownEditorView(text: $state.content, wordWrap: $wordWrap, fontSize: $fontSize, showLineNumbers: $showLineNumbers, isMarkdown: state.isMarkdownFile, fileDirectory: state.selectedFile?.deletingLastPathComponent(), scrollBridge: scrollBridge)
                    } right: {
                        MarkdownPreviewView(html: state.renderedHTML, baseURL: state.selectedFile?.deletingLastPathComponent(), scrollBridge: scrollBridge, syncScroll: syncScroll)
                    }
                } else {
                    MarkdownEditorView(text: $state.content, wordWrap: $wordWrap, fontSize: $fontSize, showLineNumbers: $showLineNumbers, isMarkdown: state.isMarkdownFile, fileDirectory: state.selectedFile?.deletingLastPathComponent(), scrollBridge: scrollBridge)
                }

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

                if flags == .option && chars == "z" {
                    wordWrap.toggle()
                    return nil
                }
                if flags == .option && chars == "p" {
                    previewUserPref.toggle()
                    return nil
                }
                if flags == .option && chars == "l" {
                    showLineNumbers.toggle()
                    return nil
                }
                if flags == .command && chars == "p" {
                    showQuickOpen.toggle()
                    return nil
                }
                // Cmd+W close tab (only when multiple tabs open)
                if flags == .command && chars == "w" && state.tabs.count > 1 {
                    state.closeActiveTab()
                    return nil
                }
                if flags == .command && (chars == "=" || chars == "+") {
                    fontSize = min(fontSize + 1, 32)
                    return nil
                }
                if flags == .command && chars == "-" {
                    fontSize = max(fontSize - 1, 9)
                    return nil
                }
                if flags == .command && chars == "0" {
                    fontSize = 14
                    return nil
                }
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
                    .help("Toggle Word Wrap (\u{2325}Z)")
                    Button {
                        showLineNumbers.toggle()
                    } label: {
                        Image(systemName: showLineNumbers ? "list.number" : "list.bullet")
                    }
                    .help("Toggle Line Numbers (\u{2325}L)")
                    if state.isMarkdownFile || state.isSVGFile {
                        Button {
                            withAnimation { previewUserPref.toggle() }
                        } label: {
                            Image(systemName: showPreview ? "rectangle.righthalf.filled" : "rectangle.righthalf.inset.filled")
                        }
                        .help("Toggle Preview (\u{2325}P)")
                        Toggle(isOn: Binding(
                            get: { syncScroll },
                            set: { syncScroll = $0 }
                        )) {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                        .toggleStyle(.button)
                        .help("Sync Scroll")
                        .disabled(!showPreview)
                    }
                }
            }
        }
    }
}
