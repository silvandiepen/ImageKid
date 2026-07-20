import SwiftUI

/// A fit-to-view image that supports pinch zoom and pan, with double-tap to
/// reset. Draws a border that hugs the *actual* image bounds (so the canvas is
/// clear even against a matching background) and moves with the image.
struct ZoomableImageView: View {
    let image: UIImage
    var cornerRadius: CGFloat = 10
    var borderColor: Color = .primary.opacity(0.3)
    var showBorder: Bool = true

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let fitted = Self.aspectFitSize(image.size, in: geo.size)
            let radius = min(cornerRadius, min(fitted.width, fitted.height) / 2)

            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: fitted.width, height: fitted.height)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay {
                    if showBorder {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            // Counter-scale so the border stays visually thin at any zoom.
                            .strokeBorder(borderColor, lineWidth: 1 / scale)
                    }
                }
                .scaleEffect(scale)
                .offset(offset)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .gesture(magnification.simultaneously(with: drag))
                .onTapGesture(count: 2) { withAnimation(.spring(duration: 0.25)) { reset() } }
                .animation(.interactiveSpring, value: scale)
        }
    }

    private static func aspectFitSize(_ imageSize: CGSize, in bounds: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }
        let ratio = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        return CGSize(width: imageSize.width * ratio, height: imageSize.height * ratio)
    }

    private var magnification: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(lastScale * value, minScale), maxScale)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= minScale { withAnimation(.spring(duration: 0.25)) { reset() } }
            }
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > minScale else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in lastOffset = offset }
    }

    private func reset() {
        scale = minScale
        lastScale = minScale
        offset = .zero
        lastOffset = .zero
    }
}
