import SwiftUI

/// The slice inspector, opened by double-clicking a slice (or `⌘E`).
///
/// Everything about one slice in one place: a preview of the region it will
/// export, its name, its exact pixel size and position, and the anchor point
/// that stays put while the size changes.
struct SliceInspector: View {
    @ObservedObject var model: SlicerDocumentModel
    let slice: Slice
    let index: Int
    let source: SlicerDocumentModel.Source

    @State private var name: String = ""
    @State private var width: Int = 0
    @State private var height: Int = 0
    @State private var originX: Int = 0
    @State private var originY: Int = 0
    @State private var anchor: SliceAnchor = .topLeft
    @State private var keepsAspectRatio = false

    /// The slice as the model currently holds it — the popover keeps showing
    /// live values while the canvas is dragged underneath it.
    private var current: Slice {
        model.slices.first { $0.id == slice.id } ?? slice
    }

    private var pixelRect: CGRect? {
        SliceGeometry.pixelRect(current.rect, pixelSize: source.pixelSize)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            preview
            nameField

            Divider()

            HStack(alignment: .top, spacing: 18) {
                anchorGrid
                dimensions
            }

            Divider()

            footer
        }
        .padding(16)
        .frame(width: 340)
        .onAppear(perform: syncFromModel)
        .onChange(of: current.rect) { _ in syncFromModel() }
        .onChange(of: current.name) { _ in name = current.name ?? "" }
    }

    // MARK: - Preview

    private var preview: some View {
        HStack(spacing: 12) {
            SliceThumbnail(
                preview: source.preview,
                rect: current.rect,
                pixelSize: source.pixelSize,
                maxWidth: 108,
                maxHeight: 84
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(current.displayName(at: index))
                    .font(.headline)
                if let pixelRect {
                    Text("\(Int(pixelRect.width)) × \(Int(pixelRect.height)) px")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("at \(Int(pixelRect.minX)), \(Int(pixelRect.minY))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text("exports as \(exportFileName)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
    }

    private var exportFileName: String {
        let options = model.exports.options
        let output = options.resolved(sourceType: source.outputType, sourceExtension: source.fileExtension)
        let base = SliceExporter.fileName(
            sourceName: source.displayName,
            index: index,
            count: model.slices.count,
            customName: current.name,
            prefix: options.sanitizedPrefix
        )
        return "\(base).\(output.fileExtension)"
    }

    // MARK: - Name

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Name")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(current.displayName(at: index), text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.rename(id: slice.id, to: name) }
                .onChange(of: name) { model.rename(id: slice.id, to: $0) }
                .accessibilityIdentifier("slicer.inspector.name")
            Text("Empty restores the automatic name.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Anchor

    private var anchorGrid: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Grows from")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 3) {
                HStack(spacing: 3) {
                    anchorButton(.topLeft); anchorButton(.top); anchorButton(.topRight)
                }
                HStack(spacing: 3) {
                    anchorButton(.left); anchorButton(.centre); anchorButton(.right)
                }
                HStack(spacing: 3) {
                    anchorButton(.bottomLeft); anchorButton(.bottom); anchorButton(.bottomRight)
                }
            }

            Text(anchor.label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func anchorButton(_ option: SliceAnchor) -> some View {
        Button {
            anchor = option
        } label: {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(anchor == option ? Color.accentColor : Color.white.opacity(0.10))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Keep the \(option.label.lowercased()) fixed while resizing")
        // A button whose label is a bare shape has no text for the
        // accessibility tree to latch onto, so it is described explicitly.
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(option.label)
        .accessibilityValue(anchor == option ? "Selected" : "")
        .accessibilityIdentifier("slicer.inspector.anchor.\(option.rawValue)")
    }

    // MARK: - Size and position

    private var dimensions: some View {
        VStack(alignment: .leading, spacing: 8) {
            field("Width", value: $width, identifier: "width") { applySize() }
            field("Height", value: $height, identifier: "height") { applySize() }

            Toggle("Lock ratio", isOn: $keepsAspectRatio)
                .font(.caption)
                .toggleStyle(.checkbox)

            Divider()

            field("X", value: $originX, identifier: "x") { applyOrigin() }
            field("Y", value: $originY, identifier: "y") { applyOrigin() }
        }
        .disabled(current.isLocked)
    }

    private func field(
        _ label: String,
        value: Binding<Int>,
        identifier: String,
        onCommit: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 74)
                .onSubmit(onCommit)
                .accessibilityIdentifier("slicer.inspector.\(identifier)")
            Stepper("") { value.wrappedValue += 1; onCommit() } onDecrement: {
                value.wrappedValue = max(value.wrappedValue - 1, 0)
                onCommit()
            }
            .labelsHidden()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Button(current.isLocked ? "Unlock" : "Lock") {
                model.setLocked(!current.isLocked, id: slice.id)
            }
            .accessibilityIdentifier("slicer.inspector.lock")

            Button("Duplicate") {
                model.selectedSliceID = slice.id
                model.duplicateSelectedSlice()
                model.inspectingSliceID = nil
            }
            .disabled(current.isLocked)

            Spacer(minLength: 0)

            Button("Delete", role: .destructive) {
                model.delete(id: slice.id)
            }
            .disabled(current.isLocked)
            .accessibilityIdentifier("slicer.inspector.delete")
        }
        .controlSize(.small)
    }

    // MARK: - Applying

    private func syncFromModel() {
        name = current.name ?? ""
        guard let pixelRect else { return }
        width = Int(pixelRect.width)
        height = Int(pixelRect.height)
        originX = Int(pixelRect.minX)
        originY = Int(pixelRect.minY)
    }

    private func applySize() {
        guard let pixelRect else { return }
        var newWidth = max(width, 1)
        var newHeight = max(height, 1)

        if keepsAspectRatio, pixelRect.width > 0, pixelRect.height > 0 {
            let ratio = pixelRect.width / pixelRect.height
            // Whichever field the user actually changed drives the other.
            if newWidth != Int(pixelRect.width) {
                newHeight = max(Int((CGFloat(newWidth) / ratio).rounded()), 1)
            } else {
                newWidth = max(Int((CGFloat(newHeight) * ratio).rounded()), 1)
            }
            width = newWidth
            height = newHeight
        }

        model.resize(
            id: slice.id,
            toPixelSize: CGSize(width: newWidth, height: newHeight),
            anchor: anchor
        )
    }

    private func applyOrigin() {
        model.move(
            id: slice.id,
            toPixelOrigin: CGPoint(x: max(originX, 0), y: max(originY, 0))
        )
    }
}
