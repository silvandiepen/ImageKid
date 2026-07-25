import BrushKit
import ImageKidKit
import InkaKit
import SwiftUI

/// Inka's root: the shared `HomeScreen` until a canvas is open, then the Metal
/// canvas with the family's floating panels (rail + dockable Brushes/Brush
/// panels from ImageKidKit).
struct ContentView: View {
    @StateObject private var model = InkaModel(document: .blank(width: 1280, height: 800))
    @StateObject private var dock = PanelDockController(PanelDockModel<InkaPanel>.makeDefault())
    @State private var hasCanvas = false

    var body: some View {
        Group {
            if hasCanvas {
                canvas
            } else {
                home
            }
        }
        .navigationTitle("Inka")
        .onAppear {
            // Test/debug hook: `--open-canvas` boots straight onto a canvas,
            // since synthetic clicks can't drive the home cards under sandbox.
            if CommandLine.arguments.contains("--open-canvas") {
                newCanvas(width: 1280, height: 800)
            }
        }
    }

    private var home: some View {
        HomeScreen(
            title: "Inka",
            subtitle: "Drawing and illustration, with a serious brush engine.",
            footnote: "a new canvas to start painting",
            character: nil,
            accent: .accentColor,
            actions: [
                HomeAction(
                    id: "inka.newCanvas",
                    icon: "paintbrush.pointed.fill",
                    title: "New Canvas",
                    subtitle: "1280 × 800",
                    action: { newCanvas(width: 1280, height: 800) }),
                HomeAction(
                    id: "inka.newSquare",
                    icon: "square",
                    title: "Square Canvas",
                    subtitle: "1024 × 1024",
                    action: { newCanvas(width: 1024, height: 1024) }),
                HomeAction(
                    id: "inka.open",
                    icon: "folder",
                    title: "Open…",
                    subtitle: "an .inka file",
                    action: { model.openDocument(); hasCanvas = true }),
            ],
            recents: { EmptyView() })
    }

    private func newCanvas(width: Int, height: Int) {
        model.newDocument(width: width, height: height)
        hasCanvas = true
    }

