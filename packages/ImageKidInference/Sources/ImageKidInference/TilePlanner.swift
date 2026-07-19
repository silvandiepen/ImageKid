import CoreGraphics
import Foundation

/// One tile of an overlapped tiling plan.
///
/// A tile is read from `readRect` (which includes overlap padding so the model
/// sees context around the seams), upscaled, and then only its `coreRect`
/// portion is written into the output. Overlap is discarded, which removes the
/// visible seams tiling would otherwise produce.
public struct Tile: Equatable, Sendable {
    /// Region of the source to feed the model, including overlap, clamped to the
    /// source bounds. In source pixels.
    public let readRect: CGRect
    /// The non-overlapping region this tile owns in the output. In source pixels.
    public let coreRect: CGRect

    public init(readRect: CGRect, coreRect: CGRect) {
        self.readRect = readRect
        self.coreRect = coreRect
    }

    /// Where `coreRect` sits inside `readRect`, in source pixels (before scaling).
    public var coreOffsetInRead: CGRect {
        CGRect(
            x: coreRect.minX - readRect.minX,
            y: coreRect.minY - readRect.minY,
            width: coreRect.width,
            height: coreRect.height
        )
    }
}

/// Splits an image into overlapped tiles for models that only accept a fixed or
/// bounded input size. Pure geometry, so it is fully unit-testable without a
/// model or any Apple imaging framework at run time.
public enum TilePlanner {
    /// - Parameters:
    ///   - sourceWidth: source width in pixels.
    ///   - sourceHeight: source height in pixels.
    ///   - tileSize: the core (non-overlap) tile edge length in pixels.
    ///   - overlap: pixels of context added around each core tile before the model runs.
    /// - Returns: tiles covering the whole image with no gaps. A single tile is
    ///   returned when the image already fits within `tileSize`.
    public static func plan(
        sourceWidth: Int,
        sourceHeight: Int,
        tileSize: Int,
        overlap: Int
    ) -> [Tile] {
        let width = max(1, sourceWidth)
        let height = max(1, sourceHeight)
        let step = max(1, tileSize)
        let pad = max(0, overlap)

        let bounds = CGRect(x: 0, y: 0, width: width, height: height)

        if width <= step && height <= step {
            return [Tile(readRect: bounds, coreRect: bounds)]
        }

        var tiles: [Tile] = []
        var originY = 0
        while originY < height {
            let coreHeight = min(step, height - originY)
            var originX = 0
            while originX < width {
                let coreWidth = min(step, width - originX)
                let core = CGRect(x: originX, y: originY, width: coreWidth, height: coreHeight)
                let padded = CGRect(
                    x: originX - pad,
                    y: originY - pad,
                    width: coreWidth + pad * 2,
                    height: coreHeight + pad * 2
                )
                let read = padded.intersection(bounds).integral
                tiles.append(Tile(readRect: read, coreRect: core))
                originX += step
            }
            originY += step
        }
        return tiles
    }
}
