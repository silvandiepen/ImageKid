import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ColorPalettePanel: View {
    @ObservedObject var session: ImageSession
    @State private var expandedColorIDs: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Picked Colours", systemImage: "paintpalette")
                    .font(.headline)
                Spacer()
                Text("\(session.sampledColors.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if session.sampledColors.isEmpty {
                ContentUnavailableView(
                    "No colours yet",
                    systemImage: "eyedropper",
                    description: Text("Press and drag over the image, then release to save a colour.")
                )
                .frame(height: 150)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(session.sampledColors) { sample in
                            colorRow(sample)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }

            Divider()

            HStack(spacing: 8) {
                Button(session.selectedColorIDs.count == session.sampledColors.count ? "None" : "All") {
                    if session.selectedColorIDs.count == session.sampledColors.count {
                        session.selectedColorIDs.removeAll()
                    } else {
                        session.selectedColorIDs = Set(session.sampledColors.map(\.id))
                    }
                }

                Spacer()

                Menu {
                    Button("HEX list") { copySelected(format: .hex) }
                    Button("RGB list") { copySelected(format: .rgb) }
                    Button("CSS variables") { copySelected(format: .css) }
                    Button("JSON") { copySelected(format: .json) }
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(selectedSamples.isEmpty)

                Menu {
                    Button("Plain text…") { exportSelected(format: .hex) }
                    Button("CSS…") { exportSelected(format: .css) }
                    Button("JSON…") { exportSelected(format: .json) }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(selectedSamples.isEmpty)

                Button(role: .destructive) {
                    session.removeSamples(session.selectedColorIDs)
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(selectedSamples.isEmpty)
                .help("Remove selected colours")
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 330)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.14))
        )
        .shadow(color: .black.opacity(0.22), radius: 20, y: 8)
    }

    @ViewBuilder
    private func colorRow(_ sample: SampledColor) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    toggleSelection(sample.id)
                } label: {
                    Image(systemName: session.selectedColorIDs.contains(sample.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(session.selectedColorIDs.contains(sample.id) ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: sample.sRGB))
                    .frame(width: 42, height: 32)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.primary.opacity(0.14)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(sample.hex)
                        .font(.system(.body, design: .monospaced, weight: .medium))
                    Text(sample.rgb)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if expandedColorIDs.contains(sample.id) {
                            expandedColorIDs.remove(sample.id)
                        } else {
                            expandedColorIDs.insert(sample.id)
                        }
                    }
                } label: {
                    Image(systemName: expandedColorIDs.contains(sample.id) ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.plain)
            }
            .padding(8)
            .contentShape(Rectangle())

            if expandedColorIDs.contains(sample.id) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("Adjust")
                            .foregroundStyle(.secondary)
                        Spacer()
                        ColorPicker(
                            "Adjust colour",
                            selection: colorBinding(for: sample.id),
                            supportsOpacity: true
                        )
                        .labelsHidden()
                    }

                    valueRow("HEX", sample.hex)
                    valueRow("RGB", sample.rgb)
                    valueRow("RGBA", sample.rgba)
                    valueRow("HSL", sample.hsl)
                    valueRow("SwiftUI", sample.swiftUIColor)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func valueRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
        }
    }

    private var selectedSamples: [SampledColor] {
        session.sampledColors.filter { session.selectedColorIDs.contains($0.id) }
    }

    private func toggleSelection(_ id: UUID) {
        if session.selectedColorIDs.contains(id) {
            session.selectedColorIDs.remove(id)
        } else {
            session.selectedColorIDs.insert(id)
        }
    }

    private func colorBinding(for id: UUID) -> Binding<Color> {
        Binding(
            get: {
                let color = session.sampledColors.first(where: { $0.id == id })?.color ?? .clear
                return Color(nsColor: color)
            },
            set: { session.updateSample(id: id, color: NSColor($0)) }
        )
    }

    private enum OutputFormat {
        case hex
        case rgb
        case css
        case json
    }

    private func output(for format: OutputFormat) -> String {
        switch format {
        case .hex:
            return selectedSamples.map(\.hex).joined(separator: "\n")
        case .rgb:
            return selectedSamples.map(\.rgb).joined(separator: "\n")
        case .css:
            return selectedSamples.enumerated().map { index, color in
                "--color-\(index + 1): \(color.hex);"
            }.joined(separator: "\n")
        case .json:
            let entries = selectedSamples.enumerated().map { index, color in
                "  \"color-\(index + 1)\": \"\(color.hex)\""
            }.joined(separator: ",\n")
            return "{\n\(entries)\n}"
        }
    }

    private func copySelected(format: OutputFormat) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output(for: format), forType: .string)
    }

    private func exportSelected(format: OutputFormat) {
        let panel = NSSavePanel()
        switch format {
        case .hex, .rgb:
            panel.allowedContentTypes = [.plainText]
            panel.nameFieldStringValue = "ImageKid-colors.txt"
        case .css:
            panel.allowedContentTypes = [UTType(filenameExtension: "css") ?? .plainText]
            panel.nameFieldStringValue = "ImageKid-colors.css"
        case .json:
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "ImageKid-colors.json"
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? output(for: format).write(to: url, atomically: true, encoding: .utf8)
    }
}
