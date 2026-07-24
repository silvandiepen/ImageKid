import CoreGraphics
import Foundation

/// One stamp the renderer draws. Everything the GPU (BrushRender) or the CPU
/// reference renderer needs, already resolved from input + brush — renderers do
/// no dynamics of their own, they only paint dabs. Colour is carried per-dab so
/// hue jitter and per-stroke tint live in one place.
public struct Dab: Equatable, Sendable {
    public var position: CGPoint
    public var diameter: Double
    /// Nib angle in radians (tip angle + tilt/jitter).
    public var angle: Double
    /// 1 = circular, <1 = ellipse minor/major ratio.
    public var roundness: Double
    /// Combined alpha this stamp lays down (flow × dynamics × taper).
    public var alpha: Double
    /// Soft edge 1 = crisp … 0 = feathered.
    public var hardness: Double
    /// sRGB 0…1; alpha here is the colour's own (usually 1 — coverage is `alpha`).
    public var color: RGBA
    /// Grain (paper tooth): the pit depth 0…1 (0 = smooth), the tooth scale in
    /// points, and a decorrelation seed. Sampled in canvas space by the
    /// renderers via `GrainNoise`.
    public var grainDepth: Double
    public var grainCell: Double
    public var grainSeed: UInt32
    /// Square footprint (Chebyshev falloff) instead of round. Textured tips fall
    /// back to round until their stamp textures land.
    public var square: Bool

    public init(
        position: CGPoint, diameter: Double, angle: Double, roundness: Double,
        alpha: Double, hardness: Double, color: RGBA,
        grainDepth: Double = 0, grainCell: Double = 8, grainSeed: UInt32 = 0,
        square: Bool = false
    ) {
        self.position = position
        self.diameter = diameter
        self.angle = angle
        self.roundness = roundness
        self.alpha = alpha
        self.hardness = hardness
        self.color = color
        self.grainDepth = grainDepth
        self.grainCell = grainCell
        self.grainSeed = grainSeed
        self.square = square
    }
}

