import BrushKit
import CoreGraphics
import simd

/// The per-instance stamp the shader reads. Layout must match `GPUDab` in
/// `Dab.metal` exactly (float2, float, float, float, float, float4).
struct GPUDab {
    var position: SIMD2<Float>
    var radius: Float
    var angle: Float
    var roundness: Float
    var hardness: Float
    var color: SIMD4<Float>
    var grainDepth: Float
    var grainCell: Float
    var grainSeed: UInt32
    var square: UInt32

    init(_ dab: Dab) {
        position = SIMD2(Float(dab.position.x), Float(dab.position.y))
        radius = Float(dab.diameter / 2)
        angle = Float(dab.angle)
        roundness = Float(dab.roundness)
        hardness = Float(dab.hardness)
        color = SIMD4(
            Float(dab.color.r), Float(dab.color.g), Float(dab.color.b), Float(dab.alpha))
        grainDepth = Float(dab.grainDepth)
        grainCell = Float(dab.grainCell)
        grainSeed = dab.grainSeed
        square = dab.square ? 1 : 0
    }
}

struct GPUUniforms {
    var viewportSize: SIMD2<Float>
}
