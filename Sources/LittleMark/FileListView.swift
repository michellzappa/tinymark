import SwiftUI

struct FileListView: View {
    @Bindable var state: AppState
    @State private var renamingFile: URL?
    @State private var renameText = ""

    var body: some View {
        List(selection: Binding(
            get: { state.selectedFile },
            set: { url in
                if let url { state.selectFile(url) }
            }
        )) {
            if state.folderURL != nil {
                ForEach(state.directories, id: \.self) { dir in
                    Button {
                        state.setFolder(dir)
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            Text(dir.lastPathComponent)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }

                ForEach(state.files, id: \.self) { file in
                    fileRow(file)
                        .tag(file)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180)
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
                    .help("Go to parent folder")

                    Text(folder.lastPathComponent)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        state.newFile()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .help("New File (⌘N)")
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
                }
            }
        }
    }

    @ViewBuilder
    private func fileRow(_ file: URL) -> some View {
        if renamingFile == file {
            TextField("Filename", text: $renameText, onCommit: {
                commitRename(file)
            })
            .textFieldStyle(.plain)
            .onExitCommand { renamingFile = nil }
        } else {
            HStack {
                Image(systemName: file.pathExtension.lowercased() == "svg" ? "photo" : "doc.text")
                    .foregroundStyle(.secondary)
                Text(file.lastPathComponent)
                    .lineLimit(1)
                if file == state.selectedFile && state.isDirty {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                }
            }
            .contextMenu {
                Button("New File") {
                    state.newFile()
                }
                Divider()
                Button("Rename\u{2026}") {
                    renameText = file.lastPathComponent
                    renamingFile = file
                }
                Button("Move to Trash", role: .destructive) {
                    state.deleteFile(file)
                }
            }
        }
    }

    private func commitRename(_ file: URL) {
        let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newName.isEmpty && newName != file.lastPathComponent {
            state.renameFile(file, to: newName)
        }
        renamingFile = nil
    }
}
