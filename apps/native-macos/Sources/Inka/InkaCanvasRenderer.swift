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

    /// View transform (points): fit is zoom 1; `zoom`/`offset` pan and scale.
    var zoom: CGFloat = 1
    var offset: CGSize = .zero
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
        var all: [Dab] = []
        for layer in document.layers where layer.isVisible {
            guard case .strokes(let strokes) = layer.content else { continue }
            let op = max(0, min(1, layer.opacity))
            for stroke in strokes {
                guard let b = brushProvider(stroke.brushID) else { continue }
                var dabs = stroke.dabs(using: b)
                if op < 1 { for i in dabs.indices { dabs[i].alpha *= op } }
                all.append(contentsOf: dabs)
            }
        }
        compositor.stamp([], into: committed, clear: true)
        if !all.isEmpty { compositor.stamp(all, into: committed, clear: false) }
    }

    // MARK: - Live stroke input (canvas pixel coordinates)

    func beginStroke(at sample: StrokeSample) {
        currentSamples = [sample]
        restampLive()
    }

    func extendStroke(to sample: StrokeSample) {
        currentSamples.append(sample)
        restampLive()
    }

    /// Finish: stamp the live stroke into committed, clear live, and emit the
    /// record. The model records it and calls `rebuild(from:)`.
    func endStroke() {
        guard !currentSamples.isEmpty else { return }
        let input = StrokeInput(samples: currentSamples)
        let dabs = BrushEngine.dabs(for: input, brush: brush, color: color)
        compositor.stamp(dabs, into: committed, clear: false)
        compositor.stamp([], into: live, clear: true)
        onCommitStroke?(BrushStroke(brushID: brush.id, color: color, input: input))
        currentSamples = []
    }

    private func restampLive() {
        let input = StrokeInput(samples: currentSamples)
        let dabs = BrushEngine.dabs(for: input, brush: brush, color: color)
        compositor.stamp(dabs, into: live, clear: true)
    }

    /// The committed canvas as a CGImage (for export / hand-off to the model).
    func committedImage() -> CGImage? { BrushCompositor.cgImage(from: committed) }

    // MARK: - Canvas transform (points)

    /// Points-per-canvas-pixel at the current zoom (fit × zoom).
    func scale(in view: CGSize) -> CGFloat {
        guard canvasSize.width > 0, canvasSize.height > 0, view.width > 0, view.height > 0 else {
            return zoom
        }
        let fit = min(view.width / canvasSize.width, view.height / canvasSize.height)
        return fit * zoom
    }

    /// The canvas's on-screen rect in view points.
    func canvasRect(in view: CGSize) -> CGRect {
        let s = scale(in: view)
        let w = canvasSize.width * s
        let h = canvasSize.height * s
        let x = (view.width - w) / 2 + offset.width
        let y = (view.height - h) / 2 + offset.height
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// View point (top-left origin) → canvas pixel (top-left origin).
    func canvasPoint(from viewPoint: CGPoint, in view: CGSize) -> CGPoint {
        let rect = canvasRect(in: view)
        let s = scale(in: view)
        guard s > 0 else { return .zero }
        return CGPoint(x: (viewPoint.x - rect.minX) / s, y: (viewPoint.y - rect.minY) / s)
    }

    /// Fit the canvas to the view (reset zoom/pan).
    func fit() {
        zoom = 1
        offset = .zero
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
        let rect = canvasRect(in: vp)
        let ndc = clipRect(rect, in: vp)
        // Paper (white), then the document, then the live stroke.
        blitter.fill(encoder: encoder, rect: ndc, color: SIMD4(1, 1, 1, 1))
        blitter.draw(encoder: encoder, textures: [committed, live], rect: ndc)
        encoder.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    /// A view-point rect (top-left origin) → clip-space `Rect` (bottom-left, −1…1).
    private func clipRect(_ r: CGRect, in view: CGSize) -> FullscreenBlitter.Rect {
        guard view.width > 0, view.height > 0 else { return .init(x: -1, y: -1, w: 2, h: 2) }
        let x = Float(r.minX / view.width * 2 - 1)
        // Flip Y: view top-left → clip bottom-left.
        let yTop = Float(1 - r.minY / view.height * 2)
        let h = Float(r.height / view.height * 2)
        return FullscreenBlitter.Rect(
            x: x, y: yTop - h, w: Float(r.width / view.width * 2), h: h)
    }

    private lazy var blitter = FullscreenBlitter(device: device)
}
