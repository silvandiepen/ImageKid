import AppKit
import SwiftUI
import ImageKidKit
import UniformTypeIdentifiers

/// Colour swatch library: sets of reusable colours. The base set also drives the
/// default colours offered to shapes, lines, and text.
struct SwatchesPanel: View {
    @EnvironmentObject private var library: ColorLibrary
    @Binding var offset: CGSize
    @Binding var size: CGSize
    let onMinimize: () -> Void
    let onPick: (NSColor) -> Void

    @State private var newColor = Color.white
    @State private var targetSetID: UUID?
    @State private var editingSetID: UUID?
    @State private var editingName = ""

    private let columns = [GridItem(.adaptive(minimum: 28, maximum: 34), spacing: 6)]

    var body: some View {
        FloatingToolPanel(
            title: "Swatches",
            systemImage: "swatchpalette",
            offset: $offset,
            onMinimize: onMinimize,
            resizable: true,
            size: $size,
            contentPadding: 0
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(library.sets) { set in
                            setSection(set)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .thinScrollbars()
                }
                .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 10) {
                    Rectangle().fill(.white.opacity(0.09)).frame(height: 1)

                    HStack(spacing: 8) {
                        ColorPicker("New swatch", selection: $newColor, supportsOpacity: true)
                            .labelsHidden()
                        Button {
                            library.addColor(NSColor(newColor), to: currentTargetSetID)
                        } label: {
                            Label("Add", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                        Button {
                            targetSetID = library.addSet()
                        } label: {
                            Label("Set", systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.bordered)
                        .help("New swatch set")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .darkPanelControl()
        }
    }

    private var currentTargetSetID: UUID {
        if let targetSetID, library.sets.contains(where: { $0.id == targetSetID }) { return targetSetID }
        return library.baseSet?.id ?? library.sets.first?.id ?? UUID()
    }

    @ViewBuilder
    private func setSection(_ set: SwatchSet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if editingSetID == set.id {
                    TextField("", text: $editingName)
                        .textFieldStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .onSubmit { library.renameSet(set.id, to: editingName); editingSetID = nil }
                } else {
                    Text(set.name.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .onTapGesture(count: 2) { editingName = set.name; editingSetID = set.id }
                }
                if set.isBase {
                    Text("BASE")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.3), in: Capsule())
                }
                Spacer()
                Circle().fill(currentTargetSetID == set.id ? Color.accentColor : .clear)
                    .frame(width: 6, height: 6)
                Button { targetSetID = set.id } label: { Image(systemName: "target").font(.system(size: 10)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.5))
                    .help("Add new swatches to this set")
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(set.colors) { swatch in
                    swatchTile(swatch, in: set)
                }
            }
        }
        .contextMenu {
            Button("Copy Hex List") { copyHexList(set) }
            Button("Export Set…") { exportSet(set) }
            if !set.isBase {
                Divider()
                Button("Rename") { editingName = set.name; editingSetID = set.id }
                Button("Delete Set", role: .destructive) { library.removeSet(set.id) }
            }
        }
    }

    private func swatchTile(_ swatch: SwatchColor, in set: SwatchSet) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(swatch.color)
            .frame(height: 28)
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.18)))
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .onTapGesture { onPick(swatch.nsColor) }
            .help(swatch.hex)
            .contextMenu {
                Button("Use Colour") { onPick(swatch.nsColor) }
                Button("Copy Hex") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(swatch.hex, forType: .string)
                }
                Button("Remove", role: .destructive) { library.removeColor(swatch.id, from: set.id) }
            }
    }

    private func copyHexList(_ set: SwatchSet) {
        let text = set.colors.map(\.hex).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func exportSet(_ set: SwatchSet) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(set.name).txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = set.colors.map(\.hex).joined(separator: "\n")
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