public struct RGBA: Equatable, Sendable, Codable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double
    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
    public static let black = RGBA(r: 0, g: 0, b: 0)

    /// This colour with its hue rotated by `turns` (1 = a full 360°). Keeps
    /// saturation/value/alpha. Used by the hue-jitter dynamic.
    public func hueShifted(by turns: Double) -> RGBA {
        guard turns != 0 else { return self }
        var (h, s, v) = RGBA.rgbToHSV(r: r, g: g, b: b)
        h = (h + turns).truncatingRemainder(dividingBy: 1)
        if h < 0 { h += 1 }
        let (nr, ng, nb) = RGBA.hsvToRGB(h: h, s: s, v: v)
        return RGBA(r: nr, g: ng, b: nb, a: a)
    }

    static func rgbToHSV(r: Double, g: Double, b: Double) -> (h: Double, s: Double, v: Double) {
        let mx = max(r, g, b)
        let mn = min(r, g, b)
        let delta = mx - mn
        var h = 0.0
        if delta > 1e-9 {
            if mx == r { h = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (b - r) / delta + 2 }
            else { h = (r - g) / delta + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, mx > 0 ? delta / mx : 0, mx)
    }

    static func hsvToRGB(h: Double, s: Double, v: Double) -> (r: Double, g: Double, b: Double) {
        if s <= 0 { return (v, v, v) }
        let i = Int(h * 6) % 6
        let f = h * 6 - Double(Int(h * 6))
        let p = v * (1 - s)
        let q = v * (1 - s * f)
        let t = v * (1 - s * (1 - f))
        switch i {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }
}

/// The portable heart: turns a captured stroke into evenly-spaced stamps.
///
/// Deterministic — jitter comes from a seed, so the same stroke + brush + seed
/// always yields the same dabs (tests and non-destructive re-rasterization both
/// depend on this). P0 implements even spacing, pressure→size/opacity/flow, and
/// taper; the remaining dynamics fields are honoured as they land in P2.
public enum BrushEngine {
    /// Generate the dab list for `stroke` painted with `brush` in `color`.
    /// `seed` makes jitter reproducible (default 0). The stroke is smoothed by
    /// the brush's `smoothing` and given derived velocity first.
    public static func dabs(
        for stroke: StrokeInput, brush: Brush, color: RGBA, seed: UInt64 = 0
    ) -> [Dab] {
        // Live smoothing: the 1€ filter (adaptive, low-latency) when the brush
        // asks for it. `smoothing` 0…1 maps to a cutoff — more smoothing = a
        // lower cutoff. Zero leaves the raw spine (deterministic tests rely on
        // that untouched path).
        let base = stroke.withDerivedVelocity()
        let prepared: StrokeInput
        if brush.smoothing > 0 {
            let s = min(max(brush.smoothing, 0), 1)
            prepared = base.oneEuroSmoothed(minCutoff: 4.5 - 4.1 * s, beta: 0.02)
        } else {
            prepared = base
        }
        guard prepared.samples.count >= 1 else { return [] }

        var rng = SplitMix64(seed: seed &+ 0x9E37_79B9_7F4A_7C15)

        // A single tap (no length) still leaves one stamp.
        let length = prepared.arcLength
        if length <= 0, let s = prepared.samples.first {
            return [dab(at: s, along: 0, of: 0, brush: brush, color: color, rng: &rng)]
        }

        var dabs: [Dab] = []
        var distance = 0.0
        // Spacing scales with the current diameter, so a pressure-swelling
        // stroke keeps a constant *visual* dab density.
        while distance <= length {
            guard let s = prepared.sample(atArcLength: distance) else { break }
            let d = dab(at: s, along: distance, of: length, brush: brush, color: color, rng: &rng)
            dabs.append(d)
            let step = max(0.5, brush.tip.spacing * d.diameter)
            distance += step
        }
        return dabs
    }

    private static func dab(
        at s: StrokeSample, along distance: Double, of length: Double, brush: Brush,
        color: RGBA, rng: inout SplitMix64
    ) -> Dab {
        let dyn = brush.dynamics
        // Shaped inputs: raw pressure/speed through their response curves — the
        // difference between a linear pen and one that feels alive.
        let pressure = dyn.pressureCurve.apply(min(max(s.pressure, 0), 1))
        let fast = dyn.velocityCurve.apply(min(s.velocity / 4000, 1))  // ~4000 pt/s ≈ "fast"
        // Tilt: 0 = pen upright, 1 = laid flat (like shading with a pencil).
        let flatness = 1 - min(max(s.altitude, 0), .pi / 2) / (.pi / 2)

        // Size: base, modulated toward `pressure`, wider when the pen is tilted
        // flat, then the taper ramp, then optional jitter.
        var sizeFactor = 1 - dyn.pressureToSize * (1 - pressure)
        if dyn.velocityToSize > 0 { sizeFactor *= 1 - dyn.velocityToSize * fast }
        if dyn.tiltToSize > 0 { sizeFactor *= 1 + dyn.tiltToSize * flatness }
        sizeFactor *= taperFactor(distance: distance, length: length, taper: brush.taper)
        if dyn.sizeJitter > 0 {
            sizeFactor *= 1 - dyn.sizeJitter * rng.nextUnit()
        }
        let diameter = max(0.1, brush.size * sizeFactor)

        // Alpha: flow, capped by opacity, modulated by pressure/velocity.
        var alpha = brush.flow
        alpha *= 1 - dyn.pressureToOpacity * (1 - pressure)
        if dyn.pressureToFlow > 0 { alpha *= 1 - dyn.pressureToFlow * (1 - pressure) }
        if dyn.velocityToOpacity > 0 { alpha *= 1 - dyn.velocityToOpacity * fast }
        alpha = min(alpha, brush.opacity)

        // Angle: nib angle blended toward the tilt bearing by tiltToAngle, plus
        // jitter. tiltToAngle 1 = the nib fully follows the pen's azimuth.
        var angle = brush.tip.angle
        if dyn.tiltToAngle > 0 { angle = brush.tip.angle * (1 - dyn.tiltToAngle) + s.azimuth * dyn.tiltToAngle }
        if dyn.angleJitter > 0 { angle += dyn.angleJitter * (rng.nextUnit() - 0.5) * 2 * .pi }

        // Scatter offsets the stamp perpendicular-agnostic (round jitter disc).
        var position = s.position
        if brush.tip.scatter > 0 {
            let r = brush.tip.scatter * diameter * rng.nextUnit()
            let theta = rng.nextUnit() * 2 * .pi
            position.x += CGFloat(cos(theta) * r)
            position.y += CGFloat(sin(theta) * r)
        }

        // Hue jitter: rotate this dab's hue by up to ±(hueJitter × half turn).
        var dabColor = color
        if dyn.hueJitter > 0 {
            dabColor = color.hueShifted(by: (rng.nextUnit() - 0.5) * dyn.hueJitter)
        }

        // Grain scale relative to the brush diameter, so tooth tracks size.
        let grainCell = max(1, brush.grain.scale * 8)
        let grainSeed = UInt32(truncatingIfNeeded: brush.id.hashValue)

        return Dab(
            position: position, diameter: diameter, angle: angle,
            roundness: min(max(brush.tip.roundness, 0.05), 1), alpha: max(0, min(alpha, 1)),
            hardness: min(max(brush.tip.hardness, 0), 1), color: dabColor,
            grainDepth: min(max(brush.grain.depth, 0), 1), grainCell: grainCell,
            grainSeed: grainSeed, square: brush.tip.shape == .square)
    }

    /// 0…1 diameter multiplier from the start/end taper ramps.
    private static func taperFactor(distance: Double, length: Double, taper: Brush.Taper) -> Double {
        var f = 1.0
        if taper.startLength > 0, distance < taper.startLength {
            let t = distance / taper.startLength
            f *= taper.startSize + (1 - taper.startSize) * t
        }
        if taper.endLength > 0, distance > length - taper.endLength {
            let t = (length - distance) / taper.endLength
            f *= taper.endSize + (1 - taper.endSize) * min(max(t, 0), 1)
        }
        return f
    }
}

/// SplitMix64 — a tiny, fast, well-distributed seeded PRNG. Deterministic across
/// platforms (pure integer math), so jitter is reproducible in tests and in
/// non-destructive re-rendering. `Math.random` is not used anywhere in the engine.
public struct SplitMix64 {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A double in [0, 1).
    public mutating func nextUnit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}
