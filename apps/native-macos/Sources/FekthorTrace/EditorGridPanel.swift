import AppKit
import FekthorKit
import SwiftUI

/// The grid's shared look, used by the canvas draw AND the palette preview
/// so they can never drift apart: the standard slate blue-grey line colour
/// (overridable per grid) and the clamped alpha formula the opacity
/// multiplier feeds.
enum GridLook {
    /// The standard slate blue-grey — reads better on the white artboard
    /// than pure gray.
    static let standardColor = Color(red: 0.42, green: 0.47, blue: 0.58)

    static func lineColor(hex: String?) -> Color {
        guard let hex, let c = PaintValue.parseHex(hex) else { return standardColor }
        return Color(
            red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
    }

    /// Line alphas for an opacity multiplier (1 = standard), clamped so
    /// cranked-up grids never overwhelm the artwork.
    static func alphas(opacity: Double) -> (major: Double, sub: Double) {
        let strength = max(0, opacity)
        return (min(0.45, 0.22 * strength), min(0.45, 0.12 * strength))
    }
}

/// One grid configuration: spacing, subdivisions, line opacity and colour.
/// The palette edits one of these; a preset is a named copy. Visibility and
/// snap stay live toggles (⌘' / ⇧⌘') — they are how you work, not which
/// grid you use.
struct GridValues: Equatable {
    var spacing: Double
    var subdivisions: Int
    var opacity: Double
    /// "#rrggbb"; nil = the standard slate blue-grey.
    var color: String?
}

/// A named grid configuration the Grid Presets palette applies in one click.
struct GridPreset: Codable, Equatable, Identifiable {
    var name: String
    var spacing: Double
    var subdivisions: Int
    var opacity: Double
    var color: String?

    // "strength" stays the stored key for opacity — presets saved before
    // the rename must keep decoding.
    private enum CodingKeys: String, CodingKey {
        case name, spacing, subdivisions, color
        case opacity = "strength"
    }

    var id: String { name }

    var values: GridValues {
        GridValues(spacing: spacing, subdivisions: subdivisions, opacity: opacity, color: color)
    }

    /// Compact "8 pt ÷ 4" detail shown next to the name.
    var detail: String {
        var out = NumericField.format(spacing) + " pt"
        if subdivisions > 0 { out += " ÷ \(subdivisions)" }
        if abs(opacity - 1) >= 0.005 {
            out += String(format: " · %.0f%%", opacity * 100)
        }
        return out
    }

    func matches(_ v: GridValues) -> Bool {
        abs(spacing - v.spacing) < 0.001 && subdivisions == v.subdivisions
            && abs(opacity - v.opacity) < 0.005 && color == v.color
    }
}

/// App-global grid state the Grid palettes own: the user's saved presets
/// (available in every workspace) and the grid DETACHED editors use — with
/// a workspace open the grid lives in the workfile instead, shared like
/// swatches. Both persist through `AppDefaults`.
@MainActor
final class GridPresetStore: ObservableObject {
    static let shared = GridPresetStore()

    /// Starting points for the 24pt icon artboards new icons default to.
    static let builtins: [GridPreset] = [
        GridPreset(name: "1 pt", spacing: 1, subdivisions: 0, opacity: 1),
        GridPreset(name: "2 pt", spacing: 2, subdivisions: 2, opacity: 1),
        GridPreset(name: "4 pt", spacing: 4, subdivisions: 4, opacity: 1),
        GridPreset(name: "8 pt", spacing: 8, subdivisions: 4, opacity: 1),
    ]

    /// The grid for editors opened WITHOUT a workspace (plain SVGs) —
    /// nothing on disk to keep it in, so it persists app-globally.
    /// ("strength" stays the stored key for opacity, as in GridPreset.)
    struct DetachedGrid: Codable, Equatable {
        var spacing: Double = 1
        var subdivisions: Int = 0
        var opacity: Double = 1
        var color: String? = nil

        private enum CodingKeys: String, CodingKey {
            case spacing, subdivisions, color
            case opacity = "strength"
        }
    }

    @Published private(set) var userPresets: [GridPreset] {
        didSet {
            guard let data = try? JSONEncoder().encode(userPresets) else { return }
            AppDefaults.store.set(data, forKey: Self.presetsKey)
        }
    }

    @Published var detached: DetachedGrid {
        didSet {
            guard let data = try? JSONEncoder().encode(detached) else { return }
            AppDefaults.store.set(data, forKey: Self.detachedKey)
        }
    }

    private static let presetsKey = "fekthor.gridPresets"
    private static let detachedKey = "fekthor.detachedGrid"

