import SwiftUI

public struct QuickOpenView: View {
    @Bindable public var state: FileState
    @Binding public var isPresented: Bool
    @State private var query = ""
    @FocusState private var isFocused: Bool

    public init(state: FileState, isPresented: Binding<Bool>) {
        self.state = state
        self._isPresented = isPresented
    }

    private var filtered: [URL] {
        if query.isEmpty { return state.files }
        let q = query.lowercased()
        return state.files.filter { $0.lastPathComponent.lowercased().contains(q) }
    }

    public var body: some View {
        VStack(spacing: 0) {
            TextField("Open file\u{2026}", text: $query)
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
                    Image(systemName: TinyFileList.fileIcon(for: file))
                        .frame(width: 16)
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
