import AppKit
import SwiftUI

/// The source image with the slice rectangles and cutting guides drawn on it.
/// This is the whole interface: the Slice tool draws and edits rectangles, the
/// Guides tool drags cutting lines, and Auto Slice turns those lines into
/// slices.
struct SlicerCanvas: View {
    @ObservedObject var model: SlicerDocumentModel
    let source: SlicerDocumentModel.Source

    /// What the current pointer drag is doing. Established on the first
    /// `onChanged` and held until the drag ends.
    private enum DragOperation {
        case creating(origin: CGPoint)
        case moving(id: Slice.ID, startRect: CGRect)
        case resizing(id: Slice.ID, handle: SliceHandle)
        case creatingGuide(origin: CGPoint)
        case movingGuide(id: SliceGuide.ID)
        case creatingCrop(origin: CGPoint)
        case movingCrop(startRect: CGRect)
        case resizingCrop(handle: SliceHandle)
    }

    /// The guide lines a live drag is currently latched onto, so the user can
    /// see *why* the rectangle stopped where it did.
    private struct SnapIndicator {
        var vertical: [CGFloat] = []
        var horizontal: [CGFloat] = []

        var isEmpty: Bool { vertical.isEmpty && horizontal.isEmpty }
    }

    @State private var operation: DragOperation?
    @State private var draftRect: CGRect?
    @State private var draftGuide: SliceGuide?
    @State private var snapIndicator = SnapIndicator()

    private static let handleTolerance: CGFloat = SliceOverlay.handleSize
    private static let guideTolerance: CGFloat = 7
    private static let snapTolerance: CGFloat = 8
    private static let guideAxisThreshold: CGFloat = 4
    private static let canvasPadding: CGFloat = 24

    var body: some View {
        GeometryReader { proxy in
            let layout = SliceCanvasLayout.make(
                pixelSize: source.pixelSize,
                bounds: CGRect(origin: .zero, size: proxy.size),
                zoom: model.zoom,
                pan: model.panOffset,
                padding: Self.canvasPadding
            )

            ZStack {
                SlicerSurface.canvas

                if layout.isUsable {
                    Image(nsImage: source.preview)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: layout.imageRect.width, height: layout.imageRect.height)
                        .shadow(color: .black.opacity(0.55), radius: 22, y: 8)
                        .position(x: layout.imageRect.midX, y: layout.imageRect.midY)
                        .accessibilityLabel("Source image, \(Int(source.pixelSize.width)) by \(Int(source.pixelSize.height)) pixels")

                    gridLayer(layout: layout)

                    if model.activeTool == .crop {
                        // One region at a time: the slice overlays would only
                        // compete with the dimming for attention.
                        cropLayer(layout: layout, canvasSize: proxy.size)
                    } else {
                        slicesLayer(layout: layout)
                        guidesLayer(layout: layout)
                    }

                    draftLayer(layout: layout)
                    snapLayer(layout: layout)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(layout: layout))
            .overlay(
                CanvasPointerEvents(
                    onScroll: { delta in pan(by: delta) },
                    onMagnify: { factor in model.setZoom(model.zoom * (1 + factor)) },
                    onDoubleClick: { point in openInspector(at: point, layout: layout) }
                )
                .allowsHitTesting(false)
            )
            .background(
                CanvasKeyMonitor(
                    onEscape: {
                        // Escape abandons an in-flight drag first; with nothing
                        // in flight it clears the selection.
                        if operation != nil || draftRect != nil || draftGuide != nil {
                            cancelActiveOperation()
                        } else {
                            model.clearSelection()
                        }
                    },
                    onDelete: {
                        guard model.hasSelection else { return false }
                        model.deleteSelection()
                        return true
                    }
                )
            )
        }
    }

    // MARK: - Layers

