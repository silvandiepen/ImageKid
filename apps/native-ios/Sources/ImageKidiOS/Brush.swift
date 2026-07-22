import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// A drawing brush preset for the freehand tool. Presets differ in opacity,
/// edge softness, and default size; the highlighter also flattens its caps
/// (its translucent flat-capped stroke reads like a real highlighter without
/// needing a blend mode, which the preview overlay couldn't show anyway).
enum BrushPreset: String, CaseIterable, Identifiable {
    case pen
    case marker
    case airbrush
    case highlighter

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pen: "Pen"
        case .marker: "Marker"
        case .airbrush: "Airbrush"
        case .highlighter: "Highlight"
        }
    }

    var systemImage: String {
        switch self {
        case .pen: "pencil.tip"
        case .marker: "paintbrush.pointed"
        case .airbrush: "paintbrush"
        case .highlighter: "highlighter"
        }
    }

    /// Stroke opacity the preset starts with (the slider can still adjust it).
    var opacity: CGFloat {
        switch self {
        case .pen: 1
        case .marker: 0.85
        case .airbrush: 0.55
        case .highlighter: 0.35
        }
    }

    /// Soft-edge amount (0 = crisp, 1 = very feathered).
    var softness: CGFloat {
        switch self {
        case .pen: 0
        case .marker: 0.12
        case .airbrush: 0.7
        case .highlighter: 0
        }
    }

    /// Default stroke width as a fraction of the image's smaller side.
    var widthFraction: CGFloat {
        switch self {
        case .pen: 0.008
        case .marker: 0.016
        case .airbrush: 0.03
        case .highlighter: 0.028
        }
    }

    /// Highlighter strokes use flat (butt) caps and a uniform width.
    var flatCaps: Bool { self == .highlighter }
}

/// Feathers stroke images with a gaussian blur (soft brushes and mask
/// painting). One shared CIContext so repeated strokes don't re-allocate.
enum StrokeSoftener {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// Blurs a full-alpha stroke image; returns the input untouched when the
    /// radius is negligible.
    static func blurred(_ image: CGImage, radius: CGFloat) -> CGImage? {
        guard radius > 0.1 else { return image }
        let input = CIImage(cgImage: image)
        let output = input
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: input.extent)
        return context.createCGImage(output, from: input.extent)
    }
}

// MARK: - Apple Pencil pressure

/// Latest Apple Pencil force for the touch in flight. A plain reference box —
/// the recognizer writes it on every touch move and the draw gesture reads it
/// when recording a point, so no SwiftUI invalidation happens per sample.
final class PencilPressureState {
    /// Normalised 0…1 force, nil when the current touch has no force data
    /// (finger input, or no touch down).
    var normalizedForce: CGFloat?

    /// Width multiplier for the point being recorded now (1 = base width).
    var widthMultiplier: CGFloat {
        guard let force = normalizedForce else { return 1 }
        return 0.35 + 1.15 * min(max(force, 0), 1)
    }
}

/// Observes pencil force without ever recognizing: SwiftUI's DragGesture
/// exposes no UITouch, so this recognizer sits on the window, stays in
/// `.possible` forever, and mirrors the pencil's force into the shared state.
/// It never claims or cancels touches, so the existing drag/zoom/tap gestures
/// are untouched.
private final class PencilForceRecognizer: UIGestureRecognizer {
    private let pressure: PencilPressureState

    init(pressure: PencilPressureState) {
        self.pressure = pressure
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        record(event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        record(event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        pressure.normalizedForce = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        pressure.normalizedForce = nil
    }

    private func record(_ event: UIEvent) {
        guard let pencil = event.allTouches?.first(where: { $0.type == .pencil }),
              pencil.maximumPossibleForce > 0 else {
            pressure.normalizedForce = nil
            return
        }
        pressure.normalizedForce = pencil.force / pencil.maximumPossibleForce
    }
}

/// Zero-size, non-interactive view that installs the force observer on the
/// window while it is in the hierarchy. Placed as a `.background` of the
/// editing canvas.
struct PencilPressureReader: UIViewRepresentable {
    let pressure: PencilPressureState

    func makeUIView(context: Context) -> PressureHostView {
        PressureHostView(pressure: pressure)
    }

    func updateUIView(_ uiView: PressureHostView, context: Context) {}

    final class PressureHostView: UIView {
        private let recognizer: PencilForceRecognizer

        init(pressure: PencilPressureState) {
            recognizer = PencilForceRecognizer(pressure: pressure)
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window {
                recognizer.view?.removeGestureRecognizer(recognizer)
                window.addGestureRecognizer(recognizer)
            }
        }

        override func willMove(toWindow newWindow: UIWindow?) {
            if newWindow == nil {
                recognizer.view?.removeGestureRecognizer(recognizer)
            }
            super.willMove(toWindow: newWindow)
        }
    }
}
