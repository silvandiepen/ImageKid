import SwiftUI
import ImageKidKit

/// The mutually-exclusive, tool-driven context inspectors (Resize, Rotate,
/// Crop, …). Unlike the dockable panels they are shown by the active tool, not
/// a rail, and never coexist — so there is no stacking, just per-panel edge
/// placement.
enum ToolPanel: String, CaseIterable {
    case resize, rotate, transform, crop, selection, colorPalette
    case maskEdit, backgroundRefine, drawing, text, grid

    /// The panel chrome width, needed to resolve/clamp right-edge anchors.
    /// Keep in sync with each control's `FloatingToolPanel(width:)`.
    var width: CGFloat {
        switch self {
        case .resize: 310
        case .transform: 280
        case .crop: 290
        case .selection: 240
        default: 300
        }
    }
}

/// Per-inspector edge placement, mirroring the dockable panels' sticking:
/// a dropped spot is stored edge-relative (so it rides the right edge across
/// window resizes) and clamped so the panel stays reachable. One shared store
/// keeps every tool inspector's last spot across tool switches and relaunches.
@MainActor
final class ToolInspectorPlacement: ObservableObject {
    @Published private var anchors: [ToolPanel: PanelAnchor] = [:]

    private static let key = "imagekid.toolinspector.anchors"
    /// Default resting inset from the top, clearing the floating toolbar.
    private static let defaultTop: CGFloat = 54
    private static let gridStep: CGFloat = 20

    init() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
            let decoded = try? JSONDecoder().decode([String: PanelAnchor].self, from: data)
        else { return }
        for (raw, anchor) in decoded {
            guard let panel = ToolPanel(rawValue: raw) else { continue }
            anchors[panel] = anchor
        }
    }

    private func persist() {
        let byString = Dictionary(
            uniqueKeysWithValues: anchors.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(byString) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    /// Where the inspector rests in the CURRENT dock: its stored anchor
    /// resolved to this dock width and clamped, or the top-right default.
    func position(_ panel: ToolPanel, in dock: CGSize) -> CGSize {
        let width = panel.width
        guard dock.width > 0 else { return .zero }
        if let anchor = anchors[panel] {
            let point = PanelPlacement.clamped(
                CGPoint(
                    x: PanelPlacement.resolveX(
                        side: anchor.side, edgeOffset: anchor.offset,
                        panelWidth: width, dockWidth: dock.width),
                    y: anchor.y),
                panelSize: CGSize(width: width, height: PanelPlacement.headerHeight),
                dock: dock)
            return CGSize(width: point.x, height: point.y)
        }
        return CGSize(
            width: max(0, dock.width - width - PanelPlacement.margin),
            height: Self.defaultTop)
    }

    /// Commit a released inspector: grid-snap, clamp inside the dock, then
    /// stick flush when within 14pt of a dock edge — stored as an edge anchor.
    func settle(_ panel: ToolPanel, at position: CGSize, in dock: CGSize) {
        guard dock.width > 0 else { return }
        let width = panel.width
        var point = CGPoint(x: position.width, y: position.height)
        point = CGPoint(
            x: (point.x / Self.gridStep).rounded() * Self.gridStep,
            y: (point.y / Self.gridStep).rounded() * Self.gridStep)
        let clamped = PanelPlacement.clamped(
            point, panelSize: CGSize(width: width, height: PanelPlacement.headerHeight), dock: dock)
        let x = PanelPlacement.edgeStuckX(clamped.x, panelWidth: width, dockWidth: dock.width)
        let side = PanelPlacement.side(ofPanelAt: x, panelWidth: width, dockWidth: dock.width)
        anchors[panel] = PanelAnchor(
            side: side,
            offset: PanelPlacement.edgeOffset(
                forPanelAt: x, side: side, panelWidth: width, dockWidth: dock.width),
            y: clamped.y)
        persist()
    }

    /// Flatten the leading/trailing corners when the inspector is flush against
    /// a dock edge.
    func dockEdges(_ panel: ToolPanel, in dock: CGSize) -> (leadingFlat: Bool, trailingFlat: Bool) {
        guard dock.width > 0 else { return (false, false) }
        let origin = position(panel, in: dock)
        return (origin.width <= 0.5, origin.width + panel.width >= dock.width - 0.5)
    }

    func offsetBinding(_ panel: ToolPanel, in dock: CGSize) -> Binding<CGSize> {
        Binding(
            get: { self.position(panel, in: dock) },
            set: { self.settle(panel, at: $0, in: dock) })
    }
}
