import SwiftUI

/// Static description of a dockable panel: its identity, label, icon, and
/// default resting geometry.
public struct DockPanelSpec<ID: Hashable>: Identifiable {
    public let id: ID
    public let title: String
    public let systemImage: String
    public let defaultPosition: CGSize
    public let defaultSize: CGSize

    public init(
        id: ID,
        title: String,
        systemImage: String,
        defaultPosition: CGSize = .zero,
        defaultSize: CGSize = CGSize(width: 280, height: 360)
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.defaultPosition = defaultPosition
        self.defaultSize = defaultSize
    }
}

/// A floating panel's resting spot stored edge-relative to the dock, so a
/// right-docked panel rides the right edge across window resizes (0 offset is
/// always flush against its edge). Mirrors Fekthor's palette anchors.
public struct PanelAnchor: Codable, Equatable, Sendable {
    public var side: PanelDockSide
    public var offset: CGFloat
    public var y: CGFloat

    public init(side: PanelDockSide, offset: CGFloat, y: CGFloat) {
        self.side = side
        self.offset = offset
        self.y = y
    }
}

/// Reusable state for a set of movable / minimizable / resizable panels that
/// snap to a grid, stick to each other, and dock/stick to the workspace edges.
/// Generic over an app-defined panel identifier.
@MainActor
public final class PanelDockModel<ID: Hashable>: ObservableObject {
    public let order: [ID]
    public let specs: [ID: DockPanelSpec<ID>]
    public let gridStep: CGFloat
    public let minSize: CGSize
    public let maxSize: CGSize
    /// When set, presented/minimized panels and the stacking arrangement
    /// persist in UserDefaults under keys prefixed with this string.
    public let defaultsKey: String?

    @Published public var presented: Set<ID> { didSet { persistPanelSets() } }
    @Published public var minimized: Set<ID> = [] { didSet { persistPanelSets() } }
    @Published public var positions: [ID: CGSize] = [:] { didSet { persistGeometry() } }
    @Published public var sizes: [ID: CGSize] = [:] { didSet { persistGeometry() } }
    /// Which panels are magnetically stuck together (ordered top → bottom),
    /// keyed by `stackKey(_:)`.
    @Published public var stacks = PanelStacks() { didSet { persistStacks() } }
    /// Edge-relative resting anchors — the source of truth for head/unstacked
    /// panels once they've been moved. `positions` is kept only to migrate
    /// pre-anchor stored spots (see `migrateLegacyPositions(in:)`).
    @Published private var anchors: [ID: PanelAnchor] = [:] { didSet { persistAnchors() } }
    /// Freshly shown panels that still need a non-overlapping opening slot in
    /// the dock. Drained by the host layer (which knows the live frames);
    /// never persisted.
    @Published public var needsPlacement: Set<ID> = []

    public init(
        panels: [DockPanelSpec<ID>],
        gridStep: CGFloat = 20,
        minSize: CGSize = CGSize(width: 220, height: 200),
        maxSize: CGSize = CGSize(width: 520, height: 900),
        initiallyPresented: Set<ID> = [],
        defaultsKey: String? = nil
    ) {
        self.order = panels.map(\.id)
        self.specs = Dictionary(uniqueKeysWithValues: panels.map { ($0.id, $0) })
        self.gridStep = gridStep
        self.minSize = minSize
        self.maxSize = maxSize
        self.defaultsKey = defaultsKey
        self.presented = initiallyPresented
        loadPersisted()
    }

    // MARK: - Persistence

