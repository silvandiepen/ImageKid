import Foundation

/// CSS timing functions, parsed from the authored strings and evaluated for
/// preview playback. `cubicBezier` uses the WebKit UnitBezier method
/// (Horner-form sampling + Newton–Raphson with a bisection fallback), the
/// same math browsers run, so scrubbed previews match shipped CSS.
public enum TimingFunction: Equatable, Sendable {
    case linear
    case cubicBezier(Double, Double, Double, Double)
    case steps(Int, StepPosition)

    public enum StepPosition: String, Equatable, Sendable {
        case start, end
        case jumpStart = "jump-start"
        case jumpEnd = "jump-end"
        case jumpBoth = "jump-both"
        case jumpNone = "jump-none"
    }

    public static let ease = TimingFunction.cubicBezier(0.25, 0.1, 0.25, 1)
    public static let easeIn = TimingFunction.cubicBezier(0.42, 0, 1, 1)
    public static let easeOut = TimingFunction.cubicBezier(0, 0, 0.58, 1)
    public static let easeInOut = TimingFunction.cubicBezier(0.42, 0, 0.58, 1)

    public static func parse(_ text: String) -> TimingFunction? {
        let t = text.trimmingCharacters(in: .whitespaces)
        switch t {
        case "linear": return .linear
        case "ease": return .ease
        case "ease-in": return .easeIn
        case "ease-out": return .easeOut
        case "ease-in-out": return .easeInOut
        case "step-start": return .steps(1, .start)
        case "step-end": return .steps(1, .end)
        default: break
        }
        if t.hasPrefix("cubic-bezier("), t.hasSuffix(")") {
            let args = t.dropFirst("cubic-bezier(".count).dropLast()
                .split(separator: ",")
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard args.count == 4 else { return nil }
            return .cubicBezier(args[0], args[1], args[2], args[3])
        }
        if t.hasPrefix("steps("), t.hasSuffix(")") {
            let args = t.dropFirst("steps(".count).dropLast()
                .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let n = args.first.flatMap({ Int($0) }), n > 0 else { return nil }
            let position = args.count > 1 ? StepPosition(rawValue: args[1]) : .end
            guard let position else { return nil }
            if position == .jumpNone && n < 2 { return nil }
            return .steps(n, position)
        }
        return nil
    }

    /// Output progress for input progress `x` (both 0…1).
    public func evaluate(_ x: Double) -> Double {
        switch self {
        case .linear:
            return min(1, max(0, x))
        case .cubicBezier(let x1, let y1, let x2, let y2):
            if x <= 0 { return 0 }
            if x >= 1 { return 1 }
            return UnitBezier(x1: x1, y1: y1, x2: x2, y2: y2).solve(x)
        case .steps(let n, let position):
            if x >= 1 { return 1 }
            if x < 0 { return 0 }
            let (jumps, increment): (Int, Int)
            switch position {
            case .start, .jumpStart: (jumps, increment) = (n, 1)
            case .end, .jumpEnd: (jumps, increment) = (n, 0)
            case .jumpBoth: (jumps, increment) = (n + 1, 1)
            case .jumpNone: (jumps, increment) = (n - 1, 0)
            }
            let current = Int((x * Double(n)).rounded(.down)) + increment
            return min(1, max(0, Double(current) / Double(max(jumps, 1))))
        }
    }

    /// WebKit's unit-interval cubic bezier solver.
    struct UnitBezier {
        let ax, bx, cx, ay, by, cy: Double

        init(x1: Double, y1: Double, x2: Double, y2: Double) {
            cx = 3 * x1
            bx = 3 * (x2 - x1) - cx
            ax = 1 - cx - bx
            cy = 3 * y1
            by = 3 * (y2 - y1) - cy
            ay = 1 - cy - by
        }

        func sampleX(_ t: Double) -> Double { ((ax * t + bx) * t + cx) * t }
        func sampleY(_ t: Double) -> Double { ((ay * t + by) * t + cy) * t }
        func sampleDX(_ t: Double) -> Double { (3 * ax * t + 2 * bx) * t + cx }

        func solve(_ x: Double, epsilon: Double = 1e-6) -> Double {
            // Newton–Raphson.
            var t = x
            for _ in 0..<8 {
                let dx = sampleX(t) - x
                if abs(dx) < epsilon { return sampleY(t) }
                let d = sampleDX(t)
                if abs(d) < 1e-6 { break }
                t -= dx / d
            }
            // Bisection fallback.
            var lo = 0.0
            var hi = 1.0
            t = x
            while hi - lo > epsilon {
                let dx = sampleX(t) - x
                if abs(dx) < epsilon { break }
                if dx > 0 { hi = t } else { lo = t }
                t = (lo + hi) / 2
            }
            return sampleY(t)
        }
    }
}

