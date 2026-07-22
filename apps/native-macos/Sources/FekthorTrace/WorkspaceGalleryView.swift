import AppKit
import FekthorKit
import SwiftUI
import UniformTypeIdentifiers

/// The workspace gallery: every icon in the managed folder, grouped into
/// collapsible category sections with async thumbnails, search, selection,
/// per-icon context menus and drop-a-PNG-to-trace. Double-click (or the
/// context menu's Open in Editor) routes an entry into the editor.
struct WorkspaceGalleryView: View {
    @ObservedObject var session: WorkspaceSession
    /// For the View ▸ Preview Composed Icons toggle (⌥⌘P).
    @ObservedObject private var menuState = MenuState.shared
    /// Hoisted to ContentView so ⌘N knows the selected icon's category
    /// even while the editor is on top.
    @Binding var selection: String?
    var onOpenEntry: (IconEntry) -> Void
    /// Create a new icon in this category (the workspace's primary action).
    var onNewIcon: (String) -> Void
    /// A raster file was dropped: (file URL, target category).
    var onDropRaster: (URL, String) -> Void
    var onClose: () -> Void

    @State private var query = ""
    /// nil = no active search (show everything).
    @State private var filtered: [IconEntry]? = nil
    @State private var sortMode: SortMode = .name
    @State private var collapsed: Set<String> = []
    @State private var dropTargeted = false

    // Sheet-less alert state for the small text-input flows.
    @State private var renameTarget: IconEntry? = nil
    @State private var renameText = ""
    @State private var deleteTarget: IconEntry? = nil
    @State private var newCategoryShown = false
    @State private var newCategoryText = ""
    /// Move-to-NEW-category flow: asks for the name, then moves.
    @State private var moveTarget: IconEntry? = nil
    @State private var moveCategoryText = ""
    // Workspace panels (also reachable from the Workspace menu).
    @State private var exportShown = false
    @State private var tokensShown = false
    @State private var containerTarget: IconEntry? = nil

    enum SortMode: String, CaseIterable {
        case name = "Name"
        case modified = "Recently Modified"
    }

    private struct SearchInput: Equatable {
        var query: String
        var workspace: Workspace?
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            ZStack {
                gallery
                if dropTargeted { dropOverlay }
            }
            Divider()
            statusBar
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { handleDrop($0) }
        .task(id: SearchInput(query: query, workspace: session.workspace)) {
            await runSearch()
        }
        .background(alertHosts)
        .background(panelHosts)
    }

