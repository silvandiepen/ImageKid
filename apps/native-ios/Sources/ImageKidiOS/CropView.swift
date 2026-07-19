import AVFoundation
import SwiftUI

/// Interactive crop editor. Drag the corner handles to resize, drag the middle
/// to move, or tap an aspect preset to snap to a centred rectangle of that
/// ratio. Produces a normalised crop rect (top-left origin) via `onApply`.
struct CropView: View {
    let image: UIImage
    let onApply: (CGRect) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var crop = CGRect(x: 0, y: 0, width: 1, height: 1)

    private let minSize: CGFloat = 0.1

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                GeometryReader { geo in
                    let imageRect = AVMakeRect(
                        aspectRatio: image.size,
                        insideRect: CGRect(origin: .zero, size: geo.size)
                    )
                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: imageRect.width, height: imageRect.height)
                            .position(x: imageRect.midX, y: imageRect.midY)
                        overlay(in: imageRect)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                aspectPresets
            }
            .padding()
            .navigationTitle("Crop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") { onApply(crop); dismiss() }.bold()
                }
            }
        }
    }

    // MARK: Overlay

    private func overlay(in imageRect: CGRect) -> some View {
        let rect = viewRect(for: crop, in: imageRect)
        return ZStack {
            // Dim everything outside the crop rectangle.
            Path { path in
                path.addRect(imageRect)
                path.addRect(rect)
            }
            .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))

            // Invisible interior hit area for the move gesture.
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .contentShape(Rectangle())
                .gesture(moveGesture(in: imageRect))

            Rectangle()
                .strokeBorder(Color.white, lineWidth: 1.5)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)

            handle(.topLeft, in: imageRect)
            handle(.topRight, in: imageRect)
            handle(.bottomLeft, in: imageRect)
            handle(.bottomRight, in: imageRect)
        }
    }

    private func handle(_ corner: Corner, in imageRect: CGRect) -> some View {
        let point = viewPoint(for: corner, in: imageRect)
        return Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.black.opacity(0.25)))
            .frame(width: 24, height: 24)
            .position(point)
            .gesture(cornerGesture(corner, in: imageRect))
    }

    // MARK: Gestures

    @State private var dragStart: CGRect?

    private func cornerGesture(_ corner: Corner, in imageRect: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragStart ?? crop
                if dragStart == nil { dragStart = crop }
                let dx = value.translation.width / imageRect.width
                let dy = value.translation.height / imageRect.height
                crop = resized(start, corner: corner, dx: dx, dy: dy)
            }
            .onEnded { _ in dragStart = nil }
    }

    private func moveGesture(in imageRect: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragStart ?? crop
                if dragStart == nil { dragStart = crop }
                var moved = start
                moved.origin.x = min(max(0, start.minX + value.translation.width / imageRect.width), 1 - start.width)
                moved.origin.y = min(max(0, start.minY + value.translation.height / imageRect.height), 1 - start.height)
                crop = moved
            }
            .onEnded { _ in dragStart = nil }
    }

    private func resized(_ start: CGRect, corner: Corner, dx: CGFloat, dy: CGFloat) -> CGRect {
        var minX = start.minX
        var minY = start.minY
        var maxX = start.maxX
        var maxY = start.maxY

        switch corner {
        case .topLeft: minX += dx; minY += dy
        case .topRight: maxX += dx; minY += dy
        case .bottomLeft: minX += dx; maxY += dy
        case .bottomRight: maxX += dx; maxY += dy
        }

        minX = min(max(0, minX), maxX - minSize)
        minY = min(max(0, minY), maxY - minSize)
        maxX = max(min(1, maxX), minX + minSize)
        maxY = max(min(1, maxY), minY + minSize)

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: Aspect presets

    private var aspectPresets: some View {
        HStack(spacing: 8) {
            presetButton("Free", ratio: nil)
            presetButton("1:1", ratio: (1, 1))
            presetButton("4:3", ratio: (4, 3))
            presetButton("3:2", ratio: (3, 2))
            presetButton("16:9", ratio: (16, 9))
        }
    }

    private func presetButton(_ title: String, ratio: (CGFloat, CGFloat)?) -> some View {
        Button(title) {
            withAnimation(.snappy) {
                crop = ratio.map { centeredCrop(ratioW: $0.0, ratioH: $0.1) } ?? CGRect(x: 0, y: 0, width: 1, height: 1)
            }
        }
        .buttonStyle(.bordered)
        .font(.subheadline)
    }

    private func centeredCrop(ratioW: CGFloat, ratioH: CGFloat) -> CGRect {
        let targetAspect = ratioW / ratioH
        let imageAspect = image.size.width / max(image.size.height, 1)
        var normalizedWidth: CGFloat
        var normalizedHeight: CGFloat
        if targetAspect > imageAspect {
            normalizedWidth = 1
            normalizedHeight = (image.size.width / targetAspect) / max(image.size.height, 1)
        } else {
            normalizedHeight = 1
            normalizedWidth = (image.size.height * targetAspect) / max(image.size.width, 1)
        }
        return CGRect(
            x: (1 - normalizedWidth) / 2,
            y: (1 - normalizedHeight) / 2,
            width: normalizedWidth,
            height: normalizedHeight
        )
    }

    // MARK: Coordinate helpers

    private func viewRect(for normalized: CGRect, in imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + normalized.minX * imageRect.width,
            y: imageRect.minY + normalized.minY * imageRect.height,
            width: normalized.width * imageRect.width,
            height: normalized.height * imageRect.height
        )
    }

    private func viewPoint(for corner: Corner, in imageRect: CGRect) -> CGPoint {
        let rect = viewRect(for: crop, in: imageRect)
        switch corner {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    enum Corner { case topLeft, topRight, bottomLeft, bottomRight }
}
