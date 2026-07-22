import AppKit
import FekthorKit
import SwiftUI

/// Right-side style inspector for the editor: fill, stroke, fill-rule and
/// opacity for the selection — or, with nothing selected, the drawing style
/// new shapes are born with. Mixed selections show em dashes; paints beyond
/// plain colours (var()/currentColor/gradients/url()) are shown read-only as
/// their raw text with a "custom" hint and are only replaced by an explicit
/// user edit. Each control interaction is one undo step (the session
/// coalesces per-control edits).
struct EditorStylePanel: View {
    @ObservedObject var session: EditorSession

    @State private var fillHex = ""
    @State private var strokeHex = ""
    @State private var widthText = ""
    @State private var dashText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                paintSection(
                    title: "Fill", summary: fillSummary, hex: $fillHex, editKey: "fill"
                ) { style, paint in
                    style.fill = paint
                }
                fillRuleRow
                Divider()
                paintSection(
                    title: "Stroke", summary: strokeSummary, hex: $strokeHex, editKey: "stroke"
                ) { style, paint in
                    style.stroke = paint
                }
                strokeDetailRows
                Divider()
                opacityRow
            }
            .padding(12)
        }
        .frame(width: 224)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear { syncFields() }
        .onChange(of: session.generation) { _, _ in syncFields() }
        .onChange(of: session.selection) { _, _ in
            session.endStyleEdit()
            syncFields()
        }
    }

    // MARK: - Selection plumbing

    private var shapes: [ShapeNode] {
        session.selection.sorted().compactMap { session.document.firstShape(id: $0) }
    }

    /// With nothing selected the panel edits the drawing style directly.
    private var styles: [Style] {
        shapes.isEmpty ? [session.drawingStyle] : shapes.map { $0.effectiveStyle }
    }

    private var header: some View {
        Text(
            shapes.isEmpty
                ? "Drawing style — new shapes"
                : "\(shapes.count) selected"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func apply(_ key: String, _ change: @escaping (inout Style) -> Void) {
        session.editSelectionStyle(key, change)
    }

    // MARK: - Paint summaries

    private enum PaintSummary: Equatable {
        case unset
        case none
        case color(UInt8, UInt8, UInt8)
        case custom(String)
        case mixed
    }

    private var fillSummary: PaintSummary { summary(styles.map { $0.fill }) }
    private var strokeSummary: PaintSummary { summary(styles.map { $0.stroke }) }

    private func summary(_ values: [PaintValue?]) -> PaintSummary {
        guard let first = values.first else { return .unset }
        for v in values.dropFirst() where v != first { return .mixed }
        switch first {
        case nil: return .unset
        case .some(.none): return .none
        case .some(.color(let r, let g, let b)): return .color(r, g, b)
        case .some(let p): return .custom(paintText(p))
        }
    }

    private func paintText(_ p: PaintValue) -> String {
        switch p {
        case .none: return "none"
        case .color(let r, let g, let b): return String(format: "#%02x%02x%02x", r, g, b)
        case .reference(let id): return "url(#\(id))"
        case .linear: return "linear gradient"
        case .radial: return "radial gradient"
        case .raw(let s): return s
        }
    }

    // MARK: - Paint rows

    @ViewBuilder
    private func paintSection(
        title: String, summary: PaintSummary, hex: Binding<String>, editKey: String,
        set: @escaping (inout Style, PaintValue?) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
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
                noneButton(active: summary == .none, editKey: editKey, set: set)
                ColorPicker(
                    "",
                    selection: Binding(
                        get: { wellColor(summary) },
                        set: { color in
                            apply(editKey) { set(&$0, paint(from: color)) }
                        }),
                    supportsOpacity: false
                )
                .labelsHidden()
                TextField("hex", text: hex)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                    .onSubmit {
                        commitHex(hex.wrappedValue, editKey: editKey, set: set)
                    }
            }
            if summary == .mixed {
                Text("mixed").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func noneButton(
        active: Bool, editKey: String, set: @escaping (inout Style, PaintValue?) -> Void
    ) -> some View {
        Button {
            apply(editKey) { set(&$0, PaintValue.none) }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(active ? Color.accentColor : Color.secondary, lineWidth: active ? 2 : 1)
                    .background(
                        RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .textBackgroundColor)))
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

    private func wellColor(_ summary: PaintSummary) -> Color {
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

    private func commitHex(
        _ text: String, editKey: String, set: @escaping (inout Style, PaintValue?) -> Void
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if trimmed.lowercased() == "none" {
            apply(editKey) { set(&$0, PaintValue.none) }
            return
        }
        let hex = trimmed.hasPrefix("#") ? trimmed : "#" + trimmed
        guard let c = PaintValue.parseHex(hex) else { return }
        apply(editKey) { set(&$0, .color(r: c.r, g: c.g, b: c.b)) }
    }

    // MARK: - Fill rule

    private var fillRuleRow: some View {
        keywordPicker(
            label: "Rule", name: "fill-rule", editKey: "fill-rule",
            options: [("nonzero", "Nonzero"), ("evenodd", "Even-odd")])
    }

    // MARK: - Stroke details

    @ViewBuilder
    private var strokeDetailRows: some View {
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
        keywordPicker(
            label: "Cap", name: "stroke-linecap", editKey: "cap",
            options: [("butt", "Butt"), ("round", "Round"), ("square", "Square")])
        keywordPicker(
            label: "Join", name: "stroke-linejoin", editKey: "join",
            options: [("miter", "Miter"), ("round", "Round"), ("bevel", "Bevel")])
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
        if case .number(_, let unit)? = styles.first?.value(of: "stroke-width") { return unit }
        return nil
    }

    private func commitWidth() {
        let trimmed = widthText.trimmingCharacters(in: .whitespaces)
        guard let v = Double(trimmed), v >= 0 else {
            syncFields()
            return
        }
        apply("stroke-width") { $0.strokeWidth = v }
    }

    private func commitDash() {
        let trimmed = dashText.trimmingCharacters(in: .whitespaces)
        apply("dash") { style in
            if trimmed.isEmpty || trimmed == "none" {
                style.remove("stroke-dasharray")
            } else {
                style.set("stroke-dasharray", .raw(trimmed))
            }
        }
    }

    // MARK: - Keyword pickers (cap / join / fill-rule)

    private func keywordPicker(
        label: String, name: String, editKey: String, options: [(String, String)]
    ) -> some View {
        let current = commonKeyword(name)
        return HStack(spacing: 8) {
            Text(label).font(.caption)
            Picker(
                "",
                selection: Binding(
                    get: { current },
                    set: { picked in
                        apply(editKey) { style in
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

    /// "" when unset everywhere, the shared keyword, or "…" when mixed.
    private func commonKeyword(_ name: String) -> String {
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

    // MARK: - Opacity

    private var opacityRow: some View {
        let value = styles.first?.opacity ?? 1
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Opacity").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int((value * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { styles.first?.opacity ?? 1 },
                    set: { v in
                        apply("opacity") { style in
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
    }

    // MARK: - Field sync

    private func syncFields() {
        if case .color(let r, let g, let b) = fillSummary {
            fillHex = String(format: "#%02x%02x%02x", r, g, b)
        } else {
            fillHex = ""
        }
        if case .color(let r, let g, let b) = strokeSummary {
            strokeHex = String(format: "#%02x%02x%02x", r, g, b)
        } else {
            strokeHex = ""
        }
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
