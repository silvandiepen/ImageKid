import AppKit
import FekthorKit
import SwiftUI

/// Workspace Settings (gallery gear / Workspace ▸ Workspace Settings…,
/// ⇧⌘,): icon size, grid, and drawing defaults. Empty fields stay UNSET in
/// the workfile — the engine's `.standard` fallback shows greyed as the
/// placeholder. Saving goes through `updateSettings`, which persists only
/// on real change.
struct WorkspaceSettingsSheet: View {
    @ObservedObject var session: WorkspaceSession
    @Environment(\.dismiss) private var dismiss

    @State private var widthText = ""
    @State private var heightText = ""
    @State private var spacingText = ""
    @State private var subdivisionsText = ""
    @State private var snap = false
    /// Grid line strength multiplier; 1 = the editor's standard look.
    @State private var gridStrength: Double = 1
    @State private var strokeHex = ""
    @State private var strokeWidthText = ""
    /// "" = unset (fallback), "none", or "color" (with `fillHex`).
    @State private var fillMode = ""
    @State private var fillHex = ""
    /// Guide icon entry id ("" = no guide) + visibility.
    @State private var guideIcon = ""
    @State private var showGuide = true

    private var std: Workfile.WorkspaceSettings { .standard }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Workspace Settings").font(.headline)
                Spacer()
                Text("empty fields use the greyed defaults")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 6)
            Form {
                Section("New icons") {
                    numberField("Width", text: $widthText, fallback: std.iconWidth)
                    numberField("Height", text: $heightText, fallback: std.iconHeight)
                }
                Section("Grid") {
                    numberField("Spacing", text: $spacingText, fallback: std.gridSpacing)
                    TextField(
                        "Subdivisions", text: $subdivisionsText,
                        prompt: Text("\(std.gridSubdivisions ?? 0)"))
                        .numericArrowKeys(text: $subdivisionsText, range: 0...64)
                    LabeledContent("Grid strength") {
                        HStack(spacing: 8) {
                            Slider(value: $gridStrength, in: 0.25...2.0)
                            Text(String(format: "%.0f%%", gridStrength * 100))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                    Toggle("Snap to grid  (⇧⌘')", isOn: $snap)
                }
                Section("Guide") {
                    Picker("Guide icon", selection: $guideIcon) {
                        Text("None").tag("")
                        ForEach(session.workspace?.entries ?? []) { entry in
                            Text(entry.id).tag(entry.id)
                        }
                    }
                    Toggle("Show guide behind icons  (⌥⌘G)", isOn: $showGuide)
                        .disabled(guideIcon.isEmpty)
                    Text("Any workspace SVG works — it draws dimmed under every icon in the editor, never in the files.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Section("Drawing defaults") {
                    LabeledContent("Stroke") {
                        HStack(spacing: 8) {
                            ColorPicker(
                                "", selection: hexColorBinding($strokeHex, fallback: "#010101"),
                                supportsOpacity: false
                            )
                            .labelsHidden()
                            TextField(
                                "", text: $strokeHex,
                                prompt: Text(std.defaultStrokeColor ?? "#010101")
                            )
                            .font(.caption.monospaced())
                            .frame(width: 80)
                        }
                    }
                    numberField(
                        "Stroke width", text: $strokeWidthText, fallback: std.defaultStrokeWidth)
                    Picker("Fill", selection: $fillMode) {
                        Text("Default (\(std.defaultFill ?? "none"))").tag("")
                        Text("None").tag("none")
                        Text("Colour").tag("color")
                    }
                    if fillMode == "color" {
                        LabeledContent("Fill colour") {
                            HStack(spacing: 8) {
                                ColorPicker(
                                    "", selection: hexColorBinding($fillHex, fallback: "#000000"),
                                    supportsOpacity: false
                                )
                                .labelsHidden()
                                TextField("", text: $fillHex, prompt: Text("#000000"))
                                    .font(.caption.monospaced())
                                    .frame(width: 80)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 440, height: 640)
        .onAppear(perform: load)
    }

    // MARK: - Field plumbing

    private func numberField(
        _ label: String, text: Binding<String>, fallback: Double?
    ) -> some View {
        TextField(label, text: text, prompt: Text(fallback.map(formatted) ?? ""))
            .numericArrowKeys(text: text, range: 0...4096)
    }

    private func formatted(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }

    /// A colour well over a hex text field: the well shows the field (or
    /// the fallback when empty) and writes back as #rrggbb.
    private func hexColorBinding(_ text: Binding<String>, fallback: String) -> Binding<Color> {
        Binding(
            get: {
                let raw = text.wrappedValue.isEmpty ? fallback : text.wrappedValue
                let hex = raw.hasPrefix("#") ? raw : "#" + raw
                guard let c = PaintValue.parseHex(hex) else { return .black }
                return Color(
                    red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
            },
            set: { color in
                let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
                text.wrappedValue = String(
                    format: "#%02x%02x%02x",
                    Int(max(0, min(255, ns.redComponent * 255))),
                    Int(max(0, min(255, ns.greenComponent * 255))),
                    Int(max(0, min(255, ns.blueComponent * 255))))
            })
    }

    // MARK: - Load / save

    private func load() {
        let raw = session.workspaceStandards
        widthText = raw?.iconWidth.map(formatted) ?? ""
        heightText = raw?.iconHeight.map(formatted) ?? ""
        spacingText = raw?.gridSpacing.map(formatted) ?? ""
        subdivisionsText = raw?.gridSubdivisions.map(String.init) ?? ""
        gridStrength = raw?.gridOpacity ?? std.gridOpacity ?? 1
        snap = raw?.snapToGrid ?? std.snapToGrid ?? false
        strokeHex = raw?.defaultStrokeColor ?? ""
        strokeWidthText = raw?.defaultStrokeWidth.map(formatted) ?? ""
        switch raw?.defaultFill {
        case nil:
            fillMode = ""
            fillHex = ""
        case "none":
            fillMode = "none"
            fillHex = ""
        case let hex?:
            fillMode = "color"
            fillHex = hex
        }
        guideIcon = raw?.guideIcon ?? ""
        showGuide = raw?.showGuide ?? true
    }

    private func save() {
        var built = session.workspaceStandards ?? Workfile.WorkspaceSettings()
        built.iconWidth = positiveNumber(widthText)
        built.iconHeight = positiveNumber(heightText)
        built.gridSpacing = positiveNumber(spacingText)
        built.gridSubdivisions = Int(subdivisionsText.trimmingCharacters(in: .whitespaces))
            .map { max(0, $0) }
        // A toggle cannot be "unset": keep nil while it still matches the
        // fallback and was never stored, so untouched files stay untouched.
        let storedSnap = session.workspaceStandards?.snapToGrid
        built.snapToGrid = (storedSnap == nil && snap == (std.snapToGrid ?? false)) ? nil : snap
        // Same unset discipline for the slider: stay nil while it was never
        // stored and still sits on the standard strength.
        let storedStrength = session.workspaceStandards?.gridOpacity
        built.gridOpacity =
            (storedStrength == nil && abs(gridStrength - (std.gridOpacity ?? 1)) < 0.005)
            ? nil : gridStrength
        built.defaultStrokeColor = normalizedHex(strokeHex)
        built.defaultStrokeWidth = positiveNumber(strokeWidthText)
        switch fillMode {
        case "none":
            built.defaultFill = "none"
        case "color":
            built.defaultFill = normalizedHex(fillHex)
        default:
            built.defaultFill = nil
        }
        // No guide, no flags: both fields collapse together so untouched
        // workfiles never gain a stored `showGuide`.
        built.guideIcon = guideIcon.isEmpty ? nil : guideIcon
        built.showGuide = guideIcon.isEmpty ? nil : showGuide
        session.updateSettings { workfile in
            workfile.settings = built
        }
    }

    private func positiveNumber(_ text: String) -> Double? {
        guard let v = Double(text.trimmingCharacters(in: .whitespaces)), v > 0 else {
            return nil
        }
        return v
    }

    private func normalizedHex(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let hex = trimmed.hasPrefix("#") ? trimmed : "#" + trimmed
        return PaintValue.parseHex(hex) != nil ? hex.lowercased() : nil
    }
}
