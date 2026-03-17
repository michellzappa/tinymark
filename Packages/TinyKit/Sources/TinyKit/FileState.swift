import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Tab Item

public struct TabItem: Identifiable, Equatable {
    public var id: URL
    public var content: String
    public var savedContent: String
    public var isDirty: Bool { content != savedContent }
    /// Set when an external change was detected while the tab has unsaved edits
    public var hasExternalChange: Bool = false

    public static func == (lhs: TabItem, rhs: TabItem) -> Bool {
        lhs.id == rhs.id && lhs.content == rhs.content && lhs.savedContent == rhs.savedContent && lhs.hasExternalChange == rhs.hasExternalChange
    }
}

// MARK: - FileState

@Observable
open class FileState {
    public var folderURL: URL?
    /// The top-level folder the user opened — navigation is clamped to this.
    public var rootFolderURL: URL?
    public var directories: [URL] = []
    public var files: [URL] = []
    public var selectedFile: URL?
    public var content: String = "" {
        didSet {
            syncContentToActiveTab()
            scheduleAutoSave()
            scheduleDirtyCheck()
        }
    }
    public var savedContent: String = "" {
        didSet { scheduleDirtyCheck() }
    }

    /// Debounced dirty flag — avoids sidebar re-render on every keystroke
    public private(set) var isDirty: Bool = false
    private var dirtyCheckTask: DispatchWorkItem?

    // MARK: - Tabs

    public private(set) var tabs: [TabItem] = []

    /// Prevents content didSet from syncing back during tab switch
    private var isSwitchingTabs = false

    // MARK: - Configuration

    public let bookmarkKey: String
    public let defaultExtension: String
    public let supportedExtensions: Set<String>

    public init(
        bookmarkKey: String = "lastFolderBookmark",
        defaultExtension: String = "txt",
        supportedExtensions: Set<String> = ["txt", "text"]
    ) {
        self.bookmarkKey = bookmarkKey
        self.defaultExtension = defaultExtension
        self.supportedExtensions = supportedExtensions
    }

    deinit {
        stopFolderWatcher()
        stopAllFileWatchers()
    }

    // MARK: - Tab management

    public func openInTab(_ url: URL) {
        // If already open, just switch to it
        if tabs.contains(where: { $0.id == url }) {
            switchToTab(url)
            return
        }

        // Stash current tab content
        stashActiveTab()

        // Read file from disk
        let fileContent = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let tab = TabItem(id: url, content: fileContent, savedContent: fileContent)
        tabs.append(tab)

        // Start watching this file
        startFileWatcher(for: url)

        // Make it active
        isSwitchingTabs = true
        selectedFile = url
        content = fileContent
        savedContent = fileContent
        isSwitchingTabs = false
    }

