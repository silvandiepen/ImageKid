import Foundation

/// Errors thrown by `Workspace` scanning and file operations. All paths are
/// plain filesystem paths for stable Equatable comparison in tests.
public enum WorkspaceError: Error, Equatable, Sendable {
    /// The scanned URL does not exist or is not a directory.
    case notADirectory(String)
    /// The entry's file vanished between scan and operation.
    case fileNotFound(String)
    /// The requested name is empty, hidden, or contains path separators.
    case invalidName(String)
    /// The operation would overwrite an existing file — always refused.
    case targetExists(String)
    /// `newCategory` target folder already exists.
    case categoryExists(String)
    /// The platform trash was unavailable for this file; nothing was deleted.
    case trashUnavailable(String)
}

/// One icon file discovered by a scan. Identity (`id`) is the stable
/// `category/name` pair, so rescans of the same tree produce matching ids
/// while `fileSize`/`modificationDate` reveal content changes.
public struct IconEntry: Equatable, Hashable, Sendable, Identifiable {
    /// Filename stem, without the `.svg` extension.
    public let name: String
    /// Owning subfolder name; `""` for SVGs directly in the workspace root.
    public let category: String
    /// Absolute file URL of the `.svg`.
    public let url: URL
    /// File size in bytes at scan time.
    public let fileSize: Int
    /// Content modification date at scan time.
    public let modificationDate: Date

    /// Stable identity across rescans: `"category/name"` (or just `name`
    /// for uncategorized entries).
    public var id: String { category.isEmpty ? name : category + "/" + name }
    /// Filename on disk, e.g. `icon_add.svg`.
    public var fileName: String { name + ".svg" }

    public init(name: String, category: String, url: URL, fileSize: Int, modificationDate: Date) {
        self.name = name
        self.category = category
        self.url = url
        self.fileSize = fileSize
        self.modificationDate = modificationDate
    }
}

/// Added/removed/modified sets between two scans of the same folder, keyed
/// by `IconEntry.id`. `modified` carries the NEW entry versions.
public struct WorkspaceDiff: Equatable, Sendable {
    public let added: [IconEntry]
    public let removed: [IconEntry]
    public let modified: [IconEntry]
    public var isEmpty: Bool { added.isEmpty && removed.isEmpty && modified.isEmpty }

    public init(added: [IconEntry], removed: [IconEntry], modified: [IconEntry]) {
        self.added = added
        self.removed = removed
        self.modified = modified
    }
}

/// Result of a file operation: the new `.svg` location plus the co-managed
/// metadata JSON location, when one was created/renamed/trashed alongside.
public struct FileChange: Equatable, Sendable {
    public let svg: URL
    public let meta: URL?

    public init(svg: URL, meta: URL?) {
        self.svg = svg
        self.meta = meta
    }
}

/// An immutable snapshot of an icon-set folder in the open-icon layout:
/// categories are first-level subfolders, icons are `.svg` files, and an
/// optional sibling `meta/` directory (next to the scanned folder, i.e.
/// `src/icons` + `src/meta`) holds flat per-icon JSON metadata.
///
/// `scan` is deterministic: categories and entries are sorted
/// case-insensitively (byte-order tiebreak), independent of filesystem
/// enumeration order and locale. File operations act on disk and return
/// what changed; the snapshot itself never mutates — rescan and `diff`
/// to update a UI cheaply.
public struct Workspace: Equatable, Sendable {
    /// The scanned icons folder.
    public let root: URL
    /// Sibling `meta/` directory, when the open-icon layout was detected.
    public let metaFolder: URL?
    /// First-level subfolder names, sorted case-insensitively. Empty
    /// categories are included (so a fresh `newCategory` shows up); the
    /// uncategorized `""` bucket is not listed here.
    public let categories: [String]
    /// All entries, sorted by (category, name) case-insensitively.
    public let entries: [IconEntry]

    // MARK: - Scan

