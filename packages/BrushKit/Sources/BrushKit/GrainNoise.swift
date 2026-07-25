import CoreGraphics
import Foundation

/// Procedural grain — the texture that makes a pencil read as pencil and chalk
/// as chalk, without shipping bitmap assets. A bilinearly-interpolated value
/// noise sampled in **canvas space**, so (by default) the grain stays pinned to
/// the paper as strokes cross it (like real tooth), rather than sliding with the
/// brush.
///
/// The SAME integer hash and interpolation are mirrored in BrushRender's Metal
/// shader (`GrainNoise` MSL), so the GPU live canvas and the CPU reference
/// renderer show the same tooth. Pure integer→float math keeps it stable across
/// platforms.
public enum GrainNoise {
    /// Value noise at canvas point (x, y). `cell` is the grain scale in points
    /// (bigger = coarser tooth). Returns 0…1. `seed` decorrelates textures.
    public static func value(x: Double, y: Double, cell: Double, seed: UInt32) -> Double {
        let s = max(cell, 0.5)
        let gx = x / s
        let gy = y / s
        let x0 = Int(floor(gx))
        let y0 = Int(floor(gy))
        let fx = smooth(gx - Double(x0))
        let fy = smooth(gy - Double(y0))
        let v00 = hash(x0, y0, seed)
        let v10 = hash(x0 + 1, y0, seed)
        let v01 = hash(x0, y0 + 1, seed)
        let v11 = hash(x0 + 1, y0 + 1, seed)
        let top = v00 + (v10 - v00) * fx
        let bottom = v01 + (v11 - v01) * fx
        return top + (bottom - top) * fy
    }

    /// The grain multiplier for a dab's coverage at (x, y): 1 where the tooth is
    /// high, down to `1 - depth` in the pits. `depth` 0 = no grain.
    public static func coverage(
        x: Double, y: Double, cell: Double, depth: Double, seed: UInt32
    ) -> Double {
        guard depth > 0 else { return 1 }
        let n = value(x: x, y: y, cell: cell, seed: seed)
        return 1 - depth * (1 - n)
    }

    /// Smoothstep for the interpolation (matches the shader).
    private static func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }

    /// A hash of an integer lattice point → 0…1. Same constants as the shader.
    private static func hash(_ x: Int, _ y: Int, _ seed: UInt32) -> Double {
        var h = UInt32(truncatingIfNeeded: x) &* 0x8DA6_B343
        h = h &+ UInt32(truncatingIfNeeded: y) &* 0xD8163_841 &+ seed &* 0x1B56_C4E9
        h = (h ^ (h >> 15)) &* 0x2C1B_3C6D
        h = (h ^ (h >> 12)) &* 0x2974_59E7
        h = h ^ (h >> 15)
        return Double(h) / Double(UInt32.max)
    }
}
