import SwiftUI
import ImageKidKit

/// App-specific dockable panels. The reusable dock mechanics live in ImageKidKit.
enum DockablePanel: String, CaseIterable, Identifiable, Hashable {
    case files
    case layers
    case history

    var id: String { rawValue }

    static let gridStep: CGFloat = 20

    /// Consistent width for all panels.
    static let panelWidth: CGFloat = 280

    var spec: DockPanelSpec<DockablePanel> {
        switch self {
        case .files:
            DockPanelSpec(id: self, title: "Files", systemImage: "photo.on.rectangle.angled",
                          defaultPosition: CGSize(width: 0, height: 0),
                          defaultSize: CGSize(width: Self.panelWidth, height: 220))
        case .layers:
            DockPanelSpec(id: self, title: "Layers", systemImage: "square.3.layers.3d",
                          defaultPosition: CGSize(width: 0, height: 240),
                          defaultSize: CGSize(width: Self.panelWidth, height: 420))
        case .history:
            DockPanelSpec(id: self, title: "History", systemImage: "clock.arrow.circlepath",
                          defaultPosition: CGSize(width: 300, height: 0),
                          defaultSize: CGSize(width: Self.panelWidth, height: 340))
        }
    }

    static var allSpecs: [DockPanelSpec<DockablePanel>] { allCases.map(\.spec) }
}

extension PanelDockModel where ID == DockablePanel {
    static func makeDefault() -> PanelDockModel<DockablePanel> {
        PanelDockModel(
            panels: DockablePanel.allSpecs,
            gridStep: DockablePanel.gridStep,
            minSize: CGSize(width: 220, height: 200),
            maxSize: CGSize(width: 520, height: 900),
            initiallyPresented: [.files]
        )
    }
}
