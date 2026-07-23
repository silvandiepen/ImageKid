import CoreGraphics
import Foundation

// MARK: - Codable geometry / image helpers

public struct IKPoint: Codable {
    public var x: CGFloat, y: CGFloat
    public init(_ p: CGPoint) { x = p.x; y = p.y }
    public var cg: CGPoint { CGPoint(x: x, y: y) }
}

public struct IKRect: Codable {
    public var x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat
    public init(_ r: CGRect) { x = r.minX; y = r.minY; w = r.width; h = r.height }
    public var cg: CGRect { CGRect(x: x, y: y, width: w, height: h) }
}

public struct IKSize: Codable {
    public var w: CGFloat, h: CGFloat
    public init(_ s: CGSize) { w = s.width; h = s.height }
    public var cg: CGSize { CGSize(width: w, height: h) }
}

public enum IKImageCoder {
    public static func encode(_ image: PlatformImage) -> String? {
        PlatformImageCoding.pngBase64(image)
    }

    public static func decode(_ string: String?) -> PlatformImage? {
        PlatformImageCoding.image(fromBase64: string)
    }
}

// MARK: - DTOs

public struct IKKind: Codable {
    public var type: String
    public var start: IKPoint?
    public var end: IKPoint?
    public var points: [IKPoint]?
    public var text: String?

    public init(_ kind: Annotation.Kind) {
        switch kind {
        case .rectangle: type = "rectangle"
        case .ellipse: type = "ellipse"
        case .line(let s, let e): type = "line"; start = IKPoint(s); end = IKPoint(e)
        case .arrow(let s, let e): type = "arrow"; start = IKPoint(s); end = IKPoint(e)
        case .freehand(let p): type = "freehand"; points = p.map(IKPoint.init)
        case .text(let value): type = "text"; text = value
        }
    }

    public var kind: Annotation.Kind {
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

public struct IKAnnotation: Codable {
    public var id: UUID
    public var kind: IKKind
    public var frame: IKRect
    public var strokeHex: String
    public var fillHex: String?
    public var lineWidth: CGFloat
    public var strokeStyle: String
    public var strokeAlignment: String
    public var cornerRadius: CGFloat
    public var cornerRadii: [CGFloat]?
    public var dashLength: CGFloat
    public var dashGap: CGFloat
    public var dashOffset: CGFloat
    public var blendMode: String
    public var opacity: Double
    public var fontFamily: String
    public var fontSize: CGFloat
    public var fontWeight: String
    public var lineHeight: CGFloat
    public var textAlignment: String
    public var customName: String?
    public var isVisible: Bool
    public var z: Double?

    public init(_ a: Annotation) {
        id = a.id
        kind = IKKind(a.kind)
        frame = IKRect(a.frame)
        strokeHex = ColorHex.string(from: a.strokeColor)
        fillHex = a.fillColor.map { ColorHex.string(from: $0) }
        lineWidth = a.lineWidth
        strokeStyle = a.strokeStyle.rawValue
        strokeAlignment = a.strokeAlignment.rawValue
        cornerRadius = a.cornerRadius
        cornerRadii = a.cornerRadii
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

    public var annotation: Annotation {
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
            cornerRadii: cornerRadii,
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

public struct IKLayer: Codable {
    public var id: UUID
    public var name: String
    public var image: String
    public var frame: IKRect
    public var opacity: Double
    public var isVisible: Bool
    public var rotation: Double
    public var flipH: Bool
    public var flipV: Bool
    public var mask: String?
    public var isMaskEnabled: Bool
    public var z: Double?

    public init?(_ layer: ImageLayer) {
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

    public var layer: ImageLayer? {
        guard let image = IKImageCoder.decode(image) else { return nil }
        return ImageLayer(
            id: id, name: name, image: image, frame: frame.cg,
            opacity: opacity, isVisible: isVisible, rotation: rotation,
            flipH: flipH, flipV: flipV,
            mask: IKImageCoder.decode(mask), isMaskEnabled: isMaskEnabled,
            z: z ?? 0
        )
    }
}

public struct IKGroup: Codable {
    public var id: UUID
    public var name: String
    public var memberIDs: [UUID]
    public var isVisible: Bool
    public var isCollapsed: Bool

    public init(_ g: LayerGroup) {
        id = g.id; name = g.name; memberIDs = g.memberIDs
        isVisible = g.isVisible; isCollapsed = g.isCollapsed
    }

    public var group: LayerGroup {
        LayerGroup(id: id, name: name, memberIDs: memberIDs, isVisible: isVisible, isCollapsed: isCollapsed)
    }
}

public struct IKGrid: Codable {
    public var show: Bool
    public var snap: Bool
    public var size: CGFloat
    public var colorHex: String
    public var opacity: Double
    public var subdivisions: Int

    public init(show: Bool, snap: Bool, size: CGFloat, colorHex: String, opacity: Double, subdivisions: Int) {
        self.show = show
        self.snap = snap
        self.size = size
        self.colorHex = colorHex
        self.opacity = opacity
        self.subdivisions = subdivisions
    }
}

// MARK: - Document

/// The on-disk ImageKid work file — the full editable state of a session,
/// portable across macOS and iOS. Session bridging (build-from / restore-into a
/// live editor) lives in each app as an extension.
public struct ImageKidDocument: Codable {
    public static let fileExtension = "imagekid"
    public static let currentVersion = 1

    public var version: Int
    public var baseImage: String
    public var backgroundRemovedImage: String?
    public var cropRect: IKRect
    public var outputSize: IKSize?
    public var viewportMode: String
    public var grid: IKGrid
    public var annotations: [IKAnnotation]
    public var imageLayers: [IKLayer]
    public var layerGroups: [IKGroup]
    public var baseUnlocked: Bool?

    public init(
        version: Int = ImageKidDocument.currentVersion,
        baseImage: String,
        backgroundRemovedImage: String?,
        cropRect: IKRect,
        outputSize: IKSize?,
        viewportMode: String,
        grid: IKGrid,
        annotations: [IKAnnotation],
        imageLayers: [IKLayer],
        layerGroups: [IKGroup],
        baseUnlocked: Bool?
    ) {
        self.version = version
        self.baseImage = baseImage
        self.backgroundRemovedImage = backgroundRemovedImage
        self.cropRect = cropRect
        self.outputSize = outputSize
        self.viewportMode = viewportMode
        self.grid = grid
        self.annotations = annotations
        self.imageLayers = imageLayers
        self.layerGroups = layerGroups
        self.baseUnlocked = baseUnlocked
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public static func decoded(from data: Data) throws -> ImageKidDocument {
        try JSONDecoder().decode(ImageKidDocument.self, from: data)
    }
}
