import CoreGraphics
import FekthorKit
import SwiftUI

/// In-editor animation playback: a clock (play/pause/scrub, looped on the
/// icon's scene length) plus per-node render overrides computed by the
/// engine's `AnimationInterpolator`. Preview NEVER touches the document —
/// no dirty, no undo, no generation churn; the canvas simply renders the
/// same tree with per-frame deltas.
@MainActor
final class AnimationPreviewController: ObservableObject {
    @Published var isPlaying = false
    @Published var loop = true
    /// The authoritative time while paused (scrub position). While playing,
    /// time derives from the anchor so no per-frame publishes happen.
    @Published var pausedTime: Double = 0
    /// Simulated consumer context (hover/focus/active/gate chips).
    @Published var state = AnimationPreviewState()

    /// Workspace animation defaults; the editor view refreshes this.
    var workspaceSettings: AnimationSettings?

    private var anchor: Date?

    // MARK: - Transport

    func play() {
        guard !isPlaying else { return }
        anchor = Date()
        isPlaying = true
    }

    func pause() {
        guard isPlaying else { return }
        pausedTime = time(at: Date())
        anchor = nil
        isPlaying = false
    }

    func toggle() { isPlaying ? pause() : play() }

    func stop() {
        pausedTime = 0
        anchor = nil
        isPlaying = false
    }

    func scrub(to t: Double) {
        pausedTime = max(0, t)
        anchor = nil
        isPlaying = false
    }

    /// The preview clock at `date` — pure while playing (no publishes), the
    /// scrub position while paused. Loops on the scene length.
    func time(at date: Date) -> Double {
        guard isPlaying, let anchor else { return pausedTime }
        var t = pausedTime + date.timeIntervalSince(anchor)
        if loop, sceneLength > 0 {
            t = t.truncatingRemainder(dividingBy: sceneLength)
        }
        return t
    }

    // MARK: - Scene snapshot (cached per document generation)

    /// Everything the interpolator needs, derived once per `generation`:
    /// the icon's defs/bindings/settings, target-class → node-id map, and
    /// per-node contexts (bbox, base style, path length).
    private struct SceneSnapshot {
        var defs: [AnimationDef] = []
        var bindings: [AnimationBinding] = []
        var settings = AnimationSettings()
        var targets: [String: [Int]] = [:]
        var contexts: [Int: AnimationTargetContext] = [:]
        var length: Double = 0
        var isEmpty: Bool { bindings.isEmpty || targets.isEmpty }
    }

    private var cachedGeneration = Int.min
    private var cachedDocumentID = ObjectIdentifier(EditorSession.self)
    private var snapshot = SceneSnapshot()

    /// The scene length the transport loops on (max track end, 3 s floor —
    /// a hover-draw of .6 s still gets a readable loop).
    private(set) var sceneLength: Double = 3

    func hasScene(_ session: EditorSession) -> Bool {
        refresh(session)
        return !snapshot.isEmpty
    }

    /// Per-node render overrides at `time` for the current document state.
    func overrides(for session: EditorSession, at time: Double) -> [Int: AnimatedOverride] {
        refresh(session)
        guard !snapshot.isEmpty else { return [:] }
        var out: [Int: AnimatedOverride] = [:]
        for binding in snapshot.bindings {
            guard let ids = snapshot.targets[binding.target] else { continue }
            for id in ids {
                guard let ctx = snapshot.contexts[id] else { continue }
                let resolved = AnimationInterpolator.resolve(
                    defs: snapshot.defs, bindings: [binding], settings: snapshot.settings,
                    time: time, state: state
                ) { _ in ctx }
                if let override = resolved[binding.target] {
                    out[id] = override
                }
            }
        }
        return out
    }

    private func refresh(_ session: EditorSession) {
        let docID = ObjectIdentifier(session)
        guard session.generation != cachedGeneration || docID != cachedDocumentID else {
            return
        }
        cachedGeneration = session.generation
        cachedDocumentID = docID
        snapshot = buildSnapshot(session.document)
        sceneLength = max(snapshot.length, 3)
    }

