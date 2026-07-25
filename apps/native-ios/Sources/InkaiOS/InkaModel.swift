import BrushKit
import CoreGraphics
import ImageIO
import InkaKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The iPad Inka session: the document, the live Metal renderer, the working
/// brush/colour, the active layer, and undo history. Mirrors the macOS model so
/// both surfaces behave identically. Committed strokes are recorded onto the
/// active layer; the renderer's committed texture is rebuilt from the document
/// after every change, which is what makes undo, layer visibility and opacity
/// work. File open/save is driven by the SwiftUI file importer/exporter in
/// `ContentView` via the `Data` helpers here.
/// What a canvas drag does.
enum InkaTool: Equatable {
    case draw
    case eraser
    case eyedropper
    case move
}

@MainActor
final class InkaModel: ObservableObject {
    @Published var document: InkaDocument
    @Published var brush: Brush { didSet { syncRenderer() } }
    @Published var currentBrushID: String
    @Published var color: Color { didSet { syncRenderer() } }
    /// The layer strokes are painted onto and the Layers panel highlights.
    @Published var activeLayerID: UUID
    /// Bumped so undo/redo controls refresh.
    @Published private(set) var historyToken = 0

    /// File-picker intents, presented by `ContentView` (SwiftUI importers can
    /// only attach to a view, so the panels flip these flags).
    @Published var brushImportRequested = false
    @Published var brushExportRequested = false

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
    private var moveLast: CGPoint?
    private var movingSelection = false

    let renderer: InkaCanvasRenderer?

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

    /// The brush size, kept as a convenience for the compact toolbar slider.
    var size: Double {
        get { brush.size }
        set { brush.size = newValue }
    }

    var currentColorRGBA: RGBA {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return RGBA(r: Double(r), g: Double(g), b: Double(b))
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
        rebuild()
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

    private func rebuild() { renderer?.rebuild(from: document) }

    // MARK: - Document lifecycle

    func newDocument(width: Int, height: Int) {
        document = .blank(width: width, height: height)
        activeLayerID = document.layers.first?.id ?? UUID()
        undoStack.removeAll()
        redoStack.removeAll()
        historyToken += 1
        renderer?.resize(to: document.size)
        renderer?.fit()
        rebuild()
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

    func setColor(_ rgba: RGBA) {
        color = rgba.color
        pushRecent(rgba.hex)
    }

    /// Sample the committed canvas at a canvas point and adopt that colour.
    @discardableResult
    func pickColor(at canvasPoint: CGPoint) -> Bool {
        guard let rgba = renderer?.sampleColor(at: canvasPoint), rgba.a > 0.01 else { return false }
        setColor(RGBA(r: rgba.r, g: rgba.g, b: rgba.b))
        tool = .draw
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

    // MARK: - Selection & move (move tool)

    func selectionBegin(at p: CGPoint) {
        if !selectedStrokeIDs.isEmpty, let b = selectionBounds, b.contains(p) {
            movingSelection = true
            moveLast = p
            snapshot()
        } else {
            movingSelection = false
            marqueeStart = p
            marquee = CGRect(origin: p, size: .zero)
            selectedStrokeIDs = []
            selectionBounds = nil
        }
    }

    func selectionUpdate(to p: CGPoint) {
        if movingSelection {
            guard let last = moveLast else { return }
            translateSelection(dx: p.x - last.x, dy: p.y - last.y)
            moveLast = p
        } else if let start = marqueeStart {
            marquee = CGRect(
                x: min(start.x, p.x), y: min(start.y, p.y),
                width: abs(p.x - start.x), height: abs(p.y - start.y))
        }
    }

    func selectionEnd() {
        if movingSelection {
            movingSelection = false
            moveLast = nil
            recomputeSelectionBounds()
        } else if let rect = marquee {
            selectStrokes(in: rect)
            marquee = nil
            marqueeStart = nil
        }
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
        movingSelection = false
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

    // MARK: - .inka document data (driven by the file importer/exporter)

    func inkaData() -> Data? { try? InkaWorkfile.encode(document) }

    func loadInka(_ data: Data) {
        guard let loaded = try? InkaWorkfile.decode(data) else { return }
        document = loaded
        activeLayerID = loaded.layers.first?.id ?? UUID()
        undoStack.removeAll()
        redoStack.removeAll()
        historyToken += 1
        renderer?.resize(to: document.size)
        renderer?.fit()
        rebuild()
    }

    // MARK: - .inkbrush brush data

    func brushData() -> Data? { try? InkBrushCoding.encode(brush) }

    func loadBrush(_ data: Data) {
        guard let loaded = try? InkBrushCoding.decode(data) else { return }
        if !document.brushes.contains(where: { $0.id == loaded.id }) {
            document.brushes.append(loaded)
        }
        brush = loaded
        currentBrushID = loaded.id
    }

    // MARK: - Export

    /// Flatten through the exact CPU rasterizer (honours per-layer opacity/blend)
    /// and return a UIImage for the share sheet.
    func exportImage() -> UIImage? {
        guard let cg = InkaRasterizer.flatten(document) ?? renderer?.committedImage() else { return nil }
        return UIImage(cgImage: cg)
    }
}
