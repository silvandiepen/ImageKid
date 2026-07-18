import CoreGraphics
import Foundation

/// How an upscaler should treat the image content.
public enum UpscaleContentMode: String, Sendable, CaseIterable {
    /// Let the engine choose based on the image (screenshot/UI vs photo).
    case automatic
    /// Sharp-edged content: screenshots, diagrams, text. Favours crisp edges.
    case textAndUI
    /// Continuous-tone content: photos and artwork. Favours a neural model.
    case photoArtwork
}

/// Something that enlarges a `CGImage` to a target pixel size.
///
/// Implementations run off the main actor and are safe to call from a
/// background task. `targetSize` is in output pixels.
public protocol ImageUpscaler: Sendable {
    func upscale(
        _ image: CGImage,
        to targetSize: CGSize,
        progress: InferenceProgressHandler?
    ) async throws -> CGImage
}

public extension ImageUpscaler {
    func upscale(_ image: CGImage, to targetSize: CGSize) async throws -> CGImage {
        try await upscale(image, to: targetSize, progress: nil)
    }
}
