import FekthorKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = ConversionModel()
    @StateObject private var workspaceSession = WorkspaceSession()
    @ObservedObject private var menuState = MenuState.shared
    @State private var editorSession: EditorSession? = nil
    @State private var showInspector = true
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var compareMode: CompareMode = .split
    /// When a raster is dropped on the gallery, the trace flow targets the
    /// workspace: the result saves into this category under this name.
    @State private var traceTarget: WorkspaceTraceTarget? = nil
    /// Gallery selection, hoisted so ⌘N can default the new icon into the
    /// selected icon's category even while the editor covers the gallery.
    @State private var gallerySelection: String? = nil
    /// Non-nil presents the New Icon prompt, pre-targeted at a category.
    @State private var newIconRequest: NewIconRequest? = nil
    /// The Workspace Settings sheet (gallery gear, or Workspace ▸ ⇧⌘,).
    @State private var workspaceSettingsShown = false
    /// A mode change (New, Open, Trace Image, Open Workspace, New Icon…)
    /// that would replace a dirty editor session waits here for the
    /// Save/Discard/Cancel choice; Cancel drops it entirely.
    @State private var pendingModeChange: (() -> Void)? = nil
    @State private var confirmModeChange = false

    struct WorkspaceTraceTarget {
        var category: String
        var name: String
    }

    struct NewIconRequest: Identifiable {
        var category: String
        var id: String { category }
    }

    /// The trace flow is active: no editor session on top, and an image or
    /// traced document is loaded. Only then do the vectorize controls
    /// (inspector sidebar + trace toolbar) belong on screen.
    private var inTraceMode: Bool {
        editorSession == nil && (model.sourceImage != nil || model.document != nil)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let session = editorSession {
                    EditorWorkspaceView(
                        session: session, zoom: $zoom, offset: $offset,
                        backLabel: workspaceSession.workspace != nil ? "Gallery" : "Home",
                        grid: editorGrid,
                        guide: editorGuide,
                        snapToPoints: menuState.snapToPoints,
                        workspace: workspaceSession,
                        onClose: { editorSession = nil })
                } else if model.sourceImage != nil || model.document != nil {
                    VStack(spacing: 0) {
                        ComparisonView(
                            model: model, mode: $compareMode, zoom: $zoom, offset: $offset)
                        Divider()
                        if traceTarget != nil && workspaceSession.workspace != nil {
                            workspaceSaveBar
                            Divider()
                        }
                        statusBar
                    }
                } else if workspaceSession.workspace != nil {
                    WorkspaceGalleryView(
                        session: workspaceSession,
                        selection: $gallerySelection,
                        onOpenEntry: { openEntry($0) },
                        onNewIcon: { category in requestNewIcon(category: category) },
                        onDropRaster: { url, category in
                            traceTarget = WorkspaceTraceTarget(
                                category: category,
                                name: url.deletingPathExtension().lastPathComponent)
                            model.load(path: url.path)
                        },
                        onClose: {
                            workspaceSession.close()
                            traceTarget = nil
                        })
                } else {
                    EmptyStateView(
                        model: model,
                        recents: workspaceSession.recents,
                        onNewFile: { newFile() },
                        onOpen: { openAny() },
                        onNewWorkspace: { newWorkspace() },
                        onOpenWorkspace: { openWorkspace() },
                        onOpenRecent: { openRecentWorkspace($0) })
                }
            }
            .navigationTitle(windowTitle)
            .toolbar { toolbarContent }
            // The title/toolbar strip must not block the window's black
            // glass: hide its default opaque background so the backdrop
            // reads through the header like everywhere else.
            .toolbarBackground(.hidden, for: .windowToolbar)
            .inspector(isPresented: inTraceMode ? $showInspector : .constant(false)) {
                InspectorView(model: model)
                    .inspectorColumnWidth(min: 250, ideal: 290, max: 380)
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { model.handleDrop($0) }
            .onPasteCommand(of: [.image, .fileURL]) { _ in model.paste() }
            .alert("Discard your edits?", isPresented: $model.confirmReconvert) {
                Button("Discard & Re-convert", role: .destructive) {
                    model.confirmPendingAction()
                }
                Button("Keep Edits", role: .cancel) { model.cancelPendingAction() }
            } message: {
                Text(
                    "Re-converting rebuilds the vector from the image and your manual point, curve and colour edits will be lost."
                )
            }
            // The mode-change guard: the same Save/Discard/Cancel choice as
            // the editor's Back button, for every transition that would
            // replace or clear a dirty session (see `withDirtyCheck`).
            .confirmationDialog(
                "Save the changes to \(editorSession?.fileURL?.lastPathComponent ?? "this file")?",
                isPresented: $confirmModeChange
            ) {
                Button("Save and Close") {
                    // Proceed only when the save really landed — a cancelled
                    // Save As panel or a failed write keeps the session.
                    if editorSession?.save() ?? true {
                        pendingModeChange?()
                    }
                    pendingModeChange = nil
                }
                Button("Discard Changes", role: .destructive) {
                    pendingModeChange?()
                    pendingModeChange = nil
                }
                Button("Cancel", role: .cancel) { pendingModeChange = nil }
            } message: {
                Text("Your edits have not been saved.")
            }
            .onChange(of: model.imageGeneration) { _, _ in
                zoom = 1
                offset = .zero
            }
            .onAppear {
                // UI-test launches are deterministic: open exactly what the
                // arguments name (workspace folder / file), never the trace
                // flow's bare-path argument.
                if UITestMode.enabled {
                    if let path = UITestMode.workspacePath,
                        workspaceSession.open(folder: URL(fileURLWithPath: path))
                    {
                        enterWorkspaceMode()
                    } else if let path = UITestMode.openPath {
                        route(url: URL(fileURLWithPath: path))
                    }
                } else {
                    model.loadLaunchArgumentIfPresent()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .fekthorNewFile)) { _ in
                // ⌘N in a workspace means "new icon"; the detached blank
                // file remains the no-workspace behaviour.
                if workspaceSession.workspace != nil {
                    requestNewIcon()
                } else {
                    newFile()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .fekthorOpen)) { _ in
                openAny()
            }
            .onReceive(NotificationCenter.default.publisher(for: .fekthorOpenWorkspace)) { _ in
                openWorkspace()
            }
            .onReceive(NotificationCenter.default.publisher(for: .fekthorSave)) { _ in
                if let session = editorSession { session.save() } else { model.exportSVG() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .fekthorSaveAs)) { _ in
                editorSession?.saveAs()
            }
            .onReceive(NotificationCenter.default.publisher(for: .fekthorTraceImage)) { _ in
                withDirtyCheck {
                    editorSession = nil
                    model.openPanel()
                }
            }
            .background(objectCommandListeners)
            .background(workspaceCommandListeners)
            .background(editorCommandListeners)
            .background(guideCommandListeners)
        }
    }

    /// The window title follows the context: open icon, workspace, or app.
    private var windowTitle: String {
        if let session = editorSession {
            return session.fileURL?.lastPathComponent ?? "Untitled"
        }
        if workspaceSession.workspace != nil { return workspaceSession.folderName }
        return "Fekthor"
    }

    /// Object-menu commands (group/ungroup, z-order) act on the editor
    /// session; a hidden background view hosts the listeners so the main
    /// body stays type-checkable.
    private var objectCommandListeners: some View {
        Color.clear
            .onReceive(NotificationCenter.default.publisher(for: .fekthorGroup)) { _ in
                editorSession?.groupSelection()
            }
            .onReceive(NotificationCenter.default.publisher(for: .fekthorUngroup)) { _ in
                editorSession?.ungroupSelection()
            }
            .onReceive(NotificationCenter.default.publisher(for: .fekthorBringForward)) { _ in
                editorSession?.bringForward()
            }
            .onReceive(NotificationCenter.default.publisher(for: .fekthorSendBackward)) { _ in
                editorSession?.sendBackward()
            }
            .onReceive(NotificationCenter.default.publisher(for: .fekthorBringToFront)) { _ in
                editorSession?.bringToFront()
            }
            .onReceive(NotificationCenter.default.publisher(for: .fekthorSendToBack)) { _ in
                editorSession?.sendToBack()
            }
    }

    /// Grid/snap toggles (⌘' / ⇧⌘'), the Path boolean commands, the New
    /// Icon sheet and menu-state sync — a second hidden host keeps the main
    /// body type-checkable.
    private var workspaceCommandListeners: some View {
        Color.clear
            .onReceive(NotificationCenter.default.publisher(for: .fekthorToggleGrid)) { _ in
                MenuState.shared.showGrid.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .fekthorToggleSnap)) { _ in
                let snap = !MenuState.shared.snapToGrid
                MenuState.shared.snapToGrid = snap
                // Persist through the workfile when a workspace is open;
                // otherwise it stays a session-level editor toggle.
                if workspaceSession.workspace != nil {
                    workspaceSession.setSnapToGrid(snap)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .fekthorPathUnite)) { _ in
                editorSession?.combineSelection(.union)
            }
            .onReceive(NotificationCenter.default.publisher(for: .fekthorPathSubtract)) { _ in
                editorSession?.combineSelection(.subtract)
            }
            .onReceive(NotificationCenter.default.publisher(for: .fekthorPathIntersect)) { _ in
                editorSession?.combineSelection(.intersect)
            }
            .onReceive(NotificationCenter.default.publisher(for: .fekthorPathExclude)) { _ in
                editorSession?.combineSelection(.exclude)
            }
            .onChange(of: workspaceSession.workspace != nil) { _, open in
                MenuState.shared.workspaceOpen = open
                if open {
                    MenuState.shared.snapToGrid =
                        workspaceSession.effectiveStandards.snapToGrid ?? false
                }
                MenuState.shared.showGuide = open && workspaceSession.showGuide
            }
            .onChange(of: workspaceSession.settings.settings?.snapToGrid) { _, snap in
                if workspaceSession.workspace != nil {
                    MenuState.shared.snapToGrid = snap ?? false
                }
            }
            .onAppear {
                MenuState.shared.workspaceOpen = workspaceSession.workspace != nil
            }
            .sheet(item: $newIconRequest) { request in
                NewIconSheet(
                    session: workspaceSession,
                    initialCategory: request.category,
                    onCreate: { name, category in createIcon(named: name, category: category) })
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .fekthorWorkspaceSettings)
            ) { _ in
                if workspaceSession.workspace != nil { workspaceSettingsShown = true }
            }
            .sheet(isPresented: $workspaceSettingsShown) {
                WorkspaceSettingsSheet(session: workspaceSession)
            }
    }

    /// Guide toggling (View ▸ Show Guide, ⌥⌘G) and its menu-state sync — a
    /// fourth hidden host keeps the others type-checkable.
    private var guideCommandListeners: some View {
        Color.clear
            .onReceive(NotificationCenter.default.publisher(for: .fekthorToggleGuide)) { _ in
                guard workspaceSession.workspace != nil else { return }
                workspaceSession.setShowGuide(!workspaceSession.showGuide)
                MenuState.shared.showGuide = workspaceSession.showGuide
            }
            .onChange(of: workspaceSession.settings.settings?.showGuide) { _, _ in
                MenuState.shared.showGuide = workspaceSession.showGuide
            }
            .onChange(of: workspaceSession.settings.settings?.guideIcon) { _, _ in
                MenuState.shared.showGuide = workspaceSession.showGuide
            }
    }

    /// Align/distribute (Object ▸ Align) and raster export (File ▸ Export)
    /// act on the editor session; a third hidden host keeps the main body
    /// type-checkable. Align and Distribute each ride ONE notification with
    /// the edge/axis in userInfo.
    private var editorCommandListeners: some View {
        Color.clear
            .onReceive(NotificationCenter.default.publisher(for: .fekthorAlign)) { note in
                guard let edge = note.userInfo?["edge"] as? AlignEdge else { return }
                editorSession?.alignSelection(edge)
            }
            .onReceive(NotificationCenter.default.publisher(for: .fekthorDistribute)) { note in
                guard let axis = note.userInfo?["axis"] as? DistributeAxis else { return }
                editorSession?.distributeSelection(axis)
            }
            .onReceive(NotificationCenter.default.publisher(for: .fekthorExportPNG)) { _ in
                editorSession?.exportPNG()
            }
            .onReceive(NotificationCenter.default.publisher(for: .fekthorExportPDF)) { _ in
                editorSession?.exportPDF()
            }
    }

    /// Runs `action` right away when no unsaved editor work is at stake;
    /// otherwise the confirmation dialog above decides — Save and Close
    /// (proceeds only when the save lands), Discard, or Cancel (the mode
    /// change never happens, no panel is shown).
    private func withDirtyCheck(_ action: @escaping () -> Void) {
        if let session = editorSession, session.dirty {
            pendingModeChange = action
            confirmModeChange = true
        } else {
            action()
        }
    }

    private func newFile() {
        withDirtyCheck {
            editorSession = EditorSession.blank(size: 72)
            zoom = 1
            offset = .zero
        }
    }

    // MARK: - New icon (the workspace's primary action)

    /// Opens the New Icon prompt. Without an explicit category it targets
    /// the icon open in the editor / selected in the gallery. A dirty
    /// editor with a file is saved first — switching must never lose work —
    /// and the prompt only opens when that save lands; a dirty untitled
    /// session goes through the Save/Discard/Cancel dialog instead.
    private func requestNewIcon(category: String? = nil) {
        guard workspaceSession.workspace != nil else {
            newFile()
            return
        }
        if let session = editorSession, session.dirty {
            guard session.fileURL != nil else {
                withDirtyCheck {
                    newIconRequest = NewIconRequest(category: category ?? inferredCategory)
                }
                return
            }
            guard session.save() else { return }
        }
        newIconRequest = NewIconRequest(category: category ?? inferredCategory)
    }

    /// The category a context-less New Icon lands in: the editor's current
    /// icon's category, else the gallery selection's, else the root.
    private var inferredCategory: String {
        guard let ws = workspaceSession.workspace else { return "" }
        if let url = editorSession?.fileURL?.standardizedFileURL,
            let entry = ws.entries.first(where: { $0.url.standardizedFileURL == url })
        {
            return entry.category
        }
        if let sel = gallerySelection,
            let entry = ws.entries.first(where: { $0.id == sel })
        {
            return entry.category
        }
        return ""
    }

    /// Create → open in the editor immediately (create → draw → ⌘S → back
    /// must be one unbroken loop). Returns false to keep the prompt open.
    private func createIcon(named name: String, category: String) -> Bool {
        guard let url = workspaceSession.createIcon(named: name, category: category) else {
            return false
        }
        do {
            let session = try EditorSession.open(url: url)
            applyWorkspaceDefaults(to: session)
            editorSession = session
            gallerySelection = category.isEmpty ? name : category + "/" + name
            zoom = 1
            offset = .zero
        } catch {
            workspaceSession.status =
                "Created \(name).svg, but it could not be opened: \(error.localizedDescription)"
        }
        return true
    }

    /// New shapes in a workspace icon are born with the workspace's drawing
    /// defaults (stroke colour/width, fill).
    private func applyWorkspaceDefaults(to session: EditorSession) {
        guard workspaceSession.workspace != nil else { return }
        let std = workspaceSession.effectiveStandards
        var style = Style()
        if let fill = std.defaultFill {
            if fill == "none" {
                style.set("fill", .paint(.none))
            } else if let c = PaintValue.parseHex(fill) {
                style.set("fill", .paint(.color(r: c.r, g: c.g, b: c.b)))
            }
        }
        if let hex = std.defaultStrokeColor, let c = PaintValue.parseHex(hex) {
            style.set("stroke", .paint(.color(r: c.r, g: c.g, b: c.b)))
        }
        if let width = std.defaultStrokeWidth {
            style.set("stroke-width", .number(width, unit: nil))
        }
        if !style.declarations.isEmpty {
            session.drawingStyle = style
        }
    }

    /// The grid the editor canvas draws/snaps: workspace standards when a
    /// workspace is open, the engine's `.standard` for detached editors.
    /// Visibility (⌘') and snap (⇧⌘') come from the menu state.
    private var editorGrid: EditorGridConfig? {
        let std =
            workspaceSession.workspace != nil
            ? workspaceSession.effectiveStandards
            : Workfile.WorkspaceSettings.standard
        guard let spacing = std.gridSpacing, spacing > 0 else { return nil }
        return EditorGridConfig(
            spacing: spacing,
            subdivisions: std.gridSubdivisions ?? 0,
            visible: menuState.showGrid,
            snap: menuState.snapToGrid,
            opacity: std.gridOpacity ?? 1)
    }

    /// The workspace guide icon drawn dimmed behind the open icon. nil when
    /// no workspace/guide is configured — or when the open file IS the
    /// guide (editing the guide must not draw the guide under itself). The
    /// View ▸ Show Guide toggle rides `showGuide` through the workfile.
    private var editorGuide: EditorGuideConfig? {
        guard workspaceSession.workspace != nil,
            let entry = workspaceSession.guideEntry(),
            let doc = workspaceSession.guideDocument()
        else { return nil }
        if let open = editorSession?.fileURL?.standardizedFileURL,
            open == entry.url.standardizedFileURL
        {
            return nil
        }
        return EditorGuideConfig(document: doc, visible: workspaceSession.showGuide)
    }

    /// One Open for everything: svg/fekthor go to the editor, rasters to trace.
    private func openAny() {
        withDirtyCheck { openAnyResolved() }
    }

    /// The open panel + routing, after any dirty session has been resolved.
    private func openAnyResolved() {
        let panel = NSOpenPanel()
        var types: [UTType] = [.png, .jpeg, .tiff, .heic, .image]
        if let svg = UTType(filenameExtension: "svg") { types.insert(svg, at: 0) }
        if let fk = UTType(filenameExtension: "fekthor") { types.insert(fk, at: 1) }
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        route(url: url)
    }

    private func route(url: URL) {
        let ext = url.pathExtension.lowercased()
        // A .fekthor with a folder reference IS a workspace; only workfiles
        // with embedded artboards (and plain SVGs) go to the editor.
        if ext == "fekthor", workspaceSession.openWorkfile(url) {
            enterWorkspaceMode()
            return
        }
        if ext == "svg" || ext == "fekthor" {
            do {
                editorSession = try EditorSession.open(url: url)
                zoom = 1
                offset = .zero
            } catch {
                model.status = "Could not open \(url.lastPathComponent): \(error.localizedDescription)"
            }
        } else {
            editorSession = nil
            model.load(path: url.path)
        }
    }

    // MARK: - Workspace mode

    private func enterWorkspaceMode() {
        editorSession = nil
        traceTarget = nil
        model.reset()
    }

    private func openWorkspace() {
        withDirtyCheck {
            if workspaceSession.openPanel() { enterWorkspaceMode() }
        }
    }

    private func newWorkspace() {
        withDirtyCheck {
            if workspaceSession.newWorkspace() { enterWorkspaceMode() }
        }
    }

    private func openRecentWorkspace(_ recent: RecentWorkspace) {
        withDirtyCheck {
            if workspaceSession.openRecent(recent) { enterWorkspaceMode() }
        }
    }

    /// Trace → editor handoff: the CURRENT vector (hand edits included)
    /// crosses the Model2Bridge into an UNTITLED editor session — dirty
    /// from birth, so leaving without saving prompts. The trace state
    /// clears once the session exists (same reset the workspace-save flow
    /// uses); a workspace trace target does NOT reroute this — the save
    /// bar remains the way to file a trace into the workspace, Open in
    /// Editor always detaches.
    private func openTraceInEditor() {
        guard let doc = model.document else { return }
        let session = EditorSession(document: Model2Bridge.graphicDocument(from: doc))
        session.dirty = true
        session.status = "Opened the traced vector — untitled; ⌘S saves it."
        editorSession = session
        traceTarget = nil
        model.reset()
        zoom = 1
        offset = .zero
    }

    /// Gallery double-click / Open in Editor: straight into the editor; the
    /// editor's Back returns to the gallery (the workspace stays open).
    private func openEntry(_ entry: IconEntry) {
        do {
            let session = try EditorSession.open(url: entry.url)
            applyWorkspaceDefaults(to: session)
            editorSession = session
            zoom = 1
            offset = .zero
        } catch {
            workspaceSession.status =
                "Could not open \(entry.fileName): \(error.localizedDescription)"
        }
    }

    /// Shown under the trace comparison when the trace was started by a
    /// drop on the gallery: name + category, one click to land the SVG in
    /// the workspace.
    private var workspaceSaveBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.grid.3x3.square").foregroundStyle(Color.accentColor)
            Text("Add to workspace:")
            TextField(
                "icon name",
                text: Binding(
                    get: { traceTarget?.name ?? "" },
                    set: { traceTarget?.name = $0 })
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: 180)
            Picker(
                "in",
                selection: Binding(
                    get: { traceTarget?.category ?? "" },
                    set: { traceTarget?.category = $0 })
            ) {
                Text("Uncategorized").tag("")
                ForEach(workspaceSession.workspace?.categories ?? [], id: \.self) {
                    Text($0).tag($0)
                }
            }
            .frame(maxWidth: 220)
            Button("Save to Workspace") { saveTraceIntoWorkspace() }
                .disabled(!model.hasResult)
            Button("Back to Gallery") {
                traceTarget = nil
                model.reset()
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.06))
    }

    private func saveTraceIntoWorkspace() {
        guard let target = traceTarget, let ws = workspaceSession.workspace,
            let svg = model.currentSVGText()
        else { return }
        let stem = target.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stem.isEmpty, !stem.hasPrefix("."), !stem.contains("/"), !stem.contains("\\")
        else {
            model.status = "Pick a usable icon name (not empty or hidden, no slashes)."
            return
        }
        let folder =
            target.category.isEmpty ? ws.root : ws.root.appendingPathComponent(target.category)
        let destination = folder.appendingPathComponent(stem + ".svg")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                model.status = "\(stem).svg already exists in that category — pick another name."
                return
            }
            try svg.write(to: destination, atomically: true, encoding: .utf8)
            workspaceSession.status =
                "Added \(stem).svg"
                + (target.category.isEmpty ? "." : " to \(target.category).")
            workspaceSession.rescanNow()
            traceTarget = nil
            model.reset()
        } catch {
            model.status = "Could not save into the workspace: \(error.localizedDescription)"
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if inTraceMode {
            ToolbarItemGroup(placement: .navigation) {
                Button { model.openPanel() } label: {
                    Label("Open", systemImage: "photo.badge.plus")
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if model.hasResult && model.sourceImage != nil {
                    Picker("View", selection: $compareMode) {
                        ForEach(CompareMode.allCases, id: \.self) { m in
                            Image(systemName: m.icon).help(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                if zoom != 1 || offset != .zero {
                    Button {
                        zoom = 1
                        offset = .zero
                    } label: { Label("Fit", systemImage: "arrow.up.left.and.arrow.down.right") }
                }
                Button { model.undoEdit() } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!model.canUndo)
                Button { openTraceInEditor() } label: {
                    Label("Open in Editor", systemImage: "square.and.pencil")
                }
                .disabled(!model.hasResult)
                .help("Continue with this vector in the editor")
                Button { model.exportSVG() } label: {
                    Label("Export SVG", systemImage: "square.and.arrow.up")
                }
                .disabled(!model.hasResult)
                Button { showInspector.toggle() } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
            }
        }
    }

    private var statusBar: some View {
        HStack {
            Text(model.status).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if model.hasResult {
                Text(
                    model.controlsMode == .strokes
                        ? String(
                            format: "quality %.0f%%  ·  strokes %d  ·  nodes %d",
                            model.overallQuality * 100, model.strokes, model.nodes)
                        : String(
                            format: "quality %.0f%%  ·  exact %.1f%%  ·  PSNR %.1f dB  ·  nodes %d",
                            model.overallQuality * 100, model.exactPct, model.psnr, model.nodes)
                )
                .font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }
}

// MARK: - Empty state

private struct EmptyStateView: View {
    @ObservedObject var model: ConversionModel
    var recents: [RecentWorkspace] = []
    var onNewFile: () -> Void = {}
    var onOpen: () -> Void = {}
    var onNewWorkspace: () -> Void = {}
    var onOpenWorkspace: () -> Void = {}
    var onOpenRecent: (RecentWorkspace) -> Void = { _ in }

    @StateObject private var recentPreviews = RecentPreviewStore()

    var body: some View {
        ZStack {
            // Transparent: the window's black-glass backdrop shows through.
            Color.clear
            VStack(spacing: 28) {
                VStack(spacing: 6) {
                    Text("Fekthor").font(.largeTitle).fontWeight(.semibold)
                    Text("Vector editing, with tracing built in.")
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 16) {
                    homeCard(
                        icon: "doc.badge.plus",
                        title: "New File",
                        subtitle: "A blank 72×72 artboard.\nSaves as plain SVG.",
                        enabled: true
                    ) {
                        onNewFile()
                    }
                    .accessibilityIdentifier("home.newFile")
                    homeCard(
                        icon: "square.grid.3x3.square",
                        title: "New Workspace",
                        subtitle: "An icon library —\na .fekthor workfile over\na folder of SVGs.",
                        enabled: true
                    ) {
                        onNewWorkspace()
                    }
                    .accessibilityIdentifier("home.newWorkspace")
                    homeCard(
                        icon: "wand.and.rays",
                        title: "Vectorize Image",
                        subtitle: "Trace a PNG or photo\ninto editable vectors.",
                        enabled: true
                    ) {
                        model.openPanel()
                    }
                    .accessibilityIdentifier("home.vectorize")
                }
                HStack(spacing: 20) {
                    Button("Open a file…", action: onOpen)
                        .buttonStyle(.link)
                    Button("Open Workspace…", action: onOpenWorkspace)
                        .buttonStyle(.link)
                }
                if !recents.isEmpty {
                    VStack(spacing: 6) {
                        Text("Recent workspaces")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(recents.prefix(5)) { recent in
                            RecentWorkspaceRow(recent: recent, store: recentPreviews) {
                                onOpenRecent(recent)
                            }
                        }
                    }
                }
                Text("or drop an image or SVG anywhere · press ⌘V to paste")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(40)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { model.handleDrop($0) }
    }

    private func homeCard(
        icon: String, title: String, subtitle: String, enabled: Bool, badge: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        HomeCard(
            icon: icon, title: title, subtitle: subtitle, enabled: enabled, badge: badge,
            action: action)
    }
}

/// One home-screen action card: borderless, on an adaptive fill that reads
/// as a card in both appearances (slightly lighter than the window in light
/// mode, slightly darker-contrasting in dark), brightening on hover.
private struct HomeCard: View {
    let icon: String
    let title: String
    let subtitle: String
    var enabled = true
    var badge: String? = nil
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 34))
                    .foregroundStyle(enabled ? Color.accentColor : Color.secondary)
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                if let badge {
                    Text(badge)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
            .frame(width: 190, height: 170)
            .background(
                ZStack {
                    // Always a touch DARKER than the window background (Sil):
                    // a black scrim reads as a sunken card in light mode and
                    // deepens the dark background too; subtler in light.
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.black.opacity(0.07))
                    if hovering && enabled {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.black.opacity(0.06))
                    }
                }
            )
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.6)
    }
}

// MARK: - Synchronized zoom/pan comparison

enum CompareMode: String, CaseIterable {
    case split = "Split"
    case overlay = "Overlay"
    case wipe = "Wipe"
    case edit = "Edit"

    var icon: String {
        switch self {
        case .split: return "rectangle.split.2x1"
        case .overlay: return "square.2.layers.3d"
        case .wipe: return "rectangle.leadinghalf.filled"
        case .edit: return "point.topleft.down.to.point.bottomright.curvepath"
        }
    }
}

private struct ComparisonView: View {
    @ObservedObject var model: ConversionModel
    @Binding var mode: CompareMode
    @Binding var zoom: CGFloat
    @Binding var offset: CGSize

    private var source: NSImage? { model.sourceImage }
    private var busy: Bool { model.isBusy }
    @State private var overlayOpacity: Double = 0.5
    @State private var wipe: CGFloat = 0.5

    private func setZoom(_ z: CGFloat) { zoom = min(24, max(1, z)) }
    private func reset() {
        zoom = 1
        offset = .zero
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Group {
                    switch (model.sourceImage == nil ? CompareMode.edit : mode) {
                    case .split:
                        HSplitView {
                            pane(title: "Source", image: source, busy: false)
                            vectorPane
                        }
                    case .overlay:
                        singleCanvas { size in
                            ZStack {
                                imageLayer(source, in: size)
                                VectorEditLayer(
                                    model: model, zoom: $zoom, offset: $offset, busy: busy,
                                    contentOpacity: overlayOpacity)
                            }
                        }
                    case .wipe:
                        singleCanvas { size in
                            ZStack {
                                imageLayer(source, in: size)
                                VectorEditLayer(
                                    model: model, zoom: $zoom, offset: $offset, busy: busy
                                )
                                .mask(alignment: .leading) {
                                    Rectangle()
                                        .frame(width: max(0, size.width * wipe))
                                }
                            }
                        }
                    case .edit:
                        singleCanvas { _ in
                            VectorEditLayer(model: model, zoom: $zoom, offset: $offset, busy: busy)
                        }
                    }
                }
                .overlay(
                    TrackpadCatcher(
                        onPan: { dx, dy in
                            offset = CGSize(width: offset.width + dx, height: offset.height + dy)
                        },
                        onZoom: { m in setZoom(zoom * (1 + m)) },
                        onDoubleClick: { p in
                            if mode == .split, p.x >= geo.size.width / 2 {
                                mode = .edit
                            } else {
                                zoomIn(at: p, in: geo.size)
                            }
                        }
                    )
                )
                if mode == .wipe {
                    wipeDivider(in: geo.size)
                }
                if !model.selectedElements.isEmpty {
                    VStack {
                        colorBar
                        Spacer()
                    }
                }
                zoomControls
            }
        }
    }

    /// Double-click: zoom in one step, anchored at the clicked point (mapped to
    /// its pane — panes share the transform, so they stay in lockstep).
    private func zoomIn(at p: CGPoint, in size: CGSize) {
        let localX: CGFloat
        let paneW: CGFloat
        if mode == .split {
            paneW = size.width / 2
            localX = p.x >= paneW ? p.x - paneW : p.x
        } else {
            paneW = size.width
            localX = p.x
        }
        let click = CGSize(width: localX - paneW / 2, height: p.y - size.height / 2)
        let newZoom = min(24, zoom * 1.6)
        let k = newZoom / zoom
        offset = CGSize(
            width: click.width - (click.width - offset.width) * k,
            height: click.height - (click.height - offset.height) * k)
        zoom = newZoom
    }

    /// The draggable wipe divider sits ABOVE the trackpad catcher so its drag
    /// wins over click-drag panning.
    private func wipeDivider(in size: CGSize) -> some View {
        let x = size.width * wipe
        return ZStack {
            Rectangle().fill(.white).frame(width: 2)
                .shadow(color: .black.opacity(0.5), radius: 2)
            Image(systemName: "arrow.left.and.right.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.black, .white)
        }
        .frame(width: 24)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .position(x: x, y: size.height / 2)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    wipe = min(0.99, max(0.01, v.location.x / size.width))
                }
        )
    }

    private func singleCanvas(@ViewBuilder content: @escaping (CGSize) -> some View) -> some View
    {
        VStack(spacing: 0) {
            HStack {
                Text(mode.rawValue).font(.headline)
                if mode == .edit {
                    Text("full-canvas editing — double-click the Vector pane to get here")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                Spacer()
                if mode == .overlay {
                    Slider(value: $overlayOpacity, in: 0...1)
                        .frame(width: 140)
                        .controlSize(.small)
                }
            }
            .padding(8)
            GeometryReader { inner in
                ZStack {
                    Rectangle().fill(Color(nsColor: .textBackgroundColor))
                    content(inner.size)
                }
                .clipped()
            }
        }
        .frame(minWidth: 300, minHeight: 340)
    }

    @ViewBuilder
    private func imageLayer(_ image: NSImage?, in size: CGSize) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .scaleEffect(zoom)
                .offset(offset)
                .frame(width: size.width, height: size.height)
        }
    }

    /// Floating recolour bar for the current path selection: a colour well,
    /// a default palette, and the colours already used in this vector.
    private var colorBar: some View {
        let defaults: [Color] = [
            .black, .white, Color(red: 0.5, green: 0.5, blue: 0.5),
            Color(red: 0.86, green: 0.18, blue: 0.16), Color(red: 0.96, green: 0.55, blue: 0.14),
            Color(red: 0.97, green: 0.82, blue: 0.25), Color(red: 0.27, green: 0.66, blue: 0.32),
            Color(red: 0.19, green: 0.62, blue: 0.62), Color(red: 0.19, green: 0.42, blue: 0.78),
            Color(red: 0.51, green: 0.31, blue: 0.72), Color(red: 0.89, green: 0.39, blue: 0.62),
            Color(red: 0.55, green: 0.36, blue: 0.24),
        ]
        return HStack(spacing: 8) {
            Text("\(model.selectedElements.count) selected")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            ColorPicker(
                "",
                selection: Binding(
                    get: { model.selectionColor },
                    set: { model.setSelectionColor($0) })
            )
            .labelsHidden()
            Divider().frame(height: 16)
            swatchRow(defaults)
            if !model.documentColors.isEmpty {
                Divider().frame(height: 16)
                swatchRow(model.documentColors)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.quaternary))
        .padding(.top, 44)
    }

    private func swatchRow(_ colors: [Color]) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, c in
                Circle()
                    .fill(c)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(.quaternary, lineWidth: 0.5))
                    .onTapGesture {
                        // Each swatch tap is its own undo step.
                        model.selectionChanged()
                        model.setSelectionColor(c)
                    }
            }
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 2) {
            Button { setZoom(zoom / 1.25) } label: { Image(systemName: "minus") }
                .keyboardShortcut("-", modifiers: .command)
            Text("\(Int(zoom * 100))%").font(.callout.monospacedDigit()).frame(width: 52)
            Button { setZoom(zoom * 1.25) } label: { Image(systemName: "plus") }
                .keyboardShortcut("=", modifiers: .command)
            // The shifted variant of the same key, so a literal Cmd-+ works too.
            Button { setZoom(zoom * 1.25) } label: { EmptyView() }
                .keyboardShortcut("+", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
            // Backspace deletes the selected paths.
            Button { model.deleteSelection() } label: { EmptyView() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(model.selectedElements.isEmpty)
                .frame(width: 0, height: 0)
                .opacity(0)
            Divider().frame(height: 16)
            Button { reset() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.quaternary))
        .padding(.bottom, 12)
    }

    private var vectorPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Vector").font(.headline)
                Spacer()
                Text("click a shape to edit").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(8)
            ZStack {
                Rectangle().fill(Color(nsColor: .textBackgroundColor))
                VectorEditLayer(model: model, zoom: $zoom, offset: $offset, busy: busy)
            }
            .clipped()
        }
        .frame(minWidth: 300, minHeight: 340)
    }

    private func pane(title: String, image: NSImage?, busy: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
            }
            .padding(8)
            GeometryReader { _ in
                ZStack {
                    Rectangle().fill(Color(nsColor: .textBackgroundColor))
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .scaleEffect(zoom)
                            .offset(offset)
                            .opacity(busy ? 0.5 : 1)
                    }
                }
                .clipped()
            }
        }
        .frame(minWidth: 300, minHeight: 340)
    }
}

