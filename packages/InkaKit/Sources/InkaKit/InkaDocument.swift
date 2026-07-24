import BrushKit
import CoreGraphics
import Foundation

/// Inka's canvas document: a fixed pixel canvas, an ordered layer stack, the
/// brush presets its strokes reference, and a working palette. The hybrid model
/// lives in `Layer.content`.
///
/// Codable throughout so the `.inka` workfile is one JSON document (raster/
/// imported pixels ride as base64 PNG). Non-destructive: a `.strokes` layer keeps
/// its `BrushStroke`s and is re-rasterized on demand, so changing a brush or a
/// stroke colour re-renders cleanly.
public struct InkaDocument: Equatable, Sendable, Codable {
    /// Canvas size in pixels (points at 1×; the app owns display scale).
    public var width: Int
    public var height: Int
    /// Ordered bottom → top (last drawn on top), matching Fekthor's z-order and
    /// ImageKidCore's stack idiom.
    public var layers: [Layer]
    /// Every brush a stroke in this document references, by `Brush.id`, plus any
    /// the user has customised. Built-ins are overlaid at load if absent.
    public var brushes: [Brush]
    /// The document's working colour swatches (`#rrggbb`).
    public var palette: [String]

    public init(
        width: Int, height: Int, layers: [Layer] = [], brushes: [Brush] = BrushLibrary.all,
        palette: [String] = []
    ) {
        self.width = width
        self.height = height
        self.layers = layers
        self.brushes = brushes
        self.palette = palette
    }

    /// A blank document with a single empty stroke layer, ready to draw on.
    public static func blank(width: Int, height: Int) -> InkaDocument {
        InkaDocument(
            width: width, height: height,
            layers: [Layer(name: "Layer 1", content: .strokes([]))])
    }

    public var size: CGSize { CGSize(width: width, height: height) }

    /// Resolve a brush id against the document's table (built-ins as fallback).
    public func brush(id: String) -> Brush? {
        brushes.first { $0.id == id } ?? BrushLibrary.brush(id: id)
    }

    /// The next free layer name ("Layer N").
    public func nextLayerName() -> String {
        "Layer \(layers.count + 1)"
    }
}

/// One layer. Identity + shared compositing properties, plus the hybrid
/// `content`.
public struct Layer: Equatable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var content: Content
    public var opacity: Double
    /// SVG/Core-style blend name ("normal", "multiply", …); the renderer maps it.
    public var blendMode: String
    public var isVisible: Bool
    public var isLocked: Bool

    public init(
        id: UUID = UUID(), name: String, content: Content, opacity: Double = 1,
        blendMode: String = "normal", isVisible: Bool = true, isLocked: Bool = false
    ) {
        self.id = id
        self.name = name
        self.content = content
        self.opacity = opacity
        self.blendMode = blendMode
        self.isVisible = isVisible
        self.isLocked = isLocked
    }

    /// The hybrid: editable vector strokes, flat raster pixels, or an imported
    /// picture. Raster/imported pixels serialize as base64 PNG.
    public enum Content: Equatable, Sendable {
        case strokes([BrushStroke])
        case raster(PNGImage)
        case imported(PNGImage)
    }

    /// True when this layer keeps editable strokes (re-rasterizable).
    public var isVector: Bool {
        if case .strokes = content { return true }
        return false
    }
}

/// A pixel buffer carried inside the document as base64 PNG. Wraps the raw PNG
/// data so raster/imported layers round-trip through JSON without a platform
/// image type leaking into the model.
public struct PNGImage: Equatable, Sendable, Codable {
    /// PNG file bytes.
    public var data: Data
    public var width: Int
    public var height: Int

    public init(data: Data, width: Int, height: Int) {
        self.data = data
        self.width = width
        self.height = height
    }
}

// MARK: - Content Codable (tagged union)

extension Layer.Content: Codable {
    private enum CodingKeys: String, CodingKey { case kind, strokes, image }
    private enum Kind: String, Codable { case strokes, raster, imported }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .strokes: self = .strokes(try c.decode([BrushStroke].self, forKey: .strokes))
        case .raster: self = .raster(try c.decode(PNGImage.self, forKey: .image))
        case .imported: self = .imported(try c.decode(PNGImage.self, forKey: .image))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .strokes(let s):
            try c.encode(Kind.strokes, forKey: .kind)
            try c.encode(s, forKey: .strokes)
        case .raster(let i):
            try c.encode(Kind.raster, forKey: .kind)
            try c.encode(i, forKey: .image)
        case .imported(let i):
            try c.encode(Kind.imported, forKey: .kind)
            try c.encode(i, forKey: .image)
        }
    }
}
