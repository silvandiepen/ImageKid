import AppKit
import BrushKit
import CoreGraphics
import ImageIO
import InkaKit
import SwiftUI
import UniformTypeIdentifiers

/// The macOS Inka session: the document, the live Metal renderer, and the
/// current brush/size/colour the canvas draws with. Committed strokes are
/// recorded onto the active layer (the non-destructive vector half of the
/// hybrid) as they finish.
@MainActor
final class InkaModel: ObservableObject {
    @Published var document: InkaDocument
    /// The working brush — a live, editable copy the canvas paints with and the
    /// brush editor tweaks. Selecting a preset replaces it; edits do not mutate
    /// the document's preset table until saved.
    @Published var brush: Brush {
        didSet { syncRenderer() }
    }
    /// Which preset the working brush came from (toolbar highlight).
    @Published var currentBrushID: String
    @Published var color: Color {
        didSet { syncRenderer() }
    }

    /// The live renderer; nil only if Metal is unavailable.
    let renderer: InkaCanvasRenderer?

    init(document: InkaDocument) {
        self.document = document
        self.brush = BrushLibrary.inkPen
        self.currentBrushID = BrushLibrary.inkPen.id
        self.color = Color(red: 0.1, green: 0.12, blue: 0.16)
        self.renderer = InkaCanvasRenderer(canvasSize: document.size)
        renderer?.onCommitStroke = { [weak self] stroke in
            Task { @MainActor in self?.record(stroke) }
        }
        renderer?.brush = brush
        renderer?.color = currentColorRGBA
    }

    var currentColorRGBA: RGBA {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return RGBA(
            r: Double(ns.redComponent), g: Double(ns.greenComponent),
            b: Double(ns.blueComponent))
    }

    /// Push the working brush/colour into the renderer.
    func syncRenderer() {
        renderer?.brush = brush
        renderer?.color = currentColorRGBA
    }

    func selectBrush(_ id: String) {
        currentBrushID = id
        brush = document.brush(id: id) ?? BrushLibrary.inkPen
    }

    // MARK: - .inkbrush import / export

    /// Save the working brush as an `.inkbrush` file.
    func saveBrush() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [inkbrushType]
        panel.nameFieldStringValue = brush.name + ".inkbrush"
        guard panel.runModal() == .OK, let url = panel.url,
            let data = try? InkBrushCoding.encode(brush)
        else { return }
        try? data.write(to: url)
    }

    /// Load an `.inkbrush`, make it the working brush and add it to the document.
    func loadBrush() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [inkbrushType]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
            let data = try? Data(contentsOf: url),
            let loaded = try? InkBrushCoding.decode(data)
        else { return }
        if !document.brushes.contains(where: { $0.id == loaded.id }) {
            document.brushes.append(loaded)
        }
        brush = loaded
        currentBrushID = loaded.id
    }

    private var inkbrushType: UTType {
        UTType(filenameExtension: "inkbrush") ?? .json
    }

    /// Append a finished stroke to the top stroke layer (create one if the top
    /// layer is not a stroke layer).
    private func record(_ stroke: BrushStroke) {
        if let index = document.layers.lastIndex(where: { $0.isVector }),
            case .strokes(var strokes) = document.layers[index].content
        {
            strokes.append(stroke)
            document.layers[index].content = .strokes(strokes)
        } else {
            document.layers.append(
                Layer(name: document.nextLayerName(), content: .strokes([stroke])))
        }
    }

    // MARK: - Export

    /// Flatten the committed canvas and write a PNG via a save panel.
    func exportPNG() {
        guard let image = renderer?.committedImage() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Inka.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard
            let dest = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    func clearCanvas() {
        renderer?.clear()
        for i in document.layers.indices where document.layers[i].isVector {
            document.layers[i].content = .strokes([])
        }
    }
}