    // MARK: - Bars

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                onClose()
            } label: {
                Label("Home", systemImage: "chevron.left")
            }
            Text(session.folderName).font(.headline)
            Text(countText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            // The primary action: a new icon in the selected category.
            Button {
                onNewIcon(targetCategory)
            } label: {
                Label("New Icon", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(.fekthorAccent)
            .help("Create a new icon (⌘N)")
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search icons", text: $query)
                    .textFieldStyle(.plain)
                    .frame(width: 200)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            Picker("Sort", selection: $sortMode) {
                ForEach(SortMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .frame(width: 190)
            // Small header actions: icon-only and neutral (never accent).
            Button {
                newCategoryText = ""
                newCategoryShown = true
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .help("New category")
            Button {
                tokensShown = true
            } label: {
                Image(systemName: "paintpalette")
            }
            .help("Workspace style tokens: scan, census, retheme.")
            Button {
                exportShown = true
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .help("Export profiles: run a pipeline over the workspace.")
            Button {
                // Hosted by ContentView so the Workspace menu (⇧⌘,) can
                // open the same sheet from anywhere.
                NotificationCenter.default.post(name: .fekthorWorkspaceSettings, object: nil)
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Workspace settings: icon size, grid, drawing defaults (⇧⌘,).")
        }
        .tint(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(keyboardShortcutHosts)
    }

    /// Gallery keyboard basics as invisible key-equivalent hosts:
    /// Return opens the selected icon, ⌘⌫ (the Finder convention) asks to
    /// trash it.
    private var keyboardShortcutHosts: some View {
        Group {
            Button {
                if let entry = selectedEntry { onOpenEntry(entry) }
            } label: {
                EmptyView()
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(selectedEntry == nil)
            Button {
                if let entry = selectedEntry { deleteTarget = entry }
            } label: {
                EmptyView()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(selectedEntry == nil)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    private var selectedEntry: IconEntry? {
        guard let selection else { return nil }
        return session.workspace?.entries.first { $0.id == selection }
    }

    private var statusBar: some View {
        HStack {
            Text(session.status).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Text("drop a PNG to trace it into this workspace")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var countText: String {
        let total = session.workspace?.entries.count ?? 0
        if let filtered { return "\(filtered.count) of \(total)" }
        return "\(total) icons"
    }

    // MARK: - Gallery body

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 96, maximum: 128), spacing: 14)]
    }

    private var gallery: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6, pinnedViews: [.sectionHeaders]) {
                ForEach(sections, id: \.category) { section in
                    Section {
                        if !collapsed.contains(section.category) {
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(section.entries) { entry in
                                    cell(for: entry)
                                }
                                // Virtual icon-in-container previews (View ▸
                                // Preview Composed Icons) — rendered live,
                                // never written to disk.
                                ForEach(composedSpecs(in: section.category)) { spec in
                                    ComposedIconCell(
                                        spec: spec,
                                        thumbnails: session.thumbnails,
                                        store: session.composedThumbnails)
                                }
                                // Creating an icon is always one click away —
                                // and the obvious first action in an empty
                                // category.
                                if filtered == nil {
                                    NewIconCell {
                                        onNewIcon(section.category)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 14)
                        }
                    } header: {
                        sectionHeader(section.category, count: section.entries.count)
                    }
                }
                if sections.isEmpty {
                    emptyGallery
                }
            }
            .padding(.vertical, 8)
        }
        // Transparent: the window's black-glass backdrop shows through.
        .contentShape(Rectangle())
        .onTapGesture { selection = nil }
    }

    private var emptyGallery: some View {
        VStack(spacing: 12) {
            Image(systemName: filtered != nil ? "magnifyingglass" : "square.grid.3x3")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text(
                filtered != nil
                    ? "No icons match “\(query)”."
                    : "This workspace has no icons yet."
            )
            .foregroundStyle(.secondary)
            if filtered == nil {
                Button {
                    onNewIcon("")
                } label: {
                    Label("Create your first icon", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                Text("…or drop a PNG to trace one, or an SVG to import it.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func sectionHeader(_ category: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Button {
                if collapsed.contains(category) {
                    collapsed.remove(category)
                } else {
                    collapsed.insert(category)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(collapsed.contains(category) ? 0 : 90))
                    Text(category.isEmpty ? "Uncategorized" : category)
                        .font(.subheadline.weight(.semibold))
                    Text("\(count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                onNewIcon(category)
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(
                "New icon in \(category.isEmpty ? "the workspace root" : category)")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        // Material, not an opaque color: pinned headers stay readable while
        // the glass shows through.
        .background(.ultraThinMaterial)
    }

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 16)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
            .background(
                RoundedRectangle(cornerRadius: 16).fill(Color.accentColor.opacity(0.06))
            )
            .overlay(
                Label("Drop a PNG to trace it into this workspace", systemImage: "wand.and.rays")
                    .font(.headline)
                    .padding(10)
                    .background(.regularMaterial, in: Capsule())
            )
            .padding(10)
            .allowsHitTesting(false)
    }

    // MARK: - Cells

    private func cell(for entry: IconEntry) -> some View {
        IconCell(
            entry: entry, thumbnails: session.thumbnails,
            selected: selection == entry.id,
            role: session.role(of: entry.name),
            isContainer: session.isContainer(entry.name),
            membershipCount: session.memberships(of: entry.name).count,
            onSelect: { selection = entry.id },
            onOpen: { onOpenEntry(entry) }
        )
        .contextMenu { contextMenu(for: entry) }
    }

    @ViewBuilder
    private func contextMenu(for entry: IconEntry) -> some View {
        Button("Open in Editor") { onOpenEntry(entry) }
        Divider()
        roleMenu(for: entry)
        Button("Rename…") {
            renameText = entry.name
            renameTarget = entry
        }
        Menu("Move to Category") {
            if !entry.category.isEmpty {
                Button("Uncategorized (root)") { session.move(entry, toCategory: "") }
            }
            ForEach(session.workspace?.categories ?? [], id: \.self) { category in
                if category != entry.category {
                    Button(category) { session.move(entry, toCategory: category) }
                }
            }
            Divider()
            Button("New Category…") {
                moveCategoryText = ""
                moveTarget = entry
            }
        }
        Button("Duplicate") { session.duplicate(entry) }
        Divider()
        Button(
            session.isContainer(entry.name) ? "Edit Container Slot…" : "Use as Container…"
        ) {
            containerTarget = entry
        }
        containersSubmenu(for: entry)
        partialLinkSubmenu(for: entry)
        Divider()
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([entry.url])
        }
        Button("Delete…", role: .destructive) { deleteTarget = entry }
    }

    /// Membership checkboxes: which defined containers this icon is composed
    /// into on export. An icon never lists itself.
    @ViewBuilder
    private func containersSubmenu(for entry: IconEntry) -> some View {
        let names = session.containerSlots.map(\.container).filter { $0 != entry.name }
        if !names.isEmpty {
            Menu("Containers") {
                ForEach(names, id: \.self) { name in
                    Toggle(
                        name,
                        isOn: Binding(
                            get: { session.memberships(of: entry.name).contains(name) },
                            set: { session.setMembership(icon: entry.name, container: name, member: $0) }
                        ))
                }
            }
        }
    }

    /// Role submenu: Icon (default, exports) / Container / Partial. Picking
    /// Container on an entry with no slot yet flows straight into the slot
    /// sheet — a container without a slot cannot compose anything.
    private func roleMenu(for entry: IconEntry) -> some View {
        Menu("Role") {
            Picker("Role", selection: roleBinding(for: entry)) {
                Text("Icon").tag(Workfile.EntryRole.icon)
                Text("Container").tag(Workfile.EntryRole.container)
                Text("Partial").tag(Workfile.EntryRole.partial)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    private func roleBinding(for entry: IconEntry) -> Binding<Workfile.EntryRole> {
        Binding(
            get: { session.role(of: entry.name) },
            set: { role in
                session.setRole(role, of: entry.name)
                if role == .container, session.slot(forContainer: entry.name) == nil {
                    containerTarget = entry
                }
            })
    }

    /// Partials link to the containers they augment; containers report how
    /// many partials merge into them on export/compose.
    @ViewBuilder
    private func partialLinkSubmenu(for entry: IconEntry) -> some View {
        switch session.role(of: entry.name) {
        case .partial:
            let names = session.containerSlots.map(\.container).filter { $0 != entry.name }
            Menu("Link to Containers") {
                if names.isEmpty {
                    Text("No containers defined")
                }
                ForEach(names, id: \.self) { name in
                    Toggle(
                        name,
                        isOn: Binding(
                            get: { session.linkedContainers(of: entry.name).contains(name) },
                            set: {
                                session.setPartialLink(
                                    partial: entry.name, container: name, linked: $0)
                            }
                        ))
                }
            }
        case .container:
            let linked = session.partials(linkedTo: entry.name)
            if !linked.isEmpty {
                Text("\(linked.count) linked partial\(linked.count == 1 ? "" : "s")")
            }
        case .icon:
            EmptyView()
        }
    }

    // MARK: - Composed previews (View ▸ Preview Composed Icons)

    /// One virtual cell: `icon` composed into `container` (merged with its
    /// linked partials), shown under `category`. The id carries the category
    /// because the same composition appears in the container's category AND
    /// in each linked partial's — the render is shared through `renderKey`.
    struct ComposedSpec: Identifiable {
        var icon: IconEntry
        var container: IconEntry
        var partials: [IconEntry]
        var slot: Workfile.ContainerSlot
        var category: String

        var id: String { "composed:\(icon.id)+\(container.id)@\(category)" }
        var title: String { "\(icon.name)-\(container.name)" }

        /// Cache key over every input: member file states (id|mtime|size via
        /// the thumbnail store's key), the slot rect/fit and the link set —
        /// so role/link/slot edits and file changes re-render live.
        @MainActor
        func renderKey(_ thumbnails: ThumbnailStore) -> String {
            let members = ([icon, container] + partials).map { thumbnails.key(for: $0) }
            let slotPart =
                "slot:\(slot.x):\(slot.y):\(slot.width):\(slot.height):\(slot.fit ?? "contain")"
            return (members + [slotPart]).joined(separator: "|")
        }
    }

    /// The composed cells for one category. A composition surfaces in the
    /// container's category (primary home) and in each linked partial's
    /// category. Hidden while searching — search matches real files.
    private func composedSpecs(in category: String) -> [ComposedSpec] {
        guard menuState.previewComposed, filtered == nil, let ws = session.workspace else {
            return []
        }
        var byName: [String: IconEntry] = [:]
        for entry in ws.entries where byName[entry.name] == nil {
            byName[entry.name] = entry
        }
        var out: [ComposedSpec] = []
        for icon in session.containerMemberships.keys.sorted() {
            guard let iconEntry = byName[icon] else { continue }
            for name in Set(session.memberships(of: icon)).sorted() {
                guard let slot = session.slot(forContainer: name),
                    let containerEntry = byName[name]
                else { continue }
                let partialEntries = session.partials(linkedTo: name).compactMap { byName[$0] }
                var categories = Set([containerEntry.category])
                for partial in partialEntries { categories.insert(partial.category) }
                guard categories.contains(category) else { continue }
                out.append(
                    ComposedSpec(
                        icon: iconEntry, container: containerEntry,
                        partials: partialEntries, slot: slot, category: category))
            }
        }
        return out
    }

    // MARK: - Sections / search / sort

    private var sections: [(category: String, entries: [IconEntry])] {
        guard let ws = session.workspace else { return [] }
        let source = filtered ?? ws.entries
        var byCategory: [String: [IconEntry]] = [:]
        for entry in source {
            byCategory[entry.category, default: []].append(entry)
        }
        var out: [(String, [IconEntry])] = []
        if let root = byCategory[""], !root.isEmpty {
            out.append(("", sorted(root)))
        }
        for category in ws.categories {
            let items = byCategory[category] ?? []
            // While searching, hide categories with no hits.
            if filtered != nil && items.isEmpty { continue }
            out.append((category, sorted(items)))
        }
        return out
    }

    private func sorted(_ items: [IconEntry]) -> [IconEntry] {
        switch sortMode {
        case .name:
            return items  // scan order is already name-sorted
        case .modified:
            return items.sorted { $0.modificationDate > $1.modificationDate }
        }
    }

    /// Search runs off-main (metadata files are read lazily per entry) and
    /// only lands if the query is still current.
    private func runSearch() async {
        guard let ws = session.workspace else {
            filtered = nil
            return
        }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            filtered = nil
            return
        }
        try? await Task.sleep(nanoseconds: 150_000_000)
        guard !Task.isCancelled else { return }
        let result = await Task.detached(priority: .userInitiated) { ws.search(q) }.value
        guard !Task.isCancelled else { return }
        filtered = result
    }

    // MARK: - Drop

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in routeDropped(url) }
        }
        return true
    }

    private func routeDropped(_ url: URL) {
        let rasterExtensions: Set<String> = [
            "png", "jpg", "jpeg", "tiff", "tif", "heic", "bmp", "gif", "webp",
        ]
        let ext = url.pathExtension.lowercased()
        if rasterExtensions.contains(ext) {
            onDropRaster(url, targetCategory)
        } else if ext == "svg" {
            session.importSVG(from: url, toCategory: targetCategory)
        } else {
            session.status = "Only PNG-style images (traced) or SVGs (imported) can be dropped here."
        }
    }

    /// Where dropped/traced files land: the selected icon's category, or the
    /// workspace root.
    private var targetCategory: String {
        guard let selection,
            let entry = session.workspace?.entries.first(where: { $0.id == selection })
        else { return "" }
        return entry.category
    }

    // MARK: - Alerts

    /// A hidden host so the main body stays type-checkable.
    private var alertHosts: some View {
        Color.clear
            .alert(
                "Rename Icon",
                isPresented: Binding(
                    get: { renameTarget != nil },
                    set: { if !$0 { renameTarget = nil } })
            ) {
                TextField("Name", text: $renameText)
                Button("Rename") {
                    if let target = renameTarget {
                        session.rename(target, to: renameText.trimmingCharacters(in: .whitespaces))
                    }
                    renameTarget = nil
                }
                Button("Cancel", role: .cancel) { renameTarget = nil }
            } message: {
                Text("The .svg file (and its metadata, when present) is renamed on disk.")
            }
            .alert(
                "New Category",
                isPresented: $newCategoryShown
            ) {
                TextField("Category name", text: $newCategoryText)
                Button("Create") {
                    session.newCategory(newCategoryText.trimmingCharacters(in: .whitespaces))
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Creates a subfolder in the workspace.")
            }
            .alert(
                "Move to New Category",
                isPresented: Binding(
                    get: { moveTarget != nil },
                    set: { if !$0 { moveTarget = nil } })
            ) {
                TextField("Category name", text: $moveCategoryText)
                Button("Move") {
                    if let target = moveTarget {
                        session.move(
                            target,
                            toCategory: moveCategoryText.trimmingCharacters(in: .whitespaces))
                    }
                    moveTarget = nil
                }
                Button("Cancel", role: .cancel) { moveTarget = nil }
            } message: {
                Text("The folder is created and the icon moved into it.")
            }
            .alert(
                "Delete Icon",
                isPresented: Binding(
                    get: { deleteTarget != nil },
                    set: { if !$0 { deleteTarget = nil } })
            ) {
                Button("Move to Trash", role: .destructive) {
                    if let target = deleteTarget { session.delete(target) }
                    deleteTarget = nil
                }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            } message: {
                Text(
                    "“\(deleteTarget?.fileName ?? "")” moves to the Trash (its metadata too, when present)."
                )
            }
            .alert(
                "Workspace",
                isPresented: Binding(
                    get: { session.errorMessage != nil },
                    set: { if !$0 { session.errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) { session.errorMessage = nil }
            } message: {
                Text(session.errorMessage ?? "")
            }
    }

    /// A second hidden host for the workspace panels (sheets + the
    /// Workspace-menu listeners), keeping each modifier chain small enough
    /// for the type checker.
    private var panelHosts: some View {
        Color.clear
            .sheet(isPresented: $exportShown) {
                WorkspaceExportView(session: session, selectedEntryID: selection)
            }
            .sheet(isPresented: $tokensShown) {
                WorkspaceTokensView(session: session)
            }
            .sheet(item: $containerTarget) { entry in
                ContainerSlotSheet(session: session, entry: entry)
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .fekthorWorkspaceExport)
            ) { _ in
                exportShown = true
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .fekthorWorkspaceTokens)
            ) { _ in
                tokensShown = true
            }
    }
}

// MARK: - New-icon ghost cell

/// The trailing "create one here" cell in every category grid: a dashed
/// placeholder matching the icon-cell footprint.
private struct NewIconCell: View {
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13)
                        .fill(Color.accentColor.opacity(hovering ? 0.10 : 0.04))
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundStyle(hovering ? Color.accentColor : Color.secondary)
                }
                .frame(width: 96, height: 96)
                .overlay(
                    RoundedRectangle(cornerRadius: 13)
                        .strokeBorder(
                            hovering ? Color.accentColor : Color(nsColor: .separatorColor),
                            style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                )
                Text("New Icon")
                    .font(.caption)
                    .foregroundStyle(hovering ? Color.accentColor : .secondary)
                    .frame(width: 96)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Create a new icon in this category")
    }
}

// MARK: - One icon cell

private struct IconCell: View {
    let entry: IconEntry
    @ObservedObject var thumbnails: ThumbnailStore
    let selected: Bool
    var role: Workfile.EntryRole = .icon
    var isContainer: Bool = false
    var membershipCount: Int = 0
    var onSelect: () -> Void
    var onOpen: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                // A light (not hard-white) well with a soft dark rim: the
                // near-black corpus icons keep full contrast, and white
                // icons pick up enough of the paper tone + rim to be seen.
                RoundedRectangle(cornerRadius: 13).fill(Color.fekthorWell)
                if let image = thumbnails.image(for: entry) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(10)
                } else if thumbnails.didFail(entry) {
                    Image(systemName: "questionmark.square.dashed")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                } else {
                    ProgressView().controlSize(.small).opacity(0.4)
                }
            }
            .frame(width: 96, height: 96)
            .overlay(alignment: .topTrailing) { badges }
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(rimColor, lineWidth: selected ? 2 : 1)
            )
            Text(entry.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(selected ? Color.accentColor : .primary)
                .frame(width: 96)
        }
        .contentShape(Rectangle())
        .gesture(TapGesture(count: 2).onEnded { onOpen() })
        .simultaneousGesture(TapGesture().onEnded { onSelect() })
        .help(entry.category.isEmpty ? entry.fileName : "\(entry.category)/\(entry.fileName)")
        // Re-request whenever the cache key changes (first appearance or a
        // rescan that saw the file's size/date change).
        .task(id: thumbnails.key(for: entry)) {
            thumbnails.request(entry)
        }
    }

    /// The cell rim: selection wins; otherwise a subtle role tint (orange
    /// box = container, indigo = partial), else a soft dark edge on the
    /// light well.
    private var rimColor: Color {
        if selected { return .accentColor }
        switch role {
        case .container: return Color.accentColor.opacity(0.55)
        case .partial: return Color.indigo.opacity(0.65)
        case .icon:
            return isContainer
                ? Color.accentColor.opacity(0.55) : Color.black.opacity(0.25)
        }
    }

    /// Role / membership badges: a box for containers, a puzzle piece for
    /// partials, a count capsule for icons composed into containers.
    @ViewBuilder
    private var badges: some View {
        HStack(spacing: 3) {
            if role == .partial {
                Image(systemName: "puzzlepiece.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.indigo)
                    .padding(3)
                    .background(.regularMaterial, in: Circle())
                    .help("Partial — merges into its linked containers on export")
            }
            if isContainer || role == .container {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(3)
                    .background(.regularMaterial, in: Circle())
                    .help("Container — icons compose into its slot on export")
            }
            if membershipCount > 0 {
                Text("×\(membershipCount)")
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.regularMaterial, in: Capsule())
                    .help("Composed into \(membershipCount) container(s) on export")
            }
        }
        .padding(4)
    }
}

// MARK: - Composed preview cell

/// A virtual gallery cell: `icon` composed into `container` (merged with the
/// container's linked partials), rendered live and never written to disk.
/// Deliberately styled apart from real cells — dashed rim, slight
/// transparency, a "composed" badge — and offers no file operations.
private struct ComposedIconCell: View {
    let spec: WorkspaceGalleryView.ComposedSpec
    let thumbnails: ThumbnailStore
    @ObservedObject var store: ComposedThumbnailStore

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 13)
                    .fill(Color.fekthorWell.opacity(0.75))
                if let image = store.image(forKey: renderKey) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(10)
                } else if store.didFail(renderKey) {
                    Image(systemName: "questionmark.square.dashed")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                } else {
                    ProgressView().controlSize(.small).opacity(0.4)
                }
            }
            .frame(width: 96, height: 96)
            .overlay(alignment: .topTrailing) {
                Image(systemName: "square.on.square.dashed")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(3)
                    .background(.regularMaterial, in: Circle())
                    .padding(4)
                    .help("Composed preview — generated, not a file")
            }
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(
                        Color.secondary.opacity(0.8),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
            Text(spec.title)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
                .frame(width: 96)
        }
        .opacity(0.9)
        .help(
            "Composed preview: \(spec.icon.name) in \(spec.container.name)"
                + (spec.partials.isEmpty
                    ? "" : " + \(spec.partials.map(\.name).joined(separator: ", "))"))
        .task(id: renderKey) {
            store.request(
                key: renderKey, iconURL: spec.icon.url, containerURL: spec.container.url,
                partialURLs: spec.partials.map(\.url), slot: spec.slot)
        }
    }

    private var renderKey: String { spec.renderKey(thumbnails) }
}
