import FekthorKit
import SwiftUI

/// The bottom animation timeline drawer (DAW-style): a resizable strip
/// under the canvas with a transport bar, one track per binding (name,
/// asset, trigger), and a time ruler with delay/duration spans, keyframe
/// diamonds and a scrubbable playhead. The floating palettes stay 240 pt
/// wide — a ruler needs the window's width, hence a drawer, not a palette.
///
/// Editing model:
/// - Diamonds drag on a 1% grid (⇧ = free). A union diamond (collapsed
///   track) moves the whole keyframe; expanded per-property lanes move one
///   property between frames.
/// - Click a diamond → popover: values, per-segment easing (presets +
///   cubic-bezier pad), delete. Double-click a lane adds a keyframe there.
/// - The span's edges drag the binding's delay/duration overrides.
/// - Record (●): style edits on bound elements become keyframes at the
///   playhead instead of base edits (`EditorSession.recordStyleEdit`).
/// All edits land in FileMeta via `editScene`-style session calls, so undo
/// covers them; workspace defs fork to file-local copies on first edit.
struct EditorTimelineDrawer: View {
    @ObservedObject var session: EditorSession
    @ObservedObject var preview: AnimationPreviewController
    @ObservedObject private var panels = EditorPanelsState.shared

    /// Horizontal zoom. Persisted per session only — like the canvas zoom,
    /// it is working state, not document state.
    @State private var pixelsPerSecond: CGFloat = 120
    /// Tracks disclosed into per-property lanes.
    @State private var expanded: Set<String> = []
    /// In-flight diamond drag: which keyframe left from where.
    @State private var diamondDrag: DiamondDrag? = nil
    /// The diamond whose popover editor is open.
    @State private var editingKeyframe: KeyframeRef? = nil
    /// In-flight span-edge drag (delay or duration override).
    @State private var spanDrag: SpanDrag? = nil

    private struct DiamondDrag: Equatable {
        var target: String
        var property: String?
        var from: Double
    }

    struct KeyframeRef: Equatable {
        var target: String
        var property: String?
        var offset: Double
    }

    private struct SpanDrag: Equatable {
        var target: String
        var leadingEdge: Bool
    }

    private let trackColumnWidth: CGFloat = 200
    private let rulerHeight: CGFloat = 22
    private let rowHeight: CGFloat = 30
    private let laneSpace = "timeline.lanes"
    private let trackTints: [Color] = [
        .blue, .orange, .green, .purple, .pink, .teal, .red, .indigo,
    ]

    private var bindings: [AnimationBinding] { session.animationBindings }

    /// The visible span: every track's end (one iteration; ∞ shows one
    /// cycle) plus breathing room, at least the loop length.
    private var span: Double {
        max(preview.sceneLength, 1) + 0.5
    }

