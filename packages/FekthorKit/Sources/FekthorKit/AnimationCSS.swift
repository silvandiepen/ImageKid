import Foundation

/// Compiles an icon's animation state (defs + bindings + resolved settings)
/// into the generated `<style id="fekthor-animations">` block.
///
/// The block is DERIVED OUTPUT: regenerated on every save from
/// FileMeta/workfile, never parsed back (SVGReader skips it in `parseCSS`).
/// Byte-idempotence rides the RawNode passthrough contract: the CSS text
/// contains no `<` or `&` (lint-enforced), every emission is fixed-order
/// with `SVGNum` number style, and inner-line indentation is embedded in
/// the string — so `write(read(write(…)))` is byte-identical with no
/// SVGWriter changes.
///
/// Selector strategy (inline-SVG CSS is document-global):
/// - Everything sits in `:where()` → zero specificity, consumers always win.
/// - Workspace defs compile to `@keyframes <prefix><name>` from def content
///   + settings only, so every icon in a set emits byte-identical keyframes
///   and cross-icon collisions on one page are harmless. File-local defs
///   compile icon-scoped (`<prefix><iconSlug>-<name>`).
/// - Triggers gate `animation-name` (never `play-state`): an untriggered
///   element carries no animation at all → static-first by construction.
/// - Play rules wrap in `@media (prefers-reduced-motion: no-preference)`
///   unless the settings say ignore; inert timing longhands live in
///   always-on base rules (they do nothing without a name).
public enum AnimationCSS {

    /// The id of the generated `<style>` element — Fekthor's namespace: a
    /// block carrying it is owned, regenerated, and removed by the engine.
    public static let styleElementID = "fekthor-animations"

    // MARK: - Compile

    /// The block's CSS-and-markup text, or nil when nothing plays (no
    /// bindings, or none referencing a known def). `workspaceDefNames`
    /// decides keyframes namespacing; `iconSlug` scopes file-local defs.
    public static func compile(
        defs: [AnimationDef], bindings: [AnimationBinding], settings: AnimationSettings,
        iconSlug: String?, workspaceDefNames: Set<String>
    ) -> String? {
        let byName = Dictionary(defs.map { ($0.name, $0) }) { first, _ in first }
        let resolved = bindings.compactMap { binding -> ResolvedBinding? in
            guard let def = byName[binding.animation] else { return nil }
            return ResolvedBinding(
                binding: binding, def: def.normalized(),
                compiled: compiledName(
                    def.name, settings: settings, iconSlug: iconSlug,
                    workspaceDefNames: workspaceDefNames),
                settings: settings)
        }
        guard !resolved.isEmpty else { return nil }

        var lines: [String] = []
        lines.append(contentsOf: headerComment(settings))

        // Keyframes for every referenced def, sorted by compiled name.
        var seen = Set<String>()
        for r in resolved.sorted(by: { $0.compiled < $1.compiled })
        where seen.insert(r.compiled).inserted {
            lines.append(contentsOf: keyframesLines(r.def, compiled: r.compiled))
        }

        // Always-on base rules (inert without animation-name), binding order.
        for r in resolved {
            lines.append(contentsOf: baseRuleLines(r))
        }

        // Play rules, reduced-motion-wrapped by default.
        let respectMotion = (settings.reducedMotion ?? "respect") != "ignore"
        var rules: [(selectors: [String], body: [String])] = resolved.map { r in
            (playSelectors(r), playBody(r))
        }
        rules.append(contentsOf: sharedUtilityRules(targets: resolved.map(\.binding.target),
                                                    settings: settings))
        if respectMotion {
            lines.append("@media (prefers-reduced-motion: no-preference) {")
            for rule in rules {
                lines.append(contentsOf: ruleLines(rule, indent: "  "))
            }
            lines.append("}")
        } else {
            for rule in rules {
                lines.append(contentsOf: ruleLines(rule, indent: ""))
            }
        }
        return lines.map { $0.isEmpty ? "" : "    " + $0 }.joined(separator: "\n")
    }

    // MARK: - Document surgery

    /// The document with its generated block replaced by `css` as the FIRST
    /// node (nil removes it). The RawNode carries the full element with the
    /// writer's 2-space closing indent embedded.
    public static func writing(_ css: String?, to doc: GraphicDocument) -> GraphicDocument {
        guard let css else { return removing(from: doc) }
        let xml = "<style id=\"\(styleElementID)\">\n\(css)\n  </style>"
        var out = removing(from: doc)
        out.nodes.insert(.raw(RawNode(id: out.nextNodeID, xml: xml)), at: 0)
        return out
    }

    /// The document without its generated block (foreign styles untouched).
    public static func removing(from doc: GraphicDocument) -> GraphicDocument {
        var out = doc
        out.nodes.removeAll {
            if case .raw(let raw) = $0 { return isAnimXML(raw.xml) }
            return false
        }
        return out
    }

