import CoreGraphics
import Foundation
import UIKit

extension UIImage {
    /// Returns an orientation-normalised, up-facing `CGImage` so the inference
    /// engines never see rotated pixel data. Photos imported from the library
    /// frequently carry a non-`.up` orientation flag.
    func normalizedCGImage() -> CGImage? {
        guard let cgImage else { return nil }
        if imageOrientation == .up { return cgImage }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let redrawn = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
        return redrawn.cgImage
    }
}

extension CGImage {
    /// High-quality resize to an exact pixel size.
    func resizedExact(width: Int, height: Int) -> CGImage? {
        let targetWidth = max(1, width)
        let targetHeight = max(1, height)
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(self, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return context.makeImage()
    }
}
