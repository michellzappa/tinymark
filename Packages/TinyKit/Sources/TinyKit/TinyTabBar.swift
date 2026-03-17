import SwiftUI

public struct TinyTabBar: View {
    @Bindable public var state: FileState

    public init(state: FileState) {
        self.state = state
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(state.tabs) { tab in
                    TabItemView(
                        tab: tab,
                        isActive: tab.id == state.selectedFile,
                        onSelect: { state.switchToTab(tab.id) },
                        onClose: { state.closeTab(tab.id) }
                    )
                }
            }
        }
        .frame(height: 30)
        .background(.bar)
    }
}

// MARK: - Tab Item View

private struct TabItemView: View {
    let tab: TabItem
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            // Dirty dot or close button
            ZStack {
                if isHovering {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 14, height: 14)
                } else if tab.isDirty {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                } else if tab.hasExternalChange {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 8))
                        .foregroundStyle(.orange)
                } else {
                    Color.clear.frame(width: 14, height: 14)
                }
            }
            .frame(width: 14, height: 14)

            Text(tab.id.lastPathComponent)
                .font(.system(size: 11))
                .lineLimit(1)
                .foregroundStyle(isActive ? .primary : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { isHovering = $0 }
    }
}
