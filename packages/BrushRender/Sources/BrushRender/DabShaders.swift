import Foundation

/// The dab shader source, compiled at runtime by `BrushCompositor`.
///
/// Embedded as a string rather than a `.metal` file on purpose: SwiftPM's
/// command-line build (and therefore `swift test`) does not compile `.metal`
/// into a metallib — only Xcode does — so a bundled metallib would leave the
/// package untestable from the terminal. Runtime `makeLibrary(source:)` works
/// everywhere and costs one compile at compositor start-up.
///
/// `GPUDab` here must match `DabInstance.swift` field-for-field.
enum DabShaders {
    static let source = """
        #include <metal_stdlib>
        using namespace metal;

        struct GPUDab {
            float2 position;
            float  radius;
            float  angle;
            float  roundness;
            float  hardness;
            float4 color;
            float  grainDepth;
            float  grainCell;
            uint   grainSeed;
            uint   square;
        };

        struct Uniforms { float2 viewportSize; };

        struct VertexOut {
            float4 position [[position]];
            float2 uv;
            float  hardness;
            float4 color;
            float  grainDepth;
            float  grainCell;
            uint   grainSeed;
            uint   square;
        };

        // Mirror of BrushKit's GrainNoise (same hash + smoothstep), sampled in
        // canvas space so the GPU tooth matches the CPU reference renderer.
        static inline float grain_hash(int x, int y, uint seed) {
            uint h = uint(x) * 0x8DA6B343u;
            h = h + uint(y) * 0xD8163841u + seed * 0x1B56C4E9u;
            h = (h ^ (h >> 15)) * 0x2C1B3C6Du;
            h = (h ^ (h >> 12)) * 0x297459E7u;
            h = h ^ (h >> 15);
            return float(h) / float(0xFFFFFFFFu);
        }
        static inline float grain_value(float px, float py, float cell, uint seed) {
            float s = max(cell, 0.5);
            float gx = px / s, gy = py / s;
            int x0 = int(floor(gx)), y0 = int(floor(gy));
            float fx = gx - float(x0), fy = gy - float(y0);
            fx = fx * fx * (3.0 - 2.0 * fx);
            fy = fy * fy * (3.0 - 2.0 * fy);
            float v00 = grain_hash(x0, y0, seed);
            float v10 = grain_hash(x0 + 1, y0, seed);
            float v01 = grain_hash(x0, y0 + 1, seed);
            float v11 = grain_hash(x0 + 1, y0 + 1, seed);
            float top = mix(v00, v10, fx);
            float bottom = mix(v01, v11, fx);
            return mix(top, bottom, fy);
        }

        constant float2 kQuad[4] = {
            float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1)
        };

        vertex VertexOut dab_vertex(
            uint vid [[vertex_id]],
            uint iid [[instance_id]],
            constant GPUDab *dabs [[buffer(0)]],
            constant Uniforms &u [[buffer(1)]])
        {
            GPUDab d = dabs[iid];
            float2 corner = kQuad[vid];

            float2 local = corner;
            local.y *= d.roundness;
            float c = cos(d.angle), s = sin(d.angle);
            float2 rotated = float2(local.x * c - local.y * s, local.x * s + local.y * c);
            float2 pixel = d.position + rotated * d.radius;

            float2 ndc = float2(
                (pixel.x / u.viewportSize.x) * 2.0 - 1.0,
                1.0 - (pixel.y / u.viewportSize.y) * 2.0);

            VertexOut out;
            out.position = float4(ndc, 0, 1);
            out.uv = corner;
            out.hardness = d.hardness;
            out.color = d.color;
            out.grainDepth = d.grainDepth;
            out.grainCell = d.grainCell;
            out.grainSeed = d.grainSeed;
            out.square = d.square;
            return out;
        }

        fragment float4 dab_fragment(VertexOut in [[stage_in]])
        {
            float r = in.square != 0u ? max(abs(in.uv.x), abs(in.uv.y)) : length(in.uv);
            if (r > 1.0) discard_fragment();
            float core = clamp(in.hardness, 0.0, 0.999);
            float coverage = 1.0 - smoothstep(core, 1.0, r);
            // Paper tooth in canvas space (in.position.xy is the pixel/canvas
            // coordinate, since the target is rendered at canvas resolution).
            if (in.grainDepth > 0.0) {
                float n = grain_value(in.position.x, in.position.y, in.grainCell, in.grainSeed);
                coverage *= (1.0 - in.grainDepth * (1.0 - n));
            }
            float alpha = in.color.a * coverage;
            return float4(in.color.rgb * alpha, alpha);
        }
        """
}
