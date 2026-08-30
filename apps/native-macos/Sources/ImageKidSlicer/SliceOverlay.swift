import CoreGraphics
import SwiftUI

/// The rectangle drawn on top of the source image for one slice.
struct SliceOverlay: View {
    let slice: Slice
    let index: Int
    let isSelected: Bool
    /// The slice in canvas coordinates.
    let viewRect: CGRect
    /// The slice in source pixels, for the label and the accessibility value.
    let pixelRect: CGRect?

    static let handleSize: CGFloat = 10

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(tint.opacity(isSelected ? 0.14 : 0.06))
                .overlay(
                    Rectangle()
                        .strokeBorder(tint, style: strokeStyle)
                )
                .frame(width: viewRect.width, height: viewRect.height)

            label
                .padding(4)
                .allowsHitTesting(false)

            if isSelected {
                handles
            }
        }
        .frame(width: viewRect.width, height: viewRect.height, alignment: .topLeading)
        .position(x: viewRect.midX, y: viewRect.midY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(slice.displayName(at: index))
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    /// Locked slices read as inert: a muted outline the pointer will not
    /// answer, so the difference is visible before the user tries to drag one.
    private var tint: Color { slice.isLocked ? .secondary : .accentColor }

    private var strokeStyle: StrokeStyle {
        StrokeStyle(
            lineWidth: isSelected ? 2 : 1,
            dash: slice.isLocked ? [5, 4] : []
        )
    }

    private var label: some View {
        HStack(spacing: 4) {
            if slice.isLocked {
                Image(systemName: "lock.fill")
                    .font(.caption2)
            }
            Text(labelText)
        }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(tint, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .opacity(viewRect.width > 70 && viewRect.height > 24 ? 1 : 0)
    }

    private var labelText: String {
        guard let pixelRect else { return slice.displayName(at: index) }
        return "\(slice.displayName(at: index))  ·  \(Int(pixelRect.width))×\(Int(pixelRect.height))"
    }

    private var accessibilityValue: String {
        guard let pixelRect else { return "Empty slice" }
        let size = "\(Int(pixelRect.width)) by \(Int(pixelRect.height)) pixels at \(Int(pixelRect.minX)), \(Int(pixelRect.minY))"
        return slice.isLocked ? "Locked, \(size)" : size
    }

    @ViewBuilder
    private var handles: some View {
        ForEach(Array(SliceHandle.allCases.enumerated()), id: \.offset) { _, handle in
            Rectangle()
                .fill(Color.white)
                .overlay(Rectangle().strokeBorder(Color.accentColor, lineWidth: 1.5))
                .frame(width: Self.handleSize, height: Self.handleSize)
                .position(
                    x: handle.unitAnchor.x * viewRect.width,
                    y: handle.unitAnchor.y * viewRect.height
                )
                .accessibilityHidden(true)
        }
    }
}
