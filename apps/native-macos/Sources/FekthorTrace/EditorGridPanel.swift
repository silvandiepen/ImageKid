import FekthorKit
import SwiftUI

/// A named grid configuration the Grid palette applies in one click:
/// spacing, subdivisions and line strength. Visibility and snap stay live
/// toggles (⌘' / ⇧⌘') — they are how you work, not which grid you use.
struct GridPreset: Codable, Equatable, Identifiable {
    var name: String
    var spacing: Double
    var subdivisions: Int
    var strength: Double

    var id: String { name }

    /// Compact "8 pt ÷ 4" detail shown next to the name.
    var detail: String {
        var out = NumericField.format(spacing) + " pt"
        if subdivisions > 0 { out += " ÷ \(subdivisions)" }
        if abs(strength - 1) >= 0.005 {
            out += String(format: " · %.0f%%", strength * 100)
        }
        return out
    }

    func matches(spacing: Double, subdivisions: Int, strength: Double) -> Bool {
        abs(self.spacing - spacing) < 0.001
            && self.subdivisions == subdivisions
            && abs(self.strength - strength) < 0.005
    }
}

/// App-global grid state the Grid palette owns: the user's saved presets
/// (available in every workspace) and the grid DETACHED editors use — with
/// a workspace open the grid lives in the workfile instead, shared like
/// swatches. Both persist through `AppDefaults`.
@MainActor
final class GridPresetStore: ObservableObject {
    static let shared = GridPresetStore()

    /// Starting points for the 24pt icon artboards new icons default to.
    static let builtins: [GridPreset] = [
        GridPreset(name: "1 pt", spacing: 1, subdivisions: 0, strength: 1),
        GridPreset(name: "2 pt", spacing: 2, subdivisions: 2, strength: 1),
        GridPreset(name: "4 pt", spacing: 4, subdivisions: 4, strength: 1),
        GridPreset(name: "8 pt", spacing: 8, subdivisions: 4, strength: 1),
    ]

    /// The grid for editors opened WITHOUT a workspace (plain SVGs) —
    /// nothing on disk to keep it in, so it persists app-globally.
    struct DetachedGrid: Codable, Equatable {
        var spacing: Double = 1
        var subdivisions: Int = 0
        var strength: Double = 1
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

// MARK: - Grid palette

/// The Grid palette: the live Show/Snap toggles (the same state ⌘'/⇧⌘'
/// drive), the grid's spacing, subdivisions and strength, and one-click
/// presets — built-ins first, then the user's own, saved with "+". With a
/// workspace open edits persist through the workfile (the Workspace
/// Settings sheet edits the same fields); detached editors keep theirs
/// app-globally in the preset store.
struct GridPanelContent: View {
    @ObservedObject var workspace: WorkspaceSession
    @ObservedObject private var menuState = MenuState.shared
    @ObservedObject private var store = GridPresetStore.shared

    @State private var spacingText = ""
    @State private var subdivisionsText = ""
    @State private var strength: Double = 1
    @State private var savePopoverShown = false
    @State private var newPresetName = ""

    private static let spacingRange = 0.1...256.0
    private static let subdivisionsRange = 0.0...12.0
    private static let strengthRange = 0.25...2.0

    /// The values the canvas currently draws with.
    private var current: (spacing: Double, subdivisions: Int, strength: Double) {
        if workspace.workspace != nil {
            let std = workspace.effectiveStandards
            return (std.gridSpacing ?? 1, std.gridSubdivisions ?? 0, std.gridOpacity ?? 1)
        }
        return (store.detached.spacing, store.detached.subdivisions, store.detached.strength)
    }

