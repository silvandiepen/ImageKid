import Foundation

/// Binding mechanics for animations, mirroring `NamedStyles`: marker-class
/// bindings on nodes (or the svg root for whole-icon animations), resolved
/// def copies + binding records in FileMeta, and the save-time style-block
/// hook. Pure functions; callers wrap them in their own undo.
public enum AnimationEngine {

    /// The marker class a def binds with by default: `fk-anim-spin`.
    public static func defaultTarget(for def: AnimationDef, settings: AnimationSettings)
        -> String
    {
        let prefix = settings.classPrefix ?? AnimationSettings.standard.classPrefix!
        return "\(prefix)anim-\(def.name)"
    }

    /// Bind `def` to `nodeIDs` — or to the WHOLE ICON when `nodeIDs` is
    /// empty (marker class on the `<svg>` root; every top-level node
    /// animates). Re-binding the same def adds nodes to the existing
    /// binding (one target class per def in v1); a non-nil `trigger`
    /// updates the binding's trigger. The def's resolved copy lands in
    /// FileMeta so the SVG stays self-contained.
    public static func bind(
        _ def: AnimationDef, trigger: String? = nil, toNodes nodeIDs: [Int],
        in doc: GraphicDocument, settings: AnimationSettings
    ) -> GraphicDocument {
        var out = doc
        let target = defaultTarget(for: def, settings: settings)
        let wantsPathLength = def.normalizesPathLength == true
        if nodeIDs.isEmpty {
            out.rootAttributes = addingRootClass(out.rootAttributes, token: target)
            if wantsPathLength {
                out.nodes = settingPathLength(out.nodes, ids: nil, on: true)
            }
        } else {
            out.nodes = addingClass(
                out.nodes, ids: Set(nodeIDs), token: target, pathLength: wantsPathLength)
        }

        var meta = FileMeta.read(from: out) ?? FileMeta.Meta()
        var defs = meta.animations ?? []
        if let i = defs.firstIndex(where: { $0.name == def.name }) {
            defs[i] = def
        } else {
            defs.append(def)
        }
        meta.animations = defs
        var bindings = meta.animationBindings ?? []
        if let i = bindings.firstIndex(where: { $0.target == target }) {
            if let trigger { bindings[i].trigger = trigger }
        } else {
            bindings.append(AnimationBinding(animation: def.name, target: target, trigger: trigger))
        }
        meta.animationBindings = bindings
        return FileMeta.writing(meta, to: out)
    }

    /// Remove the binding `target`: the record, its marker classes (nodes
    /// and root), its def copy when no other binding references it, and the
    /// `pathLength="100"` markers a draw def added.
    public static func unbind(target: String, in doc: GraphicDocument) -> GraphicDocument {
        var out = doc
        var meta = FileMeta.read(from: out) ?? FileMeta.Meta()
        let removed = meta.animationBindings?.first { $0.target == target }
        meta.animationBindings = (meta.animationBindings ?? []).filter { $0.target != target }
        if meta.animationBindings?.isEmpty == true { meta.animationBindings = nil }
        if let removed,
            meta.animationBindings?.contains(where: { $0.animation == removed.animation }) != true
        {
            let def = meta.animations?.first { $0.name == removed.animation }
            meta.animations = (meta.animations ?? []).filter { $0.name != removed.animation }
            if meta.animations?.isEmpty == true { meta.animations = nil }
            if def?.normalizesPathLength == true {
                // Strip the pathLength markers from the nodes losing this class
                // (and everywhere for whole-icon draw bindings).
                let ids = Set(boundNodeIDs(in: out, target: target))
                out.nodes = settingPathLength(out.nodes, ids: ids.isEmpty ? nil : ids, on: false)
            }
        }
        out.rootAttributes = removingRootClass(out.rootAttributes, token: target)
        var changed = false
        out.nodes = ClassStrip.strip(out.nodes, token: target, changed: &changed)
        return FileMeta.writing(meta, to: out)
    }

    /// IDs of nodes carrying the binding's marker class (document order).
    /// Whole-icon bindings (root class) return [] — callers treat that as
    /// "every top-level node".
    public static func boundNodeIDs(in doc: GraphicDocument, target: String) -> [Int] {
        NamedStyles.boundNodes(in: doc, styleName: target)
    }

    /// Whether the binding's class sits on the `<svg>` root (whole icon).
    public static func isWholeIcon(_ target: String, in doc: GraphicDocument) -> Bool {
        rootClassList(doc.rootAttributes).contains(target)
    }

    // MARK: - Class plumbing

    static func rootClassList(_ attributes: [XMLAttr]) -> [String] {
        attributes.first { $0.name == "class" }?
            .value.split(separator: " ").map(String.init) ?? []
    }

    static func addingRootClass(_ attributes: [XMLAttr], token: String) -> [XMLAttr] {
        var classes = rootClassList(attributes)
        guard !classes.contains(token) else { return attributes }
        classes.append(token)
        return settingRootClasses(attributes, classes)
    }

    static func removingRootClass(_ attributes: [XMLAttr], token: String) -> [XMLAttr] {
        let classes = rootClassList(attributes).filter { $0 != token }
        return settingRootClasses(attributes, classes)
    }

