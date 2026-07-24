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

        func begin(_ e: NSEvent, in v: NSView) { model.renderer?.beginStroke(at: sample(for: e, in: v)) }
        func drag(_ e: NSEvent, in v: NSView) { model.renderer?.extendStroke(to: sample(for: e, in: v)) }
        func end(_ e: NSEvent, in v: NSView) { model.renderer?.endStroke() }

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
}
