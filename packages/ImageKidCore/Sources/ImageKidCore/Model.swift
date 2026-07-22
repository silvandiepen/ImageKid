import CoreGraphics
import Foundation
import SwiftUI

/// The five vector-drawing shape kinds.
public enum DrawingMode: String, CaseIterable, Identifiable {
    case rectangle
    case ellipse
    case line
    case arrow
    case freehand

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .line: "Line"
        case .arrow: "Arrow"
        case .freehand: "Freehand"
        }
    }

    public var symbolName: String {
        switch self {
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .freehand: "pencil.tip"
        }
    }

    public var supportsFill: Bool {
        self == .rectangle || self == .ellipse
    }
}

public enum AnnotationFontWeight: String, CaseIterable, Identifiable {
    case regular
    case medium
    case semibold
    case bold

    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }

    public var swiftUIWeight: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }

    /// Weight index for NSFontManager (macOS text rendering).
    public var fontManagerWeight: Int {
        switch self {
        case .regular: 5
        case .medium: 7
        case .semibold: 8
        case .bold: 9
        }
    }
}

public enum AnnotationTextAlignment: String, CaseIterable, Identifiable {
    case leading
    case center
    case trailing

    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }

    public var swiftUIAlignment: Alignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

/// A vector annotation — shape, line, arrow, freehand path, or text — placed in
/// the base image's normalised (0…1) source space.
public struct Annotation: Identifiable {
    public enum Kind {
        case rectangle
        case ellipse
        case line(start: CGPoint, end: CGPoint)
        case arrow(start: CGPoint, end: CGPoint)
        case freehand(points: [CGPoint])
        case text(String)
    }

    public let id: UUID
    public var kind: Kind
    public var frame: CGRect
    public var strokeColor: PlatformColor
    public var fillColor: PlatformColor?
    public var lineWidth: CGFloat
    public var strokeStyle: ShapeStrokeStyle
    public var strokeAlignment: StrokeAlignment
    /// Corner radius for rectangles, in source pixels (0 = square corners).
    public var cornerRadius: CGFloat
    /// Custom dash: length of a dash and the gap after it, in source pixels.
    /// When dashLength <= 0 the strokeStyle preset is used instead.
    public var dashLength: CGFloat
    public var dashGap: CGFloat
    public var dashOffset: CGFloat
    public var blendMode: ShapeBlendMode
    public var opacity: Double
    public var fontFamily: String
    public var fontSize: CGFloat
    public var fontWeight: AnnotationFontWeight
    public var lineHeight: CGFloat
    public var textAlignment: AnnotationTextAlignment
    public var customName: String?
    public var isVisible: Bool
    /// Shared stack order across image layers and annotations (higher = on top).
    public var z: Double

    public init(
        id: UUID = UUID(),
        kind: Kind,
        frame: CGRect,
        strokeColor: PlatformColor = .systemRed,
        fillColor: PlatformColor? = nil,
        lineWidth: CGFloat = 3,
        strokeStyle: ShapeStrokeStyle = .solid,
        strokeAlignment: StrokeAlignment = .center,
        cornerRadius: CGFloat = 0,
        dashLength: CGFloat = 0,
        dashGap: CGFloat = 0,
        dashOffset: CGFloat = 0,
        blendMode: ShapeBlendMode = .normal,
        opacity: Double = 1,
        fontFamily: String = "",
        fontSize: CGFloat = 48,
        fontWeight: AnnotationFontWeight = .semibold,
        lineHeight: CGFloat = 1.1,
        textAlignment: AnnotationTextAlignment = .leading,
        customName: String? = nil,
        isVisible: Bool = true,
        z: Double = 0
    ) {
        self.id = id
        self.kind = kind
        self.frame = frame
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.lineWidth = lineWidth
        self.strokeStyle = strokeStyle
        self.strokeAlignment = strokeAlignment
        self.cornerRadius = cornerRadius
        self.dashLength = dashLength
        self.dashGap = dashGap
        self.dashOffset = dashOffset
        self.blendMode = blendMode
        self.opacity = opacity
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.lineHeight = lineHeight
        self.textAlignment = textAlignment
        self.customName = customName
        self.isVisible = isVisible
        self.z = z
    }

