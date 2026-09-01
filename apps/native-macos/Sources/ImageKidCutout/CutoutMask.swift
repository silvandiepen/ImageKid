import AppKit
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// The editable alpha of one cutout.
///
/// Three layers, kept apart on purpose. `baseAlpha` is what the model produced and is
/// never written to. `strength` is a levels curve over it — the dial for how much of a
/// soft edge counts as background. `strokes` are the corrections painted on top. The
/// coverage buffer the renderer reads is rebuilt from those three, so the strength can
/// be changed at any time without losing a single brush stroke, and undo is just
/// dropping the last stroke and rebuilding.
final class CutoutMask {
    /// What a stroke does to the coverage.
    enum Tool {
        case erase
        case restore
    }

    /// How a stroke is read. `brush` takes exactly what it covers; `region` treats the
    /// stroke as a rough sample of a region and follows that region out to its edges.
    enum StrokeMode {
        case brush
        case region
    }

    struct Stroke {
        var points: [CGPoint]
        var diameter: CGFloat
        var hardness: CGFloat
        var tool: Tool
        var mode: StrokeMode = .brush
        var tolerance: CGFloat = 0.2
    }

    let source: CGImage
    /// 0.5 leaves the model's mask exactly as it came. Lower keeps more of the image,
    /// higher removes more.
    private(set) var strength: CGFloat = 0.5

    private let baseAlpha: [UInt8]
    private let buffer: UnsafeMutableRawPointer
    private let byteCount: Int
    private let context: CGContext
    private let renderContext: CIContext
    private var strokes: [Stroke] = []
    private var currentStroke: Stroke?
    /// The source as straight RGBA, kept for the seeded flood. Built once, on demand.
    private var cachedSourcePixels: [UInt8]?

    /// Linear, not device gray. Core Image converts a device-gray mask from sRGB into
    /// its linear working space, so a stored 128 arrived at the blend as 55 and every
    /// soft edge came out far more transparent than the model meant it to be. In a
    /// linear space the coverage passes through untouched.
    private static let coverageSpace = CGColorSpace(name: CGColorSpace.linearGray)
        ?? CGColorSpaceCreateDeviceGray()

    var pixelSize: CGSize {
        CGSize(width: source.width, height: source.height)
    }

    var canUndo: Bool {
        !strokes.isEmpty
    }

    /// True once the model's own mask is in play. Without one there is nothing for the
    /// strength dial to act on.
    let hasModelMask: Bool