    private func loadPersisted() {
        guard let defaultsKey else { return }
        let defaults = UserDefaults.standard
        let byKey = Dictionary(
            uniqueKeysWithValues: order.map { (String(describing: $0), $0) })
        if let raw = defaults.array(forKey: defaultsKey + ".presented") as? [String] {
            presented = Set(raw.compactMap { byKey[$0] })
        }
        if let raw = defaults.array(forKey: defaultsKey + ".minimized") as? [String] {
            minimized = Set(raw.compactMap { byKey[$0] })
        }
        if let raw = defaults.dictionary(forKey: defaultsKey + ".positions") as? [String: [Double]] {
            for (key, value) in raw where value.count == 2 {
                guard let id = byKey[key] else { continue }
                positions[id] = CGSize(width: value[0], height: value[1])
            }
        }
        if let raw = defaults.dictionary(forKey: defaultsKey + ".sizes") as? [String: [Double]] {
            for (key, value) in raw where value.count == 2 {
                guard let id = byKey[key] else { continue }
                sizes[id] = CGSize(width: value[0], height: value[1])
            }
        }
        if let data = defaults.data(forKey: defaultsKey + ".anchors"),
            let decoded = try? JSONDecoder().decode([String: PanelAnchor].self, from: data)
        {
            for (key, anchor) in decoded {
                guard let id = byKey[key] else { continue }
                anchors[id] = anchor
            }
        }
        if let data = defaults.data(forKey: defaultsKey + ".stacks"),
            var decoded = try? JSONDecoder().decode(PanelStacks.self, from: data)
        {
            // A panel that is unknown, hidden or minimized cannot stay stuck.
            for key in decoded.stacks.flatMap({ $0 }) {
                guard let id = byKey[key], isExpanded(id) else {
                    decoded.detach(key)
                    continue
                }
            }
            stacks = decoded
        }
    }

    private func persistPanelSets() {
        guard let defaultsKey else { return }
        let defaults = UserDefaults.standard
        defaults.set(
            presented.map { String(describing: $0) }.sorted(),
            forKey: defaultsKey + ".presented")
        defaults.set(
            minimized.map { String(describing: $0) }.sorted(),
            forKey: defaultsKey + ".minimized")
    }

    /// Panel resting spots and sizes survive relaunches alongside the
    /// presented/minimized sets, so a dock-managed panel keeps the place the
    /// user dragged it to (what per-panel @AppStorage offsets used to do).
    private func persistGeometry() {
        guard let defaultsKey else { return }
        let defaults = UserDefaults.standard
        defaults.set(
            Dictionary(uniqueKeysWithValues: positions.map {
                (String(describing: $0.key), [Double($0.value.width), Double($0.value.height)])
            }),
            forKey: defaultsKey + ".positions")
        defaults.set(
            Dictionary(uniqueKeysWithValues: sizes.map {
                (String(describing: $0.key), [Double($0.value.width), Double($0.value.height)])
            }),
            forKey: defaultsKey + ".sizes")
    }

