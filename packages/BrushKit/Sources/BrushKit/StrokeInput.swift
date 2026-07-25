import CoreGraphics
import Foundation

/// One captured input sample along a stroke, in **canvas point space** (the app
/// converts from its view/normalized coordinates before handing it over). Every
/// platform — Apple Pencil, a Wacom tablet, a trackpad — normalises into this
/// one shape so the engine never sees platform APIs.
public struct StrokeSample: Equatable, Sendable, Codable {
    public var position: CGPoint
    /// 0…1. 1 for inputs with no pressure (mouse/trackpad) unless the app
    /// synthesises it from velocity.
    public var pressure: Double
    /// Pen tilt from the surface: π/2 = upright, 0 = flat. π/2 when unknown.
    public var altitude: Double
    /// Tilt bearing (radians, 0 = +x). 0 when unknown.
    public var azimuth: Double
    /// Point-space speed at this sample (points/second). Derived from timestamps
    /// by `StrokeInput` when the app does not supply it.
    public var velocity: Double
    /// Seconds since an arbitrary origin; only differences matter.
    public var timestamp: TimeInterval

    public init(
        position: CGPoint, pressure: Double = 1, altitude: Double = .pi / 2,
        azimuth: Double = 0, velocity: Double = 0, timestamp: TimeInterval = 0
    ) {
        self.position = position
        self.pressure = pressure
        self.altitude = altitude
        self.azimuth = azimuth
        self.velocity = velocity
        self.timestamp = timestamp
    }
}

/// A captured stroke: the raw samples plus the passes that turn jittery input
/// into a clean spine the dab generator can walk — velocity derivation and
/// positional smoothing. Deliberately platform-free and value-typed.
public struct StrokeInput: Equatable, Sendable, Codable {
    public var samples: [StrokeSample]

    public init(samples: [StrokeSample] = []) {
        self.samples = samples
    }

    public var isEmpty: Bool { samples.isEmpty }

    /// Total spine length in points (straight segments between samples).
    public var arcLength: Double {
        guard samples.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<samples.count {
            total += samples[i - 1].position.distance(to: samples[i].position)
        }
        return total
    }

    /// Fill in `velocity` from consecutive timestamps where it is zero, so the
    /// engine's velocity dynamics work even when the app only sends positions.
    public func withDerivedVelocity() -> StrokeInput {
        guard samples.count > 1 else { return self }
        var out = samples
        for i in 1..<out.count where out[i].velocity == 0 {
            let dt = out[i].timestamp - out[i - 1].timestamp
            let d = out[i - 1].position.distance(to: out[i].position)
            out[i].velocity = dt > 1e-6 ? d / dt : 0
        }
        return StrokeInput(samples: out)
    }

    /// A positionally-smoothed copy: each interior sample is pulled toward the
    /// average of its neighbours by `amount` (0 = untouched, 1 = fully
    /// averaged), a cheap low-pass that tames hand tremor. Pressure/tilt ride
    /// along unchanged. `passes` applies it repeatedly for stronger smoothing.
    ///
    /// A simple, dependency-free stand-in for the one-euro filter P2 will add;
    /// endpoints are pinned so the stroke never shrinks away from where it
    /// started or ended.
    public func smoothed(amount: Double, passes: Int = 1) -> StrokeInput {
        guard amount > 0, samples.count > 2, passes > 0 else { return self }
        let a = min(max(amount, 0), 1)
        var pts = samples
        for _ in 0..<passes {
            var next = pts
            for i in 1..<(pts.count - 1) {
                let mid = CGPoint(
                    x: (pts[i - 1].position.x + pts[i + 1].position.x) / 2,
                    y: (pts[i - 1].position.y + pts[i + 1].position.y) / 2)
                next[i].position = CGPoint(
                    x: pts[i].position.x + (mid.x - pts[i].position.x) * a,
                    y: pts[i].position.y + (mid.y - pts[i].position.y) * a)
            }
            pts = next
        }
        return StrokeInput(samples: pts)
    }

    /// Sample the stroke at arc-length `distance` from the start, linearly
    /// interpolating position/pressure/tilt between the bracketing samples.
    /// Clamped to the endpoints. Used by the dab generator's even spacing walk.
    public func sample(atArcLength distance: Double) -> StrokeSample? {
        guard let first = samples.first else { return nil }
        guard samples.count > 1, distance > 0 else { return first }
        var travelled = 0.0
        for i in 1..<samples.count {
            let a = samples[i - 1]
            let b = samples[i]
            let seg = a.position.distance(to: b.position)
            if seg <= 0 { continue }
            if travelled + seg >= distance {
                let t = (distance - travelled) / seg
                return StrokeSample.lerp(a, b, t)
            }
            travelled += seg
        }
        return samples.last
    }
}

extension StrokeSample {
    /// Linear blend of two samples (t in 0…1).
    static func lerp(_ a: StrokeSample, _ b: StrokeSample, _ t: Double) -> StrokeSample {
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        return StrokeSample(
            position: CGPoint(
                x: a.position.x + (b.position.x - a.position.x) * t,
                y: a.position.y + (b.position.y - a.position.y) * t),
            pressure: mix(a.pressure, b.pressure),
            altitude: mix(a.altitude, b.altitude),
            azimuth: mix(a.azimuth, b.azimuth),
            velocity: mix(a.velocity, b.velocity),
            timestamp: mix(a.timestamp, b.timestamp))
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> Double {
        let dx = other.x - x
        let dy = other.y - y
        return (dx * dx + dy * dy).squareRoot()
    }
}
