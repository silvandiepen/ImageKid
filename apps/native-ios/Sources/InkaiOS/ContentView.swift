import BrushKit
import ImageIO
import ImageKidKit
import InkaKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Inka iPad root: the shared `HomeScreen` until a canvas is open, then the Metal
/// canvas with the family's floating panels (rail + dockable Brushes/Brush/Layers
/// panels from ImageKidKit) — the same dock as the macOS app. Drawing uses the
/// Pencil (or a finger); two fingers pan, pinch zooms, a two-finger tap undoes
/// and a three-finger tap redoes.
struct ContentView: View {
    @StateObject private var model = InkaModel(document: .blank(width: 2048, height: 1536))
    @StateObject private var dock = PanelDockController(PanelDockModel<InkaPanel>.makeDefault())
    @State private var hasCanvas = false
    @State private var shareImage: UIImage?
    @State private var showOpen = false
    @State private var showSave = false
    // Encoded blobs captured at present-time so the exporters don't re-encode
    // the whole document on every SwiftUI render.
    @State private var saveInkaData = Data()
    @State private var saveBrushData = Data()

    var body: some View {
        Group {
            if hasCanvas { canvas } else { home }
        }
        .onAppear {
            // Test/debug hook: `--open-canvas` boots straight onto a canvas,
            // since synthetic touches can't drive the home cards under sandbox.
            if CommandLine.arguments.contains("--open-canvas") {
                newCanvas(width: 2048, height: 1536)
            }
        }
    }

    private var home: some View {
        HomeScreen(
            title: "Inka",
            subtitle: "Drawing and illustration, with a serious brush engine.",
            footnote: "a new canvas to start painting",
            character: nil,
            accent: .accentColor,
            actions: [
                HomeAction(
                    id: "inka.newCanvas", icon: "paintbrush.pointed.fill",
                    title: "New Canvas", subtitle: "2048 × 1536",
                    action: { newCanvas(width: 2048, height: 1536) }),
                HomeAction(
                    id: "inka.square", icon: "square",
                    title: "Square", subtitle: "1536 × 1536",
                    action: { newCanvas(width: 1536, height: 1536) }),
                HomeAction(
                    id: "inka.open", icon: "folder",
                    title: "Open…", subtitle: "an .inka file",
                    action: { showOpen = true; hasCanvas = true }),
            ],
            recents: { EmptyView() })
    }

    private func newCanvas(width: Int, height: Int) {
        model.newDocument(width: width, height: height)
        hasCanvas = true
    }

