import AppKit
import CoreGraphics
import FekthorKit
import SwiftUI

/// Renders a `GraphicDocument` into a small CGImage for gallery thumbnails.
/// Pure CoreGraphics on the same `CGPathBuilder` geometry the editor canvas
/// draws, so thumbnails match what opens in the editor. Safe to call off the
/// main actor (`GraphicDocument` is Sendable, no AppKit involved).
enum ThumbnailRenderer {
    static func render(_ doc: GraphicDocument, pixelSize: Int) -> CGImage? {
        let vb = doc.viewBox
        guard vb.width > 0, vb.height > 0, pixelSize > 0 else { return nil }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let ctx = CGContext(
                data: nil, width: pixelSize, height: pixelSize,
                bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Fit the viewBox with a small margin; transparent background — the
        // gallery cell provides the white artboard behind it.
        let size = CGFloat(pixelSize)
        let s = size * 0.88 / CGFloat(max(vb.width, vb.height))
        let tx = (size - s * CGFloat(vb.width)) / 2 - s * CGFloat(vb.minX)
        let ty = (size - s * CGFloat(vb.height)) / 2 - s * CGFloat(vb.minY)
        // Flip to a top-left origin so document coordinates map directly.
        ctx.translateBy(x: 0, y: size)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: tx, y: ty)
        ctx.scaleBy(x: s, y: s)
        draw(doc.nodes, in: ctx, opacity: 1)
        return ctx.makeImage()
    }

    /// Mirrors `EditorCanvasView.drawNodes` semantics: groups compose
    /// transform and opacity; shapes honour effective fill/stroke styles,
    /// fill-rule, fill-opacity, caps and joins.
    private static func draw(_ nodes: [GraphicNode], in ctx: CGContext, opacity: Double) {
        for node in nodes {
            switch node {
            case .raw:
                continue  // defs/style blocks have no direct rendering
            case .group(let g):
                let groupStyle = g.renderStyle
                if groupStyle.isDisplayNone { continue }  // hidden layer
                ctx.saveGState()
                if let t = g.transform { ctx.concatenate(affine(t)) }
                draw(g.children, in: ctx, opacity: opacity * (groupStyle.opacity ?? 1))
                ctx.restoreGState()
            case .shape(let s):
                let style = s.renderStyle
                if style.isDisplayNone { continue }  // hidden layer
                ctx.saveGState()
                if let t = s.transform { ctx.concatenate(affine(t)) }
                let nodeOpacity = opacity * (style.opacity ?? 1)
                let path = CGPathBuilder.path(for: s.kind)
                if let fill = style.fill ?? defaultFill(for: s), let c = fill.renderColor {
                    var fillOpacity = 1.0
                    if case .number(let fo, _)? = style.value(of: "fill-opacity") {
                        fillOpacity = fo
                    }
                    ctx.addPath(path)
                    ctx.setFillColor(cgColor(c, alpha: nodeOpacity * fillOpacity))
                    if case .keyword("evenodd")? = style.value(of: "fill-rule") {
                        ctx.fillPath(using: .evenOdd)
                    } else {
                        ctx.fillPath(using: .winding)
                    }
                }
                if let stroke = style.stroke, let c = stroke.renderColor {
                    // A zero-length round-capped line is a DOT in SVG;
                    // CoreGraphics strokes nothing for it. Draw the cap.
                    if case .line(let a, let b) = s.kind, a.x == b.x, a.y == b.y,
                        case .keyword("round")? = style.value(of: "stroke-linecap")
                    {
                        let r = (style.strokeWidth ?? 1) / 2
                        ctx.setFillColor(cgColor(c, alpha: nodeOpacity))
                        ctx.fillEllipse(
                            in: CGRect(x: a.x - r, y: a.y - r, width: 2 * r, height: 2 * r))
                        ctx.restoreGState()
                        continue
                    }
                    ctx.addPath(path)
                    ctx.setStrokeColor(cgColor(c, alpha: nodeOpacity))
                    ctx.setLineWidth(CGFloat(style.strokeWidth ?? 1))
                    if case .keyword(let cap)? = style.value(of: "stroke-linecap") {
                        ctx.setLineCap(cap == "round" ? .round : cap == "square" ? .square : .butt)
                    }
                    if case .keyword(let join)? = style.value(of: "stroke-linejoin") {
                        ctx.setLineJoin(join == "round" ? .round : .miter)
                    } else {
                        ctx.setLineJoin(.miter)
                    }
                    ctx.strokePath()
                }
                ctx.restoreGState()
            }
        }
    }

    /// SVG default: shapes with no fill declaration fill black (lines and
    /// polylines cannot fill) — matches the editor canvas.
    private static func defaultFill(for s: ShapeNode) -> PaintValue? {
        if case .line = s.kind { return nil }
        if case .polyline = s.kind { return nil }
        return .color(r: 0, g: 0, b: 0)
    }