/// Captures trackpad two-finger scroll (pan) and pinch (zoom) events.
private struct TrackpadCatcher: NSViewRepresentable {
    let onPan: (CGFloat, CGFloat) -> Void
    let onZoom: (CGFloat) -> Void
    var onDoubleClick: ((CGPoint) -> Void)? = nil

    func makeNSView(context: Context) -> NSView {
        let v = CatcherView()
        v.onPan = onPan
        v.onZoom = onZoom
        v.onDoubleClick = onDoubleClick
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let v = nsView as? CatcherView else { return }
        v.onPan = onPan
        v.onZoom = onZoom
        v.onDoubleClick = onDoubleClick
    }

    final class CatcherView: NSView {
        var onPan: ((CGFloat, CGFloat) -> Void)?
        var onZoom: ((CGFloat) -> Void)?
        var onDoubleClick: ((CGPoint) -> Void)?
        private var monitors: [Any] = []

        // Clicks belong to the live edit canvas below (select shapes, drag
        // anchors), so this view never claims hit-testing. Two-finger scroll,
        // pinch and double-click are taken from the event stream instead —
        // monitors see them regardless of hit-testing, and returning the
        // event keeps normal dispatch intact.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            for m in monitors { NSEvent.removeMonitor(m) }
            monitors = []
            guard window != nil else { return }
            monitors.append(
                NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
                    guard let self, self.covers(e) else { return e }
                    if e.modifierFlags.contains(.control) {
                        // Control + two-finger scroll zooms (macOS convention).
                        self.onZoom?(e.scrollingDeltaY * 0.01)
                    } else {
                        self.onPan?(e.scrollingDeltaX, e.scrollingDeltaY)
                    }
                    return e
                }!)
            monitors.append(
                NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] e in
                    guard let self, self.covers(e) else { return e }
                    self.onZoom?(e.magnification)
                    return e
                }!)
            monitors.append(
                NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] e in
                    guard let self, e.clickCount == 2, self.covers(e) else { return e }
                    let p = self.convert(e.locationInWindow, from: nil)
                    // NSView is bottom-left origin; SwiftUI expects top-left.
                    self.onDoubleClick?(CGPoint(x: p.x, y: self.bounds.height - p.y))
                    return e
                }!)
        }

        deinit {
            for m in monitors { NSEvent.removeMonitor(m) }
        }

        private func covers(_ e: NSEvent) -> Bool {
            guard e.window === window else { return false }
            let p = convert(e.locationInWindow, from: nil)
            return bounds.contains(p)
        }
    }
}

