import CoreGraphics
import Foundation

/// A brush preset — the serialized `.inkbrush` document. Modelled for depth from
/// the start (P2 fills in the dynamics/grain the P0 engine does not yet read),
/// but every field has a sensible default so a minimal brush is `Brush(name:)`.
///
/// App-neutral: no Inka/ImageKid types. Sizes are in **canvas points**; the app
/// decides how a point maps to its document.
public struct Brush: Equatable, Sendable, Codable, Identifiable {
    /// Stable identity a `BrushStroke` references, so a document can re-render
    /// its strokes when the preset changes.
    public var id: String
    public var name: String

    public var tip: Tip
    public var dynamics: Dynamics
    public var grain: Grain
    public var taper: Taper

    /// Base stamp diameter in points (before pressure/velocity dynamics).
    public var size: Double
    /// Per-dab alpha (how much paint each stamp lays down).
    public var flow: Double
    /// Ceiling alpha for the whole stroke (wet buildup never exceeds this).
    public var opacity: Double
    /// Live input smoothing 0…1 (fed to `StrokeInput.smoothed`).
    public var smoothing: Double
    /// SVG/Core-style compositing name for the stroke as a whole; the app maps
    /// it to its layer/blend system. "normal" by default.
    public var blendMode: String

    public init(
        id: String = UUID().uuidString,
        name: String,
        tip: Tip = Tip(),
        dynamics: Dynamics = Dynamics(),
        grain: Grain = Grain(),
        taper: Taper = Taper(),
        size: Double = 24,
        flow: Double = 1,
        opacity: Double = 1,
        smoothing: Double = 0.35,
        blendMode: String = "normal"
    ) {
        self.id = id
        self.name = name
        self.tip = tip
        self.dynamics = dynamics
        self.grain = grain
        self.taper = taper
        self.size = size
        self.flow = flow
        self.opacity = opacity
        self.smoothing = smoothing
        self.blendMode = blendMode
    }

    // MARK: Tip

    /// The stamp's footprint. P0 renders `round`; `square`/`textured` are
    /// modelled and rendered from P2.
    public enum Shape: String, Equatable, Sendable, Codable, CaseIterable {
        case round
        case square
        /// A named grayscale stamp image supplied alongside the preset.
        case textured
    }

    public struct Tip: Equatable, Sendable, Codable {
        public var shape: Shape
        /// Named stamp texture for `.textured` (resolved by the app/renderer).
        public var stampTexture: String?
        /// Soft edge: 1 = crisp, 0 = fully feathered.
        public var hardness: Double
        /// 1 = circular, →0 = a thin ellipse (calligraphic nib).
        public var roundness: Double
        /// Nib angle in radians.
        public var angle: Double
        /// Gap between stamps as a fraction of the current diameter (0.05 = dense).
        public var spacing: Double
        /// Random per-dab position offset, as a fraction of diameter.
        public var scatter: Double

        public init(
            shape: Shape = .round, stampTexture: String? = nil, hardness: Double = 0.85,
            roundness: Double = 1, angle: Double = 0, spacing: Double = 0.08,
            scatter: Double = 0
        ) {
            self.shape = shape
            self.stampTexture = stampTexture
            self.hardness = hardness
            self.roundness = roundness
            self.angle = angle
            self.spacing = spacing
            self.scatter = scatter
        }
    }

    // MARK: Dynamics

    /// How input drives the stamp. Each field is a 0…1 "amount" the input
    /// modulates (0 = the input has no effect on that property). P0 reads the
    /// pressure→size/opacity/flow amounts; the rest land in P2 with proper
    /// response curves.
    public struct Dynamics: Equatable, Sendable, Codable {
        public var pressureToSize: Double
        public var pressureToOpacity: Double
        public var pressureToFlow: Double
        public var velocityToSize: Double
        public var velocityToOpacity: Double
        public var tiltToSize: Double
        public var tiltToAngle: Double
        /// Per-dab random size/angle/hue variation (0 = none).
        public var sizeJitter: Double
        public var angleJitter: Double
        public var hueJitter: Double
        /// Response shaping applied to the raw pressure / speed inputs before
        /// the amounts above use them — the difference between a linear pen and
        /// one that feels alive.
        public var pressureCurve: ResponseCurve
        public var velocityCurve: ResponseCurve

