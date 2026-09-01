import Foundation

/// A folder the user pointed at, kept across launches. A plain URL loses its write
/// permission when the app quits, so the grant is stored as a security-scoped bookmark
/// and re-opened on the next launch. One instance per remembered folder.
@MainActor
final class SecurityScopedFolder {
    private let defaultsKey: String
    private let defaults: UserDefaults
    private var accessedURL: URL?

    /// The path the folder was sitting at when the user granted it. A bookmark follows
    /// a folder that is renamed, moved or thrown away, so the path is the only thing
    /// that can tell us the folder is no longer where the user thinks it is.
    private(set) var grantedPath: String?

    private var pathKey: String { defaultsKey + ".path" }

    init(defaultsKey: String, defaults: UserDefaults = .standard) {
        self.defaultsKey = defaultsKey
        self.defaults = defaults
    }

    /// Re-opens the remembered folder, or nil when there is none or the grant is gone.
    func restore() -> URL? {
        grantedPath = defaults.string(forKey: pathKey)
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        var isStale = false
        guard
            let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ),
            url.startAccessingSecurityScopedResource()
        else {
            defaults.removeObject(forKey: defaultsKey)
            return nil
        }

        accessedURL = url
        if isStale {
            adopt(url)
        }
        return url
    }

    /// Takes over from any previously remembered folder and writes a fresh bookmark.
    func adopt(_ url: URL) {
        if accessedURL != url {
            accessedURL?.stopAccessingSecurityScopedResource()
            accessedURL = url.startAccessingSecurityScopedResource() ? url : nil
        }

        if let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            defaults.set(data, forKey: defaultsKey)
        }
        grantedPath = url.standardizedFileURL.path
        defaults.set(grantedPath, forKey: pathKey)
    }
}

/// The same thing for a set of folders that grows as the user grants more of them —
/// the folders images were dropped from, which the app has to be pointed at one by one
/// before it may take a file out of them.
@MainActor
final class SecurityScopedFolderSet {
    private let defaultsKey: String
    private let defaults: UserDefaults
    private var accessed: [URL] = []

    init(defaultsKey: String, defaults: UserDefaults = .standard) {
        self.defaultsKey = defaultsKey
        self.defaults = defaults
    }

    /// Re-opens every folder that is still resolvable, and forgets the rest.
    @discardableResult
    func restoreAll() -> [URL] {
        let stored = defaults.array(forKey: defaultsKey) as? [Data] ?? []
        var kept: [Data] = []
        var urls: [URL] = []

        for data in stored {
            var isStale = false
            guard
                let url = try? URL(
                    resolvingBookmarkData: data,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ),
                url.startAccessingSecurityScopedResource()
            else {
                continue
            }
            accessed.append(url)
            urls.append(url)
            kept.append(isStale ? (bookmark(for: url) ?? data) : data)
        }

        defaults.set(kept, forKey: defaultsKey)
        return urls
    }

    func adopt(_ url: URL) {
        if url.startAccessingSecurityScopedResource() {
            accessed.append(url)
        }
        guard let data = bookmark(for: url) else { return }

        var stored = defaults.array(forKey: defaultsKey) as? [Data] ?? []
        stored.removeAll { existing in
            var isStale = false
            let resolved = try? URL(
                resolvingBookmarkData: existing,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return resolved?.standardizedFileURL == url.standardizedFileURL
        }
        stored.append(data)
        defaults.set(stored, forKey: defaultsKey)
    }

    private func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
}
