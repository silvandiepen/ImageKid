import BrushKit
import BrushRender
import CoreGraphics
import InkaKit
import Metal
import MetalKit
import simd

/// The live Metal canvas renderer. Keeps a **committed** texture (the document,
/// rebuilt from its layers) and a **live** texture (the stroke in progress,
/// re-stamped whole each frame so within-stroke overlap never builds up). Each
/// frame draws the paper, then committed, then live — positioned by the canvas
/// transform (fit + zoom + pan).
///
/// On stroke end the finished `BrushStroke` is handed to the document; the model
/// then calls `rebuild(from:)` so committed always reflects the document (which
/// is what makes undo, layer visibility and opacity work). All stamping goes
/// through the shared `BrushCompositor`.
final class InkaCanvasRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let compositor: BrushCompositor
    private let queue: MTLCommandQueue

    private(set) var canvasSize: CGSize
    private var committed: MTLTexture
    private var live: MTLTexture

    /// Current brush/colour, set by the model.
    var brush: Brush = BrushLibrary.inkPen
    var color: RGBA = RGBA(r: 0.1, g: 0.12, b: 0.16)

    /// View transform (points): fit is zoom 1; `zoom` scales, `offset` pans,
    /// `rotation` (radians) spins the canvas about its centre.
    var zoom: CGFloat = 1
    var offset: CGSize = .zero
    var rotation: CGFloat = 0
    /// The MTKView's point size, set by the view each layout — drives the fit.
    var viewSize: CGSize = .zero

    private var currentSamples: [StrokeSample] = []
    var onCommitStroke: ((BrushStroke) -> Void)?
    /// Resolves a stroke's brush id against the document (set by the model).
    var brushProvider: (String) -> Brush? = { _ in nil }

    init?(canvasSize: CGSize) {
        guard let compositor = try? BrushCompositor(),
            let queue = compositor.device.makeCommandQueue()
        else { return nil }
        self.device = compositor.device
        self.compositor = compositor
        self.queue = queue
        self.canvasSize = canvasSize
        guard let committed = Self.makeTexture(device: compositor.device, size: canvasSize),
            let live = Self.makeTexture(device: compositor.device, size: canvasSize)
        else { return nil }
        self.committed = committed
        self.live = live
        super.init()
        clear()
    }

    private static func makeTexture(device: MTLDevice, size: CGSize) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: max(1, Int(size.width)),
            height: max(1, Int(size.height)), mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared  // read back for export
        return device.makeTexture(descriptor: desc)
    }

    /// Resize the canvas (opening a document of a different size).
    func resize(to size: CGSize) {
        guard size != canvasSize,
            let c = Self.makeTexture(device: device, size: size),
            let l = Self.makeTexture(device: device, size: size)
        else { return }
        canvasSize = size
        committed = c
        live = l
        clear()
    }

    /// Wipe both textures to transparent.
    func clear() {
        compositor.stamp([], into: committed, clear: true)
        compositor.stamp([], into: live, clear: true)
    }

    /// Rebuild the committed texture from a document: stamp every visible stroke
    /// layer bottom→top, scaling each dab's alpha by the layer's opacity. (The
    /// GPU view approximates per-layer opacity; export flattens through
    /// `InkaRasterizer` for exact blend/opacity. Raster/imported layers are not
    /// yet shown on the live canvas — the app creates only stroke layers.)
    func rebuild(from document: InkaDocument) {
        compositor.stamp([], into: committed, clear: true)
        for layer in document.layers where layer.isVisible {
            guard case .strokes(let strokes) = layer.content else { continue }
            let op = max(0, min(1, layer.opacity))
            // Paint strokes batch together; an eraser (destination-out) flushes
            // the batch, then erases. (Live preview flattens layers, so an erase
            // crosses layers here; export via InkaRasterizer erases per layer.)
            var batch: [Dab] = []
            func flush() {
                if !batch.isEmpty { compositor.stamp(batch, into: committed, clear: false); batch = [] }
            }
            for stroke in strokes {
                guard let b = brushProvider(stroke.brushID) else { continue }
                var dabs = stroke.dabs(using: b)
                if op < 1 { for i in dabs.indices { dabs[i].alpha *= op } }
                if stroke.erase {
                    flush()
                    compositor.stamp(dabs, into: committed, clear: false, erase: true)
                } else {
                    batch.append(contentsOf: dabs)
                }
            }
            flush()
        }
    }

    // MARK: - Live stroke input (canvas pixel coordinates)

    /// When true the in-progress stroke erases (destination-out) rather than
    /// paints. Set by the model from the active tool.
    var eraseMode = false

    func beginStroke(at sample: StrokeSample) {
        currentSamples = [sample]
        if eraseMode {
            snapshotCommitted()  // so the whole erase re-applies cleanly each step
            restampErase()
        } else {
            restampLive()
        }
    }

    func extendStroke(to sample: StrokeSample) {
        currentSamples.append(sample)
        if eraseMode { restampErase() } else { restampLive() }
    }

    /// Finish: bake the stroke into committed and emit the record. The model
    /// records it and calls `rebuild(from:)`.
    func endStroke() {
        guard !currentSamples.isEmpty else { return }
        let input = StrokeInput(samples: currentSamples)
        if eraseMode {
            // committed already carries the erase from the last restamp.
            onCommitStroke?(BrushStroke(brushID: brush.id, color: color, input: input, erase: true))
        } else {
            let dabs = BrushEngine.dabs(for: input, brush: brush, color: color)
            compositor.stamp(dabs, into: committed, clear: false)
            compositor.stamp([], into: live, clear: true)
            onCommitStroke?(BrushStroke(brushID: brush.id, color: color, input: input))
        }
        currentSamples = []
    }

    private func restampLive() {
        let input = StrokeInput(samples: currentSamples)
        let dabs = BrushEngine.dabs(for: input, brush: brush, color: color)
        compositor.stamp(dabs, into: live, clear: true)
    }

    /// Re-apply the whole eraser stroke: restore committed to its pre-stroke
    /// snapshot, then erase the current spine (so within-stroke overlap doesn't
    /// keep eating alpha for a soft eraser).
    private func restampErase() {
        guard let backup = strokeBackup else { return }
        copyTexture(from: backup, to: committed)
        let input = StrokeInput(samples: currentSamples)
        let dabs = BrushEngine.dabs(for: input, brush: brush, color: color)
        compositor.stamp(dabs, into: committed, clear: false, erase: true)
    }

    private func snapshotCommitted() {
        if strokeBackup == nil || strokeBackup?.width != committed.width
            || strokeBackup?.height != committed.height
        {
            strokeBackup = Self.makeTexture(
                device: device, size: CGSize(width: committed.width, height: committed.height))
        }
        if let backup = strokeBackup { copyTexture(from: committed, to: backup) }
    }

    /// GPU copy between two same-size textures.
    private func copyTexture(from src: MTLTexture, to dst: MTLTexture) {
        guard let cmd = queue.makeCommandBuffer(), let blit = cmd.makeBlitCommandEncoder() else { return }
        blit.copy(
            from: src, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: min(src.width, dst.width), height: min(src.height, dst.height), depth: 1),
            to: dst, destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
    }

    private var strokeBackup: MTLTexture?

    /// The committed canvas as a CGImage (for export / hand-off to the model).
    func committedImage() -> CGImage? { BrushCompositor.cgImage(from: committed) }

    /// Read one committed pixel (canvas space, top-left origin) as `RGBA`. The
    /// committed texture is `.shared`, so this is a direct CPU read. Returns nil
    /// if the point is outside the canvas.
    func sampleColor(at p: CGPoint) -> RGBA? {
        let x = Int(p.x.rounded(.down))
        let y = Int(p.y.rounded(.down))
        guard x >= 0, y >= 0, x < committed.width, y < committed.height else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        committed.getBytes(
            &px, bytesPerRow: 4,
            from: MTLRegionMake2D(x, y, 1, 1), mipmapLevel: 0)
        // rgba8Unorm, premultiplied — un-premultiply so the eyedropper reports
        // the drawn colour, not the paper-blended one.
        let a = Double(px[3]) / 255
        guard a > 0 else { return RGBA(r: 0, g: 0, b: 0, a: 0) }
        return RGBA(
            r: min(1, Double(px[0]) / 255 / a),
            g: min(1, Double(px[1]) / 255 / a),
            b: min(1, Double(px[2]) / 255 / a),
            a: a)
    }

    // MARK: - Canvas transform (points) — pan + zoom + rotate about the centre

    /// Points-per-canvas-pixel at the current zoom (fit × zoom).
    func scale(in view: CGSize) -> CGFloat {
        guard canvasSize.width > 0, canvasSize.height > 0, view.width > 0, view.height > 0 else {
            return zoom
        }
        let fit = min(view.width / canvasSize.width, view.height / canvasSize.height)
        return fit * zoom
    }

    /// The canvas centre on screen (view points): view centre + pan.
    private func screenCenter(in view: CGSize) -> CGPoint {
        CGPoint(x: view.width / 2 + offset.width, y: view.height / 2 + offset.height)
    }

    /// Canvas point (top-left origin) → view point (top-left origin).
    func viewPoint(fromCanvas p: CGPoint, in view: CGSize) -> CGPoint {
        let s = scale(in: view)
        let c = screenCenter(in: view)
        // Centre-relative, scaled, rotated, then placed at the screen centre.
        let lx = (p.x - canvasSize.width / 2) * s
        let ly = (p.y - canvasSize.height / 2) * s
        let cosT = cos(rotation), sinT = sin(rotation)
        return CGPoint(x: c.x + lx * cosT - ly * sinT, y: c.y + lx * sinT + ly * cosT)
    }

    /// View point (top-left origin) → canvas pixel (top-left origin).
    func canvasPoint(from viewPoint: CGPoint, in view: CGSize) -> CGPoint {
        let s = scale(in: view)
        guard s > 0 else { return .zero }
        let c = screenCenter(in: view)
        let dx = viewPoint.x - c.x, dy = viewPoint.y - c.y
        // Un-rotate, then un-scale, then un-centre.
        let cosT = cos(rotation), sinT = sin(rotation)
        let lx = dx * cosT + dy * sinT
        let ly = -dx * sinT + dy * cosT
        return CGPoint(x: lx / s + canvasSize.width / 2, y: ly / s + canvasSize.height / 2)
    }

    /// The four canvas corners as view points (top-left origin), for overlays.
    func viewCorners(ofCanvasRect r: CGRect, in view: CGSize) -> [CGPoint] {
        [
            viewPoint(fromCanvas: CGPoint(x: r.minX, y: r.minY), in: view),
            viewPoint(fromCanvas: CGPoint(x: r.maxX, y: r.minY), in: view),
            viewPoint(fromCanvas: CGPoint(x: r.maxX, y: r.maxY), in: view),
            viewPoint(fromCanvas: CGPoint(x: r.minX, y: r.maxY), in: view),
        ]
    }

    /// Fit the canvas to the view (reset zoom / pan / rotation).
    func fit() {
        zoom = 1
        offset = .zero
        rotation = 0
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
            let pass = view.currentRenderPassDescriptor,
            let cmd = queue.makeCommandBuffer()
        else { return }
        pass.colorAttachments[0].loadAction = .clear
        // A neutral workspace grey behind the paper.
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.28, green: 0.29, blue: 0.31, alpha: 1)
        guard let encoder = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }

        let vp = viewSize == .zero ? view.bounds.size : viewSize
        let quad = canvasQuad(in: vp)
        // Paper (white), then the document, then the live stroke.
        blitter.fill(encoder: encoder, quad: quad, color: SIMD4(1, 1, 1, 1))
        blitter.draw(encoder: encoder, textures: [committed, live], quad: quad)
        encoder.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    /// The canvas's four corners in clip space (−1…1), rotated with the canvas.
    private func canvasQuad(in view: CGSize) -> FullscreenBlitter.Quad {
        func clip(_ p: CGPoint) -> SIMD2<Float> {
            guard view.width > 0, view.height > 0 else { return SIMD2(0, 0) }
            return SIMD2(
                Float(p.x / view.width * 2 - 1),
                Float(1 - p.y / view.height * 2))  // view top-left → clip bottom-left
        }
        let tl = viewPoint(fromCanvas: CGPoint(x: 0, y: 0), in: view)
        let tr = viewPoint(fromCanvas: CGPoint(x: canvasSize.width, y: 0), in: view)
        let bl = viewPoint(fromCanvas: CGPoint(x: 0, y: canvasSize.height), in: view)
        let br = viewPoint(fromCanvas: CGPoint(x: canvasSize.width, y: canvasSize.height), in: view)
        return FullscreenBlitter.Quad(tl: clip(tl), tr: clip(tr), bl: clip(bl), br: clip(br))
    }

    private lazy var blitter = FullscreenBlitter(device: device)
}