    /// Is this raw fragment the generated block? Tag + id match without a
    /// full parse (same trick as `FileMeta.isMetaXML`).
    public static func isAnimXML(_ xml: String) -> Bool {
        guard xml.hasPrefix("<style") else { return false }
        guard let close = xml.firstIndex(of: ">") else { return false }
        return xml[..<close].contains("id=\"\(styleElementID)\"")
    }

    // MARK: - Resolution

    /// A binding joined with its def and every timing value resolved
    /// through the cascade: binding → def.timing → settings → standard.
    struct ResolvedBinding {
        let binding: AnimationBinding
        let def: AnimationDef
        let compiled: String
        let trigger: AnimationTrigger
        let duration: Double
        let delay: Double
        let timingFunction: String
        let iterationCount: String
        let direction: String
        let fillMode: String
        let transformOrigin: String
        let settings: AnimationSettings

        init(
            binding: AnimationBinding, def: AnimationDef, compiled: String,
            settings: AnimationSettings
        ) {
            let std = AnimationSettings.standard
            self.binding = binding
            self.def = def
            self.compiled = compiled
            self.settings = settings
            let trigger = AnimationTrigger.parse(binding.trigger)
                ?? AnimationTrigger.parse(settings.defaultTrigger)
                ?? .continuous
            self.trigger = trigger
            duration = binding.duration ?? def.timing?.duration
                ?? settings.defaultDuration ?? std.defaultDuration!
            delay = binding.delay ?? def.timing?.delay
                ?? settings.defaultDelay ?? std.defaultDelay!
            timingFunction = binding.timingFunction ?? def.timing?.timingFunction
                ?? settings.defaultTimingFunction ?? std.defaultTimingFunction!
            // Iteration default is trigger-dependent: continuous animations
            // loop, interaction-started ones play once.
            iterationCount = binding.iterationCount ?? def.timing?.iterationCount
                ?? settings.defaultIterationCount
                ?? (trigger == .continuous ? "infinite" : "1")
            direction = binding.direction ?? def.timing?.direction ?? "normal"
            fillMode = binding.fillMode ?? def.timing?.fillMode
                ?? settings.defaultFillMode ?? std.defaultFillMode!
            transformOrigin = binding.transformOrigin ?? def.timing?.transformOrigin
                ?? settings.defaultTransformOrigin ?? std.defaultTransformOrigin!
        }
    }

    static func compiledName(
        _ defName: String, settings: AnimationSettings, iconSlug: String?,
        workspaceDefNames: Set<String>
    ) -> String {
        let prefix = settings.classPrefix ?? AnimationSettings.standard.classPrefix!
        if let iconSlug, !workspaceDefNames.contains(defName) {
            return "\(prefix)\(iconSlug)-\(defName)"
        }
        return prefix + defName
    }

    // MARK: - Emission

    /// Keyframe declaration order: animatables in a fixed canonical order,
    /// unknown extras alphabetical, per-segment easing always last. Public
    /// because editor UIs list properties in the same order.
    public static let declarationOrder: [String] = [
        "transform", "transform-origin", "opacity", "fill", "stroke",
        "stroke-width", "stroke-dasharray", "stroke-dashoffset", "visibility",
    ]

    private static func headerComment(_ settings: AnimationSettings) -> [String] {
        let std = AnimationSettings.standard
        let util = settings.triggerClassPrefix ?? std.triggerClassPrefix!
        let cp = settings.customPropertyPrefix ?? std.customPropertyPrefix!
        let utilities = ["", "-once", "-infinite", "-hover", "-on-parent-hover", "-focus",
                         "-active"].map { ".\(util)\($0)" }.joined(separator: " ")
        return [
            "/* Generated by Fekthor — regenerated on save; do not edit.",
            "   Consumer API: \(utilities)",
            "   on the svg or an ancestor; tune with --\(cp)-{duration,timing,delay,iteration}",
            "   (per animation: --\(cp)-name-duration, …). */",
        ]
    }

    private static func keyframesLines(_ def: AnimationDef, compiled: String) -> [String] {
        var out = ["@keyframes \(compiled) {"]
        for frame in def.keyframes {
            var decls: [String] = []
            let known = declarationOrder.filter { frame.declarations[$0] != nil }
            let extras = frame.declarations.keys
                .filter { !declarationOrder.contains($0) }.sorted()
            for property in known + extras {
                decls.append("\(property): \(frame.declarations[property]!);")
            }
            if let easing = frame.easing {
                decls.append("animation-timing-function: \(easing);")
            }
            out.append("  \(SVGNum.text(frame.offset))% { \(decls.joined(separator: " ")) }")
        }
        out.append("}")
        return out
    }