    private var canvas: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            InkaCanvasView(model: model)
                .background(Color(white: 0.28))
                .overlay {
                    GeometryReader { geo in
                        InkaSelectionOverlay(model: model, viewSize: geo.size)
                    }
                    .allowsHitTesting(false)
                }
                .overlay(alignment: .topTrailing) { panelLayer.padding(8) }
        }
        .sheet(item: Binding(
            get: { shareImage.map(ShareItem.init) },
            set: { _ in shareImage = nil })
        ) { item in
            ShareSheet(items: [item.image])
        }
        // .inka open / save
        .fileImporter(isPresented: $showOpen, allowedContentTypes: [inkaType, .data]) { result in
            if case .success(let url) = result { openInka(url) }
        }
        .fileExporter(
            isPresented: $showSave,
            document: InkaDataDocument(data: saveInkaData),
            contentType: .data, defaultFilename: "Untitled.inka"
        ) { _ in }
        // .inkbrush import / export (driven by the Brush panel)
        .fileImporter(
            isPresented: $model.brushImportRequested,
            allowedContentTypes: [inkbrushType, .data]
        ) { result in
            if case .success(let url) = result { openBrush(url) }
        }
        .fileExporter(
            isPresented: $model.brushExportRequested,
            document: InkaDataDocument(data: saveBrushData),
            contentType: .data, defaultFilename: model.brush.name + ".inkbrush"
        ) { _ in }
        .onChange(of: model.brushExportRequested) { _, now in
            if now { saveBrushData = model.brushData() ?? Data() }
        }
        // Import an image as a layer
        .fileImporter(
            isPresented: $model.imageImportRequested, allowedContentTypes: [.image]
        ) { result in
            if case .success(let url) = result { importImage(url) }
        }
    }

    private func importImage(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
            let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { return }
        model.importImage(cg)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button { hasCanvas = false } label: { Image(systemName: "chevron.left") }
            Divider().frame(height: 22)

            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.canUndo)
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!model.canRedo)
            Divider().frame(height: 22)

            ColorPicker("", selection: $model.color, supportsOpacity: false).labelsHidden()
            Button { model.tool = model.tool == .eraser ? .draw : .eraser } label: {
                Image(systemName: "eraser")
            }
            .tint(model.tool == .eraser ? .accentColor : nil)
            Button { model.tool = model.tool == .eyedropper ? .draw : .eyedropper } label: {
                Image(systemName: "eyedropper")
            }
            .tint(model.tool == .eyedropper ? .accentColor : nil)
            Button { model.tool = model.tool == .move ? .draw : .move } label: {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
            }
            .tint(model.tool == .move ? .accentColor : nil)
            if model.tool == .move, !model.selectedStrokeIDs.isEmpty {
                Button(role: .destructive) { model.deleteSelection() } label: {
                    Image(systemName: "trash.slash")
                }
            }
            Slider(value: sizeBinding, in: 1...200).frame(width: 160)
            Text("\(Int(model.brush.size))")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)

            Spacer()

            Button { model.renderer?.fit() } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            Menu {
                Button("Flip Horizontal") { model.renderer?.flipX.toggle() }
                Button("Flip Vertical") { model.renderer?.flipY.toggle() }
            } label: {
                Image(systemName: "arrow.left.arrow.right")
            }
            Button { model.clearActiveLayer() } label: { Image(systemName: "trash") }
            Divider().frame(height: 22)
            Button { model.imageImportRequested = true } label: { Image(systemName: "photo.badge.plus") }
            Button { showOpen = true } label: { Image(systemName: "folder") }
            Button { saveInkaData = model.inkaData() ?? Data(); showSave = true } label: {
                Image(systemName: "square.and.arrow.down")
            }
            Button { shareImage = model.exportImage() } label: {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var panelLayer: some View {
        HStack(alignment: .top, spacing: 8) {
            GeometryReader { geo in
                let size = geo.size
                ZStack(alignment: .topLeading) {
                    if dock.model.isExpanded(.brushes) {
                        InkaBrushesPanel(
                            model: model, offset: dock.offsetBinding(.brushes, in: size),
                            size: dock.model.sizeBinding(.brushes),
                            onMinimize: { dock.model.minimize(.brushes) },
                            stackEdges: dock.model.stackEdges(of: .brushes),
                            dockEdges: dock.model.dockEdges(of: .brushes, in: size),
                            isStackFollower: dock.model.isStackFollower(.brushes),
                            onDragChanged: { dock.dragChanged(.brushes, translation: $0, in: size) },
                            onDragEnded: { _ in dock.dragEnded(.brushes, in: size) })
                    }
                    if dock.model.isExpanded(.brush) {
                        InkaBrushPanel(
                            model: model, offset: dock.offsetBinding(.brush, in: size),
                            size: dock.model.sizeBinding(.brush),
                            onMinimize: { dock.model.minimize(.brush) },
                            stackEdges: dock.model.stackEdges(of: .brush),
                            dockEdges: dock.model.dockEdges(of: .brush, in: size),
                            isStackFollower: dock.model.isStackFollower(.brush),
                            onDragChanged: { dock.dragChanged(.brush, translation: $0, in: size) },
                            onDragEnded: { _ in dock.dragEnded(.brush, in: size) })
                    }
                    if dock.model.isExpanded(.colours) {
                        InkaColoursPanel(
                            model: model, offset: dock.offsetBinding(.colours, in: size),
                            size: dock.model.sizeBinding(.colours),
                            onMinimize: { dock.model.minimize(.colours) },
                            stackEdges: dock.model.stackEdges(of: .colours),
                            dockEdges: dock.model.dockEdges(of: .colours, in: size),
                            isStackFollower: dock.model.isStackFollower(.colours),
                            onDragChanged: { dock.dragChanged(.colours, translation: $0, in: size) },
                            onDragEnded: { _ in dock.dragEnded(.colours, in: size) })
                    }
                    if dock.model.isExpanded(.layers) {
                        InkaLayersPanel(
                            model: model, offset: dock.offsetBinding(.layers, in: size),
                            size: dock.model.sizeBinding(.layers),
                            onMinimize: { dock.model.minimize(.layers) },
                            stackEdges: dock.model.stackEdges(of: .layers),
                            dockEdges: dock.model.dockEdges(of: .layers, in: size),
                            isStackFollower: dock.model.isStackFollower(.layers),
                            onDragChanged: { dock.dragChanged(.layers, translation: $0, in: size) },
                            onDragEnded: { _ in dock.dragEnded(.layers, in: size) })
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .animation(.spring(response: 0.34, dampingFraction: 0.82), value: dock.model.presented)
                .animation(.spring(response: 0.34, dampingFraction: 0.82), value: dock.model.minimized)
                .onAppear {
                    dock.model.migrateLegacyPositions(in: size)
                    dock.placePending(in: size)
                    rightAlignDefaults(in: size)
                }
                .onChange(of: size) {
                    dock.model.migrateLegacyPositions(in: size)
                    rightAlignDefaults(in: size)
                }
                .onChange(of: dock.model.needsPlacement) { dock.placePending(in: size) }
            }
            PanelDockRail(model: dock.model, axis: .vertical)
                .panelRailChrome()
                .zIndex(1)
        }
    }

    /// One-time: park the panels against the right edge (Inka's default is a
    /// right-hand tool column), matching the macOS app.
    private func rightAlignDefaults(in size: CGSize) {
        // v2: Colours joined the panel set; it opens on demand from the rail.
        let key = "inka.ipad.paneldock.rightDefault.v2"
        guard size.width > 0, !UserDefaults.standard.bool(forKey: key) else { return }
        let x = size.width - InkaPanel.panelWidth - PanelPlacement.margin
        var y: CGFloat = 8
        for panel in [InkaPanel.brushes, .brush, .layers] {
            dock.model.setPosition(panel, to: CGSize(width: x, height: y), in: size)
            y += dock.model.size(panel).height + PanelPlacement.gap
        }
        dock.model.setPosition(.colours, to: CGSize(width: x, height: 8), in: size)
        UserDefaults.standard.set(true, forKey: key)
    }

    private func openInka(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        model.loadInka(data)
        hasCanvas = true
    }

    private func openBrush(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        model.loadBrush(data)
    }

    private var sizeBinding: Binding<Double> {
        Binding(get: { model.brush.size }, set: { model.brush.size = $0 })
    }

    private var inkaType: UTType { UTType(filenameExtension: "inka") ?? .data }
    private var inkbrushType: UTType { UTType(filenameExtension: "inkbrush") ?? .data }
}

/// Draws the move tool's live marquee and the current selection's bounding box,
/// mapping canvas-space rects through the renderer transform (rotated with the
/// canvas) to view points.
struct InkaSelectionOverlay: View {
    @ObservedObject var model: InkaModel
    let viewSize: CGSize

    var body: some View {
        Canvas { ctx, _ in
            guard let r = model.renderer else { return }
            func path(_ rect: CGRect) -> Path {
                let c = r.viewCorners(ofCanvasRect: rect, in: viewSize)
                var p = Path()
                p.move(to: c[0])
                p.addLine(to: c[1]); p.addLine(to: c[2]); p.addLine(to: c[3])
                p.closeSubpath()
                return p
            }
            func handleRect(_ c: CGPoint) -> Path {
                Path(CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12))
            }
            if let b = model.selectionBounds, !model.selectedStrokeIDs.isEmpty {
                let pth = path(b)
                ctx.fill(pth, with: .color(.accentColor.opacity(0.08)))
                ctx.stroke(
                    pth, with: .color(.accentColor),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                let corners = r.viewCorners(ofCanvasRect: b, in: viewSize)
                for c in corners { ctx.fill(handleRect(c), with: .color(.accentColor)) }
                if let rc = model.rotateHandleCanvasPoint {
                    let rv = r.viewPoint(fromCanvas: rc, in: viewSize)
                    let topMid = CGPoint(x: (corners[0].x + corners[1].x) / 2, y: (corners[0].y + corners[1].y) / 2)
                    var line = Path()
                    line.move(to: topMid)
                    line.addLine(to: rv)
                    ctx.stroke(line, with: .color(.accentColor), lineWidth: 1)
                    ctx.fill(Path(ellipseIn: CGRect(x: rv.x - 7, y: rv.y - 7, width: 14, height: 14)), with: .color(.accentColor))
                }
            }
            if let m = model.marquee {
                ctx.stroke(
                    path(m), with: .color(.white.opacity(0.9)),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
    }
}

/// A minimal `FileDocument` that carries raw bytes, so the SwiftUI file exporter
/// can write `.inka` / `.inkbrush` blobs the model already encoded.
struct InkaDataDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct ShareItem: Identifiable {
    let id = UUID()
    let image: UIImage
    init(_ image: UIImage) { self.image = image }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
