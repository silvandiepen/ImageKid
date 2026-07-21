import AppKit
import SwiftUI

struct ImageWorkspaceView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var session: ImageSession
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
    @State private var progressBarOffset: CGSize = .zero

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

                annotations(in: imageRect)
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
                        imageRect: resizeDisplayRect(in: imageRect),
                        size: session.draftOutputSize ?? session.effectivePixelSize
                    )
                }

                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(interactionGesture(in: imageRect))
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
                if tool != .view {
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
                        return false
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
            VStack {
                HStack(alignment: .top) {
                    Spacer()
                    rightToolPanels
                }
                Spacer()
            }
            .padding(.top, 54)
            .padding(.trailing, 18)
            .animation(.easeOut(duration: 0.18), value: appModel.activeTool)
            .animation(.easeOut(duration: 0.18), value: session.selectedAnnotationID)

            // Movable, minimizable dockable panels + their minimized icon rail.
            dockablePanelsLayer
                .padding(.top, 54)
                .padding(.leading, 18)
        }
    }

    @ViewBuilder
    private var rightToolPanels: some View {
        if appModel.activeTool == .pickColor {
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
                onApply: applyResize
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
        ZStack(alignment: .topLeading) {
            if appModel.isPanelExpanded(.layers) {
                LayersPanel(
                    session: session,
                    appModel: appModel,
                    offset: panelBinding(.layers),
                    size: panelSizeBinding(.layers),
                    onMinimize: { appModel.minimizePanel(.layers) }
                )
            }
            if appModel.isPanelExpanded(.history) {
                HistoryPanel(
                    session: session,
                    offset: panelBinding(.history),
                    size: panelSizeBinding(.history),
                    onMinimize: { appModel.minimizePanel(.history) }
                )
            }
            PanelDockRail(appModel: appModel)
                .animation(.easeOut(duration: 0.18), value: appModel.minimizedPanelList)
        }
    }

    private func panelBinding(_ panel: DockablePanel) -> Binding<CGSize> {
        Binding(
            get: { appModel.panelPosition(panel) },
            set: { appModel.setPanelPosition(panel, to: $0) }
        )
    }

    private func panelSizeBinding(_ panel: DockablePanel) -> Binding<CGSize> {
        Binding(
            get: { appModel.panelSize(panel) },
            set: { appModel.setPanelSize(panel, to: $0) }
        )
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
                isCollapsed: $isViewportToolbarCollapsed
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

    @ViewBuilder
    private func annotations(in imageRect: CGRect) -> some View {
        ForEach(session.annotations) { annotation in
            if let displayedFrame = displayedAnnotationFrame(annotation.frame) {
                let rect = GeometryMapper.viewRect(from: displayedFrame, in: imageRect)

                annotationContent(annotation)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .opacity(annotation.opacity)

                if session.selectedAnnotationID == annotation.id {
                    selectionOverlay(for: rect)
                }
            }
        }
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
            Canvas { context, size in
                drawAnnotation(annotation, context: &context, size: size)
            }
        }
    }

    @ViewBuilder
    private func draftDrawing(in imageRect: CGRect) -> some View {
        if let draftAnnotation,
           let displayedFrame = displayedAnnotationFrame(draftAnnotation.frame) {
            let rect = GeometryMapper.viewRect(from: displayedFrame, in: imageRect)
            annotationContent(draftAnnotation)
                .frame(width: rect.width, height: rect.height)
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
    private func selectionOverlay(for rect: CGRect) -> some View {
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
                default:
                    break
                }
                dragMode = nil
                draftAnnotation = nil
                draftFreehandPoints = []
            }
    }

    private func resolveDragMode(at point: CGPoint, imageRect: CGRect) -> DragMode {
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

            if let selectedID = session.selectedAnnotationID,
               let selected = session.annotations.first(where: { $0.id == selectedID }),
               let displayed = displayedAnnotationFrame(selected.frame) {
                let rect = GeometryMapper.viewRect(from: displayed, in: imageRect)
                if let corner = cornerHandle(at: point, rect: rect) {
                    return .resizeAnnotation(id: selectedID, corner: corner, start: selected.frame)
                }
            }

            if let annotation = hitAnnotation(at: point, imageRect: imageRect) {
                session.selectionRect = nil
                session.selectedAnnotationID = annotation.id
                return .moveAnnotation(id: annotation.id, start: annotation.frame)
            }

            session.selectedAnnotationID = nil
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
            if let selectedID = session.selectedAnnotationID,
               let selected = session.annotations.first(where: { $0.id == selectedID }),
               let displayed = displayedAnnotationFrame(selected.frame) {
                let rect = GeometryMapper.viewRect(from: displayed, in: imageRect)
                if let corner = cornerHandle(at: point, rect: rect) {
                    return .resizeAnnotation(id: selectedID, corner: corner, start: selected.frame)
                }
            }

            if let annotation = hitAnnotation(at: point, imageRect: imageRect) {
                session.selectedAnnotationID = annotation.id
                return .moveAnnotation(id: annotation.id, start: annotation.frame)
            }

            session.selectedAnnotationID = nil
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

        case .placeText:
            break

        case .moveAnnotation(let id, let start):
            let delta = sourceTranslation(value.translation, imageRect: imageRect)
            session.updateAnnotation(id: id) { annotation in
                annotation.frame = movedRect(start, by: delta)
            }

        case .resizeAnnotation(let id, let corner, let start):
            let delta = sourceTranslation(value.translation, imageRect: imageRect)
            session.updateAnnotation(id: id) { annotation in
                annotation.frame = resizedRect(start, handle: corner.boxHandle, delta: delta)
            }

        case .moveSelection(let start):
            let delta = normalizedDisplayTranslation(value.translation, imageRect: imageRect)
            session.selectionRect = movedRect(start, by: delta)

        case .resizeSelection(let handle, let start):
            let delta = normalizedDisplayTranslation(value.translation, imageRect: imageRect)
            session.selectionRect = resizedRect(start, handle: handle, delta: delta)

        case .crop(let handle, let start):
            let displayedRect: CGRect
            if handle == .new {
                guard let newRect = GeometryMapper.normalizedRect(
                    from: value.startLocation,
                    to: value.location,
                    in: imageRect
                ) else { return }
                displayedRect = cropRectApplyingRatio(newRect, handle: .bottomRight)
            } else {
                let delta = normalizedDisplayTranslation(value.translation, imageRect: imageRect)
                let changed = handle == .inside
                    ? movedRect(start, by: delta)
                    : resizedRect(start, handle: handle, delta: delta)
                displayedRect = cropRectApplyingRatio(changed, handle: handle)
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
            session.selectionRect = GeometryMapper.clampedNormalizedRect(selection, minimumSize: 0.001)

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

        case .pan, .moveAnnotation, .resizeAnnotation, .moveSelection, .resizeSelection, .crop, .resizeCanvas:
            break
        }
    }

    private func updateDraftDrawing(_ value: DragGesture.Value, imageRect: CGRect) {
        if session.drawingMode == .freehand {
            draftFreehandPoints = FreehandStrokeBuilder.append(
                points: draftFreehandPoints,
                start: value.startLocation,
                location: value.location,
                inside: imageRect
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
        session.selectedAnnotationID = nil
        session.record("Add \(session.drawingMode.label.lowercased())", systemImage: session.drawingMode.symbolName)
    }

    private func makeShapeAnnotation(
        mode: DrawingMode,
        start: CGPoint,
        end: CGPoint,
        imageRect: CGRect
    ) -> Annotation? {
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
            strokeColor: session.drawingStrokeColor,
            fillColor: mode.supportsFill ? session.drawingFillColor : nil,
            lineWidth: session.drawingLineWidth,
            opacity: session.drawingOpacity
        )
    }

    private func makeFreehandAnnotation(points: [CGPoint], imageRect: CGRect) -> Annotation? {
        let displayPoints = points.compactMap { GeometryMapper.normalizedPoint($0, in: imageRect) }
        guard displayPoints.count > 1 else { return nil }

        let minX = displayPoints.map(\.x).min() ?? 0
        let maxX = displayPoints.map(\.x).max() ?? 0
        let minY = displayPoints.map(\.y).min() ?? 0
        let maxY = displayPoints.map(\.y).max() ?? 0
        let displayFrame = GeometryMapper.clampedNormalizedRect(
            CGRect(
                x: minX,
                y: minY,
                width: max(maxX - minX, 0.002),
                height: max(maxY - minY, 0.002)
            ),
            minimumSize: 0.002
        )
        let localPoints = displayPoints.map { point in
            CGPoint(
                x: (point.x - displayFrame.minX) / max(displayFrame.width, 0.001),
                y: (point.y - displayFrame.minY) / max(displayFrame.height, 0.001)
            )
        }

        return Annotation(
            kind: .freehand(points: localPoints),
            frame: WorkingImageGeometry.sourceRect(
                fromDisplayNormalized: displayFrame,
                cropRect: session.cropRect
            ),
            strokeColor: session.drawingStrokeColor,
            lineWidth: session.drawingLineWidth,
            opacity: session.drawingOpacity
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
            strokeColor: session.autoContrastColor
        )
        session.annotations.append(annotation)
        session.selectedAnnotationID = annotation.id
        session.record("Add text", systemImage: "textformat")
        appModel.activeTool = .view
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

    private func drawAnnotation(
        _ annotation: Annotation,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        let stroke = GraphicsContext.Shading.color(Color(nsColor: annotation.strokeColor))
        let style = StrokeStyle(
            lineWidth: annotation.lineWidth,
            lineCap: .round,
            lineJoin: .round
        )

        switch annotation.kind {
        case .rectangle:
            let path = Path(CGRect(origin: .zero, size: size))
            if let fill = annotation.fillColor {
                context.fill(path, with: .color(Color(nsColor: fill)))
            }
            context.stroke(path, with: stroke, style: style)

        case .ellipse:
            var path = Path()
            path.addEllipse(in: CGRect(origin: .zero, size: size))
            if let fill = annotation.fillColor {
                context.fill(path, with: .color(Color(nsColor: fill)))
            }
            context.stroke(path, with: stroke, style: style)

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
        case moveSelection(start: CGRect)
        case resizeSelection(handle: BoxHandle, start: CGRect)
        case crop(handle: BoxHandle, start: CGRect)
        case resizeCanvas(handle: BoxHandle, start: CGSize, rect: CGRect)
        case selectRegion
        case refineBackground
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
