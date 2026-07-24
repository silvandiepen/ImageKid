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
            ],
            recents: { EmptyView() })
    }

    private func newCanvas(width: Int, height: Int) {
        model.document = .blank(width: width, height: height)
        model.clearCanvas()
        hasCanvas = true
    }

    private var canvas: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            InkaCanvasView(model: model)
                .background(Color(white: 0.5))
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
        let key = "inka.paneldock.rightDefault.v1"
        guard size.width > 0, !UserDefaults.standard.bool(forKey: key) else { return }
        let x = size.width - InkaPanel.panelWidth - PanelPlacement.margin
        dock.model.setPosition(.brushes, to: CGSize(width: x, height: 8), in: size)
        let below = 8 + dock.model.size(.brushes).height + PanelPlacement.gap
        dock.model.setPosition(.brush, to: CGSize(width: x, height: below), in: size)
        UserDefaults.standard.set(true, forKey: key)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                hasCanvas = false
            } label: { Label("Home", systemImage: "chevron.left") }

            Divider().frame(height: 20)

            ColorPicker("", selection: $model.color, supportsOpacity: false)
                .labelsHidden()

            HStack(spacing: 6) {
                Image(systemName: "circle.fill").font(.system(size: 8))
                Slider(value: sizeBinding, in: 1...200).frame(width: 130)
                Image(systemName: "circle.fill").font(.system(size: 16))
                Text("\(Int(model.brush.size))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
            }

            Text(model.brush.name).font(.callout).foregroundStyle(.secondary)

            Spacer()

            Button { model.clearCanvas() } label: { Label("Clear", systemImage: "trash") }
            Button { model.exportPNG() } label: { Label("Export PNG", systemImage: "square.and.arrow.up") }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var sizeBinding: Binding<Double> {
        Binding(get: { model.brush.size }, set: { model.brush.size = $0 })
    }
}
