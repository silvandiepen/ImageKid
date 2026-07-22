import FekthorKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = ConversionModel()
    @StateObject private var workspaceSession = WorkspaceSession()
    @State private var editorSession: EditorSession? = nil
    @State private var showInspector = true
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var compareMode: CompareMode = .split
    /// When a raster is dropped on the gallery, the trace flow targets the
    /// workspace: the result saves into this category under this name.
    @State private var traceTarget: WorkspaceTraceTarget? = nil

    struct WorkspaceTraceTarget {
        var category: String
        var name: String
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
                        onOpenEntry: { openEntry($0) },
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
            .navigationTitle("Fekthor")
            .toolbar { toolbarContent }
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
            .onChange(of: model.imageGeneration) { _, _ in
                zoom = 1
                offset = .zero
            }
            .onAppear { model.loadLaunchArgumentIfPresent() }
            .onReceive(NotificationCenter.default.publisher(for: .fekthorNewFile)) { _ in
                newFile()
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
                editorSession = nil
                model.openPanel()
            }
            .background(objectCommandListeners)
        }
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

    private func newFile() {
        editorSession = EditorSession.blank(size: 72)
        zoom = 1
        offset = .zero
    }

    /// One Open for everything: svg/fekthor go to the editor, rasters to trace.
    private func openAny() {
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
        if workspaceSession.openPanel() { enterWorkspaceMode() }
    }

    private func newWorkspace() {
        if workspaceSession.newWorkspace() { enterWorkspaceMode() }
    }

    private func openRecentWorkspace(_ recent: RecentWorkspace) {
        if workspaceSession.openRecent(recent) { enterWorkspaceMode() }
    }

    /// Gallery double-click / Open in Editor: straight into the editor; the
    /// editor's Back returns to the gallery (the workspace stays open).
    private func openEntry(_ entry: IconEntry) {
        do {
            editorSession = try EditorSession.open(url: entry.url)
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

    var body: some View {
        ZStack {
            Rectangle().fill(Color(nsColor: .windowBackgroundColor))
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
                    homeCard(
                        icon: "square.grid.3x3.square",
                        title: "New Workspace",
                        subtitle: "An icon library —\na .fekthor workfile over\na folder of SVGs.",
                        enabled: true
                    ) {
                        onNewWorkspace()
                    }
                    homeCard(
                        icon: "wand.and.rays",
                        title: "Vectorize Image",
                        subtitle: "Trace a PNG or photo\ninto editable vectors.",
                        enabled: true
                    ) {
                        model.openPanel()
                    }
                }
                HStack(spacing: 20) {
                    Button("Open a file…", action: onOpen)
                        .buttonStyle(.link)
                    Button("Open Workspace…", action: onOpenWorkspace)
                        .buttonStyle(.link)
                }
                if !recents.isEmpty {
                    VStack(spacing: 4) {
                        Text("Recent workspaces")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(recents.prefix(4)) { recent in
                            Button {
                                onOpenRecent(recent)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder")
                                    Text(recent.name)
                                    Text(recent.path)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(maxWidth: 320)
                                }
                            }
                            .buttonStyle(.link)
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
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 14).strokeBorder(.quaternary))
        }
        .buttonStyle(.plain)
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
                            Button(model.modelDownloading ? "Downloading…" : "Get model (33 MB)") {
                                model.downloadEnhanceModel()
                            }
                            .disabled(model.modelDownloading)
                        }
                        .help("Downloads the Real-ESRGAN model once from models-data.hakobs.com; it runs fully on-device.")
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
    var onClose: () -> Void

    @State private var showStylePanel = true

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    EditorCanvasView(session: session, zoom: $zoom, offset: $offset)
                        .overlay(
                            TrackpadCatcher(
                                onPan: { dx, dy in
                                    offset = CGSize(
                                        width: offset.width + dx, height: offset.height + dy)
                                },
                                onZoom: { m in zoom = min(64, max(0.2, zoom * (1 + m))) },
                                onDoubleClick: { _ in
                                    // Double-click leaves a drawing tool;
                                    // in Select it keeps its zoom meaning.
                                    if session.tool != .select {
                                        session.tool = .select
                                    } else {
                                        zoom = min(64, zoom * 1.6)
                                    }
                                }
                            )
                        )
                    editorZoomControls
                }
                if showStylePanel {
                    Divider()
                    EditorStylePanel(session: session)
                }
            }
            Divider()
            HStack {
                Text(session.status).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Text("\(session.document.nodes.count) nodes")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                onClose()
            } label: {
                Label(backLabel, systemImage: "chevron.left")
            }
            Text(session.fileURL?.lastPathComponent ?? "Untitled")
                .font(.headline)
            if session.dirty {
                Circle().fill(.orange).frame(width: 7, height: 7)
            }
            toolPicker
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
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!session.canUndo)
            Button {
                session.save()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            Button {
                showStylePanel.toggle()
            } label: {
                Label("Style", systemImage: "sidebar.trailing")
            }
            // Backspace deletes selected nodes.
            Button { session.deleteSelection() } label: { EmptyView() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(session.selection.isEmpty)
                .frame(width: 0, height: 0)
                .opacity(0)
            // Esc returns to the Select tool.
            Button { session.tool = .select } label: { EmptyView() }
                .keyboardShortcut(.escape, modifiers: [])
                .frame(width: 0, height: 0)
                .opacity(0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Select / Rect / Ellipse / Line. ⌘1–⌘4 switch tools (plain letters
    /// would steal keystrokes from the panel's text fields); Esc and
    /// double-click return to Select.
    private var toolPicker: some View {
        Picker("", selection: $session.tool) {
            Image(systemName: "cursorarrow").tag(EditorSession.Tool.select)
                .help("Select (⌘1)")
            Image(systemName: "square").tag(EditorSession.Tool.rect)
                .help("Rectangle (⌘2)")
            Image(systemName: "circle").tag(EditorSession.Tool.ellipse)
                .help("Ellipse (⌘3)")
            Image(systemName: "line.diagonal").tag(EditorSession.Tool.line)
                .help("Line (⌘4)")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 150)
        .background(toolShortcuts)
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
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    private var editorZoomControls: some View {
        HStack(spacing: 2) {
            Button { zoom = max(0.2, zoom / 1.25) } label: { Image(systemName: "minus") }
                .keyboardShortcut("-", modifiers: .command)
            Text("\(Int(zoom * 100))%").font(.callout.monospacedDigit()).frame(width: 56)
            Button { zoom = min(64, zoom * 1.25) } label: { Image(systemName: "plus") }
                .keyboardShortcut("=", modifiers: .command)
            Divider().frame(height: 16)
            Button {
                zoom = 1
                offset = .zero
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.quaternary))
        .padding(.bottom, 12)
    }
}