    private static func settingRootClasses(_ attributes: [XMLAttr], _ classes: [String])
        -> [XMLAttr]
    {
        var out = attributes
        if classes.isEmpty {
            out.removeAll { $0.name == "class" }
            return out
        }
        let value = classes.joined(separator: " ")
        if let i = out.firstIndex(where: { $0.name == "class" }) {
            out[i].value = value
        } else {
            out.append(XMLAttr(name: "class", value: value))
        }
        return out
    }

    private static func addingClass(
        _ nodes: [GraphicNode], ids: Set<Int>, token: String, pathLength: Bool
    ) -> [GraphicNode] {
        nodes.map { node in
            switch node {
            case .raw:
                return node
            case .shape(var s):
                if ids.contains(s.id) {
                    var classes = NamedStyles.classList(of: s.attributes)
                    if !classes.contains(token) {
                        classes.append(token)
                        s.attributes = NamedStyles.settingClassList(s.attributes, to: classes)
                    }
                    if pathLength { s.attributes = settingPathLengthAttr(s.attributes, on: true) }
                }
                return .shape(s)
            case .group(var g):
                if ids.contains(g.id) {
                    var classes = NamedStyles.classList(of: g.attributes)
                    if !classes.contains(token) {
                        classes.append(token)
                        g.attributes = NamedStyles.settingClassList(g.attributes, to: classes)
                    }
                    // A group binding normalizes every descendant shape.
                    if pathLength {
                        g.children = settingPathLength(g.children, ids: nil, on: true)
                    }
                }
                g.children = addingClass(g.children, ids: ids, token: token, pathLength: pathLength)
                return .group(g)
            }
        }
    }

    /// Set/remove `pathLength="100"` on shapes — all of them (`ids` nil) or
    /// a specific set. Only the exact engine-written value is ever removed.
    private static func settingPathLength(
        _ nodes: [GraphicNode], ids: Set<Int>?, on: Bool
    ) -> [GraphicNode] {
        nodes.map { node in
            switch node {
            case .raw:
                return node
            case .shape(var s):
                if ids?.contains(s.id) ?? true {
                    s.attributes = settingPathLengthAttr(s.attributes, on: on)
                }
                return .shape(s)
            case .group(var g):
                g.children = settingPathLength(g.children, ids: ids, on: on)
                return .group(g)
            }
        }
    }

    private static func settingPathLengthAttr(_ attributes: NodeAttributes, on: Bool)
        -> NodeAttributes
    {
        var out = attributes
        if on {
            if !out.extras.contains(where: { $0.name == "pathLength" }) {
                out.extras.append(XMLAttr(name: "pathLength", value: "100"))
            }
        } else {
            out.extras.removeAll { $0.name == "pathLength" && $0.value == "100" }
        }
        return out
    }

    /// Class-token removal across the tree (shapes and groups).
    enum ClassStrip {
        static func strip(_ nodes: [GraphicNode], token: String, changed: inout Bool)
            -> [GraphicNode]
        {
            nodes.map { node in
                switch node {
                case .raw:
                    return node
                case .shape(var s):
                    let kept = NamedStyles.classList(of: s.attributes).filter { $0 != token }
                    if kept.count != NamedStyles.classList(of: s.attributes).count {
                        s.attributes = NamedStyles.settingClassList(s.attributes, to: kept)
                        changed = true
                    }
                    return .shape(s)
                case .group(var g):
                    let kept = NamedStyles.classList(of: g.attributes).filter { $0 != token }
                    if kept.count != NamedStyles.classList(of: g.attributes).count {
                        g.attributes = NamedStyles.settingClassList(g.attributes, to: kept)
                        changed = true
                    }
                    g.children = strip(g.children, token: token, changed: &changed)
                    return .group(g)
                }
            }
        }
    }

    /// The one-liner save hook: recompile the generated style block from
    /// the document's FileMeta (+ workspace context), or remove it when
    /// animations are disabled or nothing is bound. Deterministic, so
    /// re-saves stay byte-identical.
    ///
    /// - `workspace`: the open workfile, if any — supplies workspace
    ///   defaults, and def names decide keyframes namespacing (workspace
    ///   defs compile globally, file-local ones icon-scoped).
    /// - `iconSlug`: sanitized file base name used to scope file-local
    ///   keyframes names; nil (lone SVG) compiles all names globally.
    public static func applyingStyleBlock(
        to doc: GraphicDocument, workspace: Workfile?, iconSlug: String? = nil
    ) -> GraphicDocument {
        let meta = FileMeta.read(from: doc)
        let settings = AnimationSettings.resolved(
            workspace: workspace?.settings?.animations, icon: meta?.animationSettings)
        let enabled = meta?.animationsEnabled ?? settings.enabled ?? true
        guard enabled, let bindings = meta?.animationBindings, !bindings.isEmpty else {
            return AnimationCSS.removing(from: doc)
        }
        // Defs: the icon's resolved copies win; the workspace fills gaps
        // (binding present but its copy not refreshed yet).
        var defs = meta?.animations ?? []
        var have = Set(defs.map(\.name))
        for def in workspace?.animations ?? [] where have.insert(def.name).inserted {
            defs.append(def)
        }
        let css = AnimationCSS.compile(
            defs: defs, bindings: bindings, settings: settings, iconSlug: iconSlug,
            workspaceDefNames: Set((workspace?.animations ?? []).map(\.name)))
        return AnimationCSS.writing(css, to: doc)
    }
}