    /// External-change token: any edit from the settings sheet, another
    /// preset or a workspace switch re-syncs the fields.
    private var syncKey: String {
        let cur = current
        return "\(cur.spacing)|\(cur.subdivisions)|\(cur.strength)|\(workspace.workspace != nil)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
            numberRow(
                "Spacing", text: $spacingText, range: Self.spacingRange,
                identifier: "grid.spacing"
            ) { v in
                applyGrid(spacing: clamp(v, to: Self.spacingRange))
            }
            numberRow(
                "Subdivide", text: $subdivisionsText, range: Self.subdivisionsRange,
                identifier: "grid.subdivisions"
            ) { v in
                applyGrid(subdivisions: Int(clamp(v.rounded(), to: Self.subdivisionsRange)))
            }
            strengthRow
            Divider()
            HStack {
                Text("Presets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            Text(
                workspace.workspace != nil
                    ? "Grid changes save into the workspace."
                    : "No workspace open — the grid is kept app-wide."
            )
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .onAppear { sync() }
        .onChange(of: syncKey) { sync() }
    }

    // MARK: Rows

    private func numberRow(
        _ label: String, text: Binding<String>, range: ClosedRange<Double>,
        identifier: String, onCommit: @escaping (Double) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            NumericField(text: text, step: 1, range: range, onCommit: onCommit)
                .accessibilityIdentifier(identifier)
        }
    }

    private var strengthRow: some View {
        HStack(spacing: 8) {
            Text("Strength")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            Slider(value: $strength, in: Self.strengthRange) { editing in
                if !editing { applyGrid(strength: strength) }
            }
            .accessibilityIdentifier("grid.strength")
            Text(String(format: "%.0f%%", strength * 100))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
    }

    // MARK: Presets

    private func presetRow(_ preset: GridPreset, editable: Bool) -> some View {
        let cur = current
        let active = preset.matches(
            spacing: cur.spacing, subdivisions: cur.subdivisions, strength: cur.strength)
        return Button {
            apply(preset)
        } label: {
            HStack {
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
            Button("Apply") { apply(preset) }
            if editable {
                Button("Overwrite with Current Grid") {
                    let cur = current
                    store.save(
                        GridPreset(
                            name: preset.name, spacing: cur.spacing,
                            subdivisions: cur.subdivisions, strength: cur.strength))
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
        let cur = current
        var name = NumericField.format(cur.spacing) + " pt"
        if cur.subdivisions > 0 { name += " ÷ \(cur.subdivisions)" }
        return name
    }

    private func savePreset() {
        let name = newPresetName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let cur = current
        store.save(
            GridPreset(
                name: name, spacing: cur.spacing, subdivisions: cur.subdivisions,
                strength: cur.strength))
        savePopoverShown = false
    }

    // MARK: Apply

    /// Applying a preset while the grid is hidden also shows it — an
    /// invisible change reads as a broken button.
    private func apply(_ preset: GridPreset) {
        applyGrid(
            spacing: preset.spacing, subdivisions: preset.subdivisions,
            strength: preset.strength)
        if !menuState.showGrid { menuState.showGrid = true }
    }

    /// The single write path for grid values: the workfile with a workspace
    /// open (shared, like swatches), the app-global store without one.
    private func applyGrid(
        spacing: Double? = nil, subdivisions: Int? = nil, strength: Double? = nil
    ) {
        if workspace.workspace != nil {
            workspace.updateSettings { workfile in
                var s = workfile.settings ?? Workfile.WorkspaceSettings()
                if let spacing { s.gridSpacing = spacing }
                if let subdivisions { s.gridSubdivisions = subdivisions }
                if let strength { s.gridOpacity = strength }
                workfile.settings = s
            }
        } else {
            if let spacing { store.detached.spacing = spacing }
            if let subdivisions { store.detached.subdivisions = subdivisions }
            if let strength { store.detached.strength = strength }
        }
        sync()
    }

    private func sync() {
        let cur = current
        spacingText = NumericField.format(cur.spacing)
        subdivisionsText = String(cur.subdivisions)
        strength = cur.strength
    }

    private func clamp(_ v: Double, to range: ClosedRange<Double>) -> Double {
        min(max(v, range.lowerBound), range.upperBound)
    }
}
