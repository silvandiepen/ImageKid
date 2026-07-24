import SwiftUI

/// The two-well paint bar that sits at the top of a panel rail: a pair of
/// overlapping swatches for the primary and secondary paint, plus a swap
/// button under them.
///
/// Fekthor arrived at this layout (fill/stroke); ImageKid uses the same one
/// for foreground/background. It lives here so the two cannot drift — the
/// geometry, the active ring and the swap control are defined once.
///
/// Callers supply the two swatch glyphs, so each app keeps its own rendering
/// (Fekthor draws gradients and "none" slashes; ImageKid draws flat colour)
/// without duplicating the frame.

/// Fekthor's numbers, now the house geometry. Outside the generic type —
/// Swift does not allow static stored properties in one.
private enum Metrics {
    static let well: CGFloat = 26
    static let offset: CGFloat = 13
    static let frame: CGFloat = 39
    static let radius: CGFloat = 6
    static let swap: CGFloat = 20
}

public enum PaintWellSlot: Sendable {
    case primary
    case secondary
}

public struct PaintWellsBar<PrimaryGlyph: View, SecondaryGlyph: View>: View {
    @Binding private var active: PaintWellSlot
    private let primary: () -> PrimaryGlyph
    private let secondary: () -> SecondaryGlyph
    private let onEdit: (PaintWellSlot) -> Void
    private let onSwap: (() -> Void)?
    private let primaryHelp: String
    private let secondaryHelp: String

    @Environment(\.colorScheme) private var colorScheme

    public init(
        active: Binding<PaintWellSlot>,
        primaryHelp: String = "Foreground",
        secondaryHelp: String = "Background",
        onEdit: @escaping (PaintWellSlot) -> Void = { _ in },
        onSwap: (() -> Void)? = nil,
        @ViewBuilder primary: @escaping () -> PrimaryGlyph,
        @ViewBuilder secondary: @escaping () -> SecondaryGlyph
    ) {
        self._active = active
        self.primaryHelp = primaryHelp
        self.secondaryHelp = secondaryHelp
        self.onEdit = onEdit
        self.onSwap = onSwap
        self.primary = primary
        self.secondary = secondary
    }

    public var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                // The active well draws last so it sits on top.
                if active == .primary {
                    well(.secondary, glyph: secondary).offset(x: Metrics.offset, y: Metrics.offset)
                    well(.primary, glyph: primary)
                } else {
                    well(.primary, glyph: primary)
                    well(.secondary, glyph: secondary).offset(x: Metrics.offset, y: Metrics.offset)
                }
            }
            .frame(width: Metrics.frame, height: Metrics.frame, alignment: .topLeading)

            if let onSwap { swapButton(onSwap) }
        }
        .padding(.bottom, 4)
    }

    private func well(
        _ slot: PaintWellSlot, @ViewBuilder glyph: () -> some View
    ) -> some View {
        let isActive = active == slot
        return glyph()
            .frame(width: Metrics.well, height: Metrics.well)
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radius)
                    .strokeBorder(
                        isActive
                            ? Color.accentColor
                            : Color.panelInk(colorScheme, 0.35),
                        lineWidth: isActive ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: Metrics.radius))
            // Double-click registered FIRST so it wins over the select tap.
            .onTapGesture(count: 2) {
                active = slot
                onEdit(slot)
            }
            .onTapGesture { active = slot }
            .help(
                (slot == .primary ? primaryHelp : secondaryHelp)
                    + (isActive ? " (active)" : " — click to make active")
                    + " · double-click to edit")
            .accessibilityIdentifier(
                "swatches.well." + (slot == .primary ? "primary" : "secondary"))
    }

    private func swapButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 9, weight: .semibold))
                .frame(width: Metrics.swap, height: Metrics.swap)
                .background(
                    Color.panelFill(colorScheme, 0.08),
                    in: RoundedRectangle(cornerRadius: Metrics.radius))
                .contentShape(RoundedRectangle(cornerRadius: Metrics.radius))
        }
        .buttonStyle(.plain)
        .help("Swap")
        .accessibilityIdentifier("swatches.swap")
    }
}
