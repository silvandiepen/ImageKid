import AppKit
import BrushKit
import CoreGraphics
import ImageIO
import InkaKit
import SwiftUI
import UniformTypeIdentifiers

/// The macOS Inka session: the document, the live Metal renderer, the working
/// brush/colour, the active layer, and undo history. Committed strokes are
/// recorded onto the active layer (the non-destructive vector half of the
/// hybrid); the renderer's committed texture is rebuilt from the document after
/// every change, which is what makes undo, layer visibility and opacity work.
/// What a canvas drag does.
enum InkaTool: Equatable {
    case draw
    case eraser
    case eyedropper
    case move
}

/// The move tool's in-flight gesture.
enum SelectionTransform {
    case none, marquee, move, scale, rotate
}

@MainActor
final class InkaModel: ObservableObject {
    @Published var document: InkaDocument
    @Published var brush: Brush { didSet { syncRenderer() } }
    @Published var currentBrushID: String
    @Published var color: Color { didSet { syncRenderer() } }
    /// The layer strokes are painted onto and the Layers panel highlights.
    @Published var activeLayerID: UUID
    /// The open document's file, if any (title bar, plain Save).
    @Published var documentURL: URL?
    /// Bumped so undo/redo menu items refresh.
    @Published private(set) var historyToken = 0
    /// The active canvas tool (paint, erase, sample a colour, or move).
    @Published var tool: InkaTool = .draw {
        didSet {
            if tool != .move { clearSelection() }
            renderer?.eraseMode = (tool == .eraser)
        }
    }
    /// Recently used colours (most-recent first), in-memory for the session.
    @Published private(set) var recentColors: [String] = []

    /// Move-tool selection: the chosen strokes (active layer), their bounding box
    /// and the live marquee — all in canvas pixel space, for the overlay.
    @Published private(set) var selectedStrokeIDs: Set<UUID> = []
    @Published private(set) var selectionBounds: CGRect?
    @Published private(set) var marquee: CGRect?
    private var marqueeStart: CGPoint?
    // A transform gesture in flight: what it does, the pivot, the grab point, and
    // the selected strokes' original sample positions (so it rewrites from the
    // originals each step — no drift).
    private var transformKind: SelectionTransform = .none
    private var transformCenter: CGPoint = .zero
    private var transformStart: CGPoint = .zero
    private var transformOriginals: [UUID: [CGPoint]] = [:]

    let renderer: InkaCanvasRenderer?

    /// Set by the canvas view; asks the MTKView to redraw after a model-driven
    /// change (undo, layers, document open/new). Drawing is on-demand.
    var requestRedraw: (() -> Void)?

    private var undoStack: [InkaDocument] = []
    private var redoStack: [InkaDocument] = []
    private static let maxUndo = 40

    init(document: InkaDocument) {
        self.document = document
        self.brush = BrushLibrary.inkPen
        self.currentBrushID = BrushLibrary.inkPen.id
        self.color = Color(red: 0.1, green: 0.12, blue: 0.16)
        self.activeLayerID = document.layers.first?.id ?? UUID()
        self.renderer = InkaCanvasRenderer(canvasSize: document.size)
        renderer?.brushProvider = { [weak self] id in self?.document.brush(id: id) }
        renderer?.onCommitStroke = { [weak self] stroke in
            Task { @MainActor in self?.record(stroke) }
        }
        syncRenderer()
    }

    var currentColorRGBA: RGBA {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return RGBA(r: Double(ns.redComponent), g: Double(ns.greenComponent), b: Double(ns.blueComponent))
    }

    func syncRenderer() {
        renderer?.brush = brush
        renderer?.color = currentColorRGBA
    }

    func selectBrush(_ id: String) {
        currentBrushID = id
        brush = document.brush(id: id) ?? BrushLibrary.inkPen
    }

    // MARK: - Layers

    var activeIndex: Int {
        document.layers.firstIndex { $0.id == activeLayerID } ?? max(0, document.layers.count - 1)
    }

    private func record(_ stroke: BrushStroke) {
        snapshot()
        pushRecent(stroke.color.hex)
        let i = strokeTargetIndex()
        if case .strokes(var strokes) = document.layers[i].content {
            strokes.append(stroke)
            document.layers[i].content = .strokes(strokes)
        }
        rebuild()
    }

    /// The stroke layer to paint onto: the active layer if it takes strokes,
    /// else a new stroke layer above it.
    private func strokeTargetIndex() -> Int {
        let i = activeIndex
        if document.layers.indices.contains(i), document.layers[i].isVector,
            !document.layers[i].isLocked, document.layers[i].isVisible
        {
            return i
        }
        let layer = Layer(name: document.nextLayerName(), content: .strokes([]))
        document.layers.insert(layer, at: min(i + 1, document.layers.count))
        activeLayerID = layer.id
        return document.layers.firstIndex { $0.id == layer.id }!
    }

