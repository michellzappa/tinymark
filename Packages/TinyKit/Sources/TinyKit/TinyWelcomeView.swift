import SwiftUI

public struct TinyWelcomeView: View {
    public let appName: String
    public let subtitle: String
    public let features: [(icon: String, title: String, description: String)]
    public let onOpenFolder: () -> Void
    public let onDismiss: () -> Void

    public init(
        appName: String,
        subtitle: String,
        features: [(icon: String, title: String, description: String)],
        onOpenFolder: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.appName = appName
        self.subtitle = subtitle
        self.features = features
        self.onOpenFolder = onOpenFolder
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)

                Text("Welcome to \(appName)")
                    .font(.system(size: 28, weight: .bold))

                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 36)

            VStack(alignment: .leading, spacing: 24) {
                ForEach(features.indices, id: \.self) { i in
                    let feature = features[i]
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

public enum WelcomeState {
    private static let key = "hasLaunchedBefore"

    public static var isFirstLaunch: Bool {
        !UserDefaults.standard.bool(forKey: key)
    }

    public static func markLaunched() {
        UserDefaults.standard.set(true, forKey: key)
    }
}
