import SwiftUI

struct CropOverlay: View {
    let imageRect: CGRect
    let normalizedRect: CGRect

    var body: some View {
        let crop = GeometryMapper.viewRect(from: normalizedRect, in: imageRect)

        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.42)
                .frame(width: imageRect.width, height: max(0, crop.minY - imageRect.minY))
                .position(x: imageRect.midX, y: imageRect.minY + max(0, crop.minY - imageRect.minY) / 2)

            Color.black.opacity(0.42)
                .frame(width: imageRect.width, height: max(0, imageRect.maxY - crop.maxY))
                .position(x: imageRect.midX, y: crop.maxY + max(0, imageRect.maxY - crop.maxY) / 2)

            Color.black.opacity(0.42)
                .frame(width: max(0, crop.minX - imageRect.minX), height: crop.height)
                .position(x: imageRect.minX + max(0, crop.minX - imageRect.minX) / 2, y: crop.midY)

            Color.black.opacity(0.42)
                .frame(width: max(0, imageRect.maxX - crop.maxX), height: crop.height)
                .position(x: crop.maxX + max(0, imageRect.maxX - crop.maxX) / 2, y: crop.midY)

            Rectangle()
                .stroke(Color.white, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .frame(width: crop.width, height: crop.height)
                .position(x: crop.midX, y: crop.midY)
        }
        .allowsHitTesting(false)
    }
}
