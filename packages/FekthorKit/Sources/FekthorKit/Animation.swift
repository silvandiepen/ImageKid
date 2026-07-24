import Foundation

/// A reusable, named keyframe animation — a workspace asset like
/// `NamedStyle`, stored in `Workfile.animations` (master) and copied,
/// resolved, into a bound icon's `FileMeta` so every SVG remains
/// self-contained (a lone file edits its animations without a workspace).
///
/// The def is a pure recipe: keyframes plus timing DEFAULTS. What an icon
/// actually plays is an `AnimationBinding` referencing the def by name,
/// optionally overriding the timing per binding. Compilation to CSS is
/// `AnimationCSS`; binding mechanics are `AnimationEngine`.
public struct AnimationDef: Codable, Equatable, Sendable {
    /// Asset name ("spin"); also the basis of the compiled
    /// `@keyframes` identifier. Sanitized per `AnimationLint.isIdentifier`.
    public var name: String
    /// Keyframes in offset order (normalize with `normalized()`).
    public var keyframes: [AnimationKeyframe]
    /// Timing defaults for bindings of this def; every field optional —
    /// resolution falls through binding → def → icon → workspace → standard.
    public var timing: AnimationTiming?
    /// Draw-style defs (dash keyframes): the engine writes
    /// `pathLength="100"` on bound shapes so `stroke-dasharray`/
    /// `stroke-dashoffset` keyframes are 0–100 regardless of geometry.
    public var normalizesPathLength: Bool?

    public init(
        name: String, keyframes: [AnimationKeyframe], timing: AnimationTiming? = nil,
        normalizesPathLength: Bool? = nil
    ) {
        self.name = name
        self.keyframes = keyframes
        self.timing = timing
        self.normalizesPathLength = normalizesPathLength
    }

    /// The def with keyframes sorted by offset (stable for equal offsets).
    public func normalized() -> AnimationDef {
        var out = self
        out.keyframes = keyframes.enumerated()
            .sorted { ($0.element.offset, $0.offset) < ($1.element.offset, $1.offset) }
            .map(\.element)
        return out
    }

    /// True when any keyframe animates `transform` (or `transform-origin`) —
    /// such defs need `transform-origin`/`transform-box` base declarations.
    public var animatesTransform: Bool {
        keyframes.contains { $0.declarations.keys.contains("transform") }
    }
}

/// One keyframe: an offset on the def's normalized 0–100% ruler and the
/// declarations that hold there. `easing` is the timing function of the
/// segment LEAVING this frame (CSS semantics: `animation-timing-function`
/// inside a keyframe applies from that frame to the next).
public struct AnimationKeyframe: Codable, Equatable, Sendable {
    public var offset: Double
    /// CSS property → value text. Encodes deterministically under the
    /// workfile's sorted-keys encoder. Properties limited to
    /// `AnimationLint.animatableProperties`.
    public var declarations: [String: String]
    public var easing: String?

    public init(offset: Double, declarations: [String: String], easing: String? = nil) {
        self.offset = offset
        self.declarations = declarations
        self.easing = easing
    }
}

/// Timing values for a def or binding. All optional; strings keep the CSS
/// grammar open (`iterationCount` may be "infinite" or "2.5").
public struct AnimationTiming: Codable, Equatable, Sendable {
    public var duration: Double?
    public var delay: Double?
    public var timingFunction: String?
    public var iterationCount: String?
    public var direction: String?
    public var fillMode: String?
    public var transformOrigin: String?

    public init(
        duration: Double? = nil, delay: Double? = nil, timingFunction: String? = nil,
        iterationCount: String? = nil, direction: String? = nil, fillMode: String? = nil,
        transformOrigin: String? = nil
    ) {
        self.duration = duration
        self.delay = delay
        self.timingFunction = timingFunction
        self.iterationCount = iterationCount
        self.direction = direction
        self.fillMode = fillMode
        self.transformOrigin = transformOrigin
    }
}