    private init() {
        if let data = AppDefaults.store.data(forKey: Self.presetsKey),
            let decoded = try? JSONDecoder().decode([GridPreset].self, from: data)
        {
            userPresets = decoded
        } else {
            userPresets = []
        }
        if let data = AppDefaults.store.data(forKey: Self.detachedKey),
            let decoded = try? JSONDecoder().decode(DetachedGrid.self, from: data)
        {
            detached = decoded
        } else {
            detached = DetachedGrid()
        }
    }

    /// Save (or overwrite the same-named) user preset.
    func save(_ preset: GridPreset) {
        if let i = userPresets.firstIndex(where: { $0.name == preset.name }) {
            userPresets[i] = preset
        } else {
            userPresets.append(preset)
        }
    }

    func remove(named name: String) {
        userPresets.removeAll { $0.name == name }
    }
}

/// The single read/write path both grid palettes share: the workfile with a
/// workspace open (shared, like swatches — the Workspace Settings sheet
/// edits the same fields), the app-global store without one.
@MainActor
private struct GridAccess {
    let workspace: WorkspaceSession
    let store: GridPresetStore

    var current: GridValues {
        if workspace.workspace != nil {
            let std = workspace.effectiveStandards
            return GridValues(
                spacing: std.gridSpacing ?? 1,
                subdivisions: std.gridSubdivisions ?? 0,
                opacity: std.gridOpacity ?? 1,
                color: std.gridColor)
        }
        let d = store.detached
        return GridValues(
            spacing: d.spacing, subdivisions: d.subdivisions, opacity: d.opacity,
            color: d.color)
    }

    func apply(_ v: GridValues) {
        if workspace.workspace != nil {
            workspace.updateSettings { workfile in
                var s = workfile.settings ?? Workfile.WorkspaceSettings()
                s.gridSpacing = v.spacing
                s.gridSubdivisions = v.subdivisions
                s.gridOpacity = v.opacity
                s.gridColor = v.color
                workfile.settings = s
            }
        } else {
            store.detached = GridPresetStore.DetachedGrid(
                spacing: v.spacing, subdivisions: v.subdivisions, opacity: v.opacity,
                color: v.color)
        }
    }

    /// Applying a preset while the grid is hidden also shows it — an
    /// invisible change reads as a broken button.
    func apply(_ preset: GridPreset) {
        apply(preset.values)
        if !MenuState.shared.showGrid { MenuState.shared.showGrid = true }
    }
}

// MARK: - Grid palette

/// The Grid palette: a collapsible live preview, the Show/Snap switches
/// (the same state ⌘'/⇧⌘' drive), spacing + subdivisions side by side,
/// line opacity and colour — and a button into the Grid Presets palette.
struct GridPanelContent: View {
    @ObservedObject var workspace: WorkspaceSession
    @ObservedObject private var menuState = MenuState.shared
    @ObservedObject private var store = GridPresetStore.shared
    @ObservedObject private var panels = EditorPanelsState.shared

    @State private var spacingText = ""
    @State private var subdivisionsText = ""
    @State private var opacity: Double = 1
    @AppStorage("fekthor.gridPreviewCollapsed", store: AppDefaults.store)
    private var previewCollapsed = false

    static let spacingRange = 0.1...256.0
    static let subdivisionsRange = 0.0...12.0
    static let opacityRange = 0.25...2.0

    private var access: GridAccess { GridAccess(workspace: workspace, store: store) }

    /// External-change token: an edit from the settings sheet, a preset
    /// click or a workspace switch re-syncs the fields.
    private var syncKey: String {
        let cur = access.current
        return "\(cur.spacing)|\(cur.subdivisions)|\(cur.opacity)|\(cur.color ?? "-")|\(workspace.workspace != nil)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            previewHeader
            if !previewCollapsed {
                GridPreviewSwatch(values: access.current, artboardUnits: artboardUnits)
            }
            Divider()
            HStack(spacing: 12) {
                Toggle("Show", isOn: $menuState.showGrid)
                    .help("Show the grid (⌘')")
                    .accessibilityIdentifier("grid.show")
                Toggle(
                    "Snap",
                    isOn: Binding(
                        get: { menuState.snapToGrid },
                        set: { _ in
                            NotificationCenter.default.post(
                                name: .fekthorToggleSnap, object: nil)
                        })
                )
                .help("Snap to the grid (⇧⌘')")
                .accessibilityIdentifier("grid.snap")
            }
            .font(.caption)
            .toggleStyle(.switch)
            .controlSize(.mini)
            Divider()
            HStack(alignment: .top, spacing: 8) {
                labeledField(
                    "Spacing", text: $spacingText, range: Self.spacingRange,
                    identifier: "grid.spacing"
                ) { v in
                    change { $0.spacing = clamp(v, to: Self.spacingRange) }
                }
                labeledField(
                    "Subdivide", text: $subdivisionsText, range: Self.subdivisionsRange,
                    identifier: "grid.subdivisions"
                ) { v in
                    change {
                        $0.subdivisions = Int(clamp(v.rounded(), to: Self.subdivisionsRange))
                    }
                }
            }
            opacityRow
            colorRow
            Divider()
            presetsButton
        }
        .onAppear { sync() }
        .onChange(of: syncKey) { sync() }
    }

