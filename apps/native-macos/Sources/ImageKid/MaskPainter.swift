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
        let size = mask.size
        let result = NSImage(size: size)
        result.lockFocus()
        defer { result.unlockFocus() }
        mask.draw(in: CGRect(origin: .zero, size: size))

        // NSImage is bottom-left origin; the mask is stored top-down.
        let center = CGPoint(x: normalizedPoint.x * size.width,
                             y: (1 - normalizedPoint.y) * size.height)
        let radius = max(diameter / 2, 1)
        let ry = radius * max(min(roundness, 1), 0.05)
        let alpha = CGFloat(min(max(opacity, 0), 1))
        let color = (reveal ? NSColor.white : NSColor.black).withAlphaComponent(alpha)
        let inner = max(0, 1 - min(max(softness, 0), 1))

        // Rotate/translate around the dab centre so the ellipse can be angled.
        guard let context = NSGraphicsContext.current else { return result }
        context.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y)
        transform.rotate(byDegrees: -angle)
        transform.concat()

        let ovalRect = CGRect(x: -radius, y: -ry, width: radius * 2, height: ry * 2)
        if let gradient = NSGradient(colors: [color, color.withAlphaComponent(0)],
                                     atLocations: [inner, 1], colorSpace: .deviceGray) {
            gradient.draw(in: NSBezierPath(ovalIn: ovalRect), relativeCenterPosition: .zero)
        } else {
            color.setFill()
            NSBezierPath(ovalIn: ovalRect).fill()
        }
        context.restoreGraphicsState()
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
