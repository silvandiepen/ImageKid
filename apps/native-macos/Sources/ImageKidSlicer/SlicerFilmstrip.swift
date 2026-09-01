import SwiftUI

/// The strip of open images below the canvas. It appears only once a second
/// image is open, so slicing one sheet stays exactly as small as it was.
struct SlicerFilmstrip: View {
    @ObservedObject var model: SlicerDocumentModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.images) { session in
                    item(session)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(height: 78)
        .chromeSurface(hairline: .top)
        .accessibilityIdentifier("slicer.filmstrip")
    }

    private func item(_ session: SlicerDocumentModel.ImageSession) -> some View {
        let isCurrent = session.id == model.currentImageID

        return Button {
            model.select(imageID: session.id)
        } label: {
            VStack(spacing: 3) {
                SliceThumbnail(
                    preview: session.source.preview,
                    rect: CGRect(x: 0, y: 0, width: 1, height: 1),
                    pixelSize: session.source.pixelSize,
                    maxWidth: 58,
                    maxHeight: 40
                )

                Text(session.source.displayName)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 66)

                Text(sliceLabel(session))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(session.hasUnsavedSlices ? Color.orange : Color.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                isCurrent ? Color.accentColor.opacity(0.22) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isCurrent ? Color.accentColor : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(session.source.displayName)
        .accessibilityLabel("Image \(session.source.displayName)")
        .accessibilityAddTraits(isCurrent ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("slicer.film.\(session.source.displayName)")
        .contextMenu {
            Button("Close Image") { model.close(imageID: session.id) }
        }
    }

    private func sliceLabel(_ session: SlicerDocumentModel.ImageSession) -> String {
        let count = session.slices.count
        guard count > 0 else { return "—" }
        return session.hasUnsavedSlices ? "\(count) •" : "\(count)"
    }
}
