import SwiftUI
import AppKit
import TinyKit

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
            }

            CommandGroup(after: .newItem) {
                OpenFolderButton()

                Divider()

                Button("Save") {
                    activeState?.save()
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Save As\u{2026}") {
                    activeState?.saveAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
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
            .welcomeSheet(
                isPresented: $showWelcome,
                appName: "TinyMark",
                subtitle: "A minimal Markdown editor",
                features: [
                    ("folder", "Open a Folder", "Browse and edit Markdown files from the sidebar."),
                    ("rectangle.split.2x1", "Write and Preview", "Side-by-side editor with live preview."),
                    ("bolt.fill", "Auto-Save", "Changes saved automatically as you type."),
                ],
                onOpen: { state.openFolder() },
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

/// Standalone button so @FocusedValue resolves reliably in menu context
struct OpenFolderButton: View {
    @FocusedValue(\.appState) private var state

    var body: some View {
        Button("Open Folder\u{2026}") {
            state?.openFolder()
        }
        .keyboardShortcut("o", modifiers: .command)
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
