import AppKit
import SwiftUI

struct ImageWorkspaceView: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject var session: ImageSession

    @State private var hoverControls = false
    @State private var dragMode: DragMode?
    @State private var draftAnnotation: Annotation?
    @State private var draftFreehandPoints: [CGPoint] = []
    @State private var panelOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let workingSize = WorkingImageGeometry.croppedPixelSize(
                sourceSize: session.pixelSize,
                cropRect: session.cropRect
            )
            let fitted = GeometryMapper.aspectFitRect(
                contentSize: workingSize,
                in: bounds.insetBy(dx: 32, dy: 32)
            )
            let imageRect = transformedRect(fitted)
            let workingImage = WorkingImagePreview.croppedImage(
                from: session.sourceImage,
                cropRect: session.cropRect
            )

            ZStack {
                Color(nsColor: .underPageBackgroundColor)

                checkerboard(in: imageRect)

                Image(nsImage: workingImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)

                annotations(in: imageRect)
                draftDrawing(in: imageRect)

                if appModel.activeTool == .crop,
                   let displayedCrop = displayedCropRect(session.draftCropRect ?? session.cropRect) {
                    CropOverlay(
                        imageRect: imageRect,
                        normalizedRect: displayedCrop
                    )
                }

                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(interactionGesture(in: imageRect))

                TrackpadGestureMonitor(
                    onPan: { delta in
                        guard appModel.activeTool == .view else { return }
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

                toolPanels
                controls
            }
            .clipped()
            .onHover { inside in
                withAnimation(.easeOut(duration: 0.15)) {
                    hoverControls = inside
                }
            }
            .onChange(of: appModel.activeTool) { _, tool in
                if tool == .crop, session.draftCropRect == nil {
                    session.draftCropRect = session.cropRect
                }
                if tool != .view {
                    session.selectedAnnotationID = nil
                }
            }
            .onExitCommand {
                cancelCurrentTool()
            }
        }
    }

    @ViewBuilder
    private var toolPanels: some View {
        VStack {
            HStack(alignment: .top) {
                Spacer()

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
            Spacer()
        }
        .padding(.top, 54)
        .padding(.trailing, 18)
        .animation(.easeOut(duration: 0.18), value: appModel.activeTool)
        .animation(.easeOut(duration: 0.18), value: session.selectedAnnotationID)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Spacer()

            if appModel.activeTool != .crop {
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

    @ViewBuilder
    private func checkerboard(in imageRect: CGRect) -> some View {
        Rectangle()
            .fill(Color.white)
            .frame(width: imageRect.width, height: imageRect.height)
            .position(x: imageRect.midX, y: imageRect.midY)
            .overlay {
                Canvas { context, size in
                    let cell: CGFloat = 12
                    for row in 0...Int(size.height / cell) {
                        for column in 0...Int(size.width / cell) where (row + column).isMultiple(of: 2) {
                            context.fill(
                                Path(CGRect(
                                    x: CGFloat(column) * cell,
                                    y: CGFloat(row) * cell,
                                    width: cell,
                                    height: cell
                                )),
                                with: .color(.gray.opacity(0.18))
                            )
                        }
                    }
                }
                .frame(width: imageRect.width, height: imageRect.height)
                .position(x: imageRect.midX, y: imageRect.midY)
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
                dragMode = nil
                draftAnnotation = nil
                draftFreehandPoints = []
            }
    }

    private func resolveDragMode(at point: CGPoint, imageRect: CGRect) -> DragMode {
        switch appModel.activeTool {
        case .view:
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

        case .draw:
            return .draw

        case .text:
            return .placeText
        }
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

        case .pan, .moveAnnotation, .resizeAnnotation, .crop:
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
        session.isDirty = true
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
            )
        )
        session.annotations.append(annotation)
        session.selectedAnnotationID = annotation.id
        session.isDirty = true
        appModel.activeTool = .view
    }

    private func updateLiveSample(at point: CGPoint, imageRect: CGRect) {
        guard let displayPoint = GeometryMapper.normalizedPoint(point, in: imageRect) else { return }
        let sourcePoint = WorkingImageGeometry.sourcePoint(
            fromDisplayNormalized: displayPoint,
            cropRect: session.cropRect
        )
        guard let color = PixelSampler.color(in: session.sourceImage, at: sourcePoint) else { return }
        session.liveSampleColor = color
        session.liveSampleLocation = point
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
        return .custom(annotation.fontFamily, size: displayedSize)
            .weight(annotation.fontWeight.swiftUIWeight)
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
        session.resetView()
        appModel.activeTool = .view
    }

    private func cancelCurrentTool() {
        draftAnnotation = nil
        draftFreehandPoints = []
        appModel.cancelCurrentTool()
    }

    private enum DragMode {
        case pan(start: CGSize)
        case pick
        case draw
        case placeText
        case moveAnnotation(id: UUID, start: CGRect)
        case resizeAnnotation(id: UUID, corner: AnnotationCorner, start: CGRect)
        case crop(handle: BoxHandle, start: CGRect)
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
