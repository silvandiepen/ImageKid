import AppKit
import FekthorKit
import SwiftUI

/// "Use as Container…" sheet: define (or edit) the icon's content slot —
/// numeric x/y/width/height in the icon's own viewBox units plus the fit
/// rule — previewed as a translucent rectangle over the icon's thumbnail.
/// Saving stores a `Workfile.ContainerSlot` under the icon's name; removing
/// deletes the slot and every membership that referenced it.
struct ContainerSlotSheet: View {
    @ObservedObject var session: WorkspaceSession
    let entry: IconEntry
    @Environment(\.dismiss) private var dismiss

    @State private var x: Double = 0
    @State private var y: Double = 0
    @State private var width: Double = 0
    @State private var height: Double = 0
    @State private var fit: FitRule = .contain
    @State private var viewBox: ViewBox? = nil
    @State private var loaded = false
    @State private var confirmRemove = false

    private var existing: Workfile.ContainerSlot? {
        session.slot(forContainer: entry.name)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(existing == nil ? "Use “\(entry.name)” as Container" : "Container “\(entry.name)”")
                    .font(.headline)
                Spacer()
            }
            .padding(12)
            Divider()
            HStack(alignment: .top, spacing: 16) {
                preview
                fields
            }
            .padding(14)
            Divider()
            HStack {
                if existing != nil {
                    Button("Remove Container…", role: .destructive) { confirmRemove = true }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Slot") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(width <= 0 || height <= 0)
            }
            .padding(12)
        }
        .frame(width: 560)
        .task { await load() }
        .alert("Remove this container?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) {
                session.removeContainer(named: entry.name)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "The slot definition and every icon membership referencing “\(entry.name)” are removed from the workfile. The SVG itself is untouched."
            )
        }
    }

    // MARK: - Preview

    /// Thumbnail with the slot rectangle drawn over it, both mapped through
    /// the exact fit math the thumbnail renderer uses (0.88 margin, centered).
    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(Color.fekthorWell)
            ThumbnailImage(entry: entry, thumbnails: session.thumbnails, side: Self.previewSide)
            if let vb = viewBox, vb.width > 0, vb.height > 0 {
                slotRectangle(in: vb)
            }
        }
        .frame(width: Self.previewSide, height: Self.previewSide)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.black.opacity(0.25))
        )
    }

    /// Observes the thumbnail store so the async render lands in the sheet.
    private struct ThumbnailImage: View {
        let entry: IconEntry
        @ObservedObject var thumbnails: ThumbnailStore
        let side: CGFloat

        var body: some View {
            Group {
                if let image = thumbnails.image(for: entry) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: side, height: side)
                } else {
                    ProgressView().controlSize(.small).opacity(0.4)
                }
            }
            .task(id: thumbnails.key(for: entry)) {
                thumbnails.request(entry)
            }
        }
    }

    private static let previewSide: CGFloat = 260

    private func slotRectangle(in vb: ViewBox) -> some View {
        // Mirror ThumbnailRenderer: s = side * 0.88 / max(w, h), centered.
        let side = Self.previewSide
        let s = side * 0.88 / CGFloat(max(vb.width, vb.height))
        let tx = (side - s * CGFloat(vb.width)) / 2 - s * CGFloat(vb.minX)
        let ty = (side - s * CGFloat(vb.height)) / 2 - s * CGFloat(vb.minY)
        let rect = CGRect(
            x: CGFloat(x) * s + tx, y: CGFloat(y) * s + ty,
            width: CGFloat(width) * s, height: CGFloat(height) * s)
        return Rectangle()
            .fill(Color.accentColor.opacity(0.18))
            .overlay(
                Rectangle().strokeBorder(
                    Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            )
            .frame(width: max(rect.width, 0), height: max(rect.height, 0))
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }

    // MARK: - Fields

    private var fields: some View {
        Form {
            Text("Content slot (in this icon's viewBox units)")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("X", value: $x, format: .number)
            TextField("Y", value: $y, format: .number)
            TextField("Width", value: $width, format: .number)
            TextField("Height", value: $height, format: .number)
            Picker("Fit", selection: $fit) {
                Text("Contain").tag(FitRule.contain)
                Text("Cover").tag(FitRule.cover)
                Text("Stretch").tag(FitRule.stretch)
                Text("Center").tag(FitRule.center)
            }
            if let vb = viewBox {
                LabeledContent(
                    "viewBox",
                    value: "\(Int(vb.minX)) \(Int(vb.minY)) \(Int(vb.width)) \(Int(vb.height))")
            }
            Text("Member icons are composed into this rect on export (Export ▸ Compose containers).")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .formStyle(.columns)
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Load / save

    private func load() async {
        guard !loaded else { return }
        loaded = true
        if let slot = existing {
            x = slot.x
            y = slot.y
            width = slot.width
            height = slot.height
            fit = FitRule.parse(slot.fit)
        }
        let url = entry.url
        let vb = await Task.detached(priority: .userInitiated) { () -> ViewBox? in
            guard let data = try? Data(contentsOf: url),
                let doc = try? SVGReader.read(data)
            else { return nil }
            return doc.viewBox
        }.value
        viewBox = vb
        // A fresh container defaults to a centered slot at half the artboard.
        if existing == nil, width <= 0, let vb, vb.width > 0, vb.height > 0 {
            x = (vb.minX + vb.width * 0.25).rounded()
            y = (vb.minY + vb.height * 0.25).rounded()
            width = (vb.width * 0.5).rounded()
            height = (vb.height * 0.5).rounded()
        }
    }

    private func save() {
        session.setSlot(
            Workfile.ContainerSlot(
                container: entry.name, x: x, y: y, width: width, height: height,
                fit: fit == .contain ? nil : fit.rawValue))
        dismiss()
    }
}
