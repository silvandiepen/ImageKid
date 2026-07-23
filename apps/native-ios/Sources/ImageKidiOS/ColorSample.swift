import CoreGraphics
import Foundation
import SwiftUI

/// A sampled pixel colour with copy-ready string formats.
struct SampledColor: Identifiable, Equatable {
    let id = UUID()
    let r: Int
    let g: Int
    let b: Int

    var hex: String { String(format: "#%02X%02X%02X", r, g, b) }
    var rgb: String { "rgb(\(r), \(g), \(b))" }

    var hsl: String {
        let rf = Double(r) / 255, gf = Double(g) / 255, bf = Double(b) / 255
        let maximum = max(rf, gf, bf), minimum = min(rf, gf, bf)
        let delta = maximum - minimum
        let lightness = (maximum + minimum) / 2
        let saturation = delta == 0 ? 0 : delta / (1 - abs(2 * lightness - 1))
        var hue = 0.0
        if delta != 0 {
            if maximum == rf { hue = 60 * (((gf - bf) / delta).truncatingRemainder(dividingBy: 6)) }
            else if maximum == gf { hue = 60 * (((bf - rf) / delta) + 2) }
            else { hue = 60 * (((rf - gf) / delta) + 4) }
        }
        if hue < 0 { hue += 360 }
        return String(format: "hsl(%.0f, %.0f%%, %.0f%%)", hue, saturation * 100, lightness * 100)
    }

    var cssVariable: String { "--color: \(hex);" }

    var color: Color {
        Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}

enum PixelSampler {
    /// Reads the colour at a normalised (0…1, top-left origin) location by
    /// isolating a single pixel and straightening any premultiplied alpha.
    static func sample(_ image: CGImage, at normalized: CGPoint) -> SampledColor? {
        let px = min(max(Int(normalized.x * CGFloat(image.width)), 0), image.width - 1)
        let py = min(max(Int(normalized.y * CGFloat(image.height)), 0), image.height - 1)
        guard let cropped = image.cropping(to: CGRect(x: px, y: py, width: 1, height: 1)) else {
            return nil
        }

        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        let alpha = Int(pixel[3])
        func straighten(_ channel: UInt8) -> Int {
            guard alpha > 0 else { return 0 }
            guard alpha < 255 else { return Int(channel) }
            return min(255, Int(channel) * 255 / alpha)
        }
        return SampledColor(r: straighten(pixel[0]), g: straighten(pixel[1]), b: straighten(pixel[2]))
    }
}
