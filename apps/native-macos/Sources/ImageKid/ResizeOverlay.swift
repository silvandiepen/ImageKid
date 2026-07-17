import SwiftUI

struct ResizeOverlay: View {
    let imageRect: CGRect
    let size: CGSize

    var body: some View {
        ZStack {
            Rectangle()
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .frame(width: imageRect.width, height: imageRect.height)
                .position(x: imageRect.midX, y: imageRect.midY)

            Text("\(Int(size.width.rounded())) × \(Int(size.height.rounded())) px")
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.72), in: Capsule())
                .position(x: imageRect.midX, y: max(18, imageRect.minY - 18))

            ForEach(Array(handlePoints.enumerated()), id: \.offset) { _, point in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 11, height: 11)
                    .overlay(RoundedRectangle(cornerRadius: 2.5).stroke(Color.accentColor, lineWidth: 2))
                    .position(point)
            }
        }
        .allowsHitTesting(false)
    }

    private var handlePoints: [CGPoint] {
        [
            CGPoint(x: imageRect.minX, y: imageRect.minY),
            CGPoint(x: imageRect.midX, y: imageRect.minY),
            CGPoint(x: imageRect.maxX, y: imageRect.minY),
            CGPoint(x: imageRect.minX, y: imageRect.midY),
            CGPoint(x: imageRect.maxX, y: imageRect.midY),
            CGPoint(x: imageRect.minX, y: imageRect.maxY),
            CGPoint(x: imageRect.midX, y: imageRect.maxY),
            CGPoint(x: imageRect.maxX, y: imageRect.maxY)
        ]
    }
}
