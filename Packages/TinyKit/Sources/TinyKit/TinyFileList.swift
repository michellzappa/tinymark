import SwiftUI

public struct TinyFileList: View {
    @Bindable public var state: FileState
    @State private var renamingFile: URL?
    @State private var renameText = ""
    @State private var renameExtension = ""
    private let favorites = FavoriteFolders.shared

    public init(state: FileState) {
        self.state = state
    }

    // MARK: - Icon helper

    public static func fileIcon(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "svg":            return "photo"
        case "md", "markdown": return "doc.text"
        case "txt", "text":    return "doc.plaintext"
        case "json":           return "curlybraces"
        case "yaml", "yml":    return "list.bullet.indent"
        default:               return "doc"
        }
    }

    private static let iconWidth: CGFloat = 16

    // MARK: - File size formatting

    public static func fileSize(for url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else { return nil }
        if size < 1_000 { return "\(size) B" }
        if size < 1_000_000 { return String(format: "%.1f KB", Double(size) / 1_000) }
        return String(format: "%.1f MB", Double(size) / 1_000_000)
    }

    public var body: some View {
        List(selection: Binding(
            get: { state.selectedFile },
            set: { url in
                if let url { state.selectFile(url) }
            }
        )) {
            // Favorites section
            if !favorites.folders.isEmpty {
                Section("Favorites") {
                    ForEach(favorites.folders, id: \.self) { folder in
                        Button {
                            state.setFolder(folder)
                        } label: {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .frame(width: Self.iconWidth)
                                    .foregroundStyle(.orange)
                                Text(folder.lastPathComponent)
                                    .lineLimit(1)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([folder])
                            }
                            Divider()
                            Button("Remove from Favorites") {
                                favorites.remove(folder)
                            }
                        }
                    }
                }
            }

            // Current folder contents
            if state.folderURL != nil {
                ForEach(state.directories, id: \.self) { dir in
                    Button {
                        state.setFolder(dir, isRoot: false)
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                                .frame(width: Self.iconWidth)
                                .foregroundStyle(.secondary)
                            Text(dir.lastPathComponent)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Open in Sidebar") {
                            state.setFolder(dir, isRoot: false)
                        }
                        Divider()
                        if favorites.contains(dir) {
                            Button("Remove from Favorites") {
                                favorites.remove(dir)
                            }
                        } else {
                            Button("Add to Favorites") {
                                favorites.add(dir)
                            }
                        }
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([dir])
                        }
                    }
                }

                ForEach(state.files, id: \.self) { file in
                    fileRow(file)
                        .tag(file)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180)
        .contextMenu {
            Button("New File") { state.newFile() }
            Button("New Folder") { state.newFolder() }
            if let folder = state.folderURL {
                Divider()
                if favorites.contains(folder) {
                    Button("Remove Folder from Favorites") {
                        favorites.remove(folder)
                    }
                } else {
                    Button("Add Folder to Favorites") {
                        favorites.add(folder)
                    }
                }
            }
        }
        .onKeyPress(.return, action: {
            guard renamingFile == nil, let file = state.selectedFile else { return .ignored }
            beginRename(file)
            return .handled
        })
        .background {
            Button("") {
                if let file = state.selectedFile { state.deleteFile(file) }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .hidden()
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let folder = state.folderURL {
                HStack(spacing: 6) {
                    Button {
                        state.goUpDirectory()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .disabled(!state.canGoUp)
                    .opacity(state.canGoUp ? 1 : 0.3)
                    .help("Go to parent folder")

                    Text(folder.lastPathComponent)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        favorites.toggle(folder)
                    } label: {
                        Image(systemName: favorites.contains(folder) ? "star.fill" : "star")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(favorites.contains(folder) ? .orange : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(favorites.contains(folder) ? "Remove from Favorites" : "Add to Favorites")

                    Button {
                        state.newFile()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .help("New File")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.bar)
            }
        }
        .overlay {
            if state.folderURL == nil {
                ContentUnavailableView {
                    Label("No Folder Open", systemImage: "folder")
                } description: {
                    Text("Open a folder to get started")
                } actions: {
                    Button("Open Folder\u{2026}") {
                        state.openFolder()
                    }
                }
            } else if state.files.isEmpty && state.directories.isEmpty {
                ContentUnavailableView {
                    Label("No Files", systemImage: "doc.text")
                } description: {
                    Text("No supported files in this folder")
                } actions: {
                    if state.canGoUp {
                        Button("Go Back") { state.goUpDirectory() }
                    }
                    Button("Open Folder\u{2026}") { state.openFolder() }
                }
            }
        }
    }

    // MARK: - File row

    @ViewBuilder
    private func fileRow(_ file: URL) -> some View {
        let icon = Self.fileIcon(for: file)
        if renamingFile == file {
            HStack {
                Image(systemName: icon)
                    .frame(width: Self.iconWidth)
                    .foregroundStyle(.secondary)
                TextField("Filename", text: $renameText, onCommit: {
                    commitRename(file)
                })
                .textFieldStyle(.plain)
                if !renameExtension.isEmpty {
                    Text(".\(renameExtension)")
                        .foregroundStyle(.tertiary)
                }
            }
            .onExitCommand { renamingFile = nil }
        } else {
            HStack {
                Image(systemName: icon)
                    .frame(width: Self.iconWidth)
                    .foregroundStyle(.secondary)
                Text(file.lastPathComponent)
                    .lineLimit(1)
                Spacer()
                if file == state.selectedFile && state.isDirty {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                } else if let size = Self.fileSize(for: file) {
                    Text(size)
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                }
            }
            .contextMenu {
                Button("New File") { state.newFile() }
                Button("New Folder") { state.newFolder() }
                Divider()
                Button("Rename\u{2026}") { beginRename(file) }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                }
                Divider()
                Button("Move to Trash", role: .destructive) {
                    state.deleteFile(file)
                }
            }
        }
    }

    // MARK: - Rename helpers

    private func beginRename(_ file: URL) {
        let ext = file.pathExtension
        let stem = file.deletingPathExtension().lastPathComponent
        renameText = stem
        renameExtension = ext
        renamingFile = file
    }

    private func commitRename(_ file: URL) {
        let stem = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stem.isEmpty else { renamingFile = nil; return }
        let newName = renameExtension.isEmpty ? stem : "\(stem).\(renameExtension)"
        if newName != file.lastPathComponent {
            state.renameFile(file, to: newName)
        }
        renamingFile = nil
    }
}