/// One applied animation inside an icon: which def plays, on which nodes
/// (the marker class `target`), when (`trigger`), and with what timing
/// overrides. The icon's ordered binding list IS its animation scene —
/// there is no separate scene type, matching CSS (no master clock, only
/// per-element delay/duration).
///
/// `target` is an ENGINE-OWNED class token (default
/// `<classPrefix>anim-<defName>`, e.g. `fk-anim-spin`; suffixed when the
/// same def binds twice with different params). Binding by class, never by
/// svgID, means user renames of `id`/`data-name` cannot break bindings.
/// Whole-icon binding puts the class on the `<svg>` root.
public struct AnimationBinding: Codable, Equatable, Sendable {
    /// Name of the `AnimationDef` this binding plays.
    public var animation: String
    /// Marker class on bound node(s) — the CSS selector hook.
    public var target: String
    /// `AnimationTrigger` raw value; nil = the resolved default trigger.
    public var trigger: String?
    /// Per-binding timing overrides; `delay` doubles as the timeline track
    /// offset on the icon's shared clock.
    public var duration: Double?
    public var delay: Double?
    public var iterationCount: String?
    public var direction: String?
    public var fillMode: String?
    public var timingFunction: String?
    public var transformOrigin: String?

    public init(
        animation: String, target: String, trigger: String? = nil,
        duration: Double? = nil, delay: Double? = nil, iterationCount: String? = nil,
        direction: String? = nil, fillMode: String? = nil, timingFunction: String? = nil,
        transformOrigin: String? = nil
    ) {
        self.animation = animation
        self.target = target
        self.trigger = trigger
        self.duration = duration
        self.delay = delay
        self.iterationCount = iterationCount
        self.direction = direction
        self.fillMode = fillMode
        self.timingFunction = timingFunction
        self.transformOrigin = transformOrigin
    }
}

/// When a binding plays. Stored as a string in `AnimationBinding.trigger`
/// so the grammar stays open; `parse` tolerates unknown values as nil.
public enum AnimationTrigger: Equatable, Sendable {
    /// Runs whenever the SVG is live (inline, `<img>`, standalone).
    case continuous
    /// While the icon (or the bound element via the root form) is hovered.
    case hover
    /// While focus is on/inside the icon.
    case focus
    /// While the icon is active (pressed).
    case active
    /// While an ancestor carries `cls` — the "animate when my panel says
    /// so" trigger (`parent-class:live` → `.live svg …`).
    case parentClass(String)
    /// No authored selector at all; only the consumer utility classes
    /// (`.animate` etc.) can start it.
    case manual

    public var rawValue: String {
        switch self {
        case .continuous: return "continuous"
        case .hover: return "hover"
        case .focus: return "focus"
        case .active: return "active"
        case .parentClass(let cls): return "parent-class:\(cls)"
        case .manual: return "manual"
        }
    }

    public static func parse(_ raw: String?) -> AnimationTrigger? {
        guard let raw, !raw.isEmpty else { return nil }
        switch raw {
        case "continuous": return .continuous
        case "hover": return .hover
        case "focus": return .focus
        case "active": return .active
        case "manual": return .manual
        default:
            let prefix = "parent-class:"
            guard raw.hasPrefix(prefix) else { return nil }
            let cls = String(raw.dropFirst(prefix.count))
            return cls.isEmpty ? nil : .parentClass(cls)
        }
    }

    /// Whether starting requires interaction/context that `<img>` and
    /// standalone documents can never provide.
    public var isInteractive: Bool {
        switch self {
        case .continuous: return false
        default: return true
        }
    }
}