    private static func baseRuleLines(_ r: ResolvedBinding) -> [String] {
        let std = AnimationSettings.standard
        let cp = r.settings.customPropertyPrefix ?? std.customPropertyPrefix!
        let name = r.def.name
        let duration = timeText(r.duration)
        let delay = timeText(r.delay)
        var out = [":where(.\(r.binding.target)) {"]
        out.append(
            "  animation-duration: var(--\(cp)-\(name)-duration, "
                + "var(--\(cp)-duration, \(duration)));")
        out.append(
            "  animation-timing-function: var(--\(cp)-\(name)-timing, "
                + "var(--\(cp)-timing, \(r.timingFunction)));")
        out.append(
            "  animation-delay: var(--\(cp)-\(name)-delay, "
                + "var(--\(cp)-delay, \(delay)));")
        out.append(
            "  animation-iteration-count: var(--\(cp)-\(name)-iteration, "
                + "var(--\(cp)-iteration, \(r.iterationCount)));")
        out.append("  animation-direction: \(r.direction);")
        out.append("  animation-fill-mode: \(r.fillMode);")
        if r.def.animatesTransform {
            out.append("  transform-origin: \(r.transformOrigin);")
            out.append("  transform-box: fill-box;")
        }
        out.append("}")
        return out
    }

    /// The full selector group that starts this binding: the authored
    /// trigger's selectors plus every consumer utility (utilities force-play
    /// any binding, whatever its authored trigger). Each `:where` group is
    /// one line.
    private static func playSelectors(_ r: ResolvedBinding) -> [String] {
        let t = r.binding.target
        let util = r.settings.triggerClassPrefix
            ?? AnimationSettings.standard.triggerClassPrefix!
        var out: [String] = []
        switch r.trigger {
        case .continuous:
            out.append(":where(.\(t))")
        case .hover:
            out.append(":where(svg:hover .\(t), svg.\(t):hover)")
        case .focus:
            out.append(
                ":where(svg:focus .\(t), svg:focus-visible .\(t), "
                    + "svg.\(t):focus, svg.\(t):focus-visible)")
        case .active:
            out.append(":where(svg:active .\(t), svg.\(t):active)")
        case .parentClass(let gate):
            out.append(":where(.\(gate) .\(t), .\(gate).\(t))")
        case .manual:
            break
        }
        out.append(":where(.\(util) .\(t), svg.\(util).\(t))")
        out.append(":where(.\(util)-once .\(t), svg.\(util)-once.\(t))")
        out.append(":where(.\(util)-infinite .\(t), svg.\(util)-infinite.\(t))")
        out.append(":where(.\(util)-hover:hover .\(t), svg.\(util)-hover:hover.\(t))")
        out.append(":where(.\(util)-on-parent-hover:hover .\(t))")
        out.append(
            ":where(.\(util)-focus:focus-within .\(t), svg.\(util)-focus:focus-within.\(t))")
        out.append(":where(.\(util)-active:active .\(t), svg.\(util)-active:active.\(t))")
        return out
    }

    private static func playBody(_ r: ResolvedBinding) -> [String] {
        var out = ["animation-name: \(r.compiled);"]
        if r.def.normalizesPathLength == true {
            // Draw setup: the dash covers the whole (normalized) length, so
            // the un-animated render stays a solid stroke.
            out.append("stroke-dasharray: 100 100;")
        }
        return out
    }

    /// `.animate-once` / `.animate-infinite` parameter overrides, applied
    /// across every target in the icon.
    private static func sharedUtilityRules(
        targets: [String], settings: AnimationSettings
    ) -> [(selectors: [String], body: [String])] {
        let util = settings.triggerClassPrefix
            ?? AnimationSettings.standard.triggerClassPrefix!
        let sorted = targets.sorted()
        func group(_ suffix: String) -> [String] {
            let ancestor = sorted.map { ".\(util)\(suffix) .\($0)" }
            let root = sorted.map { "svg.\(util)\(suffix).\($0)" }
            return [":where(" + (ancestor + root).joined(separator: ", ") + ")"]
        }
        return [
            (group("-once"), ["animation-iteration-count: 1;", "animation-fill-mode: forwards;"]),
            (group("-infinite"), ["animation-iteration-count: infinite;"]),
        ]
    }

    private static func ruleLines(
        _ rule: (selectors: [String], body: [String]), indent: String
    ) -> [String] {
        var out: [String] = []
        for (i, selector) in rule.selectors.enumerated() {
            out.append(indent + selector + (i == rule.selectors.count - 1 ? " {" : ","))
        }
        for declaration in rule.body {
            out.append(indent + "  " + declaration)
        }
        out.append(indent + "}")
        return out
    }

    /// Seconds in corpus number style: `.8s`, `0s`, `1.5s`.
    static func timeText(_ v: Double) -> String {
        SVGNum.text(v) + "s"
    }
}