    func addLayer() {
        snapshot()
        let layer = Layer(name: document.nextLayerName(), content: .strokes([]))
        document.layers.insert(layer, at: min(activeIndex + 1, document.layers.count))
        activeLayerID = layer.id
        rebuild()
    }

    func deleteLayer(_ id: UUID) {
        guard document.layers.count > 1, let i = document.layers.firstIndex(where: { $0.id == id })
        else { return }
        snapshot()
        document.layers.remove(at: i)
        if activeLayerID == id {
            activeLayerID = document.layers[min(i, document.layers.count - 1)].id
        }
        rebuild()
    }

    func moveLayer(_ id: UUID, up: Bool) {
        guard let i = document.layers.firstIndex(where: { $0.id == id }) else { return }
        let j = up ? i + 1 : i - 1
        guard document.layers.indices.contains(j) else { return }
        snapshot()
        document.layers.swapAt(i, j)
        rebuild()
    }

    func setLayerVisible(_ id: UUID, _ visible: Bool) {
        guard let i = document.layers.firstIndex(where: { $0.id == id }) else { return }
        snapshot()
        document.layers[i].isVisible = visible
        rebuild()
    }

    func setLayerOpacity(_ id: UUID, _ opacity: Double) {
        guard let i = document.layers.firstIndex(where: { $0.id == id }) else { return }
        document.layers[i].opacity = opacity
        rebuild()  // live; the opacity slider coalesces its own undo via snapshotOnce
    }

    func renameLayer(_ id: UUID, to name: String) {
        guard let i = document.layers.firstIndex(where: { $0.id == id }) else { return }
        snapshot()
        document.layers[i].name = name
    }

