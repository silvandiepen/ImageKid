import AppKit
import FekthorKit
import SwiftUI

// The Fill palette's gradient face: a paint-type segmented control
// (Solid | Linear | Radial | None) and, while the selection shares one
// gradient, a stops editor — a live gradient bar with draggable stop chips
// (click an empty spot to add an interpolated stop), plus colour / hex /
// offset controls and a delete for the selected stop (minimum two stops).
// Every control edits through the session's coalescing so a chip drag or a
// colour scrub is ONE undo step; the on-canvas axis handles live in
// EditorCanvasView.

/// What the fill segmented control shows for the current selection.
enum FillPaintKind: String, CaseIterable {
    case solid
    case linear
    case radial
    case none

    var title: String {
        switch self {
        case .solid: return "Solid"
        case .linear: return "Linear"
        case .radial: return "Radial"
        case .none: return "None"
        }
    }
}

struct FillPaintTypeRow: View {
    @ObservedObject var session: EditorSession

    /// The shared paint kind, or nil when mixed / unmodelled (url()/var()).
    private var currentKind: FillPaintKind? {
        let paints = StyleSelection(session: session).styles.map { $0.fill }
        guard let first = paints.first else { return nil }
        for p in paints.dropFirst() where !Self.sameKind(p, first) { return nil }
        switch first {
        case .color?: return .solid
        case .linear?: return .linear
        case .radial?: return .radial
        case PaintValue.none?: return FillPaintKind.none
        case nil: return .solid  // unset renders as SVG's default solid black
        default: return nil
        }
    }

    private static func sameKind(_ a: PaintValue?, _ b: PaintValue?) -> Bool {
        switch (a, b) {
        case (.color?, .color?), (.linear?, .linear?), (.radial?, .radial?),
            (PaintValue.none?, PaintValue.none?), (nil, nil),
            (nil, .color?), (.color?, nil):
            return true
        default:
            return false
        }
    }

