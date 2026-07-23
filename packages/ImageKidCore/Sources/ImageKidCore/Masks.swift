import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Non-destructive mask helpers: apply a grayscale mask to an image, and derive
/// a mask from a cutout's alpha channel. Shared by both apps.
public enum MaskCompositor {
    private static var context: CIContext { PlatformRender.ciContext }

    /// Composite `image` through `mask` (white = keep, black = hide) over
    /// transparency, without altering the original pixels.
    public static func apply(mask: PlatformImage, to image: PlatformImage) -> PlatformImage? {
        guard let imageCG = image.cgImageForRendering,
              let maskCG = mask.cgImageForRendering else {
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
        return .fromCGImage(result, size: image.size)
    }

    /// A translucent red overlay showing the hidden (black) areas of a mask —
    /// opaque red where the mask hides, transparent where it keeps.
    public static func hiddenOverlay(from mask: PlatformImage) -> PlatformImage? {
        guard let maskCG = mask.cgImageForRendering else { return nil }
        let filter = CIFilter.colorMatrix()
        filter.inputImage = CIImage(cgImage: maskCG)
        // RGB = red; alpha = 1 - R (grayscale mask, so R == luminance).
        filter.rVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        filter.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        filter.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        filter.aVector = CIVector(x: -1, y: 0, z: 0, w: 0)
        filter.biasVector = CIVector(x: 1, y: 0, z: 0, w: 1)
        guard let output = filter.outputImage,
              let result = context.createCGImage(output, from: output.extent) else { return nil }
        return .fromCGImage(result, size: mask.size)
    }

    /// Build an opaque grayscale mask whose brightness equals the cutout's alpha
    /// (foreground → white, removed background → black).
    public static func alphaMask(from cutout: CGImage) -> PlatformImage? {
        let filter = CIFilter.colorMatrix()
        filter.inputImage = CIImage(cgImage: cutout)
        // Move the alpha channel into R, G, B; force output alpha to 1.
        filter.rVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        filter.gVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        filter.bVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        filter.biasVector = CIVector(x: 0, y: 0, z: 0, w: 1)

        let bounds = CGRect(x: 0, y: 0, width: cutout.width, height: cutout.height)
        guard let output = filter.outputImage,
              let result = context.createCGImage(output, from: bounds) else {
            return nil
        }
        return .fromCGImage(result, size: CGSize(width: cutout.width, height: cutout.height))
    }
}
