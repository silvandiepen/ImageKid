import AppKit
import SwiftUI

/// The slice's own region of the source, cropped out of the display preview.
struct SliceThumbnail: View {
    let preview: NSImage
    let rect: CGRect
    let pixelSize: CGSize

    /// The row thumbnail is small; the inspector's preview is much larger.
    var maxWidth: CGFloat = 48
    var maxHeight: CGFloat = 36

    var body: some View {
        let box = boxSize

        GeometryReader { _ in
            // Draw the whole preview at the scale that makes this slice fill
            // the box, then slide the slice's corner to the box's origin.
            Image(nsImage: preview)
                .resizable()
                .interpolation(.medium)
                .frame(
                    width: box.width / max(rect.width, 0.0001),
                    height: box.height / max(rect.height, 0.0001)
                )
                .offset(
                    x: -rect.minX * box.width / max(rect.width, 0.0001),
                    y: -rect.minY * box.height / max(rect.height, 0.0001)
                )
        }
        .frame(width: box.width, height: box.height)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15))
        )
        .frame(width: maxWidth, height: maxHeight)
        .accessibilityHidden(true)
    }

    /// The largest box with the slice's own aspect ratio that fits the row.
    private var boxSize: CGSize {
        let width = rect.width * pixelSize.width
        let height = rect.height * pixelSize.height
        guard width > 0, height > 0 else { return CGSize(width: maxWidth, height: maxHeight) }

        let scale = min(maxWidth / width, maxHeight / height)
        return CGSize(width: max(width * scale, 1), height: max(height * scale, 1))
    }
}