    /// Scans `folder` into a deterministic snapshot. Only `.svg` files are
    /// listed (case-insensitive extension match); hidden files and folders
    /// are skipped; SVGs directly in `folder` land in the `""` category.
    /// Throws `WorkspaceError.notADirectory` if `folder` is not a directory.
    public static func scan(_ folder: URL) throws -> Workspace {
        let fm = FileManager.default
        let root = folder.standardizedFileURL
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            throw WorkspaceError.notADirectory(root.path)
        }

        var categories: [String] = []
        var entries: [IconEntry] = []
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]

        for item in try sortedChildren(of: root, keys: keys) {
            if try item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                categories.append(item.lastPathComponent)
                for sub in try sortedChildren(of: item, keys: keys) {
                    if let entry = try entry(for: sub, category: item.lastPathComponent) {
                        entries.append(entry)
                    }
                }
            } else if let entry = try entry(for: item, category: "") {
                entries.append(entry)
            }
        }

        categories.sort(by: caseInsensitiveLess)
        entries.sort {
            $0.category == $1.category
                ? caseInsensitiveLess($0.name, $1.name)
                : caseInsensitiveLess($0.category, $1.category)
        }
        return Workspace(
            root: root, metaFolder: detectMetaFolder(next: root),
            categories: categories, entries: entries)
    }

    /// Entries in one category (`""` for the uncategorized root bucket),
    /// in scan order.
    public func entries(in category: String) -> [IconEntry] {
        entries.filter { $0.category == category }
    }

    // MARK: - Metadata

    /// Loads the entry's per-icon metadata from the sibling `meta/` folder
    /// (`meta/<fileName>.json`). Returns nil when no meta folder was
    /// detected, the file is absent, or it fails to parse.
    public func metadata(for entry: IconEntry) -> IconMeta? {
        guard let url = metaURL(for: entry.fileName),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(IconMeta.self, from: data)
    }

    // MARK: - File operations

    /// Renames the entry's `.svg` to `newName` (a filename stem, no
    /// extension) within its category, co-renaming the metadata JSON when
    /// present. Refuses to overwrite an existing `.svg` or meta target.
    @discardableResult
    public func rename(_ entry: IconEntry, to newName: String) throws -> FileChange {
        try validate(name: newName)
        let fm = FileManager.default
        guard fm.fileExists(atPath: entry.url.path) else {
            throw WorkspaceError.fileNotFound(entry.url.path)
        }
        let newSVG = entry.url.deletingLastPathComponent()
            .appendingPathComponent(newName + ".svg")
        guard !fm.fileExists(atPath: newSVG.path) else {
            throw WorkspaceError.targetExists(newSVG.path)
        }
        let oldMeta = existingMetaURL(for: entry.fileName)
        let newMeta = oldMeta == nil ? nil : metaURL(for: newName + ".svg")
        if let newMeta, fm.fileExists(atPath: newMeta.path) {
            throw WorkspaceError.targetExists(newMeta.path)
        }
        try fm.moveItem(at: entry.url, to: newSVG)
        if let oldMeta, let newMeta {
            try fm.moveItem(at: oldMeta, to: newMeta)
        }
        return FileChange(svg: newSVG, meta: newMeta)
    }

    /// Moves the entry's `.svg` into `category` (`""` moves it to the
    /// workspace root), creating the category folder if needed. Metadata is
    /// flat and keyed by filename, so it is untouched by a move. Refuses to
    /// overwrite an existing target.
    @discardableResult
    public func move(_ entry: IconEntry, toCategory category: String) throws -> FileChange {
        if !category.isEmpty { try validate(name: category) }
        let fm = FileManager.default
        guard fm.fileExists(atPath: entry.url.path) else {
            throw WorkspaceError.fileNotFound(entry.url.path)
        }
        let folder = category.isEmpty ? root : root.appendingPathComponent(category)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(entry.fileName)
        guard !fm.fileExists(atPath: target.path) else {
            throw WorkspaceError.targetExists(target.path)
        }
        try fm.moveItem(at: entry.url, to: target)
        return FileChange(svg: target, meta: nil)
    }

    /// Writes a brand-new icon SVG into a category (`""` = root), creating
    /// the category folder if needed. Refuses to overwrite (`targetExists`).
    /// Returns the change; callers rescan to pick up the new entry.
    @discardableResult
    public func create(name: String, category: String, svg: String) throws -> FileChange {
        try validate(name: name)
        if !category.isEmpty { try validate(name: category) }
        let fm = FileManager.default
        let folder = category.isEmpty ? root : root.appendingPathComponent(category)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(name + ".svg")
        guard !fm.fileExists(atPath: target.path) else {
            throw WorkspaceError.targetExists(target.path)
        }
        try svg.write(to: target, atomically: true, encoding: .utf8)
        return FileChange(svg: target, meta: nil)
    }

    /// Creates an empty category subfolder. Throws `categoryExists` when a
    /// file or folder of that name is already present.
    @discardableResult
    public func newCategory(_ name: String) throws -> URL {
        try validate(name: name)
        let fm = FileManager.default
        let folder = root.appendingPathComponent(name)
        guard !fm.fileExists(atPath: folder.path) else {
            throw WorkspaceError.categoryExists(folder.path)
        }
        try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        return folder
    }

    /// Moves the entry's `.svg` — and its metadata JSON, when present — to
    /// the system trash. Throws `trashUnavailable` (deleting nothing) when
    /// the platform trash cannot take the file.
    @discardableResult
    public func delete(_ entry: IconEntry) throws -> FileChange {
        let fm = FileManager.default
        guard fm.fileExists(atPath: entry.url.path) else {
            throw WorkspaceError.fileNotFound(entry.url.path)
        }
        var trashedSVG: NSURL?
        do {
            try fm.trashItem(at: entry.url, resultingItemURL: &trashedSVG)
        } catch {
            throw WorkspaceError.trashUnavailable(entry.url.path)
        }
        var trashedMeta: NSURL?
        if let meta = existingMetaURL(for: entry.fileName) {
            try? fm.trashItem(at: meta, resultingItemURL: &trashedMeta)
        }
        return FileChange(
            svg: (trashedSVG as URL?) ?? entry.url, meta: trashedMeta as URL?)
    }

    /// Copies the entry's `.svg` — and its metadata JSON, when present — to
    /// the first free `<name> copy`, `<name> copy 2`, … slot in the same
    /// category. Never overwrites.
    @discardableResult
    public func duplicate(_ entry: IconEntry) throws -> FileChange {
        let fm = FileManager.default
        guard fm.fileExists(atPath: entry.url.path) else {
            throw WorkspaceError.fileNotFound(entry.url.path)
        }
        let folder = entry.url.deletingLastPathComponent()
        var newName = entry.name + " copy"
        var counter = 2
        func taken(_ stem: String) -> Bool {
            if fm.fileExists(atPath: folder.appendingPathComponent(stem + ".svg").path) {
                return true
            }
            if let meta = metaURL(for: stem + ".svg"), fm.fileExists(atPath: meta.path) {
                return true
            }
            return false
        }
        while taken(newName) {
            newName = entry.name + " copy \(counter)"
            counter += 1
        }
        let newSVG = folder.appendingPathComponent(newName + ".svg")
        try fm.copyItem(at: entry.url, to: newSVG)
        var newMeta: URL?
        if let oldMeta = existingMetaURL(for: entry.fileName),
            let target = metaURL(for: newName + ".svg")
        {
            try fm.copyItem(at: oldMeta, to: target)
            newMeta = target
        }
        return FileChange(svg: newSVG, meta: newMeta)
    }

    // MARK: - Diffing

    /// Compares two scans of the same folder by entry `id`: `added` is in
    /// `new` only, `removed` in `old` only, `modified` is present in both
    /// with a different size, modification date, or location (the NEW
    /// version is reported). Output order follows the respective scan.
    public static func diff(old: Workspace, new: Workspace) -> WorkspaceDiff {
        let oldByID = Dictionary(uniqueKeysWithValues: old.entries.map { ($0.id, $0) })
        let newIDs = Set(new.entries.map(\.id))
        var added: [IconEntry] = []
        var modified: [IconEntry] = []
        for entry in new.entries {
            guard let previous = oldByID[entry.id] else {
                added.append(entry)
                continue
            }
            if previous != entry { modified.append(entry) }
        }
        let removed = old.entries.filter { !newIDs.contains($0.id) }
        return WorkspaceDiff(added: added, removed: removed, modified: modified)
    }

    // MARK: - Search

    /// Entries whose name or metadata (title, tags, meta categories)
    /// contains `query`, case- and diacritic-insensitively. An empty (or
    /// whitespace-only) query returns all entries; order follows the scan.
    public func search(_ query: String) -> [IconEntry] {
        let needle = Self.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return entries }
        return entries.filter { entry in
            if Self.fold(entry.name).contains(needle) { return true }
            guard let meta = metadata(for: entry) else { return false }
            return meta.searchTerms.contains { Self.fold($0).contains(needle) }
        }
    }

    // MARK: - Internals

    /// Case- and diacritic-insensitive normalization, locale-independent.
    private static func fold(_ s: String) -> String {
        s.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Deterministic ordering: lowercase comparison with a byte-order
    /// tiebreak, independent of locale and filesystem order.
    private static func caseInsensitiveLess(_ a: String, _ b: String) -> Bool {
        let la = a.lowercased(), lb = b.lowercased()
        return la == lb ? a < b : la < lb
    }

    /// Non-hidden children of `folder`, sorted deterministically by name.
    private static func sortedChildren(of folder: URL, keys: Set<URLResourceKey>) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ).sorted { caseInsensitiveLess($0.lastPathComponent, $1.lastPathComponent) }
    }

    /// Builds an entry for `file` if it is a regular `.svg`; nil otherwise.
    private static func entry(for file: URL, category: String) throws -> IconEntry? {
        guard file.pathExtension.lowercased() == "svg" else { return nil }
        let values = try file.resourceValues(forKeys: [
            .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
        ])
        guard values.isDirectory != true else { return nil }
        return IconEntry(
            name: file.deletingPathExtension().lastPathComponent,
            category: category,
            url: file,
            fileSize: values.fileSize ?? 0,
            modificationDate: values.contentModificationDate ?? .distantPast)
    }

    /// Detects the open-icon layout: a `meta/` directory sitting next to
    /// the scanned folder (e.g. `src/icons` + `src/meta`).
    private static func detectMetaFolder(next root: URL) -> URL? {
        let candidate = root.deletingLastPathComponent().appendingPathComponent("meta")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir),
            isDir.boolValue
        else { return nil }
        return candidate
    }

    /// The metadata URL an icon filename WOULD have (`meta/<fileName>.json`),
    /// whether or not the file exists; nil without a meta folder.
    private func metaURL(for fileName: String) -> URL? {
        metaFolder?.appendingPathComponent(fileName + ".json")
    }

    /// The metadata URL for an icon filename, only if the file exists.
    private func existingMetaURL(for fileName: String) -> URL? {
        guard let url = metaURL(for: fileName),
            FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url
    }

    /// Rejects empty names, hidden names, and anything containing a path
    /// separator or NUL.
    private func validate(name: String) throws {
        if name.isEmpty || name.hasPrefix(".") || name.contains("/")
            || name.contains("\\") || name.contains("\0")
        {
            throw WorkspaceError.invalidName(name)
        }
    }

    private init(root: URL, metaFolder: URL?, categories: [String], entries: [IconEntry]) {
        self.root = root
        self.metaFolder = metaFolder
        self.categories = categories
        self.entries = entries
    }
}
