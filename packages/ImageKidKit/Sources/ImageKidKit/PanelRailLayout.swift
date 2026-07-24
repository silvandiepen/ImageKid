import CoreGraphics

/// How many chips a panel rail can show, and what spills into its overflow.
///
/// A rail is a fixed column down the side of the canvas: once the app has
/// more palettes than the window is tall, the buttons either run off the
/// bottom edge (unreachable) or something has to give. This decides that
/// split from the live canvas height — the head of the order stays on the
/// rail, the tail moves behind an overflow button that takes the last slot.
/// Pure geometry, no view state, so both apps' rails can share it and it can
/// be tested without a window.
public enum PanelRailLayout {
    /// The split for `order` in `height` points of rail.
    ///
    /// - Parameters:
    ///   - chip: one button's edge length.
    ///   - spacing: gap between buttons.
    ///   - padding: the rail's own inset, top and bottom.
    ///   - reserved: anything fixed above the buttons (paint wells, say).
    /// - Returns: the buttons to show, and the ones that need the overflow.
    ///   `hidden` empty means everything fits and no overflow button is
    ///   needed; when it is non-empty, `shown` has already given up one slot
    ///   for that button. At least one chip is always shown, however short
    ///   the window — a rail with no buttons is worse than a cramped one.
    public static func split<ID>(
        _ order: [ID], height: CGFloat, chip: CGFloat, spacing: CGFloat,
        padding: CGFloat, reserved: CGFloat
    ) -> (shown: [ID], hidden: [ID]) {
        guard !order.isEmpty else { return ([], []) }
        let step = chip + spacing
        guard step > 0 else { return (order, []) }
        let available = height - reserved - padding * 2
        // n chips need n·chip + (n−1)·spacing = n·step − spacing.
        let fits = max(1, Int(((available + spacing) / step).rounded(.down)))
        guard order.count > fits else { return (order, []) }
        let visible = max(1, fits - 1)  // the overflow button needs a slot too
        return (Array(order.prefix(visible)), Array(order.dropFirst(visible)))
    }
}
