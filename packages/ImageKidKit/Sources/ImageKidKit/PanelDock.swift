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

    @Published public var presented: Set<ID>
    @Published public var minimized: Set<ID> = []
    @Published public var positions: [ID: CGSize] = [:]
    @Published public var sizes: [ID: CGSize] = [:]

    public init(
        panels: [DockPanelSpec<ID>],
        gridStep: CGFloat = 20,
        minSize: CGSize = CGSize(width: 220, height: 200),
        maxSize: CGSize = CGSize(width: 520, height: 900),
        initiallyPresented: Set<ID> = []
    ) {
        self.order = panels.map(\.id)
        self.specs = Dictionary(uniqueKeysWithValues: panels.map { ($0.id, $0) })
        self.gridStep = gridStep
        self.minSize = minSize
        self.maxSize = maxSize
        self.presented = initiallyPresented
    }

    public func spec(_ id: ID) -> DockPanelSpec<ID>? { specs[id] }

    public func isExpanded(_ id: ID) -> Bool {
        presented.contains(id) && !minimized.contains(id)
    }

    public func toggle(_ id: ID) {
        if presented.contains(id) {
            presented.remove(id)
            minimized.remove(id)
        } else {
            presented.insert(id)
            minimized.remove(id)
        }
    }

    public func minimize(_ id: ID) { minimized.insert(id) }

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
                    Button {
                        model.railToggle(id)
                    } label: {
                        Image(systemName: spec.systemImage)
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 38, height: 38)
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
                    .help((isActive ? "Hide " : "Show ") + spec.title)
                }
            }
        }
    }
}