    // MARK: - Undo / redo

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private func snapshot() {
        undoStack.append(document)
        if undoStack.count > Self.maxUndo { undoStack.removeFirst() }
        redoStack.removeAll()
        historyToken += 1
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document)
        document = previous
        if !document.layers.contains(where: { $0.id == activeLayerID }) {
            activeLayerID = document.layers.first?.id ?? activeLayerID
        }
        historyToken += 1
        rebuild()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        document = next
        historyToken += 1
        rebuild()
    }

    private func rebuild() {
        renderer?.rebuild(from: document)
        requestRedraw?()
    }

    // MARK: - Document lifecycle

    func newDocument(width: Int, height: Int) {
        document = .blank(width: width, height: height)
        activeLayerID = document.layers.first?.id ?? UUID()
        documentURL = nil
        undoStack.removeAll()
        redoStack.removeAll()
        historyToken += 1
        renderer?.resize(to: document.size)
        renderer?.fit()
        rebuild()
    }

    func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [inkaType]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
            let data = try? Data(contentsOf: url),
            let loaded = try? InkaWorkfile.decode(data)
        else { return }
        document = loaded
        activeLayerID = loaded.layers.first?.id ?? UUID()
        documentURL = url
        undoStack.removeAll()
        redoStack.removeAll()
        historyToken += 1
        renderer?.resize(to: document.size)
        renderer?.fit()
        rebuild()
    }

    func saveDocument() {
        if let url = documentURL { write(to: url); return }
        saveDocumentAs()
    }

    func saveDocumentAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [inkaType]
        panel.nameFieldStringValue = (documentURL?.deletingPathExtension().lastPathComponent ?? "Untitled") + ".inka"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        documentURL = url
        write(to: url)
    }

    private func write(to url: URL) {
        guard let data = try? InkaWorkfile.encode(document) else { return }
        try? data.write(to: url)
    }

    // MARK: - Export

    /// Flatten through the exact CPU rasterizer (honours per-layer opacity/blend)
    /// and write a PNG.
    func exportPNG() {
        guard let image = InkaRasterizer.flatten(document) ?? renderer?.committedImage() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = (documentURL?.deletingPathExtension().lastPathComponent ?? "Inka") + ".png"
        guard panel.runModal() == .OK, let url = panel.url,
            let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    func clearActiveLayer() {
        guard document.layers.indices.contains(activeIndex) else { return }
        snapshot()
        if document.layers[activeIndex].isVector {
            document.layers[activeIndex].content = .strokes([])
        }
        rebuild()
    }

    // MARK: - Colour & palette

    /// Set the working colour from an engine `RGBA` (eyedropper / swatch) and
    /// record it in the recents.
    func setColor(_ rgba: RGBA) {
        color = rgba.color
        pushRecent(rgba.hex)
    }

    /// Sample the committed canvas at a canvas point and adopt that colour.
    /// Returns false if the point missed the canvas or read transparent.
    @discardableResult
    func pickColor(at canvasPoint: CGPoint) -> Bool {
        guard let rgba = renderer?.sampleColor(at: canvasPoint), rgba.a > 0.01 else { return false }
        setColor(RGBA(r: rgba.r, g: rgba.g, b: rgba.b))
        tool = .draw  // one-shot, like most editors
        return true
    }

    func addCurrentSwatch() {
        let hex = currentColorRGBA.hex
        guard !document.palette.contains(hex) else { return }
        snapshot()
        document.palette.append(hex)
    }

    func removeSwatch(_ hex: String) {
        guard let i = document.palette.firstIndex(of: hex) else { return }
        snapshot()
        document.palette.remove(at: i)
    }

    func selectSwatch(_ hex: String) {
        guard let rgba = RGBA(hex: hex) else { return }
        setColor(rgba)
    }

    private func pushRecent(_ hex: String) {
        recentColors.removeAll { $0 == hex }
        recentColors.insert(hex, at: 0)
        if recentColors.count > 12 { recentColors.removeLast() }
    }

    // MARK: - Selection & transform (move tool)

    /// Grab radius / rotate-handle offset in canvas units (constant on screen).
    private var canvasScale: CGFloat {
        let s = renderer?.scale(in: renderer?.viewSize ?? .zero) ?? 1
        return s > 0 ? s : 1
    }
    private var grabRadiusCanvas: CGFloat { 13 / canvasScale }
    private var rotateHandleOffsetCanvas: CGFloat { 32 / canvasScale }

    /// The rotate handle's canvas point (above the selection's top edge), for the
    /// overlay and hit-testing. Nil when there is no selection.
    var rotateHandleCanvasPoint: CGPoint? {
        guard let b = selectionBounds else { return nil }
        return CGPoint(x: b.midX, y: b.minY - rotateHandleOffsetCanvas)
    }

    /// A canvas-space drag started: grab a handle (move / scale / rotate) on the
    /// current selection, or begin a fresh marquee.
    func selectionBegin(at p: CGPoint) {
        guard !selectedStrokeIDs.isEmpty, let b = selectionBounds else { startMarquee(p); return }
        let kind = handle(at: p, bounds: b)
        if kind == .marquee { startMarquee(p); return }
        transformKind = kind
        transformStart = p
        transformCenter = CGPoint(x: b.midX, y: b.midY)
        captureOriginals()
        snapshot()  // one undo step for the whole transform
    }

    private func startMarquee(_ p: CGPoint) {
        transformKind = .marquee
        marqueeStart = p
        marquee = CGRect(origin: p, size: .zero)
        selectedStrokeIDs = []
        selectionBounds = nil
    }

    private func handle(at p: CGPoint, bounds b: CGRect) -> SelectionTransform {
        let g = grabRadiusCanvas
        if let rh = rotateHandleCanvasPoint, hypot(p.x - rh.x, p.y - rh.y) <= g { return .rotate }
        let corners = [
            CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY),
            CGPoint(x: b.maxX, y: b.maxY), CGPoint(x: b.minX, y: b.maxY),
        ]
        if corners.contains(where: { hypot($0.x - p.x, $0.y - p.y) <= g }) { return .scale }
        if b.insetBy(dx: -g / 2, dy: -g / 2).contains(p) { return .move }
        return .marquee
    }

    func selectionUpdate(to p: CGPoint) {
        let c = transformCenter
        switch transformKind {
        case .marquee:
            guard let start = marqueeStart else { return }
            marquee = CGRect(
                x: min(start.x, p.x), y: min(start.y, p.y),
                width: abs(p.x - start.x), height: abs(p.y - start.y))
        case .move:
            let dx = p.x - transformStart.x, dy = p.y - transformStart.y
            applyFromOriginals { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        case .scale:
            let d0 = max(1e-3, hypot(transformStart.x - c.x, transformStart.y - c.y))
            let f = max(0.05, min(20, hypot(p.x - c.x, p.y - c.y) / d0))
            applyFromOriginals { CGPoint(x: c.x + ($0.x - c.x) * f, y: c.y + ($0.y - c.y) * f) }
        case .rotate:
            let a = atan2(p.y - c.y, p.x - c.x) - atan2(transformStart.y - c.y, transformStart.x - c.x)
            let ca = cos(a), sa = sin(a)
            applyFromOriginals {
                let dx = $0.x - c.x, dy = $0.y - c.y
                return CGPoint(x: c.x + dx * ca - dy * sa, y: c.y + dx * sa + dy * ca)
            }
        case .none:
            break
        }
    }

    func selectionEnd() {
        if transformKind == .marquee, let rect = marquee {
            selectStrokes(in: rect)
            marquee = nil
            marqueeStart = nil
        } else {
            recomputeSelectionBounds()
        }
        transformKind = .none
        transformOriginals = [:]
    }

    /// Capture the selected strokes' sample positions so a transform rewrites
    /// from the originals each step (no compounding drift).
    private func captureOriginals() {
        transformOriginals = [:]
        guard document.layers.indices.contains(activeIndex),
            case .strokes(let strokes) = document.layers[activeIndex].content
        else { return }
        for st in strokes where selectedStrokeIDs.contains(st.id) {
            transformOriginals[st.id] = st.input.samples.map(\.position)
        }
    }

    private func applyFromOriginals(_ f: (CGPoint) -> CGPoint) {
        guard document.layers.indices.contains(activeIndex),
            case .strokes(var strokes) = document.layers[activeIndex].content
        else { return }
        for k in strokes.indices where selectedStrokeIDs.contains(strokes[k].id) {
            guard let orig = transformOriginals[strokes[k].id] else { continue }
            for i in strokes[k].input.samples.indices where i < orig.count {
                strokes[k].input.samples[i].position = f(orig[i])
            }
        }
        document.layers[activeIndex].content = .strokes(strokes)
        recomputeSelectionBounds()
        rebuild()
    }

    /// Nudge the selection by whole canvas pixels (arrow keys).
    func nudgeSelection(dx: CGFloat, dy: CGFloat) {
        guard !selectedStrokeIDs.isEmpty else { return }
        snapshot()
        translateSelection(dx: dx, dy: dy)
    }

    func deleteSelection() {
        guard !selectedStrokeIDs.isEmpty,
            document.layers.indices.contains(activeIndex),
            case .strokes(var strokes) = document.layers[activeIndex].content
        else { return }
        snapshot()
        strokes.removeAll { selectedStrokeIDs.contains($0.id) }
        document.layers[activeIndex].content = .strokes(strokes)
        clearSelection()
        rebuild()
    }

    func clearSelection() {
        selectedStrokeIDs = []
        selectionBounds = nil
        marquee = nil
        marqueeStart = nil
        transformKind = .none
        transformOriginals = [:]
    }

    private func translateSelection(dx: CGFloat, dy: CGFloat) {
        guard dx != 0 || dy != 0, document.layers.indices.contains(activeIndex),
            case .strokes(var strokes) = document.layers[activeIndex].content
        else { return }
        for k in strokes.indices where selectedStrokeIDs.contains(strokes[k].id) {
            for s in strokes[k].input.samples.indices {
                strokes[k].input.samples[s].position.x += dx
                strokes[k].input.samples[s].position.y += dy
            }
        }
        document.layers[activeIndex].content = .strokes(strokes)
        selectionBounds = selectionBounds?.offsetBy(dx: dx, dy: dy)
        rebuild()
    }

    private func selectStrokes(in rect: CGRect) {
        guard document.layers.indices.contains(activeIndex),
            case .strokes(let strokes) = document.layers[activeIndex].content
        else { selectedStrokeIDs = []; selectionBounds = nil; return }
        var ids: Set<UUID> = []
        var union: CGRect?
        for st in strokes {
            let bb = strokeBounds(st)
            if bb.intersects(rect) {
                ids.insert(st.id)
                union = union?.union(bb) ?? bb
            }
        }
        selectedStrokeIDs = ids
        selectionBounds = union
    }

    private func recomputeSelectionBounds() {
        guard document.layers.indices.contains(activeIndex),
            case .strokes(let strokes) = document.layers[activeIndex].content
        else { return }
        var union: CGRect?
        for st in strokes where selectedStrokeIDs.contains(st.id) {
            let bb = strokeBounds(st)
            union = union?.union(bb) ?? bb
        }
        selectionBounds = union
    }

    /// A stroke's canvas-space bounds, padded by the brush radius.
    private func strokeBounds(_ s: BrushStroke) -> CGRect {
        let pts = s.input.samples.map(\.position)
        guard let first = pts.first else { return .zero }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in pts {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        let pad = (document.brush(id: s.brushID)?.size ?? brush.size) / 2 + 1
        return CGRect(
            x: minX - pad, y: minY - pad,
            width: (maxX - minX) + 2 * pad, height: (maxY - minY) + 2 * pad)
    }

    // MARK: - .inkbrush import / export

    func saveBrush() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [inkbrushType]
        panel.nameFieldStringValue = brush.name + ".inkbrush"
        guard panel.runModal() == .OK, let url = panel.url, let data = try? InkBrushCoding.encode(brush)
        else { return }
        try? data.write(to: url)
    }

    func loadBrush() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [inkbrushType]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
            let data = try? Data(contentsOf: url), let loaded = try? InkBrushCoding.decode(data)
        else { return }
        if !document.brushes.contains(where: { $0.id == loaded.id }) {
            document.brushes.append(loaded)
        }
        brush = loaded
        currentBrushID = loaded.id
    }

    private var inkbrushType: UTType { UTType(filenameExtension: "inkbrush") ?? .json }
    private var inkaType: UTType { UTType(filenameExtension: "inka") ?? .json }
}
