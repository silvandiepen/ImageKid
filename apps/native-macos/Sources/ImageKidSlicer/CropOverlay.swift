import SwiftUI

/// The Crop tool's overlay: everything outside the region is dimmed, and the
/// region itself carries rule-of-thirds guides and resize handles.
struct CropOverlay: View {
    /// The crop in canvas coordinates.
    let viewRect: CGRect
    /// The whole canvas, so the dimming can cover it.
    let canvasSize: CGSize
    /// The crop in source pixels, for the readout.
    let pixelRect: CGRect?

    static let handleSize: CGFloat = 12

    var body: some View {
        ZStack(alignment: .topLeading) {
            dimming
            border
            thirds
            handles
            readout
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Crop region")
        .accessibilityValue(accessibilityValue)
    }

    /// Everything but the crop, darkened — the even-odd rule punches the
    /// region out of the full-canvas rectangle.
    private var dimming: some View {
        Path { path in
            path.addRect(CGRect(origin: .zero, size: canvasSize))
            path.addRect(viewRect)
        }
        .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
    }

    private var border: some View {
        Rectangle()
            .strokeBorder(Color.white.opacity(0.95), lineWidth: 1.5)
            .frame(width: viewRect.width, height: viewRect.height)
            .position(x: viewRect.midX, y: viewRect.midY)
    }

    private var thirds: some View {
        Path { path in
            for step in 1...2 {
                let fraction = CGFloat(step) / 3
                let x = viewRect.minX + viewRect.width * fraction
                path.move(to: CGPoint(x: x, y: viewRect.minY))
                path.addLine(to: CGPoint(x: x, y: viewRect.maxY))

                let y = viewRect.minY + viewRect.height * fraction
                path.move(to: CGPoint(x: viewRect.minX, y: y))
                path.addLine(to: CGPoint(x: viewRect.maxX, y: y))
            }
        }
        .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
        .opacity(viewRect.width > 60 && viewRect.height > 60 ? 1 : 0)
    }

    private var handles: some View {
        ForEach(Array(SliceHandle.allCases.enumerated()), id: \.offset) { _, handle in
            Rectangle()
                .fill(Color.white)
                .frame(width: Self.handleSize, height: Self.handleSize)
                .shadow(color: .black.opacity(0.5), radius: 2)
                .position(
                    x: viewRect.minX + handle.unitAnchor.x * viewRect.width,
                    y: viewRect.minY + handle.unitAnchor.y * viewRect.height
                )
        }
    }

    private var readout: some View {
        Text(readoutText)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.55), in: Capsule())
            .position(x: viewRect.midX, y: max(viewRect.minY - 16, 14))
            .opacity(viewRect.width > 90 ? 1 : 0)
    }

    private var readoutText: String {
        guard let pixelRect else { return "Empty crop" }
        return "\(Int(pixelRect.width)) × \(Int(pixelRect.height))"
    }

    private var accessibilityValue: String {
        guard let pixelRect else { return "Empty crop" }
        return "\(Int(pixelRect.width)) by \(Int(pixelRect.height)) pixels at \(Int(pixelRect.minX)), \(Int(pixelRect.minY))"
    }
}
