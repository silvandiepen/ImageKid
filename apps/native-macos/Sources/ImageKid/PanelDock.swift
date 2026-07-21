import SwiftUI

/// Floating panels that can be moved freely, snapped to a grid, and minimized
/// to an icon rail in the top-left corner.
enum DockablePanel: String, CaseIterable, Identifiable {
    case files
    case layers
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .files: "Files"
        case .layers: "Layers"
        case .history: "History"
        }
    }

    var systemImage: String {
        switch self {
        case .files: "photo.on.rectangle.angled"
        case .layers: "square.3.layers.3d"
        case .history: "clock.arrow.circlepath"
        }
    }

    /// Default resting position (offset from the top-left content anchor).
    var defaultPosition: CGSize {
        switch self {
        case .files: CGSize(width: 0, height: 0)
        case .layers: CGSize(width: 0, height: 0)
        case .history: CGSize(width: 0, height: 300)
        }
    }
}

extension AppModel {
    static let panelGridStep: CGFloat = 20

    func isPanelExpanded(_ panel: DockablePanel) -> Bool {
        presentedPanels.contains(panel) && !minimizedPanels.contains(panel)
    }

    func togglePanel(_ panel: DockablePanel) {
        if presentedPanels.contains(panel) {
            presentedPanels.remove(panel)
            minimizedPanels.remove(panel)
        } else {
            presentedPanels.insert(panel)
            minimizedPanels.remove(panel)
        }
    }

    func minimizePanel(_ panel: DockablePanel) {
        minimizedPanels.insert(panel)
    }

    func restorePanel(_ panel: DockablePanel) {
        presentedPanels.insert(panel)
        minimizedPanels.remove(panel)
    }

    func panelPosition(_ panel: DockablePanel) -> CGSize {
        panelPositions[panel] ?? panel.defaultPosition
    }

    /// Store a dropped position snapped to the nearest grid intersection.
    func setPanelPosition(_ panel: DockablePanel, to position: CGSize) {
        let step = Self.panelGridStep
        panelPositions[panel] = CGSize(
            width: max(0, (position.width / step).rounded() * step),
            height: max(0, (position.height / step).rounded() * step)
        )
    }

    /// Panels that are present but collapsed to the dock rail.
    var minimizedPanelList: [DockablePanel] {
        DockablePanel.allCases.filter { presentedPanels.contains($0) && minimizedPanels.contains($0) }
    }
}

/// Vertical rail of icons for minimized panels, shown top-left. Click to restore.
struct PanelDockRail: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        VStack(spacing: 8) {
            ForEach(appModel.minimizedPanelList) { panel in
                Button {
                    appModel.restorePanel(panel)
                } label: {
                    Image(systemName: panel.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .background(Color.black.opacity(0.80), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(.white.opacity(0.12))
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .help("Show \(panel.title)")
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
}
