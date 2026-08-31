import AppKit
import SwiftUI

/// The optional list of slices beside the canvas: rename, lock, reveal the
/// exact pixel size, and delete. Hidden by default — the canvas stays the
/// interface until the user asks for the list.
struct SliceListSidebar: View {
    @ObservedObject var model: SlicerDocumentModel
    let source: SlicerDocumentModel.Source

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Rectangle().fill(SlicerSurface.hairline).frame(height: 1)

            if model.slices.isEmpty {
                Text("Draw a slice, or lay down a template.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(model.slices.enumerated()), id: \.element.id) { index, slice in
                            row(slice, index: index)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(width: 264)
        .chromeSurface(hairline: .leading)
        .accessibilityIdentifier("slicer.sidebar")
    }

    private var header: some View {
        HStack {
            Text("Slices")
                .font(.headline)
            Spacer()
            Text("\(model.slices.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func row(_ slice: Slice, index: Int) -> some View {
        let isSelected = slice.id == model.selectedSliceID
        let pixelRect = SliceGeometry.pixelRect(slice.rect, pixelSize: source.pixelSize)

        return HStack(spacing: 10) {
            SliceThumbnail(preview: source.preview, rect: slice.rect, pixelSize: source.pixelSize)

            VStack(alignment: .leading, spacing: 2) {
                TextField(
                    slice.displayName(at: index),
                    text: nameBinding(for: slice)
                )
                .textFieldStyle(.plain)
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .accessibilityIdentifier("slicer.row.name.\(index)")
                .accessibilityLabel("Name of \(slice.displayName(at: index))")

                Text(pixelRect.map { "\(Int($0.width)) × \(Int($0.height))" } ?? "Empty")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                model.setLocked(!slice.isLocked, id: slice.id)
            } label: {
                Image(systemName: slice.isLocked ? "lock.fill" : "lock.open")
                    .foregroundStyle(slice.isLocked ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .toolTip(slice.isLocked ? "Unlock this slice" : "Lock this slice so the pointer ignores it")
            .accessibilityLabel(slice.isLocked ? "Unlock \(slice.displayName(at: index))" : "Lock \(slice.displayName(at: index))")
            .accessibilityIdentifier("slicer.row.lock.\(index)")

            Button {
                model.delete(id: slice.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(slice.isLocked)
            .toolTip("Delete this slice")
            .accessibilityLabel("Delete \(slice.displayName(at: index))")
            .accessibilityIdentifier("slicer.row.delete.\(index)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            isSelected ? Color.accentColor.opacity(0.16) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            guard !slice.isLocked else { return }
            model.selectedSliceID = slice.id
            model.selectedGuideID = nil
        }
        // Dragging out lives on the list row, not the canvas rectangle: on the
        // canvas a drag already means move, and a file drag would fight it.
        .onDrag {
            guard let url = model.temporaryFile(for: slice.id) else { return NSItemProvider() }
            return NSItemProvider(contentsOf: url) ?? NSItemProvider()
        }
    }

    /// Empty text means "no custom name", which puts the automatic `Slice n`
    /// back — so clearing the field is how a rename is undone.
    private func nameBinding(for slice: Slice) -> Binding<String> {
        Binding(
            get: { model.slices.first { $0.id == slice.id }?.name ?? "" },
            set: { model.rename(id: slice.id, to: $0) }
        )
    }
}
