import AppKit
import FekthorKit
import SwiftUI

// The style palettes' contents: Fill, Stroke and Opacity, split from the old
// right-side inspector into separate floating panels (hosted by
// EditorPanelsLayer). The shared plumbing lives in StyleSelection so all
// three edit through the same session API — mixed selections show em dashes,
// paints beyond plain colours (var()/currentColor/gradients/url()) are shown
// read-only as their raw text with a "custom" hint and are only replaced by
// an explicit user edit, and each control interaction is one undo step (the
// session coalesces per-control edits).

/// Selection plumbing shared by the style palettes. With nothing selected the
/// palettes edit the drawing style new shapes are born with.
@MainActor
struct StyleSelection {
    var session: EditorSession

    var shapes: [ShapeNode] {
        session.selection.sorted().compactMap { session.document.firstShape(id: $0) }
    }

    var styles: [Style] {
        let shapes = shapes
        return shapes.isEmpty ? [session.drawingStyle] : shapes.map { $0.effectiveStyle }
    }

    var headerText: String {
        let count = shapes.count
        return count == 0 ? "Drawing style — new shapes" : "\(count) selected"
    }

    enum PaintSummary: Equatable {
        case unset
        case none
        case color(UInt8, UInt8, UInt8)
        case custom(String)
        case mixed
    }

    func summary(of get: (Style) -> PaintValue?) -> PaintSummary {
        let values = styles.map(get)
        guard let first = values.first else { return .unset }
        for v in values.dropFirst() where v != first { return .mixed }
        switch first {
        case nil: return .unset
        case .some(.none): return .none
        case .some(.color(let r, let g, let b)): return .color(r, g, b)
        case .some(let p): return .custom(Self.paintText(p))
        }
    }

    static func paintText(_ p: PaintValue) -> String {
        switch p {
        case .none: return "none"
        case .color(let r, let g, let b): return String(format: "#%02x%02x%02x", r, g, b)
        case .reference(let id): return "url(#\(id))"
        case .linear: return "linear gradient"
        case .radial: return "radial gradient"
        case .raw(let s): return s
        }
    }

    /// "" when unset everywhere, the shared keyword, or "…" when mixed.
    func commonKeyword(_ name: String) -> String {
        var found: String? = nil
        for style in styles {
            let v: String
            if case .keyword(let k)? = style.value(of: name) {
                v = k
            } else if case .raw(let r)? = style.value(of: name) {
                v = r
            } else {
                v = ""
            }
            if found == nil {
                found = v
            } else if found != v {
                return "…"
            }
        }
        return found ?? ""
    }

    static func hexText(_ summary: PaintSummary) -> String {
        if case .color(let r, let g, let b) = summary {
            return String(format: "#%02x%02x%02x", r, g, b)
        }
        return ""
    }
}

/// The shared "N selected / drawing style" caption at the top of each palette.
private struct SelectionHeader: View {
    @ObservedObject var session: EditorSession

    var body: some View {
        Text(StyleSelection(session: session).headerText)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Fill palette

struct FillPanelContent: View {
    @ObservedObject var session: EditorSession

    @State private var hex = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SelectionHeader(session: session)
            PaintControls(
                session: session, editKey: "fill", hex: $hex,
                get: { $0.fill }, set: { $0.fill = $1 })
            KeywordPickerRow(
                session: session, label: "Rule", name: "fill-rule", editKey: "fill-rule",
                options: [("nonzero", "Nonzero"), ("evenodd", "Even-odd")])
        }
        .onAppear { sync() }
        .onChange(of: session.generation) { _, _ in sync() }
        .onChange(of: session.selection) { _, _ in
            session.endStyleEdit()
            sync()
        }
    }

    private func sync() {
        hex = StyleSelection.hexText(StyleSelection(session: session).summary(of: { $0.fill }))
    }
}

// MARK: - Stroke palette

struct StrokePanelContent: View {
    @ObservedObject var session: EditorSession

    @State private var hex = ""
    @State private var widthText = ""
    @State private var dashText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SelectionHeader(session: session)
            PaintControls(
                session: session, editKey: "stroke", hex: $hex,
                get: { $0.stroke }, set: { $0.stroke = $1 })
            widthRow
            KeywordPickerRow(
                session: session, label: "Cap", name: "stroke-linecap", editKey: "cap",
                options: [("butt", "Butt"), ("round", "Round"), ("square", "Square")])
            KeywordPickerRow(
                session: session, label: "Join", name: "stroke-linejoin", editKey: "join",
                options: [("miter", "Miter"), ("round", "Round"), ("bevel", "Bevel")])
            dashRow
        }
        .onAppear { sync() }
        .onChange(of: session.generation) { _, _ in sync() }
        .onChange(of: session.selection) { _, _ in
            session.endStyleEdit()
            sync()
        }
    }

    private var widthRow: some View {
        HStack(spacing: 8) {
            Text("Width").font(.caption)
            TextField("—", text: $widthText)
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospaced())
                .frame(width: 64)
                .onSubmit { commitWidth() }
            if let unit = strokeWidthUnit {
                Text(unit).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var dashRow: some View {
        HStack(spacing: 8) {
            Text("Dash").font(.caption)
            TextField("e.g. 4 2", text: $dashText)
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospaced())
                .onSubmit { commitDash() }
        }
    }

    /// The first style's declared stroke-width unit (units are preserved on
    /// write via `Style.strokeWidth`).
    private var strokeWidthUnit: String? {
        let styles = StyleSelection(session: session).styles
        if case .number(_, let unit)? = styles.first?.value(of: "stroke-width") { return unit }
        return nil
    }

    private func commitWidth() {
        let trimmed = widthText.trimmingCharacters(in: .whitespaces)
        guard let v = Double(trimmed), v >= 0 else {
            sync()
            return
        }
        session.editSelectionStyle("stroke-width") { $0.strokeWidth = v }
    }

    private func commitDash() {
        let trimmed = dashText.trimmingCharacters(in: .whitespaces)
        session.editSelectionStyle("dash") { style in
            if trimmed.isEmpty || trimmed == "none" {
                style.remove("stroke-dasharray")
            } else {
                style.set("stroke-dasharray", .raw(trimmed))
            }
        }
    }

    private func sync() {
        let selection = StyleSelection(session: session)
        hex = StyleSelection.hexText(selection.summary(of: { $0.stroke }))
        let styles = selection.styles
        let widths = styles.map { $0.strokeWidth }
        if let first = widths.first, widths.allSatisfy({ $0 == first }), let w = first {
            widthText = w == w.rounded() ? String(Int(w)) : String(w)
        } else {
            widthText = ""
        }
        let dashes = styles.map { style -> String in
            if case .raw(let r)? = style.value(of: "stroke-dasharray") { return r }
            return ""
        }
        if let first = dashes.first, dashes.allSatisfy({ $0 == first }) {
            dashText = first
        } else {
            dashText = ""
        }
    }
}