    private func persistStacks() {
        guard let defaultsKey else { return }
        guard let data = try? JSONEncoder().encode(stacks) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey + ".stacks")
    }

    private func persistAnchors() {
        guard let defaultsKey else { return }
        let byString = Dictionary(
            uniqueKeysWithValues: anchors.map { (String(describing: $0.key), $0.value) })
        guard let data = try? JSONEncoder().encode(byString) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey + ".anchors")
    }

    public func spec(_ id: ID) -> DockPanelSpec<ID>? { specs[id] }

    public func isExpanded(_ id: ID) -> Bool {
        presented.contains(id) && !minimized.contains(id)
    }

    /// The stack neighbour a hidden/minimized panel sat next to, and on which
    /// side, so showing it again rebuilds the same stack. `neighbourBelow`
    /// true means the panel was the head (neighbour under it); false means it
    /// was a follower (neighbour = its predecessor above).
    private struct StackLink { let neighbour: String; let neighbourBelow: Bool }
    private var stackMemory: [ID: StackLink] = [:]

    /// Record the adjacent panel before `id` leaves a stack: its predecessor
    /// if it's a follower, otherwise its first follower if it's the head.
    private func rememberStack(_ id: ID) {
        let key = stackKey(id)
        guard let stack = stacks.stack(containing: key),
            let index = stack.firstIndex(of: key)
        else { stackMemory[id] = nil; return }
        if index > 0 {
            stackMemory[id] = StackLink(neighbour: stack[index - 1], neighbourBelow: false)
        } else if stack.count > 1 {
            stackMemory[id] = StackLink(neighbour: stack[index + 1], neighbourBelow: true)
        } else {
            stackMemory[id] = nil
        }
    }

    /// Reveal a now-presented panel where it belongs: rebuild the stack it
    /// left (re-attach under its predecessor, or pull its follower chain back
    /// under it if it was the head) when the neighbour is still open;
    /// otherwise back at its last spot. Only a panel that has *never* been
    /// placed — or a former follower whose stack is gone (its stored spot is a
    /// stale head-derived coordinate) — gets a fresh opening slot.
    private func revealPlacement(_ id: ID) {
        let key = stackKey(id)
        if let link = stackMemory[id] {
            stackMemory[id] = nil
            if let target = panel(forStackKey: link.neighbour), isExpanded(target) {
                if link.neighbourBelow {
                    stacks.attach(link.neighbour, below: key)
                    syncStackWidths(containing: key)
                } else {
                    stacks.attach(key, below: link.neighbour)
                    syncStackWidths(containing: link.neighbour)
                }
                return
            }
            if !link.neighbourBelow { needsPlacement.insert(id); return }
        }
        if !hasPlacement(id) { needsPlacement.insert(id) }
    }

    public func toggle(_ id: ID) {
        if presented.contains(id) {
            rememberStack(id)
            stacks.detach(stackKey(id))
            presented.remove(id)
            minimized.remove(id)
        } else {
            presented.insert(id)
            minimized.remove(id)
            revealPlacement(id)
        }
    }

    /// Collapse to the rail's icon-only button. A stacked panel detaches
    /// first — its followers close up, and an icon can't be a stick target —
    /// but we remember the stack so restoring re-attaches it.
    public func minimize(_ id: ID) {
        rememberStack(id)
        stacks.detach(stackKey(id))
        minimized.insert(id)
    }

    public func restore(_ id: ID) {
        presented.insert(id)
        minimized.remove(id)
        revealPlacement(id)
    }

    public func position(_ id: ID) -> CGSize {
        positions[id] ?? specs[id]?.defaultPosition ?? .zero
    }

    /// Store a dropped position snapped to the nearest grid intersection.
    public func setPosition(_ id: ID, to position: CGSize) {
        positions[id] = CGSize(
            width: max(0, (position.width / gridStep).rounded() * gridStep),
            height: max(0, (position.height / gridStep).rounded() * gridStep)
        )
    }

    public func size(_ id: ID) -> CGSize {
        sizes[id] ?? specs[id]?.defaultSize ?? CGSize(width: 280, height: 360)
    }

    public func setSize(_ id: ID, to size: CGSize) {
        let newWidth = min(max(size.width, minSize.width), maxSize.width)
        // The resize handle is the bottom-trailing corner, so a widen should
        // keep the LEADING edge put and grow rightward. A right-side anchor is
        // stored trailing-edge-relative, so resolving it with the new width
        // would otherwise shove the panel left by the whole width delta —
        // compensate by shrinking the trailing offset to hold the leading edge.
        if let anchor = anchors[id], anchor.side == .right {
            let delta = newWidth - self.size(id).width
            if delta != 0 {
                anchors[id] = PanelAnchor(
                    side: .right, offset: anchor.offset - delta, y: anchor.y)
            }
        }
        sizes[id] = CGSize(
            width: newWidth,
            height: min(max(size.height, minSize.height), maxSize.height)
        )
    }

    public var minimizedList: [ID] {
        order.filter { presented.contains($0) && minimized.contains($0) }
    }

    /// Rail button behaviour: show if hidden, restore if minimized, hide if open.
    public func railToggle(_ id: ID) {
        if !presented.contains(id) {
            presented.insert(id)
            minimized.remove(id)
            revealPlacement(id)
        } else if minimized.contains(id) {
            minimized.remove(id)
            revealPlacement(id)
        } else {
            rememberStack(id)
            stacks.detach(stackKey(id))
            presented.remove(id)
            minimized.remove(id)
        }
    }

    public func positionBinding(_ id: ID) -> Binding<CGSize> {
        Binding(get: { self.position(id) }, set: { self.setPosition(id, to: $0) })
    }

    public func sizeBinding(_ id: ID) -> Binding<CGSize> {
        Binding(get: { self.size(id) }, set: { self.setSize(id, to: $0) })
    }

    // MARK: - Stacking

    /// Stable string identity for the stacking model (an enum's case name).
    public func stackKey(_ id: ID) -> String { String(describing: id) }

    private func panel(forStackKey key: String) -> ID? {
        order.first { stackKey($0) == key }
    }

    public func isStackFollower(_ id: ID) -> Bool {
        stacks.isFollower(stackKey(id))
    }

    /// Flattened-corner edges for the panel chrome on its stick lines.
    public func stackEdges(of id: ID) -> (topFlat: Bool, bottomFlat: Bool) {
        let key = stackKey(id)
        return (stacks.isFollower(key), !stacks.followers(of: key).isEmpty)
    }

    /// Where the panel actually rests: followers derive their origin from
    /// their stack head so the stack always reads flush, heads and unstacked
    /// panels use their stored position.
    public func displayPosition(_ id: ID) -> CGSize {
        let key = stackKey(id)
        guard let stack = stacks.stack(containing: key), stack.first != key,
            let headID = panel(forStackKey: stack[0])
        else { return position(id) }
        let head = position(headID)
        var memberSizes: [String: CGSize] = [:]
        for memberKey in stack {
            guard let member = panel(forStackKey: memberKey) else { continue }
            memberSizes[memberKey] = size(member)
        }
        let origins = PanelStacks.layout(
            stack: stack,
            headOrigin: CGPoint(x: head.width, y: head.height),
            sizes: memberSizes)
        guard let origin = origins[key] else { return position(id) }
        return CGSize(width: origin.x, height: origin.y)
    }

    /// Grabbing a follower's header detaches it: freeze it exactly where it
    /// rests (deliberately not grid-snapped, so the drag continues without a
    /// jump) and pull it out of its stack — the panels below close up.
    public func detachForDrag(_ id: ID) {
        let key = stackKey(id)
        guard stacks.isFollower(key) else { return }
        positions[id] = displayPosition(id)
        stacks.detach(key)
    }

    /// Frames of every expanded panel (origin = display position), the input
    /// for stick detection on release.
    public func expandedFrames() -> [String: CGRect] {
        var frames: [String: CGRect] = [:]
        for id in order where isExpanded(id) {
            let origin = displayPosition(id)
            frames[stackKey(id)] = CGRect(
                origin: CGPoint(x: origin.width, y: origin.height), size: size(id))
        }
        return frames
    }

    /// Stick detection for a released panel: attach it (and its followers)
    /// under the closest candidate, syncing every member to the head's width.
    public func snapReleased(_ id: ID) {
        let key = stackKey(id)
        let frames = expandedFrames()
        guard let dragged = frames[key],
            let target = stacks.snapCandidate(for: key, frame: dragged, others: frames)
        else { return }
        stacks.attach(key, below: target)
        syncStackWidths(containing: target)
    }

    /// The whole stack keeps the head's width.
    private func syncStackWidths(containing key: String) {
        guard let stack = stacks.stack(containing: key),
            let headID = panel(forStackKey: stack[0])
        else { return }
        let width = size(headID).width
        for memberKey in stack.dropFirst() {
            guard let member = panel(forStackKey: memberKey) else { continue }
            let current = size(member)
            if current.width != width {
                sizes[member] = CGSize(width: width, height: current.height)
            }
        }
    }

    // MARK: - Edge docking (dock-size aware)
    //
    // These mirror Fekthor's palette placement (`PanelPlacement`): a stored
    // anchor resolves to an absolute spot in the CURRENT dock and is clamped so
    // the panel stays reachable; drops stick flush to the dock edges; freshly
    // opened panels take a non-overlapping slot. The dock-agnostic methods
    // above stay for the stacking maths and any caller without a dock size.

    private func panelWidth(_ id: ID) -> CGFloat { size(id).width }

    /// Whether the panel has a resting spot yet — an edge anchor or a legacy
    /// absolute position. False means it still sits at its spec default, so a
    /// host can seed a first-run spot without clobbering a user's placement.
    public func hasPlacement(_ id: ID) -> Bool {
        anchors[id] != nil || positions[id] != nil
    }

    /// Where the panel rests in the CURRENT dock: its stored anchor resolved
    /// against this dock width (right-anchored panels ride the right edge) and
    /// clamped in-bounds. Falls back to any pre-anchor absolute spot, then the
    /// spec default.
    public func position(_ id: ID, in dock: CGSize) -> CGSize {
        if let anchor = anchors[id] {
            let width = panelWidth(id)
            guard dock.width > 0 else {
                return CGSize(width: anchor.side == .left ? anchor.offset : 0, height: anchor.y)
            }
            let point = PanelPlacement.clamped(
                CGPoint(
                    x: PanelPlacement.resolveX(
                        side: anchor.side, edgeOffset: anchor.offset,
                        panelWidth: width, dockWidth: dock.width),
                    y: anchor.y),
                panelSize: size(id), dock: dock)
            return CGSize(width: point.x, height: point.y)
        }
        if let legacy = positions[id] { return legacy }
        return specs[id]?.defaultPosition ?? .zero
    }

    /// Store a dropped spot as an edge anchor: the side is the panel centre
    /// against the dock midpoint, the offset that side's edge distance. Clears
    /// any legacy absolute position for this panel.
    public func setPosition(_ id: ID, to position: CGSize, in dock: CGSize) {
        let width = panelWidth(id)
        let side: PanelDockSide =
            dock.width > 0
            ? PanelPlacement.side(ofPanelAt: position.width, panelWidth: width, dockWidth: dock.width)
            : .left
        anchors[id] = PanelAnchor(
            side: side,
            offset: PanelPlacement.edgeOffset(
                forPanelAt: position.width, side: side, panelWidth: width, dockWidth: dock.width),
            y: position.height)
        if positions[id] != nil { positions[id] = nil }
    }

    /// One-time conversion of pre-anchor absolute positions into edge anchors,
    /// run by the host once a believable dock size is known (side/offset need
    /// the real dock width, or every panel misfiles as left-docked).
    public func migrateLegacyPositions(in dock: CGSize) {
        guard dock.width >= 300, !positions.isEmpty else { return }
        let legacy = positions
        for (id, position) in legacy { setPosition(id, to: position, in: dock) }
        positions = [:]
    }

    /// Where the panel actually rests now (dock-aware): followers derive their
    /// origin from their stack head so the stack always reads flush.
    public func displayPosition(_ id: ID, in dock: CGSize) -> CGSize {
        let key = stackKey(id)
        guard let stack = stacks.stack(containing: key), stack.first != key,
            let headID = panel(forStackKey: stack[0])
        else { return position(id, in: dock) }
        let head = position(headID, in: dock)
        var memberSizes: [String: CGSize] = [:]
        for memberKey in stack {
            guard let member = panel(forStackKey: memberKey) else { continue }
            memberSizes[memberKey] = size(member)
        }
        let origins = PanelStacks.layout(
            stack: stack, headOrigin: CGPoint(x: head.width, y: head.height), sizes: memberSizes)
        guard let origin = origins[key] else { return position(id, in: dock) }
        return CGSize(width: origin.x, height: origin.y)
    }

    /// Flatten the chrome's leading/trailing corners when the panel sits flush
    /// against a dock edge — the visual "stuck to the edge" cue.
    public func dockEdges(of id: ID, in dock: CGSize) -> (leadingFlat: Bool, trailingFlat: Bool) {
        guard dock.width > 0 else { return (false, false) }
        let origin = displayPosition(id, in: dock)
        let width = size(id).width
        return (origin.width <= 0.5, origin.width + width >= dock.width - 0.5)
    }

    /// Frames of every expanded panel in the current dock — the input for
    /// stick detection and opening-slot placement.
    public func expandedFrames(in dock: CGSize) -> [String: CGRect] {
        var frames: [String: CGRect] = [:]
        for id in order where isExpanded(id) {
            let origin = displayPosition(id, in: dock)
            frames[stackKey(id)] = CGRect(
                origin: CGPoint(x: origin.width, y: origin.height), size: size(id))
        }
        return frames
    }

    /// Grabbing a follower's header detaches it: freeze it exactly where it
    /// rests (as an anchor, not grid-snapped) and pull it from its stack.
    public func detachForDrag(_ id: ID, in dock: CGSize) {
        let key = stackKey(id)
        guard stacks.isFollower(key) else { return }
        setPosition(id, to: displayPosition(id, in: dock), in: dock)
        stacks.detach(key)
    }

    /// Stick detection for a released panel against the current dock frames.
    public func snapReleased(_ id: ID, in dock: CGSize) {
        let key = stackKey(id)
        let frames = expandedFrames(in: dock)
        guard let dragged = frames[key],
            let target = stacks.snapCandidate(for: key, frame: dragged, others: frames)
        else { return }
        stacks.attach(key, below: target)
        syncStackWidths(containing: target)
    }

    /// Drain the freshly-opened panels awaiting placement, in dock order.
    public func takePendingPlacement() -> [ID] {
        guard !needsPlacement.isEmpty else { return [] }
        let pending = order.filter { needsPlacement.contains($0) }
        needsPlacement = []
        return pending
    }
}

