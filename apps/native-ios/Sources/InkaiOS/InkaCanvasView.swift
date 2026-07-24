import BrushKit
import MetalKit
import SwiftUI
import UIKit

/// SwiftUI host for the Metal canvas on iPad. Wraps an `MTKView` subclass that
/// captures touches — Apple Pencil force/tilt/azimuth, or a finger — and feeds
/// `InkaCanvasRenderer` in canvas pixel coordinates. Uses coalesced touches so
/// the high-frequency Pencil samples all reach the engine.
struct InkaCanvasView: UIViewRepresentable {
    @ObservedObject var model: InkaModel

    func makeUIView(context: Context) -> MTKView {
        let renderer = model.renderer
        let view = InputMTKView()
        view.device = renderer?.device
        view.delegate = renderer
        view.framebufferOnly = false
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 120
        view.colorPixelFormat = .bgra8Unorm
        view.isMultipleTouchEnabled = false
        view.model = model
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        model.renderer?.brush = model.currentBrush
        model.renderer?.color = model.currentColorRGBA
        (uiView as? InputMTKView)?.model = model
    }
}

/// An MTKView that turns touches into `StrokeSample`s. Pressure comes from
/// `UITouch.force` (Pencil); a finger has no force, so it draws at full
/// pressure. Tilt rides on `altitudeAngle`/`azimuthAngle`.
final class InputMTKView: MTKView {
    weak var model: InkaModel?

    private func sample(_ touch: UITouch) -> StrokeSample {
        let p = touch.location(in: self)
        let canvas = model?.document.size ?? bounds.size
        let scaleX = canvas.width / max(bounds.width, 1)
        let scaleY = canvas.height / max(bounds.height, 1)
        let pressure: Double
        if touch.type == .pencil, touch.maximumPossibleForce > 0 {
            pressure = Double(touch.force / touch.maximumPossibleForce)
        } else {
            pressure = 1
        }
        return StrokeSample(
            position: CGPoint(x: p.x * scaleX, y: p.y * scaleY),
            pressure: max(0.02, pressure),
            altitude: Double(touch.type == .pencil ? touch.altitudeAngle : .pi / 2),
            azimuth: Double(touch.type == .pencil ? touch.azimuthAngle(in: self) : 0),
            timestamp: touch.timestamp)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        model?.renderer?.beginStroke(at: sample(touch))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        // Feed every coalesced sample so fast Pencil strokes stay smooth.
        for coalesced in event?.coalescedTouches(for: touch) ?? [touch] {
            model?.renderer?.extendStroke(to: sample(coalesced))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        model?.renderer?.endStroke()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        model?.renderer?.endStroke()
    }
}
