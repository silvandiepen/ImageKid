import AppKit
import FekthorKit
import SwiftUI

extension Notification.Name {
    static let fekthorNewFile = Notification.Name("fekthor.newFile")
    static let fekthorOpen = Notification.Name("fekthor.open")
    static let fekthorOpenWorkspace = Notification.Name("fekthor.openWorkspace")
    static let fekthorSave = Notification.Name("fekthor.save")
    static let fekthorSaveAs = Notification.Name("fekthor.saveAs")
    static let fekthorTraceImage = Notification.Name("fekthor.traceImage")
    static let fekthorGroup = Notification.Name("fekthor.group")
    static let fekthorUngroup = Notification.Name("fekthor.ungroup")
    static let fekthorBringForward = Notification.Name("fekthor.bringForward")
    static let fekthorSendBackward = Notification.Name("fekthor.sendBackward")
    static let fekthorBringToFront = Notification.Name("fekthor.bringToFront")
    static let fekthorSendToBack = Notification.Name("fekthor.sendToBack")
    static let fekthorWorkspaceExport = Notification.Name("fekthor.workspaceExport")
    static let fekthorWorkspaceTokens = Notification.Name("fekthor.workspaceTokens")
    static let fekthorWorkspaceSettings = Notification.Name("fekthor.workspaceSettings")
    static let fekthorToggleGrid = Notification.Name("fekthor.toggleGrid")
    static let fekthorToggleSnap = Notification.Name("fekthor.toggleSnap")
    static let fekthorToggleGuide = Notification.Name("fekthor.toggleGuide")
    static let fekthorPathUnite = Notification.Name("fekthor.pathUnite")
    static let fekthorPathSubtract = Notification.Name("fekthor.pathSubtract")
    static let fekthorPathIntersect = Notification.Name("fekthor.pathIntersect")
    static let fekthorPathExclude = Notification.Name("fekthor.pathExclude")
    /// userInfo["edge"]: AlignEdge — one notification for all six edges.
    static let fekthorAlign = Notification.Name("fekthor.align")
    /// userInfo["axis"]: DistributeAxis.
    static let fekthorDistribute = Notification.Name("fekthor.distribute")
    static let fekthorExportPNG = Notification.Name("fekthor.exportPNG")
    static let fekthorExportPDF = Notification.Name("fekthor.exportPDF")
    static let fekthorWorkspaceAnimations = Notification.Name("fekthor.workspaceAnimations")
    static let fekthorToggleTimeline = Notification.Name("fekthor.toggleTimeline")
    /// userInfo["animation"]: the def name to apply to the selection.
    static let fekthorAnimateApply = Notification.Name("fekthor.animateApply")
}

/// State the menu bar needs to reflect app context: whether a workspace is
/// open (⌘N reads "New Icon"), whether the editor selection can combine
/// (Path submenu), and the grid/snap toggles' checkmarks. Views update it;
/// the App observes it so menus re-render.
@MainActor
final class MenuState: ObservableObject {
    static let shared = MenuState()

    @Published var workspaceOpen = false
    @Published var canCombine = false
    /// The editor selection can align: anything selected (a single node
    /// aligns to the artboard; 2+ align to each other).
    @Published var canAlign = false
    /// An editor session is open (File ▸ Export targets its document; the
    /// trace flow keeps its own Export SVG button).
    @Published var editorOpen = false
    /// Grid visibility (⌘'). App-side because the engine's WorkspaceSettings
    /// has no showGrid field; persisted globally in UserDefaults so hiding
    /// never erases a workspace's configured spacing.
    @Published var showGrid: Bool {
        didSet { AppDefaults.store.set(showGrid, forKey: Self.showGridKey) }
    }
    /// Snap to grid (⇧⌘'). Mirrors the open workspace's setting (persisted
    /// through the workfile by ContentView); session-level for detached
    /// editors.
    @Published var snapToGrid = false
    /// Show Guide (⌥⌘G): mirrors the open workspace's guide visibility
    /// (persisted through the workfile by ContentView). Meaningless — and
    /// the menu item disabled — without a workspace.
    @Published var showGuide = false
    /// Snap to points (⌥⌘'): dragged anchors, drawn shapes and moved
    /// selections magnet onto other shapes' anchors and bounds
    /// corners/centres. App-side and persisted globally in UserDefaults —
    /// point snapping is an editor habit, not a workspace standard.
    @Published var snapToPoints: Bool {
        didSet { AppDefaults.store.set(snapToPoints, forKey: Self.snapToPointsKey) }
    }
    /// View ▸ Preview Composed Icons (⌥⌘P): the gallery also shows virtual
    /// icon-in-container cells. Session-level — composed previews are never
    /// written to disk, so the toggle need not persist either.
    @Published var previewComposed = false
    /// The animation defs the Object ▸ Animate submenu offers (workspace
    /// library + unshadowed presets), refreshed by the editor view.
    @Published var animationNames: [String] = []