/// The simulated consumer context while previewing in the editor: which
/// pseudo-states are "on" and which gate classes are pretended present.
public struct AnimationPreviewState: Equatable, Sendable {
    public var hover = false
    public var focus = false
    public var active = false
    public var gateClasses: Set<String> = []
    /// Simulates the `.animate` utility: force-play everything (including
    /// `manual` bindings, which have no authored selector).
    public var forcePlay = false

    public init(
        hover: Bool = false, focus: Bool = false, active: Bool = false,
        gateClasses: Set<String> = [], forcePlay: Bool = false
    ) {
        self.hover = hover
        self.focus = focus
        self.active = active
        self.gateClasses = gateClasses
        self.forcePlay = forcePlay
    }

    public func satisfies(_ trigger: AnimationTrigger) -> Bool {
        if forcePlay { return true }
        switch trigger {
        case .continuous: return true
        case .hover: return hover
        case .focus: return focus
        case .active: return active
        case .parentClass(let cls): return gateClasses.contains(cls)
        case .manual: return false
        }
    }
}

/// What the canvas needs to know about a bound element to resolve
/// percentage translates, transform origins, dash normalization, and
/// implicit start frames. Bounds are the element's untransformed bbox in
/// user units (CSS `transform-box: fill-box`).
public struct AnimationTargetContext: Sendable {
    public var bounds: ViewBox
    public var baseOpacity: Double
    public var baseFill: PaintValue?
    public var baseStroke: PaintValue?
    public var baseStrokeWidth: Double
    public var baseStrokeDashoffset: Double
    /// Real geometric path length; converts `pathLength="100"`-normalized
    /// dash keyframes into canvas units. nil skips dash overrides.
    public var pathLength: Double?

    public init(
        bounds: ViewBox, baseOpacity: Double = 1, baseFill: PaintValue? = nil,
        baseStroke: PaintValue? = nil, baseStrokeWidth: Double = 1,
        baseStrokeDashoffset: Double = 0, pathLength: Double? = nil
    ) {
        self.bounds = bounds
        self.baseOpacity = baseOpacity
        self.baseFill = baseFill
        self.baseStroke = baseStroke
        self.baseStrokeWidth = baseStrokeWidth
        self.baseStrokeDashoffset = baseStrokeDashoffset
        self.pathLength = pathLength
    }
}

/// The per-element render deltas at one moment of preview time. The canvas
/// concatenates `transform`, multiplies `opacity`, and substitutes the
/// paint/stroke fields; everything nil leaves the base render untouched.
public struct AnimatedOverride: Equatable, Sendable {
    /// Column-major 2×3 matrix (a b c d tx ty) to concatenate after the
    /// node's own transform. Includes the transform-origin conjugation.
    public var transform: [Double]?
    public var opacity: Double?
    public var fill: PaintValue?
    public var stroke: PaintValue?
    public var strokeWidth: Double?
    public var strokeDashoffset: Double?
    /// Dash period covering the whole path (draw-on effects).
    public var strokeDasharray: Double?
    public var hidden: Bool?

    public var isEmpty: Bool {
        transform == nil && opacity == nil && fill == nil && stroke == nil
            && strokeWidth == nil && strokeDashoffset == nil && strokeDasharray == nil
            && hidden == nil
    }
}

/// Replays the compiled CSS semantics on the editor's clock: keyframe
/// interpolation with per-segment easing, delay/iteration/direction/fill,
/// sRGB color lerp, TRS transform composition around the origin.
///
/// The transform model is the authored subset (translate/rotate/scale as
/// TRS components, composed T·R·S around `transform-origin`) — matching
/// what the timeline writes and what the presets emit, not arbitrary CSS
/// transform lists.
public enum AnimationInterpolator {

