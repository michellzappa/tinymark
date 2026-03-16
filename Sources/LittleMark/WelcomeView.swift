import SwiftUI

struct WelcomeView: View {
    var onOpenFolder: () -> Void
    var onDismiss: () -> Void

    private let features: [(icon: String, title: String, description: String)] = [
        ("folder", "Open a Folder", "Browse and edit Markdown files from the sidebar."),
        ("rectangle.split.2x1", "Write and Preview", "Side-by-side editor with live preview."),
        ("bolt.fill", "Auto-Save", "Changes saved automatically as you type."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon + title
            VStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)

                Text("Welcome to Little Mark")
                    .font(.system(size: 28, weight: .bold))

                Text("A minimal Markdown editor")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 36)

            // Feature list
            VStack(alignment: .leading, spacing: 24) {
                ForEach(features, id: \.title) { feature in
                    HStack(spacing: 14) {
                        Image(systemName: feature.icon)
                            .font(.system(size: 22))
                            .foregroundColor(.accentColor)
                            .frame(width: 32, alignment: .center)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title)
                                .font(.system(size: 13, weight: .semibold))
                            Text(feature.description)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.horizontal, 40)

            Spacer()

            // Actions
            VStack(spacing: 10) {
                Button(action: onOpenFolder) {
                    Text("Open a Folder")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)

                Button(action: onDismiss) {
                    Text("Start Empty")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 60)
            .padding(.bottom, 28)
        }
        .frame(width: 440, height: 480)
    }
}

// MARK: - First-launch check

enum WelcomeState {
    private static let key = "hasLaunchedBefore"

    static var isFirstLaunch: Bool {
        !UserDefaults.standard.bool(forKey: key)
    }

    static func markLaunched() {
        UserDefaults.standard.set(true, forKey: key)
    }
}
