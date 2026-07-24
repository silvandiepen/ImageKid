import CoreGraphics
import Foundation

/// A CPU, CoreGraphics reference renderer for dabs. NOT the live path — that is
/// Metal in BrushRender — but the ground truth the headless `brush` CLI and the
/// tests render with, and a portable fallback. Stamps each dab as a radial-
/// gradient disc (hardness = the solid core fraction), so soft brushes feather
/// and crisp brushes stay tight. Premultiplied-alpha "over" compositing.
///
/// The context is top-left origin here (pixel buffers), which is all the tests
/// and PNG export need; the app's live canvas handles its own orientation.
public enum ReferenceRenderer {
    /// Render dabs into a new RGBA8 premultiplied bitmap of `size` pixels.
    /// `background` fills first (nil = transparent).
    public static func render(
        dabs: [Dab], size: CGSize, background: RGBA? = nil
    ) -> CGImage? {
        let w = Int(size.width.rounded())
        let h = Int(size.height.rounded())
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
            let ctx = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        if let bg = background {
            ctx.setFillColor(cgColor(bg))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
        // Flip to a top-left origin so a dab at input y paints at bitmap row y —
        // matching BrushRender's Metal shader and the document's coordinates.
        // (CoreGraphics' native origin is bottom-left.)
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        for dab in dabs {
            stamp(dab, in: ctx)
        }
        return ctx.makeImage()
    }

    /// Convenience: generate and render a stroke in one call.
    public static func render(
        stroke: StrokeInput, brush: Brush, color: RGBA, size: CGSize,
        background: RGBA? = nil, seed: UInt64 = 0
    ) -> CGImage? {
        let dabs = BrushEngine.dabs(for: stroke, brush: brush, color: color, seed: seed)
        return render(dabs: dabs, size: size, background: background)
    }

    private static func stamp(_ dab: Dab, in ctx: CGContext) {
        let radius = dab.diameter / 2
        guard radius > 0, dab.alpha > 0 else { return }
        // Grain (per-pixel tooth) and square tips can't be a round gradient fill:
        // render those as a small per-pixel buffer.
        if dab.grainDepth > 0 || dab.square {
            stampPerPixel(dab, in: ctx)
            return
        }
        ctx.saveGState()
        ctx.translateBy(x: dab.position.x, y: dab.position.y)
        ctx.rotate(by: CGFloat(dab.angle))
        ctx.scaleBy(x: 1, y: CGFloat(dab.roundness))  // ellipse via y-squash

        let core = RGBA(r: dab.color.r, g: dab.color.g, b: dab.color.b, a: dab.alpha)
        let edge = RGBA(r: dab.color.r, g: dab.color.g, b: dab.color.b, a: 0)
        // hardness = fraction of the radius that stays fully solid before the
        // gradient falls off. A crisp brush (hardness→1) is nearly a flat disc.
        let solid = CGFloat(min(max(dab.hardness, 0), 0.999))
        if solid >= 0.999 {
            ctx.setFillColor(cgColor(core))
            ctx.fillEllipse(in: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
        } else if let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [cgColor(core), cgColor(core), cgColor(edge)] as CFArray,
            locations: [0, solid, 1])
        {
            ctx.addEllipse(in: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
            ctx.clip()
            ctx.drawRadialGradient(
                gradient, startCenter: .zero, startRadius: 0, endCenter: .zero,
                endRadius: radius, options: [])
        }
        ctx.restoreGState()
    }

    /// Per-pixel stamp: build a small premultiplied RGBA8 tile with the tip
    /// falloff (round or square) × canvas-space grain, then draw it. Slower than
    /// the gradient path, so used only for grained or square dabs — the CPU
    /// renderer is the tests/CLI/flatten path; the live canvas is Metal.
    private static func stampPerPixel(_ dab: Dab, in ctx: CGContext) {
        let radius = dab.diameter / 2
        // The stamp's axis-aligned bounding box in canvas space (rotation of an
        // ellipse fits inside the round bbox of `radius`).
        let cx = dab.position.x
        let cy = dab.position.y
        let side = Int((radius * 2).rounded(.up)) + 2
        guard side > 0 else { return }
        let originX = Int((cx - Double(side) / 2).rounded())
        let originY = Int((cy - Double(side) / 2).rounded())

        let ca = cos(-dab.angle)
        let sa = sin(-dab.angle)
        let solid = min(max(dab.hardness, 0), 0.999)
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let r = UInt8(min(max(dab.color.r, 0), 1) * 255)
        let g = UInt8(min(max(dab.color.g, 0), 1) * 255)
        let b = UInt8(min(max(dab.color.b, 0), 1) * 255)

        for py in 0..<side {
            for px in 0..<side {
                let canvasX = Double(originX + px) + 0.5
                let canvasY = Double(originY + py) + 0.5
                // Into the dab's local (unrotated, un-squashed) unit space.
                let dx = canvasX - cx
                let dy = canvasY - cy
                let lx = (dx * ca - dy * sa) / radius
                let ly = (dx * sa + dy * ca) / (radius * max(dab.roundness, 0.05))
                // Round tips fall off by radius; square tips by the larger axis
                // (Chebyshev), giving a hard-cornered footprint.
                let dist = dab.square ? max(abs(lx), abs(ly)) : (lx * lx + ly * ly).squareRoot()
                if dist > 1 { continue }
                var cov = dist <= solid ? 1 : 1 - (dist - solid) / (1 - solid)
                cov *= GrainNoise.coverage(
                    x: canvasX, y: canvasY, cell: dab.grainCell, depth: dab.grainDepth,
                    seed: dab.grainSeed)
                let a = cov * dab.alpha
                guard a > 0 else { continue }
                let i = (py * side + px) * 4
                // Premultiplied last.
                pixels[i] = UInt8(Double(r) * a)
                pixels[i + 1] = UInt8(Double(g) * a)
                pixels[i + 2] = UInt8(Double(b) * a)
                pixels[i + 3] = UInt8(a * 255)
            }
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let provider = CGDataProvider(data: Data(pixels) as CFData),
            let tile = CGImage(
                width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: side * 4, space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return }
        // The context is flipped to top-left; draw the tile upright there.
        ctx.saveGState()
        ctx.translateBy(x: CGFloat(originX), y: CGFloat(originY + side))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(tile, in: CGRect(x: 0, y: 0, width: side, height: side))
        ctx.restoreGState()
    }

    private static func cgColor(_ c: RGBA) -> CGColor {
        CGColor(
            srgbRed: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: CGFloat(c.a))
    }
}
