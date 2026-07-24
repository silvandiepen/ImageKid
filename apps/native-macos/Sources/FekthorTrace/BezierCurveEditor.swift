import FekthorKit
import SwiftUI

/// A cubic-bezier easing pad: the unit square with draggable P1/P2 handles,
/// the live curve, and the numeric readout. Emits standard CSS
/// `cubic-bezier(x1, y1, x2, y2)` text (x clamped to 0…1 per the spec, y
/// free for overshoot easings). Shared by the timeline's easing popover and
/// the workspace animation editor.
struct BezierCurveEditor: View {
    @Binding var easing: String

    private let size: CGFloat = 120
    /// Vertical overdraw so overshoot handles (y outside 0…1) stay visible.
    private let overshoot: CGFloat = 0.35

    private var control: (x1: Double, y1: Double, x2: Double, y2: Double) {
        if case .cubicBezier(let x1, let y1, let x2, let y2)? = TimingFunction.parse(easing) {
            return (x1, y1, x2, y2)
        }
        return (0.25, 0.1, 0.25, 1)  // ease
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            pad
            Text(easingText)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var easingText: String {
        let c = control
        return "cubic-bezier(\(num(c.x1)), \(num(c.y1)), \(num(c.x2)), \(num(c.y2)))"
    }

    private func num(_ v: Double) -> String { SVGNum.text(v) }

    // MARK: - Pad

    private func point(_ x: Double, _ y: Double) -> CGPoint {
        let usable = size / (1 + 2 * overshoot)
        return CGPoint(
            x: CGFloat(x) * size,
            y: size - (CGFloat(y) + overshoot) * usable)
    }

    private func value(at location: CGPoint) -> (Double, Double) {
        let usable = size / (1 + 2 * overshoot)
        let x = min(1, max(0, Double(location.x / size)))
        let y = Double((size - location.y) / usable) - Double(overshoot)
        return (x, min(1 + Double(overshoot), max(-Double(overshoot), y)))
    }

    private var pad: some View {
        let c = control
        let p0 = point(0, 0)
        let p1 = point(c.x1, c.y1)
        let p2 = point(c.x2, c.y2)
        let p3 = point(1, 1)
        return ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.08))
            // The unit square (progress space).
            Path { p in
                p.addRect(CGRect(origin: point(0, 1), size: CGSize(
                    width: point(1, 0).x - point(0, 0).x,
                    height: point(0, 0).y - point(0, 1).y)))
            }
            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            // Handle levers.
            Path { p in
                p.move(to: p0)
                p.addLine(to: p1)
                p.move(to: p3)
                p.addLine(to: p2)
            }
            .stroke(Color.secondary.opacity(0.6), lineWidth: 1)
            // The curve.
            Path { p in
                p.move(to: p0)
                p.addCurve(to: p3, control1: p1, control2: p2)
            }
            .stroke(Color.accentColor, lineWidth: 2)
            handle(at: p1) { x, y in setControl(x1: x, y1: y) }
            handle(at: p2) { x, y in setControl(x2: x, y2: y) }
        }
        .frame(width: size, height: size)
    }

    private func handle(at position: CGPoint, update: @escaping (Double, Double) -> Void)
        -> some View
    {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 10, height: 10)
            .position(position)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let (x, y) = value(at: drag.location)
                        update(x, y)
                    }
            )
    }

    private func setControl(
        x1: Double? = nil, y1: Double? = nil, x2: Double? = nil, y2: Double? = nil
    ) {
        let c = control
        let next = (x1 ?? c.x1, y1 ?? c.y1, x2 ?? c.x2, y2 ?? c.y2)
        easing = "cubic-bezier(\(num(next.0)), \(num(next.1)), \(num(next.2)), \(num(next.3)))"
    }
}
