import CoreGraphics
import Foundation

/// Something that removes the background from an image, returning a `CGImage`
/// with the subject kept and the background made transparent (straight alpha).
public protocol BackgroundRemover: Sendable {
    func removeBackground(
        from image: CGImage,
        progress: InferenceProgressHandler?
    ) async throws -> CGImage
}

public extension BackgroundRemover {
    func removeBackground(from image: CGImage) async throws -> CGImage {
        try await removeBackground(from: image, progress: nil)
    }
}
