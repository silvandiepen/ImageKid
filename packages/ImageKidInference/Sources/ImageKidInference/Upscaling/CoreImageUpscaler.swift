import CoreGraphics
import CoreImage
import Foundation

/// Deterministic, always-available upscaler using Core Image (Lanczos scaling
/// plus unsharp masking). This is the cross-platform equivalent of the app's
/// "Standard" engine and works with no model download.
public struct CoreImageUpscaler: ImageUpscaler {
    public enum Sharpening: Sendable {
        /// Tuned for screenshots, diagrams, and text.
        case textAndUI
        /// Gentler settings for photos and artwork.
        case photoArtwork
    }

    private let sharpening: Sharpening

    public init(sharpening: Sharpening = .textAndUI) {
        self.sharpening = sharpening
    }

    public func upscale(
        _ image: CGImage,
        to targetSize: CGSize,
        progress: InferenceProgressHandler?
    ) async throws -> CGImage {
        progress?(InferenceProgress(detail: "Scaling", fraction: nil))

        let width = max(1, Int(targetSize.width.rounded()))
        let height = max(1, Int(targetSize.height.rounded()))
        let scale = max(
            CGFloat(width) / CGFloat(max(image.width, 1)),
            CGFloat(height) / CGFloat(max(image.height, 1))
        )

        var output = CIImage(cgImage: image)

        if let lanczos = CIFilter(name: "CILanczosScaleTransform") {
            lanczos.setValue(output, forKey: kCIInputImageKey)
            lanczos.setValue(scale, forKey: kCIInputScaleKey)
            lanczos.setValue(1.0, forKey: kCIInputAspectRatioKey)
            output = lanczos.outputImage ?? output
        }

        let (radius, intensity) = unsharpParameters
        if let unsharp = CIFilter(name: "CIUnsharpMask") {
            unsharp.setValue(output, forKey: kCIInputImageKey)
            unsharp.setValue(radius, forKey: kCIInputRadiusKey)
            unsharp.setValue(intensity, forKey: kCIInputIntensityKey)
            output = unsharp.outputImage ?? output
        }

        let target = CGRect(x: 0, y: 0, width: width, height: height)
        guard let result = ImageConversion.ciContext.createCGImage(
            output.cropped(to: target),
            from: target
        ) else {
            throw InferenceError.outputDecodingFailed
        }

        progress?(InferenceProgress(detail: "Done", fraction: 1))
        // Sharpening can darken transparent edges; restore the source's alpha.
        return ImageConversion.reapplyAlpha(from: image, onto: result)
    }

    private var unsharpParameters: (radius: Double, intensity: Double) {
        switch sharpening {
        case .textAndUI: return (0.54, 0.34)
        case .photoArtwork: return (1.1, 0.18)
        }
    }
}
