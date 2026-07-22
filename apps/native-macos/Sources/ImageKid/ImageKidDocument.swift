import AppKit
import Foundation

// MARK: - Codable geometry / image helpers

private struct IKPoint: Codable {
    var x: CGFloat, y: CGFloat
    init(_ p: CGPoint) { x = p.x; y = p.y }
    var cg: CGPoint { CGPoint(x: x, y: y) }
}

private struct IKRect: Codable {
    var x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat
    init(_ r: CGRect) { x = r.minX; y = r.minY; w = r.width; h = r.height }
    var cg: CGRect { CGRect(x: x, y: y, width: w, height: h) }
}

private struct IKSize: Codable {
    var w: CGFloat, h: CGFloat
    init(_ s: CGSize) { w = s.width; h = s.height }
    var cg: CGSize { CGSize(width: w, height: h) }
}

private enum IKImageCoder {
    static func encode(_ image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return png.base64EncodedString()
    }

    static func decode(_ string: String?) -> NSImage? {
        guard let string, let data = Data(base64Encoded: string) else { return nil }
        return NSImage(data: data)
    }
}

// MARK: - DTOs

private struct IKKind: Codable {
    var type: String
    var start: IKPoint?
    var end: IKPoint?
    var points: [IKPoint]?
    var text: String?

    init(_ kind: Annotation.Kind) {
        switch kind {
        case .rectangle: type = "rectangle"
        case .ellipse: type = "ellipse"
        case .line(let s, let e): type = "line"; start = IKPoint(s); end = IKPoint(e)
        case .arrow(let s, let e): type = "arrow"; start = IKPoint(s); end = IKPoint(e)
        case .freehand(let p): type = "freehand"; points = p.map(IKPoint.init)
        case .text(let value): type = "text"; text = value
        }
    }

    var kind: Annotation.Kind {
        switch type {
        case "ellipse": return .ellipse
        case "line": return .line(start: start?.cg ?? .zero, end: end?.cg ?? .zero)
        case "arrow": return .arrow(start: start?.cg ?? .zero, end: end?.cg ?? .zero)
        case "freehand": return .freehand(points: (points ?? []).map(\.cg))
        case "text": return .text(text ?? "")
        default: return .rectangle
        }
    }
}

private struct IKAnnotation: Codable {
    var id: UUID
    var kind: IKKind
    var frame: IKRect
    var strokeHex: String
    var fillHex: String?
    var lineWidth: CGFloat
    var strokeStyle: String
    var strokeAlignment: String
    var cornerRadius: CGFloat
    var dashLength: CGFloat
    var dashGap: CGFloat
    var dashOffset: CGFloat
    var blendMode: String
    var opacity: Double
    var fontFamily: String
    var fontSize: CGFloat
    var fontWeight: String
    var lineHeight: CGFloat
    var textAlignment: String
    var customName: String?
    var isVisible: Bool
    var z: Double?

    init(_ a: Annotation) {
        id = a.id
        kind = IKKind(a.kind)
        frame = IKRect(a.frame)
        strokeHex = ColorHex.string(from: a.strokeColor)
        fillHex = a.fillColor.map { ColorHex.string(from: $0) }
        lineWidth = a.lineWidth
        strokeStyle = a.strokeStyle.rawValue
        strokeAlignment = a.strokeAlignment.rawValue
        cornerRadius = a.cornerRadius
        dashLength = a.dashLength
        dashGap = a.dashGap
        dashOffset = a.dashOffset
        blendMode = a.blendMode.rawValue
        opacity = a.opacity
        fontFamily = a.fontFamily
        fontSize = a.fontSize
        fontWeight = a.fontWeight.rawValue
        lineHeight = a.lineHeight
        textAlignment = a.textAlignment.rawValue
        customName = a.customName
        isVisible = a.isVisible
        z = a.z
    }

    var annotation: Annotation {
        Annotation(
            id: id,
            kind: kind.kind,
            frame: frame.cg,
            strokeColor: ColorHex.color(from: strokeHex) ?? .systemRed,
            fillColor: fillHex.flatMap { ColorHex.color(from: $0) },
            lineWidth: lineWidth,
            strokeStyle: ShapeStrokeStyle(rawValue: strokeStyle) ?? .solid,
            strokeAlignment: StrokeAlignment(rawValue: strokeAlignment) ?? .center,
            cornerRadius: cornerRadius,
            dashLength: dashLength,
            dashGap: dashGap,
            dashOffset: dashOffset,
            blendMode: ShapeBlendMode(rawValue: blendMode) ?? .normal,
            opacity: opacity,
            fontFamily: fontFamily,
            fontSize: fontSize,
            fontWeight: AnnotationFontWeight(rawValue: fontWeight) ?? .semibold,
            lineHeight: lineHeight,
            textAlignment: AnnotationTextAlignment(rawValue: textAlignment) ?? .leading,
            customName: customName,
            isVisible: isVisible,
            z: z ?? 0
        )
    }
}

