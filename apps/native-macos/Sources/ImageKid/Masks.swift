import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Non-destructive mask helpers: apply a grayscale mask to an image, and derive
/// a mask from a cutout's alpha channel.
enum MaskCompositor {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Composite `image` through `mask` (white = keep, black = hide) over
    /// transparency, without altering the original pixels.
    static func apply(mask: NSImage, to image: NSImage) -> NSImage? {
        guard let imageCG = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let maskCG = mask.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let base = CIImage(cgImage: imageCG)
        var maskCI = CIImage(cgImage: maskCG)
        if maskCG.width != imageCG.width || maskCG.height != imageCG.height {
            let sx = CGFloat(imageCG.width) / CGFloat(max(maskCG.width, 1))
            let sy = CGFloat(imageCG.height) / CGFloat(max(maskCG.height, 1))
            maskCI = maskCI.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        }

        let filter = CIFilter.blendWithMask()
        filter.inputImage = base
        filter.backgroundImage = CIImage.empty()
        filter.maskImage = maskCI

        guard let output = filter.outputImage,
              let result = context.createCGImage(output, from: base.extent) else {
            return nil
        }
        return NSImage(cgImage: result, size: image.size)
    }

    /// Build an opaque grayscale mask whose brightness equals the cutout's alpha
    /// (foreground → white, removed background → black).
    static func alphaMask(from cutout: CGImage) -> NSImage? {
        let filter = CIFilter.colorMatrix()
        filter.inputImage = CIImage(cgImage: cutout)
        // Move the alpha channel into R, G, B; force output alpha to 1.
        filter.rVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        filter.gVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        filter.bVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        filter.biasVector = CIVector(x: 0, y: 0, z: 0, w: 1)

        guard let output = filter.outputImage,
              let result = context.createCGImage(output, from: output.extent) else {
            return nil
        }
        return NSImage(cgImage: result, size: CGSize(width: cutout.width, height: cutout.height))
    }
}