    var body: some View {
        VStack(spacing: 0) {
            resizeGrip
            transport
            Divider()
            if bindings.isEmpty {
                emptyState
            } else {
                tracks
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        // A real container element: without `.contain`, the identifier
        // would attach to the first child button and hijack its identity.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeline.drawer")
    }

    // MARK: - Rows (shared by the left column and the lanes)

    private enum Row: Identifiable {
        case track(AnimationBinding, Color)
        case property(AnimationBinding, String, Color)

        var id: String {
            switch self {
            case .track(let b, _): return b.target
            case .property(let b, let p, _): return "\(b.target)|\(p)"
            }
        }
    }

    private var rows: [Row] {
        var out: [Row] = []
        for (index, binding) in bindings.enumerated() {
            let tint = trackTints[index % trackTints.count]
            out.append(.track(binding, tint))
            if expanded.contains(binding.target) {
                for property in animatedProperties(binding) {
                    out.append(.property(binding, property, tint))
                }
            }
        }
        return out
    }

    private func animatedProperties(_ binding: AnimationBinding) -> [String] {
        guard let def = session.animationDef(named: binding.animation) else { return [] }
        var seen = Set<String>()
        for frame in def.keyframes { seen.formUnion(frame.declarations.keys) }
        let ordered = AnimationCSS.declarationOrder.filter(seen.contains)
        return ordered + seen.subtracting(ordered).sorted()
    }

    // MARK: - Chrome

    /// Drag the drawer's top edge to resize (140…480 pt).
    private var resizeGrip: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 7)
            .overlay(
                Capsule()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 44, height: 4))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let proposed = panels.timelineHeight - value.translation.height
                        panels.timelineHeight = min(480, max(140, proposed))
                    }
            )
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() }
            }
    }

    private var transport: some View {
        HStack(spacing: 10) {
            Button {
                preview.toggle()
            } label: {
                Image(systemName: preview.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 16)
            }
            .buttonStyle(.bordered)
            .disabled(bindings.isEmpty)
            .keyboardShortcut(.space, modifiers: [])
            .help(preview.isPlaying ? "Pause (Space)" : "Play (Space)")
            .accessibilityIdentifier("timeline.play")

            Button {
                preview.stop()
            } label: {
                Image(systemName: "backward.end.fill")
            }
            .buttonStyle(.bordered)
            .disabled(bindings.isEmpty)
            .help("Stop and rewind")

            Toggle(isOn: $preview.loop) { Image(systemName: "repeat") }
                .toggleStyle(.button)
                .help("Loop")

            Toggle(isOn: $session.animationRecordArmed) {
                Image(systemName: "record.circle")
                    .foregroundStyle(session.animationRecordArmed ? .red : .secondary)
            }
            .toggleStyle(.button)
            .disabled(bindings.isEmpty)
            .help("Record: style edits on bound elements become keyframes at the playhead")
            .accessibilityIdentifier("timeline.record")

            timeReadout

            Divider().frame(height: 16)

            Toggle("Hover", isOn: $preview.state.hover).toggleStyle(.button)
            Toggle("Focus", isOn: $preview.state.focus).toggleStyle(.button)
            Toggle("Active", isOn: $preview.state.active).toggleStyle(.button)
            Toggle("Force", isOn: $preview.state.forcePlay)
                .toggleStyle(.button)
                .help("Play every binding regardless of trigger (the .animate utility)")

            Spacer()

            Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
            Slider(value: $pixelsPerSecond, in: 40...400)
                .frame(width: 110)
                .help("Timeline zoom")
            Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)

            Button {
                panels.timelineShown = false
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Close the timeline")
        }
        .controlSize(.small)
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    /// Live readout while playing — its own clock so the track rows never
    /// re-render per frame.
    private var timeReadout: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !preview.isPlaying)) { tl in
            let t = preview.time(at: tl.date)
            Text(String(format: "%.2f s", t))
                .font(.system(.caption, design: .monospaced))
                .frame(width: 52, alignment: .trailing)
                .accessibilityIdentifier("timeline.readout")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Text("No animations on this icon yet.")
                .foregroundStyle(.secondary)
            addTrackMenu
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .font(.callout)
    }

    // MARK: - Tracks

    private var tracks: some View {
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                trackColumn
                Divider()
                ScrollView(.horizontal) {
                    lanes
                }
            }
        }
    }

    private var trackColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                addTrackMenu
                Spacer()
            }
            .frame(height: rulerHeight)
            .padding(.horizontal, 8)
            ForEach(rows) { row in
                switch row {
                case .track(let binding, let tint):
                    trackHeader(binding, tint: tint)
                case .property(_, let property, let tint):
                    propertyHeader(property, tint: tint)
                }
            }
        }
        .frame(width: trackColumnWidth, alignment: .leading)
    }

    private var addTrackMenu: some View {
        Menu {
            ForEach(session.availableAnimationDefs, id: \.name) { def in
                Button(def.name) { session.applyAnimation(def) }
            }
        } label: {
            Label(
                session.selection.isEmpty ? "Animate icon" : "Animate selection",
                systemImage: "plus")
        }
        .controlSize(.small)
        .font(.caption)
        .fixedSize()
        .accessibilityIdentifier("timeline.addTrack")
    }

    private func trackHeader(_ binding: AnimationBinding, tint: Color) -> some View {
        let bound = AnimationEngine.boundNodeIDs(in: session.document, target: binding.target)
        let selected = !Set(bound).isDisjoint(with: session.selection)
        let isExpanded = expanded.contains(binding.target)
        return HStack(spacing: 6) {
            Button {
                if isExpanded {
                    expanded.remove(binding.target)
                } else {
                    expanded.insert(binding.target)
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.borderless)
            Circle().fill(tint).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(trackName(binding, bound: bound))
                    .font(.caption)
                    .lineLimit(1)
                Text("\(binding.animation) · \(triggerLabel(binding))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                session.removeAnimation(target: binding.target)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .controlSize(.mini)
            .help("Remove this animation")
        }
        .padding(.horizontal, 8)
        .frame(height: rowHeight)
        .background(selected ? Color.accentColor.opacity(0.12) : .clear)
        .contentShape(Rectangle())
        .onTapGesture {
            // Track click ↔ canvas selection sync.
            if !bound.isEmpty { session.selection = Set(bound) }
        }
    }

    private func propertyHeader(_ property: String, tint: Color) -> some View {
        HStack {
            Text(property)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.leading, 36)
        .padding(.trailing, 8)
        .frame(height: rowHeight * 0.75)
    }

    private func trackName(_ binding: AnimationBinding, bound: [Int]) -> String {
        if AnimationEngine.isWholeIcon(binding.target, in: session.document) {
            return "Icon"
        }
        guard let first = bound.first, let node = session.document.firstNode(id: first)
        else {
            return binding.target
        }
        let attributes: NodeAttributes
        let kind: String
        switch node {
        case .shape(let s):
            attributes = s.attributes
            kind = shapeKindName(s.kind)
        case .group(let g):
            attributes = g.attributes
            kind = "group"
        case .raw:
            return binding.target
        }
        let name = attributes.extras.first { $0.name == "data-name" }?.value
            ?? attributes.svgID ?? kind
        return bound.count > 1 ? "\(name) +\(bound.count - 1)" : name
    }

    private func shapeKindName(_ kind: ShapeKind) -> String {
        switch kind {
        case .path: return "path"
        case .line: return "line"
        case .polyline: return "polyline"
        case .polygon: return "polygon"
        case .rect: return "rect"
        case .circle: return "circle"
        case .ellipse: return "ellipse"
        }
    }

    private func triggerLabel(_ binding: AnimationBinding) -> String {
        let trigger = AnimationTrigger.parse(binding.trigger)
            ?? AnimationTrigger.parse(session.resolvedAnimationSettings.defaultTrigger)
            ?? .continuous
        switch trigger {
        case .continuous: return "continuous"
        case .hover: return "hover"
        case .focus: return "focus"
        case .active: return "active"
        case .parentClass(let cls): return ".\(cls)"
        case .manual: return "manual"
        }
    }

    // MARK: - Lanes (ruler + spans + diamonds + playhead)

    private var laneWidth: CGFloat {
        CGFloat(span) * pixelsPerSecond + 20
    }

    private var lanes: some View {
        VStack(alignment: .leading, spacing: 0) {
            ruler
            ForEach(rows) { row in
                switch row {
                case .track(let binding, let tint):
                    laneRow(binding, tint: tint)
                case .property(let binding, let property, let tint):
                    propertyLane(binding, property: property, tint: tint)
                }
            }
        }
        .frame(width: laneWidth, alignment: .leading)
        .coordinateSpace(name: laneSpace)
        .overlay(playhead, alignment: .topLeading)
    }

    /// Ticks every 0.1 s, labelled majors every 0.5 s. Dragging scrubs.
    private var ruler: some View {
        Canvas { ctx, size in
            let secondary = Color.secondary.opacity(0.55)
            var t = 0.0
            while t <= span {
                let x = CGFloat(t) * pixelsPerSecond
                let isMajor = (t * 10).rounded().truncatingRemainder(dividingBy: 5) == 0
                var line = Path()
                line.move(to: CGPoint(x: x, y: isMajor ? 6 : 13))
                line.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(line, with: .color(secondary.opacity(isMajor ? 0.9 : 0.4)),
                           lineWidth: 1)
                if isMajor {
                    ctx.draw(
                        Text(String(format: t == t.rounded() ? "%.0fs" : "%.1fs", t))
                            .font(.system(size: 8))
                            .foregroundColor(.secondary),
                        at: CGPoint(x: x + 3, y: 6), anchor: .topLeading)
                }
                t += 0.1
            }
        }
        .frame(height: rulerHeight)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    preview.scrub(to: Double(value.location.x / pixelsPerSecond))
                }
        )
        .accessibilityIdentifier("timeline.ruler")
    }

    private func laneRow(_ binding: AnimationBinding, tint: Color) -> some View {
        let geometry = trackGeometry(binding)
        return ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.secondary.opacity(0.06))
                .frame(height: rowHeight - 6)
            if let geometry {
                if geometry.delay > 0 {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(tint.opacity(0.12))
                        .frame(
                            width: CGFloat(geometry.delay) * pixelsPerSecond,
                            height: rowHeight - 12)
                }
                activeSpan(binding, geometry: geometry, tint: tint)
                if geometry.iterations == .infinity {
                    Image(systemName: "infinity")
                        .font(.system(size: 8))
                        .foregroundStyle(tint)
                        .offset(
                            x: CGFloat(geometry.delay + geometry.duration) * pixelsPerSecond
                                + 4)
                }
                ForEach(geometry.diamondOffsets, id: \.self) { offset in
                    diamond(
                        binding, geometry: geometry, offset: offset, property: nil,
                        tint: tint)
                }
            }
        }
        .frame(height: rowHeight, alignment: .leading)
        .contentShape(Rectangle())
        .gesture(addKeyframeGesture(binding, property: nil))
    }

    private func propertyLane(
        _ binding: AnimationBinding, property: String, tint: Color
    ) -> some View {
        let geometry = trackGeometry(binding)
        return ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.secondary.opacity(0.03))
                .frame(height: rowHeight * 0.75 - 4)
            if let geometry, let def = session.animationDef(named: binding.animation) {
                let offsets = def.keyframes
                    .filter { $0.declarations[property] != nil }
                    .map(\.offset)
                ForEach(Array(Set(offsets)).sorted(), id: \.self) { offset in
                    diamond(
                        binding, geometry: geometry, offset: offset, property: property,
                        tint: tint.opacity(0.8), small: true)
                }
            }
        }
        .frame(height: rowHeight * 0.75, alignment: .leading)
        .contentShape(Rectangle())
        .gesture(addKeyframeGesture(binding, property: property))
    }

    /// The tinted active span with delay/duration drag handles on its edges.
    private func activeSpan(
        _ binding: AnimationBinding, geometry: TrackGeometry, tint: Color
    ) -> some View {
        let width = max(CGFloat(geometry.duration) * pixelsPerSecond, 2)
        return RoundedRectangle(cornerRadius: 3)
            .fill(tint.opacity(0.28))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(tint.opacity(0.5), lineWidth: 1))
            .frame(width: width, height: rowHeight - 12)
            .overlay(alignment: .leading) {
                spanHandle(binding, leadingEdge: true, geometry: geometry)
            }
            .overlay(alignment: .trailing) {
                spanHandle(binding, leadingEdge: false, geometry: geometry)
            }
            .offset(x: CGFloat(geometry.delay) * pixelsPerSecond)
    }

    private func spanHandle(
        _ binding: AnimationBinding, leadingEdge: Bool, geometry: TrackGeometry
    ) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 7)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named(laneSpace))
                    .onChanged { value in
                        spanDrag = SpanDrag(target: binding.target, leadingEdge: leadingEdge)
                        let t = max(0, Double(value.location.x / pixelsPerSecond))
                        if leadingEdge {
                            session.updateAnimationBinding(
                                target: binding.target, label: "Delay",
                                coalesceKey: "span-delay|\(binding.target)"
                            ) { $0.delay = (t * 100).rounded() / 100 }
                        } else {
                            let duration = max(0.05, t - geometry.delay)
                            session.updateAnimationBinding(
                                target: binding.target, label: "Duration",
                                coalesceKey: "span-duration|\(binding.target)"
                            ) { $0.duration = (duration * 100).rounded() / 100 }
                        }
                    }
                    .onEnded { _ in
                        spanDrag = nil
                        session.endStyleEdit()
                    }
            )
    }

    // MARK: - Diamonds

    private func diamond(
        _ binding: AnimationBinding, geometry: TrackGeometry, offset: Double,
        property: String?, tint: Color, small: Bool = false
    ) -> some View {
        let time = geometry.delay + offset / 100 * geometry.duration
        let side: CGFloat = small ? 7 : 9
        let ref = KeyframeRef(target: binding.target, property: property, offset: offset)
        return Diamond()
            .fill(tint)
            .frame(width: side, height: side)
            .frame(width: 16, height: rowHeight - 6)  // hit target
            .contentShape(Rectangle())
            .offset(x: CGFloat(time) * pixelsPerSecond - 8)
            .gesture(diamondDragGesture(binding, geometry: geometry, offset: offset,
                                        property: property))
            .onTapGesture { editingKeyframe = ref }
            .popover(
                isPresented: Binding(
                    get: { editingKeyframe == ref },
                    set: { shown in if !shown { editingKeyframe = nil } })
            ) {
                KeyframePopover(
                    session: session, target: binding.target, property: property,
                    offset: currentOffset(of: ref))
            }
            .accessibilityIdentifier("timeline.keyframe")
    }

    /// A drag may have moved the keyframe since the popover opened; follow
    /// the live scene, not the captured ref.
    private func currentOffset(of ref: KeyframeRef) -> Double {
        ref.offset
    }

    private func diamondDragGesture(
        _ binding: AnimationBinding, geometry: TrackGeometry, offset: Double,
        property: String?
    ) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(laneSpace))
            .onChanged { value in
                if diamondDrag == nil {
                    diamondDrag = DiamondDrag(
                        target: binding.target, property: property, from: offset)
                }
                guard let drag = diamondDrag else { return }
                let time = Double(value.location.x / pixelsPerSecond)
                var newOffset =
                    (time - geometry.delay) / max(geometry.duration, 1e-9) * 100
                if !NSEvent.modifierFlags.contains(.shift) {
                    newOffset = newOffset.rounded()  // 1% grid
                }
                newOffset = min(100, max(0, newOffset))
                guard newOffset != drag.from else { return }
                moveKeyframe(drag: drag, to: newOffset)
                diamondDrag?.from = newOffset
            }
            .onEnded { _ in
                diamondDrag = nil
                session.endStyleEdit()
            }
    }

    private func moveKeyframe(drag: DiamondDrag, to newOffset: Double) {
        let coalesceKey = "kf-move|\(drag.target)|\(drag.property ?? "*")"
        session.editAnimationDef(
            bindingTarget: drag.target, label: "Move keyframe", coalesceKey: coalesceKey
        ) { def in
            if let property = drag.property {
                // Move ONE property between frames.
                guard
                    let source = def.keyframes.firstIndex(where: {
                        $0.offset == drag.from && $0.declarations[property] != nil
                    }), let value = def.keyframes[source].declarations[property]
                else { return }
                def.keyframes[source].declarations.removeValue(forKey: property)
                if def.keyframes[source].declarations.isEmpty {
                    def.keyframes.remove(at: source)
                }
                if let dest = def.keyframes.firstIndex(where: { $0.offset == newOffset }) {
                    def.keyframes[dest].declarations[property] = value
                } else {
                    def.keyframes.append(
                        AnimationKeyframe(
                            offset: newOffset, declarations: [property: value]))
                }
            } else {
                // Move the whole frame (union diamond).
                if let i = def.keyframes.firstIndex(where: { $0.offset == drag.from }) {
                    def.keyframes[i].offset = newOffset
                }
            }
        }
    }

    /// Double-click a lane adds a keyframe at that time, holding the
    /// previous frame's values (predictable; tweak via record/popover).
    private func addKeyframeGesture(
        _ binding: AnimationBinding, property: String?
    ) -> some Gesture {
        SpatialTapGesture(count: 2, coordinateSpace: .named(laneSpace))
            .onEnded { value in
                guard let geometry = trackGeometry(binding) else { return }
                let time = Double(value.location.x / pixelsPerSecond)
                let offset = min(
                    100,
                    max(0, ((time - geometry.delay) / max(geometry.duration, 1e-9) * 100)
                            .rounded()))
                session.editAnimationDef(
                    bindingTarget: binding.target, label: "Add keyframe"
                ) { def in
                    guard !def.keyframes.contains(where: { $0.offset == offset }) else {
                        return
                    }
                    let previous = def.keyframes.last { $0.offset < offset }
                        ?? def.keyframes.first
                    var declarations = previous?.declarations ?? [:]
                    if let property {
                        declarations = declarations.filter { $0.key == property }
                    }
                    def.keyframes.append(
                        AnimationKeyframe(offset: offset, declarations: declarations))
                }
            }
    }

    private struct TrackGeometry {
        var delay: Double
        var duration: Double
        var iterations: Double
        var diamondOffsets: [Double]
    }

    private func trackGeometry(_ binding: AnimationBinding) -> TrackGeometry? {
        guard let def = session.animationDef(named: binding.animation) else { return nil }
        let timing = AnimationInterpolator.timing(
            of: binding, def: def, settings: session.resolvedAnimationSettings)
        let offsets = Set(def.keyframes.map(\.offset)).sorted()
        return TrackGeometry(
            delay: timing.delay,
            duration: timing.duration,
            iterations: timing.iterations,
            diamondOffsets: offsets)
    }

    /// The playhead: its own clock overlay, so only this layer redraws per
    /// frame while playing.
    private var playhead: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !preview.isPlaying)) { tl in
            let t = preview.time(at: tl.date)
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 1.5)
                .frame(maxHeight: .infinity)
                .overlay(
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                        .offset(y: 3),
                    alignment: .top
                )
                .offset(x: CGFloat(t) * pixelsPerSecond)
                .allowsHitTesting(false)
        }
        .accessibilityIdentifier("timeline.playhead")
    }
}