    /// Overrides for every satisfied binding at `time` (seconds since the
    /// icon's shared clock zero), keyed by binding target class.
    public static func resolve(
        defs: [AnimationDef], bindings: [AnimationBinding], settings: AnimationSettings,
        time: Double, state: AnimationPreviewState,
        context: (String) -> AnimationTargetContext?
    ) -> [String: AnimatedOverride] {
        let byName = Dictionary(defs.map { ($0.name, $0) }) { first, _ in first }
        var out: [String: AnimatedOverride] = [:]
        for binding in bindings {
            guard let def = byName[binding.animation] else { continue }
            let r = AnimationCSS.ResolvedBinding(
                binding: binding, def: def.normalized(), compiled: "", settings: settings)
            guard state.satisfies(r.trigger) else { continue }
            guard let ctx = context(binding.target) else { continue }
            guard let progress = directedProgress(r, time: time) else { continue }
            let override = override(r, progress: progress, ctx: ctx)
            if !override.isEmpty { out[binding.target] = override }
        }
        return out
    }

    /// A binding's timing resolved through the full cascade — the editor
    /// uses this for track lengths and scene duration.
    public struct ResolvedTiming: Equatable, Sendable {
        public let duration: Double
        public let delay: Double
        /// `.infinity` for infinite iteration counts.
        public let iterations: Double
        public let trigger: AnimationTrigger
    }

    public static func timing(
        of binding: AnimationBinding, def: AnimationDef, settings: AnimationSettings
    ) -> ResolvedTiming {
        let r = AnimationCSS.ResolvedBinding(
            binding: binding, def: def, compiled: "", settings: settings)
        let iterations: Double =
            r.iterationCount == "infinite" ? .infinity : max(Double(r.iterationCount) ?? 1, 0)
        return ResolvedTiming(
            duration: r.duration, delay: r.delay, iterations: iterations, trigger: r.trigger)
    }

    // MARK: - Clock → progress

    /// The directed 0…1 progress through the keyframes at `time`, or nil
    /// when the animation has no effect (before delay without backwards
    /// fill; past the end without forwards fill).
    static func directedProgress(_ r: AnimationCSS.ResolvedBinding, time: Double) -> Double? {
        let duration = max(r.duration, 1e-9)
        let iterations: Double =
            r.iterationCount == "infinite" ? .infinity : max(Double(r.iterationCount) ?? 1, 0)
        let local = time - r.delay
        let fillsBackwards = r.fillMode == "backwards" || r.fillMode == "both"
        let fillsForwards = r.fillMode == "forwards" || r.fillMode == "both"

        func directed(iteration: Double, progress: Double) -> Double {
            switch r.direction {
            case "reverse": return 1 - progress
            case "alternate":
                return iteration.truncatingRemainder(dividingBy: 2) < 1 ? progress : 1 - progress
            case "alternate-reverse":
                return iteration.truncatingRemainder(dividingBy: 2) < 1 ? 1 - progress : progress
            default: return progress
            }
        }

        if local < 0 {
            guard fillsBackwards else { return nil }
            return directed(iteration: 0, progress: 0)
        }
        let total = duration * iterations
        if local >= total {
            guard fillsForwards, iterations.isFinite else { return nil }
            // Hold the end of the last iteration.
            let last = max(iterations.rounded(.up) - 1, 0)
            let endProgress = iterations - last  // 1 for whole counts, fraction otherwise
            return directed(iteration: last, progress: min(endProgress, 1))
        }
        let iteration = (local / duration).rounded(.down)
        let progress = (local - iteration * duration) / duration
        return directed(iteration: iteration, progress: progress)
    }

    // MARK: - Keyframe interpolation

    static func override(
        _ r: AnimationCSS.ResolvedBinding, progress: Double, ctx: AnimationTargetContext
    ) -> AnimatedOverride {
        var out = AnimatedOverride()
        let frames = r.def.keyframes
        let animationTiming = TimingFunction.parse(r.timingFunction) ?? .ease

        // Properties declared anywhere in the def.
        var properties = Set<String>()
        for frame in frames { properties.formUnion(frame.declarations.keys) }

        for property in properties {
            // The frames that declare this property, plus implicit 0%/100%
            // frames holding the base value.
            var stops: [(offset: Double, value: String?, easing: TimingFunction)] = []
            for frame in frames where frame.declarations[property] != nil {
                stops.append(
                    (frame.offset / 100, frame.declarations[property],
                     frame.easing.flatMap(TimingFunction.parse) ?? animationTiming))
            }
            if stops.first!.offset > 0 {
                stops.insert((0, nil, animationTiming), at: 0)
            }
            if stops.last!.offset < 1 {
                stops.append((1, nil, animationTiming))
            }

            // Bracketing pair; the FROM stop's easing shapes the segment.
            var lo = stops[0]
            var hi = stops[stops.count - 1]
            for i in 0..<(stops.count - 1)
            where stops[i].offset <= progress && progress <= stops[i + 1].offset {
                lo = stops[i]
                hi = stops[i + 1]
                break
            }
            let span = hi.offset - lo.offset
            let fraction = span <= 0 ? 1 : (progress - lo.offset) / span
            let eased = lo.easing.evaluate(min(1, max(0, fraction)))
            apply(
                property, from: lo.value, to: hi.value, fraction: eased, ctx: ctx,
                origin: r.transformOrigin, into: &out)
        }
        return out
    }