    private func gridLayer(layout: SliceCanvasLayout) -> some View {
        Path { path in
            let rect = layout.imageRect
            for x in model.grid.verticalLines {
                path.move(to: CGPoint(x: rect.minX + x * rect.width, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.minX + x * rect.width, y: rect.maxY))
            }
            for y in model.grid.horizontalLines {
                path.move(to: CGPoint(x: rect.minX, y: rect.minY + y * rect.height))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + y * rect.height))
            }
        }
        .stroke(Color.white.opacity(0.28), lineWidth: 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func slicesLayer(layout: SliceCanvasLayout) -> some View {
        ForEach(Array(model.slices.enumerated()), id: \.element.id) { index, slice in
            SliceOverlay(
                slice: slice,
                index: index,
                isSelected: slice.id == model.selectedSliceID,
                viewRect: layout.viewRect(for: slice.rect),
                pixelRect: SliceGeometry.pixelRect(slice.rect, pixelSize: source.pixelSize)
            )
            .popover(isPresented: inspectorBinding(for: slice), arrowEdge: .trailing) {
                SliceInspector(model: model, slice: slice, index: index, source: source)
            }
            .contextMenu {
                Button("Edit Slice…") { model.inspect(id: slice.id) }
                Button(slice.isLocked ? "Unlock Slice" : "Lock Slice") {
                    model.setLocked(!slice.isLocked, id: slice.id)
                }
                Button("Delete Slice") { model.delete(id: slice.id) }
                    .disabled(slice.isLocked)
            }
        }
    }

    @ViewBuilder
    private func cropLayer(layout: SliceCanvasLayout, canvasSize: CGSize) -> some View {
        if let cropRect = model.cropRect {
            CropOverlay(
                viewRect: layout.viewRect(for: cropRect),
                canvasSize: canvasSize,
                pixelRect: SliceGeometry.pixelRect(cropRect, pixelSize: source.pixelSize)
            )
        }
    }

    private func guidesLayer(layout: SliceCanvasLayout) -> some View {
        ForEach(model.guides) { guide in
            GuideLine(
                guide: guide,
                isSelected: guide.id == model.selectedGuideID,
                imageRect: layout.imageRect,
                pixelSize: source.pixelSize
            )
            .contextMenu {
                Button("Delete Guide") { model.delete(guideID: guide.id) }
            }
        }
    }

    @ViewBuilder
    private func draftLayer(layout: SliceCanvasLayout) -> some View {
        if let draftRect {
            let rect = layout.viewRect(for: draftRect)
            Rectangle()
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
        }

        if let draftGuide {
            GuideLine(
                guide: draftGuide,
                isSelected: true,
                imageRect: layout.imageRect,
                pixelSize: source.pixelSize
            )
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func snapLayer(layout: SliceCanvasLayout) -> some View {
        if !snapIndicator.isEmpty {
            Path { path in
                let rect = layout.imageRect
                for x in snapIndicator.vertical {
                    path.move(to: CGPoint(x: rect.minX + x * rect.width, y: rect.minY))
                    path.addLine(to: CGPoint(x: rect.minX + x * rect.width, y: rect.maxY))
                }
                for y in snapIndicator.horizontal {
                    path.move(to: CGPoint(x: rect.minX, y: rect.minY + y * rect.height))
                    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + y * rect.height))
                }
            }
            .stroke(Color.pink, lineWidth: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Pointer

    private func dragGesture(layout: SliceCanvasLayout) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard layout.isUsable else { return }
                if operation == nil {
                    operation = beginOperation(at: value.startLocation, layout: layout)
                }
                continueOperation(value: value, layout: layout)
            }
            .onEnded { value in
                guard layout.isUsable else { return }
                if operation == nil {
                    operation = beginOperation(at: value.startLocation, layout: layout)
                }
                continueOperation(value: value, layout: layout)
                finishOperation()
            }
    }

    private func beginOperation(at point: CGPoint, layout: SliceCanvasLayout) -> DragOperation {
        if model.activeTool == .crop {
            if let cropRect = model.cropRect {
                if let handle = layout.handle(at: point, of: cropRect, tolerance: CropOverlay.handleSize) {
                    return .resizingCrop(handle: handle)
                }
                // A crop covering the whole image has nowhere to move to and no
                // outside to start a new drag from, so dragging inside it draws
                // a fresh region. Once it is smaller, dragging inside moves it.
                let coversEverything = cropRect.width > 0.999 && cropRect.height > 0.999
                if !coversEverything, layout.viewRect(for: cropRect).contains(point) {
                    return .movingCrop(startRect: cropRect)
                }
            }
            return .creatingCrop(origin: layout.normalizedPoint(point))
        }

        if model.activeTool == .guides {
            if let guide = guide(at: point, layout: layout) {
                model.selectedSliceID = nil
                model.selectedGuideID = guide.id
                return .movingGuide(id: guide.id)
            }
            model.clearSelection()
            return .creatingGuide(origin: point)
        }

        // A selected slice keeps its handles: check those before anything else,
        // otherwise a handle sitting over a neighbouring slice would select it.
        if
            let selected = model.selectedSlice,
            let handle = layout.handle(at: point, of: selected.rect, tolerance: Self.handleTolerance)
        {
            return .resizing(id: selected.id, handle: handle)
        }

        // Topmost first: the most recently drawn slice wins an overlap. Locked
        // slices are skipped entirely, so a drag that starts on one draws a new
        // slice rather than picking the locked one up.
        if let hit = model.slices.reversed().first(where: {
            !$0.isLocked && layout.viewRect(for: $0.rect).contains(point)
        }) {
            model.selectedSliceID = hit.id
            model.selectedGuideID = nil
            return .moving(id: hit.id, startRect: hit.rect)
        }

        model.clearSelection()
        return .creating(origin: layout.normalizedPoint(point))
    }

    private func continueOperation(value: DragGesture.Value, layout: SliceCanvasLayout) {
        let shift = NSEvent.modifierFlags.contains(.shift)

        switch operation {
        case .creating(let origin):
            var rect = SliceGeometry.rect(
                from: origin,
                to: layout.normalizedPoint(value.location),
                square: shift,
                pixelAspect: source.pixelAspect
            )
            if !shift {
                let snapped = snapping(layout: layout, excluding: nil).map { context in
                    SliceSnapping.snapEdges(
                        rect,
                        movingLeft: true, movingRight: true, movingTop: true, movingBottom: true,
                        targets: context.targets,
                        thresholdX: context.thresholdX,
                        thresholdY: context.thresholdY
                    )
                }
                if let snapped {
                    rect = snapped.rect
                    show(snapped)
                }
            }
            draftRect = rect

        case .moving(let id, let startRect):
            var rect = SliceGeometry.moved(startRect, by: layout.normalizedDelta(value.translation))
            if let context = snapping(layout: layout, excluding: id) {
                let snapped = SliceSnapping.snapMoved(
                    rect,
                    targets: context.targets,
                    thresholdX: context.thresholdX,
                    thresholdY: context.thresholdY
                )
                rect = snapped.rect
                show(snapped)
            }
            model.updateSlice(id: id, rect: rect)

        case .resizing(let id, let handle):
            guard let slice = model.slices.first(where: { $0.id == id }) else { return }
            var rect = SliceGeometry.resized(
                slice.rect,
                handle: handle,
                to: layout.normalizedPoint(value.location),
                square: shift,
                pixelAspect: source.pixelAspect
            )
            if !shift, let context = snapping(layout: layout, excluding: id) {
                let snapped = SliceSnapping.snapEdges(
                    rect,
                    movingLeft: movesLeftEdge(handle),
                    movingRight: movesRightEdge(handle),
                    movingTop: movesTopEdge(handle),
                    movingBottom: movesBottomEdge(handle),
                    targets: context.targets,
                    thresholdX: context.thresholdX,
                    thresholdY: context.thresholdY
                )
                rect = snapped.rect
                show(snapped)
            }
            model.updateSlice(id: id, rect: rect)

        case .creatingGuide(let origin):
            let axis = guideAxis(from: origin, to: value.location)
            guard let axis else { return }
            let point = layout.normalizedPoint(value.location)
            let raw = axis == .vertical ? point.x : point.y
            draftGuide = SliceGuide(axis: axis, position: snappedGuidePosition(raw, axis: axis, layout: layout))

        case .creatingCrop(let origin):
            var rect = SliceGeometry.rect(
                from: origin,
                to: layout.normalizedPoint(value.location),
                square: shift,
                pixelAspect: source.pixelAspect
            )
            if !shift, let context = snapping(layout: layout, excluding: nil) {
                let snapped = SliceSnapping.snapEdges(
                    rect,
                    movingLeft: true, movingRight: true, movingTop: true, movingBottom: true,
                    targets: context.targets,
                    thresholdX: context.thresholdX,
                    thresholdY: context.thresholdY
                )
                rect = snapped.rect
                show(snapped)
            }
            guard SliceGeometry.isMeaningful(rect) else { return }
            model.setCrop(rect)

        case .movingCrop(let startRect):
            var rect = SliceGeometry.moved(startRect, by: layout.normalizedDelta(value.translation))
            if let context = snapping(layout: layout, excluding: nil) {
                let snapped = SliceSnapping.snapMoved(
                    rect,
                    targets: context.targets,
                    thresholdX: context.thresholdX,
                    thresholdY: context.thresholdY
                )
                rect = snapped.rect
                show(snapped)
            }
            model.setCrop(rect)

        case .resizingCrop(let handle):
            guard let cropRect = model.cropRect else { return }
            var rect = SliceGeometry.resized(
                cropRect,
                handle: handle,
                to: layout.normalizedPoint(value.location),
                square: shift,
                pixelAspect: source.pixelAspect
            )
            if !shift, let context = snapping(layout: layout, excluding: nil) {
                let snapped = SliceSnapping.snapEdges(
                    rect,
                    movingLeft: movesLeftEdge(handle),
                    movingRight: movesRightEdge(handle),
                    movingTop: movesTopEdge(handle),
                    movingBottom: movesBottomEdge(handle),
                    targets: context.targets,
                    thresholdX: context.thresholdX,
                    thresholdY: context.thresholdY
                )
                rect = snapped.rect
                show(snapped)
            }
            model.setCrop(rect)

        case .movingGuide(let id):
            guard let guide = model.guides.first(where: { $0.id == id }) else { return }
            let point = layout.normalizedPoint(value.location)
            let raw = guide.axis == .vertical ? point.x : point.y
            model.updateGuide(id: id, position: snappedGuidePosition(raw, axis: guide.axis, layout: layout))

        case nil:
            break
        }
    }

    private func finishOperation() {
        if case .creating = operation, let draftRect {
            model.addSlice(draftRect)
        }
        if case .creatingGuide = operation, let draftGuide {
            model.addGuide(axis: draftGuide.axis, at: draftGuide.position)
        }
        cancelActiveOperation()
    }

    /// `Escape` abandons whatever the pointer was doing.
    private func cancelActiveOperation() {
        draftRect = nil
        draftGuide = nil
        snapIndicator = SnapIndicator()
        operation = nil
    }

    /// A double-click on a slice opens its inspector. Locked slices answer
    /// too — the inspector is where a lock is undone.
    private func openInspector(at point: CGPoint, layout: SliceCanvasLayout) {
        guard layout.isUsable, model.activeTool != .crop else { return }
        guard let hit = model.slices.reversed().first(where: {
            layout.viewRect(for: $0.rect).contains(point)
        }) else { return }
        model.inspect(id: hit.id)
    }

    private func inspectorBinding(for slice: Slice) -> Binding<Bool> {
        Binding(
            get: { model.inspectingSliceID == slice.id },
            set: { isPresented in
                if !isPresented, model.inspectingSliceID == slice.id {
                    model.inspectingSliceID = nil
                }
            }
        )
    }

    private func pan(by delta: CGSize) {
        guard model.zoom > SlicerDocumentModel.minimumZoom else { return }
        model.panOffset = CGSize(
            width: model.panOffset.width + delta.width,
            height: model.panOffset.height + delta.height
        )
    }

    // MARK: - Snapping

    private struct SnapContext {
        let targets: SnapTargets
        let thresholdX: CGFloat
        let thresholdY: CGFloat
    }

    /// The snap targets and per-axis tolerances for the current frame, or
    /// `nil` when snapping is switched off.
    private func snapping(layout: SliceCanvasLayout, excluding id: Slice.ID?) -> SnapContext? {
        guard model.isSnappingEnabled, layout.isUsable else { return nil }
        return SnapContext(
            targets: SliceSnapping.targets(
                slices: model.slices,
                excluding: id,
                guides: model.guides,
                grid: model.grid,
                includeCentreLines: model.snapsToCentreLines
            ),
            // One on-screen tolerance becomes two normalised ones, because the
            // image is rarely square.
            thresholdX: Self.snapTolerance / layout.imageRect.width,
            thresholdY: Self.snapTolerance / layout.imageRect.height
        )
    }

    private func show(_ result: SnapResult) {
        snapIndicator = SnapIndicator(vertical: result.verticalLines, horizontal: result.horizontalLines)
    }

    private func snappedGuidePosition(
        _ position: CGFloat,
        axis: SliceGuide.Axis,
        layout: SliceCanvasLayout
    ) -> CGFloat {
        guard let context = snapping(layout: layout, excluding: nil) else { return position }
        return SliceSnapping.snapGuide(
            position,
            axis: axis,
            targets: context.targets,
            threshold: axis == .vertical ? context.thresholdX : context.thresholdY
        )
    }

    // MARK: - Hit testing

    private func guide(at point: CGPoint, layout: SliceCanvasLayout) -> SliceGuide? {
        model.guides.first { guide in
            let rect = layout.imageRect
            switch guide.axis {
            case .vertical:
                return abs(point.x - (rect.minX + guide.position * rect.width)) <= Self.guideTolerance
            case .horizontal:
                return abs(point.y - (rect.minY + guide.position * rect.height)) <= Self.guideTolerance
            }
        }
    }

    /// A mostly-sideways drag sweeps out a horizontal cut; a mostly-upright
    /// drag sweeps out a vertical one. Below the threshold the direction is
    /// still ambiguous, so no guide appears yet.
    private func guideAxis(from origin: CGPoint, to location: CGPoint) -> SliceGuide.Axis? {
        let dx = abs(location.x - origin.x)
        let dy = abs(location.y - origin.y)
        guard max(dx, dy) >= Self.guideAxisThreshold else { return nil }
        return dx >= dy ? .horizontal : .vertical
    }

    private func movesLeftEdge(_ handle: SliceHandle) -> Bool {
        handle == .topLeft || handle == .left || handle == .bottomLeft
    }

    private func movesRightEdge(_ handle: SliceHandle) -> Bool {
        handle == .topRight || handle == .right || handle == .bottomRight
    }

    private func movesTopEdge(_ handle: SliceHandle) -> Bool {
        handle == .topLeft || handle == .top || handle == .topRight
    }

    private func movesBottomEdge(_ handle: SliceHandle) -> Bool {
        handle == .bottomLeft || handle == .bottom || handle == .bottomRight
    }
}

/// One cutting line drawn across the image.
private struct GuideLine: View {
    let guide: SliceGuide
    let isSelected: Bool
    let imageRect: CGRect
    let pixelSize: CGSize

    private static let hitWidth: CGFloat = 11

    var body: some View {
        Rectangle()
            .fill(Color.cyan.opacity(isSelected ? 1 : 0.75))
            .frame(
                width: guide.axis == .vertical ? (isSelected ? 2 : 1) : imageRect.width,
                height: guide.axis == .vertical ? imageRect.height : (isSelected ? 2 : 1)
            )
            .frame(
                width: guide.axis == .vertical ? Self.hitWidth : imageRect.width,
                height: guide.axis == .vertical ? imageRect.height : Self.hitWidth
            )
            .contentShape(Rectangle())
            .position(x: centre.x, y: centre.y)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(guide.axis == .vertical ? "Vertical guide" : "Horizontal guide")
            .accessibilityValue(valueDescription)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var centre: CGPoint {
        switch guide.axis {
        case .vertical:
            CGPoint(x: imageRect.minX + guide.position * imageRect.width, y: imageRect.midY)
        case .horizontal:
            CGPoint(x: imageRect.midX, y: imageRect.minY + guide.position * imageRect.height)
        }
    }

    private var valueDescription: String {
        let pixels = guide.axis == .vertical
            ? guide.position * pixelSize.width
            : guide.position * pixelSize.height
        return "\(Int(pixels.rounded())) pixels"
    }
}

/// Trackpad scroll and pinch, and the double-click that opens a slice's
/// inspector — none of which SwiftUI surfaces on macOS. The view only supplies
/// a frame to convert against; the events arrive through a local monitor, so
/// the canvas keeps its own drag gesture.
private struct CanvasPointerEvents: NSViewRepresentable {
    let onScroll: (CGSize) -> Void
    let onMagnify: (CGFloat) -> Void
    /// The click location in the canvas's own coordinates.
    let onDoubleClick: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScroll: onScroll, onMagnify: onMagnify, onDoubleClick: onDoubleClick)
    }

    func makeNSView(context: Context) -> FlippedView {
        let view = FlippedView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: FlippedView, context: Context) {
        context.coordinator.onScroll = onScroll
        context.coordinator.onMagnify = onMagnify
        context.coordinator.onDoubleClick = onDoubleClick
        context.coordinator.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: FlippedView, coordinator: Coordinator) {
        coordinator.stop()
    }

    /// Flipped so a converted point matches SwiftUI's top-left origin, and the
    /// same coordinates the layout hands out can be used for hit testing.
    final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }

    final class Coordinator {
        var onScroll: (CGSize) -> Void
        var onMagnify: (CGFloat) -> Void
        var onDoubleClick: (CGPoint) -> Void
        private weak var view: NSView?
        private var monitor: Any?

        init(
            onScroll: @escaping (CGSize) -> Void,
            onMagnify: @escaping (CGFloat) -> Void,
            onDoubleClick: @escaping (CGPoint) -> Void
        ) {
            self.onScroll = onScroll
            self.onMagnify = onMagnify
            self.onDoubleClick = onDoubleClick
        }

        func attach(to view: NSView) {
            self.view = view
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.scrollWheel, .magnify, .leftMouseDown]
            ) { [weak self] event in
                guard let self, let view = self.view, event.window === view.window else { return event }
                let location = view.convert(event.locationInWindow, from: nil)
                guard view.bounds.contains(location) else { return event }

                switch event.type {
                case .scrollWheel:
                    guard event.phase != .cancelled else { return event }
                    self.onScroll(CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY))
                case .magnify:
                    self.onMagnify(event.magnification)
                case .leftMouseDown:
                    // Pass the event on regardless: the drag gesture still owns
                    // selection, and swallowing the second click of a
                    // double-click would strand it mid-drag.
                    if event.clickCount == 2 { self.onDoubleClick(location) }
                default:
                    break
                }
                return event
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            stop()
        }
    }
}

