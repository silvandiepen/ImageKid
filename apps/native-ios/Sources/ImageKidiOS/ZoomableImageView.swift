import AVFoundation
import SwiftUI
import UIKit

/// Free pan + zoom image viewer (no UIScrollView, so it never springs back to
/// centre): one-finger drag pans, pinch zooms (down to 25% and up to 8× of the
/// fit size), double-tap returns to Fit. Matches the editor canvas so movement
/// feels the same everywhere.
struct ZoomableImageView: View {
    let image: UIImage
    var cornerRadius: CGFloat = 10
    var borderColor: Color = .primary.opacity(0.3)
    var showBorder: Bool = true

    @State private var zoomScale: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var committedPan: CGSize = .zero

    private let minZoom: CGFloat = 0.25
    private let maxZoom: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let fitRect = AVMakeRect(aspectRatio: image.size, insideRect: CGRect(origin: .zero, size: geo.size))
            let rect = transformedRect(fitRect)

            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: rect.width, height: rect.height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay {
                        if showBorder {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(borderColor, lineWidth: 1)
                        }
                    }
                    .position(x: rect.midX, y: rect.midY)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(panGesture)
            .simultaneousGesture(zoomGesture)
            .onTapGesture(count: 2) { fit() }
            .overlay(alignment: .topTrailing) {
                zoomControls.padding(12)
            }
        }
    }

    private func transformedRect(_ fitRect: CGRect) -> CGRect {
        CGRect(
            x: fitRect.midX + panOffset.width - fitRect.width * zoomScale / 2,
            y: fitRect.midY + panOffset.height - fitRect.height * zoomScale / 2,
            width: fitRect.width * zoomScale,
            height: fitRect.height * zoomScale
        )
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                panOffset = CGSize(
                    width: committedPan.width + value.translation.width,
                    height: committedPan.height + value.translation.height
                )
            }
            .onEnded { _ in committedPan = panOffset }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in zoomScale = clamped(committedZoom * value) }
            .onEnded { _ in committedZoom = zoomScale }
    }

    private func clamped(_ value: CGFloat) -> CGFloat { min(max(value, minZoom), maxZoom) }

    private func setZoom(_ value: CGFloat) {
        withAnimation(.snappy) {
            zoomScale = clamped(value)
            committedZoom = zoomScale
        }
    }

    private func fit() {
        withAnimation(.snappy) {
            zoomScale = 1
            committedZoom = 1
            panOffset = .zero
            committedPan = .zero
        }
    }

    private var label: String {
        (zoomScale > 0.99 && zoomScale < 1.01) ? "Fit" : "\(Int((zoomScale * 100).rounded()))%"
    }

    private var zoomControls: some View {
        HStack(spacing: 0) {
            controlButton("minus") { setZoom(zoomScale / 1.5) }
                .disabled(zoomScale <= minZoom + 0.001)
            Menu {
                Button("Fit") { fit() }
                Button("25%") { setZoom(0.25) }
                Button("50%") { setZoom(0.5) }
                Button("100%") { setZoom(1) }
                Button("200%") { setZoom(2) }
                Button("400%") { setZoom(4) }
                Button("800%") { setZoom(8) }
            } label: {
                Text(label)
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .frame(minWidth: 46)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            controlButton("plus") { setZoom(zoomScale * 1.5) }
                .disabled(zoomScale >= maxZoom - 0.001)
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
