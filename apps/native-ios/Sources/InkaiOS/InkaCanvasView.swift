import BrushKit
import MetalKit
import SwiftUI
import UIKit

/// SwiftUI host for the Metal canvas on iPad. Wraps an `MTKView` subclass that
/// captures touches — Apple Pencil force/tilt/azimuth, or a finger — mapped
/// through the renderer's canvas transform to canvas pixels, and adds the
/// Procreate-style navigation gestures: two-finger pan, pinch-zoom, two-finger
/// tap = undo, three-finger tap = redo. A pencil always draws (so you can rest a
/// hand); with no pencil, one finger draws and two navigate.
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
        view.isMultipleTouchEnabled = true
        view.model = model
        renderer?.viewSize = view.bounds.size
        view.installGestures()
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        model.renderer?.brush = model.brush
        model.renderer?.color = model.currentColorRGBA
        model.renderer?.viewSize = uiView.bounds.size
        (uiView as? InputMTKView)?.model = model
    }
}

/// An MTKView that turns touches into `StrokeSample`s and hosts the navigation
/// gestures. Pressure comes from `UITouch.force` (Pencil); a finger draws at
/// full pressure. Tilt rides on `altitudeAngle`/`azimuthAngle`.
final class InputMTKView: MTKView, UIGestureRecognizerDelegate {
    weak var model: InkaModel?

    /// The touch currently active (pencil preferred), if any.
    private var drawingTouch: UITouch?
    /// The tool latched when the active touch began (draw / eyedropper / move).
    private var activeGesture: InkaTool = .draw
    /// Zoom captured at the start of a pinch.
    private var pinchStartZoom: CGFloat = 1
    /// Offset captured at the start of a two-finger pan.
    private var panStartOffset: CGSize = .zero
    /// Rotation captured at the start of a two-finger rotate.
    private var rotateStart: CGFloat = 0

    func installGestures() {
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        pinch.delegate = self
        addGestureRecognizer(pinch)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.delegate = self
        addGestureRecognizer(pan)

        let rotate = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate))
        rotate.delegate = self
        addGestureRecognizer(rotate)

        let undoTap = UITapGestureRecognizer(target: self, action: #selector(handleUndoTap))
        undoTap.numberOfTouchesRequired = 2
        undoTap.delegate = self
        addGestureRecognizer(undoTap)

        let redoTap = UITapGestureRecognizer(target: self, action: #selector(handleRedoTap))
        redoTap.numberOfTouchesRequired = 3
        redoTap.delegate = self
        addGestureRecognizer(redoTap)
    }

    // Pinch + pan should run together; taps are exclusive of drags by nature.
    func gestureRecognizer(
        _ g: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool { true }

    // MARK: - Drawing

    private func sample(_ touch: UITouch) -> StrokeSample {
        let p = touch.location(in: self)
        let canvas = model?.renderer?.canvasPoint(from: p, in: bounds.size) ?? p
        let pressure: Double
        if touch.type == .pencil, touch.maximumPossibleForce > 0 {
            pressure = Double(touch.force / touch.maximumPossibleForce)
        } else {
            pressure = 1
        }
        return StrokeSample(
            position: canvas,
            pressure: max(0.02, pressure),
            altitude: Double(touch.type == .pencil ? touch.altitudeAngle : .pi / 2),
            azimuth: Double(touch.type == .pencil ? touch.azimuthAngle(in: self) : 0),
            timestamp: touch.timestamp)
    }

    /// Pick the touch that should draw: a pencil if present, else a lone finger.
    private func drawingCandidate(_ event: UIEvent?) -> UITouch? {
        let all = event?.allTouches ?? []
        if let pencil = all.first(where: { $0.type == .pencil && $0.phase != .ended && $0.phase != .cancelled }) {
            return pencil
        }
        let fingers = all.filter { $0.type != .pencil && $0.phase != .ended && $0.phase != .cancelled }
        return fingers.count == 1 ? fingers.first : nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let candidate = drawingCandidate(event) else {
            // Two+ fingers (no pencil): navigation, not drawing — drop any gesture.
            abandonActiveGesture()
            return
        }
        // A second finger arriving while one was active turns it into navigation.
        if drawingTouch != nil, drawingTouch !== candidate { abandonActiveGesture() }
        drawingTouch = candidate
        activeGesture = model?.tool ?? .draw
        switch activeGesture {
        case .draw, .eraser: model?.renderer?.beginStroke(at: sample(candidate))
        case .eyedropper: model?.pickColor(at: sample(candidate).position)
        case .move: model?.selectionBegin(at: sample(candidate).position)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = drawingTouch, touches.contains(touch) else { return }
        switch activeGesture {
        case .draw, .eraser:
            // Feed every coalesced sample so fast Pencil strokes stay smooth.
            for coalesced in event?.coalescedTouches(for: touch) ?? [touch] {
                model?.renderer?.extendStroke(to: sample(coalesced))
            }
        case .eyedropper: model?.pickColor(at: sample(touch).position)
        case .move: model?.selectionUpdate(to: sample(touch).position)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = drawingTouch, touches.contains(touch) else { return }
        switch activeGesture {
        case .draw, .eraser: model?.renderer?.endStroke()
        case .eyedropper: break
        case .move: model?.selectionEnd()
        }
        drawingTouch = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = drawingTouch, touches.contains(touch) else { return }
        abandonActiveGesture()
    }

    /// Abandon the in-flight single-touch gesture (a second finger or a cancel).
    private func abandonActiveGesture() {
        guard drawingTouch != nil else { return }
        switch activeGesture {
        case .draw, .eraser: model?.renderer?.cancelStroke()
        case .move: model?.selectionEnd()
        case .eyedropper: break
        }
        drawingTouch = nil
    }

    // MARK: - Navigation gestures

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        guard let r = model?.renderer else { return }
        switch g.state {
        case .began:
            pinchStartZoom = r.zoom
            abandonActiveGesture()
        case .changed:
            r.zoom = min(32, max(0.1, pinchStartZoom * g.scale))
        default:
            break
        }
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        guard let r = model?.renderer else { return }
        switch g.state {
        case .began:
            panStartOffset = r.offset
            abandonActiveGesture()
        case .changed:
            let t = g.translation(in: self)
            r.offset = CGSize(width: panStartOffset.width + t.x, height: panStartOffset.height + t.y)
        default:
            break
        }
    }

    @objc private func handleRotate(_ g: UIRotationGestureRecognizer) {
        guard let r = model?.renderer else { return }
        switch g.state {
        case .began:
            rotateStart = r.rotation
            abandonActiveGesture()
        case .changed:
            r.rotation = rotateStart + g.rotation
        default:
            break
        }
    }

    @objc private func handleUndoTap(_ g: UITapGestureRecognizer) {
        guard g.state == .ended else { return }
        model?.undo()
    }

    @objc private func handleRedoTap(_ g: UITapGestureRecognizer) {
        guard g.state == .ended else { return }
        model?.redo()
    }
}
