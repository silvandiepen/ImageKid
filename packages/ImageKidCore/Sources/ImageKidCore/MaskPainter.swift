import CoreGraphics
import CoreImage
import Foundation

/// Edits a grayscale layer mask (white = keep, black = hide) with soft brushes
/// and a flood-fill "magic wand". Shared by both apps; all drawing goes through
/// portable CoreGraphics via `PlatformRender` (bottom-left, y-up context).
public enum MaskPainter {
    /// Invert a grayscale mask (white ⇄ black), i.e. swap shown and hidden.
    public static func invert(_ mask: PlatformImage) -> PlatformImage {
        guard let cg = mask.cgImageForRendering else { return mask }
        let inverted = CIImage(cgImage: cg).applyingFilter("CIColorInvert")
        return PlatformRender.image(from: inverted, size: mask.size) ?? mask
    }

    /// A fully-opaque (white) mask sized to the layer image — nothing hidden yet.
    public static func fullMask(size: CGSize) -> PlatformImage {
        PlatformRender.image(size: size) { ctx in
            ctx.setFillColor(PlatformColor.white.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// Paint a soft circular dab into the mask. `reveal` paints white (keep),
    /// otherwise black (hide). `normalizedPoint` is top-left origin (0…1).
    public static func paint(
        on mask: PlatformImage,
        atNormalized normalizedPoint: CGPoint,
        diameter: CGFloat,
        softness: CGFloat,
        reveal: Bool,
        opacity: Double = 1,
        roundness: CGFloat = 1,
        angle: Double = 0
    ) -> PlatformImage {
        paintStroke(on: mask, normalizedPoints: [normalizedPoint], diameter: diameter,
                    softness: softness, reveal: reveal, opacity: opacity,
                    roundness: roundness, angle: angle)
    }

    /// Paint a whole stroke as ONE solid shape (line of `diameter` width through
    /// all the points), then blur it by `softness` and composite onto the mask.
    /// Because the stroke is a single shape, overlapping dabs never build up, so
    /// the soft edge (hardness) is uniform along the whole stroke.
    public static func paintStroke(
        on mask: PlatformImage,
        normalizedPoints points: [CGPoint],
        diameter: CGFloat,
        softness: CGFloat,
        reveal: Bool,
        opacity: Double = 1,
        roundness: CGFloat = 1,
        angle: Double = 0
    ) -> PlatformImage {
        guard !points.isEmpty else { return mask }
        let size = mask.size
        let radius = max(diameter / 2, 1)
        let color = (reveal ? PlatformColor.white : PlatformColor.black).cgColor

        // 1) Draw the whole stroke as one solid shape in a clear buffer.
        let strokeImage = PlatformRender.image(size: size) { ctx in
            let pts = points.map { CGPoint(x: $0.x * size.width, y: (1 - $0.y) * size.height) }
            if pts.count == 1 {
                ctx.setFillColor(color)
                ctx.fillEllipse(in: CGRect(x: pts[0].x - radius, y: pts[0].y - radius,
                                           width: radius * 2, height: radius * 2))
            } else {
                let path = CGMutablePath()
                path.move(to: pts[0])
                if pts.count < 3 {
                    for p in pts.dropFirst() { path.addLine(to: p) }
                } else {
                    for i in 1..<(pts.count - 1) {
                        let cur = pts[i], next = pts[i + 1]
                        let mid = CGPoint(x: (cur.x + next.x) / 2, y: (cur.y + next.y) / 2)
                        path.addCurve(to: mid, control1: cur, control2: cur)
                    }
                    path.addLine(to: pts[pts.count - 1])
                }
                ctx.addPath(path)
                ctx.setStrokeColor(color)
                ctx.setLineWidth(radius * 2)
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)
                ctx.strokePath()
            }
        }

        // 2) Blur the whole stroke by softness (uniform soft edge, no buildup).
        let blurRadius = CGFloat(min(max(softness, 0), 1)) * radius
        let paint = blurRadius > 0.5 ? gaussianBlur(strokeImage, radius: blurRadius) : strokeImage

        // 3) Composite the (blurred) stroke over the mask at brush opacity.
        let rect = CGRect(origin: .zero, size: size)
        return PlatformRender.image(size: size) { ctx in
            if let maskCG = mask.cgImageForRendering { ctx.draw(maskCG, in: rect) }
            ctx.setAlpha(CGFloat(min(max(opacity, 0), 1)))
            if let paintCG = paint.cgImageForRendering { ctx.draw(paintCG, in: rect) }
        }
    }

    private static func gaussianBlur(_ image: PlatformImage, radius: CGFloat) -> PlatformImage {
        guard let cg = image.cgImageForRendering else { return image }
        let ci = CIImage(cgImage: cg)
        let blurred = ci.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: ci.extent)
        return PlatformRender.image(from: blurred, size: image.size, cropTo: ci.extent) ?? image
    }

    /// Flood-fill from a point on `layerImage`, hiding the connected region of
    /// similar colour in `mask` (sets it black). Returns the updated mask.
    public static func floodHide(
        mask: PlatformImage,
        layerImage: PlatformImage,
        atNormalized normalizedPoint: CGPoint,
        tolerance: CGFloat
    ) -> PlatformImage? {
        guard let cg = layerImage.cgImageForRendering else { return nil }
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
        if let maskCG = mask.cgImageForRendering,
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
        return .fromCGImage(out, size: mask.size)
    }
}
