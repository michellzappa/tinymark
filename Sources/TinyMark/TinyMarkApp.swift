import SwiftUI
import AppKit
import TinyKit
import UniformTypeIdentifiers

// MARK: - FocusedValue key for per-window AppState

struct FocusedAppStateKey: FocusedValueKey {
    typealias Value = AppState
}

extension FocusedValues {
    var appState: AppState? {
        get { self[FocusedAppStateKey.self] }
        set { self[FocusedAppStateKey.self] = newValue }
    }
}

// MARK: - App

@main
struct TinyMarkApp: App {
    @NSApplicationDelegateAdaptor(TinyAppDelegate.self) var appDelegate
    @FocusedValue(\.appState) private var activeState

    var body: some Scene {
        WindowGroup(id: "editor") {
            WindowContentView()
                .frame(minWidth: 800, minHeight: 500)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New File") {
                    activeState?.newFile()
                }
                .keyboardShortcut("n", modifiers: .command)

                NewWindowButton()
            }

            CommandGroup(replacing: .appInfo) {
                Button("About TinyMark") {
                    NSApp.orderFrontStandardAboutPanel()
                }
                Button("Welcome to TinyMark") {
                    NotificationCenter.default.post(name: .showWelcome, object: nil)
                }
                Divider()
                Button("Feedback\u{2026}") {
                    NSWorkspace.shared.open(URL(string: "https://tinysuite.app/support.html")!)
                }
                Button("TinySuite Website") {
                    NSWorkspace.shared.open(URL(string: "https://tinysuite.app")!)
                }
            }

            CommandGroup(replacing: .help) {
                Button("TinyMark on GitHub") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/michellzappa/tinymark")!)
                }
            }

            CommandGroup(after: .newItem) {
                OpenFileButton()

                OpenFolderButton()

                RecentFilesMenu { url in
                    activeState?.selectFile(url)
                }

                Divider()

                Button("Save") {
                    activeState?.save()
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Save As\u{2026}") {
                    activeState?.saveAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

                ExportPDFButton()
                ExportHTMLButton()

                Divider()

                CopyMarkdownButton()
                CopyHTMLButton()
                CopyRichTextButton()
            }

            CommandGroup(replacing: .sidebar) {
                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(name: .toggleSidebar, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
            }
        }

    }
}

/// Each window owns its own AppState
struct WindowContentView: View {
    @State private var state = AppState()
    @State private var showWelcome = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        ContentView(state: state, columnVisibility: $columnVisibility)
            .defaultAppBanner(appName: "TinyMark", associations: [
                FileTypeAssociation(utType: UTType("net.daringfireball.markdown") ?? .plainText, label: ".md files"),
            ])
            .navigationTitle(state.selectedFile?.lastPathComponent ?? "TinyMark")
            .focusedSceneValue(\.appState, state)
            .onAppear {
                // Handle files passed via Finder before the window appeared
                if !TinyAppDelegate.pendingFiles.isEmpty {
                    let files = TinyAppDelegate.pendingFiles
                    TinyAppDelegate.pendingFiles.removeAll()
                    openFiles(files)
                } else if WelcomeState.isFirstLaunch {
                    showWelcome = true
                } else {
                    state.restoreLastFolder()
                }

                // Handle files opened after launch
                TinyAppDelegate.onOpenFiles = { [weak state] urls in
                    guard let state else { return }
                    openFilesInState(urls, state: state)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
                withAnimation {
                    columnVisibility = columnVisibility == .detailOnly ? .automatic : .detailOnly
                }
            }
            .welcomeSheet(
                isPresented: $showWelcome,
                appName: "TinyMark",
                subtitle: "A minimal, fast Markdown editor for macOS.",
                features: [
                    ("folder", "Open a Folder", "Browse and edit Markdown files from the sidebar."),
                    ("rectangle.split.2x1", "Write and Preview", "Side-by-side editor with live preview."),
                    ("bolt.fill", "Auto-Save", "Changes saved automatically as you type."),
                ],
                onOpenFolder: { state.openFolder() },
                onOpenFile: { state.openFile() },
                onDismiss: { state.restoreLastFolder() }
            )
            .background(WindowCloseGuard(state: state))
    }

    private func openFiles(_ urls: [URL]) {
        openFilesInState(urls, state: state)
    }

    private func openFilesInState(_ urls: [URL], state: AppState) {
        guard let url = urls.first else { return }
        let folder = url.deletingLastPathComponent()
        if state.folderURL != folder {
            state.setFolder(folder)
        }
        state.selectFile(url)
        columnVisibility = .detailOnly
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let toggleSidebar = Notification.Name("toggleSidebar")
}

// MARK: - Menu Buttons

/// Standalone button so @FocusedValue resolves reliably in menu context
struct OpenFileButton: View {
    @FocusedValue(\.appState) private var state

    var body: some View {
        Button("Open File\u{2026}") {
            state?.openFile()
        }
        .keyboardShortcut("o", modifiers: .command)
    }
}

struct OpenFolderButton: View {
    @FocusedValue(\.appState) private var state

    var body: some View {
        Button("Open Folder\u{2026}") {
            state?.openFolder()
        }
        .keyboardShortcut("o", modifiers: [.command, .shift])
    }
}

/// Button that uses @Environment to open a new window from the menu
struct NewWindowButton: View {
    @Environment(\.openWindow) var openWindow

    var body: some View {
        Button("New Window") {
            openWindow(id: "editor")
        }
        .keyboardShortcut("n", modifiers: [.command, .shift])
    }
}

// MARK: - Export Buttons

struct ExportPDFButton: View {
    @FocusedValue(\.appState) private var state

    var body: some View {
        Button("Export as PDF\u{2026}") {
            guard let state else { return }
            let name = state.selectedFile?.lastPathComponent ?? "document.md"
            ExportManager.exportPDF(
                html: state.exportHTML,
                baseURL: state.selectedFile?.deletingLastPathComponent(),
                suggestedName: name
            )
        }
        .keyboardShortcut("e", modifiers: [.command, .shift])
        .disabled(state == nil)
    }
}

struct ExportHTMLButton: View {
    @FocusedValue(\.appState) private var state

    var body: some View {
        Button("Export as HTML\u{2026}") {
            guard let state else { return }
            let name = state.selectedFile?.lastPathComponent ?? "document.md"
            ExportManager.exportHTML(html: state.exportHTML, suggestedName: name)
        }
        .disabled(state == nil)
    }
}

struct CopyMarkdownButton: View {
    @FocusedValue(\.appState) private var state

    var body: some View {
        Button("Copy as Markdown") {
            guard let state else { return }
            ExportManager.copyAsPlainText(state.content)
        }
        .keyboardShortcut("c", modifiers: [.command, .shift])
        .disabled(state == nil)
    }
}

struct CopyHTMLButton: View {
    @FocusedValue(\.appState) private var state

    var body: some View {
        Button("Copy as HTML") {
            guard let state else { return }
            ExportManager.copyAsHTMLSource(
                body: state.renderedHTML,
                title: state.selectedFile?.lastPathComponent ?? "document"
            )
        }
        .disabled(state == nil)
    }
}

struct CopyRichTextButton: View {
    @FocusedValue(\.appState) private var state

    var body: some View {
        Button("Copy as Rich Text") {
            guard let state else { return }
            ExportManager.copyAsRichText(body: state.renderedHTML)
        }
        .keyboardShortcut("c", modifiers: [.command, .option])
        .disabled(state == nil)
    }
}