// MARK: - Inspector

private struct InspectorView: View {
    @ObservedObject var model: ConversionModel

    var body: some View {
        Form {
            if model.isBusy {
                Section {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Processing…").foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            Section("Vectorise") {
                Picker("Mode", selection: $model.mode) {
                    Text("Auto").tag(Mode.auto)
                    Text("Shapes").tag(Mode.shapes)
                    Text("Strokes").tag(Mode.strokes)
                    Text("Gradient").tag(Mode.gradient)
                }
                .onChange(of: model.mode) { _, _ in model.convert() }

                if model.mode == .auto {
                    LabeledContent("Detected", value: model.resolvedMode.rawValue.capitalized)
                }

                Button {
                    model.autoTune()
                } label: {
                    Label("Auto-tune settings", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .help(
                    "Try Detail, Simplicity and Smoothing combinations on a thumbnail and move the sliders to the best-scoring one."
                )
                .disabled(model.isBusy)

                if model.controlsMode == .shapes {
                    Toggle("Logo", isOn: $model.logoPreset)
                        .onChange(of: model.logoPreset) { _, enabled in
                            if enabled {
                                model.applyLogoPreset()
                            } else {
                                model.convert()
                            }
                        }
                }

                if model.sourceIsSmall {
                    if model.enhanceAvailable {
                        Toggle("Enhance small image (AI)", isOn: $model.enhance)
                            .onChange(of: model.enhance) { _, _ in model.enhanceChanged() }
                            .help(
                                "Upscale 4x with on-device Real-ESRGAN before vectorising — small logos and icons trace far better. Fully local."
                            )
                    } else {
                        LabeledContent("Enhance small image (AI)") {
                            Text("Model not installed")
                                .foregroundStyle(.secondary)
                        }
                        .help(
                            "Fekthor never downloads models. To enable on-device 4× upscaling, place a compiled Real-ESRGAN model at \(ModelStore.compiledURL(.realESRGAN).path); it runs fully local."
                        )
                    }
                }
                Picker("Resolution", selection: $model.resolution) {
                    Text("Auto").tag(0)
                    Text("Fast · 512").tag(512)
                    Text("Balanced · 1024").tag(1024)
                    Text("Detailed · 2048").tag(2048)
                }
                .onChange(of: model.resolution) { _, _ in model.resolutionChanged() }

                if model.controlsMode == .shapes || model.controlsMode == .gradient {
                    Toggle("Auto colours", isOn: $model.autoColors)
                        .onChange(of: model.autoColors) { _, _ in model.convert() }
                    slider(
                        model.autoColors ? "Max colours" : "Colours", value: $model.colors,
                        range: 2...32, step: 1
                    ) { "\(Int(model.colors))" }
                }
                if model.controlsMode == .shapes || model.controlsMode == .gradient {
                    slider(
                        model.controlsMode == .gradient ? "Blend" : "Simplicity",
                        value: $model.simplicity, range: 0...1, step: 0.05
                    ) { String(format: "%.0f%%", model.simplicity * 100) }
                }
                if model.controlsMode == .shapes {
                    // Flatten: collapse shade families (a beard's blonds, a face's
                    // skins) into flat colours. 0% keeps today's output exactly.
                    slider("Flatten", value: $model.flatten, range: 0...1, step: 0.05) {
                        String(format: "%.0f%%", model.flatten * 100)
                    }
                    Toggle("Part aware (AI)", isOn: $model.partAware)
                        .onChange(of: model.partAware) { _, _ in model.convert() }
                        .help(
                            "Use on-device Vision segmentation so regions never merge across a detected part boundary. Fully local."
                        )
                }
                if model.controlsMode == .strokes {
                    Picker("Lines from", selection: $model.strokeSource) {
                        Text("Auto").tag(StrokeSource.auto)
                        Text("Centreline").tag(StrokeSource.centreline)
                        Text("Region edges").tag(StrokeSource.edges)
                    }
                    .onChange(of: model.strokeSource) { _, _ in model.convert() }
                    Toggle("Auto line width", isOn: $model.strokeWidthAuto)
                        .onChange(of: model.strokeWidthAuto) { _, _ in model.convert() }
                    if !model.strokeWidthAuto {
                        slider("Line width", value: $model.strokeWidth, range: 0.5...30, step: 0.5) {
                            String(format: "%.1f", model.strokeWidth)
                        }
                    } else {
                        Toggle("Uniform width", isOn: $model.uniformStrokeWidth)
                            .onChange(of: model.uniformStrokeWidth) { _, _ in model.convert() }
                    }
                    Picker("Caps", selection: $model.strokeCap) {
                        Text("Round").tag(LineCap.round)
                        Text("Butt").tag(LineCap.butt)
                        Text("Square").tag(LineCap.square)
                    }
                    .onChange(of: model.strokeCap) { _, _ in model.convert() }
                    Toggle("Taper ends", isOn: $model.taper)
                        .onChange(of: model.taper) { _, _ in model.convert() }
                    Toggle("Variable width", isOn: $model.variableWidth)
                        .onChange(of: model.variableWidth) { _, _ in model.convert() }
                        .help(
                            "Lines whose ink swells and thins become smooth outline fills that follow the drawn width, like Illustrator width profiles."
                        )
                    Toggle("Line colour", isOn: $model.lineColorEnabled)
                        .onChange(of: model.lineColorEnabled) { _, _ in model.convert() }
                    if model.lineColorEnabled {
                        ColorPicker("Colour", selection: $model.lineColor, supportsOpacity: false)
                            .onChange(of: model.lineColor) { _, _ in model.convert() }
                    }
                }
                slider("Detail", value: $model.detail, range: 0...1, step: 0.05) {
                    String(format: "%.0f%%", model.detail * 100)
                }
                slider("Smoothing", value: $model.smoothing, range: 0...1, step: 0.05) {
                    String(format: "%.0f%%", model.smoothing * 100)
                }
                slider("Straighten", value: $model.straighten, range: 0...1, step: 0.05) {
                    String(format: "%.0f%%", model.straighten * 100)
                }
            }

            if !model.sourceInfo.isEmpty {
                Section("Source") {
                    LabeledContent("Working size", value: model.sourceInfo)
                }
            }

            if model.hasResult {
                Section("Result") {
                    // One honest, mode-aware score comparable across all modes.
                    LabeledContent(
                        "Quality", value: String(format: "%.0f%%", model.overallQuality * 100))
                    // Pixel-match metrics only apply to fill modes; Strokes output is
                    // line art, so comparing it to a colour source is not meaningful.
                    if model.controlsMode == .strokes {
                        LabeledContent("Strokes", value: "\(model.strokes)")
                    } else {
                        LabeledContent("Exact match", value: String(format: "%.1f%%", model.exactPct))
                        LabeledContent("PSNR", value: String(format: "%.1f dB", model.psnr))
                        LabeledContent("Fills", value: "\(model.fills)")
                    }
                    LabeledContent("Nodes", value: "\(model.nodes)")
                    LabeledContent("SVG size", value: "\(model.svgKB) KB")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func slider(
        _ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double,
        _ label: @escaping () -> String
    ) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text(label()).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step) { editing in
                if !editing { model.convert() }
            }
        }
    }
}

// MARK: - Editor workspace

/// The vector-editor face of the app: an EditorSession's canvas with a
/// compact top bar (file name, fill/stroke colour for the selection, undo,
/// save, close). Trace remains a separate flow.
struct EditorWorkspaceView: View {
    @ObservedObject var session: EditorSession
    @Binding var zoom: CGFloat
    @Binding var offset: CGSize
    /// Where Back leads: "Home", or "Gallery" when a workspace is open.
    var backLabel: String = "Home"
    /// Workspace grid (drawn + snapped by the canvas); nil hides it.
    var grid: EditorGridConfig? = nil
    /// Workspace guide icon (drawn dimmed behind the artwork); nil = none.
    var guide: EditorGuideConfig? = nil
    /// View ▸ Snap to Points (⌥⌘'), passed through to the canvas.
    var snapToPoints: Bool = false
    /// The app's workspace session — the Swatches palette reads/writes the
    /// shared swatches through it (works detached too: the panel shows a
    /// hint while no workspace is open).
    let workspace: WorkspaceSession
    var onClose: () -> Void

    @ObservedObject private var panels = EditorPanelsState.shared
    @State private var confirmClose = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            ZStack(alignment: .bottom) {
                EditorCanvasView(
                    session: session, zoom: $zoom, offset: $offset, grid: grid,
                    guide: guide, snapToPoints: snapToPoints)
                    .overlay(
                        TrackpadCatcher(
                            onPan: { dx, dy in
                                offset = CGSize(
                                    width: offset.width + dx, height: offset.height + dy)
                            },
                            onZoom: { m in zoom = min(64, max(0.2, zoom * (1 + m))) },
                            onDoubleClick: { _ in
                                // Double-click finishes a pen path OPEN
                                // (the second click landed as an anchor;
                                // the finish trims that duplicate) and
                                // leaves the other drawing tools; in
                                // Select it keeps its zoom meaning.
                                if session.tool == .pen {
                                    if !session.penAnchors.isEmpty {
                                        session.finishPenPath(
                                            closed: false, trimDuplicate: true)
                                    } else {
                                        session.tool = .select
                                    }
                                } else if session.tool != .select {
                                    session.tool = .select
                                } else {
                                    zoom = min(64, zoom * 1.6)
                                }
                            }
                        )
                    )
                toolShelf
            }
            // The zoom/scale pill floats top-centre of the canvas, like
            // ImageKid's viewport toolbar — same dark glass as the tool
            // shelf, non-draggable.
            .overlay(alignment: .top) { zoomPill.padding(.top, 12) }
            // The style/combine palettes float above the canvas, inside the
            // window (ImageKid's panel mechanic) — draggable, closable,
            // positions persisted. The workspace session rides the
            // environment so panel internals (swatch popovers) can read the
            // shared swatches without threading it through every initializer.
            .overlay(
                EditorPanelsLayer(session: session, workspace: workspace)
                    .environmentObject(workspace))
            Divider()
            HStack {
                Text(session.status).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Text("\(session.document.nodes.count) nodes")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("editor.nodeCount")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        // The window/tab title tracks the open icon and its dirty state.
        .navigationTitle(session.fileURL?.lastPathComponent ?? "Untitled")
        .navigationSubtitle(session.dirty ? "Edited" : "")
        .onAppear {
            MenuState.shared.canCombine = session.selection.count >= 2
            MenuState.shared.canAlign = !session.selection.isEmpty
            MenuState.shared.editorOpen = true
        }
        .onDisappear {
            MenuState.shared.canCombine = false
            MenuState.shared.canAlign = false
            MenuState.shared.editorOpen = false
        }
        .onChange(of: session.selection) { _, selection in
            MenuState.shared.canCombine = selection.count >= 2
            MenuState.shared.canAlign = !selection.isEmpty
        }
        .confirmationDialog(
            "Save the changes to \(session.fileURL?.lastPathComponent ?? "this file")?",
            isPresented: $confirmClose
        ) {
            Button("Save and Close") {
                // Close only when the save really landed — untitled files
                // route through Save As, which the user can cancel.
                if session.save() { onClose() }
            }
            Button("Discard Changes", role: .destructive) { onClose() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your edits have not been saved.")
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                if session.dirty {
                    confirmClose = true
                } else {
                    onClose()
                }
            } label: {
                Label(backLabel, systemImage: "chevron.left")
            }
            .accessibilityIdentifier("editor.back")
            Text(session.fileURL?.lastPathComponent ?? "Untitled")
                .font(.headline)
                .accessibilityIdentifier("editor.title")
            if session.dirty {
                Circle().fill(.orange).frame(width: 7, height: 7)
                    .accessibilityLabel("Edited")
                    .accessibilityIdentifier("editor.dirtyDot")
            }
            Spacer()
            if !session.selection.isEmpty {
                Text("\(session.selection.count) selected")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button {
                session.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .labelStyle(.iconOnly)
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!session.canUndo)
            .help("Undo (⌘Z)")
            .accessibilityIdentifier("editor.undo")
            Button {
                session.save()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
                    .labelStyle(.iconOnly)
            }
            .accessibilityIdentifier("editor.save")
            // The one prominent header action: Save keeps the accent while
            // there is something to save; everything else stays neutral.
            .tint(session.dirty ? Color.fekthorAccent : .primary)
            .help("Save (⌘S)")
            // Compact access to the floating palettes (same set as the
            // Panels menu): checkmarked toggles for Fill / Stroke / Opacity
            // / Combine.
            Menu {
                ForEach(EditorPanel.allCases) { panel in
                    Toggle(panel.title, isOn: panels.toggleBinding(panel))
                }
            } label: {
                Label("Panels", systemImage: "square.grid.2x2")
                    .labelStyle(.iconOnly)
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Show or hide the floating panels")
            // Backspace: while a pen path is in progress it removes the
            // last placed anchor; otherwise it deletes the selected nodes.
            Button {
                if session.tool == .pen, !session.penAnchors.isEmpty {
                    session.penRemoveLastAnchor()
                } else {
                    session.deleteSelection()
                }
            } label: { EmptyView() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(
                    session.selection.isEmpty
                        && !(session.tool == .pen && !session.penAnchors.isEmpty))
                .frame(width: 0, height: 0)
                .opacity(0)
            // Return commits a live Free Distort, else finishes the pen
            // path OPEN.
            Button {
                if session.distort != nil {
                    session.commitDistort()
                } else {
                    session.finishPenPath(closed: false)
                }
            } label: { EmptyView() }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(
                    session.distort == nil
                        && !(session.tool == .pen && !session.penAnchors.isEmpty))
                .frame(width: 0, height: 0)
                .opacity(0)
            // Esc cancels a live Free Distort first, then an in-progress
            // pen path; otherwise it returns to Select.
            Button {
                if session.distort != nil {
                    session.cancelDistort()
                } else if session.tool == .pen, !session.penAnchors.isEmpty {
                    session.cancelPenPath()
                } else {
                    session.tool = .select
                }
            } label: { EmptyView() }
                .keyboardShortcut(.escape, modifiers: [])
                .frame(width: 0, height: 0)
                .opacity(0)
        }
        // Header controls stay neutral; only Save-when-dirty keeps the accent.
        .tint(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // Translucent, not opaque: the window's black glass reads through
        // the bar; the thin material + divider keep it legible.
        .background(.ultraThinMaterial)
        .background(ToolShortcutMonitor { session.tool = $0 })
    }

    /// Select / Rect / Ellipse / Line / Pen as a floating shelf centred at
    /// the bottom of the canvas — the same dark-glass chrome as the
    /// floating palettes (`FloatingToolPanel`), non-draggable. Illustrator's
    /// single letters (V/A, M, L, \, P) switch tools while no text field is
    /// being edited (see `ToolShortcutMonitor`); ⌘1–⌘5 always work; Esc and
    /// double-click return to Select.
    private var toolShelf: some View {
        HStack(spacing: 4) {
            shelfButton(.select, "cursorarrow", "Select", "V or ⌘1")
            shelfButton(.directSelect, "cursorarrow.motionlines", "Direct Select", "A")
            shelfButton(.rect, "square", "Rectangle", "M or ⌘2")
            shelfButton(.ellipse, "circle", "Ellipse", "L or ⌘3")
            shelfButton(.line, "line.diagonal", "Line", "\\ or ⌘4")
            shelfButton(.pen, "pencil.tip", "Pen", "P or ⌘5")
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Color.black.opacity(0.80), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.36), radius: 18, y: 8)
        .padding(.bottom, 16)
        .background(toolShortcuts)
    }

    private func shelfButton(
        _ tool: EditorSession.Tool, _ symbol: String, _ name: String, _ keys: String
    ) -> some View {
        let active = session.tool == tool
        return Button {
            session.tool = tool
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(active ? Color.fekthorAccent : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("\(name) (\(keys))")
        .accessibilityLabel(name)
        .accessibilityIdentifier("tool.\(tool.rawValue)")
    }

    private var toolShortcuts: some View {
        Group {
            Button { session.tool = .select } label: { EmptyView() }
                .keyboardShortcut("1", modifiers: .command)
            Button { session.tool = .rect } label: { EmptyView() }
                .keyboardShortcut("2", modifiers: .command)
            Button { session.tool = .ellipse } label: { EmptyView() }
                .keyboardShortcut("3", modifiers: .command)
            Button { session.tool = .line } label: { EmptyView() }
                .keyboardShortcut("4", modifiers: .command)
            Button { session.tool = .pen } label: { EmptyView() }
                .keyboardShortcut("5", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    /// The floating zoom/scale pill, top-centre of the canvas (ImageKid's
    /// viewport-toolbar spot): − / percent menu (50/100/200/400/Fit) / + /
    /// fit, on the same dark-glass chrome as the tool shelf. Non-draggable.
    /// ⌘− and ⌘= keep working from here.
    private var zoomPill: some View {
        HStack(spacing: 2) {
            Button { zoom = max(0.2, zoom / 1.25) } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .keyboardShortcut("-", modifiers: .command)
            .help("Zoom out (⌘−)")
            Menu {
                Button("50%") { zoom = 0.5 }
                Button("100%") { zoom = 1 }
                Button("200%") { zoom = 2 }
                Button("400%") { zoom = 4 }
                Divider()
                Button("Fit") {
                    zoom = 1
                    offset = .zero
                }
            } label: {
                Text("\(Int(zoom * 100))%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .frame(width: 48)
                    .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Zoom level")
            Button { zoom = min(64, zoom * 1.25) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .keyboardShortcut("=", modifiers: .command)
            .help("Zoom in (⌘+)")
            Divider().frame(height: 14)
            Button {
                zoom = 1
                offset = .zero
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .help("Fit (100%, centred)")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Color.black.opacity(0.80), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.36), radius: 18, y: 8)
    }
}

/// Illustrator's single-letter tool shortcuts, alive only while the editor is
/// on screen: V (and A, until a separate direct-selection tool exists) →
/// Select, M → Rectangle, L → Ellipse, \ → Line, P → Pen. A local keyDown
/// monitor that passes every event through untouched when it carries ⌘/⌥/⌃
/// (menu equivalents like ⌘P must win), when a text field is being edited
/// (the field editor is an NSTextView — letters must never steal keystrokes
/// from the style panel), or when the key is unmapped (so Esc/Return/Delete
/// pen handling is unaffected). Mapped letters switch the tool and are
/// consumed; switching away mid-pen-path finishes the path safely via the
/// tool's didSet.
private struct ToolShortcutMonitor: NSViewRepresentable {
    var onTool: (EditorSession.Tool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = MonitorView()
        view.onTool = onTool
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? MonitorView)?.onTool = onTool
    }

    final class MonitorView: NSView {
        var onTool: ((EditorSession.Tool) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty
                else { return event }
                if let responder = self.window?.firstResponder, responder is NSText {
                    return event
                }
                guard let letter = event.charactersIgnoringModifiers?.lowercased(),
                    let tool = Self.tool(for: letter)
                else { return event }
                self.onTool?(tool)
                return nil
            }
        }

        private static func tool(for letter: String) -> EditorSession.Tool? {
            switch letter {
            case "v": return .select
            case "a": return .directSelect
            case "m": return .rect
            case "l": return .ellipse
            case "\\": return .line
            case "p": return .pen
            default: return nil
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
