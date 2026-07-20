import SwiftUI
import UIKit

/// Pinch-to-zoom image built on `UIScrollView`, so zooming focuses on the pinch
/// point (not the centre), with pan, double-tap to return to contain size, and
/// on-screen zoom controls. A thin border hugs the image bounds and stays visually
/// constant at any zoom (like the macOS viewport).
struct ZoomableImageView: View {
    let image: UIImage
    var cornerRadius: CGFloat = 10
    var borderColor: Color = .primary.opacity(0.3)
    var showBorder: Bool = true

    @StateObject private var controller = ZoomController()

    var body: some View {
        ZStack {
            ZoomableScrollView(
                image: image,
                cornerRadius: cornerRadius,
                borderColor: UIColor(borderColor),
                showBorder: showBorder,
                controller: controller
            )

            zoomControls
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(12)
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 0) {
            controlButton("minus") { controller.zoomOut() }
                .disabled(!controller.canZoomOut)

            Button { controller.fit() } label: {
                Text(controller.label)
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .frame(minWidth: 46)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            controlButton("plus") { controller.zoomIn() }
                .disabled(!controller.canZoomIn)
        }
        .foregroundStyle(.primary)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
    }

    private func controlButton(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 40, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Bridges the SwiftUI zoom buttons to the underlying scroll view.
@MainActor
final class ZoomController: ObservableObject {
    /// Zoom relative to contain/fit (1 = fit).
    @Published var relativeZoom: CGFloat = 1
    weak var scrollView: UIScrollView?

    var label: String { relativeZoom <= 1.01 ? "Fit" : "\(Int((relativeZoom * 100).rounded()))%" }

    var canZoomIn: Bool {
        guard let scrollView else { return false }
        return scrollView.zoomScale < scrollView.maximumZoomScale - 0.001
    }

    var canZoomOut: Bool {
        guard let scrollView else { return false }
        return scrollView.zoomScale > scrollView.minimumZoomScale + 0.001
    }

    func zoomIn() { multiplyZoom(by: 1.5) }
    func zoomOut() { multiplyZoom(by: 1 / 1.5) }

    func fit() {
        guard let scrollView else { return }
        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
    }

    private func multiplyZoom(by factor: CGFloat) {
        guard let scrollView else { return }
        let target = min(max(scrollView.zoomScale * factor, scrollView.minimumZoomScale), scrollView.maximumZoomScale)
        scrollView.setZoomScale(target, animated: true)
    }
}

private struct ZoomableScrollView: UIViewRepresentable {
    let image: UIImage
    let cornerRadius: CGFloat
    let borderColor: UIColor
    let showBorder: Bool
    let controller: ZoomController

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleToFill
        imageView.layer.cornerCurve = .continuous
        imageView.layer.masksToBounds = true
        imageView.frame = CGRect(origin: .zero, size: image.size)
        scrollView.contentSize = image.size
        scrollView.addSubview(imageView)

        context.coordinator.imageView = imageView
        context.coordinator.controller = controller
        controller.scrollView = scrollView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.cornerRadius = cornerRadius
        coordinator.showBorder = showBorder
        coordinator.borderColor = borderColor

        if coordinator.imageView?.image !== image {
            coordinator.imageView?.image = image
            coordinator.imageView?.frame = CGRect(origin: .zero, size: image.size)
            scrollView.contentSize = image.size
            coordinator.needsFit = true
        }
        coordinator.applyBorder(scrollView)
        DispatchQueue.main.async { coordinator.configureZoom(scrollView) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        weak var controller: ZoomController?
        var cornerRadius: CGFloat = 10
        var showBorder = true
        var borderColor: UIColor = .gray
        var needsFit = true
        private var lastBounds: CGSize = .zero

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func configureZoom(_ scrollView: UIScrollView) {
            guard let imageView, imageView.bounds.width > 0, scrollView.bounds.width > 0 else { return }
            let size = imageView.bounds.size
            let fit = min(scrollView.bounds.width / size.width, scrollView.bounds.height / size.height)
            let boundsChanged = lastBounds != scrollView.bounds.size

            scrollView.minimumZoomScale = fit
            scrollView.maximumZoomScale = fit * 8

            if needsFit || boundsChanged {
                scrollView.zoomScale = fit
                needsFit = false
                lastBounds = scrollView.bounds.size
            }
            centerContent(scrollView)
            applyBorder(scrollView)
            publishZoom(scrollView)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContent(scrollView)
            applyBorder(scrollView)
            publishZoom(scrollView)
        }

        func applyBorder(_ scrollView: UIScrollView) {
            guard let imageView else { return }
            let zoom = max(scrollView.zoomScale, 0.0001)
            imageView.layer.cornerRadius = cornerRadius / zoom
            imageView.layer.borderColor = borderColor.cgColor
            imageView.layer.borderWidth = showBorder ? 1 / zoom : 0
        }

        private func centerContent(_ scrollView: UIScrollView) {
            guard let imageView else { return }
            let bounds = scrollView.bounds.size
            var frame = imageView.frame
            frame.origin.x = frame.width < bounds.width ? (bounds.width - frame.width) / 2 : 0
            frame.origin.y = frame.height < bounds.height ? (bounds.height - frame.height) / 2 : 0
            imageView.frame = frame
        }

        private func publishZoom(_ scrollView: UIScrollView) {
            guard scrollView.minimumZoomScale > 0 else { return }
            let relative = scrollView.zoomScale / scrollView.minimumZoomScale
            if abs((controller?.relativeZoom ?? -1) - relative) > 0.001 {
                controller?.relativeZoom = relative
            }
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            // Double-tap returns the image to contain (fit) size, centred.
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        }
    }
}
