import SwiftUI

/// The drag/settle/place wiring around a `PanelDockModel`, extracted so an app
/// does not have to re-write it. ImageKid and Fekthor grew their own copies of
/// this glue (offset binding, live stack-drag, grid-snap-on-release, edge
/// sticking, opening-slot placement); this is that logic, generic, in the Kit —
/// so Inka (and, when they migrate, the others) just render panels and call
/// these handlers.
///
/// Hold one per dock as a `@StateObject`, render the rail from `model`, and give
/// each `FloatingToolPanel` `offsetBinding(id:in:)`, `onDragChanged` →
/// `dragChanged`, `onDragEnded` → `dragEnded`; call `placePending(in:)` when the
/// dock appears / resizes / `model.needsPlacement` changes.
@MainActor
public final class PanelDockController<ID: Hashable>: ObservableObject {
    public let model: PanelDockModel<ID>

    /// While a stack head is being dragged, its followers ride along live.
    @Published private var stackDragHead: ID?
    @Published private var stackDragTranslation: CGSize = .zero

    public init(_ model: PanelDockModel<ID>) {
        self.model = model
    }

    /// The live offset for a panel: its resting spot plus, if it is a follower
    /// of the head currently being dragged, that head's translation.
    public func offsetBinding(_ id: ID, in dock: CGSize) -> Binding<CGSize> {
        Binding(
            get: { [self] in
                var origin = model.displayPosition(id, in: dock)
                if let head = stackDragHead, id != head,
                    model.stacks.head(of: model.stackKey(id)) == model.stacks.head(of: model.stackKey(head))
                {
                    origin.width += stackDragTranslation.width
                    origin.height += stackDragTranslation.height
                }
                return origin
            },
            set: { [self] in settle(id, at: $0, in: dock) })
    }

    /// Commit a released panel: grid-snap, clamp inside the dock, then stick it
    /// flush when it landed within tolerance of a dock edge.
    private func settle(_ id: ID, at position: CGSize, in dock: CGSize) {
        let size = model.size(id)
        var point = CGPoint(x: position.width, y: position.height)
        let grid = model.gridStep
        if grid > 0 {
            point = CGPoint(
                x: (point.x / grid).rounded() * grid, y: (point.y / grid).rounded() * grid)
        }
        let clamped = PanelPlacement.clamped(point, panelSize: size, dock: dock)
        let x = PanelPlacement.edgeStuckX(clamped.x, panelWidth: size.width, dockWidth: dock.width)
        model.setPosition(id, to: CGSize(width: x, height: clamped.y), in: dock)
    }

    public func dragChanged(_ id: ID, translation: CGSize, in dock: CGSize) {
        if model.isStackFollower(id) {
            // Grabbing a follower by its header detaches it; the rest close up.
            model.detachForDrag(id, in: dock)
        } else if !model.stacks.followers(of: model.stackKey(id)).isEmpty {
            // Grabbing the head moves its followers along, live.
            stackDragHead = id
            stackDragTranslation = translation
        }
    }

    public func dragEnded(_ id: ID, in dock: CGSize) {
        stackDragHead = nil
        stackDragTranslation = .zero
        model.snapReleased(id, in: dock)
    }

    /// Place freshly-opened panels into a clean slot rather than a stale spot
    /// that overlaps an open panel or hangs off the dock.
    public func placePending(in dock: CGSize) {
        guard dock.width > 0 else { return }
        for id in model.takePendingPlacement() {
            guard model.isExpanded(id) else { continue }
            let size = model.size(id)
            let others = model.order
                .filter { $0 != id && model.isExpanded($0) }
                .map { other -> CGRect in
                    let origin = model.displayPosition(other, in: dock)
                    return CGRect(
                        origin: CGPoint(x: origin.width, y: origin.height), size: model.size(other))
                }
            let stored = model.position(id, in: dock)
            let frame = CGRect(origin: CGPoint(x: stored.width, y: stored.height), size: size)
            let fits =
                frame.minX >= 0 && frame.maxX <= dock.width && frame.minY >= 0
                && frame.minY + PanelPlacement.headerHeight <= dock.height
            if fits && !PanelPlacement.overlaps(frame, any: others) { continue }
            let slot = PanelPlacement.openingSlot(panelSize: size, dock: dock, openFrames: others)
            model.setPosition(id, to: CGSize(width: slot.x, height: slot.y), in: dock)
        }
    }
}
