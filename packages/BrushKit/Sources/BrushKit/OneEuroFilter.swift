import CoreGraphics
import Foundation

/// The 1€ (one-euro) filter — the standard low-latency smoother for pointer and
/// stylus input (Casiez, Roussel & Vogel, 2012). It adapts: it smooths hard
/// when the pen moves slowly (killing tremor) and barely at all when it moves
/// fast (killing lag), which a fixed moving average cannot do. This is what
/// makes an inked line feel clean without feeling rubbery.
///
/// `StrokeInput.oneEuroSmoothed` applies it to a captured stroke; the engine
/// uses it as the live smoothing path.
struct OneEuroFilter {
    var minCutoff: Double
    var beta: Double
    var dCutoff: Double

    init(minCutoff: Double, beta: Double, dCutoff: Double = 1) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    private var lastValue: Double?
    private var lastDeriv = 0.0

    private static func alpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1 / (2 * .pi * cutoff)
        return 1 / (1 + tau / dt)
    }

    mutating func filter(_ value: Double, dt: Double) -> Double {
        guard let prev = lastValue, dt > 0 else {
            lastValue = value
            return value
        }
        // Derivative, low-pass filtered.
        let deriv = (value - prev) / dt
        let ad = Self.alpha(cutoff: dCutoff, dt: dt)
        let smoothDeriv = ad * deriv + (1 - ad) * lastDeriv
        lastDeriv = smoothDeriv
        // Adaptive cutoff: faster movement → higher cutoff → less smoothing.
        let cutoff = minCutoff + beta * abs(smoothDeriv)
        let a = Self.alpha(cutoff: cutoff, dt: dt)
        let smoothed = a * value + (1 - a) * prev
        lastValue = smoothed
        return smoothed
    }
}

extension StrokeInput {
    /// A 1€-filtered copy of the stroke (position only; pressure/tilt ride
    /// along). `minCutoff` lower = smoother; `beta` higher = more responsive to
    /// speed. Samples with no time delta pass through unfiltered. Endpoints are
    /// preserved (the filter seeds on the first sample).
    public func oneEuroSmoothed(minCutoff: Double, beta: Double) -> StrokeInput {
        guard samples.count > 2 else { return self }
        var fx = OneEuroFilter(minCutoff: minCutoff, beta: beta)
        var fy = OneEuroFilter(minCutoff: minCutoff, beta: beta)
        var out = samples
        for i in out.indices {
            let dt = i == 0 ? 0 : out[i].timestamp - samples[i - 1].timestamp
            let x = fx.filter(Double(samples[i].position.x), dt: dt)
            let y = fy.filter(Double(samples[i].position.y), dt: dt)
            out[i].position = CGPoint(x: x, y: y)
        }
        // Pin the true endpoints so the stroke never pulls away from where it
        // started or ended.
        out[0].position = samples[0].position
        out[out.count - 1].position = samples[samples.count - 1].position
        return StrokeInput(samples: out)
    }
}
