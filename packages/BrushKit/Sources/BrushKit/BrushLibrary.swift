import Foundation

/// The starter brushes every app boots with — a small, honest set that shows the
/// engine's range (crisp ink, tapered pencil, soft airbrush, flat marker). P2's
/// brush editor and `.inkbrush` import grow this into a real library; these have
/// fixed ids so a saved stroke keeps resolving.
public enum BrushLibrary {
    public static let inkPen = Brush(
        id: "builtin.ink-pen",
        name: "Ink Pen",
        tip: Brush.Tip(hardness: 0.95, spacing: 0.05),
        dynamics: Brush.Dynamics(pressureToSize: 0.5, pressureToOpacity: 0.1),
        size: 10, flow: 1, opacity: 1, smoothing: 0.5)

    public static let pencil = Brush(
        id: "builtin.pencil",
        name: "Pencil",
        tip: Brush.Tip(hardness: 0.5, spacing: 0.05, scatter: 0.08),
        dynamics: Brush.Dynamics(
            pressureToSize: 0.35, pressureToOpacity: 0.7, sizeJitter: 0.1,
            pressureCurve: .easeIn),
        // Real graphite tooth — the grain is what sells it as a pencil.
        grain: Brush.Grain(scale: 0.6, depth: 0.7),
        taper: Brush.Taper(startLength: 12, endLength: 18, startSize: 0.2, endSize: 0),
        size: 9, flow: 0.85, opacity: 0.95, smoothing: 0.4)

    public static let charcoal = Brush(
        id: "builtin.charcoal",
        name: "Charcoal",
        tip: Brush.Tip(hardness: 0.35, roundness: 0.85, spacing: 0.04, scatter: 0.25),
        dynamics: Brush.Dynamics(
            pressureToSize: 0.5, pressureToOpacity: 0.6, tiltToSize: 0.8,
            sizeJitter: 0.2, pressureCurve: .easeIn),
        grain: Brush.Grain(scale: 1.4, depth: 0.85),
        size: 34, flow: 0.7, opacity: 0.9, smoothing: 0.3)

    public static let airbrush = Brush(
        id: "builtin.airbrush",
        name: "Airbrush",
        tip: Brush.Tip(hardness: 0.08, spacing: 0.03),
        dynamics: Brush.Dynamics(pressureToSize: 0.7, pressureToOpacity: 0.5),
        size: 60, flow: 0.25, opacity: 0.85, smoothing: 0.3)

    public static let marker = Brush(
        id: "builtin.marker",
        name: "Marker",
        tip: Brush.Tip(hardness: 0.8, roundness: 0.55, angle: .pi / 4, spacing: 0.04),
        dynamics: Brush.Dynamics(pressureToSize: 0.2, pressureToOpacity: 0.1),
        size: 28, flow: 0.55, opacity: 0.6, smoothing: 0.35)

    public static let all: [Brush] = [inkPen, pencil, charcoal, airbrush, marker]

    /// Look up a preset by id (built-ins here; the app overlays user brushes).
    public static func brush(id: String) -> Brush? {
        all.first { $0.id == id }
    }
}
