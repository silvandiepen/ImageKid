import ImageKidSculptorKit
import SwiftUI

/// A format the user can export the generated model in.
enum ExportFormat: String, CaseIterable, Identifiable {
    case glb
    case obj
    case stl
    case ply

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glb: "GLB"
        case .obj: "OBJ"
        case .stl: "STL"
        case .ply: "PLY"
        }
    }

    var detail: String {
        switch self {
        case .glb: "One self-contained file. Best for games, AR and the web."
        case .obj: "Widest compatibility. Opens in almost any 3D tool."
        case .stl: "For 3D printing. Geometry only, no colour."
        case .ply: "Raw geometry with per-vertex colour, for scanning tools."
        }
    }

    /// Whether the file carries the model's colour.
    var keepsColour: Bool { self != .stl }

    var fileExtension: String { rawValue }
}

/// Choices made in the export sheet.
struct ExportSettings: Equatable {
    var formats: Set<ExportFormat> = [.glb]
    /// Nil means keep the model exactly as generated.
    var triangleBudget: Int?
    var flatColour: Bool = true

    var isValid: Bool { !formats.isEmpty }

    /// Extra formats the worker must produce, beyond the GLB it always writes.
    var additionalFormats: [String] {
        formats.filter { $0 != .glb }.map(\.rawValue).sorted()
    }
}

/// Export options, shown before the save panel.
///
/// A plain save panel could only ever ask "where", which is the least
/// interesting question — the model is finished, and what a person actually
/// needs to decide is what they are taking away: which formats, how heavy, and
/// whether it keeps the flat cartoon colour or the sampled original.
struct ExportSheet: View {
    @Binding var settings: ExportSettings
    /// Triangle count of the model as generated, so the choices can be
    /// expressed relative to something real.
    let currentTriangles: Int
    var onCancel: () -> Void
    var onExport: () -> Void

    private var budgets: [(label: String, value: Int?)] {
        [
            ("As generated", nil),
            ("Light — 10k", 10_000),
            ("Medium — 25k", 25_000),
            ("Detailed — 60k", 60_000)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Export 3D Model")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                Text("Format").font(.headline)
                ForEach(ExportFormat.allCases) { format in
                    Toggle(isOn: binding(for: format)) {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(format.title)
                                if !format.keepsColour {
                                    Text("no colour")
                                        .font(.caption2)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(
                                            Capsule().fill(Color.secondary.opacity(0.18))
                                        )
                                }
                            }
                            Text(format.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Detail").font(.headline)
                Picker("Detail", selection: $settings.triangleBudget) {
                    ForEach(budgets, id: \.label) { budget in
                        Text(budget.label).tag(budget.value)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(
                    settings.triangleBudget == nil
                        ? "Keeps all \(currentTriangles.formatted()) triangles."
                        : "Re-exports at about "
                            + (settings.triangleBudget ?? 0).formatted()
                            + " triangles, from \(currentTriangles.formatted())."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Toggle("Flat cartoon colour", isOn: $settings.flatColour)
                    .padding(.top, 4)
                Text(
                    settings.flatColour
                        ? "A few solid colours with crisp edges."
                        : "The full range of colour sampled from the image."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                if !settings.isValid {
                    Label("Choose at least one format", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Export…", action: onExport)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!settings.isValid)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func binding(for format: ExportFormat) -> Binding<Bool> {
        Binding(
            get: { settings.formats.contains(format) },
            set: { isOn in
                if isOn {
                    settings.formats.insert(format)
                } else {
                    settings.formats.remove(format)
                }
            }
        )
    }
}