    private static let showGridKey = "fekthor.showGrid"
    private static let snapToPointsKey = "fekthor.snapToPoints"

    private init() {
        showGrid = AppDefaults.store.object(forKey: Self.showGridKey) as? Bool ?? true
        snapToPoints = AppDefaults.store.bool(forKey: Self.snapToPointsKey)
    }
}

extension Color {
    /// The app accent — a warm orange. Single source of truth is the asset
    /// catalog's AccentColor (light #F0741E, dark #F58535), which the build
    /// setting ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME also routes
    /// into every `Color.accentColor` reference.
    static let fekthorAccent = Color("AccentColor", bundle: .main)

    /// The light thumbnail well behind icon artwork. Not pure white — a soft
    /// paper tone so white-on-white icons still read (with the well's dark
    /// rim) while near-black corpus icons keep full contrast.
    static let fekthorWell = Color(white: 0.88)
}

/// The window's black-glass backdrop: a behind-window blur with a dark tint,
/// stretched under the whole app (the app runs forced-dark, so every material
/// above it resolves dark too). Views that must stay readable — the artboard,
/// thumbnail wells — keep their own opaque surfaces on top.
struct WindowBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

@main
struct FekthorApp: App {
    @ObservedObject private var menuState = MenuState.shared
    @ObservedObject private var panelsState = EditorPanelsState.shared

    private func postAlign(_ edge: AlignEdge) {
        NotificationCenter.default.post(name: .fekthorAlign, object: nil, userInfo: ["edge": edge])
    }