// MARK: - Opacity palette

struct OpacityPanelContent: View {
    @ObservedObject var session: EditorSession

    var body: some View {
        let value = StyleSelection(session: session).styles.first?.opacity ?? 1
        VStack(alignment: .leading, spacing: 8) {
            SelectionHeader(session: session)
            HStack {
                Text("Opacity").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int((value * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { StyleSelection(session: session).styles.first?.opacity ?? 1 },
                    set: { v in
                        session.editSelectionStyle("opacity") { style in
                            if v >= 0.999 {
                                style.opacity = nil
                            } else {
                                style.opacity = (v * 100).rounded() / 100
                            }
                        }
                    }),
                in: 0...1,
                onEditingChanged: { editing in
                    if !editing { session.endStyleEdit() }
                })
        }
        .onChange(of: session.selection) { _, _ in session.endStyleEdit() }
    }
}

// MARK: - Shared paint controls (none / colour well / hex)

private struct PaintControls: View {
    @ObservedObject var session: EditorSession
    let editKey: String
    @Binding var hex: String
    let get: (Style) -> PaintValue?
    let set: (inout Style, PaintValue?) -> Void

    private var summary: StyleSelection.PaintSummary {
        StyleSelection(session: session).summary(of: get)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if case .custom(let text) = summary {
                Text(text)
                    .font(.caption.monospaced())
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text("custom paint — pick a colour to replace")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                noneButton
                ColorPicker(
                    "",
                    selection: Binding(
                        get: { wellColor(summary) },
                        set: { color in
                            apply { set(&$0, paint(from: color)) }
                        }),
                    supportsOpacity: false
                )
                .labelsHidden()
                TextField("hex", text: $hex)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                    .onSubmit { commitHex() }
            }
            if summary == .mixed {
                Text("mixed").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func apply(_ change: @escaping (inout Style) -> Void) {
        session.editSelectionStyle(editKey, change)
    }

    private var noneButton: some View {
        let active = summary == .none
        return Button {
            apply { set(&$0, PaintValue.none) }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(
                        active ? Color.accentColor : Color.secondary, lineWidth: active ? 2 : 1
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(nsColor: .textBackgroundColor)))
                Path { p in
                    p.move(to: CGPoint(x: 3, y: 15))
                    p.addLine(to: CGPoint(x: 15, y: 3))
                }
                .stroke(Color.red, lineWidth: 1.5)
            }
            .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .help("No \(editKey)")
    }

    private func wellColor(_ summary: StyleSelection.PaintSummary) -> Color {
        if case .color(let r, let g, let b) = summary {
            return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
        }
        return .black
    }

    private func paint(from color: Color) -> PaintValue {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return .color(
            r: UInt8(max(0, min(255, ns.redComponent * 255))),
            g: UInt8(max(0, min(255, ns.greenComponent * 255))),
            b: UInt8(max(0, min(255, ns.blueComponent * 255))))
    }

    private func commitHex() {
        let trimmed = hex.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if trimmed.lowercased() == "none" {
            apply { set(&$0, PaintValue.none) }
            return
        }
        let value = trimmed.hasPrefix("#") ? trimmed : "#" + trimmed
        guard let c = PaintValue.parseHex(value) else { return }
        apply { set(&$0, .color(r: c.r, g: c.g, b: c.b)) }
    }
}

// MARK: - Keyword pickers (cap / join / fill-rule)

private struct KeywordPickerRow: View {
    @ObservedObject var session: EditorSession
    let label: String
    let name: String
    let editKey: String
    let options: [(String, String)]

    var body: some View {
        let current = StyleSelection(session: session).commonKeyword(name)
        return HStack(spacing: 8) {
            Text(label).font(.caption)
            Picker(
                "",
                selection: Binding(
                    get: { current },
                    set: { picked in
                        session.editSelectionStyle(editKey) { style in
                            if picked.isEmpty {
                                style.remove(name)
                            } else if picked != "…" {
                                style.set(name, .keyword(picked))
                            }
                        }
                    })
            ) {
                Text("Default").tag("")
                ForEach(options, id: \.0) { value, title in
                    Text(title).tag(value)
                }
                if current == "…" {
                    Text("Mixed").tag("…")
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
        }
    }
}