    public func switchToTab(_ url: URL) {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == url }) else { return }
        guard url != selectedFile else { return }

        stashActiveTab()

        let tab = tabs[tabIndex]
        isSwitchingTabs = true
        selectedFile = url
        content = tab.content
        savedContent = tab.savedContent
        isSwitchingTabs = false
    }

    public func closeTab(_ url: URL) {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == url }) else { return }

        // Save if dirty
        if tabs[tabIndex].isDirty {
            let tabContent = tabs[tabIndex].content
            try? tabContent.write(to: url, atomically: true, encoding: .utf8)
        }

        stopFileWatcher(for: url)
        tabs.remove(at: tabIndex)

        // If we closed the active tab, switch to a neighbor
        if selectedFile == url {
            if tabs.isEmpty {
                selectedFile = nil
                isSwitchingTabs = true
                content = ""
                savedContent = ""
                isSwitchingTabs = false
            } else {
                let newIndex = min(tabIndex, tabs.count - 1)
                let newTab = tabs[newIndex]
                isSwitchingTabs = true
                selectedFile = newTab.id
                content = newTab.content
                savedContent = newTab.savedContent
                isSwitchingTabs = false
            }
        }
    }

    public func closeActiveTab() {
        guard let url = selectedFile else { return }
        closeTab(url)
    }

    public func saveAllDirtyTabs() {
        stashActiveTab()
        for tab in tabs where tab.isDirty {
            try? tab.content.write(to: tab.id, atomically: true, encoding: .utf8)
        }
    }

    private func stashActiveTab() {
        guard let url = selectedFile,
              let idx = tabs.firstIndex(where: { $0.id == url }) else { return }
        tabs[idx].content = content
        tabs[idx].savedContent = savedContent
    }

    private func syncContentToActiveTab() {
        guard !isSwitchingTabs,
              let url = selectedFile,
              let idx = tabs.firstIndex(where: { $0.id == url }) else { return }
        tabs[idx].content = content
    }

    // MARK: - Dirty check

    private func scheduleDirtyCheck() {
        dirtyCheckTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let dirty = self.content != self.savedContent
            if self.isDirty != dirty {
                self.isDirty = dirty
            }
        }
        dirtyCheckTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
    }

    // MARK: - Auto-save

    private var autoSaveTask: DispatchWorkItem?

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        guard !isSwitchingTabs, selectedFile != nil else { return }
        let task = DispatchWorkItem { [weak self] in
            guard let self, self.isDirty, let url = self.selectedFile else { return }
            self.writeFile(to: url)
        }
        autoSaveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: task)
    }

    // MARK: - Bookmark persistence

    public func restoreLastFolder() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &isStale) else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        if isStale { saveBookmark(for: url) }
        folderURL = url
        rootFolderURL = url
        startFolderWatcher()
        refreshFiles()
        if let first = files.first {
            selectFile(first)
        }
    }

    private func saveBookmark(for url: URL) {
        if let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }
    }

    // MARK: - Folder

    public func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setFolder(url)
    }

    public func setFolder(_ url: URL, isRoot: Bool = true) {
        folderURL = url
        if isRoot { rootFolderURL = url }
        saveBookmark(for: url)
        startFolderWatcher()
        refreshFiles()
        if let first = files.first {
            selectFile(first)
        }
    }

    public var canGoUp: Bool {
        guard let folder = folderURL, let root = rootFolderURL else { return false }
        return folder.standardizedFileURL != root.standardizedFileURL
    }

    public func goUpDirectory() {
        guard canGoUp, let folder = folderURL else { return }
        let parent = folder.deletingLastPathComponent()
        guard parent.path != folder.path else { return }
        setFolder(parent, isRoot: false)
    }

    public func refreshFiles() {
        guard let folder = folderURL else { files = []; directories = []; return }
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []

        var newFiles: [URL] = []
        var newDirs: [URL] = []
        for url in items {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                if !url.lastPathComponent.hasPrefix(".") {
                    newDirs.append(url)
                }
            } else if supportedExtensions.contains(url.pathExtension.lowercased()) {
                newFiles.append(url)
            }
        }

        files = newFiles.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
        directories = newDirs.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    // MARK: - File Selection

    public func selectFile(_ url: URL) {
        openInTab(url)
    }

    public func loadFile(_ url: URL) {
        content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        savedContent = content
    }

    // MARK: - Save

    public func save() {
        guard let url = selectedFile else { saveAs(); return }
        writeFile(to: url)
    }

    public func saveAs() {
        let panel = NSSavePanel()
        if let type = UTType(filenameExtension: defaultExtension) {
            panel.allowedContentTypes = [type]
        }
        panel.nameFieldStringValue = selectedFile?.lastPathComponent ?? "Untitled.\(defaultExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        writeFile(to: url)
        selectedFile = url
        if url.deletingLastPathComponent() == folderURL {
            refreshFiles()
        }
    }

    public func newFile() {
        guard let folder = folderURL else {
            saveAs()
            return
        }
        let name = uniqueFileName(in: folder)
        let url = folder.appendingPathComponent(name)
        try? "".write(to: url, atomically: true, encoding: .utf8)
        refreshFiles()
        selectFile(url)
    }

    public func newFolder() {
        guard let folder = folderURL else { return }
        let base = "Untitled Folder"
        var name = base
        var counter = 1
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) {
            name = "\(base) \(counter)"
            counter += 1
        }
        let url = folder.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        refreshFiles()
    }

    // MARK: - Delete

    public func deleteFile(_ url: URL) {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            // Close tab if open
            if tabs.contains(where: { $0.id == url }) {
                stopFileWatcher(for: url)
                tabs.removeAll { $0.id == url }
                if selectedFile == url {
                    if let next = tabs.first {
                        isSwitchingTabs = true
                        selectedFile = next.id
                        content = next.content
                        savedContent = next.savedContent
                        isSwitchingTabs = false
                    } else {
                        selectedFile = nil
                        isSwitchingTabs = true
                        content = ""
                        savedContent = ""
                        isSwitchingTabs = false
                    }
                }
            }
            refreshFiles()
        } catch {
            // silently fail
        }
    }

    // MARK: - Rename

    public func renameFile(_ url: URL, to newName: String) {
        let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)
        guard !FileManager.default.fileExists(atPath: newURL.path) else { return }
        do {
            try FileManager.default.moveItem(at: url, to: newURL)
            // Update tab identity
            if let idx = tabs.firstIndex(where: { $0.id == url }) {
                stopFileWatcher(for: url)
                tabs[idx].id = newURL
                startFileWatcher(for: newURL)
            }
            if selectedFile == url {
                selectedFile = newURL
            }
            refreshFiles()
        } catch {
            // silently fail
        }
    }

    // MARK: - Write

    private func writeFile(to url: URL) {
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            savedContent = content
            // Sync to tab entry
            if let idx = tabs.firstIndex(where: { $0.id == url }) {
                tabs[idx].savedContent = content
                tabs[idx].hasExternalChange = false
            }
        } catch {
            // Write failed
        }
    }

    private func uniqueFileName(in folder: URL) -> String {
        let base = "Untitled"
        let ext = defaultExtension
        var name = "\(base).\(ext)"
        var counter = 1
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) {
            name = "\(base) \(counter).\(ext)"
            counter += 1
        }
        return name
    }

    // MARK: - Folder Watcher

    private var folderWatcherSource: DispatchSourceFileSystemObject?
    private var folderWatcherFD: Int32 = -1

    private func startFolderWatcher() {
        stopFolderWatcher()
        guard let folder = folderURL else { return }
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        folderWatcherFD = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.refreshFiles()
        }
        source.setCancelHandler { [fd] in close(fd) }
        source.resume()
        folderWatcherSource = source
    }

    private func stopFolderWatcher() {
        folderWatcherSource?.cancel()
        folderWatcherSource = nil
        folderWatcherFD = -1
    }

    // MARK: - Per-file Watchers

    private var fileWatcherSources: [URL: DispatchSourceFileSystemObject] = [:]

    private func startFileWatcher(for url: URL) {
        guard fileWatcherSources[url] == nil else { return }
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.handleFileChanged(url)
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileWatcherSources[url] = source
    }

    private func stopFileWatcher(for url: URL) {
        fileWatcherSources[url]?.cancel()
        fileWatcherSources.removeValue(forKey: url)
    }

    private func stopAllFileWatchers() {
        for source in fileWatcherSources.values { source.cancel() }
        fileWatcherSources.removeAll()
    }

    private func handleFileChanged(_ url: URL) {
        guard let newContent = try? String(contentsOf: url, encoding: .utf8) else { return }
        guard let idx = tabs.firstIndex(where: { $0.id == url }) else { return }

        if tabs[idx].isDirty {
            // User has unsaved edits — don't overwrite, just flag
            tabs[idx].hasExternalChange = true
        } else {
            // Safe to auto-reload
            tabs[idx].content = newContent
            tabs[idx].savedContent = newContent
            tabs[idx].hasExternalChange = false
            if url == selectedFile {
                isSwitchingTabs = true
                content = newContent
                savedContent = newContent
                isSwitchingTabs = false
            }
        }
    }
}