    private func buildSnapshot(_ doc: GraphicDocument) -> SceneSnapshot {
        var out = SceneSnapshot()
        guard let meta = FileMeta.read(from: doc),
            let bindings = meta.animationBindings, !bindings.isEmpty
        else { return out }
        out.bindings = bindings
        out.defs = meta.animations ?? []
        out.settings = AnimationSettings.resolved(
            workspace: workspaceSettings, icon: meta.animationSettings)
        let defsByName = Dictionary(out.defs.map { ($0.name, $0) }) { first, _ in first }

        // Class walk: node id → class tokens, plus per-node context data.
        var members: [String: [Int]] = [:]
        var topLevel: [Int] = []
        func walk(_ nodes: [GraphicNode], depth: Int) {
            for node in nodes {
                switch node {
                case .raw:
                    continue
                case .shape(let s):
                    if depth == 0 { topLevel.append(s.id) }
                    for token in ClassTokens.list(s.attributes) {
                        members[token, default: []].append(s.id)
                    }
                case .group(let g):
                    if depth == 0 { topLevel.append(g.id) }
                    for token in ClassTokens.list(g.attributes) {
                        members[token, default: []].append(g.id)
                    }
                    walk(g.children, depth: depth + 1)
                }
            }
        }
        walk(doc.nodes, depth: 0)

        // Whole-icon bindings: the marker class sits on the <svg> root and
        // means "everything animates" — mapped to every top-level node.
        let rootClasses = Set(
            doc.rootAttributes.first { $0.name == "class" }?
                .value.split(separator: " ").map(String.init) ?? [])

        var length = 0.0
        for binding in bindings {
            guard let def = defsByName[binding.animation] else { continue }
            let ids = rootClasses.contains(binding.target)
                ? topLevel : (members[binding.target] ?? [])
            guard !ids.isEmpty else { continue }
            out.targets[binding.target] = ids
            let wantsPathLength = def.normalizesPathLength == true
            for id in ids where out.contexts[id] == nil {
                out.contexts[id] = context(
                    for: id, in: doc, includePathLength: wantsPathLength)
            }
            let timing = AnimationInterpolator.timing(
                of: binding, def: def, settings: out.settings)
            let end = timing.delay
                + timing.duration * (timing.iterations.isFinite ? timing.iterations : 1)
            length = max(length, end)
        }
        out.length = length
        return out
    }

    /// Bbox, base style, and (for draw defs) path length of one node.
    /// Bounds are the element's own untransformed geometry (CSS
    /// `transform-box: fill-box`); group bounds union their descendants.
    private func context(
        for id: Int, in doc: GraphicDocument, includePathLength: Bool
    ) -> AnimationTargetContext? {
        guard let node = findNode(id, in: doc.nodes) else { return nil }
        var box = CGRect.null
        var style = Style()
        var pathLength = 0.0

        func accumulate(_ shape: ShapeNode) {
            let path = CGPathBuilder.path(for: shape.kind)
            box = box.union(path.boundingBoxOfPath)
            if includePathLength {
                pathLength += PathSampler.length(of: path)
            }
        }

        switch node {
        case .shape(let s):
            accumulate(s)
            style = s.renderStyle
        case .group(let g):
            style = g.renderStyle
            func walk(_ nodes: [GraphicNode]) {
                for child in nodes {
                    switch child {
                    case .shape(let s): accumulate(s)
                    case .group(let inner): walk(inner.children)
                    case .raw: break
                    }
                }
            }
            walk(g.children)
        case .raw:
            return nil
        }
        guard !box.isNull else { return nil }

        return AnimationTargetContext(
            bounds: ViewBox(
                minX: box.minX, minY: box.minY, width: box.width, height: box.height),
            baseOpacity: style.opacity ?? 1,
            baseFill: style.fill,
            baseStroke: style.stroke,
            baseStrokeWidth: style.strokeWidth ?? 1,
            baseStrokeDashoffset: 0,
            pathLength: includePathLength && pathLength > 0 ? pathLength : nil)
    }

    private func findNode(_ id: Int, in nodes: [GraphicNode]) -> GraphicNode? {
        for node in nodes {
            switch node {
            case .raw: continue
            case .shape(let s):
                if s.id == id { return node }
            case .group(let g):
                if g.id == id { return node }
                if let hit = findNode(id, in: g.children) { return hit }
            }
        }
        return nil
    }
}

/// Geometric length of a CGPath by flattening: lines exactly, quads/cubics
/// sampled (16 steps — plenty for dash preview on icon-scale geometry).
enum PathSampler {
    static func length(of path: CGPath) -> Double {
        var total = 0.0
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        path.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint:
                current = e.points[0]
                subpathStart = current
            case .addLineToPoint:
                total += hypot(e.points[0].x - current.x, e.points[0].y - current.y)
                current = e.points[0]
            case .addQuadCurveToPoint:
                total += sampled(from: current, points: [e.points[0], e.points[1]])
                current = e.points[1]
            case .addCurveToPoint:
                total += sampled(
                    from: current, points: [e.points[0], e.points[1], e.points[2]])
                current = e.points[2]
            case .closeSubpath:
                total += hypot(subpathStart.x - current.x, subpathStart.y - current.y)
                current = subpathStart
            @unknown default:
                break
            }
        }
        return total
    }

    private static func sampled(from start: CGPoint, points: [CGPoint]) -> Double {
        func at(_ t: CGFloat) -> CGPoint {
            let u = 1 - t
            if points.count == 2 {
                let x = u * u * start.x + 2 * u * t * points[0].x + t * t * points[1].x
                let y = u * u * start.y + 2 * u * t * points[0].y + t * t * points[1].y
                return CGPoint(x: x, y: y)
            }
            let x =
                u * u * u * start.x + 3 * u * u * t * points[0].x
                + 3 * u * t * t * points[1].x + t * t * t * points[2].x
            let y =
                u * u * u * start.y + 3 * u * u * t * points[0].y
                + 3 * u * t * t * points[1].y + t * t * t * points[2].y
            return CGPoint(x: x, y: y)
        }
        var total = 0.0
        var prev = start
        for i in 1...16 {
            let p = at(CGFloat(i) / 16)
            total += hypot(p.x - prev.x, p.y - prev.y)
            prev = p
        }
        return total
    }
}
