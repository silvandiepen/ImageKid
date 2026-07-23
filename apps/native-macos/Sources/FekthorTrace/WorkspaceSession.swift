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
    /// The workspace's full `.fekthor` workfile — export profiles, style
    /// tokens, containers, memberships. Held even when the workspace was
    /// opened as a bare folder (settings then live in memory until the
    /// first edit prompts for a workfile location). Mutate ONLY through
    /// `updateSettings`, which persists deterministically on real change.
    @Published private(set) var settings = Workfile(version: 1)

    let thumbnails = ThumbnailStore()
    /// Renders for the gallery's virtual composed cells (never files).
    let composedThumbnails = ComposedThumbnailStore()

    private var folderURL: URL?
    /// The URL a successful `startAccessingSecurityScopedResource` was made
    /// on — balanced in `closeCurrent()`.
    private var scopedURL: URL?
    private var workfileURL: URL?
    private var watcher: FolderWatcher?
    private var debounce: Task<Void, Never>?
    private var scanGeneration = 0
    /// Parsed guide SVG, keyed by entry id + modification date.
    private var guideCache: (key: String, doc: GraphicDocument)?

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
            if open(
                folder: resolved.url, alreadyScoped: access ? resolved.url : nil,
                workfile: url, decodedWorkfile: workfile)
            {
                if resolved.stale { refreshBookmark(in: url, for: resolved.url) }
                return true
            }
            if access { resolved.url.stopAccessingSecurityScopedResource() }
        }

        // Path fallback (relative paths resolve against the workfile).
        let candidate = URL(
            fileURLWithPath: ref.path, relativeTo: url.deletingLastPathComponent()
        ).standardizedFileURL
        if open(folder: candidate, workfile: url, decodedWorkfile: workfile, quiet: true) {
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
        if open(folder: picked, workfile: url, decodedWorkfile: workfile) {
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
        folder: URL, alreadyScoped: URL? = nil, workfile: URL? = nil,
        decodedWorkfile: Workfile? = nil, quiet: Bool = false
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
        settings = decodedWorkfile ?? Self.loadWorkfile(at: workfile) ?? Workfile(version: 1)
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
        settings = Workfile(version: 1)
        guideCache = nil
        scanGeneration += 1
    }

    // MARK: - Workfile persistence

    /// NSSavePanel for the workspace `.fekthor` (folder path + fresh
    /// security-scoped bookmark). Cancelling keeps the workspace open,
    /// just unpersisted.
    private func saveWorkfilePanel(for folder: URL) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.fekthorType]
        // Default INSIDE the folder: that's the one location the folder's
        // own bookmark keeps writable across relaunches.
        panel.directoryURL = folder
        panel.nameFieldStringValue = folder.lastPathComponent + ".fekthor"
        panel.message = "Save the workspace's .fekthor workfile."
        guard panel.runModal() == .OK, let url = panel.url else {
            status = "Workspace opened (no workfile saved — File ▸ Save As can add one later)."
            return
        }
        var workfile = settings
        workfile.folder = .init(path: folder.path, bookmark: makeBookmark(for: folder))
        do {
            try workfile.encoded().write(to: url)
            settings = workfile
            workfileURL = url
            status = "Workspace saved as \(url.lastPathComponent)."
            rememberRecent(folder: folder, workfile: url)
        } catch {
            errorMessage = "Could not save the workfile: \(error.localizedDescription)"
        }
    }

    // MARK: - Workspace settings (export profiles, tokens, containers)

    var exportProfiles: [Workfile.ExportProfile] { settings.exportProfiles ?? [] }
    var styleTokens: [Workfile.StyleToken] { settings.styleTokens ?? [] }
    var containerSlots: [Workfile.ContainerSlot] { settings.containers ?? [] }
    var containerMemberships: [String: [String]] { settings.containerMemberships ?? [:] }

    /// The single mutation path for workspace settings. The edit is applied
    /// to a copy; nothing is written (and nothing is published) unless the
    /// workfile actually changed. When the workspace was opened as a bare
    /// folder, the first real edit prompts for a `.fekthor` location
    /// (defaulted NEXT TO the folder, named after it — the same place
    /// New Workspace puts it).
    func updateSettings(_ edit: (inout Workfile) -> Void) {
        var updated = settings
        edit(&updated)
        Self.normalize(&updated)
        guard updated != settings else { return }
        settings = updated
        persistSettings()
    }

    /// Empty collections collapse to nil so an untouched section never
    /// appears in the JSON (deterministic, diff-friendly files).
    private static func normalize(_ workfile: inout Workfile) {
        if workfile.settings == Workfile.WorkspaceSettings() { workfile.settings = nil }
        if workfile.swatches?.isEmpty == true { workfile.swatches = nil }
        if workfile.exportProfiles?.isEmpty == true { workfile.exportProfiles = nil }
        if workfile.styleTokens?.isEmpty == true { workfile.styleTokens = nil }
        if workfile.containers?.isEmpty == true { workfile.containers = nil }
        if workfile.containerMemberships?.isEmpty == true { workfile.containerMemberships = nil }
        workfile.containerMemberships = workfile.containerMemberships?.compactMapValues {
            $0.isEmpty ? nil : $0
        }
        if workfile.containerMemberships?.isEmpty == true { workfile.containerMemberships = nil }
        // Roles: the default ("icon") is never stored explicitly.
        workfile.entryRoles = workfile.entryRoles?.compactMapValues {
            $0 == Workfile.EntryRole.icon.rawValue ? nil : $0
        }
        if workfile.entryRoles?.isEmpty == true { workfile.entryRoles = nil }
        workfile.partialLinks = workfile.partialLinks?.compactMapValues {
            $0.isEmpty ? nil : $0
        }
        if workfile.partialLinks?.isEmpty == true { workfile.partialLinks = nil }
    }

    private func persistSettings() {
        guard ensureWorkfileURL() else {
            status = "Settings kept for this session only — no workfile was saved."
            return
        }
        guard let url = workfileURL else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try settings.encoded()
            // Deterministic write: skip when the bytes on disk already match.
            if let existing = try? Data(contentsOf: url), existing == data { return }
            try data.write(to: url)
        } catch {
            // A workfile OUTSIDE the workspace folder (e.g. next to it, from
            // an older build) is beyond the folder's security scope after a
            // relaunch. Relocate it inside the folder — which we always have
            // access to while the workspace is open — instead of failing.
            if let relocated = relocateWorkfileInsideFolder() {
                workfileURL = relocated
                if let folderURL { rememberRecent(folder: folderURL, workfile: relocated) }
                status =
                    "Workfile moved into the workspace folder (\(relocated.lastPathComponent)) — the old copy outside it is no longer used."
            } else {
                errorMessage = "Could not save workspace settings: \(error.localizedDescription)"
            }
        }
    }

    /// Writes the current settings to `<folder>/<folder name>.fekthor`.
    /// Returns nil when there is no folder or the write fails too.
    private func relocateWorkfileInsideFolder() -> URL? {
        guard let folderURL else { return nil }
        let inside = folderURL.appendingPathComponent(folderURL.lastPathComponent + ".fekthor")
        guard inside != workfileURL else { return nil }
        settings.folder = .init(path: folderURL.path, bookmark: makeBookmark(for: folderURL))
        guard (try? settings.encoded().write(to: inside)) != nil else { return nil }
        return inside
    }

    /// Bare-folder workspaces get their `.fekthor` on the first settings
    /// edit, written directly INSIDE the folder (folder name + `.fekthor`):
    /// no prompt — the open workspace already grants write access there,
    /// and inside the folder is the one place the sandbox can always reach
    /// again after a relaunch through the folder's own bookmark.
    private func ensureWorkfileURL() -> Bool {
        if workfileURL != nil { return true }
        guard let folderURL else { return false }
        settings.folder = .init(path: folderURL.path, bookmark: makeBookmark(for: folderURL))
        let url = folderURL.appendingPathComponent(folderURL.lastPathComponent + ".fekthor")
        workfileURL = url
        rememberRecent(folder: folderURL, workfile: url)
        return true
    }

    // MARK: - Workspace standards (icon size, grid, drawing defaults)

    /// The stored standards as-is; nil fields mean "use the fallback".
    var workspaceStandards: Workfile.WorkspaceSettings? { settings.settings }

    /// Standards with `.standard` fallbacks applied per field.
    var effectiveStandards: Workfile.WorkspaceSettings {
        let raw = settings.settings
        let std = Workfile.WorkspaceSettings.standard
        return Workfile.WorkspaceSettings(
            iconWidth: raw?.iconWidth ?? std.iconWidth,
            iconHeight: raw?.iconHeight ?? std.iconHeight,
            gridSpacing: raw?.gridSpacing ?? std.gridSpacing,
            gridSubdivisions: raw?.gridSubdivisions ?? std.gridSubdivisions,
            snapToGrid: raw?.snapToGrid ?? std.snapToGrid,
            gridOpacity: raw?.gridOpacity ?? std.gridOpacity,
            defaultStrokeColor: raw?.defaultStrokeColor ?? std.defaultStrokeColor,
            defaultStrokeWidth: raw?.defaultStrokeWidth ?? std.defaultStrokeWidth,
            defaultFill: raw?.defaultFill ?? std.defaultFill)
    }

    /// The snap toggle (⇧⌘'), persisted through the workfile.
    func setSnapToGrid(_ snap: Bool) {
        updateSettings { workfile in
            var s = workfile.settings ?? Workfile.WorkspaceSettings()
            s.snapToGrid = snap
            workfile.settings = s
        }
    }

    // MARK: - Guide icon (drawn dimmed behind every icon in the editor)

    /// A configured guide defaults to SHOWN; the toggle only stores false.
    var showGuide: Bool {
        guard settings.settings?.guideIcon != nil else { return false }
        return settings.settings?.showGuide ?? true
    }

    /// View ▸ Show Guide (⌥⌘G), persisted through the workfile.
    func setShowGuide(_ show: Bool) {
        updateSettings { workfile in
            var s = workfile.settings ?? Workfile.WorkspaceSettings()
            s.showGuide = show
            workfile.settings = s
        }
    }

    /// The workspace entry configured as the guide icon, if it still exists.
    func guideEntry() -> IconEntry? {
        guard let ws = workspace, let id = settings.settings?.guideIcon else { return nil }
        return ws.entries.first { $0.id == id }
    }

    /// The guide's parsed SVG, cached per entry id + modification date so
    /// gallery scrolls and editor publishes never re-read the file; a save
    /// to the guide file rides the FSEvents rescan into a fresh key.
    func guideDocument() -> GraphicDocument? {
        guard let entry = guideEntry() else { return nil }
        let key = entry.id + "|" + entry.modificationDate.timeIntervalSince1970.description
        if let cached = guideCache, cached.key == key { return cached.doc }
        guard let data = try? Data(contentsOf: entry.url),
            let doc = try? SVGReader.read(data)
        else { return nil }
        guideCache = (key, doc)
        return doc
    }

    // MARK: - New icon

    /// Writes a blank icon sized by the workspace standards into `category`
    /// and returns its URL so the caller can open it in the editor
    /// immediately. Collisions surface as the usual error alert.
    func createIcon(named name: String, category: String) -> URL? {
        guard let ws = workspace else { return nil }
        let std = effectiveStandards
        let doc = GraphicDocument.blank(
            width: std.iconWidth ?? 24, height: std.iconHeight ?? 24)
        do {
            let change = try ws.create(name: name, category: category, svg: SVGWriter.write(doc))
            status = "Created \(name).svg" + (category.isEmpty ? "." : " in \(category).")
            rescanNow()
            return change.svg
        } catch {
            errorMessage = Self.describe(error)
            rescanNow()
            return nil
        }
    }

    /// The next free "icon_untitled" / "icon_untitled-2" name in a category.
    func nextFreeIconName(in category: String) -> String {
        let existing = Set(
            (workspace?.entries ?? [])
                .filter { $0.category == category }
                .map { $0.name.lowercased() })
        if !existing.contains("icon_untitled") { return "icon_untitled" }
        var i = 2
        while existing.contains("icon_untitled-\(i)") { i += 1 }
        return "icon_untitled-\(i)"
    }

    // MARK: Containers

    func slot(forContainer name: String) -> Workfile.ContainerSlot? {
        containerSlots.first { $0.container == name }
    }

    func isContainer(_ name: String) -> Bool {
        slot(forContainer: name) != nil
    }

    /// Insert or replace the slot for `slot.container`.
    func setSlot(_ slot: Workfile.ContainerSlot) {
        updateSettings { workfile in
            var slots = workfile.containers ?? []
            if let i = slots.firstIndex(where: { $0.container == slot.container }) {
                slots[i] = slot
            } else {
                slots.append(slot)
                slots.sort { $0.container < $1.container }
            }
            workfile.containers = slots
        }
        status = "Container \(slot.container): slot saved."
    }

    /// Remove a container definition, every membership that references it,
    /// and every partial link pointing at it.
    func removeContainer(named name: String) {
        updateSettings { workfile in
            workfile.containers?.removeAll { $0.container == name }
            workfile.containerMemberships = workfile.containerMemberships?.compactMapValues {
                let kept = $0.filter { $0 != name }
                return kept.isEmpty ? nil : kept
            }
            workfile.partialLinks = workfile.partialLinks?.compactMapValues {
                let kept = $0.filter { $0 != name }
                return kept.isEmpty ? nil : kept
            }
        }
        status = "Container \(name) removed."
    }

    // MARK: Roles (Icon / Container / Partial)

    /// The entry's role; absent or unknown = plain icon (the only role that
    /// exports by default — containers and partials are ingredients).
    func role(of name: String) -> Workfile.EntryRole {
        settings.role(of: name)
    }

    /// Record a role. The default role is stored as absence; leaving the
    /// partial role also drops the entry's container links (they only mean
    /// something for partials).
    func setRole(_ role: Workfile.EntryRole, of name: String) {
        updateSettings { workfile in
            var roles = workfile.entryRoles ?? [:]
            roles[name] = role == .icon ? nil : role.rawValue
            workfile.entryRoles = roles
            if role != .partial {
                workfile.partialLinks?[name] = nil
            }
        }
        status = "\(name): role set to \(role.rawValue)."
    }

    var partialLinks: [String: [String]] { settings.partialLinks ?? [:] }

    /// The containers this partial merges into on export/compose.
    func linkedContainers(of partial: String) -> [String] {
        partialLinks[partial] ?? []
    }

    /// The partials linked to a container (the inverse view, sorted).
    func partials(linkedTo container: String) -> [String] {
        partialLinks.compactMap { $0.value.contains(container) ? $0.key : nil }.sorted()
    }

    func setPartialLink(partial: String, container: String, linked: Bool) {
        updateSettings { workfile in
            var all = workfile.partialLinks ?? [:]
            var list = all[partial] ?? []
            if linked {
                if !list.contains(container) {
                    list.append(container)
                    list.sort()
                }
            } else {
                list.removeAll { $0 == container }
            }
            all[partial] = list.isEmpty ? nil : list
            workfile.partialLinks = all
        }
    }

    func memberships(of iconName: String) -> [String] {
        containerMemberships[iconName] ?? []
    }

    func setMembership(icon: String, container: String, member: Bool) {
        updateSettings { workfile in
            var all = workfile.containerMemberships ?? [:]
            var list = all[icon] ?? []
            if member {
                if !list.contains(container) {
                    list.append(container)
                    list.sort()
                }
            } else {
                list.removeAll { $0 == container }
            }
            all[icon] = list.isEmpty ? nil : list
            workfile.containerMemberships = all
        }
    }

    private static func loadWorkfile(at url: URL?) -> Workfile? {
        guard let url else { return nil }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Workfile.decode(data)
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
        // Keep the in-memory settings in step when this IS the open workfile.
        if workfile == workfileURL {
            settings.folder = decoded.folder
        }
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
