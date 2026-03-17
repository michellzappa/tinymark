import Foundation

/// Manages favorite folders shared across all Tiny* apps via an App Group.
@Observable
public final class FavoriteFolders {
    public static let shared = FavoriteFolders()

    private let defaults: UserDefaults
    private static let key = "favoriteFolderBookmarks"

    public private(set) var folders: [URL] = []

    public init(suiteName: String = "com.tiny.shared") {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
        self.folders = Self.loadFolders(from: defaults)
    }

    // MARK: - Public API

    public func add(_ url: URL) {
        guard !contains(url) else { return }
        folders.append(url)
        saveFolders()
    }

    public func remove(_ url: URL) {
        let standardized = url.standardizedFileURL
        folders.removeAll { $0.standardizedFileURL == standardized }
        saveFolders()
    }

    public func contains(_ url: URL) -> Bool {
        let standardized = url.standardizedFileURL
        return folders.contains { $0.standardizedFileURL == standardized }
    }

    public func toggle(_ url: URL) {
        if contains(url) {
            remove(url)
        } else {
            add(url)
        }
    }

    // MARK: - Persistence

    private static func loadFolders(from defaults: UserDefaults) -> [URL] {
        guard let dataArray = defaults.array(forKey: key) as? [Data] else { return [] }
        return dataArray.compactMap { data in
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                bookmarkDataIsStale: &isStale
            ) else { return nil }
            _ = url.startAccessingSecurityScopedResource()
            return url
        }
    }

    private func saveFolders() {
        let dataArray = folders.compactMap { url in
            try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        defaults.set(dataArray, forKey: Self.key)
    }
}
