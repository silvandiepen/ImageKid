import BrushKit
import CoreGraphics
import Foundation
import Metal
import simd

/// The shared Metal dab compositor. Stamps BrushKit `Dab`s into a target texture
/// with premultiplied "over" blending — the live path Inka's canvas drives and
/// the one ImageKid can adopt. UI-free: the app owns the `MTKView`/drawable and
/// hands this a target texture; this owns only the pipeline.
///
/// Target textures are treated as top-left origin (matching BrushKit's
/// `ReferenceRenderer`), so GPU and CPU output agree.
public final class BrushCompositor {
    public let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    public enum SetupError: Error {
        case noDevice
        case library(Error)
        case missingFunctions
        case pipeline(Error)
    }

    /// Build a compositor for `device` (or the system default). Throws when the
    /// shader library or pipeline cannot be created — callers on a machine
    /// without a usable GPU should catch and fall back to `ReferenceRenderer`.
    public init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws {
        guard let device, let queue = device.makeCommandQueue() else {
            throw SetupError.noDevice
        }
        self.device = device
        self.queue = queue

        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: DabShaders.source, options: nil)
        } catch {
            throw SetupError.library(error)
        }
        guard let vertex = library.makeFunction(name: "dab_vertex"),
            let fragment = library.makeFunction(name: "dab_fragment")
        else {
            throw SetupError.missingFunctions
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertex
        desc.fragmentFunction = fragment
        let color = desc.colorAttachments[0]!
        color.pixelFormat = .rgba8Unorm
        // Standard premultiplied "over": src + dst·(1−srcA).
        color.isBlendingEnabled = true
        color.rgbBlendOperation = .add
        color.alphaBlendOperation = .add
        color.sourceRGBBlendFactor = .one
        color.sourceAlphaBlendFactor = .one
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            throw SetupError.pipeline(error)
        }
    }

    /// Stamp `dabs` into `target`. `clear` wipes the target to transparent
    /// first; pass false to paint onto existing content (a live stroke buffer).
    public func stamp(
        _ dabs: [Dab], into target: MTLTexture, clear: Bool
    ) {
        guard !dabs.isEmpty || clear,
            let commandBuffer = queue.makeCommandBuffer()
        else { return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = clear ? .clear : .load
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            return
        }
        if !dabs.isEmpty {
            var instances = dabs.map(GPUDab.init)
            var uniforms = GPUUniforms(
                viewportSize: SIMD2(Float(target.width), Float(target.height)))
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBytes(
                &instances, length: MemoryLayout<GPUDab>.stride * instances.count, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<GPUUniforms>.stride, index: 1)
            encoder.drawPrimitives(
                type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                instanceCount: instances.count)
        }
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    /// Offscreen convenience: render `dabs` to a fresh RGBA8 CGImage. The GPU
    /// twin of `ReferenceRenderer.render(dabs:size:)` — used by golden-image
    /// tests and any headless export.
    public func renderImage(dabs: [Dab], size: CGSize) -> CGImage? {
        let w = Int(size.width.rounded())
        let h = Int(size.height.rounded())
        guard w > 0, h > 0 else { return nil }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        #if os(macOS)
        desc.storageMode = .managed
        #else
        desc.storageMode = .shared
        #endif
        guard let target = device.makeTexture(descriptor: desc) else { return nil }

        stamp(dabs, into: target, clear: true)
        return Self.cgImage(from: target)
    }

    /// Read a texture back into a premultiplied-last RGBA8 CGImage. The texture
    /// must be CPU-readable (`.shared`/`.managed`).
    public static func cgImage(from texture: MTLTexture) -> CGImage? {
        let w = texture.width
        let h = texture.height
        let bytesPerRow = w * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * h)
        texture.getBytes(
            &bytes, bytesPerRow: bytesPerRow,
            from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let provider = CGDataProvider(data: Data(bytes) as CFData)
        else { return nil }
        return CGImage(
            width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
