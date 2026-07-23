import AppKit
import CoreGraphics

/// Edits a grayscale layer mask (white = keep, black = hide) with soft brushes
/// and a flood-fill "magic wand".
enum MaskPainter {
    /// A fully-opaque (white) mask sized to the layer image — nothing hidden yet.
    static func fullMask(size: CGSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
    }

    /// Paint a soft circular dab into the mask. `reveal` paints white (keep),
    /// otherwise black (hide). `normalizedPoint` is top-left origin (0…1).
    static func paint(
        on mask: NSImage,
        atNormalized normalizedPoint: CGPoint,
        diameter: CGFloat,
        softness: CGFloat,
        reveal: Bool,
        opacity: Double = 1,
        roundness: CGFloat = 1,
        angle: Double = 0
    ) -> NSImage {
        paintStroke(on: mask, normalizedPoints: [normalizedPoint], diameter: diameter,
                    softness: softness, reveal: reveal, opacity: opacity,
                    roundness: roundness, angle: angle)
    }

    /// Paint many dabs (a whole stroke segment) in a SINGLE draw pass. Copying
    /// the full mask image once per dab was the source of severe lag — this
    /// draws the existing mask once and then stamps every dab onto it.
    static func paintStroke(
        on mask: NSImage,
        normalizedPoints points: [CGPoint],
        diameter: CGFloat,
        softness: CGFloat,
        reveal: Bool,
        opacity: Double = 1,
        roundness: CGFloat = 1,
        angle: Double = 0
    ) -> NSImage {
        guard !points.isEmpty else { return mask }
        let size = mask.size
        let w = max(Int(size.width.rounded()), 1)
        let h = max(Int(size.height.rounded()), 1)
        let radius = max(diameter / 2, 1)
        let inner = max(0, 1 - min(max(softness, 0), 1))
        let gray = CGColorSpaceCreateDeviceGray()

        // 1) Build the stroke's coverage in a grayscale buffer. Overlapping soft
        //    dabs are combined with .lighten (max), NOT added — so the soft edge
        //    (hardness) survives a dense stroke instead of filling in to a hard edge.
        guard let cov = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: gray,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return mask
        }
        cov.setFillColor(CGColor(gray: 0, alpha: 1))
        cov.fill(CGRect(x: 0, y: 0, width: w, height: h))
        cov.setBlendMode(.lighten)
        let softGradient = CGGradient(
            colorsSpace: gray,
            colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 0, alpha: 1)] as CFArray,
            locations: [inner, 1]
        )
        let roundY = max(min(roundness, 1), 0.05)
        for point in points {
            let cx = point.x * size.width
            let cy = (1 - point.y) * size.height // bottom-left origin
            cov.saveGState()
            cov.translateBy(x: cx, y: cy)
            cov.rotate(by: -angle * .pi / 180)
            cov.scaleBy(x: 1, y: roundY)
            cov.addEllipse(in: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
            cov.clip()
            if let softGradient {
                cov.drawRadialGradient(softGradient, startCenter: .zero, startRadius: 0,
                                       endCenter: .zero, endRadius: radius, options: [])
            } else {
                cov.setFillColor(CGColor(gray: 1, alpha: 1))
                cov.fill(CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
            }
            cov.restoreGState()
        }
        guard let coverageImage = cov.makeImage() else { return mask }

        // 2) Paint the mask colour once, through that coverage, at brush opacity.
        let result = NSImage(size: size)
        result.lockFocus()
        defer { result.unlockFocus() }
        mask.draw(in: CGRect(origin: .zero, size: size))
        if let ctx = NSGraphicsContext.current?.cgContext {
            let full = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            ctx.saveGState()
            ctx.clip(to: full, mask: coverageImage) // white coverage = painted
            ctx.setAlpha(CGFloat(min(max(opacity, 0), 1)))
            ctx.setFillColor(reveal ? CGColor(gray: 1, alpha: 1) : CGColor(gray: 0, alpha: 1))
            ctx.fill(full)
            ctx.restoreGState()
        }
        return result
    }

    /// Flood-fill from a point on `layerImage`, hiding the connected region of
    /// similar colour in `mask` (sets it black). Returns the updated mask.
    static func floodHide(
        mask: NSImage,
        layerImage: NSImage,
        atNormalized normalizedPoint: CGPoint,
        tolerance: CGFloat
    ) -> NSImage? {
        guard let cg = layerImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = cg.width, height = cg.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let ctx = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        let sx = min(max(Int(normalizedPoint.x * CGFloat(width)), 0), width - 1)
        let sy = min(max(Int(normalizedPoint.y * CGFloat(height)), 0), height - 1)

        func color(at i: Int) -> (Double, Double, Double) {
            let a = data[i + 3]
            if a == 0 { return (0, 0, 0) }
            let scale = 255.0 / Double(a)
            return (Double(data[i]) * scale, Double(data[i + 1]) * scale, Double(data[i + 2]) * scale)
        }
        let target = color(at: (sy * width + sx) * 4)
        let threshold = Double(max(0, min(tolerance, 1))) * 441.673

        // Build a black-fill region on a copy of the current mask.
        var visited = [Bool](repeating: false, count: width * height)
        var region = [Bool](repeating: false, count: width * height)
        var stack = [sy * width + sx]
        visited[sy * width + sx] = true
        while let p = stack.popLast() {
            let (r, g, b) = color(at: p * 4)
            let dr = r - target.0, dg = g - target.1, db = b - target.2
            if (dr * dr + dg * dg + db * db).squareRoot() > threshold { continue }
            region[p] = true
            let x = p % width, y = p / width
            if x > 0, !visited[p - 1] { visited[p - 1] = true; stack.append(p - 1) }
            if x < width - 1, !visited[p + 1] { visited[p + 1] = true; stack.append(p + 1) }
            if y > 0, !visited[p - width] { visited[p - width] = true; stack.append(p - width) }
            if y < height - 1, !visited[p + width] { visited[p + width] = true; stack.append(p + width) }
        }

        // Rasterise the current mask to the same grid and paint the region black.
        var maskData = [UInt8](repeating: 255, count: bytesPerRow * height)
        if let maskCG = mask.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let mctx = CGContext(data: &maskData, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            mctx.translateBy(x: 0, y: CGFloat(height))
            mctx.scaleBy(x: 1, y: -1)
            mctx.draw(maskCG, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        for p in 0..<(width * height) where region[p] {
            let i = p * 4
            maskData[i] = 0; maskData[i + 1] = 0; maskData[i + 2] = 0; maskData[i + 3] = 255
        }
        guard let mctx = CGContext(data: &maskData, width: width, height: height, bitsPerComponent: 8,
                                   bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let out = mctx.makeImage() else { return nil }
        return NSImage(cgImage: out, size: mask.size)
    }
}
