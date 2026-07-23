import CoreGraphics
import SwiftUI

/// Stroke line style for shapes and lines.
public enum ShapeStrokeStyle: String, CaseIterable, Identifiable, Hashable {
    case solid, dashed, dotted
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .solid: return "Solid"
        case .dashed: return "Dashed"
        case .dotted: return "Dotted"
        }
    }
    /// Dash pattern scaled to the stroke width (empty = solid line).
    public func dashPattern(lineWidth: CGFloat) -> [CGFloat] {
        let w = max(lineWidth, 1)
        switch self {
        case .solid: return []
        case .dashed: return [w * 3, w * 2.2]
        case .dotted: return [w * 0.05, w * 1.8]
        }
    }
}

/// Where a shape's stroke sits relative to its edge.
public enum StrokeAlignment: String, CaseIterable, Identifiable, Hashable {
    case inset, center, outset
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .inset: return "Inside"
        case .center: return "Center"
        case .outset: return "Outside"
        }
    }
    /// How far (in stroke-width multiples) to shift the stroke path outward.
    public var edgeShift: CGFloat {
        switch self {
        case .inset: return -0.5
        case .center: return 0
        case .outset: return 0.5
        }
    }
}

/// Blend mode for how a shape composites over the layers beneath it.
public enum ShapeBlendMode: String, CaseIterable, Identifiable, Hashable {
    case normal, multiply, screen, overlay, darken, lighten
    case colorDodge, colorBurn, softLight, hardLight
    case difference, exclusion, hue, saturation, color, luminosity

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .normal: return "Normal"
        case .multiply: return "Multiply"
        case .screen: return "Screen"
        case .overlay: return "Overlay"
        case .darken: return "Darken"
        case .lighten: return "Lighten"
        case .colorDodge: return "Color Dodge"
        case .colorBurn: return "Color Burn"
        case .softLight: return "Soft Light"
        case .hardLight: return "Hard Light"
        case .difference: return "Difference"
        case .exclusion: return "Exclusion"
        case .hue: return "Hue"
        case .saturation: return "Saturation"
        case .color: return "Color"
        case .luminosity: return "Luminosity"
        }
    }

    public var swiftUI: BlendMode {
        switch self {
        case .normal: return .normal
        case .multiply: return .multiply
        case .screen: return .screen
        case .overlay: return .overlay
        case .darken: return .darken
        case .lighten: return .lighten
        case .colorDodge: return .colorDodge
        case .colorBurn: return .colorBurn
        case .softLight: return .softLight
        case .hardLight: return .hardLight
        case .difference: return .difference
        case .exclusion: return .exclusion
        case .hue: return .hue
        case .saturation: return .saturation
        case .color: return .color
        case .luminosity: return .luminosity
        }
    }

    public var cg: CGBlendMode {
        switch self {
        case .normal: return .normal
        case .multiply: return .multiply
        case .screen: return .screen
        case .overlay: return .overlay
        case .darken: return .darken
        case .lighten: return .lighten
        case .colorDodge: return .colorDodge
        case .colorBurn: return .colorBurn
        case .softLight: return .softLight
        case .hardLight: return .hardLight
        case .difference: return .difference
        case .exclusion: return .exclusion
        case .hue: return .hue
        case .saturation: return .saturation
        case .color: return .color
        case .luminosity: return .luminosity
        }
    }
}