/// The animation settings cascade node, present at two levels: workspace
/// (`Workfile.WorkspaceSettings.animations`) and icon
/// (`FileMeta.Meta.animationSettings`). Every field optional; resolution
/// per emitted value is binding → def.timing → icon → workspace →
/// `standard` (with a trigger-dependent iteration default: continuous ⇒
/// infinite, interaction ⇒ 1).
public struct AnimationSettings: Codable, Equatable, Sendable {
    /// Master toggle: false strips/omits the style block (source stays
    /// static). Default true.
    public var enabled: Bool?
    public var defaultTrigger: String?
    public var defaultDuration: Double?
    public var defaultDelay: Double?
    public var defaultTimingFunction: String?
    /// nil → trigger-dependent (see above).
    public var defaultIterationCount: String?
    public var defaultFillMode: String?
    public var defaultTransformOrigin: String?
    /// Engine class namespace: `<classPrefix>anim-*` marker classes and
    /// `<classPrefix>*` keyframes names. Default "fk-".
    public var classPrefix: String?
    /// Consumer utility class stem. Default "animate" → `.animate`,
    /// `.animate-hover`, …
    public var triggerClassPrefix: String?
    /// Consumer custom-property stem. Default "icon-animate" →
    /// `--icon-animate-duration`, `--icon-animate-<name>-duration`, …
    public var customPropertyPrefix: String?
    /// "respect" (default) wraps play rules in
    /// `@media (prefers-reduced-motion: no-preference)`; "ignore" doesn't.
    public var reducedMotion: String?

    public init(
        enabled: Bool? = nil, defaultTrigger: String? = nil, defaultDuration: Double? = nil,
        defaultDelay: Double? = nil, defaultTimingFunction: String? = nil,
        defaultIterationCount: String? = nil, defaultFillMode: String? = nil,
        defaultTransformOrigin: String? = nil, classPrefix: String? = nil,
        triggerClassPrefix: String? = nil, customPropertyPrefix: String? = nil,
        reducedMotion: String? = nil
    ) {
        self.enabled = enabled
        self.defaultTrigger = defaultTrigger
        self.defaultDuration = defaultDuration
        self.defaultDelay = defaultDelay
        self.defaultTimingFunction = defaultTimingFunction
        self.defaultIterationCount = defaultIterationCount
        self.defaultFillMode = defaultFillMode
        self.defaultTransformOrigin = defaultTransformOrigin
        self.classPrefix = classPrefix
        self.triggerClassPrefix = triggerClassPrefix
        self.customPropertyPrefix = customPropertyPrefix
        self.reducedMotion = reducedMotion
    }

    /// Fekthor's fallbacks — also the documented consumer contract
    /// (`fk-` engine classes, `.animate*` utilities, `--icon-animate-*`
    /// custom properties).
    public static let standard = AnimationSettings(
        enabled: true, defaultTrigger: AnimationTrigger.continuous.rawValue,
        defaultDuration: 0.8, defaultDelay: 0, defaultTimingFunction: "ease",
        defaultIterationCount: nil, defaultFillMode: "none",
        defaultTransformOrigin: "center", classPrefix: "fk-",
        triggerClassPrefix: "animate", customPropertyPrefix: "icon-animate",
        reducedMotion: "respect")

    /// Field-wise cascade: icon overrides workspace overrides nothing.
    /// (`standard` is applied per-value at resolution time, not here, so
    /// the result still distinguishes "unset" from "set to the default".)
    public static func resolved(workspace: AnimationSettings?, icon: AnimationSettings?)
        -> AnimationSettings
    {
        var out = workspace ?? AnimationSettings()
        guard let icon else { return out }
        out.enabled = icon.enabled ?? out.enabled
        out.defaultTrigger = icon.defaultTrigger ?? out.defaultTrigger
        out.defaultDuration = icon.defaultDuration ?? out.defaultDuration
        out.defaultDelay = icon.defaultDelay ?? out.defaultDelay
        out.defaultTimingFunction = icon.defaultTimingFunction ?? out.defaultTimingFunction
        out.defaultIterationCount = icon.defaultIterationCount ?? out.defaultIterationCount
        out.defaultFillMode = icon.defaultFillMode ?? out.defaultFillMode
        out.defaultTransformOrigin = icon.defaultTransformOrigin ?? out.defaultTransformOrigin
        out.classPrefix = icon.classPrefix ?? out.classPrefix
        out.triggerClassPrefix = icon.triggerClassPrefix ?? out.triggerClassPrefix
        out.customPropertyPrefix = icon.customPropertyPrefix ?? out.customPropertyPrefix
        out.reducedMotion = icon.reducedMotion ?? out.reducedMotion
        return out
    }
}

