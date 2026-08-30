import AppKit
import SwiftUI

/// A real AppKit vibrancy layer behind the window's chrome, so the material
/// picks up what is behind the window rather than faking a grey.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

/// Slicer's surfaces.
///
/// The chrome is translucent so the window sits in the desktop rather than on
/// it; the canvas deliberately is not. A slicing tool is a colour-critical
/// surface, and letting whatever is behind the window tint the source image
/// would be a bad trade for a nicer screenshot.
enum SlicerSurface {
    /// The canvas backdrop: a deep neutral, slightly lifted from black so the
    /// slice outlines and a dark source image still separate from it.
    static let canvasTop = Color(red: 0.070, green: 0.076, blue: 0.090)
    static let canvasBottom = Color(red: 0.043, green: 0.047, blue: 0.058)

    static var canvas: some View {
        LinearGradient(
            colors: [canvasTop, canvasBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// The hairline between a translucent surface and its neighbour.
    static let hairline = Color.white.opacity(0.09)

    /// A dark wash over the vibrancy. Without it the material takes its colour
    /// from whatever happens to be behind the window — a green desktop turns
    /// the whole chrome green — and the app stops looking like itself.
    static let chromeScrim = Color(red: 0.055, green: 0.060, blue: 0.072).opacity(0.62)

    /// The translucent chrome fill, as a shape style pair: material first, then
    /// the wash.
    @ViewBuilder
    static func glass<S: Shape>(_ shape: S) -> some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(chromeScrim))
    }
}

extension View {
    /// A translucent chrome surface with a hairline on one edge.
    func chromeSurface(hairline edge: Edge? = nil) -> some View {
        background { SlicerSurface.glass(Rectangle()) }
            .overlay(alignment: hairlineAlignment(edge)) {
                if let edge {
                    Rectangle()
                        .fill(SlicerSurface.hairline)
                        .frame(
                            width: edge == .leading || edge == .trailing ? 1 : nil,
                            height: edge == .top || edge == .bottom ? 1 : nil
                        )
                }
            }
    }

    private func hairlineAlignment(_ edge: Edge?) -> Alignment {
        switch edge {
        case .top: .top
        case .bottom: .bottom
        case .leading: .leading
        case .trailing: .trailing
        case nil: .center
        }
    }
}
