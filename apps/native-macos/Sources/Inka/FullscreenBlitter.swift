import Metal
import MetalKit

/// Draws textured and solid quads at arbitrary clip-space rects, with "over"
/// blending — how the canvas renderer presents the paper + committed + live
/// textures, positioned/scaled by the canvas transform (zoom/pan). Runtime-
/// compiled shader (same reasoning as BrushRender: `swift build` doesn't
/// compile `.metal`).
final class FullscreenBlitter {
    private let texturePipeline: MTLRenderPipelineState?
    private let solidPipeline: MTLRenderPipelineState?
    private let sampler: MTLSamplerState?

    /// A clip-space rect (x,y = bottom-left, in −1…1; w,h in clip units).
    struct Rect {
        var x: Float
        var y: Float
        var w: Float
        var h: Float
    }

    init(device: MTLDevice) {
        let source = """
            #include <metal_stdlib>
            using namespace metal;
            struct Rect { float x; float y; float w; float h; };
            struct VOut { float4 position [[position]]; float2 uv; };
            vertex VOut quad_vertex(uint vid [[vertex_id]], constant Rect &r [[buffer(0)]]) {
                float2 corner = float2((vid << 1) & 2, vid & 2) * 0.5;  // 0,0 1,0 0,1 1,1
                VOut o;
                o.position = float4(r.x + corner.x * r.w, r.y + corner.y * r.h, 0, 1);
                o.uv = float2(corner.x, 1.0 - corner.y);  // texture row 0 at top
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

    /// Fill a clip-space rect with a solid premultiplied colour (the paper).
    func fill(encoder: MTLRenderCommandEncoder, rect: Rect, color: SIMD4<Float>) {
        guard let solidPipeline else { return }
        var r = rect
        var c = color
        encoder.setRenderPipelineState(solidPipeline)
        encoder.setVertexBytes(&r, length: MemoryLayout<Rect>.stride, index: 0)
        encoder.setFragmentBytes(&c, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    /// Draw each texture (bottom → top) into the same clip-space rect.
    func draw(encoder: MTLRenderCommandEncoder, textures: [MTLTexture], rect: Rect) {
        guard let texturePipeline, let sampler else { return }
        var r = rect
        encoder.setRenderPipelineState(texturePipeline)
        encoder.setVertexBytes(&r, length: MemoryLayout<Rect>.stride, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        for texture in textures {
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
    }
}