/// `Escape` and `Delete`/`Backspace` while the Slicer window is key.
///
/// A monitor rather than `onKeyPress` so cancelling a drag or deleting the
/// selected slice never depends on which view holds focus — clicking a slice
/// on the canvas gives focus to nothing in particular. Text editing wins:
/// while a field is first responder, Backspace is left alone.
private struct CanvasKeyMonitor: NSViewRepresentable {
    let onEscape: () -> Void
    /// Returns `true` when it consumed the key.
    let onDelete: () -> Bool

    private enum Key {
        static let escape: UInt16 = 53
        static let delete: UInt16 = 51
        static let forwardDelete: UInt16 = 117
    }

    func makeCoordinator() -> Coordinator { Coordinator(onEscape: onEscape, onDelete: onDelete) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onEscape = onEscape
        context.coordinator.onDelete = onDelete
        context.coordinator.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var onEscape: () -> Void
        var onDelete: () -> Bool
        private weak var view: NSView?
        private var monitor: Any?

        init(onEscape: @escaping () -> Void, onDelete: @escaping () -> Bool) {
            self.onEscape = onEscape
            self.onDelete = onDelete
        }

        func attach(to view: NSView) {
            self.view = view
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let view = self.view, event.window === view.window else { return event }

                switch event.keyCode {
                case Key.escape:
                    self.onEscape()
                    return nil
                case Key.delete, Key.forwardDelete:
                    guard !self.isEditingText(in: event.window) else { return event }
                    return self.onDelete() ? nil : event
                default:
                    return event
                }
            }
        }

        /// True while a text field or text view has focus, so typing in the
        /// template-name field never eats a slice.
        private func isEditingText(in window: NSWindow?) -> Bool {
            let responder = window?.firstResponder
            if responder is NSTextView || responder is NSTextField { return true }
            if let responder = responder as? NSView, responder.superview is NSTextField { return true }
            return false
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit { stop() }
    }
}
