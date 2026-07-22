import CoreGraphics
import Foundation

/// Hex <-> color conversion in the sRGB space, shared by both apps and the
/// .imagekid document format.
public enum ColorHex {
    public static func string(from color: PlatformColor) -> String {
        let c = color.sRGBComponents
        let includeAlpha = c.alpha < 0.999
        return String(
            format: includeAlpha ? "#%02X%02X%02X%02X" : "#%02X%02X%02X",
            Int((c.red * 255).rounded()),
            Int((c.green * 255).rounded()),
            Int((c.blue * 255).rounded()),
            Int((c.alpha * 255).rounded())
        )
    }

    public static func color(from hex: String) -> PlatformColor? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard let value = UInt64(s, radix: 16) else { return nil }
        switch s.count {
        case 6:
            return .sRGB(red: CGFloat((value >> 16) & 0xFF) / 255,
                         green: CGFloat((value >> 8) & 0xFF) / 255,
                         blue: CGFloat(value & 0xFF) / 255, alpha: 1)
        case 8:
            return .sRGB(red: CGFloat((value >> 24) & 0xFF) / 255,
                         green: CGFloat((value >> 16) & 0xFF) / 255,
                         blue: CGFloat((value >> 8) & 0xFF) / 255,
                         alpha: CGFloat(value & 0xFF) / 255)
        default:
            return nil
        }
    }
}

/// A color picked from an image, with formatting helpers for the various
/// clipboard/CSS representations.
public struct SampledColor: Identifiable {
    public let id: UUID
    public var color: PlatformColor

    public init(id: UUID = UUID(), color: PlatformColor) {
        self.id = id
        self.color = color
    }

    /// The color resolved into the sRGB space.
    public var sRGB: PlatformColor {
        let c = components
        return .sRGB(red: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }

    private var components: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        color.sRGBComponents
    }

    public var hex: String {
        let c = components
        let includeAlpha = c.alpha < 0.999
        return String(
            format: includeAlpha ? "#%02X%02X%02X%02X" : "#%02X%02X%02X",
            Int((c.red * 255).rounded()),
            Int((c.green * 255).rounded()),
            Int((c.blue * 255).rounded()),
            Int((c.alpha * 255).rounded())
        )
    }

    public var rgb: String {
        let c = components
        return String(
            format: "rgb(%d, %d, %d)",
            Int((c.red * 255).rounded()),
            Int((c.green * 255).rounded()),
            Int((c.blue * 255).rounded())
        )
    }

    public var rgba: String {
        let c = components
        return String(
            format: "rgba(%d, %d, %d, %.3f)",
            Int((c.red * 255).rounded()),
            Int((c.green * 255).rounded()),
            Int((c.blue * 255).rounded()),
            c.alpha
        )
    }

    public var hsl: String {
        let c = components
        let r = c.red, g = c.green, b = c.blue
        let maximum = max(r, g, b)
        let minimum = min(r, g, b)
        let delta = maximum - minimum
        let lightness = (maximum + minimum) / 2
        let saturation = delta == 0 ? 0 : delta / (1 - abs(2 * lightness - 1))
        var hue: CGFloat = 0
        if delta != 0 {
            if maximum == r {
                hue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maximum == g {
                hue = 60 * (((b - r) / delta) + 2)
            } else {
                hue = 60 * (((r - g) / delta) + 4)
            }
        }
        if hue < 0 { hue += 360 }
        return String(format: "hsl(%.0f, %.0f%%, %.0f%%)", hue, saturation * 100, lightness * 100)
    }

    public var cssVariable: String { "--color: \(hex);" }

    public var swiftUIColor: String {
        let c = components
        return String(
            format: "Color(red: %.3f, green: %.3f, blue: %.3f, opacity: %.3f)",
            c.red, c.green, c.blue, c.alpha
        )
    }
}