    var body: some View {
        Picker(
            "",
            selection: Binding<String>(
                get: { currentKind?.rawValue ?? "" },
                set: { apply($0) })
        ) {
            if currentKind == nil {
                Text("Mixed").tag("")
            }
            ForEach(FillPaintKind.allCases, id: \.rawValue) { kind in
                Text(kind.title).tag(kind.rawValue)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
    }

    private func apply(_ raw: String) {
        guard let kind = FillPaintKind(rawValue: raw), kind != currentKind else { return }
        switch kind {
        case .solid:
            session.setSelectionFillSolid()
        case .linear:
            session.setSelectionFillGradient(.linear)
        case .radial:
            session.setSelectionFillGradient(.radial)
        case .none:
            session.editSelectionStyle("fill", label: "Fill colour") {
                $0.fill = PaintValue.none
            }
            session.endStyleEdit()
        }
    }
}

// MARK: - Stops editor

struct GradientStopsEditor: View {
    @ObservedObject var session: EditorSession

    @State private var selectedStop = 0
    @State private var hexText = ""
    @State private var offsetText = ""
    /// Non-nil while a chip drag is in flight (its index rides along).
    @State private var draggingStop: Int? = nil

    private static let barHeight: CGFloat = 18

    /// The one gradient every selected shape shares, or nil.
    private var commonGradient: PaintValue? {
        let paints = StyleSelection(session: session).styles.map { $0.fill }
        guard let first = paints.first, let paint = first, paint.gradientStops != nil
        else { return nil }
        for p in paints.dropFirst() where p != paint { return nil }
        return paint
    }

    var body: some View {
        if let paint = commonGradient, let stops = paint.gradientStops {
            VStack(alignment: .leading, spacing: 8) {
                bar(paint, stops)
                stopControls(paint, stops)
                Text("Click the bar to add a stop · drag chips to move")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .onAppear { syncFields(stops) }
            .onChange(of: session.selection) { _, _ in
                selectedStop = 0
                session.endStyleEdit()
                if let s = commonGradient?.gradientStops { syncFields(s) }
            }
            .onChange(of: session.generation) { _, _ in
                if draggingStop == nil, let s = commonGradient?.gradientStops {
                    syncFields(s)
                }
            }
        } else {
            Text("Shapes have different gradients — edit one at a time.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Bar

    private func bar(_ paint: PaintValue, _ stops: [GradientStop]) -> some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: stops.map { stop in
                                .init(
                                    color: Self.color(stop),
                                    location: CGFloat(max(0, min(1, stop.offset))))
                            }),
                            startPoint: .leading, endPoint: .trailing)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(.white.opacity(0.25), lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 5))
                    .gesture(
                        // A click on empty bar space adds an interpolated
                        // stop right there (one undo step).
                        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.barSpace))
                            .onEnded { v in
                                addStop(paint, at: Double(v.location.x / width))
                            }
                    )
                ForEach(stops.indices, id: \.self) { i in
                    chip(paint, stops, index: i, width: width)
                }
            }
            .coordinateSpace(name: Self.barSpace)
        }
        .frame(height: Self.barHeight)
        .padding(.horizontal, 2)
    }

    /// The chips' drags measure against the BAR, not their own 12pt frame.
    private static let barSpace = "fekthor.gradient.bar"

    private func chip(
        _ paint: PaintValue, _ stops: [GradientStop], index: Int, width: CGFloat
    ) -> some View {
        let stop = stops[index]
        let x = CGFloat(max(0, min(1, stop.offset))) * width
        let selected = index == selectedStop
        return Circle()
            .fill(Self.color(stop))
            .frame(width: 12, height: 12)
            .overlay(
                Circle().strokeBorder(
                    selected ? Color.white : .white.opacity(0.5),
                    lineWidth: selected ? 2 : 1))
            .position(x: x, y: Self.barHeight / 2)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.barSpace))
                    .onChanged { v in
                        draggingStop = index
                        selectedStop = index
                        moveStop(paint, index: index, to: Double(v.location.x / width))
                    }
                    .onEnded { _ in
                        draggingStop = nil
                        session.endStyleEdit()
                        if let s = commonGradient?.gradientStops { syncFields(s) }
                    }
            )
    }

    // MARK: Selected stop controls

    private func stopControls(_ paint: PaintValue, _ stops: [GradientStop]) -> some View {
        let index = min(selectedStop, stops.count - 1)
        let stop = stops[index]
        return HStack(spacing: 8) {
            // Swatch-first stop colour (file / workspace / document grids,
            // Custom… for the system picker).
            SwatchColorWell(
                session: session,
                current: Self.color(stop),
                addableHex: Self.hex(stop),
                onPick: { recolorStop(paint, index: index, color: $0) })
            TextField("hex", text: $hexText)
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospaced())
                .frame(width: 66)
                .onSubmit { commitHex(paint, index: index) }
            NumericField(placeholder: "%", text: $offsetText, range: 0...100) { _ in
                commitOffset(paint, index: index)
            }
            .frame(width: 44)
            Text("%")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                deleteStop(paint, index: index)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .disabled(stops.count <= 2)
            .opacity(stops.count <= 2 ? 0.4 : 1)
            .help("Delete this stop (gradients keep at least two)")
        }
    }

    // MARK: Edits (all through the session's coalescing keys)

    private func write(_ paint: PaintValue, _ stops: [GradientStop], key: String, label: String) {
        let next = paint.withGradientStops(stops)
        session.editSelectionStyle(key, label: label) { $0.fill = next }
    }

    private func addStop(_ paint: PaintValue, at t: Double) {
        let clamped = max(0, min(1, t))
        guard var stops = paint.gradientStops,
            let c = paint.interpolatedColor(at: clamped)
        else { return }
        // A click ON a chip belongs to the chip (its gesture wins), but be
        // safe: never add a duplicate within a chip radius.
        guard !stops.contains(where: { abs($0.offset - clamped) < 0.02 }) else { return }
        stops.append(GradientStop(color: (c.r, c.g, c.b), offset: clamped))
        stops.sort { $0.offset < $1.offset }
        write(paint, stops, key: "fill-grad-add", label: "Add gradient stop")
        session.endStyleEdit()
        selectedStop = stops.firstIndex { abs($0.offset - clamped) < 1e-9 } ?? 0
        syncFields(stops)
    }

    private func moveStop(_ paint: PaintValue, index: Int, to t: Double) {
        guard var stops = paint.gradientStops, stops.indices.contains(index) else { return }
        let clamped = max(0, min(1, t))
        stops[index].offset = clamped
        // Keep the array sorted; track the moved stop's new index so the
        // drag keeps hold of it across reorders.
        let moved = stops[index]
        stops.sort { $0.offset < $1.offset }
        write(paint, stops, key: "fill-grad-move", label: "Move gradient stop")
        if let i = stops.firstIndex(where: {
            $0.offset == moved.offset && $0.color == moved.color
        }) {
            selectedStop = i
            draggingStop = i
        }
        offsetText = String(Int((clamped * 100).rounded()))
    }

    private func recolorStop(_ paint: PaintValue, index: Int, color: Color) {
        guard var stops = paint.gradientStops, stops.indices.contains(index) else { return }
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        stops[index].color = [
            UInt8(max(0, min(255, ns.redComponent * 255))),
            UInt8(max(0, min(255, ns.greenComponent * 255))),
            UInt8(max(0, min(255, ns.blueComponent * 255))),
        ]
        write(paint, stops, key: "fill-grad-color", label: "Gradient colour")
        syncFields(stops)
    }

    private func commitHex(_ paint: PaintValue, index: Int) {
        let trimmed = hexText.trimmingCharacters(in: .whitespaces)
        let value = trimmed.hasPrefix("#") ? trimmed : "#" + trimmed
        guard var stops = paint.gradientStops, stops.indices.contains(index),
            let c = PaintValue.parseHex(value)
        else { return }
        stops[index].color = [c.r, c.g, c.b]
        write(paint, stops, key: "fill-grad-color", label: "Gradient colour")
        session.endStyleEdit()
    }

    private func commitOffset(_ paint: PaintValue, index: Int) {
        guard let pct = Double(offsetText.trimmingCharacters(in: .whitespaces)) else { return }
        moveStop(paint, index: index, to: pct / 100)
        session.endStyleEdit()
        if let s = commonGradient?.gradientStops { syncFields(s) }
    }

    private func deleteStop(_ paint: PaintValue, index: Int) {
        guard var stops = paint.gradientStops, stops.count > 2,
            stops.indices.contains(index)
        else { return }
        stops.remove(at: index)
        write(paint, stops, key: "fill-grad-delete", label: "Delete gradient stop")
        session.endStyleEdit()
        selectedStop = max(0, index - 1)
        syncFields(stops)
    }

    // MARK: Helpers

    private func syncFields(_ stops: [GradientStop]) {
        let index = min(selectedStop, stops.count - 1)
        guard stops.indices.contains(index) else { return }
        let c = stops[index].color
        hexText = String(
            format: "#%02x%02x%02x", c.count > 0 ? c[0] : 0, c.count > 1 ? c[1] : 0,
            c.count > 2 ? c[2] : 0)
        offsetText = String(Int((stops[index].offset * 100).rounded()))
    }

    static func hex(_ stop: GradientStop) -> String {
        let c = stop.color
        return String(
            format: "#%02x%02x%02x", c.count > 0 ? c[0] : 0, c.count > 1 ? c[1] : 0,
            c.count > 2 ? c[2] : 0)
    }

    static func color(_ stop: GradientStop) -> Color {
        let c = stop.color
        return Color(
            red: Double(c.count > 0 ? c[0] : 0) / 255,
            green: Double(c.count > 1 ? c[1] : 0) / 255,
            blue: Double(c.count > 2 ? c[2] : 0) / 255)
    }
}