    private static func affine(_ t: TransformValue) -> CGAffineTransform {
        let m = t.matrix
        return CGAffineTransform(a: m[0], b: m[1], c: m[2], d: m[3], tx: m[4], ty: m[5])
    }

    private static func cgColor(_ c: (r: UInt8, g: UInt8, b: UInt8), alpha: Double) -> CGColor {
        CGColor(
            srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255,
            blue: CGFloat(c.b) / 255, alpha: CGFloat(alpha))
    }
}

/// In-memory thumbnail cache keyed by entry id + modification state, so a
/// rescan-with-changes naturally re-renders only the icons whose files
/// changed. Rendering (file read → SVG parse → CG draw) happens off the
/// main actor; `version` bumps when a new image lands so visible cells
/// refresh.
@MainActor
final class ThumbnailStore: ObservableObject {
    @Published private(set) var version = 0

    private let cache = NSCache<NSString, NSImage>()
    private var inFlight: Set<String> = []
    private var failed: Set<String> = []

    init() {
        cache.countLimit = 2048
    }

    func key(for entry: IconEntry) -> String {
        "\(entry.id)|\(entry.modificationDate.timeIntervalSinceReferenceDate)|\(entry.fileSize)"
    }

    func image(for entry: IconEntry) -> NSImage? {
        cache.object(forKey: key(for: entry) as NSString)
    }

    func didFail(_ entry: IconEntry) -> Bool {
        failed.contains(key(for: entry))
    }

    /// Kick off an async render unless it is cached, in flight, or known bad.
    func request(_ entry: IconEntry, pixelSize: Int = 192) {
        let k = key(for: entry)
        guard cache.object(forKey: k as NSString) == nil,
            !inFlight.contains(k), !failed.contains(k)
        else { return }
        inFlight.insert(k)
        let url = entry.url
        Task.detached(priority: .utility) {
            var image: NSImage?
            if let data = try? Data(contentsOf: url),
                let doc = try? SVGReader.read(data),
                let cg = ThumbnailRenderer.render(doc, pixelSize: pixelSize)
            {
                let points = CGFloat(pixelSize) / 2  // 2× for Retina
                image = NSImage(cgImage: cg, size: NSSize(width: points, height: points))
            }
            let rendered = image
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.inFlight.remove(k)
                if let rendered {
                    self.cache.setObject(rendered, forKey: k as NSString)
                } else {
                    self.failed.insert(k)
                }
                self.version += 1
            }
        }
    }
}

/// Thumbnails for the gallery's virtual composed cells (View ▸ Preview
/// Composed Icons): icon composed into a container merged with its linked
/// partials, rendered through the same `ThumbnailRenderer` so previews match
/// what a composed export would produce. Keys are built by the caller over
/// every input (member file states + slot + link set), so role/link/slot
/// edits and file changes re-render live; stale keys just age out of the
/// cache. Nothing is ever written to disk.
@MainActor
final class ComposedThumbnailStore: ObservableObject {
    @Published private(set) var version = 0

    private let cache = NSCache<NSString, NSImage>()
    private var inFlight: Set<String> = []
    private var failed: Set<String> = []

    init() {
        cache.countLimit = 1024
    }

    func image(forKey key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    func didFail(_ key: String) -> Bool {
        failed.contains(key)
    }

    func request(
        key: String, iconURL: URL, containerURL: URL, partialURLs: [URL],
        slot: Workfile.ContainerSlot, pixelSize: Int = 192
    ) {
        guard cache.object(forKey: key as NSString) == nil,
            !inFlight.contains(key), !failed.contains(key)
        else { return }
        inFlight.insert(key)
        Task.detached(priority: .utility) {
            var image: NSImage?
            if let iconData = try? Data(contentsOf: iconURL),
                let iconDoc = try? SVGReader.read(iconData),
                let containerData = try? Data(contentsOf: containerURL),
                let containerDoc = try? SVGReader.read(containerData)
            {
                let partials = partialURLs.compactMap { url -> GraphicDocument? in
                    guard let data = try? Data(contentsOf: url) else { return nil }
                    return try? SVGReader.read(data)
                }
                let composed = Containers.compose(
                    content: iconDoc,
                    into: Containers.merged(containerDoc, partials: partials),
                    slot: slot)
                if let cg = ThumbnailRenderer.render(composed, pixelSize: pixelSize) {
                    let points = CGFloat(pixelSize) / 2  // 2× for Retina
                    image = NSImage(cgImage: cg, size: NSSize(width: points, height: points))
                }
            }
            let rendered = image
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.inFlight.remove(key)
                if let rendered {
                    self.cache.setObject(rendered, forKey: key as NSString)
                } else {
                    self.failed.insert(key)
                }
                self.version += 1
            }
        }
    }
}
