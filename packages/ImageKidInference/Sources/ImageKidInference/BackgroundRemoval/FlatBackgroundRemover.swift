import CoreGraphics
import Foundation

/// Background removal for images that were rendered or shot on a flat backdrop.
///
/// A saliency model answers "what is the subject here", which is the wrong question
/// for a product render or a generated asset: it drops anything it does not read as
/// the subject, so a river, a shadow or a base plate disappears with the backdrop.
/// This asks the question the image actually poses — "what is the backdrop" — by
/// sampling the border colour and flooding inwards from the edges. Anything the flood
/// cannot reach is kept, whatever it looks like.
public struct FlatBackgroundRemover: BackgroundRemover {
    /// How far a colour may sit from the backdrop and still count as backdrop, as a
    /// fraction of the full channel range. Larger removes more.
    public var tolerance: Double

    public init(tolerance: Double = 0.12) {
        self.tolerance = tolerance
    }

    public func removeBackground(
        from image: CGImage,
        progress: InferenceProgressHandler?
    ) async throws -> CGImage {
        progress?(InferenceProgress(detail: "Reading the image", fraction: 0.1))

        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { throw InferenceError.outputDecodingFailed }

        let count = width * height
        var pixels = [UInt8](repeating: 0, count: count * 4)
        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = pixels.withUnsafeMutableBytes({ raw in
                CGContext(
                    data: raw.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            })
        else {
            throw InferenceError.outputDecodingFailed
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        progress?(InferenceProgress(detail: "Finding the backdrop", fraction: 0.4))
        let backdrop = Self.borderColour(of: pixels, width: width, height: height)
        let limit = max(1, Int((tolerance * 255).rounded()))
        // Fully transparent up to half the tolerance, then ramping back to opaque, so
        // the cut keeps the anti-aliased edge the render already has.
        let solid = max(1, limit / 2)

        progress?(InferenceProgress(detail: "Separating the subject", fraction: 0.6))
        let alpha = Self.floodAlpha(
            pixels: pixels,
            width: width,
            height: height,
            backdrop: backdrop,
            limit: limit,
            solid: solid
        )

        progress?(InferenceProgress(detail: "Writing the cutout", fraction: 0.9))
        for index in 0..<count {
            let base = index * 4
            let coverage = Int(alpha[index])
            guard coverage < 255 else { continue }
            // The buffer is premultiplied, so colour has to come down with the alpha.
            pixels[base] = UInt8(Int(pixels[base]) * coverage / 255)
            pixels[base + 1] = UInt8(Int(pixels[base + 1]) * coverage / 255)
            pixels[base + 2] = UInt8(Int(pixels[base + 2]) * coverage / 255)
            pixels[base + 3] = UInt8(Int(pixels[base + 3]) * coverage / 255)
        }

        guard
            let output = pixels.withUnsafeMutableBytes({ raw -> CGImage? in
                guard let rewritten = CGContext(
                    data: raw.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else {
                    return nil
                }
                return rewritten.makeImage()
            })
        else {
            throw InferenceError.outputDecodingFailed
        }

        progress?(InferenceProgress(detail: "Done", fraction: 1))
        return output
    }

    /// The median of the border pixels. A median rather than a mean so a subject that
    /// touches one edge cannot drag the reading towards itself.
    static func borderColour(of pixels: [UInt8], width: Int, height: Int) -> (Int, Int, Int) {
        var reds: [UInt8] = []
        var greens: [UInt8] = []
        var blues: [UInt8] = []
        reds.reserveCapacity((width + height) * 2)

        func sample(_ x: Int, _ y: Int) {
            let base = (y * width + x) * 4
            reds.append(pixels[base])
            greens.append(pixels[base + 1])
            blues.append(pixels[base + 2])
        }

        for x in 0..<width {
            sample(x, 0)
            sample(x, height - 1)
        }
        for y in 0..<height {
            sample(0, y)
            sample(width - 1, y)
        }

        func median(_ values: inout [UInt8]) -> Int {
            values.sort()
            return Int(values[values.count / 2])
        }
        return (median(&reds), median(&greens), median(&blues))
    }

    /// Flood fill inwards from every edge pixel that matches the backdrop, and grade the
    /// result by how close each pixel came. Interior pixels that happen to share the
    /// backdrop colour are untouched, because the flood never reaches them.
    static func floodAlpha(
        pixels: [UInt8],
        width: Int,
        height: Int,
        backdrop: (Int, Int, Int),
        limit: Int,
        solid: Int
    ) -> [UInt8] {
        var alpha = [UInt8](repeating: 255, count: width * height)
        var visited = [Bool](repeating: false, count: width * height)
        var stack: [Int] = []
        stack.reserveCapacity(width * 4)

        func distance(at index: Int) -> Int {
            let base = index * 4
            let dr = abs(Int(pixels[base]) - backdrop.0)
            let dg = abs(Int(pixels[base + 1]) - backdrop.1)
            let db = abs(Int(pixels[base + 2]) - backdrop.2)
            return max(dr, max(dg, db))
        }

        func push(_ index: Int) {
            guard !visited[index] else { return }
            visited[index] = true
            let gap = distance(at: index)
            guard gap <= limit else { return }
            alpha[index] = gap <= solid
                ? 0
                : UInt8((gap - solid) * 255 / max(1, limit - solid))
            stack.append(index)
        }

        for x in 0..<width {
            push(x)
            push((height - 1) * width + x)
        }
        for y in 0..<height {
            push(y * width)
            push(y * width + width - 1)
        }

        while let index = stack.popLast() {
            let x = index % width
            let y = index / width
            if x > 0 { push(index - 1) }
            if x < width - 1 { push(index + 1) }
            if y > 0 { push(index - width) }
            if y < height - 1 { push(index + width) }
        }

        return alpha
    }
}