// MARK: - Keyframe popover

/// Value + easing editor for one keyframe (or one property of it): text
/// fields per declaration, easing presets + cubic-bezier pad (the easing
/// shapes the segment LEAVING this frame), delete.
private struct KeyframePopover: View {
    @ObservedObject var session: EditorSession
    let target: String
    let property: String?
    let offset: Double

    private var keyframe: AnimationKeyframe? {
        guard
            let binding = session.animationBindings.first(where: { $0.target == target }),
            let def = session.animationDef(named: binding.animation)
        else { return nil }
        return def.keyframes.first { $0.offset == offset }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let keyframe {
                Text(String(format: "Keyframe at %.0f%%", offset))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(properties(of: keyframe), id: \.self) { name in
                    declarationRow(name, keyframe: keyframe)
                }
                addPropertyMenu(keyframe)
                Divider()
                easingSection(keyframe)
                Divider()
                Button(role: .destructive) {
                    deleteKeyframe()
                } label: {
                    Label(
                        property == nil ? "Delete Keyframe" : "Remove Property Here",
                        systemImage: "trash")
                }
                .controlSize(.small)
            } else {
                Text("Keyframe removed.").foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 230)
    }

    private func properties(of keyframe: AnimationKeyframe) -> [String] {
        let all = AnimationCSS.declarationOrder.filter { keyframe.declarations[$0] != nil }
            + keyframe.declarations.keys
            .filter { !AnimationCSS.declarationOrder.contains($0) }.sorted()
        if let property { return all.filter { $0 == property } }
        return all
    }

