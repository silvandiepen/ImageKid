import CoreGraphics
import Foundation

/// Which vertical dock edge a floating panel belongs to. Derived from the
/// panel's centre against the dock midpoint, and used to store positions
/// edge-relative so right-docked panels ride along when the window resizes.
public enum PanelDockSide: String, Codable, Sendable {
    case left
    case right
}

/// Pure, host-agnostic placement geometry for floating panels: side
/// derivation, edge-relative offsets, on-screen clamping, flush edge
/// sticking, and the free-slot finder used when a panel opens. Shared by the
/// apps the same way `PanelStacks` is, so behaviour stays testable and equal.
public enum PanelPlacement {
    /// Horizontal stick distance to the dock edges, matching the stacking
    /// tolerance so both magnets feel the same.
    public static let edgeSnapTolerance: CGFloat = 14
    /// The least of a panel that must stay inside the dock horizontally.
    public static let minVisible: CGFloat = 80
    /// FloatingToolPanel's header strip (28pt icon + 13pt vertical padding
    /// each side) — the drag handle that must never leave the dock.
    public static let headerHeight: CGFloat = 54
    /// Default dock inset (how far a docked panel sits from the frame edge) and
    /// the inter-panel gap of the docked columns. A tighter inset keeps panels
    /// close to the window edge.
    public static let margin: CGFloat = 8
    public static let gap: CGFloat = 12

    // MARK: - Sides

    /// The dock side a panel belongs to: centre left of the dock midpoint is
    /// `.left`, everything else (including dead centre) `.right`.
    public static func side(
        ofPanelAt x: CGFloat, panelWidth: CGFloat, dockWidth: CGFloat
    ) -> PanelDockSide {
        x + panelWidth / 2 < dockWidth / 2 ? .left : .right
    }

    /// The edge-relative offset to persist: distance from the left dock edge
    /// to the panel's leading edge (`.left`), or from the right dock edge to
    /// its trailing edge (`.right`) — 0 always means flush against the edge.
    public static func edgeOffset(
        forPanelAt x: CGFloat, side: PanelDockSide, panelWidth: CGFloat, dockWidth: CGFloat
    ) -> CGFloat {
        switch side {
        case .left: return x
        case .right: return dockWidth - x - panelWidth
        }
    }

    /// Resolve a persisted edge-relative offset back to an absolute x in the
    /// CURRENT dock — the inverse of `edgeOffset`, so right-side panels hug
    /// the right edge across window resizes.
    public static func resolveX(
        side: PanelDockSide, edgeOffset: CGFloat, panelWidth: CGFloat, dockWidth: CGFloat
    ) -> CGFloat {
        switch side {
        case .left: return edgeOffset
        case .right: return dockWidth - edgeOffset - panelWidth
        }
    }

    // MARK: - Clamping

    /// Keep a panel reachable: at least `minVisible` points of its width stay
    /// inside the dock horizontally, and its full header bar stays inside
    /// vertically (the header is the drag handle — lose it and the panel is
    /// stranded). Degenerate docks pass the position through untouched.
    public static func clamped(
        _ position: CGPoint,
        panelSize: CGSize,
        dock: CGSize,
        headerHeight: CGFloat = PanelPlacement.headerHeight,
        minVisible: CGFloat = PanelPlacement.minVisible
    ) -> CGPoint {
        guard dock.width > 0, dock.height > 0 else { return position }
        let lowestX = min(0, minVisible - panelSize.width)
        let highestX = max(lowestX, dock.width - minVisible)
        let highestY = max(0, dock.height - headerHeight)
        return CGPoint(
            x: min(max(position.x, lowestX), highestX),
            y: min(max(position.y, 0), highestY))
    }

    // MARK: - Edge sticking

    /// Flush edge stick on release: within `tolerance` of the left or right
    /// dock edge the panel snaps exactly flush (x = 0, or trailing edge on
    /// the dock's right edge); anywhere else x passes through unchanged.
    public static func edgeStuckX(
        _ x: CGFloat, panelWidth: CGFloat, dockWidth: CGFloat,
        tolerance: CGFloat = PanelPlacement.edgeSnapTolerance
    ) -> CGFloat {
        guard dockWidth > 0 else { return x }
        if x <= tolerance { return 0 }
        let flushRight = dockWidth - panelWidth
        if abs(x - flushRight) <= tolerance { return flushRight }
        return x
    }

    // MARK: - Opening placement

    /// True when `frame` intersects any of `others` — used to reject a stale
    /// stored position that would land a freshly opened panel on top of an
    /// already open one.
    public static func overlaps(_ frame: CGRect, any others: [CGRect]) -> Bool {
        others.contains { $0.intersects(frame) }
    }

    /// The next free slot in the dock columns for a freshly opened panel:
    /// below the lowest panel of the side with more room left (the column
    /// whose next slot is higher), flush into the `margin` inset — the same
    /// stacking maths as the first-run columns, but against the CURRENTLY
    /// open panels' real frames. An empty side starts at the top margin.
    public static func openingSlot(
        panelSize: CGSize,
        dock: CGSize,
        openFrames: [CGRect],
        margin: CGFloat = PanelPlacement.margin,
        gap: CGFloat = PanelPlacement.gap,
        headerHeight: CGFloat = PanelPlacement.headerHeight,
        minVisible: CGFloat = PanelPlacement.minVisible
    ) -> CGPoint {
        func nextY(on side: PanelDockSide) -> CGFloat {
            let bottom = openFrames
                .filter {
                    Self.side(ofPanelAt: $0.minX, panelWidth: $0.width, dockWidth: dock.width)
                        == side
                }
                .map(\.maxY).max()
            return bottom.map { $0 + gap } ?? margin
        }
        let leftY = nextY(on: .left)
        let rightY = nextY(on: .right)
        let side: PanelDockSide = leftY <= rightY ? .left : .right
        let position = CGPoint(
            x: side == .left ? margin : dock.width - panelSize.width - margin,
            y: side == .left ? leftY : rightY)
        return clamped(
            position, panelSize: panelSize, dock: dock,
            headerHeight: headerHeight, minVisible: minVisible)
    }
}
