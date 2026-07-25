import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Normalises an imported image into a canvas-sized PNG (aspect-fit, centred), so
/// an `.imported` layer shows identically on the GPU canvas and in export — both
/// draw it as a full-canvas quad. Shared by both app shells.
public enum InkaImageFit {
    public static func fitToCanvasPNG(_ image: CGImage, width: Int, height: Int) -> PNGImage? {
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
            let ctx = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let scale = min(CGFloat(width) / CGFloat(image.width), CGFloat(height) / CGFloat(image.height))
        let dw = CGFloat(image.width) * scale
        let dh = CGFloat(image.height) * scale
        let x = (CGFloat(width) - dw) / 2
        let y = (CGFloat(height) - dh) / 2
        ctx.draw(image, in: CGRect(x: x, y: y, width: dw, height: dh))
        guard let out = ctx.makeImage(), let data = pngData(out) else { return nil }
        return PNGImage(data: data, width: width, height: height)
    }

    static func pngData(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