    /// The dash pattern to render with: custom (dashLength/dashGap scaled by the
    /// given render scale) when set, otherwise the strokeStyle preset.
    public func effectiveDash(lineWidth: CGFloat, scale: CGFloat = 1) -> [CGFloat] {
        if dashLength > 0 {
            return [dashLength * scale, max(dashGap, 0) * scale]
        }
        return strokeStyle.dashPattern(lineWidth: lineWidth)
    }

    public var textValue: String? {
        get {
            guard case .text(let value) = kind else { return nil }
            return value
        }
        set {
            guard case .text = kind, let newValue else { return }
            kind = .text(newValue)
        }
    }

    public var isText: Bool {
        if case .text = kind { return true }
        return false
    }

    public var isDrawable: Bool { !isText }

    /// Rectangle or ellipse — shapes that can be filled.
    public var isFillable: Bool {
        switch kind {
        case .rectangle, .ellipse: return true
        default: return false
        }
    }

    public var isRectangle: Bool {
        if case .rectangle = kind { return true }
        return false
    }

    public var drawingMode: DrawingMode? {
        switch kind {
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .line: .line
        case .arrow: .arrow
        case .freehand: .freehand
        case .text: nil
        }
    }

    public mutating func changeDrawingMode(_ mode: DrawingMode) {
        switch mode {
        case .rectangle:
            kind = .rectangle
        case .ellipse:
            kind = .ellipse
        case .line:
            kind = .line(start: .zero, end: CGPoint(x: 1, y: 1))
        case .arrow:
            kind = .arrow(start: .zero, end: CGPoint(x: 1, y: 1))
        case .freehand:
            kind = .freehand(points: [.zero, CGPoint(x: 1, y: 1)])
        }
    }
}

/// A placed raster image composited above the base image and below vector
/// annotations. `frame` is normalised in the base-image source space (0…1),
/// matching `Annotation.frame`.
public struct ImageLayer: Identifiable {
    public let id: UUID
    public var name: String
    public var image: PlatformImage
    public var frame: CGRect
    public var opacity: Double
    public var isVisible: Bool
    /// Rotation in degrees, clockwise, about the layer's centre.
    public var rotation: Double
    public var flipH: Bool
    public var flipV: Bool
    /// Non-destructive alpha mask (white = keep, black = hide). Applied to the
    /// layer image when `isMaskEnabled` is true; the original pixels are kept.
    public var mask: PlatformImage?
    public var isMaskEnabled: Bool
    /// Shared stack order across image layers and annotations (higher = on top).
    public var z: Double

    public init(
        id: UUID = UUID(),
        name: String,
        image: PlatformImage,
        frame: CGRect,
        opacity: Double = 1,
        isVisible: Bool = true,
        rotation: Double = 0,
        flipH: Bool = false,
        flipV: Bool = false,
        mask: PlatformImage? = nil,
        isMaskEnabled: Bool = true,
        z: Double = 0
    ) {
        self.id = id
        self.name = name
        self.image = image
        self.frame = frame
        self.opacity = opacity
        self.isVisible = isVisible
        self.rotation = rotation
        self.flipH = flipH
        self.flipV = flipV
        self.mask = mask
        self.isMaskEnabled = isMaskEnabled
        self.z = z
    }

    public var hasMask: Bool { mask != nil }
}

/// One entry in the unified layer stack — an image layer or a vector annotation.
public enum StackItem: Identifiable {
    case layer(ImageLayer)
    case annotation(Annotation)

    public var id: UUID {
        switch self {
        case .layer(let l): return l.id
        case .annotation(let a): return a.id
        }
    }
    public var z: Double {
        switch self {
        case .layer(let l): return l.z
        case .annotation(let a): return a.z
        }
    }
    public var isLayer: Bool { if case .layer = self { return true }; return false }
}

/// An organisational group over image layers. Toggling group visibility gates
/// all members; members keep their own z-order in the flat layer stack.
public struct LayerGroup: Identifiable {
    public let id: UUID
    public var name: String
    public var memberIDs: [UUID]
    public var isVisible: Bool
    public var isCollapsed: Bool

    public init(id: UUID = UUID(), name: String, memberIDs: [UUID], isVisible: Bool = true, isCollapsed: Bool = false) {
        self.id = id
        self.name = name
        self.memberIDs = memberIDs
        self.isVisible = isVisible
        self.isCollapsed = isCollapsed
    }
}
