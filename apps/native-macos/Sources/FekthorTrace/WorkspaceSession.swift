import AppKit
import CoreServices
import FekthorKit
import SwiftUI
import UniformTypeIdentifiers

/// A workspace the user opened before: enough to reopen it from the home
/// screen. The folder bookmark restores sandboxed access across relaunches;
/// the plain path is the human-readable fallback.
struct RecentWorkspace: Codable, Equatable, Identifiable {
    var name: String
    var path: String
    var bookmark: Data?
    var workfilePath: String?
    var id: String { path }
}

/// The workspace mode's session: opens an icon folder (directly, through a
/// `.fekthor` workfile's folder reference, or from the recents list), holds
/// the immutable `Workspace` snapshot, watches the folder with FSEvents
/// (debounced rescans, diff-driven updates) and wraps every engine file
/// operation with a rescan and a readable status.
@MainActor
final class WorkspaceSession: ObservableObject {
    @Published private(set) var workspace: Workspace?
    @Published var status = ""
    /// Non-nil presents a user-facing alert (op failures, stale bookmarks).
    @Published var errorMessage: String?
    @Published private(set) var recents: [RecentWorkspace]

    let thumbnails = ThumbnailStore()

    private var folderURL: URL?
    /// The URL a successful `startAccessingSecurityScopedResource` was made
    /// on — balanced in `closeCurrent()`.
    private var scopedURL: URL?
    private var workfileURL: URL?
    private var watcher: FolderWatcher?
    private var debounce: Task<Void, Never>?
    private var scanGeneration = 0

    private static let recentsKey = "fekthor.recentWorkspaces"
    private static let fekthorType = UTType(filenameExtension: "fekthor") ?? .json

    init() {
        recents = Self.loadRecents()
    }

    var folderName: String { folderURL?.lastPathComponent ?? "Workspace" }

    // MARK: - Opening

