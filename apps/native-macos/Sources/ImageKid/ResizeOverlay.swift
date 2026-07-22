import AppKit
import SwiftUI

struct ResizeOverlay: View {
    /// The full canvas rect (the current on-screen image bounds).
    let fullRect: CGRect
    /// The scaled preview rect at the target size.
    let imageRect: CGRect
    let size: CGSize
    var previewImage: NSImage?

    var body: some View {
        ZStack {
            // Ghost of the original bounds.
            Rectangle()
                .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .frame(width: fullRect.width, height: fullRect.height)
                .position(x: fullRect.midX, y: fullRect.midY)

            // Actual scaled preview of the image at the new size.
            if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: imageRect.width, height: imageRect.height)
                    .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1.5))
                    .position(x: imageRect.midX, y: imageRect.midY)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
            } else {
                Rectangle()
                    .stroke(Color.accentColor, lineWidth: 1.5)
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)
            }

            Text("\(Int(size.width.rounded())) × \(Int(size.height.rounded())) px")
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.72), in: Capsule())
                .position(x: imageRect.midX, y: max(18, imageRect.minY - 18))
        }
        .allowsHitTesting(false)
    }
}