    private func postDistribute(_ axis: DistributeAxis) {
        NotificationCenter.default.post(
            name: .fekthorDistribute, object: nil, userInfo: ["axis": axis])
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 940, minHeight: 620)
                .tint(.fekthorAccent)
                // Forced dark + the behind-window blur = black glass. The
                // artboard and thumbnail wells keep their own light surfaces.
                .preferredColorScheme(.dark)
                .background(WindowBackdrop().ignoresSafeArea())
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(menuState.workspaceOpen ? "New Icon" : "New File") {
                    NotificationCenter.default.post(name: .fekthorNewFile, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                Button("Open…") {
                    NotificationCenter.default.post(name: .fekthorOpen, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
                Button("Open Workspace…") {
                    NotificationCenter.default.post(name: .fekthorOpenWorkspace, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    NotificationCenter.default.post(name: .fekthorSave, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
                Button("Save As…") {
                    NotificationCenter.default.post(name: .fekthorSaveAs, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Menu("Export") {
                    Button("Export PNG…") {
                        NotificationCenter.default.post(name: .fekthorExportPNG, object: nil)
                    }
                    Button("Export PDF…") {
                        NotificationCenter.default.post(name: .fekthorExportPDF, object: nil)
                    }
                }
                .disabled(!menuState.editorOpen)
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Trace Image…") {
                    NotificationCenter.default.post(name: .fekthorTraceImage, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Toggle(
                    "Show Grid",
                    isOn: Binding(
                        get: { menuState.showGrid },
                        set: { _ in
                            NotificationCenter.default.post(name: .fekthorToggleGrid, object: nil)
                        })
                )
                .keyboardShortcut("'", modifiers: .command)
                Toggle(
                    "Snap to Grid",
                    isOn: Binding(
                        get: { menuState.snapToGrid },
                        set: { _ in
                            NotificationCenter.default.post(name: .fekthorToggleSnap, object: nil)
                        })
                )
                .keyboardShortcut("'", modifiers: [.command, .shift])
                // Direct binding (no notification round-trip): the toggle is
                // app-global and persists itself via MenuState's didSet.
                Toggle("Snap to Points", isOn: $menuState.snapToPoints)
                    .keyboardShortcut("'", modifiers: [.command, .option])
                Divider()
                Toggle(
                    "Show Guide",
                    isOn: Binding(
                        get: { menuState.showGuide },
                        set: { _ in
                            NotificationCenter.default.post(
                                name: .fekthorToggleGuide, object: nil)
                        })
                )
                .keyboardShortcut("g", modifiers: [.command, .option])
                .disabled(!menuState.workspaceOpen)
                Divider()
                Toggle("Preview Composed Icons", isOn: $menuState.previewComposed)
                    .keyboardShortcut("p", modifiers: [.command, .option])
                    .disabled(!menuState.workspaceOpen)
                Divider()
            }
            CommandMenu("Workspace") {
                Button("Workspace Settings…") {
                    NotificationCenter.default.post(name: .fekthorWorkspaceSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: [.command, .shift])
                .disabled(!menuState.workspaceOpen)
                Divider()
                Button("Export Profiles…") {
                    NotificationCenter.default.post(name: .fekthorWorkspaceExport, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Style Tokens…") {
                    NotificationCenter.default.post(name: .fekthorWorkspaceTokens, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                Button("Animations…") {
                    NotificationCenter.default.post(
                        name: .fekthorWorkspaceAnimations, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command, .option])
            }
            CommandMenu("Object") {
                Button("Group") {
                    NotificationCenter.default.post(name: .fekthorGroup, object: nil)
                }
                .keyboardShortcut("g", modifiers: .command)
                Button("Ungroup") {
                    NotificationCenter.default.post(name: .fekthorUngroup, object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                Divider()
                Menu("Path") {
                    Button("Unite") {
                        NotificationCenter.default.post(name: .fekthorPathUnite, object: nil)
                    }
                    Button("Subtract") {
                        NotificationCenter.default.post(name: .fekthorPathSubtract, object: nil)
                    }
                    Button("Intersect") {
                        NotificationCenter.default.post(name: .fekthorPathIntersect, object: nil)
                    }
                    Button("Exclude") {
                        NotificationCenter.default.post(name: .fekthorPathExclude, object: nil)
                    }
                }
                .disabled(!menuState.canCombine)
                Menu("Align") {
                    Button("Align Left") { postAlign(.left) }
                    Button("Align Center") { postAlign(.centerX) }
                    Button("Align Right") { postAlign(.right) }
                    Divider()
                    Button("Align Top") { postAlign(.top) }
                    Button("Align Middle") { postAlign(.centerY) }
                    Button("Align Bottom") { postAlign(.bottom) }
                    Divider()
                    Button("Distribute Horizontally") { postDistribute(.horizontal) }
                    Button("Distribute Vertically") { postDistribute(.vertical) }
                }
                .disabled(!menuState.canAlign)
                Menu("Animate") {
                    ForEach(menuState.animationNames, id: \.self) { name in
                        Button(name) {
                            NotificationCenter.default.post(
                                name: .fekthorAnimateApply, object: nil,
                                userInfo: ["animation": name])
                        }
                    }
                    Divider()
                    Button("Show Timeline") {
                        NotificationCenter.default.post(
                            name: .fekthorToggleTimeline, object: nil)
                    }
                    .keyboardShortcut("t", modifiers: [.command, .option])
                }
                .disabled(!menuState.editorOpen)
                Divider()
                Button("Bring to Front") {
                    NotificationCenter.default.post(name: .fekthorBringToFront, object: nil)
                }
                .keyboardShortcut("]", modifiers: [.command, .option])
                Button("Bring Forward") {
                    NotificationCenter.default.post(name: .fekthorBringForward, object: nil)
                }
                .keyboardShortcut("]", modifiers: .command)
                Button("Send Backward") {
                    NotificationCenter.default.post(name: .fekthorSendBackward, object: nil)
                }
                .keyboardShortcut("[", modifiers: .command)
                Button("Send to Back") {
                    NotificationCenter.default.post(name: .fekthorSendToBack, object: nil)
                }
                .keyboardShortcut("[", modifiers: [.command, .option])
            }
            // The editor's floating palettes; same toggles as the compact
            // Panels menu in the editor top bar.
            CommandMenu("Panels") {
                ForEach(EditorPanel.allCases) { panel in
                    Toggle(panel.title, isOn: panelsState.toggleBinding(panel))
                        .disabled(!menuState.editorOpen)
                }
            }
        }
    }
}
