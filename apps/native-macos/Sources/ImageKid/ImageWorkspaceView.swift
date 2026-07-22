import AppKit
import SwiftUI
import ImageKidKit
import UniformTypeIdentifiers

struct ImageWorkspaceView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: ColorLibrary
    @ObservedObject var session: ImageSession
    @ObservedObject var panelDock: PanelDockModel<DockablePanel>
    private let showsBackgroundRefinementControls = false

    @State private var hoverControls = false
    @State private var dragMode: DragMode?
    @State private var draftAnnotation: Annotation?
    @State private var draftFreehandPoints: [CGPoint] = []
    @State private var backgroundBrushLocation: CGPoint?
    @State private var lastBackgroundBrushPoint: CGPoint?
    @State private var didCaptureBackgroundUndo = false
    @State private var isViewportToolbarCollapsed = false
    @State private var panelOffset: CGSize = .zero
    @State private var gridPanelOffset: CGSize = .zero
    @State private var lastMaskPoint: CGPoint?
    @State private var maskBrushCursor: CGPoint?
    /// Set when a new text item is created so its default "Text" is selected.
    @State private var pendingTextSelectAll = false
    /// Live brush-stroke points (view space) accumulated during a drag; rasterised
    /// into the mask once on release so painting stays fast.
    @State private var maskStrokeViewPoints: [CGPoint] = []
    @State private var progressBarOffset: CGSize = .zero
    @State private var editingTextID: UUID?
    @FocusState private var inlineTextFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let workingSize = session.effectivePixelSize
            let viewportBounds = bounds.insetBy(dx: 32, dy: 72)
            let fitted = fittedViewportRect(
                contentSize: workingSize,
                in: viewportBounds
            )
            let imageRect = transformedRect(fitted)
            let displayedScale = fitted.width / max(workingSize.width, 1)
            let workingImage = WorkingImagePreview.croppedImage(
                from: session.workingSourceImage,
                cropRect: session.cropRect
            )

            ZStack {
                canvasBackground

                canvasBorder(in: imageRect)

                if !session.baseUnlocked {
                    Image(nsImage: workingImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: imageRect.width, height: imageRect.height)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: imageCornerRadius(for: imageRect),
                                style: .continuous
                            )
                        )
                        .scaleEffect(
                            x: rotatePreviewActive && session.rotationFlipHorizontal ? -1 : 1,
                            y: rotatePreviewActive && session.rotationFlipVertical ? -1 : 1
                        )
                        .rotationEffect(rotatePreviewActive ? .degrees(session.rotationDraft) : .zero)
                        .position(x: imageRect.midX, y: imageRect.midY)
                }

                stackedContent(in: imageRect)
                maskEditOverlay(in: imageRect)
                gridOverlay(in: imageRect, canvas: bounds)
                imageSelection(in: imageRect)
                draftDrawing(in: imageRect)

                if appModel.activeTool == .crop,
                   let displayedCrop = displayedCropRect(session.draftCropRect ?? session.cropRect) {
                    CropOverlay(
                        imageRect: imageRect,
                        normalizedRect: displayedCrop
                    )
                }

                if appModel.activeTool == .resize {
                    ResizeOverlay(
                        fullRect: imageRect,
                        imageRect: resizeDisplayRect(in: imageRect),
                        size: session.draftOutputSize ?? session.effectivePixelSize,
                        previewImage: session.baseUnlocked ? nil : workingImage
                    )
                }

                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(interactionGesture(in: imageRect))
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location): maskBrushCursor = location
                        case .ended: maskBrushCursor = nil
                        }
                    }
                    .simultaneousGesture(
                        SpatialTapGesture(count: 2).onEnded { value in
                            beginTextEditing(at: value.location, imageRect: imageRect)
                        }
                    )
                    .contextMenu {
                        if appModel.activeTool == .select {
                            Button("Copy Image") { appModel.copyImageSelectionToClipboard() }
                                .disabled(!appModel.canCopyImageSelection)
                            Button("Select All") { appModel.selectAllImage() }
                            Divider()
                            Button("Crop Selection") { appModel.cropSelection() }
                                .disabled(!appModel.canCopyImageSelection)
                            Button("Magic") { appModel.requestPromptEdit() }
                                .disabled(!appModel.canCopyImageSelection)
                            Divider()
                            Button("Export…") { appModel.requestExport() }
                        }
                    }

                inlineTextEditor(in: imageRect)

                brushCursorOverlay(in: imageRect)

                TrackpadGestureMonitor(
                    onPan: { delta in
                        session.pan = CGSize(
                            width: session.pan.width + delta.width,
                            height: session.pan.height + delta.height
                        )
                    },
                    onMagnify: { delta in
                        session.zoom = min(max(session.zoom * (1 + delta), 0.1), 12)
                    }
                )
                .allowsHitTesting(false)

                if appModel.activeTool == .pickColor,
                   let color = session.liveSampleColor,
                   let point = session.liveSampleLocation {
                    liveColorLoupe(color: color, at: point, in: bounds)
                }

                backgroundBrushCursor(in: imageRect)

                toolPanels
                viewportToolbar(displayedScale: displayedScale)
                controls
                progressOverlay
            }
            .clipped()
            .onDrop(of: [UTType.fileURL.identifier, UTType.plainText.identifier], isTargeted: nil) { providers in
                handleCanvasDrop(providers)
            }
            .onHover { inside in
                withAnimation(.easeOut(duration: 0.15)) {
                    hoverControls = inside
                }
                if !inside {
                    backgroundBrushLocation = nil
                }
            }
            .onChange(of: appModel.activeTool) { _, tool in
                if tool != .select {
                    session.selectionRect = nil
                }
                if tool == .crop, session.draftCropRect == nil {
                    session.draftCropRect = session.cropRect
                }
                if tool == .resize, session.draftOutputSize == nil {
                    session.beginResize()
                }
                if tool == .rotate {
                    session.beginRotation()
                }
                // Canvas-level tools drop any annotation selection; View and
                // Select keep it (Select is where you edit the selected item,
                // and newly-placed text switches to Select while staying selected).
                if tool != .view && tool != .select {
                    session.selectedAnnotationID = nil
                }
            }
            .onExitCommand {
                cancelCurrentTool()
            }
            .background(
                EscapeKeyMonitor(
                    onEscape: {
                        cancelCurrentTool()
                    },
                    onDelete: {
                        guard appModel.canDeleteSelection else { return false }
                        appModel.deleteSelection()
                        return true
                    },
                    onCommit: {
                        if appModel.activeTool == .crop {
                            applyCrop()
                            return true
                        }
                        if appModel.activeTool == .resize {
                            applyResize()
                            return true
                        }
                        if appModel.activeTool == .rotate {
                            applyRotate()
                            return true
                        }
                        if session.isEditingMask {
                            session.endMaskEdit()
                            return true
                        }
                        // Enter confirms/deselects a selected layer or annotation.
                        if session.selectedLayerID != nil || session.selectedAnnotationID != nil {
                            session.selectedLayerID = nil
                            session.selectedLayerIDs = []
                            session.selectedAnnotationID = nil
                            return true
                        }
                        return false
                    },
                    onKey: { chars in
                        guard session.isEditingMask else { return false }
                        switch chars.lowercased() {
                        case "x":
                            session.maskBrushReveal.toggle()
                            return true
                        case "[":
                            let delta = max(2, (session.maskBrushSize * 0.15).rounded())
                            session.maskBrushSize = max(4, session.maskBrushSize - delta)
                            return true
                        case "]":
                            let delta = max(2, (session.maskBrushSize * 0.15).rounded())
                            session.maskBrushSize = min(400, session.maskBrushSize + delta)
                            return true
                        default:
                            return false
                        }
                    }
                )
                .frame(width: 0, height: 0)
            )
        }
    }

    @ViewBuilder
    private var toolPanels: some View {
        ZStack(alignment: .topLeading) {
            // Right-side, tool-driven context panels.
            VStack(spacing: 12) {
                HStack(alignment: .top) {
                    Spacer()
                    rightToolPanels
                }
                if session.showGridPanel {
                    HStack(alignment: .top) {
                        Spacer()
                        GridControls(
                            session: session,
                            offset: $gridPanelOffset,
                            onClose: { session.showGridPanel = false }
                        )
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                Spacer()
            }
            .padding(.top, 54)
            .padding(.trailing, 18)
            .animation(.easeOut(duration: 0.18), value: appModel.activeTool)
            .animation(.easeOut(duration: 0.18), value: session.selectedAnnotationID)
            .animation(.easeOut(duration: 0.18), value: session.showGridPanel)

            // Movable, minimizable dockable panels + their minimized icon rail.
            dockablePanelsLayer
                .padding(.top, 15)
                .padding(.leading, 15)
        }
    }

    @ViewBuilder
    private var rightToolPanels: some View {
        if session.isEditingMask {
            MaskEditControls(
                session: session,
                offset: $panelOffset,
                onDone: { session.endMaskEdit() }
            )
            .transition(.move(edge: .trailing).combined(with: .opacity))
        } else if let layerID = session.selectedLayerID,
                  appModel.activeTool == .view || appModel.activeTool == .select {
            TransformControls(
                session: session,
                layerID: layerID,
                offset: $panelOffset,
                onClose: { session.selectedLayerID = nil; session.selectedLayerIDs = [] }
            )
            .transition(.move(edge: .trailing).combined(with: .opacity))
        } else if appModel.activeTool == .select, session.hasImageSelection, session.selectedAnnotationID == nil {
            SelectionPanel(
                session: session,
                appModel: appModel,
                offset: $panelOffset,
                onClose: { session.selectionRect = nil }
            )
            .transition(.move(edge: .trailing).combined(with: .opacity))
        } else if appModel.activeTool == .pickColor {
            ColorPalettePanel(
                session: session,
                offset: $panelOffset,
                onClose: { appModel.activeTool = .view }
            )
            .transition(.move(edge: .trailing).combined(with: .opacity))
        } else if appModel.activeTool == .crop {
            CropControls(
                session: session,
                offset: $panelOffset,
                onCancel: cancelCrop,
                onApply: applyCrop
            )
            .transition(.move(edge: .trailing).combined(with: .opacity))
        } else if appModel.activeTool == .resize {
            ResizeControls(
                session: session,
                offset: $panelOffset,
                isApplying: appModel.isApplyingResize,
                onCancel: cancelResize,
                onApply: applyResize,
                onSmartUpscale: { appModel.smartUpscale($0) }
            )
            .transition(.move(edge: .trailing).combined(with: .opacity))
        } else if appModel.activeTool == .rotate {
            RotateControls(
                session: session,
                offset: $panelOffset,
                onCancel: cancelRotate,
                onApply: applyRotate
            )
            .transition(.move(edge: .trailing).combined(with: .opacity))
        } else if showsBackgroundRefinementControls,
                  appModel.activeTool == .refineBackground,
                  session.backgroundRemovedImage != nil {
            BackgroundRefinementControls(
                session: session,
                offset: $panelOffset,
                onUndo: { session.undoLastBackgroundRefinement() },
                onClose: { appModel.activeTool = .view }
            )
            .transition(.move(edge: .trailing).combined(with: .opacity))
        } else if appModel.activeTool == .draw || session.selectedAnnotation?.isDrawable == true {
            DrawingInspector(
                session: session,
                offset: $panelOffset,
                onClose: {
                    session.selectedAnnotationID = nil
                    appModel.activeTool = .view
                }
            )
            .transition(.move(edge: .trailing).combined(with: .opacity))
        } else if let selected = session.selectedAnnotation, selected.isText {
            TextInspector(
                session: session,
                annotationID: selected.id,
                offset: $panelOffset
            )
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var dockablePanelsLayer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    appModel.isShowingNewFile = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 38, height: 38)
                        .background(Color.accentColor.opacity(0.9), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .help("New File")

                PanelDockRail(model: panelDock, axis: .horizontal)

                ForegroundBackgroundChips(library: library, session: session)
                    .padding(.leading, 4)
            }

            ZStack(alignment: .topLeading) {
                if panelDock.isExpanded(.files) {
                    FilesPanel(
                        appModel: appModel,
                        offset: panelDock.positionBinding(.files),
                        size: panelDock.sizeBinding(.files),
                        onMinimize: { panelDock.minimize(.files) }
                    )
                    .transition(panelCollapse)
                }
                if panelDock.isExpanded(.layers) {
                    LayersPanel(
                        session: session,
                        appModel: appModel,
                        offset: panelDock.positionBinding(.layers),
                        size: panelDock.sizeBinding(.layers),
                        onMinimize: { panelDock.minimize(.layers) }
                    )
                    .transition(panelCollapse)
                }
                if panelDock.isExpanded(.history) {
                    HistoryPanel(
                        session: session,
                        offset: panelDock.positionBinding(.history),
                        size: panelDock.sizeBinding(.history),
                        onMinimize: { panelDock.minimize(.history) }
                    )
                    .transition(panelCollapse)
                }
                if panelDock.isExpanded(.swatches) {
                    SwatchesPanel(
                        offset: panelDock.positionBinding(.swatches),
                        size: panelDock.sizeBinding(.swatches),
                        onMinimize: { panelDock.minimize(.swatches) },
                        onPick: { applySwatchColor($0) }
                    )
                    .transition(panelCollapse)
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.82), value: panelDock.presented)
            .animation(.spring(response: 0.34, dampingFraction: 0.82), value: panelDock.minimized)
        }
    }

    /// Panels collapse toward their top-left corner (where the rail buttons sit).
    private var panelCollapse: AnyTransition {
        .scale(scale: 0.06, anchor: .topLeading).combined(with: .opacity)
    }

    /// Finder files → open as new images; an internal Files-row drag → add as a layer.
    private func handleCanvasDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        if !fileProviders.isEmpty {
            for provider in fileProviders {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL? = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                    if let url { Task { @MainActor in appModel.load(url) } }
                }
            }
            return true
        }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                let text = (item as? String) ?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
                if let text { Task { @MainActor in appModel.addDraggedImageAsLayer(text, into: session) } }
            }
            return true
        }
        return false
    }

    /// Apply a swatch colour: it becomes the foreground (default stroke/text)
    /// colour and recolours the selected annotation.
    private func applySwatchColor(_ color: NSColor) {
        library.foreground = color
        session.drawingStrokeColor = color
        if let id = session.selectedAnnotationID {
            session.updateAnnotation(id: id) { $0.strokeColor = color }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Spacer()

            if appModel.activeTool != .crop && appModel.activeTool != .resize && appModel.activeTool != .rotate {
                FloatingToolbar(canExport: true)
                    .opacity(
                        hoverControls
                        || appModel.activeTool != .view
                        || session.selectedAnnotationID != nil ? 1 : 0
                    )
                    .offset(
                        y: hoverControls
                        || appModel.activeTool != .view
                        || session.selectedAnnotationID != nil ? 0 : 8
                    )
            }
        }
        .padding(.bottom, 20)
        .animation(.easeOut(duration: 0.15), value: hoverControls)
    }

    private func viewportToolbar(displayedScale: CGFloat) -> some View {
        VStack {
            ViewportToolbar(
                session: session,
                displayedScale: displayedScale,
                isCollapsed: $isViewportToolbarCollapsed,
                onEditSize: {
                    session.selectedLayerID = nil
                    session.selectedLayerIDs = []
                    session.selectedAnnotationID = nil
                    appModel.activeTool = .resize
                }
            )
            .padding(.top, 10)
            Spacer()
        }
    }

    @ViewBuilder
    private var progressOverlay: some View {
        if appModel.isRemovingBackground || appModel.isApplyingResize || appModel.isApplyingPromptEdit {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                OperationProgressBar(
                    progress: appModel.operationProgress,
                    fallbackTitle: progressFallbackTitle,
                    currentDate: context.date,
                    offset: $progressBarOffset
                )
            }
        }
    }

    private var progressFallbackTitle: String {
        if appModel.isApplyingResize { return "Stretching it up" }
        if appModel.isApplyingPromptEdit { return "Prompted edit" }
        return "Peeling off the background"
    }

    @ViewBuilder
    private func backgroundBrushCursor(in imageRect: CGRect) -> some View {
        if appModel.activeTool == .refineBackground,
           let backgroundBrushLocation,
           imageRect.contains(backgroundBrushLocation) {
            let diameter = session.backgroundBrushSize / max(session.resizePreviewSize.width, 1) * imageRect.width
            Circle()
                .stroke(
                    session.backgroundRefinementMode == .keep ? Color.green : Color.red,
                    style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                )
                .background(
                    Circle()
                        .fill((session.backgroundRefinementMode == .keep ? Color.green : Color.red).opacity(0.12))
                )
                .frame(width: max(8, diameter), height: max(8, diameter))
                .position(backgroundBrushLocation)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var canvasBackground: some View {
        if settings.canvasBackground == .checkerboard {
            CheckerboardBackground(cellSize: 18)
                .ignoresSafeArea()
        } else {
            settings.canvasColor
                .ignoresSafeArea()
        }
    }

    private func canvasBorder(in imageRect: CGRect) -> some View {
        RoundedRectangle(cornerRadius: imageCornerRadius(for: imageRect), style: .continuous)
            .strokeBorder(canvasBorderColor, lineWidth: settings.canvasBackground == .checkerboard ? 1.5 : 1)
            .frame(width: imageRect.width, height: imageRect.height)
            .position(x: imageRect.midX, y: imageRect.midY)
            .allowsHitTesting(false)
    }

    private func imageCornerRadius(for imageRect: CGRect) -> CGFloat {
        min(CGFloat(settings.imageCornerRadius), min(imageRect.width, imageRect.height) / 2)
    }

    private var canvasBorderColor: Color {
        switch settings.canvasBackground {
        case .dark:
            return .white.opacity(0.28)
        case .checkerboard:
            return .accentColor.opacity(0.82)
        case .custom:
            return isCustomCanvasColorDark ? .white.opacity(0.34) : .black.opacity(0.32)
        case .light:
            return .black.opacity(0.26)
        }
    }

    private var isCustomCanvasColorDark: Bool {
        let color = settings.customCanvasBackground.usingColorSpace(.sRGB) ?? settings.customCanvasBackground
        let luminance = 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
        return luminance < 0.45
    }

    @ViewBuilder
    private func checkerboard(in imageRect: CGRect) -> some View {
        CheckerboardBackground()
            .frame(width: imageRect.width, height: imageRect.height)
            .position(x: imageRect.midX, y: imageRect.midY)
    }

    @ViewBuilder
    private func imageSelection(in imageRect: CGRect) -> some View {
        if let selectionRect = session.selectionRect {
            let rect = GeometryMapper.viewRect(from: selectionRect, in: imageRect)
            selectionOverlay(for: rect)
                .allowsHitTesting(false)
        }
    }

    /// The unified stack: image layers and annotations rendered in one shared
    /// z-order (bottom to top), so shapes and image layers freely interleave.
    @ViewBuilder
    private func stackedContent(in imageRect: CGRect) -> some View {
        ForEach(session.stackBottomToTop) { item in
            switch item {
            case .layer(let layer):
                imageLayerView(layer, in: imageRect)
            case .annotation(let annotation):
                annotationView(annotation, in: imageRect)
            }
        }
    }

    @ViewBuilder
    private func imageLayerView(_ layer: ImageLayer, in imageRect: CGRect) -> some View {
        if session.isLayerEffectivelyVisible(layer), let displayedFrame = displayedAnnotationFrame(layer.frame) {
            let rect = GeometryMapper.viewRect(from: displayedFrame, in: imageRect)
            // Show the full (unmasked) image while editing its mask.
            let displayImage = session.maskEditLayerID == layer.id ? layer.image : layer.renderedImage
            Image(nsImage: displayImage)
                .resizable()
                .interpolation(.high)
                .frame(width: rect.width, height: rect.height)
                .opacity(layer.opacity)
                .scaleEffect(x: layer.flipH ? -1 : 1, y: layer.flipV ? -1 : 1)
                .rotationEffect(.degrees(layer.rotation))
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)

            if session.selectedLayerID == layer.id {
                rotatedLayerSelectionOverlay(for: rect, rotation: layer.rotation)
                    .allowsHitTesting(false)
            }
        }
    }

    private func rotatedLayerSelectionOverlay(for rect: CGRect, rotation: Double) -> some View {
        let corners = [
            CGPoint(x: 0, y: 0), CGPoint(x: rect.width, y: 0),
            CGPoint(x: 0, y: rect.height), CGPoint(x: rect.width, y: rect.height)
        ]
        return ZStack {
            Rectangle()
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            ForEach(Array(corners.enumerated()), id: \.offset) { _, point in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.accentColor, lineWidth: 2))
                    .position(point)
            }
        }
        .frame(width: rect.width, height: rect.height)
        .rotationEffect(.degrees(rotation))
        .position(x: rect.midX, y: rect.midY)
    }

    /// Map a screen point back into a layer's un-rotated space for hit-testing.
    private func unrotatePoint(_ point: CGPoint, around center: CGPoint, degrees: Double) -> CGPoint {
        guard degrees != 0 else { return point }
        let a = -degrees * .pi / 180
        let dx = point.x - center.x, dy = point.y - center.y
        return CGPoint(
            x: center.x + dx * cos(a) - dy * sin(a),
            y: center.y + dx * sin(a) + dy * cos(a)
        )
    }

    @ViewBuilder
    private func gridOverlay(in imageRect: CGRect, canvas canvasBounds: CGRect) -> some View {
        // Always show the grid while snapping so the user sees what they snap to.
        if session.showGrid || session.snapToGrid {
            let workingSize = session.effectivePixelSize
            let step = session.gridSizePx * imageRect.width / max(workingSize.width, 1)
            if step > 3 {
                let base = Color(nsColor: session.gridColor)
                let subdivisions = max(1, session.gridSubdivisions)
                let subStep = step / CGFloat(subdivisions)
                Canvas { context, _ in
                    // Lines span the whole canvas but stay anchored (phase-aligned)
                    // to the image's grid origin so they line up with the pixels.
                    func verticalLines(spacing: CGFloat) -> Path {
                        var p = Path()
                        let offset = (imageRect.minX - canvasBounds.minX).truncatingRemainder(dividingBy: spacing)
                        var x = canvasBounds.minX + offset - spacing
                        while x <= canvasBounds.maxX + 0.5 {
                            if x >= canvasBounds.minX - 0.5 {
                                p.move(to: CGPoint(x: x, y: canvasBounds.minY))
                                p.addLine(to: CGPoint(x: x, y: canvasBounds.maxY))
                            }
                            x += spacing
                        }
                        return p
                    }
                    func horizontalLines(spacing: CGFloat) -> Path {
                        var p = Path()
                        let offset = (imageRect.minY - canvasBounds.minY).truncatingRemainder(dividingBy: spacing)
                        var y = canvasBounds.minY + offset - spacing
                        while y <= canvasBounds.maxY + 0.5 {
                            if y >= canvasBounds.minY - 0.5 {
                                p.move(to: CGPoint(x: canvasBounds.minX, y: y))
                                p.addLine(to: CGPoint(x: canvasBounds.maxX, y: y))
                            }
                            y += spacing
                        }
                        return p
                    }

                    // Finer subdivision lines first (fainter), main grid on top.
                    if subdivisions > 1 && subStep > 2 {
                        var subPath = verticalLines(spacing: subStep)
                        subPath.addPath(horizontalLines(spacing: subStep))
                        context.stroke(subPath, with: .color(base.opacity(session.gridOpacity * 0.45)), lineWidth: 0.5)
                    }

                    var path = verticalLines(spacing: step)
                    path.addPath(horizontalLines(spacing: step))
                    context.stroke(path, with: .color(base.opacity(session.gridOpacity)), lineWidth: 0.6)
                }
                .allowsHitTesting(false)
            }
        }
    }

    /// Live brush ring at the cursor + a preview of the in-progress stroke.
    @ViewBuilder
    private func brushCursorOverlay(in imageRect: CGRect) -> some View {
        if session.isEditingMask, !session.maskWandMode,
           let layer = session.maskEditLayer, let mask = layer.mask,
           let displayedFrame = displayedAnnotationFrame(layer.frame) {
            let rect = GeometryMapper.viewRect(from: displayedFrame, in: imageRect)
            let scale = rect.width / max(mask.size.width, 1)
            let w = max(session.maskBrushSize * scale, 4)
            let h = max(w * session.maskBrushRoundness, 4)
            // Blue = reveal, red = hide, so the two modes are easy to tell apart.
            let ringColor: Color = session.maskBrushReveal ? .blue : .red

            // Live preview of the stroke; rasterised to black/white on release.
            if maskStrokeViewPoints.count > 1 {
                Path { p in
                    p.move(to: maskStrokeViewPoints[0])
                    for pt in maskStrokeViewPoints.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(ringColor.opacity(0.55 * session.maskBrushOpacity),
                        style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
                .allowsHitTesting(false)
            }

            if let cursor = maskBrushCursor {
                Ellipse()
                    .stroke(Color.black.opacity(0.7), lineWidth: 2.5)
                    .frame(width: w, height: h)
                    .rotationEffect(.degrees(session.maskBrushAngle))
                    .position(cursor)
                    .allowsHitTesting(false)
                Ellipse()
                    .stroke(ringColor.opacity(0.9), lineWidth: 1)
                    .frame(width: w, height: h)
                    .rotationEffect(.degrees(session.maskBrushAngle))
                    .position(cursor)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func maskEditOverlay(in imageRect: CGRect) -> some View {
        if let layer = session.maskEditLayer, let mask = layer.mask,
           let displayedFrame = displayedAnnotationFrame(layer.frame) {
            let rect = GeometryMapper.viewRect(from: displayedFrame, in: imageRect)
            // Show the black/white mask over the layer at the chosen opacity.
            Image(nsImage: mask)
                .resizable()
                .frame(width: rect.width, height: rect.height)
                .opacity(session.maskViewOpacity)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func annotationView(_ annotation: Annotation, in imageRect: CGRect) -> some View {
        if annotation.isVisible, let displayedFrame = displayedAnnotationFrame(annotation.frame) {
            let rect = GeometryMapper.viewRect(from: displayedFrame, in: imageRect)

            if editingTextID != annotation.id {
                let m = drawableMargin(annotation)
                annotationContent(annotation)
                    .frame(width: rect.width + 2 * m, height: rect.height + 2 * m)
                    .position(x: rect.midX, y: rect.midY)
                    .blendMode(annotation.blendMode.swiftUI)
                    .opacity(annotation.opacity)
            }

            if session.selectedAnnotationID == annotation.id {
                selectionOverlay(for: rect, annotation: annotation)
            }
        }
    }

    @ViewBuilder
    private func inlineTextEditor(in imageRect: CGRect) -> some View {
        if let id = editingTextID,
           let annotation = session.annotations.first(where: { $0.id == id }),
           let displayedFrame = displayedAnnotationFrame(annotation.frame) {
            let rect = GeometryMapper.viewRect(from: displayedFrame, in: imageRect)
            TextEditor(text: inlineTextBinding(id))
                .font(annotationFont(annotation))
                .foregroundStyle(Color(nsColor: annotation.strokeColor))
                .multilineTextAlignment(textAlignment(annotation.textAlignment))
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .focused($inlineTextFocused)
                .padding(0)
                .frame(width: max(rect.width, 24), height: max(rect.height, 24))
                .background(Color.accentColor.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.accentColor, lineWidth: 1))
                .position(x: rect.midX, y: rect.midY)
                .onExitCommand { endTextEditing() }
                .background(TextSelectAllHelper(trigger: $pendingTextSelectAll))
        }
    }

    private func inlineTextBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { session.annotations.first(where: { $0.id == id })?.textValue ?? "" },
            set: { value in session.updateAnnotation(id: id) { $0.textValue = value } }
        )
    }

    private func beginTextEditing(at point: CGPoint, imageRect: CGRect) {
        guard let hit = session.annotations.reversed().first(where: { annotation in
            guard annotation.isText, annotation.isVisible,
                  let frame = displayedAnnotationFrame(annotation.frame) else { return false }
            return GeometryMapper.viewRect(from: frame, in: imageRect).insetBy(dx: -6, dy: -6).contains(point)
        }) else { return }
        appModel.activeTool = .select
        session.selectedAnnotationID = hit.id
        session.selectedLayerID = nil
        editingTextID = hit.id
        inlineTextFocused = true
    }

    private func endTextEditing() {
        editingTextID = nil
        inlineTextFocused = false
    }

    /// Map a view location to a normalised point (0…1, top-left) inside the
    /// currently mask-editing layer's own image space.
    private func maskSourcePoint(_ location: CGPoint, imageRect: CGRect) -> CGPoint? {
        guard let layer = session.maskEditLayer,
              let displayedFrame = displayedAnnotationFrame(layer.frame) else { return nil }
        let rect = GeometryMapper.viewRect(from: displayedFrame, in: imageRect)
        guard rect.width > 0, rect.height > 0 else { return nil }
        return CGPoint(
            x: min(max((location.x - rect.minX) / rect.width, 0), 1),
            y: min(max((location.y - rect.minY) / rect.height, 0), 1)
        )
    }

    @ViewBuilder
    private func annotationContent(_ annotation: Annotation) -> some View {
        switch annotation.kind {
        case .text(let value):
            Text(value)
                .font(annotationFont(annotation))
                .foregroundStyle(Color(nsColor: annotation.strokeColor))
                .multilineTextAlignment(textAlignment(annotation.textAlignment))
                .lineSpacing(max(0, annotation.fontSize * session.zoom * 0.72 * (annotation.lineHeight - 1)))
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: annotation.textAlignment.swiftUIAlignment
                )

        case .rectangle, .ellipse, .line, .arrow, .freehand:
            // The Canvas is enlarged by a margin on all sides so a wide, outset,
            // or round-capped stroke isn't clipped at the shape's frame edge.
            let margin = drawableMargin(annotation)
            Canvas { context, size in
                context.translateBy(x: margin, y: margin)
                let inner = CGSize(width: max(0, size.width - 2 * margin),
                                   height: max(0, size.height - 2 * margin))
                drawAnnotation(annotation, context: &context, size: inner)
            }
        }
    }

    /// Extra room around a shape's canvas so its stroke (up to ~1× line width
    /// beyond the edge with outset alignment + round caps) is never clipped.
    private func drawableMargin(_ annotation: Annotation) -> CGFloat {
        annotation.isText ? 0 : annotation.lineWidth * 1.5 + 2
    }

    @ViewBuilder
    private func draftDrawing(in imageRect: CGRect) -> some View {
        if let draftAnnotation,
           let displayedFrame = displayedAnnotationFrame(draftAnnotation.frame) {
            let rect = GeometryMapper.viewRect(from: displayedFrame, in: imageRect)
            let m = drawableMargin(draftAnnotation)
            annotationContent(draftAnnotation)
                .frame(width: rect.width + 2 * m, height: rect.height + 2 * m)
                .position(x: rect.midX, y: rect.midY)
                .opacity(0.82)
        }

        if session.drawingMode == .freehand, draftFreehandPoints.count > 1 {
            Path { path in
                path.move(to: draftFreehandPoints[0])
                for point in draftFreehandPoints.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(
                Color(nsColor: session.drawingStrokeColor).opacity(session.drawingOpacity),
                style: StrokeStyle(
                    lineWidth: session.drawingLineWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
    }

    @ViewBuilder
    private func selectionOverlay(for rect: CGRect, annotation: Annotation? = nil) -> some View {
        Rectangle()
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)

        ForEach(Array(cornerPoints(for: rect).enumerated()), id: \.offset) { _, point in
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.white)
                .frame(width: 12, height: 12)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.accentColor, lineWidth: 2))
                .position(point)
        }

        // Corner-radius handle for rectangles: a small dot inset from the corner.
        if let annotation, annotation.isRectangle {
            let dot = cornerRadiusHandlePoint(rect: rect, radius: annotation.cornerRadius)
            Circle()
                .fill(Color.white)
                .frame(width: 11, height: 11)
                .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                .position(dot)
                .help("Drag to round the corners")
        }
    }

    private func liveColorLoupe(color: NSColor, at point: CGPoint, in bounds: CGRect) -> some View {
        let x = min(max(point.x, 54), bounds.maxX - 54)
        let preferredY = point.y + 78
        let y = preferredY + 64 < bounds.maxY ? preferredY : point.y - 78
        let sample = SampledColor(color: color)

        return VStack(spacing: 7) {
            Circle()
                .fill(Color(nsColor: sample.sRGB))
                .frame(width: 76, height: 76)
                .overlay(Circle().stroke(.white, lineWidth: 4))
                .overlay(Circle().stroke(.black.opacity(0.2), lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 12, y: 5)

            Text(sample.hex)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.80), in: Capsule())
                .foregroundStyle(.white)
        }
        .position(x: x, y: y)
        .allowsHitTesting(false)
    }

    private func transformedRect(_ fitted: CGRect) -> CGRect {
        let width = fitted.width * session.zoom
        let height = fitted.height * session.zoom
        return CGRect(
            x: fitted.midX - width / 2 + session.pan.width,
            y: fitted.midY - height / 2 + session.pan.height,
            width: width,
            height: height
        )
    }

    private func fittedViewportRect(contentSize: CGSize, in bounds: CGRect) -> CGRect {
        guard contentSize.width > 0, contentSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return .zero
        }

        switch session.viewportMode {
        case .contain:
            return GeometryMapper.aspectFitRect(contentSize: contentSize, in: bounds)

        case .cover:
            let scale = max(bounds.width / contentSize.width, bounds.height / contentSize.height)
            let size = CGSize(width: contentSize.width * scale, height: contentSize.height * scale)
            return CGRect(
                x: bounds.midX - size.width / 2,
                y: bounds.midY - size.height / 2,
                width: size.width,
                height: size.height
            )

        case .original:
            return CGRect(
                x: bounds.midX - contentSize.width / 2,
                y: bounds.midY - contentSize.height / 2,
                width: contentSize.width,
                height: contentSize.height
            )
        }
    }

    private func interactionGesture(in imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragMode == nil {
                    // A click on the canvas (outside the inline editor) commits editing.
                    if editingTextID != nil { editingTextID = nil }
                    dragMode = resolveDragMode(at: value.startLocation, imageRect: imageRect)
                }
                updateDrag(value, imageRect: imageRect)
            }
            .onEnded { value in
                finishDrag(value, imageRect: imageRect)
                // Record the completed gesture as a single named history step.
                switch dragMode {
                case .moveAnnotation:
                    session.record("Move", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                case .resizeAnnotation:
                    session.record("Resize annotation", systemImage: "arrow.up.left.and.arrow.down.right")
                case .cornerRadius:
                    session.record("Corner radius", systemImage: "square.dashed")
                case .moveLayer:
                    session.record("Move layer", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                case .resizeLayer:
                    session.record("Resize layer", systemImage: "arrow.up.left.and.arrow.down.right")
                case .rotateLayer:
                    session.record("Rotate layer", systemImage: "rotate.right")
                default:
                    break
                }
                dragMode = nil
                draftAnnotation = nil
                draftFreehandPoints = []
                lastMaskPoint = nil
                maskStrokeViewPoints = []
            }
    }

    private func resolveDragMode(at point: CGPoint, imageRect: CGRect) -> DragMode {
        if session.isEditingMask { return .maskEdit }
        switch appModel.activeTool {
        case .view:
            return resolveViewDragMode(at: point, imageRect: imageRect)

        case .select:
            if let selectionRect = session.selectionRect {
                let rect = GeometryMapper.viewRect(from: selectionRect, in: imageRect)
                if let handle = boxHandle(at: point, rect: rect) {
                    if handle == .inside {
                        return .moveSelection(start: selectionRect)
                    }
                    return .resizeSelection(handle: handle, start: selectionRect)
                }
            }

            if let mode = selectedShapeCornerRadiusMode(at: point, imageRect: imageRect) {
                return mode
            }

            if let selectedID = session.selectedAnnotationID,
               let selected = session.annotations.first(where: { $0.id == selectedID }),
               let displayed = displayedAnnotationFrame(selected.frame) {
                let rect = GeometryMapper.viewRect(from: displayed, in: imageRect)
                if let corner = cornerHandle(at: point, rect: rect) {
                    return .resizeAnnotation(id: selectedID, corner: corner, start: selected.frame)
                }
            }

            if let mode = selectedLayerResizeMode(at: point, imageRect: imageRect) {
                return mode
            }

            if let item = hitTopStackItem(at: point, imageRect: imageRect) {
                session.selectionRect = nil
                switch item {
                case .annotation(let a): return annotationMoveMode(a)
                case .layer(let l): return layerMoveModeFor(l)
                }
            }

            session.selectedAnnotationID = nil
            session.selectedLayerID = nil
            return .selectRegion

        case .pickColor:
            return .pick

        case .crop:
            let sourceDraft = session.draftCropRect ?? session.cropRect
            let displayedDraft = displayedCropRect(sourceDraft)
                ?? CGRect(x: 0, y: 0, width: 1, height: 1)
            let rect = GeometryMapper.viewRect(from: displayedDraft, in: imageRect)
            if let handle = boxHandle(at: point, rect: rect) {
                return .crop(handle: handle, start: displayedDraft)
            }
            return .crop(handle: .new, start: displayedDraft)

        case .resize:
            let rect = resizeDisplayRect(in: imageRect)
            if let handle = boxHandle(at: point, rect: rect), handle != .inside, handle != .new {
                return .resizeCanvas(
                    handle: handle,
                    start: session.draftOutputSize ?? session.effectivePixelSize,
                    rect: rect
                )
            }
            return .pan(start: session.pan)

        case .rotate:
            return .pan(start: session.pan)

        case .refineBackground:
            return .refineBackground

        case .draw:
            return .draw

        case .text:
            return .placeText
        }
    }

    private func resolveViewDragMode(at point: CGPoint, imageRect: CGRect) -> DragMode {
            if let mode = selectedShapeCornerRadiusMode(at: point, imageRect: imageRect) {
                return mode
            }

            if let selectedID = session.selectedAnnotationID,
               let selected = session.annotations.first(where: { $0.id == selectedID }),
               let displayed = displayedAnnotationFrame(selected.frame) {
                let rect = GeometryMapper.viewRect(from: displayed, in: imageRect)
                if let corner = cornerHandle(at: point, rect: rect) {
                    return .resizeAnnotation(id: selectedID, corner: corner, start: selected.frame)
                }
            }

            if let mode = selectedLayerResizeMode(at: point, imageRect: imageRect) {
                return mode
            }

            if let item = hitTopStackItem(at: point, imageRect: imageRect) {
                switch item {
                case .annotation(let a): return annotationMoveMode(a)
                case .layer(let l): return layerMoveModeFor(l)
                }
            }

            session.selectedAnnotationID = nil
            session.selectedLayerID = nil
            return .pan(start: session.pan)
    }

    private func updateDrag(_ value: DragGesture.Value, imageRect: CGRect) {
        guard let dragMode else { return }

        switch dragMode {
        case .pan(let start):
            session.pan = CGSize(
                width: start.width + value.translation.width,
                height: start.height + value.translation.height
            )

        case .pick:
            updateLiveSample(at: value.location, imageRect: imageRect)

        case .draw:
            updateDraftDrawing(value, imageRect: imageRect)

        case .maskEdit:
            // Accumulate the stroke; it's rasterised into the mask on release so
            // dragging stays smooth even on large masks.
            if !session.maskWandMode {
                maskStrokeViewPoints.append(value.location)
            }

        case .placeText:
            break

        case .moveAnnotation(let id, let start):
            let delta = sourceTranslation(value.translation, imageRect: imageRect)
            session.updateAnnotation(id: id) { annotation in
                annotation.frame = session.gridSnapped(movedRect(start, by: delta))
            }

        case .resizeAnnotation(let id, let corner, let start):
            let delta = sourceTranslation(value.translation, imageRect: imageRect)
            session.updateAnnotation(id: id) { annotation in
                annotation.frame = session.gridSnapped(resizedRect(start, handle: corner.boxHandle, delta: delta), keepSize: false)
            }

        case .cornerRadius(let id, let rect):
            // Drag diagonally inward from the top-left corner to grow the radius.
            let maxD = min(rect.width, rect.height) / 2
            let newRadius = min(max(min(value.location.x - rect.minX, value.location.y - rect.minY), 0), maxD)
            session.updateAnnotation(id: id) { $0.cornerRadius = newRadius }

        case .moveLayer(let id, let start):
            let delta = sourceTranslation(value.translation, imageRect: imageRect)
            session.updateImageLayer(id: id) { layer in
                layer.frame = session.gridSnapped(movedRect(start, by: delta))
            }

        case .resizeLayer(let id, let corner, let start):
            let delta = sourceTranslation(value.translation, imageRect: imageRect)
            session.updateImageLayer(id: id) { layer in
                layer.frame = resizedRect(start, handle: corner.boxHandle, delta: delta)
            }

        case .rotateLayer(let id, let center, let startAngle, let startRotation):
            let angle = atan2(value.location.y - center.y, value.location.x - center.x)
            var degrees = startRotation + Double((angle - startAngle) * 180 / .pi)
            if NSEvent.modifierFlags.contains(.shift) { degrees = (degrees / 15).rounded() * 15 }
            session.updateImageLayer(id: id) { $0.rotation = degrees }

        case .moveSelection(let start):
            let delta = normalizedDisplayTranslation(value.translation, imageRect: imageRect)
            session.selectionRect = session.gridSnappedDisplayNormalized(movedRect(start, by: delta), keepSize: true)

        case .resizeSelection(let handle, let start):
            let delta = normalizedDisplayTranslation(value.translation, imageRect: imageRect)
            session.selectionRect = session.gridSnappedDisplayNormalized(resizedRect(start, handle: handle, delta: delta))

        case .crop(let handle, let start):
            var displayedRect: CGRect
            if handle == .new {
                guard let newRect = GeometryMapper.normalizedRect(
                    from: value.startLocation,
                    to: value.location,
                    in: imageRect
                ) else { return }
                displayedRect = cropRectApplyingRatio(newRect, handle: .bottomRight)
                displayedRect = session.gridSnappedDisplayNormalized(displayedRect)
            } else {
                let delta = normalizedDisplayTranslation(value.translation, imageRect: imageRect)
                let changed = handle == .inside
                    ? movedRect(start, by: delta)
                    : resizedRect(start, handle: handle, delta: delta)
                displayedRect = cropRectApplyingRatio(changed, handle: handle)
                displayedRect = session.gridSnappedDisplayNormalized(displayedRect, keepSize: handle == .inside)
            }

            session.draftCropRect = WorkingImageGeometry.sourceRect(
                fromDisplayNormalized: displayedRect,
                cropRect: session.cropRect
            )

        case .resizeCanvas(let handle, let start, let rect):
            session.setDraftOutputSize(
                resizedOutputSize(start, handle: handle, translation: value.translation, imageRect: rect)
            )

        case .selectRegion:
            guard let selection = GeometryMapper.normalizedRect(
                from: value.startLocation,
                to: value.location,
                in: imageRect
            ) else {
                return
            }
            let snapped = session.gridSnappedDisplayNormalized(selection)
            session.selectionRect = GeometryMapper.clampedNormalizedRect(snapped, minimumSize: 0.001)

        case .refineBackground:
            backgroundBrushLocation = value.location
            applyBackgroundBrush(at: value.location, imageRect: imageRect)
        }
    }

    private func finishDrag(_ value: DragGesture.Value, imageRect: CGRect) {
        guard let dragMode else { return }

        switch dragMode {
        case .pick:
            updateLiveSample(at: value.location, imageRect: imageRect)
            if let color = session.liveSampleColor {
                session.addSample(color)
            }
            session.liveSampleColor = nil
            session.liveSampleLocation = nil

        case .draw:
            finishDrawing(value, imageRect: imageRect)

        case .placeText:
            placeText(at: value.location, imageRect: imageRect)

        case .refineBackground:
            backgroundBrushLocation = value.location
            applyBackgroundBrush(at: value.location, imageRect: imageRect)
            lastBackgroundBrushPoint = nil
            didCaptureBackgroundUndo = false

        case .selectRegion:
            if let selectionRect = session.selectionRect,
               selectionRect.width <= 0.003 || selectionRect.height <= 0.003 {
                session.selectionRect = nil
            }
            appModel.activeTool = .select

        case .maskEdit:
            if session.maskWandMode, let point = maskSourcePoint(value.location, imageRect: imageRect) {
                session.floodHideMask(atNormalized: point)
            } else {
                let normalized = maskStrokeViewPoints.compactMap { maskSourcePoint($0, imageRect: imageRect) }
                session.applyMaskStroke(normalizedPoints: normalized)
                maskStrokeViewPoints = []
            }

        case .pan, .moveAnnotation, .resizeAnnotation, .cornerRadius, .moveLayer, .resizeLayer, .rotateLayer, .moveSelection, .resizeSelection, .crop, .resizeCanvas:
            break
        }
    }

    private func updateDraftDrawing(_ value: DragGesture.Value, imageRect: CGRect) {
        if session.drawingMode == .freehand {
            draftFreehandPoints = FreehandStrokeBuilder.append(
                points: draftFreehandPoints,
                start: value.startLocation,
                location: value.location,
                inside: imageRect,
                minimumDistance: 1.5 + CGFloat(session.drawingSmoothing) * 12
            )
            return
        }

        draftAnnotation = makeShapeAnnotation(
            mode: session.drawingMode,
            start: value.startLocation,
            end: value.location,
            imageRect: imageRect
        )
    }

    private func finishDrawing(_ value: DragGesture.Value, imageRect: CGRect) {
        let annotation: Annotation?
        if session.drawingMode == .freehand {
            let completedPoints = FreehandStrokeBuilder.append(
                points: draftFreehandPoints,
                start: value.startLocation,
                location: value.location,
                inside: imageRect,
                minimumDistance: 0
            )
            annotation = makeFreehandAnnotation(points: completedPoints, imageRect: imageRect)
        } else {
            annotation = draftAnnotation ?? makeShapeAnnotation(
                mode: session.drawingMode,
                start: value.startLocation,
                end: value.location,
                imageRect: imageRect
            )
        }

        guard let annotation else { return }
        session.annotations.append(annotation)
        session.record("Add \(session.drawingMode.label.lowercased())", systemImage: session.drawingMode.symbolName)
        // Select the shape just drawn so it can be adjusted immediately.
        // Freehand keeps the brush active for continued drawing.
        if session.drawingMode != .freehand {
            session.selectedAnnotationID = annotation.id
            appModel.activeTool = .select
        } else {
            session.selectedAnnotationID = nil
        }
    }

    /// Snap a view-space point to the nearest (sub)grid intersection, using the
    /// same anchor/step as the canvas grid overlay. No-op unless snapping is on.
    private func snappedDrawPoint(_ point: CGPoint, imageRect: CGRect) -> CGPoint {
        guard session.snapToGrid else { return point }
        let workingSize = session.effectivePixelSize
        let step = session.gridSizePx * imageRect.width / max(workingSize.width, 1)
        guard step > 1 else { return point }
        let spacing = step / CGFloat(max(1, session.gridSubdivisions))
        return CGPoint(
            x: imageRect.minX + ((point.x - imageRect.minX) / spacing).rounded() * spacing,
            y: imageRect.minY + ((point.y - imageRect.minY) / spacing).rounded() * spacing
        )
    }

    private func makeShapeAnnotation(
        mode: DrawingMode,
        start rawStart: CGPoint,
        end rawEnd: CGPoint,
        imageRect: CGRect
    ) -> Annotation? {
        let start = snappedDrawPoint(rawStart, imageRect: imageRect)
        let end = snappedDrawPoint(rawEnd, imageRect: imageRect)
        guard
            let startDisplay = GeometryMapper.normalizedPoint(start, in: imageRect),
            let endDisplay = GeometryMapper.normalizedPoint(end, in: imageRect),
            let displayFrame = GeometryMapper.normalizedRect(from: start, to: end, in: imageRect),
            displayFrame.width > 0.004,
            displayFrame.height > 0.004
        else { return nil }

        let localStart = CGPoint(
            x: (startDisplay.x - displayFrame.minX) / displayFrame.width,
            y: (startDisplay.y - displayFrame.minY) / displayFrame.height
        )
        let localEnd = CGPoint(
            x: (endDisplay.x - displayFrame.minX) / displayFrame.width,
            y: (endDisplay.y - displayFrame.minY) / displayFrame.height
        )

        let kind: Annotation.Kind
        switch mode {
        case .rectangle:
            kind = .rectangle
        case .ellipse:
            kind = .ellipse
        case .line:
            kind = .line(start: localStart, end: localEnd)
        case .arrow:
            kind = .arrow(start: localStart, end: localEnd)
        case .freehand:
            return nil
        }

        return Annotation(
            kind: kind,
            frame: WorkingImageGeometry.sourceRect(
                fromDisplayNormalized: displayFrame,
                cropRect: session.cropRect
            ),
            strokeColor: library.foreground,
            fillColor: mode.supportsFill ? session.drawingFillColor : nil,
            lineWidth: session.drawingLineWidth,
            strokeStyle: session.drawingStrokeStyle,
            strokeAlignment: session.drawingStrokeAlignment,
            cornerRadius: mode == .rectangle ? session.drawingCornerRadius : 0,
            dashLength: session.drawingDashLength,
            dashGap: session.drawingDashGap,
            dashOffset: session.drawingDashOffset,
            blendMode: session.drawingBlendMode,
            opacity: session.drawingOpacity,
            z: session.nextStackZ
        )
    }

    private func makeFreehandAnnotation(points: [CGPoint], imageRect: CGRect) -> Annotation? {
        let displayPoints = points.compactMap { GeometryMapper.normalizedPoint($0, in: imageRect) }
        guard displayPoints.count > 1 else { return nil }

        // Store points in full display-normalised coordinates over a full-canvas
        // frame. Normalising into a tight bounding box (as shapes do) distorts a
        // freehand stroke because the points then get re-stretched to the box's
        // aspect ratio on render; a full-canvas frame renders exactly where drawn.
        return Annotation(
            kind: .freehand(points: displayPoints),
            frame: WorkingImageGeometry.sourceRect(
                fromDisplayNormalized: CGRect(x: 0, y: 0, width: 1, height: 1),
                cropRect: session.cropRect
            ),
            strokeColor: library.foreground,
            lineWidth: session.drawingLineWidth,
            strokeStyle: session.drawingStrokeStyle,
            opacity: session.drawingOpacity,
            z: session.nextStackZ
        )
    }

    private func placeText(at point: CGPoint, imageRect: CGRect) {
        guard let displayPoint = GeometryMapper.normalizedPoint(point, in: imageRect) else { return }
        let displayFrame = GeometryMapper.clampedNormalizedRect(
            CGRect(
                x: min(displayPoint.x, 0.68),
                y: min(displayPoint.y, 0.86),
                width: 0.3,
                height: 0.12
            )
        )
        let annotation = Annotation(
            kind: .text("Text"),
            frame: WorkingImageGeometry.sourceRect(
                fromDisplayNormalized: displayFrame,
                cropRect: session.cropRect
            ),
            strokeColor: library.foreground,
            z: session.nextStackZ
        )
        session.annotations.append(annotation)
        session.selectedAnnotationID = annotation.id
        session.record("Add text", systemImage: "textformat")
        appModel.activeTool = .select
        // Immediately edit the new text in place, with the default "Text" selected
        // so the first keystroke replaces it.
        editingTextID = annotation.id
        inlineTextFocused = true
        pendingTextSelectAll = true
    }

    private func updateLiveSample(at point: CGPoint, imageRect: CGRect) {
        guard let displayPoint = GeometryMapper.normalizedPoint(point, in: imageRect) else { return }
        let sourcePoint = WorkingImageGeometry.sourcePoint(
            fromDisplayNormalized: displayPoint,
            cropRect: session.cropRect
        )
        guard let color = PixelSampler.color(in: session.workingSourceImage, at: sourcePoint) else { return }
        session.liveSampleColor = color
        session.liveSampleLocation = point
    }

    private func applyBackgroundBrush(at point: CGPoint, imageRect: CGRect) {
        guard let current = session.backgroundRemovedImage else { return }
        if !didCaptureBackgroundUndo {
            session.backgroundRefinementUndoImage = current
            didCaptureBackgroundUndo = true
        }

        let points = interpolatedBrushPoints(from: lastBackgroundBrushPoint, to: point, imageRect: imageRect)
        lastBackgroundBrushPoint = point

        var image = current
        for point in points {
            guard let displayPoint = GeometryMapper.normalizedPoint(point, in: imageRect) else { continue }
            let sourcePoint = WorkingImageGeometry.sourcePoint(
                fromDisplayNormalized: displayPoint,
                cropRect: session.cropRect
            )
            guard let edited = BackgroundMaskEditor.applyBrush(
                to: image,
                sourceImage: session.sourceImage,
                normalizedPoint: sourcePoint,
                diameter: session.backgroundBrushSize,
                softness: session.backgroundBrushSoftness,
                strength: session.backgroundBrushStrength,
                mode: session.backgroundRefinementMode
            ) else { continue }
            image = edited
        }
        session.backgroundRemovedImage = image
        session.isDirty = true
    }

    private func interpolatedBrushPoints(from start: CGPoint?, to end: CGPoint, imageRect: CGRect) -> [CGPoint] {
        guard let start else { return [end] }
        let displayDiameter = session.backgroundBrushSize / max(session.resizePreviewSize.width, 1) * imageRect.width
        let step = max(2, displayDiameter * 0.28)
        let distance = hypot(end.x - start.x, end.y - start.y)
        let count = max(1, Int(ceil(distance / step)))
        return (1...count).map { index in
            let t = CGFloat(index) / CGFloat(count)
            return CGPoint(
                x: start.x + (end.x - start.x) * t,
                y: start.y + (end.y - start.y) * t
            )
        }
    }

    private func hitAnnotation(at point: CGPoint, imageRect: CGRect) -> Annotation? {
        session.annotations.reversed().first { annotation in
            guard let displayed = displayedAnnotationFrame(annotation.frame) else { return false }
            return GeometryMapper.viewRect(from: displayed, in: imageRect)
                .insetBy(dx: -6, dy: -6)
                .contains(point)
        }
    }

    private func hitLayer(at point: CGPoint, imageRect: CGRect) -> ImageLayer? {
        session.imageLayers.reversed().first { layer in layerContains(layer, at: point, imageRect: imageRect) }
    }

    private func annotationContains(_ annotation: Annotation, at point: CGPoint, imageRect: CGRect) -> Bool {
        guard annotation.isVisible, let displayed = displayedAnnotationFrame(annotation.frame) else { return false }
        return GeometryMapper.viewRect(from: displayed, in: imageRect).insetBy(dx: -6, dy: -6).contains(point)
    }

    private func layerContains(_ layer: ImageLayer, at point: CGPoint, imageRect: CGRect) -> Bool {
        guard session.isLayerEffectivelyVisible(layer), let displayed = displayedAnnotationFrame(layer.frame) else { return false }
        let rect = GeometryMapper.viewRect(from: displayed, in: imageRect)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return rect.contains(unrotatePoint(point, around: center, degrees: layer.rotation))
    }

    /// The top-most stack item (by shared z) under the point — layer or annotation.
    private func hitTopStackItem(at point: CGPoint, imageRect: CGRect) -> StackItem? {
        session.stackTopToBottom.first { item in
            switch item {
            case .annotation(let a): return annotationContains(a, at: point, imageRect: imageRect)
            case .layer(let l): return layerContains(l, at: point, imageRect: imageRect)
            }
        }
    }

    /// Resize handle (on a corner) or rotate (just outside a corner) for the
    /// currently-selected image layer.
    private func selectedLayerResizeMode(at point: CGPoint, imageRect: CGRect) -> DragMode? {
        guard let selectedID = session.selectedLayerID,
              let selected = session.imageLayers.first(where: { $0.id == selectedID }),
              let displayed = displayedAnnotationFrame(selected.frame) else { return nil }
        let rect = GeometryMapper.viewRect(from: displayed, in: imageRect)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let local = unrotatePoint(point, around: center, degrees: selected.rotation)
        if let corner = cornerHandle(at: local, rect: rect) {
            return .resizeLayer(id: selectedID, corner: corner, start: selected.frame)
        }
        // Rotate ring: just beyond a corner dot.
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)
        ]
        let nearest = corners.map { hypot($0.x - local.x, $0.y - local.y) }.min() ?? .infinity
        if nearest > 11, nearest < 36 {
            let startAngle = atan2(point.y - center.y, point.x - center.x)
            return .rotateLayer(id: selectedID, center: center, startAngle: startAngle, startRotation: selected.rotation)
        }
        return nil
    }

    /// The on-canvas radius handle for a selected rectangle: a dot inset from the
    /// top-left corner that drags the corner radius.
    private func cornerRadiusHandlePoint(rect: CGRect, radius: CGFloat) -> CGPoint {
        let maxD = min(rect.width, rect.height) / 2
        let d = min(max(radius, 16), max(maxD, 16))
        return CGPoint(x: rect.minX + d, y: rect.minY + d)
    }

    private func selectedShapeCornerRadiusMode(at point: CGPoint, imageRect: CGRect) -> DragMode? {
        guard let id = session.selectedAnnotationID,
              let annotation = session.annotations.first(where: { $0.id == id }),
              annotation.isRectangle,
              let displayed = displayedAnnotationFrame(annotation.frame) else { return nil }
        let rect = GeometryMapper.viewRect(from: displayed, in: imageRect)
        let dot = cornerRadiusHandlePoint(rect: rect, radius: annotation.cornerRadius)
        if hypot(dot.x - point.x, dot.y - point.y) <= 11 {
            return .cornerRadius(id: id, rect: rect)
        }
        return nil
    }

    private func layerMoveMode(at point: CGPoint, imageRect: CGRect) -> DragMode? {
        guard let layer = hitLayer(at: point, imageRect: imageRect) else { return nil }
        return layerMoveModeFor(layer)
    }

    /// Start moving a specific image layer; Option-drag duplicates it.
    private func layerMoveModeFor(_ layer: ImageLayer) -> DragMode {
        session.selectionRect = nil
        if NSEvent.modifierFlags.contains(.option),
           let copyID = session.duplicateImageLayer(id: layer.id, offset: 0),
           let copy = session.imageLayers.first(where: { $0.id == copyID }) {
            return .moveLayer(id: copyID, start: copy.frame)
        }
        session.selectedLayerID = layer.id
        session.selectedAnnotationID = nil
        return .moveLayer(id: layer.id, start: layer.frame)
    }

    /// Move-drag for an annotation; Option-drag duplicates it and drags the copy.
    private func annotationMoveMode(_ annotation: Annotation) -> DragMode {
        if NSEvent.modifierFlags.contains(.option),
           let copyID = session.duplicateAnnotation(id: annotation.id, offset: 0),
           let copy = session.annotations.first(where: { $0.id == copyID }) {
            session.selectedLayerID = nil
            return .moveAnnotation(id: copyID, start: copy.frame)
        }
        session.selectedAnnotationID = annotation.id
        session.selectedLayerID = nil
        return .moveAnnotation(id: annotation.id, start: annotation.frame)
    }

    private func displayedAnnotationFrame(_ sourceFrame: CGRect) -> CGRect? {
        WorkingImageGeometry.displayRect(
            fromSourceNormalized: sourceFrame,
            cropRect: session.cropRect
        )
    }

    private func displayedCropRect(_ sourceFrame: CGRect) -> CGRect? {
        WorkingImageGeometry.displayRect(
            fromSourceNormalized: sourceFrame,
            cropRect: session.cropRect
        )
    }

    private func cornerHandle(at point: CGPoint, rect: CGRect) -> AnnotationCorner? {
        let threshold: CGFloat = 12
        let points: [(AnnotationCorner, CGPoint)] = [
            (.topLeft, CGPoint(x: rect.minX, y: rect.minY)),
            (.topRight, CGPoint(x: rect.maxX, y: rect.minY)),
            (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)),
            (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY))
        ]
        return points.first(where: { hypot($0.1.x - point.x, $0.1.y - point.y) <= threshold })?.0
    }

    private func boxHandle(at point: CGPoint, rect: CGRect) -> BoxHandle? {
        let threshold: CGFloat = 13
        let handles: [(BoxHandle, CGPoint)] = [
            (.topLeft, CGPoint(x: rect.minX, y: rect.minY)),
            (.top, CGPoint(x: rect.midX, y: rect.minY)),
            (.topRight, CGPoint(x: rect.maxX, y: rect.minY)),
            (.left, CGPoint(x: rect.minX, y: rect.midY)),
            (.right, CGPoint(x: rect.maxX, y: rect.midY)),
            (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)),
            (.bottom, CGPoint(x: rect.midX, y: rect.maxY)),
            (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY))
        ]
        if let handle = handles.first(where: { hypot($0.1.x - point.x, $0.1.y - point.y) <= threshold }) {
            return handle.0
        }
        return rect.contains(point) ? .inside : nil
    }

    private func normalizedDisplayTranslation(_ translation: CGSize, imageRect: CGRect) -> CGSize {
        CGSize(
            width: translation.width / max(imageRect.width, 1),
            height: translation.height / max(imageRect.height, 1)
        )
    }

    private func sourceTranslation(_ translation: CGSize, imageRect: CGRect) -> CGSize {
        WorkingImageGeometry.sourceTranslation(
            fromDisplayNormalized: normalizedDisplayTranslation(translation, imageRect: imageRect),
            cropRect: session.cropRect
        )
    }

    private func movedRect(_ rect: CGRect, by delta: CGSize) -> CGRect {
        GeometryMapper.clampedNormalizedRect(
            CGRect(
                x: rect.minX + delta.width,
                y: rect.minY + delta.height,
                width: rect.width,
                height: rect.height
            )
        )
    }

    private func resizedRect(_ rect: CGRect, handle: BoxHandle, delta: CGSize) -> CGRect {
        var left = rect.minX
        var right = rect.maxX
        var top = rect.minY
        var bottom = rect.maxY

        switch handle {
        case .topLeft:
            left += delta.width
            top += delta.height
        case .top:
            top += delta.height
        case .topRight:
            right += delta.width
            top += delta.height
        case .left:
            left += delta.width
        case .right:
            right += delta.width
        case .bottomLeft:
            left += delta.width
            bottom += delta.height
        case .bottom:
            bottom += delta.height
        case .bottomRight:
            right += delta.width
            bottom += delta.height
        case .inside, .new:
            return rect
        }

        let normalized = CGRect(
            x: min(left, right),
            y: min(top, bottom),
            width: abs(right - left),
            height: abs(bottom - top)
        )
        return GeometryMapper.clampedNormalizedRect(normalized, minimumSize: 0.002)
    }

    private func resizedOutputSize(
        _ size: CGSize,
        handle: BoxHandle,
        translation: CGSize,
        imageRect: CGRect
    ) -> CGSize {
        let horizontalScale = size.width / max(imageRect.width, 1)
        let verticalScale = size.height / max(imageRect.height, 1)
        var width = size.width
        var height = size.height

        switch handle {
        case .topLeft:
            width -= translation.width * horizontalScale
            height -= translation.height * verticalScale
        case .top:
            height -= translation.height * verticalScale
        case .topRight:
            width += translation.width * horizontalScale
            height -= translation.height * verticalScale
        case .left:
            width -= translation.width * horizontalScale
        case .right:
            width += translation.width * horizontalScale
        case .bottomLeft:
            width -= translation.width * horizontalScale
            height += translation.height * verticalScale
        case .bottom:
            height += translation.height * verticalScale
        case .bottomRight:
            width += translation.width * horizontalScale
            height += translation.height * verticalScale
        case .inside, .new:
            break
        }

        width = max(1, width)
        height = max(1, height)

        if session.resizePreservesAspect {
            let ratio = session.croppedPixelSize.width / max(session.croppedPixelSize.height, 1)
            if abs(translation.width) >= abs(translation.height) {
                height = width / max(ratio, 0.0001)
            } else {
                width = height * ratio
            }
        }

        return CGSize(width: width, height: height)
    }

    private func resizeDisplayRect(in imageRect: CGRect) -> CGRect {
        let size = session.draftOutputSize ?? session.effectivePixelSize
        let widthScale = size.width / max(session.effectivePixelSize.width, 1)
        let heightScale = size.height / max(session.effectivePixelSize.height, 1)
        let displaySize = CGSize(
            width: imageRect.width * widthScale,
            height: imageRect.height * heightScale
        )
        return CGRect(
            x: imageRect.midX - displaySize.width / 2,
            y: imageRect.midY - displaySize.height / 2,
            width: displaySize.width,
            height: displaySize.height
        )
    }

    private func cropRectApplyingRatio(_ rect: CGRect, handle: BoxHandle) -> CGRect {
        let workingSize = WorkingImageGeometry.croppedPixelSize(
            sourceSize: session.pixelSize,
            cropRect: session.cropRect
        )
        guard let pixelRatio = session.cropAspectRatio.ratio(for: workingSize) else {
            return GeometryMapper.clampedNormalizedRect(rect)
        }

        let normalizedRatio = pixelRatio * workingSize.height / max(workingSize.width, 1)
        var width = rect.width
        var height = rect.height

        if width / max(height, 0.001) > normalizedRatio {
            height = width / normalizedRatio
        } else {
            width = height * normalizedRatio
        }

        var x = rect.minX
        var y = rect.minY
        switch handle {
        case .topLeft:
            x = rect.maxX - width
            y = rect.maxY - height
        case .top, .topRight:
            x = handle == .top ? rect.midX - width / 2 : rect.minX
            y = rect.maxY - height
        case .left, .bottomLeft:
            x = rect.maxX - width
            y = handle == .left ? rect.midY - height / 2 : rect.minY
        case .right:
            y = rect.midY - height / 2
        case .bottom:
            x = rect.midX - width / 2
        case .bottomRight, .new, .inside:
            break
        }

        return GeometryMapper.clampedNormalizedRect(
            CGRect(x: x, y: y, width: width, height: height),
            minimumSize: 0.002
        )
    }

    private func cornerPoints(for rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ]
    }

    private func annotationFont(_ annotation: Annotation) -> Font {
        let displayedSize = max(8, annotation.fontSize * session.zoom * 0.72)
        if annotation.fontFamily.isEmpty {
            return .system(size: displayedSize, weight: annotation.fontWeight.swiftUIWeight)
        }
        if let weightedFont = NSFontManager.shared.font(
            withFamily: annotation.fontFamily,
            traits: [],
            weight: annotation.fontWeight.fontManagerWeight,
            size: displayedSize
        ) {
            return Font(weightedFont)
        }
        return .custom(annotation.fontFamily, size: displayedSize).weight(annotation.fontWeight.swiftUIWeight)
    }

    private func textAlignment(_ alignment: AnnotationTextAlignment) -> TextAlignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private func roundedRectPath(_ rect: CGRect, radius: CGFloat) -> Path {
        guard radius > 0 else { return Path(rect) }
        let r = min(radius, min(abs(rect.width), abs(rect.height)) / 2)
        return Path(roundedRect: rect, cornerRadius: r, style: .continuous)
    }

    private func drawAnnotation(
        _ annotation: Annotation,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        let stroke = GraphicsContext.Shading.color(Color(nsColor: annotation.strokeColor))
        let dash = annotation.effectiveDash(lineWidth: annotation.lineWidth)
        let style = StrokeStyle(
            lineWidth: annotation.lineWidth,
            lineCap: .round,
            lineJoin: .round,
            dash: dash,
            dashPhase: annotation.dashOffset
        )
        let lw = annotation.lineWidth
        let baseRect = CGRect(origin: .zero, size: size)
        let strokeRect = baseRect.insetBy(
            dx: -annotation.strokeAlignment.edgeShift * lw,
            dy: -annotation.strokeAlignment.edgeShift * lw
        )

        switch annotation.kind {
        case .rectangle:
            let radius = annotation.cornerRadius
            let fillPath = roundedRectPath(baseRect, radius: radius)
            if let fill = annotation.fillColor {
                context.fill(fillPath, with: .color(Color(nsColor: fill)))
            }
            let strokeRadius = max(0, radius + annotation.strokeAlignment.edgeShift * lw)
            context.stroke(roundedRectPath(strokeRect, radius: strokeRadius), with: stroke, style: style)

        case .ellipse:
            if let fill = annotation.fillColor {
                var fillPath = Path()
                fillPath.addEllipse(in: baseRect)
                context.fill(fillPath, with: .color(Color(nsColor: fill)))
            }
            var strokePath = Path()
            strokePath.addEllipse(in: strokeRect)
            context.stroke(strokePath, with: stroke, style: style)

        case .line(let start, let end):
            var path = Path()
            path.move(to: localPoint(start, size: size))
            path.addLine(to: localPoint(end, size: size))
            context.stroke(path, with: stroke, style: style)

        case .arrow(let start, let end):
            drawArrow(
                from: localPoint(start, size: size),
                to: localPoint(end, size: size),
                context: &context,
                stroke: stroke,
                style: style
            )

        case .freehand(let points):
            guard let first = points.first else { return }
            var path = Path()
            path.move(to: localPoint(first, size: size))
            for point in points.dropFirst() {
                path.addLine(to: localPoint(point, size: size))
            }
            context.stroke(path, with: stroke, style: style)

        case .text:
            break
        }
    }

    private func drawArrow(
        from start: CGPoint,
        to end: CGPoint,
        context: inout GraphicsContext,
        stroke: GraphicsContext.Shading,
        style: StrokeStyle
    ) {
        var shaft = Path()
        shaft.move(to: start)
        shaft.addLine(to: end)
        context.stroke(shaft, with: stroke, style: style)

        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(10, style.lineWidth * 4)
        let spread: CGFloat = .pi / 7
        let left = CGPoint(
            x: end.x - cos(angle - spread) * headLength,
            y: end.y - sin(angle - spread) * headLength
        )
        let right = CGPoint(
            x: end.x - cos(angle + spread) * headLength,
            y: end.y - sin(angle + spread) * headLength
        )
        var head = Path()
        head.move(to: left)
        head.addLine(to: end)
        head.addLine(to: right)
        context.stroke(head, with: stroke, style: style)
    }

    private func localPoint(_ point: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }

    private func cancelCrop() {
        session.cancelCrop()
        appModel.activeTool = .view
    }

    private func applyCrop() {
        session.applyDraftCrop()
        appModel.activeTool = .view
    }

    private var rotatePreviewActive: Bool {
        appModel.activeTool == .rotate
    }

    private func cancelRotate() {
        session.beginRotation()
        appModel.activeTool = .view
    }

    private func applyRotate() {
        appModel.applyRotationToCurrentImage()
    }

    private func cancelResize() {
        session.cancelDraftResize()
        appModel.activeTool = .view
    }

    private func applyResize() {
        let targetSize = session.draftOutputSize ?? session.resizePreviewSize
        appModel.applyResizeToCurrentImage(
            targetSize: targetSize,
            upscaleEngine: .standard,
            upscaleContentMode: settings.upscaleContentMode
        )
    }

    private func cancelCurrentTool() {
        if session.selectionRect != nil {
            session.selectionRect = nil
            appModel.activeTool = .view
            return
        }
        draftAnnotation = nil
        draftFreehandPoints = []
        lastBackgroundBrushPoint = nil
        didCaptureBackgroundUndo = false
        appModel.cancelCurrentTool()
    }

    private enum DragMode {
        case pan(start: CGSize)
        case pick
        case draw
        case placeText
        case moveAnnotation(id: UUID, start: CGRect)
        case resizeAnnotation(id: UUID, corner: AnnotationCorner, start: CGRect)
        case cornerRadius(id: UUID, rect: CGRect)
        case moveLayer(id: UUID, start: CGRect)
        case resizeLayer(id: UUID, corner: AnnotationCorner, start: CGRect)
        case rotateLayer(id: UUID, center: CGPoint, startAngle: CGFloat, startRotation: Double)
        case moveSelection(start: CGRect)
        case resizeSelection(handle: BoxHandle, start: CGRect)
        case crop(handle: BoxHandle, start: CGRect)
        case resizeCanvas(handle: BoxHandle, start: CGSize, rect: CGRect)
        case selectRegion
        case refineBackground
        case maskEdit
    }

    private enum AnnotationCorner {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight

        var boxHandle: BoxHandle {
            switch self {
            case .topLeft: .topLeft
            case .topRight: .topRight
            case .bottomLeft: .bottomLeft
            case .bottomRight: .bottomRight
            }
        }
    }

    private enum BoxHandle: Equatable {
        case topLeft
        case top
        case topRight
        case left
        case right
        case bottomLeft
        case bottom
        case bottomRight
        case inside
        case new
    }
}

/// Selects all text in the focused NSTextView when triggered — used so a newly
/// created text item's default "Text" is highlighted for immediate replacement.
private struct TextSelectAllHelper: NSViewRepresentable {
    @Binding var trigger: Bool

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard trigger else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let textView = nsView.window?.firstResponder as? NSTextView {
                textView.selectAll(nil)
            }
            trigger = false
        }
    }
}