    private func declarationRow(_ name: String, keyframe: AnimationKeyframe) -> some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.caption)
                .frame(width: 92, alignment: .trailing)
                .foregroundStyle(.secondary)
            TextField(
                "value",
                text: Binding(
                    get: { keyframe.declarations[name] ?? "" },
                    set: { text in
                        guard AnimationLint.isSafeValue(text) else { return }
                        session.editAnimationDef(
                            bindingTarget: target, label: "Keyframe value",
                            coalesceKey: "kf-value|\(target)|\(offset)|\(name)"
                        ) { def in
                            guard
                                let i = def.keyframes.firstIndex(where: {
                                    $0.offset == offset
                                })
                            else { return }
                            def.keyframes[i].declarations[name] = text
                        }
                    })
            )
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .onSubmit { session.endStyleEdit() }
        }
    }

    private func addPropertyMenu(_ keyframe: AnimationKeyframe) -> some View {
        let missing = AnimationLint.animatableProperties
            .subtracting(keyframe.declarations.keys)
            .sorted()
        return Menu {
            ForEach(missing, id: \.self) { name in
                Button(name) {
                    session.editAnimationDef(
                        bindingTarget: target, label: "Add property"
                    ) { def in
                        guard
                            let i = def.keyframes.firstIndex(where: { $0.offset == offset })
                        else { return }
                        def.keyframes[i].declarations[name] = defaultValue(for: name)
                    }
                }
            }
        } label: {
            Label("Add Property", systemImage: "plus")
        }
        .controlSize(.small)
        .disabled(missing.isEmpty || property != nil)
    }

    private func defaultValue(for property: String) -> String {
        switch property {
        case "transform": return "rotate(0deg)"
        case "opacity": return "1"
        case "stroke-width": return "2"
        case "stroke-dashoffset", "stroke-dasharray": return "100"
        case "visibility": return "visible"
        case "transform-origin": return "center"
        default: return "#010101"
        }
    }

    private func easingSection(_ keyframe: AnimationKeyframe) -> some View {
        let easingBinding = Binding(
            get: { keyframe.easing ?? "" },
            set: { text in
                session.editAnimationDef(
                    bindingTarget: target, label: "Easing",
                    coalesceKey: "kf-easing|\(target)|\(offset)"
                ) { def in
                    guard let i = def.keyframes.firstIndex(where: { $0.offset == offset })
                    else { return }
                    def.keyframes[i].easing = text.isEmpty ? nil : text
                }
            })
        return VStack(alignment: .leading, spacing: 6) {
            Text("Easing out of this frame")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Easing", selection: presetSelection(easingBinding)) {
                Text("Inherit").tag("")
                Text("linear").tag("linear")
                Text("ease").tag("ease")
                Text("ease-in").tag("ease-in")
                Text("ease-out").tag("ease-out")
                Text("ease-in-out").tag("ease-in-out")
                Text("steps(2)").tag("steps(2, end)")
                Text("steps(4)").tag("steps(4, end)")
                Text("custom curve").tag("custom")
            }
            .labelsHidden()
            .controlSize(.small)
            if isCustom(easingBinding.wrappedValue) {
                BezierCurveEditor(easing: easingBinding)
            }
        }
    }

    private func isCustom(_ easing: String) -> Bool {
        easing.hasPrefix("cubic-bezier(")
    }

    private func presetSelection(_ easing: Binding<String>) -> Binding<String> {
        Binding(
            get: { isCustom(easing.wrappedValue) ? "custom" : easing.wrappedValue },
            set: { picked in
                easing.wrappedValue =
                    picked == "custom" ? "cubic-bezier(.25, .1, .25, 1)" : picked
            })
    }

    private func deleteKeyframe() {
        session.editAnimationDef(bindingTarget: target, label: "Delete keyframe") { def in
            guard let i = def.keyframes.firstIndex(where: { $0.offset == offset }) else {
                return
            }
            if let property {
                def.keyframes[i].declarations.removeValue(forKey: property)
                if def.keyframes[i].declarations.isEmpty {
                    def.keyframes.remove(at: i)
                }
            } else {
                def.keyframes.remove(at: i)
            }
        }
    }
}

/// A keyframe marker.
struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.closeSubpath()
        return p
    }
}
