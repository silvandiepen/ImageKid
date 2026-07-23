import SwiftUI
import ImageKidCore

struct CropOverlay: View {
    let imageRect: CGRect
    let normalizedRect: CGRect

    var body: some View {
        let crop = GeometryMapper.viewRect(from: normalizedRect, in: imageRect)
        let handles = Array(handlePoints(for: crop).enumerated())

        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.48)
                .frame(width: imageRect.width, height: max(0, crop.minY - imageRect.minY))
                .position(x: imageRect.midX, y: imageRect.minY + max(0, crop.minY - imageRect.minY) / 2)

            Color.black.opacity(0.48)
                .frame(width: imageRect.width, height: max(0, imageRect.maxY - crop.maxY))
                .position(x: imageRect.midX, y: crop.maxY + max(0, imageRect.maxY - crop.maxY) / 2)

            Color.black.opacity(0.48)
                .frame(width: max(0, crop.minX - imageRect.minX), height: crop.height)
                .position(x: imageRect.minX + max(0, crop.minX - imageRect.minX) / 2, y: crop.midY)

            Color.black.opacity(0.48)
                .frame(width: max(0, imageRect.maxX - crop.maxX), height: crop.height)
                .position(x: crop.maxX + max(0, imageRect.maxX - crop.maxX) / 2, y: crop.midY)

            Rectangle()
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: crop.width, height: crop.height)
                .position(x: crop.midX, y: crop.midY)

            ruleOfThirds(in: crop)

            ForEach(handles, id: \.offset) { _, point in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 11, height: 11)
                    .overlay(RoundedRectangle(cornerRadius: 2.5).stroke(.black.opacity(0.35)))
                    .position(point)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func ruleOfThirds(in crop: CGRect) -> some View {
        Path { path in
            let firstX = crop.minX + crop.width / 3
            let secondX = crop.minX + crop.width * 2 / 3
            let firstY = crop.minY + crop.height / 3
            let secondY = crop.minY + crop.height * 2 / 3
            path.move(to: CGPoint(x: firstX, y: crop.minY))
            path.addLine(to: CGPoint(x: firstX, y: crop.maxY))
            path.move(to: CGPoint(x: secondX, y: crop.minY))
            path.addLine(to: CGPoint(x: secondX, y: crop.maxY))
            path.move(to: CGPoint(x: crop.minX, y: firstY))
            path.addLine(to: CGPoint(x: crop.maxX, y: firstY))
            path.move(to: CGPoint(x: crop.minX, y: secondY))
            path.addLine(to: CGPoint(x: crop.maxX, y: secondY))
        }
        .stroke(.white.opacity(0.42), lineWidth: 0.8)
    }

    private func handlePoints(for crop: CGRect) -> [CGPoint] {
        [
            CGPoint(x: crop.minX, y: crop.minY),
            CGPoint(x: crop.midX, y: crop.minY),
            CGPoint(x: crop.maxX, y: crop.minY),
            CGPoint(x: crop.minX, y: crop.midY),
            CGPoint(x: crop.maxX, y: crop.midY),
            CGPoint(x: crop.minX, y: crop.maxY),
            CGPoint(x: crop.midX, y: crop.maxY),
            CGPoint(x: crop.maxX, y: crop.maxY)
        ]
    }
}
