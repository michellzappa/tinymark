import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Files requested via Finder "Open With" before or after launch
    static var pendingFiles: [URL] = []
    static var onOpenFiles: (([URL]) -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let handler = Self.onOpenFiles {
            handler(urls)
        } else {
            Self.pendingFiles.append(contentsOf: urls)
        }
    }
}

extension Notification.Name {
    static let showWelcome = Notification.Name("showWelcome")
}

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
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
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

    var body: some View {
        ContentView(state: state)
            .focusedSceneValue(\.appState, state)
            .onAppear {
                // Handle files passed via Finder before the window appeared
                if !AppDelegate.pendingFiles.isEmpty {
                    let files = AppDelegate.pendingFiles
                    AppDelegate.pendingFiles.removeAll()
                    openFiles(files)
                } else if WelcomeState.isFirstLaunch {
                    showWelcome = true
                } else {
                    state.restoreLastFolder()
                }

                // Handle files opened after launch
                AppDelegate.onOpenFiles = { [weak state] urls in
                    guard let state else { return }
                    openFilesInState(urls, state: state)
                }
            }
            .sheet(isPresented: $showWelcome) {
                WelcomeView(
                    onOpenFolder: {
                        showWelcome = false
                        WelcomeState.markLaunched()
                        state.openFolder()
                    },
                    onDismiss: {
                        showWelcome = false
                        WelcomeState.markLaunched()
                        state.restoreLastFolder()
                    }
                )
            }
            .background(WindowCloseGuard(state: state))
            .onReceive(NotificationCenter.default.publisher(for: .showWelcome)) { _ in
                showWelcome = true
            }
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
    }
}

/// Hooks into the window delegate to warn about unsaved changes on close
struct WindowCloseGuard: NSViewRepresentable {
    let state: AppState

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.state = state
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.originalDelegate = window.delegate
            window.delegate = context.coordinator
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.state = state
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, NSWindowDelegate {
        var state: AppState?
        weak var originalDelegate: NSWindowDelegate?

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard let state, state.isDirty else { return true }
            // Force save before closing (autosave may not have fired yet)
            state.save()
            return true
        }

        // Forward all other delegate calls to SwiftUI's original delegate
        func windowWillClose(_ notification: Notification) {
            originalDelegate?.windowWillClose?(notification)
        }

        func windowDidBecomeKey(_ notification: Notification) {
            originalDelegate?.windowDidBecomeKey?(notification)
        }

        func windowDidResignKey(_ notification: Notification) {
            originalDelegate?.windowDidResignKey?(notification)
        }
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
