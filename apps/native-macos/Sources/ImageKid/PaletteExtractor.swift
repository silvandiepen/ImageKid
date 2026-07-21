import AppKit
import CoreGraphics

/// Extracts a small palette of dominant colours from an image using a
/// median-cut bucketing over a downsampled pixel set. Runs off the source
/// image directly; deterministic and dependency-free.
enum PaletteExtractor {
    private struct Pixel { var r: Int; var g: Int; var b: Int }

    static func dominantColors(from image: NSImage, count: Int = 6, sample: Int = 96) -> [NSColor] {
        guard count > 0,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }

        let width = max(1, min(sample, cgImage.width))
        let height = max(1, Int((Double(cgImage.height) / Double(cgImage.width) * Double(width)).rounded()))
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let ctx = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var pixels: [Pixel] = []
        pixels.reserveCapacity(width * height)
        for i in stride(from: 0, to: data.count, by: bytesPerPixel) {
            let a = data[i + 3]
            if a < 24 { continue } // skip transparent pixels (e.g. after cutout)
            pixels.append(Pixel(r: Int(data[i]), g: Int(data[i + 1]), b: Int(data[i + 2])))
        }
        guard !pixels.isEmpty else { return [] }

        let buckets = medianCut(pixels, into: count)
        return buckets.compactMap(averageColor)
    }

    private static func medianCut(_ pixels: [Pixel], into target: Int) -> [[Pixel]] {
        var buckets: [[Pixel]] = [pixels]
        while buckets.count < target {
            // Split the bucket with the largest colour range along its widest channel.
            guard let index = buckets.enumerated()
                .filter({ $0.element.count > 1 })
                .max(by: { range($0.element) < range($1.element) })?.offset else { break }

            var bucket = buckets.remove(at: index)
            let channel = widestChannel(bucket)
            bucket.sort { value($0, channel) < value($1, channel) }
            let mid = bucket.count / 2
            buckets.append(Array(bucket[..<mid]))
            buckets.append(Array(bucket[mid...]))
        }
        return buckets
    }

    private static func value(_ p: Pixel, _ channel: Int) -> Int {
        channel == 0 ? p.r : (channel == 1 ? p.g : p.b)
    }

    private static func widestChannel(_ pixels: [Pixel]) -> Int {
        var lo = Pixel(r: 255, g: 255, b: 255)
        var hi = Pixel(r: 0, g: 0, b: 0)
        for p in pixels {
            lo = Pixel(r: min(lo.r, p.r), g: min(lo.g, p.g), b: min(lo.b, p.b))
            hi = Pixel(r: max(hi.r, p.r), g: max(hi.g, p.g), b: max(hi.b, p.b))
        }
        let rr = hi.r - lo.r, gr = hi.g - lo.g, br = hi.b - lo.b
        if rr >= gr && rr >= br { return 0 }
        return gr >= br ? 1 : 2
    }

    private static func range(_ pixels: [Pixel]) -> Int {
        guard !pixels.isEmpty else { return 0 }
        var lo = Pixel(r: 255, g: 255, b: 255)
        var hi = Pixel(r: 0, g: 0, b: 0)
        for p in pixels {
            lo = Pixel(r: min(lo.r, p.r), g: min(lo.g, p.g), b: min(lo.b, p.b))
            hi = Pixel(r: max(hi.r, p.r), g: max(hi.g, p.g), b: max(hi.b, p.b))
        }
        return (hi.r - lo.r) + (hi.g - lo.g) + (hi.b - lo.b)
    }

    private static func averageColor(_ pixels: [Pixel]) -> NSColor? {
        guard !pixels.isEmpty else { return nil }
        let total = pixels.reduce((r: 0, g: 0, b: 0)) { ($0.r + $1.r, $0.g + $1.g, $0.b + $1.b) }
        let n = CGFloat(pixels.count)
        return NSColor(
            srgbRed: CGFloat(total.r) / n / 255,
            green: CGFloat(total.g) / n / 255,
            blue: CGFloat(total.b) / n / 255,
            alpha: 1
        )
    }
}