/// Validation for defs, bindings, and settings before compilation. Two
/// jobs: keep authored values inside the v1 animatable whitelist, and
/// guarantee the byte-idempotence/injection contract — generated CSS must
/// never contain `<` or `&` (the reader's raw-text escaping would break
/// byte-identity) nor stray `{ } ;` from user strings.
public enum AnimationLint {

    /// v1 animatable whitelist. `display` is deliberately absent
    /// (non-interpolable and removes the element outright); `visibility`
    /// covers blink-style effects via `steps()`.
    public static let animatableProperties: Set<String> = [
        "transform", "opacity", "fill", "stroke", "stroke-width",
        "stroke-dasharray", "stroke-dashoffset", "visibility", "transform-origin",
    ]

    public enum Severity: Equatable, Sendable { case error, warning }

    public struct Issue: Equatable, Sendable {
        public var severity: Severity
        public var message: String
        public init(_ severity: Severity, _ message: String) {
            self.severity = severity
            self.message = message
        }
    }

    /// CSS identifier shape for names, targets, and gate classes.
    public static func isIdentifier(_ s: String) -> Bool {
        guard let first = s.first, first.isLetter else { return false }
        return s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    /// Whether a value string is safe to embed in the generated block.
    public static func isSafeValue(_ s: String) -> Bool {
        !s.contains(where: { "<&{};".contains($0) })
    }

    public static func validate(_ def: AnimationDef) -> [Issue] {
        var out: [Issue] = []
        if !isIdentifier(def.name) {
            out.append(Issue(.error, "animation name '\(def.name)' is not a valid identifier"))
        }
        if def.keyframes.isEmpty {
            out.append(Issue(.error, "animation '\(def.name)' has no keyframes"))
        }
        for frame in def.keyframes {
            if !(0...100).contains(frame.offset) {
                out.append(
                    Issue(.error, "keyframe offset \(frame.offset) outside 0–100 in '\(def.name)'"))
            }
            if let easing = frame.easing, !isSafeValue(easing) {
                out.append(Issue(.error, "unsafe easing value in '\(def.name)'"))
            }
            for (property, value) in frame.declarations {
                if !animatableProperties.contains(property) {
                    out.append(
                        Issue(.error, "property '\(property)' is not animatable in '\(def.name)'"))
                }
                if !isSafeValue(value) {
                    out.append(
                        Issue(.error, "unsafe value for '\(property)' in '\(def.name)'"))
                }
            }
        }
        for value in [
            def.timing?.timingFunction, def.timing?.iterationCount, def.timing?.direction,
            def.timing?.fillMode, def.timing?.transformOrigin,
        ] {
            if let value, !isSafeValue(value) {
                out.append(Issue(.error, "unsafe timing value in '\(def.name)'"))
            }
        }
        return out
    }

    /// Binding checks against its def and the icon's other bindings.
    public static func validate(
        _ binding: AnimationBinding, defs: [AnimationDef], siblings: [AnimationBinding]
    ) -> [Issue] {
        var out: [Issue] = []
        if !isIdentifier(binding.target) {
            out.append(Issue(.error, "binding target '\(binding.target)' is not a valid class"))
        }
        if !defs.contains(where: { $0.name == binding.animation }) {
            out.append(Issue(.error, "binding references unknown animation '\(binding.animation)'"))
        }
        if siblings.contains(where: { $0.target == binding.target }) {
            out.append(
                Issue(
                    .error,
                    "duplicate target '\(binding.target)' — CSS animation-name would drop one"))
        }
        if let raw = binding.trigger {
            guard let trigger = AnimationTrigger.parse(raw) else {
                out.append(Issue(.error, "unknown trigger '\(raw)'"))
                return out
            }
            if case .parentClass(let cls) = trigger, !isIdentifier(cls) {
                out.append(Issue(.error, "gate class '\(cls)' is not a valid class"))
            }
        }
        for value in [
            binding.iterationCount, binding.direction, binding.fillMode,
            binding.timingFunction, binding.transformOrigin,
        ] {
            if let value, !isSafeValue(value) {
                out.append(Issue(.error, "unsafe timing value on binding '\(binding.target)'"))
            }
        }
        return out
    }
}
