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

/// Reusable state for a set of movable / minimizable / resizable panels that
/// snap to a grid. Generic over an app-defined panel identifier.
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
    @Published public var positions: [ID: CGSize] = [:]
    @Published public var sizes: [ID: CGSize] = [:]
    /// Which panels are magnetically stuck together (ordered top → bottom),
    /// keyed by `stackKey(_:)`.
    @Published public var stacks = PanelStacks() { didSet { persistStacks() } }

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

    private func persistStacks() {
        guard let defaultsKey else { return }
        guard let data = try? JSONEncoder().encode(stacks) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey + ".stacks")
    }

    public func spec(_ id: ID) -> DockPanelSpec<ID>? { specs[id] }

    public func isExpanded(_ id: ID) -> Bool {
        presented.contains(id) && !minimized.contains(id)
    }

    public func toggle(_ id: ID) {
        if presented.contains(id) {
            stacks.detach(stackKey(id))
            presented.remove(id)
            minimized.remove(id)
        } else {
            presented.insert(id)
            minimized.remove(id)
        }
    }

    /// Collapse to the rail's icon-only button. A stacked panel detaches
    /// first — its followers close up, and an icon can't be a stick target.
    public func minimize(_ id: ID) {
        stacks.detach(stackKey(id))
        minimized.insert(id)
    }

    public func restore(_ id: ID) {
        presented.insert(id)
        minimized.remove(id)
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
        sizes[id] = CGSize(
            width: min(max(size.width, minSize.width), maxSize.width),
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
        } else if minimized.contains(id) {
            minimized.remove(id)
        } else {
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

/// Always-visible vertical rail of toggle buttons — one per panel. Each button
/// shows/hides its panel and is highlighted while the panel is open.
public struct PanelDockRail<ID: Hashable>: View {
    @ObservedObject var model: PanelDockModel<ID>

    public init(model: PanelDockModel<ID>) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 8) {
            ForEach(model.order, id: \.self) { id in
                if let spec = model.spec(id) {
                    let isActive = model.presented.contains(id)
                    MinimizedPanelChip(systemImage: spec.systemImage, isActive: isActive) {
                        model.railToggle(id)
                    }
                    .help((isActive ? "Hide " : "Show ") + spec.title)
                }
            }
        }
    }
}