    private static func apply(
        _ property: String, from: String?, to: String?, fraction: Double,
        ctx: AnimationTargetContext, origin: String, into out: inout AnimatedOverride
    ) {
        switch property {
        case "transform":
            let a = TRS.parse(from, bounds: ctx.bounds) ?? .identity
            let b = TRS.parse(to, bounds: ctx.bounds) ?? .identity
            out.transform = TRS.lerp(a, b, fraction)
                .matrix(origin: origin, bounds: ctx.bounds)
        case "opacity":
            let a = from.flatMap(Double.init) ?? ctx.baseOpacity
            let b = to.flatMap(Double.init) ?? ctx.baseOpacity
            out.opacity = lerp(a, b, fraction)
        case "fill":
            out.fill = lerpPaint(
                from.map(SVGStyle.paint) ?? ctx.baseFill,
                to.map(SVGStyle.paint) ?? ctx.baseFill, fraction)
        case "stroke":
            out.stroke = lerpPaint(
                from.map(SVGStyle.paint) ?? ctx.baseStroke,
                to.map(SVGStyle.paint) ?? ctx.baseStroke, fraction)
        case "stroke-width":
            let a = from.flatMap(Double.init) ?? ctx.baseStrokeWidth
            let b = to.flatMap(Double.init) ?? ctx.baseStrokeWidth
            out.strokeWidth = lerp(a, b, fraction)
        case "stroke-dashoffset":
            guard let length = ctx.pathLength else { return }
            // Keyframes are on the pathLength="100" normalized ruler.
            let a = (from.flatMap(Double.init) ?? ctx.baseStrokeDashoffset) / 100 * length
            let b = (to.flatMap(Double.init) ?? ctx.baseStrokeDashoffset) / 100 * length
            out.strokeDashoffset = lerp(a, b, fraction)
            out.strokeDasharray = length
        case "stroke-dasharray":
            guard let length = ctx.pathLength else { return }
            let a = (from.flatMap(firstNumber) ?? 100) / 100 * length
            let b = (to.flatMap(firstNumber) ?? 100) / 100 * length
            out.strokeDasharray = lerp(a, b, fraction)
        case "visibility":
            // CSS: visible whenever either endpoint is visible mid-segment.
            let a = from ?? "visible"
            let b = to ?? "visible"
            if fraction <= 0 {
                out.hidden = a == "hidden"
            } else if fraction >= 1 {
                out.hidden = b == "hidden"
            } else {
                out.hidden = a == "hidden" && b == "hidden"
            }
        default:
            break  // transform-origin rides the binding, not keyframes, in v1.
        }
    }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    private static func firstNumber(_ text: String) -> Double? {
        text.split(whereSeparator: { $0 == " " || $0 == "," }).first.flatMap { Double($0) }
    }

    /// sRGB component lerp between paints; non-color paints swap discretely
    /// at the segment midpoint.
    private static func lerpPaint(_ a: PaintValue?, _ b: PaintValue?, _ t: Double)
        -> PaintValue?
    {
        guard let a, let b else { return t < 0.5 ? a : b }
        if case .color(let r1, let g1, let b1) = a, case .color(let r2, let g2, let b2) = b {
            func mix(_ x: UInt8, _ y: UInt8) -> UInt8 {
                UInt8(min(255, max(0, (Double(x) + (Double(y) - Double(x)) * t).rounded())))
            }
            return .color(r: mix(r1, r2), g: mix(g1, g2), b: mix(b1, b2))
        }
        return t < 0.5 ? a : b
    }

    // MARK: - Transforms

    /// The authored transform subset as TRS components. Composition is
    /// T·R·S around the transform origin.
    struct TRS: Equatable {
        var tx = 0.0
        var ty = 0.0
        var rotation = 0.0  // degrees
        var sx = 1.0
        var sy = 1.0

        static let identity = TRS()

