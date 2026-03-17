import Foundation
import SwiftUI
import Markdown

@Observable
final class AppState {
    var folderURL: URL?
    /// The top-level folder the user opened — navigation is clamped to this.
    var rootFolderURL: URL?
    var directories: [URL] = []
    var files: [URL] = []
    var selectedFile: URL?
    var content: String = "" {
        didSet {
            scheduleAutoSave()
            scheduleDirtyCheck()
        }
    }
    var savedContent: String = "" {
        didSet { scheduleDirtyCheck() }
    }

    /// Debounced dirty flag — avoids sidebar re-render on every keystroke
    private(set) var isDirty: Bool = false
    private var dirtyCheckTask: DispatchWorkItem?

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

    var isSVGFile: Bool {
        selectedFile?.pathExtension.lowercased() == "svg"
    }

    private static let markdownExtensions = Set(["md", "markdown"])

    var isMarkdownFile: Bool {
        guard let ext = selectedFile?.pathExtension.lowercased() else { return false }
        return Self.markdownExtensions.contains(ext)
    }

    var renderedHTML: String {
        if isSVGFile {
            return "<div style=\"display:flex;justify-content:center;padding:20px\">\(content)</div>"
        }

        guard isMarkdownFile else {
            // Plain text preview — show as preformatted text
            let escaped = content
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            return "<pre style=\"white-space:pre-wrap;word-wrap:break-word;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:13px;line-height:1.5;\">\(escaped)</pre>"
        }

        let (frontmatter, body) = Self.extractFrontmatter(content)
        let document = Document(parsing: body)
        var html = HTMLFormatter.format(document)

        if let fm = frontmatter {
            html = Self.renderFrontmatterTable(fm) + html
        }

        return html
    }

    // MARK: - Frontmatter

    /// Extracts YAML frontmatter (between --- delimiters) and returns (frontmatter pairs, remaining body)
    private static func extractFrontmatter(_ text: String) -> ([(String, String)]?, String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("---") else { return (nil, text) }

        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return (nil, text) }

        // Find closing ---
        var endIndex: Int?
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                endIndex = i
                break
            }
        }

        guard let end = endIndex, end > 1 else { return (nil, text) }

        // Parse simple key: value pairs
        var pairs: [(String, String)] = []
        for i in 1..<end {
            let line = lines[i]
            guard let colonRange = line.range(of: ":") else { continue }
            let key = String(line[line.startIndex..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let value = String(line[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty {
                pairs.append((key, value))
            }
        }

        let body = lines[(end + 1)...].joined(separator: "\n")
        return (pairs.isEmpty ? nil : pairs, body)
    }

    private static func renderFrontmatterTable(_ pairs: [(String, String)]) -> String {
        var html = "<table class=\"frontmatter\"><tbody>"
        for (key, value) in pairs {
            let escapedKey = key.replacingOccurrences(of: "<", with: "&lt;")
            let escapedValue = value.replacingOccurrences(of: "<", with: "&lt;")
            html += "<tr><td class=\"fm-key\">\(escapedKey)</td><td>\(escapedValue)</td></tr>"
        }
        html += "</tbody></table>"
        return html
    }

    // MARK: - Auto-save

    private var autoSaveTask: DispatchWorkItem?

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        guard selectedFile != nil else { return }
        let task = DispatchWorkItem { [weak self] in
            guard let self, self.isDirty, let url = self.selectedFile else { return }
            self.writeFile(to: url)
        }
        autoSaveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: task)
    }

    // MARK: - Bookmark persistence

    private static let bookmarkKey = "lastFolderBookmark"

    func restoreLastFolder() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &isStale) else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        if isStale { saveBookmark(for: url) }
        folderURL = url
        rootFolderURL = url
        refreshFiles()
        if let first = files.first {
            selectFile(first)
        }
    }

    private func saveBookmark(for url: URL) {
        if let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        }
    }

    // MARK: - Folder

    func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setFolder(url)
    }

    func setFolder(_ url: URL, isRoot: Bool = true) {
        folderURL = url
        if isRoot { rootFolderURL = url }
        saveBookmark(for: url)
        refreshFiles()
        if let first = files.first {
            selectFile(first)
        }
    }

    var canGoUp: Bool {
        guard let folder = folderURL, let root = rootFolderURL else { return false }
        return folder.standardizedFileURL != root.standardizedFileURL
    }

    func goUpDirectory() {
        guard canGoUp, let folder = folderURL else { return }
        let parent = folder.deletingLastPathComponent()
        guard parent.path != folder.path else { return }
        setFolder(parent, isRoot: false)
    }

    private static let supportedExtensions = Set(["md", "markdown", "svg", "txt", "text", "json", "yaml", "yml", "toml", "xml", "html", "css", "js", "ts", "py", "swift", "sh", "zsh", "bash", "r", "rb", "go", "rs", "c", "h", "cpp", "hpp", "java", "kt", "lua", "sql", "graphql", "env", "ini", "cfg", "conf", "log", "csv", "tsv"])

    func refreshFiles() {
        guard let folder = folderURL else { files = []; directories = []; return }
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []

        // Single pass — partition into files and directories
        var newFiles: [URL] = []
        var newDirs: [URL] = []
        for url in items {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                if !url.lastPathComponent.hasPrefix(".") {
                    newDirs.append(url)
                }
            } else if Self.supportedExtensions.contains(url.pathExtension.lowercased()) {
                newFiles.append(url)
            }
        }

        files = newFiles.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
        directories = newDirs.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    // MARK: - File Selection

    func selectFile(_ url: URL) {
        if isDirty {
            // Auto-save silently when switching files
            if let current = selectedFile {
                writeFile(to: current)
            }
        }
        selectedFile = url
        loadFile(url)
    }

    func loadFile(_ url: URL) {
        content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        savedContent = content
    }

    // MARK: - Save

    func save() {
        guard let url = selectedFile else { saveAs(); return }
        writeFile(to: url)
    }

    func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.nameFieldStringValue = selectedFile?.lastPathComponent ?? "Untitled.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        writeFile(to: url)
        selectedFile = url
        if url.deletingLastPathComponent() == folderURL {
            refreshFiles()
        }
    }

    func newFile() {
        guard let folder = folderURL else {
            // No folder open — prompt with save panel
            saveAs()
            return
        }
        let name = uniqueFileName(in: folder)
        let url = folder.appendingPathComponent(name)
        try? "".write(to: url, atomically: true, encoding: .utf8)
        refreshFiles()
        selectFile(url)
    }

    // MARK: - Delete

    func deleteFile(_ url: URL) {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            if selectedFile == url {
                selectedFile = nil
                content = ""
                savedContent = ""
            }
            refreshFiles()
            // Select next file if available
            if selectedFile == nil, let first = files.first {
                selectFile(first)
            }
        } catch {
            // silently fail
        }
    }

    // MARK: - Rename

    func renameFile(_ url: URL, to newName: String) {
        let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)
        guard !FileManager.default.fileExists(atPath: newURL.path) else { return }
        do {
            try FileManager.default.moveItem(at: url, to: newURL)
            if selectedFile == url {
                selectedFile = newURL
            }
            refreshFiles()
        } catch {
            // silently fail
        }
    }

    // MARK: - Private

    private func writeFile(to url: URL) {
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            savedContent = content
        } catch {
            // Write failed — don't mark as saved
        }
    }

    private func uniqueFileName(in folder: URL) -> String {
        let base = "Untitled"
        let ext = "md"
        var name = "\(base).\(ext)"
        var counter = 1
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) {
            name = "\(base) \(counter).\(ext)"
            counter += 1
        }
        return name
    }
}