/// A minimized panel collapsed to a single icon-only button: the shared look
/// for ImageKid's dock rail and Fekthor's minimized-palette strip.
public struct MinimizedPanelChip: View {
    let systemImage: String
    let isActive: Bool
    let action: () -> Void

    public init(systemImage: String, isActive: Bool = false, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.isActive = isActive
        self.action = action
    }

    /// 38pt reads right next to macOS chrome; touch needs the full 44pt.
    private var chipSize: CGFloat {
        #if os(iOS)
        44
        #else
        38
        #endif
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: chipSize, height: chipSize)
                .background(
                    isActive ? Color.accentColor.opacity(0.9) : Color.black.opacity(0.80),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(.white.opacity(isActive ? 0.0 : 0.12))
                )
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

/// Always-visible rail of toggle buttons — one per panel. Each button
/// shows/hides its panel and is highlighted while the panel is open.
/// Lay out vertically (default) or horizontally.
public struct PanelDockRail<ID: Hashable>: View {
    @ObservedObject var model: PanelDockModel<ID>
    let axis: Axis

    public init(model: PanelDockModel<ID>, axis: Axis = .vertical) {
        self.model = model
        self.axis = axis
    }

    public var body: some View {
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: 8))
            : AnyLayout(VStackLayout(spacing: 8))
        layout {
            ForEach(model.order, id: \.self) { id in
                if let spec = model.spec(id) {
                    let isActive = model.isExpanded(id)
                    MinimizedPanelChip(systemImage: spec.systemImage, isActive: isActive) {
                        model.railToggle(id)
                    }
                    .help((isActive ? "Hide " : "Show ") + spec.title)
                }
            }
        }
    }
}