private struct IKLayer: Codable {
    var id: UUID
    var name: String
    var image: String
    var frame: IKRect
    var opacity: Double
    var isVisible: Bool
    var rotation: Double
    var flipH: Bool
    var flipV: Bool
    var mask: String?
    var isMaskEnabled: Bool
    var z: Double?

    init?(_ layer: ImageLayer) {
        guard let image = IKImageCoder.encode(layer.image) else { return nil }
        id = layer.id
        name = layer.name
        self.image = image
        frame = IKRect(layer.frame)
        opacity = layer.opacity
        isVisible = layer.isVisible
        rotation = layer.rotation
        flipH = layer.flipH
        flipV = layer.flipV
        mask = layer.mask.flatMap { IKImageCoder.encode($0) }
        isMaskEnabled = layer.isMaskEnabled
        z = layer.z
    }

    var layer: ImageLayer? {
        guard let nsImage = IKImageCoder.decode(image) else { return nil }
        return ImageLayer(
            id: id, name: name, image: nsImage, frame: frame.cg,
            opacity: opacity, isVisible: isVisible, rotation: rotation,
            flipH: flipH, flipV: flipV,
            mask: IKImageCoder.decode(mask), isMaskEnabled: isMaskEnabled,
            z: z ?? 0
        )
    }
}

private struct IKGroup: Codable {
    var id: UUID
    var name: String
    var memberIDs: [UUID]
    var isVisible: Bool
    var isCollapsed: Bool

    init(_ g: LayerGroup) {
        id = g.id; name = g.name; memberIDs = g.memberIDs
        isVisible = g.isVisible; isCollapsed = g.isCollapsed
    }

    var group: LayerGroup {
        LayerGroup(id: id, name: name, memberIDs: memberIDs, isVisible: isVisible, isCollapsed: isCollapsed)
    }
}

private struct IKGrid: Codable {
    var show: Bool
    var snap: Bool
    var size: CGFloat
    var colorHex: String
    var opacity: Double
    var subdivisions: Int
}

// MARK: - Document

/// The on-disk ImageKid work file — the full editable state of a session.
struct ImageKidDocument: Codable {
    static let fileExtension = "imagekid"
    static let currentVersion = 1

    fileprivate var version: Int
    fileprivate var baseImage: String
    fileprivate var backgroundRemovedImage: String?
    fileprivate var cropRect: IKRect
    fileprivate var outputSize: IKSize?
    fileprivate var viewportMode: String
    fileprivate var grid: IKGrid
    fileprivate var annotations: [IKAnnotation]
    fileprivate var imageLayers: [IKLayer]
    fileprivate var layerGroups: [IKGroup]
    fileprivate var baseUnlocked: Bool?

    @MainActor
    init?(session: ImageSession) {
        guard let base = IKImageCoder.encode(session.sourceImage) else { return nil }
        version = Self.currentVersion
        baseImage = base
        backgroundRemovedImage = session.backgroundRemovedImage.flatMap { IKImageCoder.encode($0) }
        cropRect = IKRect(session.cropRect)
        outputSize = session.outputSize.map(IKSize.init)
        viewportMode = session.viewportMode.rawValue
        grid = IKGrid(
            show: session.showGrid, snap: session.snapToGrid, size: session.gridSizePx,
            colorHex: session.gridColorHex, opacity: session.gridOpacity, subdivisions: session.gridSubdivisions
        )
        annotations = session.annotations.map(IKAnnotation.init)
        imageLayers = session.imageLayers.compactMap(IKLayer.init)
        layerGroups = session.layerGroups.map(IKGroup.init)
        baseUnlocked = session.baseUnlocked
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    static func decoded(from data: Data) throws -> ImageKidDocument {
        try JSONDecoder().decode(ImageKidDocument.self, from: data)
    }

    /// Rebuild a live session from the document.
    @MainActor
    func makeSession() -> ImageSession? {
        guard let base = IKImageCoder.decode(baseImage) else { return nil }
        let session = ImageSession(sourceURL: nil, sourceImage: base)
        session.backgroundRemovedImage = IKImageCoder.decode(backgroundRemovedImage)
        session.cropRect = cropRect.cg
        session.outputSize = outputSize?.cg
        session.viewportMode = ViewportMode(rawValue: viewportMode) ?? .contain
        session.showGrid = grid.show
        session.snapToGrid = grid.snap
        session.gridSizePx = grid.size
        session.gridColorHex = grid.colorHex
        session.gridOpacity = grid.opacity
        session.gridSubdivisions = grid.subdivisions
        session.annotations = annotations.map(\.annotation)
        session.imageLayers = imageLayers.compactMap(\.layer)
        session.layerGroups = layerGroups.map(\.group)
        session.baseUnlocked = baseUnlocked ?? false
        session.seedHistory()
        return session
    }
}
