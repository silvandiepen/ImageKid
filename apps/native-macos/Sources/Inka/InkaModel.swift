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