    /// - Parameter cutout: a previously produced cutout whose alpha seeds the coverage.
    ///   Without one the mask starts fully opaque, which is the honest starting point
    ///   for an image whose background has not been removed yet.
    init?(source: CGImage, cutout: CGImage?, strength: CGFloat = 0.5) {
        let width = source.width
        let height = source.height
        let byteCount = width * height
        guard byteCount > 0 else { return nil }

        var base = [UInt8](repeating: 255, count: byteCount)
        if let cutout {
            // Drawing into an alpha-only context copies the cutout's alpha channel
            // straight out — no colour conversion to get wrong.
            base = [UInt8](repeating: 0, count: byteCount)
            base.withUnsafeMutableBytes { raw in
                guard
                    let pointer = raw.baseAddress,
                    let alphaContext = CGContext(
                        data: pointer,
                        width: width,
                        height: height,
                        bitsPerComponent: 8,
                        bytesPerRow: width,
                        space: CGColorSpaceCreateDeviceGray(),
                        bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
                    )
                else {
                    return
                }
                alphaContext.draw(cutout, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
        }

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 1)
        buffer.initializeMemory(as: UInt8.self, repeating: 255, count: byteCount)

        guard let context = CGContext(
            data: buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: Self.coverageSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            buffer.deallocate()
            return nil
        }

        self.source = source
        self.baseAlpha = base
        self.hasModelMask = cutout != nil
        self.buffer = buffer
        self.byteCount = byteCount
        self.context = context
        self.renderContext = CIContext(options: [.cacheIntermediates: false])
        self.strength = strength

        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setShouldAntialias(true)
        rebuild()
    }

    deinit {
        buffer.deallocate()
    }

    // MARK: - Strength

    func setStrength(_ value: CGFloat) {
        let clamped = min(1, max(0, value))
        guard clamped != strength else { return }
        strength = clamped
        rebuild()
    }

    // MARK: - Strokes

    func beginStroke(
        diameter: CGFloat,
        hardness: CGFloat,
        tool: Tool,
        mode: StrokeMode = .brush,
        tolerance: CGFloat = 0.2
    ) {
        currentStroke = Stroke(
            points: [],
            diameter: diameter,
            hardness: hardness,
            tool: tool,
            mode: mode,
            tolerance: tolerance
        )
    }

    /// The last point of the last stroke, so a shift-click can continue from it.
    var lastStrokeEnd: CGPoint? {
        currentStroke?.points.last ?? strokes.last?.points.last
    }

    /// Extends the stroke in progress. Only the new segment is drawn — a full rebuild
    /// per mouse move would be pointless work.
    func paint(to point: CGPoint) {
        guard var stroke = currentStroke else { return }
        let from = stroke.points.last ?? point
        stroke.points.append(point)
        currentStroke = stroke
        draw(segmentFrom: from, to: point, stroke: stroke)
    }

    func endStroke() {
        guard let stroke = currentStroke, !stroke.points.isEmpty else {
            currentStroke = nil
            return
        }
        strokes.append(stroke)
        currentStroke = nil
        // A seeded flood only runs once the whole stroke is known — during the drag the
        // brush paints normally so there is immediate feedback, and the rebuild replaces
        // it with the region the flood actually found.
        if stroke.mode == .region {
            rebuild()
        }
    }

    func undo() {
        guard !strokes.isEmpty else { return }
        strokes.removeLast()
        rebuild()
    }

    // MARK: - Rendering

    /// The source composited through the current coverage.
    func render() -> CGImage? {
        guard let mask = context.makeImage() else { return nil }
        let sourceImage = CIImage(cgImage: source)
        let filter = CIFilter.blendWithMask()
        filter.inputImage = sourceImage
        filter.backgroundImage = CIImage(color: .clear).cropped(to: sourceImage.extent)
        filter.maskImage = CIImage(cgImage: mask)
        guard let output = filter.outputImage else { return nil }
        return renderContext.createCGImage(output, from: sourceImage.extent)
    }

    // MARK: - Internals

    /// Coverage = the model's alpha through the strength curve, then every stroke replayed.
    private func rebuild() {
        let table = Self.levels(strength: strength)
        let destination = buffer.assumingMemoryBound(to: UInt8.self)
        baseAlpha.withUnsafeBufferPointer { base in
            for index in 0..<byteCount {
                destination[index] = table[Int(base[index])]
            }
        }
        for stroke in strokes {
            draw(stroke)
        }
        if let currentStroke {
            draw(currentStroke)
        }
    }

    /// A levels curve on the model's mask. 0.5 is identity; below it the mask is lifted
    /// so soft edges survive, above it they are pushed to nothing.
    private static func levels(strength: CGFloat) -> [UInt8] {
        let low = max(0, 2 * strength - 1)
        let high = min(1, 2 * strength)
        let span = max(0.001, high - low)
        return (0...255).map { value in
            let normalised = (CGFloat(value) / 255 - low) / span
            return UInt8(min(255, max(0, normalised * 255)).rounded())
        }
    }

    private func draw(_ stroke: Stroke) {
        guard let first = stroke.points.first else { return }
        if stroke.mode == .region {
            floodRegion(stroke)
            return
        }
        var previous = first
        for point in stroke.points {
            draw(segmentFrom: previous, to: point, stroke: stroke)
            previous = point
        }
    }

    /// Applies the stroke's tool to the whole region it sits in: the colours under the
    /// brush seed a flood that spreads through neighbouring pixels of a similar colour
    /// and stops at the edge of the region. Rough input, exact result — and it removes or
    /// restores according to the tool, so the same gesture works both ways.
    private func floodRegion(_ stroke: Stroke) {
        guard let pixels = sourcePixels() else { return }
        let width = source.width
        let height = source.height
        let count = width * height
        let radius = max(1, Int(stroke.diameter / 2))

        var visited = [Bool](repeating: false, count: count)
        var stack: [Int] = []
        var reds: [Int] = []
        var greens: [Int] = []
        var blues: [Int] = []

        for point in stroke.points {
            let cx = Int(point.x)
            let cy = Int(point.y)
            for y in max(0, cy - radius)...min(height - 1, cy + radius) {
                for x in max(0, cx - radius)...min(width - 1, cx + radius) {
                    let dx = x - cx
                    let dy = y - cy
                    guard dx * dx + dy * dy <= radius * radius else { continue }
                    let index = y * width + x
                    guard !visited[index] else { continue }
                    visited[index] = true
                    stack.append(index)
                    let base = index * 4
                    reds.append(Int(pixels[base]))
                    greens.append(Int(pixels[base + 1]))
                    blues.append(Int(pixels[base + 2]))
                }
            }
        }
        guard !reds.isEmpty else { return }

        // Median, so a stroke that clips the subject at its edges is not dragged towards it.
        reds.sort(); greens.sort(); blues.sort()
        let middle = reds.count / 2
        let seed = (reds[middle], greens[middle], blues[middle])

        let limit = max(2, Int((stroke.tolerance * 255).rounded()))
        let solid = max(1, limit / 2)
        let destination = buffer.assumingMemoryBound(to: UInt8.self)

        func gap(at index: Int) -> Int {
            let base = index * 4
            return max(
                abs(Int(pixels[base]) - seed.0),
                max(abs(Int(pixels[base + 1]) - seed.1), abs(Int(pixels[base + 2]) - seed.2))
            )
        }

        // The guard is not an optimisation: a stroke that strays onto the subject seeds
        // pixels far outside the tolerance, and the ramp then computes past 255 and traps
        // on the way into UInt8. Those pixels are not part of the region anyway.
        let restoring = stroke.tool == .restore
        func settle(_ index: Int, _ distance: Int) {
            guard distance <= limit else { return }
            // 0 at the heart of the region, rising to 255 at the tolerance edge, so the
            // effect fades out rather than leaving a cut line.
            let fade = distance <= solid
                ? 0
                : min(255, (distance - solid) * 255 / max(1, limit - solid))
            if restoring {
                destination[index] = max(destination[index], UInt8(255 - fade))
            } else {
                destination[index] = min(destination[index], UInt8(fade))
            }
        }

        for index in stack {
            settle(index, gap(at: index))
        }

        while let index = stack.popLast() {
            let x = index % width
            let y = index / width

            func consider(_ neighbour: Int) {
                guard !visited[neighbour] else { return }
                visited[neighbour] = true
                let distance = gap(at: neighbour)
                guard distance <= limit else { return }
                settle(neighbour, distance)
                stack.append(neighbour)
            }

            if x > 0 { consider(index - 1) }
            if x < width - 1 { consider(index + 1) }
            if y > 0 { consider(index - width) }
            if y < height - 1 { consider(index + width) }
        }
    }

    private func sourcePixels() -> [UInt8]? {
        if let cachedSourcePixels { return cachedSourcePixels }
        let width = source.width
        let height = source.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            pixels.withUnsafeMutableBytes({ raw -> Bool in
                guard let context = CGContext(
                    data: raw.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                ) else {
                    return false
                }
                context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            })
        else {
            return nil
        }
        cachedSourcePixels = pixels
        return pixels
    }

    /// Points are in image pixels with a top-left origin, which is what the view hands
    /// over; the context works bottom-up.
    private func draw(segmentFrom start: CGPoint, to end: CGPoint, stroke: Stroke) {
        let height = CGFloat(source.height)
        let from = CGPoint(x: start.x, y: height - start.y)
        let to = CGPoint(x: end.x, y: height - end.y)
        let value: CGFloat = stroke.tool == .restore ? 1 : 0

        context.saveGState()
        defer { context.restoreGState() }

        guard stroke.hardness < 0.99 else {
            context.setStrokeColor(gray: value, alpha: 1)
            context.setLineWidth(max(1, stroke.diameter))
            context.move(to: from)
            context.addLine(to: to)
            context.strokePath()
            return
        }

        let radius = max(0.5, stroke.diameter / 2)
        let inner = radius * max(0, min(1, stroke.hardness))
        guard let gradient = CGGradient(
            colorSpace: Self.coverageSpace,
            colorComponents: [value, 1, value, 0],
            locations: [0, 1],
            count: 2
        ) else {
            return
        }

        // A soft brush is stamped along the segment rather than stroked, because a
        // stroke has one flat colour and no falloff.
        let distance = hypot(to.x - from.x, to.y - from.y)
        let steps = max(1, Int(distance / max(1, radius * 0.2)))
        for step in 0...steps {
            let progress = CGFloat(step) / CGFloat(steps)
            let point = CGPoint(
                x: from.x + (to.x - from.x) * progress,
                y: from.y + (to.y - from.y) * progress
            )
            context.saveGState()
            context.addEllipse(in: CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            context.clip()
            context.drawRadialGradient(
                gradient,
                startCenter: point,
                startRadius: inner,
                endCenter: point,
                endRadius: radius,
                options: [.drawsBeforeStartLocation]
            )
            context.restoreGState()
        }
    }
}
