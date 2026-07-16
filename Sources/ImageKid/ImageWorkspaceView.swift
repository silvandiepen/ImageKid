import AppKit
import SwiftUI

struct ImageWorkspaceView: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject var session: ImageSession

    @State private var hoverControls = false
    @State private var dragMode: DragMode?
    @State private var draftAnnotationRect: CGRect?

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let fitted = GeometryMapper.aspectFitRect(contentSize: session.pixelSize, in: bounds.insetBy(dx: 32, dy: 32))
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

                if let draftAnnotationRect {
                    Rectangle()
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                        .frame(width: draftAnnotationRect.width, height: draftAnnotationRect.height)
                        .position(x: draftAnnotationRect.midX, y: draftAnnotationRect.midY)
                }

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
        }
    }

    @ViewBuilder
    private var toolPanels: some View {
        VStack {
            HStack(alignment: .top) {
                Spacer()

                if appModel.activeTool == .pickColor {
                    ColorPalettePanel(session: session)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else if let selected = session.selectedAnnotation,
                          selected.isText {
                    TextInspector(session: session, annotationID: selected.id)
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

            if appModel.activeTool == .crop {
                CropControls(
                    session: session,
                    onCancel: {
                        session.draftCropRect = nil
                        appModel.activeTool = .view
                    },
                    onApply: {
                        session.applyDraftCrop()
                        appModel.activeTool = .view
                    }
                )
            } else {
                FloatingToolbar(canExport: true)
                    .opacity(hoverControls || appModel.activeTool != .view || session.selectedAnnotationID != nil ? 1 : 0)
                    .offset(y: hoverControls || appModel.activeTool != .view || session.selectedAnnotationID != nil ? 0 : 8)
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
                                Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)),
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

            Group {
                switch annotation.kind {
                case .rectangle:
                    Rectangle()
                        .stroke(Color(nsColor: annotation.strokeColor), lineWidth: annotation.lineWidth)
                        .background(
                            Rectangle().fill(
                                annotation.fillColor.map { Color(nsColor: $0) } ?? .clear
                            )
                        )

                case .text(let value):
                    Text(value)
                        .font(annotationFont(annotation, imageRect: imageRect))
                        .foregroundStyle(Color(nsColor: annotation.strokeColor))
                        .multilineTextAlignment(textAlignment(annotation.textAlignment))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: annotation.textAlignment.swiftUIAlignment)
                }
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)

            if session.selectedAnnotationID == annotation.id {
                selectionOverlay(for: rect)
            }
        }
    }

    @ViewBuilder
    private func selectionOverlay(for rect: CGRect) -> some View {
        Rectangle()
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)

        ForEach(cornerPoints(for: rect), id: \.self) { point in
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
                .frame(width: 70, height: 70)
                .overlay(Circle().stroke(.white, lineWidth: 4))
                .overlay(Circle().stroke(.black.opacity(0.2), lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 12, y: 5)

            Text(sample.hex)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: Capsule())
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
                draftAnnotationRect = nil
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

        case .rectangle:
            return .drawRectangle

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

        case .drawRectangle:
            draftAnnotationRect = rect(from: value.startLocation, to: value.location)

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

        case .drawRectangle:
            guard let normalizedRect = GeometryMapper.normalizedRect(
                from: value.startLocation,
                to: value.location,
                in: imageRect
            ), normalizedRect.width > 0.005, normalizedRect.height > 0.005 else { return }
            let annotation = Annotation(kind: .rectangle, frame: normalizedRect)
            session.annotations.append(annotation)
            session.selectedAnnotationID = annotation.id
            session.isDirty = true
            appModel.activeTool = .view

        case .placeText:
            guard let normalized = GeometryMapper.normalizedPoint(value.location, in: imageRect) else { return }
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

        case .pan, .moveAnnotation, .resizeAnnotation, .crop:
            break
        }
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
                .insetBy(dx: -5, dy: -5)
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

    private func annotationFont(_ annotation: Annotation, imageRect: CGRect) -> Font {
        let displayedSize = max(8, annotation.fontSize * imageRect.width / max(session.pixelSize.width, 1))
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

    private func rect(from first: CGPoint, to second: CGPoint) -> CGRect {
        CGRect(
            x: min(first.x, second.x),
            y: min(first.y, second.y),
            width: abs(second.x - first.x),
            height: abs(second.y - first.y)
        )
    }

    private enum DragMode {
        case pan(start: CGSize)
        case pick
        case drawRectangle
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
