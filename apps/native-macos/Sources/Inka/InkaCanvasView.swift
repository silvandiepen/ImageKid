import AppKit
import BrushKit
import MetalKit
import SwiftUI

/// SwiftUI host for the Metal canvas. Wraps an `MTKView` subclass that captures
/// mouse/tablet drags (pressure from `NSEvent.pressure`, real on a tablet, 1 for
/// a mouse) and feeds `InkaCanvasRenderer` in canvas pixel coordinates.
struct InkaCanvasView: NSViewRepresentable {
    @ObservedObject var model: InkaModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> MTKView {
        let renderer = model.renderer
        let view = InputMTKView()
        view.device = renderer?.device
        view.delegate = renderer
        view.framebufferOnly = false
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.preferredFramesPerSecond = 120
        view.colorPixelFormat = .bgra8Unorm
        view.autoResizeDrawable = true
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        // Keep the renderer's brush/colour in step with the model.
        model.renderer?.brush = model.brush
        model.renderer?.color = model.currentColorRGBA
        (nsView as? InputMTKView)?.coordinator = context.coordinator
    }

    /// Bridges AppKit events to the renderer, converting view points to canvas
    /// pixels (the canvas fills the view 1:1 for the P1 skeleton). Main-actor:
    /// all AppKit event delivery is on the main thread.
    @MainActor
    final class Coordinator {
        let model: InkaModel
        init(model: InkaModel) { self.model = model }

        func sample(for event: NSEvent, in view: NSView) -> StrokeSample {
            let p = view.convert(event.locationInWindow, from: nil)
            // AppKit view coordinates are bottom-left; the canvas is top-left.
            let canvas = model.document.size
            let scaleX = canvas.width / max(view.bounds.width, 1)
            let scaleY = canvas.height / max(view.bounds.height, 1)
            let x = p.x * scaleX
            let y = (view.bounds.height - p.y) * scaleY
            // `pressure` is 0 for a plain mouse mid-drag on some inputs; treat
            // 0 as full so mouse strokes are solid, real tablet pressure passes.
            let pressure = event.pressure > 0 ? Double(event.pressure) : 1
            return StrokeSample(
                position: CGPoint(x: x, y: y), pressure: pressure,
                timestamp: event.timestamp)
        }

        func begin(_ event: NSEvent, in view: NSView) {
            model.renderer?.beginStroke(at: sample(for: event, in: view))
        }
        func drag(_ event: NSEvent, in view: NSView) {
            model.renderer?.extendStroke(to: sample(for: event, in: view))
        }
        func end(_ event: NSEvent, in view: NSView) {
            model.renderer?.endStroke()
        }
    }
}

/// An MTKView that forwards mouse/tablet drags to the coordinator. Pressure
/// rides on `NSEvent.pressure` (a graphics tablet fills it; a mouse leaves it 1).
final class InputMTKView: MTKView {
    weak var coordinator: InkaCanvasView.Coordinator?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) { coordinator?.begin(event, in: self) }
    override func mouseDragged(with event: NSEvent) { coordinator?.drag(event, in: self) }
    override func mouseUp(with event: NSEvent) { coordinator?.end(event, in: self) }
    // Tablet devices can arrive as their own event subtype; the base mouse
    // handlers above already carry `pressure`, so no separate path is needed
    // for the P1 skeleton.
}