        /// Parse `translate(…) rotate(…) scale(…)`-style values; percent
        /// translates resolve against the element bounds.
        static func parse(_ text: String?, bounds: ViewBox) -> TRS? {
            guard let text else { return nil }
            var out = TRS()
            var scanner = text[...]
            var found = false
            while let open = scanner.firstIndex(of: "(") {
                let name = scanner[..<open].trimmingCharacters(in: .whitespaces)
                guard let close = scanner[open...].firstIndex(of: ")") else { break }
                let args = scanner[scanner.index(after: open)..<close]
                    .split(whereSeparator: { $0 == "," || $0 == " " })
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                func length(_ i: Int, axis: Double) -> Double {
                    guard i < args.count else { return 0 }
                    let a = args[i]
                    if a.hasSuffix("%") {
                        return (Double(a.dropLast()) ?? 0) / 100 * axis
                    }
                    return Double(a.replacingOccurrences(of: "px", with: "")) ?? 0
                }
                func number(_ i: Int, fallback: Double) -> Double {
                    guard i < args.count else { return fallback }
                    return Double(
                        args[i].replacingOccurrences(of: "deg", with: "")) ?? fallback
                }
                switch name {
                case "translate":
                    out.tx = length(0, axis: bounds.width)
                    out.ty = length(1, axis: bounds.height)
                case "translateX": out.tx = length(0, axis: bounds.width)
                case "translateY": out.ty = length(0, axis: bounds.height)
                case "rotate": out.rotation = number(0, fallback: 0)
                case "scale":
                    out.sx = number(0, fallback: 1)
                    out.sy = args.count > 1 ? number(1, fallback: out.sx) : out.sx
                case "scaleX": out.sx = number(0, fallback: 1)
                case "scaleY": out.sy = number(0, fallback: 1)
                default: break
                }
                found = true
                scanner = scanner[scanner.index(after: close)...]
            }
            return found ? out : nil
        }

        static func lerp(_ a: TRS, _ b: TRS, _ t: Double) -> TRS {
            var out = TRS()
            out.tx = a.tx + (b.tx - a.tx) * t
            out.ty = a.ty + (b.ty - a.ty) * t
            out.rotation = a.rotation + (b.rotation - a.rotation) * t
            out.sx = a.sx + (b.sx - a.sx) * t
            out.sy = a.sy + (b.sy - a.sy) * t
            return out
        }

        /// `translate(origin) · T · R · S · translate(-origin)` as
        /// (a b c d tx ty).
        func matrix(origin: String, bounds: ViewBox) -> [Double] {
            let o = AnimationInterpolator.origin(origin, bounds: bounds)
            let radians = rotation * .pi / 180
            var m: [Double] = [1, 0, 0, 1, o.x + tx, o.y + ty]
            m = multiply(m, [cos(radians), sin(radians), -sin(radians), cos(radians), 0, 0])
            m = multiply(m, [sx, 0, 0, sy, 0, 0])
            m = multiply(m, [1, 0, 0, 1, -o.x, -o.y])
            return m
        }

        private func multiply(_ a: [Double], _ b: [Double]) -> [Double] {
            [
                a[0] * b[0] + a[2] * b[1],
                a[1] * b[0] + a[3] * b[1],
                a[0] * b[2] + a[2] * b[3],
                a[1] * b[2] + a[3] * b[3],
                a[0] * b[4] + a[2] * b[5] + a[4],
                a[1] * b[4] + a[3] * b[5] + a[5],
            ]
        }
    }

    /// transform-origin against the element bbox (`transform-box: fill-box`
    /// semantics): keywords, percentages, and user-unit lengths.
    static func origin(_ text: String, bounds: ViewBox) -> Pt {
        let parts = text.split(separator: " ").map(String.init)
        func component(_ raw: String?, min: Double, size: Double) -> Double {
            switch raw {
            case nil, "center": return min + size / 2
            case "left", "top": return min
            case "right", "bottom": return min + size
            case .some(let value):
                if value.hasSuffix("%") {
                    return min + (Double(value.dropLast()) ?? 50) / 100 * size
                }
                return min + (Double(value.replacingOccurrences(of: "px", with: "")) ?? 0)
            }
        }
        let x = component(
            parts.count > 0 ? parts[0] : nil, min: bounds.minX, size: bounds.width)
        let y = component(
            parts.count > 1 ? parts[1] : (parts.first == "center" ? "center" : nil),
            min: bounds.minY, size: bounds.height)
        return Pt(x, y)
    }
}