    private var canvas: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            InkaCanvasView(model: model)
                .background(Color(white: 0.28))
                // The move-tool marquee / selection outline, in view space.
                .overlay {
                    GeometryReader { geo in
                        InkaSelectionOverlay(model: model, viewSize: geo.size)
                    }
                    .allowsHitTesting(false)
                }
                // The panels float over the canvas on the RIGHT: dockable
                // Brushes/Brush panels, then the rail hard against the frame
                // edge — all ImageKidKit.
                .overlay(alignment: .topTrailing) { panelLayer.padding(8) }
        }
    }

    private var panelLayer: some View {
        HStack(alignment: .top, spacing: 8) {
            GeometryReader { geo in
                let size = geo.size
                ZStack(alignment: .topLeading) {
                    if dock.model.isExpanded(.brushes) {
                        InkaBrushesPanel(
                            model: model, offset: dock.offsetBinding(.brushes, in: size),
                            size: dock.model.sizeBinding(.brushes),
                            onMinimize: { dock.model.minimize(.brushes) },
                            stackEdges: dock.model.stackEdges(of: .brushes),
                            dockEdges: dock.model.dockEdges(of: .brushes, in: size),
                            isStackFollower: dock.model.isStackFollower(.brushes),
                            onDragChanged: { dock.dragChanged(.brushes, translation: $0, in: size) },
                            onDragEnded: { _ in dock.dragEnded(.brushes, in: size) })
                    }
                    if dock.model.isExpanded(.brush) {
                        InkaBrushPanel(
                            model: model, offset: dock.offsetBinding(.brush, in: size),
                            size: dock.model.sizeBinding(.brush),
                            onMinimize: { dock.model.minimize(.brush) },
                            stackEdges: dock.model.stackEdges(of: .brush),
                            dockEdges: dock.model.dockEdges(of: .brush, in: size),
                            isStackFollower: dock.model.isStackFollower(.brush),
                            onDragChanged: { dock.dragChanged(.brush, translation: $0, in: size) },
                            onDragEnded: { _ in dock.dragEnded(.brush, in: size) })
                    }
                    if dock.model.isExpanded(.colours) {
                        InkaColoursPanel(
                            model: model, offset: dock.offsetBinding(.colours, in: size),
                            size: dock.model.sizeBinding(.colours),
                            onMinimize: { dock.model.minimize(.colours) },
                            stackEdges: dock.model.stackEdges(of: .colours),
                            dockEdges: dock.model.dockEdges(of: .colours, in: size),
                            isStackFollower: dock.model.isStackFollower(.colours),
                            onDragChanged: { dock.dragChanged(.colours, translation: $0, in: size) },
                            onDragEnded: { _ in dock.dragEnded(.colours, in: size) })
                    }
                    if dock.model.isExpanded(.layers) {
                        InkaLayersPanel(
                            model: model, offset: dock.offsetBinding(.layers, in: size),
                            size: dock.model.sizeBinding(.layers),
                            onMinimize: { dock.model.minimize(.layers) },
                            stackEdges: dock.model.stackEdges(of: .layers),
                            dockEdges: dock.model.dockEdges(of: .layers, in: size),
                            isStackFollower: dock.model.isStackFollower(.layers),
                            onDragChanged: { dock.dragChanged(.layers, translation: $0, in: size) },
                            onDragEnded: { _ in dock.dragEnded(.layers, in: size) })
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .animation(.spring(response: 0.34, dampingFraction: 0.82), value: dock.model.presented)
                .animation(.spring(response: 0.34, dampingFraction: 0.82), value: dock.model.minimized)
                .onAppear {
                    dock.model.migrateLegacyPositions(in: size)
                    dock.placePending(in: size)
                    rightAlignDefaults(in: size)
                }
                .onChange(of: size) {
                    dock.model.migrateLegacyPositions(in: size)
                    // Runs once when the layout size first becomes valid.
                    rightAlignDefaults(in: size)
                }
                .onChange(of: dock.model.needsPlacement) { dock.placePending(in: size) }
            }
            PanelDockRail(model: dock.model, axis: .vertical)
                .panelRailChrome()
                .zIndex(1)
        }
    }

    /// One-time: park the panels against the right edge (Inka's default is a
    /// right-hand tool column). The model stores a right-side anchor, so it
    /// sticks across resizes and relaunches and yields to any user drag after.
    private func rightAlignDefaults(in size: CGSize) {
        // v3: pack the three default panels; Colours parks at the top of the
        // column so it lands cleanly when opened from the rail.
        let key = "inka.paneldock.rightDefault.v3"
        guard size.width > 0, !UserDefaults.standard.bool(forKey: key) else { return }
        let x = size.width - InkaPanel.panelWidth - PanelPlacement.margin
        var y: CGFloat = 8
        for panel in [InkaPanel.brushes, .brush, .layers] {
            dock.model.setPosition(panel, to: CGSize(width: x, height: y), in: size)
            y += dock.model.size(panel).height + PanelPlacement.gap
        }
        dock.model.setPosition(.colours, to: CGSize(width: x, height: 8), in: size)
        UserDefaults.standard.set(true, forKey: key)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button { hasCanvas = false } label: { Label("Home", systemImage: "chevron.left") }

            Divider().frame(height: 20)

            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .keyboardShortcut("z", modifiers: .command).disabled(!model.canUndo).help("Undo")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!model.canRedo).help("Redo")

            Divider().frame(height: 20)

            ColorPicker("", selection: $model.color, supportsOpacity: false).labelsHidden()
            Button { model.tool = model.tool == .eyedropper ? .draw : .eyedropper } label: {
                Image(systemName: "eyedropper")
            }
            .tint(model.tool == .eyedropper ? .accentColor : nil)
            .help("Eyedropper — pick a colour off the canvas")
            Button { model.tool = model.tool == .move ? .draw : .move } label: {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
            }
            .tint(model.tool == .move ? .accentColor : nil)
            .help("Move — marquee-select strokes and drag them (arrows nudge, ⌫ deletes)")
            HStack(spacing: 6) {
                Image(systemName: "circle.fill").font(.system(size: 8))
                Slider(value: sizeBinding, in: 1...200).frame(width: 120)
                Image(systemName: "circle.fill").font(.system(size: 16))
                Text("\(Int(model.brush.size))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)
            }
            Text(model.brush.name).font(.callout).foregroundStyle(.secondary)

            Spacer()

            Button { model.renderer?.fit(); model.requestRedraw?(); nudge() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                .keyboardShortcut("0", modifiers: .command).help("Fit")
            Button { model.clearActiveLayer() } label: { Image(systemName: "trash") }
                .help("Clear layer")

            Divider().frame(height: 20)

            Button { model.openDocument() } label: { Image(systemName: "folder") }
                .keyboardShortcut("o", modifiers: .command).help("Open .inka")
            Button { model.saveDocument() } label: { Image(systemName: "square.and.arrow.down") }
                .keyboardShortcut("s", modifiers: .command).help("Save .inka")
            Button { model.exportPNG() } label: { Label("Export", systemImage: "square.and.arrow.up") }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    /// Fit changes the transform, which the MTKView already redraws each frame;
    /// this just pokes SwiftUI so any dependent chrome refreshes.
    @State private var fitTick = 0
    private func nudge() { fitTick &+= 1 }

    private var sizeBinding: Binding<Double> {
        Binding(get: { model.brush.size }, set: { model.brush.size = $0 })
    }
}

/// Draws the move tool's live marquee and the current selection's bounding box,
/// mapping canvas-space rects through the renderer's transform to view points.
struct InkaSelectionOverlay: View {
    @ObservedObject var model: InkaModel
    let viewSize: CGSize

    var body: some View {
        Canvas { ctx, _ in
            guard let r = model.renderer else { return }
            if let b = model.selectionBounds, !model.selectedStrokeIDs.isEmpty {
                let rect = r.viewRect(fromCanvas: b, in: viewSize)
                ctx.stroke(
                    Path(rect), with: .color(.accentColor),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                ctx.fill(Path(rect), with: .color(.accentColor.opacity(0.08)))
            }
            if let m = model.marquee {
                let rect = r.viewRect(fromCanvas: m, in: viewSize)
                ctx.stroke(
                    Path(rect), with: .color(.white.opacity(0.9)),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
    }
}
