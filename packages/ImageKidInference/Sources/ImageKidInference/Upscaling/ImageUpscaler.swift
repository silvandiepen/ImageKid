import CoreGraphics
import Foundation

/// How an upscaler should treat the image content.
public enum UpscaleContentMode: String, Sendable, CaseIterable, Identifiable {
    /// Let the engine choose based on the image (screenshot/UI vs photo).
    case automatic
    /// Sharp-edged content: screenshots, diagrams, text. Favours crisp edges.
    case textAndUI
    /// Continuous-tone content: photos and artwork. Favours a neural model.
    case photoArtwork

    public var id: String { rawValue }

    /// Human label, shared by both apps.
    public var label: String {
        switch self {
        case .automatic: "Auto"
        case .textAndUI: "Text & UI"
        case .photoArtwork: "Photo & Artwork"
        }
    }

    /// Resolves `.automatic` to a concrete mode by sampling the image; other modes
    /// pass through. Shared logic so macOS and iOS classify content identically.
    public static func resolved(_ mode: UpscaleContentMode, for image: CGImage) -> UpscaleContentMode {
        guard mode == .automatic else { return mode }
        return looksLikeScreenshotOrUI(image) ? .textAndUI : .photoArtwork
    }

    /// Compact screenshot/UI vs photo heuristic: UI/screenshots have few distinct
    /// colours and hard edges; photos have many colours and soft gradients.
    private static func looksLikeScreenshotOrUI(_ image: CGImage) -> Bool {
        let size = 64
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let context = CGContext(
            data: &pixels, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: size * 4, space: ImageConversion.sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

        var buckets = Set<Int>()
        var hardEdges = 0
        var comparisons = 0
        func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = (y * size + x) * 4
            return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
        }
        for y in 0..<size {
            for x in 0..<size {
                let (r, g, b) = rgb(x, y)
                buckets.insert((r / 24) << 16 | (g / 24) << 8 | (b / 24))
                if x > 0 {
                    let (pr, pg, pb) = rgb(x - 1, y)
                    if abs(r - pr) + abs(g - pg) + abs(b - pb) > 90 { hardEdges += 1 }
                    comparisons += 1
                }
            }
        }
        let edgeRatio = comparisons > 0 ? Double(hardEdges) / Double(comparisons) : 0
        let colourRatio = Double(buckets.count) / Double(size * size)
        // Few colours + frequent hard edges → screenshot/UI/text.
        return colourRatio < 0.12 && edgeRatio > 0.05
    }
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
