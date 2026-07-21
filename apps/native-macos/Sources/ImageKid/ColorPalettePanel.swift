import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ImageKidKit

struct ColorPalettePanel: View {
    @ObservedObject var session: ImageSession
    @Binding var offset: CGSize
    let onClose: () -> Void

    @State private var expandedColorIDs: Set<UUID> = []

    var body: some View {
        FloatingToolPanel(
            title: "Picked Colours",
            systemImage: "paintpalette",
            width: 320,
            offset: $offset,
            onClose: onClose
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("\(session.sampledColors.count) saved")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.58))
                    Spacer()
                    Button {
                        session.extractPalette()
                    } label: {
                        Label("Extract", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderless)
                    .help("Extract dominant colours from the image")
                    if !session.sampledColors.isEmpty {
                        Button(session.selectedColorIDs.count == session.sampledColors.count ? "None" : "All") {
                            toggleAll()
                        }
                        .buttonStyle(.borderless)
                    }
                }

                if session.sampledColors.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "eyedropper")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                        Text("Press and drag over the image. Release to save the current colour.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.58))
                    }
                    .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(session.sampledColors) { sample in
                                colorRow(sample)
                            }
                        }
                    }
                    .frame(maxHeight: 390)
                }

                Rectangle()
                    .fill(.white.opacity(0.09))
                    .frame(height: 1)

                VStack(spacing: 9) {
                    Menu {
                        Button("HEX list") { copySelected(format: .hex) }
                        Button("RGB list") { copySelected(format: .rgb) }
                        Button("CSS variables") { copySelected(format: .css) }
                        Button("JSON") { copySelected(format: .json) }
                    } label: {
                        Label("Copy Selected", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .menuStyle(.button)
                    .disabled(selectedSamples.isEmpty)

                    Menu {
                        Button("Plain text…") { exportSelected(format: .hex) }
                        Button("CSS…") { exportSelected(format: .css) }
                        Button("JSON…") { exportSelected(format: .json) }
                    } label: {
                        Label("Export Selected", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .menuStyle(.button)
                    .disabled(selectedSamples.isEmpty)

                    Button(role: .destructive) {
                        session.removeSamples(session.selectedColorIDs)
                    } label: {
                        Label("Remove Selected", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedSamples.isEmpty)
                }
            }
            .darkPanelControl()
        }
    }

    @ViewBuilder
    private func colorRow(_ sample: SampledColor) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    toggleSelection(sample.id)
                } label: {
                    Image(systemName: session.selectedColorIDs.contains(sample.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(session.selectedColorIDs.contains(sample.id) ? Color.accentColor : .white.opacity(0.48))
                }
                .buttonStyle(.plain)
                .help(session.selectedColorIDs.contains(sample.id) ? "Deselect Colour" : "Select Colour")
                .accessibilityLabel(session.selectedColorIDs.contains(sample.id) ? "Deselect Colour" : "Select Colour")

                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color(nsColor: sample.sRGB))
                    .frame(width: 50, height: 38)
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(.white.opacity(0.16)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(sample.hex)
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                    Text(sample.rgb)
                        .font(.caption.monospaced())
                        .foregroundStyle(.white.opacity(0.52))
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        toggleExpanded(sample.id)
                    }
                } label: {
                    Image(systemName: expandedColorIDs.contains(sample.id) ? "chevron.up" : "chevron.down")
                        .frame(width: 26, height: 26)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .help(expandedColorIDs.contains(sample.id) ? "Collapse Colour Details" : "Expand Colour Details")
                .accessibilityLabel(expandedColorIDs.contains(sample.id) ? "Collapse Colour Details" : "Expand Colour Details")
            }
            .padding(10)

            if expandedColorIDs.contains(sample.id) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Adjust")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.62))
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

                    Button(role: .destructive) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            removeSample(sample.id)
                        }
                    } label: {
                        Label("Remove Colour", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 2)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func valueRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.52))
                .frame(width: 48, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button {
                copy(value)
            } label: {
                Image(systemName: "doc.on.doc")
                    .opacity(0.5)
            }
            .buttonStyle(.plain)
            .help("Copy \(label)")
            .accessibilityLabel("Copy \(label)")
        }
    }

    private var selectedSamples: [SampledColor] {
        session.sampledColors.filter { session.selectedColorIDs.contains($0.id) }
    }

    private func toggleAll() {
        if session.selectedColorIDs.count == session.sampledColors.count {
            session.selectedColorIDs.removeAll()
        } else {
            session.selectedColorIDs = Set(session.sampledColors.map(\.id))
        }
    }

    private func toggleSelection(_ id: UUID) {
        if session.selectedColorIDs.contains(id) {
            session.selectedColorIDs.remove(id)
        } else {
            session.selectedColorIDs.insert(id)
        }
    }

    private func toggleExpanded(_ id: UUID) {
        if expandedColorIDs.contains(id) {
            expandedColorIDs.remove(id)
        } else {
            expandedColorIDs.insert(id)
        }
    }

    private func removeSample(_ id: UUID) {
        session.removeSamples([id])
        expandedColorIDs.remove(id)
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
        copy(output(for: format))
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
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