    /// Open Workspace…: a folder, or a `.fekthor` whose folder ref resolves.
    @discardableResult
    func openPanel() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [Self.fekthorType]
        panel.message = "Choose an icon folder, or a .fekthor workfile that references one."
        panel.prompt = "Open Workspace"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            return open(folder: url)
        }
        return openWorkfile(url)
    }

    /// New Workspace: pick (or create) the icon folder, then persist a
    /// `.fekthor` workfile next to it — folder path + fresh security-scoped
    /// bookmark — so the workspace reopens with one double-click.
    @discardableResult
    func newWorkspace() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose (or create) the folder that holds this workspace's SVG icons."
        panel.prompt = "Use This Folder"
        guard panel.runModal() == .OK, let folder = panel.url else { return false }
        guard open(folder: folder) else { return false }
        saveWorkfilePanel(for: folder)
        return true
    }

    /// Opens a `.fekthor` as a workspace. Returns true when the workfile WAS
    /// a workspace workfile (folder ref present) — even if resolving failed,
    /// in which case an error/prompt was already shown. Returns false when
    /// the file has no folder ref (caller falls back to the editor).
    @discardableResult
    func openWorkfile(_ url: URL) -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
            let workfile = try? Workfile.decode(data),
            let ref = workfile.folder
        else { return false }

        // Bookmark first: the only way access survives a relaunch.
        if let bookmarkData = ref.bookmark,
            let resolved = resolveBookmark(bookmarkData)
        {
            let access = resolved.url.startAccessingSecurityScopedResource()
            if open(folder: resolved.url, alreadyScoped: access ? resolved.url : nil, workfile: url) {
                if resolved.stale { refreshBookmark(in: url, for: resolved.url) }
                return true
            }
            if access { resolved.url.stopAccessingSecurityScopedResource() }
        }

        // Path fallback (relative paths resolve against the workfile).
        let candidate = URL(
            fileURLWithPath: ref.path, relativeTo: url.deletingLastPathComponent()
        ).standardizedFileURL
        if open(folder: candidate, workfile: url, quiet: true) {
            refreshBookmark(in: url, for: candidate)
            return true
        }

        // Stale bookmark AND unreadable path: re-prompt for access.
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = candidate
        panel.message =
            "Fekthor needs access to this workspace's folder again — select \(ref.path) (or its new location)."
        panel.prompt = "Grant Access"
        guard panel.runModal() == .OK, let picked = panel.url else {
            errorMessage = "The workspace folder could not be opened: \(ref.path)"
            return true
        }
        if open(folder: picked, workfile: url) {
            refreshBookmark(in: url, for: picked)
        }
        return true
    }

    @discardableResult
    func openRecent(_ recent: RecentWorkspace) -> Bool {
        if let data = recent.bookmark, let resolved = resolveBookmark(data) {
            let access = resolved.url.startAccessingSecurityScopedResource()
            let workfile = recent.workfilePath.map { URL(fileURLWithPath: $0) }
            if open(folder: resolved.url, alreadyScoped: access ? resolved.url : nil, workfile: workfile) {
                return true
            }
            if access { resolved.url.stopAccessingSecurityScopedResource() }
        }
        // Plain-path fallback (may work within the same session or for
        // non-sandbox-restricted locations); otherwise re-prompt.
        if open(folder: URL(fileURLWithPath: recent.path), quiet: true) { return true }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: recent.path)
        panel.message = "Fekthor needs access to \(recent.path) again — reselect the folder."
        panel.prompt = "Grant Access"
        guard panel.runModal() == .OK, let picked = panel.url else { return false }
        return open(folder: picked)
    }

    /// Core adoption: scan, take over scoped access, start the watcher and
    /// record the recent. `alreadyScoped` transfers ownership of an access
    /// the caller has already started; `quiet` suppresses the error alert
    /// (used for best-effort fallbacks).
    @discardableResult
    func open(
        folder: URL, alreadyScoped: URL? = nil, workfile: URL? = nil, quiet: Bool = false
    ) -> Bool {
        let scanned: Workspace
        do {
            scanned = try Workspace.scan(folder)
        } catch {
            if !quiet { errorMessage = Self.describe(error) }
            return false
        }
        closeCurrent()
        folderURL = scanned.root
        scopedURL = alreadyScoped
        workfileURL = workfile
        workspace = scanned
        status = summary(of: scanned)
        startWatching()
        rememberRecent(folder: scanned.root, workfile: workfile)
        return true
    }

    func close() {
        closeCurrent()
        workspace = nil
        status = ""
    }

    private func closeCurrent() {
        debounce?.cancel()
        debounce = nil
        watcher?.stop()
        watcher = nil
        if let scopedURL {
            scopedURL.stopAccessingSecurityScopedResource()
        }
        scopedURL = nil
        folderURL = nil
        workfileURL = nil
        scanGeneration += 1
    }

    // MARK: - Workfile persistence

    /// NSSavePanel for the workspace `.fekthor` (folder path + fresh
    /// security-scoped bookmark). Cancelling keeps the workspace open,
    /// just unpersisted.
    private func saveWorkfilePanel(for folder: URL) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.fekthorType]
        panel.directoryURL = folder.deletingLastPathComponent()
        panel.nameFieldStringValue = folder.lastPathComponent + ".fekthor"
        panel.message = "Save the workspace's .fekthor workfile."
        guard panel.runModal() == .OK, let url = panel.url else {
            status = "Workspace opened (no workfile saved — File ▸ Save As can add one later)."
            return
        }
        let workfile = Workfile(
            version: 1,
            folder: .init(path: folder.path, bookmark: makeBookmark(for: folder)))
        do {
            try workfile.encoded().write(to: url)
            workfileURL = url
            status = "Workspace saved as \(url.lastPathComponent)."
            rememberRecent(folder: folder, workfile: url)
        } catch {
            errorMessage = "Could not save the workfile: \(error.localizedDescription)"
        }
    }

    /// Rewrites the workfile's folder ref with a fresh bookmark (best
    /// effort — e.g. after a stale-bookmark resolve or a path-only open).
    private func refreshBookmark(in workfile: URL, for folder: URL) {
        let scoped = workfile.startAccessingSecurityScopedResource()
        defer { if scoped { workfile.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: workfile),
            var decoded = try? Workfile.decode(data),
            let bookmark = makeBookmark(for: folder)
        else { return }
        decoded.folder = .init(path: folder.path, bookmark: bookmark)
        try? decoded.encoded().write(to: workfile)
    }

    // MARK: - Bookmarks

    private func makeBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private func resolveBookmark(_ data: Data) -> (url: URL, stale: Bool)? {
        var stale = false
        guard
            let url = try? URL(
                resolvingBookmarkData: data, options: [.withSecurityScope],
                relativeTo: nil, bookmarkDataIsStale: &stale)
        else { return nil }
        return (url, stale)
    }

    // MARK: - Recents

    private func rememberRecent(folder: URL, workfile: URL?) {
        var entry = RecentWorkspace(
            name: folder.lastPathComponent, path: folder.path,
            bookmark: makeBookmark(for: folder), workfilePath: workfile?.path)
        if entry.workfilePath == nil,
            let existing = recents.first(where: { $0.path == entry.path })
        {
            entry.workfilePath = existing.workfilePath
        }
        var list = recents.filter { $0.path != entry.path }
        list.insert(entry, at: 0)
        if list.count > 8 { list.removeLast(list.count - 8) }
        recents = list
        Self.saveRecents(list)
    }

    private static func loadRecents() -> [RecentWorkspace] {
        guard let data = UserDefaults.standard.data(forKey: recentsKey),
            let list = try? JSONDecoder().decode([RecentWorkspace].self, from: data)
        else { return [] }
        return list
    }

    private static func saveRecents(_ list: [RecentWorkspace]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: recentsKey)
        }
    }

    // MARK: - Watching (FSEvents, debounced, diff-driven)

    private func startWatching() {
        guard let folderURL else { return }
        watcher = FolderWatcher(path: folderURL.path) { [weak self] in
            Task { @MainActor in self?.scheduleRescan() }
        }
    }

    /// Debounce bursts (a git checkout touches hundreds of files) into one
    /// rescan ~300 ms after the last event.
    func scheduleRescan() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            self?.rescanNow(external: true)
        }
    }

    /// Async rescan off the main actor; the diff drives the UI update (and
    /// the status line, for changes made outside the app).
    func rescanNow(external: Bool = false) {
        guard let folderURL, workspace != nil else { return }
        scanGeneration += 1
        let generation = scanGeneration
        let old = workspace
        Task.detached(priority: .utility) {
            let result = Result { try Workspace.scan(folderURL) }
            await MainActor.run { [weak self] in
                guard let self, generation == self.scanGeneration else { return }
                switch result {
                case .success(let new):
                    guard let old, old != new else {
                        if old == nil { self.workspace = new }
                        return
                    }
                    let diff = Workspace.diff(old: old, new: new)
                    self.workspace = new
                    if external, !diff.isEmpty {
                        self.status = Self.describe(diff: diff)
                    }
                case .failure:
                    self.status = "The workspace folder is no longer readable."
                }
            }
        }
    }

    private static func describe(diff: WorkspaceDiff) -> String {
        var parts: [String] = []
        if !diff.added.isEmpty { parts.append("\(diff.added.count) added") }
        if !diff.removed.isEmpty { parts.append("\(diff.removed.count) removed") }
        if !diff.modified.isEmpty { parts.append("\(diff.modified.count) changed") }
        return "Folder changed on disk: " + parts.joined(separator: ", ") + "."
    }

    private func summary(of ws: Workspace) -> String {
        let cats = ws.categories.count
        return "\(ws.entries.count) icons · \(cats) \(cats == 1 ? "category" : "categories")"
    }

    // MARK: - File operations (engine op + rescan + status)

    func rename(_ entry: IconEntry, to newName: String) {
        perform("Renamed \(entry.name) to \(newName).") { try $0.rename(entry, to: newName) }
    }

    func move(_ entry: IconEntry, toCategory category: String) {
        let destination = category.isEmpty ? "the workspace root" : category
        perform("Moved \(entry.name) to \(destination).") {
            try $0.move(entry, toCategory: category)
        }
    }

    func newCategory(_ name: String) {
        perform("Created category \(name).") { try $0.newCategory(name) }
    }

    func delete(_ entry: IconEntry) {
        perform("Moved \(entry.fileName) to the Trash.") { try $0.delete(entry) }
    }

    func duplicate(_ entry: IconEntry) {
        perform("Duplicated \(entry.name).") { try $0.duplicate(entry) }
    }

    /// Copies an external SVG into the workspace under a collision-free name.
    func importSVG(from url: URL, toCategory category: String) {
        guard let ws = workspace else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let folder =
                category.isEmpty ? ws.root : ws.root.appendingPathComponent(category)
            try FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true)
            let base = url.deletingPathExtension().lastPathComponent
            var stem = base
            var counter = 2
            while FileManager.default.fileExists(
                atPath: folder.appendingPathComponent(stem + ".svg").path)
            {
                stem = "\(base) \(counter)"
                counter += 1
            }
            try FileManager.default.copyItem(
                at: url, to: folder.appendingPathComponent(stem + ".svg"))
            status =
                "Imported \(stem).svg" + (category.isEmpty ? "." : " into \(category).")
        } catch {
            errorMessage = Self.describe(error)
        }
        rescanNow()
    }

    private func perform(_ successMessage: String, _ op: (Workspace) throws -> Void) {
        guard let ws = workspace else { return }
        do {
            try op(ws)
            status = successMessage
        } catch {
            errorMessage = Self.describe(error)
        }
        rescanNow()
    }

    /// Typed engine errors as user-readable sentences.
    static func describe(_ error: Error) -> String {
        guard let e = error as? WorkspaceError else { return error.localizedDescription }
        switch e {
        case .notADirectory(let path):
            return "\(path) is not a folder that can be opened as a workspace."
        case .fileNotFound(let path):
            return
                "\((path as NSString).lastPathComponent) has moved or vanished on disk — the workspace was rescanned."
        case .invalidName(let name):
            return "“\(name)” is not a usable name (it cannot be empty, hidden, or contain slashes)."
        case .targetExists(let path):
            return "\((path as NSString).lastPathComponent) already exists — nothing was overwritten."
        case .categoryExists(let path):
            return "A category named \((path as NSString).lastPathComponent) already exists."
        case .trashUnavailable(let path):
            return
                "The Trash is unavailable for \((path as NSString).lastPathComponent); nothing was deleted."
        }
    }
}

// MARK: - FSEvents watcher

/// A recursive FSEvents stream on one folder. Events are delivered on a
/// private queue; the handler hops to whatever context it needs. FSEvents
/// (unlike a DispatchSource on the root vnode) also fires for changes
/// inside category subfolders.
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "fekthor.workspace.fsevents", qos: .utility)
    private let handler: @Sendable () -> Void

    init?(path: String, handler: @escaping @Sendable () -> Void) {
        self.handler = handler
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue().handler()
        }
        guard
            let stream = FSEventStreamCreate(
                kCFAllocatorDefault, callback, &context, [path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.2,
                FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone))
        else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}
