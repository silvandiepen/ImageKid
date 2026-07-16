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
            let fitted = GeometryMapper.aspectFitRect(
                contentSize: session.pixelSize,
                in: bounds.insetBy(dx: 32, dy: 32)
            )
            let imageRect = transformedRect(fitted)

            ZStack {
                Color(nsColor: .underPageBackgroundColor)

                checkerboard(in: imageRect)

                Image(nsImage: session.sourceImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)

                annotations(in: imageRect)
                draftDrawing(in: imageRect)

                if appModel.activeTool == .crop {
                    CropOverlay(
                        imageRect: imageRect,
                        normalizedRect: session.draftCropRect ?? session.cropRect
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
            let rect = GeometryMapper.viewRect(from: annotation.frame, in: imageRect)

            annotationContent(annotation)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .opacity(annotation.opacity)

            if session.selectedAnnotationID == annotation.id {
                selectionOverlay(for: rect)
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
                context.opacity = annotation.opacity
                drawAnnotation(annotation, context: &context, size: size)
            }
        }
    }

    @ViewBuilder
    private func draftDrawing(in imageRect: CGRect) -> some View {
        if let draftAnnotation {
            let rect = GeometryMapper.viewRect(from: draftAnnotation.frame, in: imageRect)
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
               let selected = session.annotations.first(where: { $0.id == selectedID }) {
                let rect = GeometryMapper.viewRect(from: selected.frame, in: imageRect)
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
            let normalized = session.draftCropRect ?? session.cropRect
            let rect = GeometryMapper.viewRect(from: normalized, in: imageRect)
            if let handle = boxHandle(at: point, rect: rect) {
                return .crop(handle: handle, start: normalized)
            }
            return .crop(handle: .new, start: normalized)

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
            let delta = normalizedTranslation(value.translation, imageRect: imageRect)
            session.updateAnnotation(id: id) { annotation in
                annotation.frame = movedRect(start, by: delta)
            }

        case .resizeAnnotation(let id, let corner, let start):
            let delta = normalizedTranslation(value.translation, imageRect: imageRect)
            session.updateAnnotation(id: id) { annotation in
                annotation.frame = resizedRect(start, handle: corner.boxHandle, delta: delta)
            }

        case .crop(let handle, let start):
            if handle == .new {
                guard let newRect = GeometryMapper.normalizedRect(
                    from: value.startLocation,
                    to: value.location,
                    in: imageRect
                ) else { return }
                session.draftCropRect = cropRectApplyingRatio(newRect, handle: .bottomRight)
            } else {
                let delta = normalizedTranslation(value.translation, imageRect: imageRect)
                let changed = handle == .inside
                    ? movedRect(start, by: delta)
                    : resizedRect(start, handle: handle, delta: delta)
                session.draftCropRect = cropRectApplyingRatio(changed, handle: handle)
            }
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
            guard imageRect.contains(value.location) else { return }
            if let last = draftFreehandPoints.last,
               hypot(last.x - value.location.x, last.y - value.location.y) < 1.5 {
                return
            }
            draftFreehandPoints.append(value.location)
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
            annotation = makeFreehandAnnotation(points: draftFreehandPoints, imageRect: imageRect)
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
        session.selectedAnnotationID = annotation.id
        session.isDirty = true
        appModel.activeTool = .view
    }

    private func makeShapeAnnotation(
        mode: DrawingMode,
        start: CGPoint,
        end: CGPoint,
        imageRect: CGRect
    ) -> Annotation? {
        guard
            let startNormalized = GeometryMapper.normalizedPoint(start, in: imageRect),
            let endNormalized = GeometryMapper.normalizedPoint(end, in: imageRect),
            let frame = GeometryMapper.normalizedRect(from: start, to: end, in: imageRect),
            frame.width > 0.004,
            frame.height > 0.004
        else { return nil }

        let localStart = CGPoint(
            x: (startNormalized.x - frame.minX) / frame.width,
            y: (startNormalized.y - frame.minY) / frame.height
        )
        let localEnd = CGPoint(
            x: (endNormalized.x - frame.minX) / frame.width,
            y: (endNormalized.y - frame.minY) / frame.height
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
            frame: frame,
            strokeColor: session.drawingStrokeColor,
            fillColor: mode.supportsFill ? session.drawingFillColor : nil,
            lineWidth: session.drawingLineWidth,
            opacity: session.drawingOpacity
        )
    }

    private func makeFreehandAnnotation(points: [CGPoint], imageRect: CGRect) -> Annotation? {
        let normalized = points.compactMap { GeometryMapper.normalizedPoint($0, in: imageRect) }
        guard normalized.count > 1 else { return nil }

        let minX = normalized.map(\.x).min() ?? 0
        let maxX = normalized.map(\.x).max() ?? 0
        let minY = normalized.map(\.y).min() ?? 0
        let maxY = normalized.map(\.y).max() ?? 0
        let rawFrame = CGRect(
            x: minX,
            y: minY,
            width: max(maxX - minX, 0.01),
            height: max(maxY - minY, 0.01)
        )
        let frame = GeometryMapper.clampedNormalizedRect(rawFrame)
        let localPoints = normalized.map { point in
            CGPoint(
                x: (point.x - frame.minX) / max(frame.width, 0.001),
                y: (point.y - frame.minY) / max(frame.height, 0.001)
            )
        }

        return Annotation(
            kind: .freehand(points: localPoints),
            frame: frame,
            strokeColor: session.drawingStrokeColor,
            lineWidth: session.drawingLineWidth,
            opacity: session.drawingOpacity
        )
    }

    private func placeText(at point: CGPoint, imageRect: CGRect) {
        guard let normalized = GeometryMapper.normalizedPoint(point, in: imageRect) else { return }
        let frame = GeometryMapper.clampedNormalizedRect(
            CGRect(
                x: min(normalized.x, 0.68),
                y: min(normalized.y, 0.86),
                width: 0.3,
                height: 0.12
            )
        )
        let annotation = Annotation(kind: .text("Text"), frame: frame)
        session.annotations.append(annotation)
        session.selectedAnnotationID = annotation.id
        session.isDirty = true
        appModel.activeTool = .view
    }

    private func updateLiveSample(at point: CGPoint, imageRect: CGRect) {
        guard let normalized = GeometryMapper.normalizedPoint(point, in: imageRect),
              let color = PixelSampler.color(in: session.sourceImage, at: normalized) else {
            return
        }
        session.liveSampleColor = color
        session.liveSampleLocation = point
    }

    private func hitAnnotation(at point: CGPoint, imageRect: CGRect) -> Annotation? {
        session.annotations.reversed().first { annotation in
            GeometryMapper.viewRect(from: annotation.frame, in: imageRect)
                .insetBy(dx: -6, dy: -6)
                .contains(point)
        }
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

    private func normalizedTranslation(_ translation: CGSize, imageRect: CGRect) -> CGSize {
        CGSize(
            width: translation.width / max(imageRect.width, 1),
            height: translation.height / max(imageRect.height, 1)
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
        return GeometryMapper.clampedNormalizedRect(normalized, minimumSize: 0.025)
    }

    private func cropRectApplyingRatio(_ rect: CGRect, handle: BoxHandle) -> CGRect {
        guard let pixelRatio = session.cropAspectRatio.ratio(for: session.pixelSize) else {
            return GeometryMapper.clampedNormalizedRect(rect)
        }

        let normalizedRatio = pixelRatio * session.pixelSize.height / max(session.pixelSize.width, 1)
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
            minimumSize: 0.025
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
        let displayedSize = max(
            8,
            annotation.fontSize * session.zoom * 0.72
        )
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