        public init(
            pressureToSize: Double = 0.6, pressureToOpacity: Double = 0.3,
            pressureToFlow: Double = 0, velocityToSize: Double = 0,
            velocityToOpacity: Double = 0, tiltToSize: Double = 0,
            tiltToAngle: Double = 0, sizeJitter: Double = 0, angleJitter: Double = 0,
            hueJitter: Double = 0, pressureCurve: ResponseCurve = .linear,
            velocityCurve: ResponseCurve = .linear
        ) {
            self.pressureToSize = pressureToSize
            self.pressureToOpacity = pressureToOpacity
            self.pressureToFlow = pressureToFlow
            self.velocityToSize = velocityToSize
            self.velocityToOpacity = velocityToOpacity
            self.tiltToSize = tiltToSize
            self.tiltToAngle = tiltToAngle
            self.sizeJitter = sizeJitter
            self.angleJitter = angleJitter
            self.hueJitter = hueJitter
            self.pressureCurve = pressureCurve
            self.velocityCurve = velocityCurve
        }

        // Custom decode so older `.inkbrush` files (no curve fields) still load.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func d(_ k: CodingKeys) -> Double { (try? c.decode(Double.self, forKey: k)) ?? 0 }
            pressureToSize = (try? c.decode(Double.self, forKey: .pressureToSize)) ?? 0.6
            pressureToOpacity = (try? c.decode(Double.self, forKey: .pressureToOpacity)) ?? 0.3
            pressureToFlow = d(.pressureToFlow)
            velocityToSize = d(.velocityToSize)
            velocityToOpacity = d(.velocityToOpacity)
            tiltToSize = d(.tiltToSize)
            tiltToAngle = d(.tiltToAngle)
            sizeJitter = d(.sizeJitter)
            angleJitter = d(.angleJitter)
            hueJitter = d(.hueJitter)
            pressureCurve = (try? c.decode(ResponseCurve.self, forKey: .pressureCurve)) ?? .linear
            velocityCurve = (try? c.decode(ResponseCurve.self, forKey: .velocityCurve)) ?? .linear
        }
    }

    // MARK: Grain (dual-texture) — modelled now, rendered from P2.

    public struct Grain: Equatable, Sendable, Codable {
        public var texture: String?
        public var scale: Double
        public var depth: Double
        /// Grain fixed to the canvas (true) or rolling with the stroke (false).
        public var movingWithStroke: Bool

        public init(
            texture: String? = nil, scale: Double = 1, depth: Double = 0,
            movingWithStroke: Bool = false
        ) {
            self.texture = texture
            self.scale = scale
            self.depth = depth
            self.movingWithStroke = movingWithStroke
        }
    }

    // MARK: Taper

    public struct Taper: Equatable, Sendable, Codable {
        /// Ramp length at each end, in points.
        public var startLength: Double
        public var endLength: Double
        /// Diameter fraction the ramp starts/ends at (0 = a fine point).
        public var startSize: Double
        public var endSize: Double

        public init(
            startLength: Double = 0, endLength: Double = 0, startSize: Double = 0,
            endSize: Double = 0
        ) {
            self.startLength = startLength
            self.endLength = endLength
            self.startSize = startSize
            self.endSize = endSize
        }
    }
}

// MARK: - .inkbrush codec

public enum InkBrushCoding {
    /// Version stamp so the format can evolve without silent misreads.
    public static let formatVersion = 1

    public static func encode(_ brush: Brush) throws -> Data {
        var doc = Envelope(version: formatVersion, brush: brush)
        doc.version = formatVersion
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(doc)
    }

    public static func decode(_ data: Data) throws -> Brush {
        try JSONDecoder().decode(Envelope.self, from: data).brush
    }

    private struct Envelope: Codable {
        var version: Int
        var brush: Brush
    }
}