    /// The preview scales to the workspace's artboard width so it shows the
    /// grid as new icons will actually wear it.
    private var artboardUnits: Double {
        workspace.effectiveStandards.iconWidth ?? 24
    }

    // MARK: Rows

    private var previewHeader: some View {
        Button {
            previewCollapsed.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: previewCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                Text("Preview")
                    .font(.caption)
                Spacer()
                PanelInfoButton(
                    text: workspace.workspace != nil
                        ? "Grid changes save into the workspace's workfile, shared like swatches. The preview is scaled to the workspace artboard."
                        : "No workspace open — grid changes are kept app-wide."
                )
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(previewCollapsed ? "Show the grid preview" : "Hide the grid preview")
        .accessibilityIdentifier("grid.previewToggle")
    }

    private func labeledField(
        _ label: String, text: Binding<String>, range: ClosedRange<Double>,
        identifier: String, onCommit: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            NumericField(text: text, step: 1, range: range, onCommit: onCommit)
                .accessibilityIdentifier(identifier)
        }
    }

    private var opacityRow: some View {
        HStack(spacing: 8) {
            Text("Opacity")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            Slider(value: $opacity, in: Self.opacityRange) { editing in
                if !editing { change { $0.opacity = opacity } }
            }
            .accessibilityIdentifier("grid.opacity")
            Text(String(format: "%.0f%%", opacity * 100))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
    }

    private var colorRow: some View {
        let custom = access.current.color != nil
        return HStack(spacing: 8) {
            Text("Color")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            ColorPicker(
                "",
                selection: Binding(
                    get: { GridLook.lineColor(hex: access.current.color) },
                    set: { picked in change { $0.color = hex(from: picked) } }),
                supportsOpacity: false
            )
            .labelsHidden()
            .controlSize(.small)
            .accessibilityIdentifier("grid.color")
            Spacer()
            if custom {
                Button {
                    change { $0.color = nil }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 18, height: 18)
                        .background(
                            .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                        .contentShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("Back to the standard grid colour")
                .accessibilityIdentifier("grid.colorReset")
            }
        }
    }

    private var presetsButton: some View {
        Button {
            panels.railToggle(.gridPresets)
        } label: {
            HStack {
                Image(systemName: "square.grid.3x3")
                    .font(.system(size: 10, weight: .medium))
                Text("Presets…")
                    .font(.caption)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                .white.opacity(panels.isExpanded(.gridPresets) ? 0.18 : 0.08),
                in: RoundedRectangle(cornerRadius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help("Open the Grid Presets palette")
        .accessibilityIdentifier("grid.openPresets")
    }

    // MARK: Apply / sync

    private func change(_ edit: (inout GridValues) -> Void) {
        var v = access.current
        edit(&v)
        access.apply(v)
        sync()
    }

    private func sync() {
        let cur = access.current
        spacingText = NumericField.format(cur.spacing)
        subdivisionsText = String(cur.subdivisions)
        opacity = cur.opacity
    }

    private func hex(from color: Color) -> String {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return String(
            format: "#%02x%02x%02x",
            Int(round(ns.redComponent * 255)),
            Int(round(ns.greenComponent * 255)),
            Int(round(ns.blueComponent * 255)))
    }

    private func clamp(_ v: Double, to range: ClosedRange<Double>) -> Double {
        min(max(v, range.lowerBound), range.upperBound)
    }
}

/// A small white artboard swatch wearing the current grid — spacing scaled
/// to the workspace's artboard width, subdivisions, colour and opacity all
/// live, using the same alpha formula as the canvas draw.
private struct GridPreviewSwatch: View {
    var values: GridValues
    var artboardUnits: Double

    var body: some View {
        Canvas { ctx, size in
            let shape = Path(
                roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 6)
            ctx.fill(shape, with: .color(.white))
            ctx.clip(to: shape)
            let scale = size.width / max(1, artboardUnits)
            let majorPx = values.spacing * scale
            guard majorPx >= 2 else { return }
            let line = GridLook.lineColor(hex: values.color)
            let (majorAlpha, subAlpha) = GridLook.alphas(opacity: values.opacity)
            let subs = max(0, values.subdivisions)
            if subs > 0 {
                let subStep = majorPx / Double(subs + 1)
                if subStep >= 2.5 {
                    var p = Path()
                    addLines(&p, step: subStep, skipEvery: subs + 1, in: size)
                    ctx.stroke(p, with: .color(line.opacity(subAlpha)), lineWidth: 0.5)
                }
            }
            var p = Path()
            addLines(&p, step: majorPx, skipEvery: 0, in: size)
            ctx.stroke(p, with: .color(line.opacity(majorAlpha)), lineWidth: 0.5)
        }
        .frame(height: 84)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.white.opacity(0.25), lineWidth: 1))
        .accessibilityIdentifier("grid.preview")
    }

    private func addLines(_ p: inout Path, step: Double, skipEvery: Int, in size: CGSize) {
        var i = 0
        while true {
            let x = Double(i) * step
            if x > size.width + 1e-9 { break }
            if skipEvery == 0 || i % skipEvery != 0 {
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x, y: size.height))
            }
            i += 1
        }
        i = 0
        while true {
            let y = Double(i) * step
            if y > size.height + 1e-9 { break }
            if skipEvery == 0 || i % skipEvery != 0 {
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
            }
            i += 1
        }
    }
}

// MARK: - Grid Presets palette

/// The Grid Presets palette, opened from the Grid palette (or the rail /
/// Panels menu): built-ins first, then the user's own, saved with "+".
/// Clicking a preset applies it (and shows the grid if it was hidden); the
/// one matching the current grid is highlighted. Right-click a saved preset
/// to overwrite it with the current grid or delete it.
struct GridPresetsPanelContent: View {
    @ObservedObject var workspace: WorkspaceSession
    @ObservedObject private var store = GridPresetStore.shared

