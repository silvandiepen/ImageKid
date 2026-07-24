import Metal
import MetalKit

/// Draws one or more premultiplied textures over the current render pass as
/// fullscreen quads with "over" blending — how the canvas renderer presents its
/// committed + live textures to the drawable. Runtime-compiled shader (same
/// reasoning as BrushRender: `swift build` doesn't compile `.metal`).
final class FullscreenBlitter {
    private let pipeline: MTLRenderPipelineState?
    private let sampler: MTLSamplerState?

    init(device: MTLDevice) {
        let source = """
            #include <metal_stdlib>
            using namespace metal;
            struct VOut { float4 position [[position]]; float2 uv; };
            vertex VOut fs_vertex(uint vid [[vertex_id]]) {
                float2 corner = float2((vid << 1) & 2, vid & 2);   // 0,0 2,0 0,2
                VOut o;
                o.position = float4(corner * float2(2, -2) + float2(-1, 1), 0, 1);
                o.uv = corner;   // 0,0 top-left … 1,1 bottom-right
                return o;
            }
            fragment float4 fs_fragment(
                VOut in [[stage_in]], texture2d<float> tex [[texture(0)]],
                sampler s [[sampler(0)]]) {
                return tex.sample(s, in.uv);   // premultiplied
            }
            """
        guard let library = try? device.makeLibrary(source: source, options: nil),
            let vertex = library.makeFunction(name: "fs_vertex"),
            let fragment = library.makeFunction(name: "fs_fragment")
        else {
            pipeline = nil
            sampler = nil
            return
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertex
        desc.fragmentFunction = fragment
        let color = desc.colorAttachments[0]!
        color.pixelFormat = .bgra8Unorm
        color.isBlendingEnabled = true
        color.rgbBlendOperation = .add
        color.alphaBlendOperation = .add
        color.sourceRGBBlendFactor = .one
        color.sourceAlphaBlendFactor = .one
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipeline = try? device.makeRenderPipelineState(descriptor: desc)

        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear
        sd.magFilter = .linear
        sampler = device.makeSamplerState(descriptor: sd)
    }

    /// Draw each texture in order (bottom → top) into the encoder.
    func encode(encoder: MTLRenderCommandEncoder, textures: [MTLTexture], drawableSize: CGSize) {
        guard let pipeline, let sampler else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentSamplerState(sampler, index: 0)
        for texture in textures {
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
    }
}
