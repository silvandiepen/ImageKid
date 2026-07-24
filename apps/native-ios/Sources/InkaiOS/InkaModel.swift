import BrushKit
import CoreGraphics
import ImageIO
import InkaKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The iPad Inka session: document, live Metal renderer, current brush/size/
/// colour. Mirrors the macOS model (a shared model package is a later
/// refactor); committed strokes are recorded onto the active stroke layer.
@MainActor
final class InkaModel: ObservableObject {
    @Published var document: InkaDocument
    @Published var currentBrushID: String
    @Published var color: Color
    @Published var size: Double

    let renderer: InkaCanvasRenderer?

    init(document: InkaDocument) {
        self.document = document
        self.currentBrushID = BrushLibrary.inkPen.id
        self.color = Color(red: 0.1, green: 0.12, blue: 0.16)
        self.size = BrushLibrary.inkPen.size
        self.renderer = InkaCanvasRenderer(canvasSize: document.size)
        renderer?.onCommitStroke = { [weak self] stroke in
            Task { @MainActor in self?.record(stroke) }
        }
        renderer?.brush = currentBrush
        renderer?.color = currentColorRGBA
    }

    var currentBrush: Brush {
        var brush = document.brush(id: currentBrushID) ?? BrushLibrary.inkPen
        brush.size = size
        return brush
    }

    var currentColorRGBA: RGBA {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return RGBA(r: Double(r), g: Double(g), b: Double(b))
    }

    func syncRenderer() {
        renderer?.brush = currentBrush
        renderer?.color = currentColorRGBA
    }

    func selectBrush(_ id: String) {
        currentBrushID = id
        if let base = document.brush(id: id) { size = base.size }
        syncRenderer()
    }

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

    func clearCanvas() {
        renderer?.clear()
        for i in document.layers.indices where document.layers[i].isVector {
            document.layers[i].content = .strokes([])
        }
    }

    /// Flatten the committed canvas to a UIImage for a share sheet.
    func exportImage() -> UIImage? {
        guard let cg = renderer?.committedImage() else { return nil }
        return UIImage(cgImage: cg)
    }
}