    @State private var savePopoverShown = false
    @State private var newPresetName = ""

    private var access: GridAccess { GridAccess(workspace: workspace, store: store) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Presets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                PanelInfoButton(
                    text:
                        "A preset stores spacing, subdivide, opacity and colour — app-wide, so it works in every workspace. + saves the current grid; right-click a saved preset to overwrite or delete it."
                )
                Spacer()
                addButton
            }
            VStack(spacing: 2) {
                ForEach(GridPresetStore.builtins) { preset in
                    presetRow(preset, editable: false)
                }
                ForEach(store.userPresets) { preset in
                    presetRow(preset, editable: true)
                }
            }
        }
    }

    private func presetRow(_ preset: GridPreset, editable: Bool) -> some View {
        let active = preset.matches(access.current)
        return Button {
            access.apply(preset)
        } label: {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(GridLook.lineColor(hex: preset.color))
                    .frame(width: 8, height: 8)
                    .opacity(preset.color == nil ? 0.5 : 1)
                Text(preset.name)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Text(preset.detail)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                .white.opacity(active ? 0.18 : 0.05),
                in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("Apply \(preset.name) (\(preset.detail))")
        .accessibilityIdentifier("grid.preset.\(preset.name)")
        .contextMenu {
            Button("Apply") { access.apply(preset) }
            if editable {
                Button("Overwrite with Current Grid") {
                    store.save(currentPreset(named: preset.name))
                }
                Divider()
                Button("Delete", role: .destructive) { store.remove(named: preset.name) }
            }
        }
    }

    private var addButton: some View {
        Button {
            newPresetName = suggestedName
            savePopoverShown = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 20)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("Save the current grid as a preset")
        .accessibilityIdentifier("grid.addPreset")
        .popover(isPresented: $savePopoverShown, arrowEdge: .bottom) {
            savePresetForm
        }
    }

    private var savePresetForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Save grid preset")
                .font(.caption.weight(.semibold))
            TextField("Name", text: $newPresetName)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .frame(width: 160)
                .onSubmit { savePreset() }
                .accessibilityIdentifier("grid.presetName")
            HStack {
                Spacer()
                Button("Save") { savePreset() }
                    .disabled(
                        newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("grid.savePreset")
            }
        }
        .padding(12)
    }

    /// "8 pt ÷ 4"-style default name from the current values.
    private var suggestedName: String {
        let cur = access.current
        var name = NumericField.format(cur.spacing) + " pt"
        if cur.subdivisions > 0 { name += " ÷ \(cur.subdivisions)" }
        return name
    }

    private func currentPreset(named name: String) -> GridPreset {
        let cur = access.current
        return GridPreset(
            name: name, spacing: cur.spacing, subdivisions: cur.subdivisions,
            opacity: cur.opacity, color: cur.color)
    }

    private func savePreset() {
        let name = newPresetName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        store.save(currentPreset(named: name))
        savePopoverShown = false
    }
}
