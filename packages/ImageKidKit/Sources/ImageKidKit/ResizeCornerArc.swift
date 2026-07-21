import SwiftUI

/// A short arc that hugs a panel's bottom-right rounded corner — a subtle resize
/// affordance that can grow more visible on hover.
public struct ResizeCornerArc: Shape {
    /// The panel's own corner radius; the arc is drawn concentric with it, inset.
    public var cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = 28) {
        self.cornerRadius = cornerRadius
    }

    public func path(in rect: CGRect) -> Path {
        // Centre of curvature sits `cornerRadius` in from the panel's corner,
        // which is this view's bottom-right (its frame aligns to the corner).
        let center = CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY - cornerRadius)
        var path = Path()
        path.addArc(
            center: center,
            radius: cornerRadius - 10,
            startAngle: .degrees(16),
            endAngle: .degrees(74),
            clockwise: false
        )
        return path
    }
}
