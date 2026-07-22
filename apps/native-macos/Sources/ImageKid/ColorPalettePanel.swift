import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ImageKidKit

struct ColorPalettePanel: View {
    @EnvironmentObject private var library: ColorLibrary
    @ObservedObject var session: ImageSession
    @Binding var offset: CGSize
    let onClose: () -> Void

    @State private var expandedColorIDs: Set<UUID> = []
    @State private var detailColorID: UUID?
    @State private var panelSize = CGSize(width: 320, height: 460)
    @State private var extractCount = 6
    @State private var swipeOffsets: [UUID: CGFloat] = [:]

    var body: some View {
        FloatingToolPanel(
            title: "Picked Colours",
            systemImage: "paintpalette",
            offset: $offset,
            onClose: onClose,
            resizable: true,
            size: $panelSize
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text("\(session.sampledColors.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.58))
                    Spacer()
                    Menu {
                        ForEach([4, 6, 8, 12, 16], id: \.self) { count in
                            Button("Extract \(count) colours") {
                                extractCount = count
                                session.extractPalette(count: count)
                            }
                        }
                    } label: {
                        Label("Extract", systemImage: "wand.and.stars")
                    } primaryAction: {
                        session.extractPalette(count: extractCount)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Extract up to \(extractCount) dominant colours from the image")
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
                                swipeableRow(sample)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
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

    /// A colour row that can be swiped left to delete.
    private func swipeableRow(_ sample: SampledColor) -> some View {
        let dx = swipeOffsets[sample.id] ?? 0
        return ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.red.opacity(0.85))
                .overlay(alignment: .trailing) {
                    Image(systemName: "trash")
                        .foregroundStyle(.white)
                        .padding(.trailing, 20)
                }
            colorRow(sample)
                .background(
                    Color(red: 0.10, green: 0.10, blue: 0.11),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .offset(x: dx)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 14)
                        .onChanged { value in
                            if value.translation.width < 0 {
                                swipeOffsets[sample.id] = max(value.translation.width, -130)
                            }
                        }
                        .onEnded { value in
                            if value.translation.width < -70 {
                                withAnimation(.easeOut(duration: 0.16)) { swipeOffsets[sample.id] = -420 }
                                session.removeSamples([sample.id])
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                    swipeOffsets[sample.id] = 0
                                }
                            }
                        }
                )
        }
        .contextMenu {
            Menu("Add to Swatches") {
                ForEach(library.sets) { set in
                    Button(set.name) { library.addColor(sample.color, to: set.id) }
                }
            }
            Button("Remove", role: .destructive) { session.removeSamples([sample.id]) }
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
                    detailColorID = (detailColorID == sample.id) ? nil : sample.id
                } label: {
                    Image(systemName: "info.circle")
                        .frame(width: 26, height: 26)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Colour details")
                .accessibilityLabel("Colour details")
                .popover(
                    isPresented: Binding(
                        get: { detailColorID == sample.id },
                        set: { if !$0 { detailColorID = nil } }
                    ),
                    arrowEdge: .leading
                ) {
                    colorDetail(sample)
                        .frame(width: 250)
                        .padding(14)
                }
            }
            .padding(10)
        }
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func colorDetail(_ sample: SampledColor) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: sample.sRGB))
                    .frame(width: 44, height: 32)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.primary.opacity(0.2)))
                Spacer()
                ColorPicker("Adjust", selection: colorBinding(for: sample.id), supportsOpacity: true)
                    .labelsHidden()
            }
            valueRow("HEX", sample.hex)
            valueRow("RGB", sample.rgb)
            valueRow("RGBA", sample.rgba)
            valueRow("HSL", sample.hsl)
            valueRow("SwiftUI", sample.swiftUIColor)
            Divider()
            HStack {
                Menu("Add to Swatches") {
                    ForEach(library.sets) { set in
                        Button(set.name) { library.addColor(sample.color, to: set.id) }
                    }
                }
                Spacer()
                Button(role: .destructive) {
                    detailColorID = nil
                    session.removeSamples([sample.id])
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func valueRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
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
