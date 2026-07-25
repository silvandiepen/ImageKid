import Metal
import MetalKit

/// Draws textured and solid quads from four explicit clip-space corners, with
/// "over" blending — how the canvas renderer presents the paper + committed +
/// live textures, positioned by the canvas transform (pan / zoom / **rotate**).
/// Runtime-compiled shader (same reasoning as BrushRender: `swift build` doesn't
/// compile `.metal`).
final class FullscreenBlitter {
    private let texturePipeline: MTLRenderPipelineState?
    private let solidPipeline: MTLRenderPipelineState?
    private let sampler: MTLSamplerState?

    /// Four clip-space corners (−1…1) in triangle-strip order: top-left,
    /// top-right, bottom-left, bottom-right — matching the texture's rows so
    /// (0,0) samples the top-left texel. A rotated canvas is just rotated
    /// corners.
    struct Quad {
        var tl: SIMD2<Float>
        var tr: SIMD2<Float>
        var bl: SIMD2<Float>
        var br: SIMD2<Float>
    }

    init(device: MTLDevice) {
        let source = """
            #include <metal_stdlib>
            using namespace metal;
            struct Quad { float2 tl; float2 tr; float2 bl; float2 br; };
            struct VOut { float4 position [[position]]; float2 uv; };
            vertex VOut quad_vertex(uint vid [[vertex_id]], constant Quad &q [[buffer(0)]]) {
                float2 pos[4] = { q.tl, q.tr, q.bl, q.br };
                float2 uvs[4] = { float2(0,0), float2(1,0), float2(0,1), float2(1,1) };
                VOut o;
                o.position = float4(pos[vid], 0, 1);
                o.uv = uvs[vid];   // texture row 0 at top-left
                return o;
            }
            fragment float4 tex_fragment(
                VOut in [[stage_in]], texture2d<float> tex [[texture(0)]],
                sampler s [[sampler(0)]]) {
                return tex.sample(s, in.uv);   // premultiplied
            }
            fragment float4 solid_fragment(VOut in [[stage_in]], constant float4 &c [[buffer(0)]]) {
                return c;   // premultiplied
            }
            """
        guard let library = try? device.makeLibrary(source: source, options: nil),
            let vertex = library.makeFunction(name: "quad_vertex"),
            let texFrag = library.makeFunction(name: "tex_fragment"),
            let solidFrag = library.makeFunction(name: "solid_fragment")
        else {
            texturePipeline = nil
            solidPipeline = nil
            sampler = nil
            return
        }
        func pipeline(_ fragment: MTLFunction) -> MTLRenderPipelineState? {
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
            return try? device.makeRenderPipelineState(descriptor: desc)
        }
        texturePipeline = pipeline(texFrag)
        solidPipeline = pipeline(solidFrag)
        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear
        sd.magFilter = .linear
        sampler = device.makeSamplerState(descriptor: sd)
    }

    /// Fill a clip-space quad with a solid premultiplied colour (the paper).
    func fill(encoder: MTLRenderCommandEncoder, quad: Quad, color: SIMD4<Float>) {
        guard let solidPipeline else { return }
        var q = quad
        var c = color
        encoder.setRenderPipelineState(solidPipeline)
        encoder.setVertexBytes(&q, length: MemoryLayout<Quad>.stride, index: 0)
        encoder.setFragmentBytes(&c, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    /// Draw each texture (bottom → top) into the same clip-space quad.
    func draw(encoder: MTLRenderCommandEncoder, textures: [MTLTexture], quad: Quad) {
        guard let texturePipeline, let sampler else { return }
        var q = quad
        encoder.setRenderPipelineState(texturePipeline)
        encoder.setVertexBytes(&q, length: MemoryLayout<Quad>.stride, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        for texture in textures {
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
    }
}
