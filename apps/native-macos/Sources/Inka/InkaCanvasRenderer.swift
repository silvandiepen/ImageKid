import BrushKit
import BrushRender
import CoreGraphics
import InkaKit
import Metal
import MetalKit
import simd

/// The live Metal canvas renderer — the walking-skeleton heart. Keeps two
/// textures: a **committed** texture (everything already drawn) and a **live**
/// texture (the stroke in progress, re-stamped whole each frame so overlapping
/// dabs never build up within one stroke). Each MTKView frame blits committed +
/// live to the drawable.
///
/// On stroke end the live texture is stamped into committed and the stroke is
/// handed back as a `BrushStroke` for the document — the non-destructive record.
/// Uses the shared `BrushCompositor` for all stamping, so it is the exact GPU
/// path the family shares.
final class InkaCanvasRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let compositor: BrushCompositor
    private let queue: MTLCommandQueue

    /// Canvas pixel size (fixed for the document).
    let canvasSize: CGSize
    private var committed: MTLTexture
    private var live: MTLTexture

    /// Current brush/colour, set by the model.
    var brush: Brush = BrushLibrary.inkPen
    var color: RGBA = RGBA(r: 0.1, g: 0.12, b: 0.16)

    /// The in-progress stroke's samples (canvas pixel space).
    private var currentSamples: [StrokeSample] = []
    /// Called when a stroke commits, with the finished record.
    var onCommitStroke: ((BrushStroke) -> Void)?

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
            pixelFormat: .rgba8Unorm, width: Int(size.width), height: Int(size.height),
            mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        // Shared so the committed texture can be read back for export
        // (getBytes needs a CPU-visible texture). Fine on Apple Silicon.
        desc.storageMode = .shared
        return device.makeTexture(descriptor: desc)
    }

    /// Wipe the canvas to transparent.
    func clear() {
        compositor.stamp([], into: committed, clear: true)
        compositor.stamp([], into: live, clear: true)
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
    /// record for the document.
    func endStroke() {
        guard !currentSamples.isEmpty else { return }
        let input = StrokeInput(samples: currentSamples)
        let dabs = BrushEngine.dabs(for: input, brush: brush, color: color)
        compositor.stamp(dabs, into: committed, clear: false)
        compositor.stamp([], into: live, clear: true)
        onCommitStroke?(BrushStroke(brushID: brush.id, color: color, input: input))
        currentSamples = []
    }

    /// Re-stamp the whole in-progress stroke into the live texture from scratch,
    /// so within-stroke overlap never darkens (Procreate/Photoshop behaviour).
    private func restampLive() {
        let input = StrokeInput(samples: currentSamples)
        let dabs = BrushEngine.dabs(for: input, brush: brush, color: color)
        compositor.stamp(dabs, into: live, clear: true)
    }

    /// The committed canvas as a CGImage (for export / hand-off to the model).
    func committedImage() -> CGImage? {
        BrushCompositor.cgImage(from: committed)
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
            let pass = view.currentRenderPassDescriptor,
            let cmd = queue.makeCommandBuffer()
        else { return }
        // The canvas checker/background is the view's clear colour; blit the two
        // canvas textures over it, scaled to the drawable by the blit fit.
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)
        guard let encoder = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        // For the P1 skeleton the canvas fills the drawable 1:1 (view sized to
        // the canvas); a fitted blit + zoom/pan arrives in P4. We present the
        // textures with a fullscreen textured quad.
        blitter.encode(
            encoder: encoder, textures: [committed, live],
            drawableSize: view.drawableSize)
        encoder.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    private lazy var blitter = FullscreenBlitter(device: device)
}
