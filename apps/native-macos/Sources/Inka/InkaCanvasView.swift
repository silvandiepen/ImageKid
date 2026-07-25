import AppKit
import BrushKit
import MetalKit
import SwiftUI

/// SwiftUI host for the Metal canvas. An `MTKView` subclass captures mouse/tablet
/// drags (pressure from `NSEvent.pressure`) and scroll/pinch to pan/zoom, mapping
/// view points through the renderer's canvas transform to canvas pixels.
struct InkaCanvasView: NSViewRepresentable {
    @ObservedObject var model: InkaModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> MTKView {
        let renderer = model.renderer
        let view = InputMTKView()
        view.device = renderer?.device
        view.delegate = renderer
        view.framebufferOnly = false
        // On-demand drawing: redraw when input/state changes, not on a timer
        // (the internal display loop does not run reliably inside a SwiftUI
        // NSViewRepresentable here).
        view.enableSetNeedsDisplay = true
        view.isPaused = true
        view.colorPixelFormat = .bgra8Unorm
        view.autoResizeDrawable = true
        view.coordinator = context.coordinator
        renderer?.viewSize = view.bounds.size
        // Model-driven changes (undo, layers, fit) ask the view to redraw.
        model.requestRedraw = { [weak view] in view?.needsDisplay = true }
        view.needsDisplay = true
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        model.renderer?.brush = model.brush
        model.renderer?.color = model.currentColorRGBA
        model.renderer?.viewSize = nsView.bounds.size
        (nsView as? InputMTKView)?.coordinator = context.coordinator
        nsView.needsDisplay = true
    }

    @MainActor
    final class Coordinator {
        let model: InkaModel
        init(model: InkaModel) { self.model = model }

        /// A view mouse event → a canvas-space `StrokeSample`.
        func sample(for event: NSEvent, in view: NSView) -> StrokeSample {
            let p = view.convert(event.locationInWindow, from: nil)
            // AppKit is bottom-left; the transform expects top-left view points.
            let top = CGPoint(x: p.x, y: view.bounds.height - p.y)
            let canvas = model.renderer?.canvasPoint(from: top, in: view.bounds.size) ?? top
            let pressure = event.pressure > 0 ? Double(event.pressure) : 1
            return StrokeSample(
                position: canvas, pressure: pressure, timestamp: event.timestamp)
        }

        private enum Gesture { case draw, pick, move }
        /// What the in-flight drag is doing (fixed at mouse-down by the tool).
        private var gesture: Gesture = .draw

        func begin(_ e: NSEvent, in v: NSView) {
            let s = sample(for: e, in: v)
            switch model.tool {
            case .eyedropper:
                gesture = .pick
                model.pickColor(at: s.position)
            case .move:
                gesture = .move
                model.selectionBegin(at: s.position)
            case .draw:
                gesture = .draw
                model.renderer?.beginStroke(at: s)
            }
        }
        func drag(_ e: NSEvent, in v: NSView) {
            let p = sample(for: e, in: v).position
            switch gesture {
            case .pick: model.pickColor(at: p)
            case .move: model.selectionUpdate(to: p)
            case .draw: model.renderer?.extendStroke(to: sample(for: e, in: v))
            }
        }
        func end(_ e: NSEvent, in v: NSView) {
            switch gesture {
            case .pick: break
            case .move: model.selectionEnd()
            case .draw: model.renderer?.endStroke()
            }
        }

        func pan(by delta: CGSize) {
            model.renderer?.offset.width += delta.width
            model.renderer?.offset.height += delta.height
        }
        func zoom(by factor: CGFloat) {
            guard let r = model.renderer else { return }
            r.zoom = min(32, max(0.1, r.zoom * factor))
        }
    }
}

/// An MTKView that forwards mouse/tablet drags and scroll/pinch. Pressure rides
/// on `NSEvent.pressure` (a tablet fills it; a mouse leaves it 1).
final class InputMTKView: MTKView {
    weak var coordinator: InkaCanvasView.Coordinator?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) { coordinator?.begin(event, in: self); needsDisplay = true }
    override func mouseDragged(with event: NSEvent) { coordinator?.drag(event, in: self); needsDisplay = true }
    override func mouseUp(with event: NSEvent) { coordinator?.end(event, in: self); needsDisplay = true }

    override func scrollWheel(with event: NSEvent) {
        // Two-finger scroll pans the canvas.
        coordinator?.pan(by: CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY))
        needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        // Pinch zooms.
        coordinator?.zoom(by: 1 + event.magnification)
        needsDisplay = true
    }

    // Move-tool keyboard: arrows nudge the selection (⇧ = ×10), delete removes
    // it, escape clears it. Falls through to the next responder otherwise.
    override func keyDown(with event: NSEvent) {
        guard let model = coordinator?.model, model.tool == .move else {
            super.keyDown(with: event)
            return
        }
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch Int(event.keyCode) {
        case 123: model.nudgeSelection(dx: -step, dy: 0)  // ←
        case 124: model.nudgeSelection(dx: step, dy: 0)   // →
        case 125: model.nudgeSelection(dx: 0, dy: step)   // ↓ (canvas y grows down)
        case 126: model.nudgeSelection(dx: 0, dy: -step)  // ↑
        case 51, 117: model.deleteSelection()             // delete / fwd-delete
        case 53: model.clearSelection()                   // esc
        default: super.keyDown(with: event); return
        }
    }
}
