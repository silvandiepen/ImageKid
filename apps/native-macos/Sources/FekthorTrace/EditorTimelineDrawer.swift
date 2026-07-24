import FekthorKit
import SwiftUI

/// The bottom animation timeline drawer (DAW-style): a resizable strip
/// under the canvas with a transport bar, one track per binding (name,
/// asset, trigger), and a time ruler with delay/duration spans, keyframe
/// diamonds and a scrubbable playhead. The floating palettes stay 240 pt
/// wide — a ruler needs the window's width, hence a drawer, not a palette.
///
/// This surface READS the scene and drives the preview clock; keyframe
/// editing (drags, easing, record) layers on top of the same geometry.
struct EditorTimelineDrawer: View {
    @ObservedObject var session: EditorSession
    @ObservedObject var preview: AnimationPreviewController
    @ObservedObject private var panels = EditorPanelsState.shared

    /// Horizontal zoom. Persisted per session only — like the canvas zoom,
    /// it is working state, not document state.
    @State private var pixelsPerSecond: CGFloat = 120

    private let trackColumnWidth: CGFloat = 200
    private let rulerHeight: CGFloat = 22
    private let rowHeight: CGFloat = 30
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
        .accessibilityIdentifier("timeline.drawer")
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
            ForEach(Array(bindings.enumerated()), id: \.element.target) { index, binding in
                trackHeader(binding, tint: trackTints[index % trackTints.count])
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
        return HStack(spacing: 6) {
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
            ForEach(Array(bindings.enumerated()), id: \.element.target) { index, binding in
                laneRow(binding, tint: trackTints[index % trackTints.count])
            }
        }
        .frame(width: laneWidth, alignment: .leading)
        .overlay(playhead, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(scrubGesture)
    }

    /// Ticks every 0.1 s, labelled majors every 0.5 s.
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
        .accessibilityIdentifier("timeline.ruler")
    }

    private func laneRow(_ binding: AnimationBinding, tint: Color) -> some View {
        let geometry = trackGeometry(binding)
        return ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.secondary.opacity(0.06))
                .frame(height: rowHeight - 6)
            if let geometry {
                // Delay lead-in (dimmed) + active span (tinted).
                if geometry.delay > 0 {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(tint.opacity(0.12))
                        .frame(
                            width: CGFloat(geometry.delay) * pixelsPerSecond,
                            height: rowHeight - 12)
                        .offset(x: 0)
                }
                RoundedRectangle(cornerRadius: 3)
                    .fill(tint.opacity(0.28))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(tint.opacity(0.5), lineWidth: 1))
                    .frame(
                        width: max(CGFloat(geometry.duration) * pixelsPerSecond, 2),
                        height: rowHeight - 12)
                    .offset(x: CGFloat(geometry.delay) * pixelsPerSecond)
                if geometry.iterations == .infinity {
                    Image(systemName: "infinity")
                        .font(.system(size: 8))
                        .foregroundStyle(tint)
                        .offset(
                            x: CGFloat(geometry.delay + geometry.duration) * pixelsPerSecond
                                + 4)
                }
                // Union keyframe diamonds (one per distinct offset).
                ForEach(geometry.diamondTimes, id: \.self) { t in
                    Diamond()
                        .fill(tint)
                        .frame(width: 9, height: 9)
                        .offset(x: CGFloat(t) * pixelsPerSecond - 4.5)
                }
            }
        }
        .frame(height: rowHeight, alignment: .leading)
    }

    private struct TrackGeometry {
        var delay: Double
        var duration: Double
        var iterations: Double
        var diamondTimes: [Double]
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
            diamondTimes: offsets.map { timing.delay + $0 / 100 * timing.duration })
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

    /// Click/drag anywhere on the lanes scrubs the paused clock.
    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                preview.scrub(to: Double(value.location.x / pixelsPerSecond))
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
