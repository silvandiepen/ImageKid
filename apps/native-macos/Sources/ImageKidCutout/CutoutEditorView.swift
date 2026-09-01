import AppKit
import CoreGraphics
import SwiftUI

@MainActor
final class CutoutEditorState: ObservableObject {
    enum Stage: Equatable {
        case loading
        case ready
        case working(String)
        case failed(String)
    }

    @Published private(set) var stage: Stage = .loading
    @Published private(set) var sourceImage: NSImage?
    @Published private(set) var previewImage: NSImage?
    @Published private(set) var hasCutout = false
    @Published private(set) var canUndo = false
    @Published private(set) var isEdited = false
    @Published var tool: CutoutMask.Tool = .erase
    @Published var brushDiameter: Double = 64
    @Published var brushHardness: Double = 0.85
    @Published var strokeMode: CutoutMask.StrokeMode = .brush
    @Published var similarity: Double = 0.2
    @Published private(set) var hasModelMask = false
    /// True when the mask came from a live engine run rather than a cutout already on
    /// disk, which is the only case where the strength dial has the full mask to work on.
    @Published private(set) var isFreshFromModel = false
    @Published var strength: Double = 0.5 {
        didSet {
            guard strength != oldValue else { return }
            mask?.setStrength(strength)
            refreshPreview()
        }
    }

    private var mask: CutoutMask?
    private var isStroking = false

    var pixelSize: CGSize {
        mask?.pixelSize ?? .zero
    }

    func load(_ item: BatchItem) {
        stage = .loading
        do {
            let source = try CompanionImageIO.loadImage(at: item.sourceURL)
            sourceImage = NSImage(cgImage: source, size: NSSize(width: source.width, height: source.height))

            var cutout: CGImage?
            if let existing = item.outputURL ?? item.plannedOutputURL,
               existing != item.sourceURL,
               FileManager.default.fileExists(atPath: existing.path) {
                cutout = try? CompanionImageIO.loadImage(at: existing)
            }

            guard let mask = CutoutMask(source: source, cutout: cutout, strength: strength) else {
                stage = .failed("This image could not be opened for editing.")
                return
            }
            self.mask = mask
            hasCutout = cutout != nil
            hasModelMask = mask.hasModelMask
            isFreshFromModel = false
            isEdited = false
            refreshPreview()
            stage = .ready
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    /// Runs the app's current cutout engine for this one image, so an unprocessed
    /// image can be corrected without going through the queue first.
    func removeBackground(using remove: @escaping (CGImage, Double) async throws -> CGImage) async {
        guard let source = mask?.source else { return }
        stage = .working("Removing the background")
        do {
            let cutout = try await remove(source, strength)
            mask = CutoutMask(source: source, cutout: cutout, strength: strength)
            hasCutout = true
            hasModelMask = true
            isFreshFromModel = true
            isEdited = true
            refreshPreview()
            stage = .ready
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    /// - Parameter continuingLine: a shift-click, which runs a straight stroke from where
    ///   the last one ended to here rather than starting fresh under the cursor.
    func paint(to point: CGPoint, continuingLine: Bool = false) {
        guard let mask, hasCutout else { return }
        if !isStroking {
            mask.beginStroke(
                diameter: brushDiameter,
                hardness: brushHardness,
                tool: tool,
                mode: strokeMode,
                tolerance: similarity
            )
            isStroking = true
            if continuingLine, let anchor = mask.lastStrokeEnd {
                mask.paint(to: anchor)
            }
        }
        mask.paint(to: point)
        isEdited = true
        refreshPreview()
    }

    var canContinueLine: Bool {
        mask?.lastStrokeEnd != nil
    }

    func endStroke() {
        guard isStroking else { return }
        mask?.endStroke()
        isStroking = false
        canUndo = mask?.canUndo ?? false
        refreshPreview()
    }

    func undo() {
        mask?.undo()
        canUndo = mask?.canUndo ?? false
        refreshPreview()
    }

    func save(to url: URL) -> Bool {
        guard let image = mask?.render() else { return false }
        do {
            try CompanionImageIO.prepareDirectory(for: url)
            try CompanionImageIO.writePNG(image, to: url)
            return true
        } catch {
            stage = .failed(error.localizedDescription)
            return false
        }
    }

    private func refreshPreview() {
        guard let image = mask?.render() else { return }
        previewImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}


struct CutoutEditorView: View {
    enum CompareMode: String, CaseIterable, Identifiable {
        case cutout
        case split
        case original

        var id: String { rawValue }

        var label: String {
            switch self {
            case .cutout: "Cutout"
            case .split: "Compare"
            case .original: "Original"
            }
        }
    }

    let item: BatchItem
    @Binding var engine: CompanionBatchModel.CutoutEngine
    let removeBackground: (CGImage, Double) async throws -> CGImage
    let onSaved: (URL) -> Void

    @StateObject private var state = CutoutEditorState()
    @State private var mode = CompareMode.cutout
    @State private var splitFraction = 0.5
    @State private var originalOpacity = 0.0
    @State private var hoverPoint: CGPoint?
    @State private var zoom: CGFloat = 1
    @State private var zoomAtGestureStart: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panAtGestureStart: CGSize = .zero
    @State private var canvasSize: CGSize = .zero
    @Environment(\.dismiss) private var dismiss

    private static let maximumZoom: CGFloat = 12

    /// The original is shown on a flat backdrop rather than the checkerboard: an input
    /// that is already transparent would otherwise look identical to its own cutout.
    private let originalBackdrop = Color(white: 0.16)

    private var destinationURL: URL? {
        item.outputURL ?? item.plannedOutputURL
    }

    private var destinationExists: Bool {
        guard let destinationURL else { return false }
        return FileManager.default.fileExists(atPath: destinationURL.path)
    }

    private var canPaint: Bool {
        mode == .cutout && state.hasCutout
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                rail
                canvas
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .frame(minWidth: 980, idealWidth: 1240, minHeight: 700, idealHeight: 880)
        .background {
            VisualEffectBackground()
                .overlay(Color.black.opacity(0.32))
                .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .onAppear { state.load(item) }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName)
                    .font(.headline)
                Text(item.sizeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("View", selection: $mode) {
                ForEach(CompareMode.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    /// The controls live in a rail, the way they do in the main window, so the image
    /// gets the room instead of a crowded strip under it.
    private var rail: some View {
        ScrollView(.vertical) {
            railContent
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
        }
        .frame(width: 250)
        .background(Color.white.opacity(0.03))
    }

    private var railContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !state.hasCutout, state.stage == .ready {
                notProcessedNotice
            }

            // Three questions: how it was cut, what the brush does, what you are looking
            // at. Every explanation that was a paragraph is a tooltip now.
            section("Cut") {
                Picker("Method", selection: $engine) {
                    ForEach(CompanionBatchModel.CutoutEngine.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .labelsHidden()
                .help(engine.explanation)

                LabeledSlider(
                    title: "Strength",
                    reading: strengthReading,
                    value: $state.strength
                )
                .disabled(!state.hasModelMask)
                .help(strengthExplanation)

                if !state.isFreshFromModel, state.hasCutout {
                    Text("Already cut, so the dial only has what survived. Cut again for the full mask.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task { await state.removeBackground(using: removeBackground) }
                } label: {
                    Text(state.hasCutout ? "Cut Again at This Strength" : "Remove Background")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(state.stage != .ready)
            }

            section("Brush") {
                Picker("Tool", selection: $state.tool) {
                    Text("Remove").tag(CutoutMask.Tool.erase)
                    Text("Add Back").tag(CutoutMask.Tool.restore)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(!canPaint)
                .help("Whether a stroke takes the image away or brings it back.")

                Picker("Reach", selection: $state.strokeMode) {
                    Text("Brush").tag(CutoutMask.StrokeMode.brush)
                    Text("Region").tag(CutoutMask.StrokeMode.region)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(!canPaint)
                .help(reachExplanation)

                Text(reachExplanation)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                LabeledSlider(
                    title: "Size",
                    reading: "\(Int(state.brushDiameter)) px",
                    value: $state.brushDiameter,
                    range: 8...400
                )

                if state.strokeMode == .region {
                    LabeledSlider(
                        title: "Similarity",
                        reading: "\(Int(state.similarity * 100))%",
                        value: $state.similarity,
                        range: 0.02...0.6
                    )
                } else {
                    LabeledSlider(
                        title: "Soft edge",
                        reading: "\(Int((1 - state.brushHardness) * 100))%",
                        value: $state.brushHardness
                    )
                }
            }
            .disabled(!canPaint)

            section("View") {
                LabeledSlider(
                    title: "Show original",
                    reading: "\(Int(originalOpacity * 100))%",
                    value: $originalOpacity
                )
                .disabled(mode != .cutout)
                .help("Ghosts the input under the cutout so you can see what was removed.")
            }

            Button {
                state.undo()
            } label: {
                Label("Undo Stroke", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!state.canUndo)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notProcessedNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Not cut out yet")
                .font(.subheadline.weight(.semibold))
            Text("You are looking at the input. Remove the background to start correcting it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await state.removeBackground(using: removeBackground) }
            } label: {
                Text("Remove Background").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    /// An already-saved cutout has had its background deleted outright, so the dial can
    /// only lift what survived as a soft edge. Re-cutting gives it the model's full mask.
    private var strengthExplanation: String {
        if engine == .flatBackground {
            return "How far a colour may sit from the backdrop and still count as backdrop. Cut again to apply it."
        }
        if !state.isFreshFromModel {
            return "This file was already cut, so the dial can only work with what survived. Cut again to give it the model's full mask."
        }
        return "Lifts edges the model left part-transparent. It cannot bring back anything the "
            + "model removed outright \u{2014} switch method for that."
    }

    private var reachExplanation: String {
        let verb = state.tool == .erase ? "removed" : "added back"
        switch state.strokeMode {
        case .brush:
            return "Exactly what the brush covers is \(verb). Shift-click to run a straight line from the last stroke."
        case .region:
            return "Scribble roughly inside an area and the whole region it belongs to is \(verb)."
        }
    }

    private var strengthReading: String {
        let percent = Int((state.strength * 100).rounded())
        return percent == 50 ? "50% (as cut)" : "\(percent)%"
    }

    private func reading(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            Text(value).monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer()
            Button("Close") { dismiss() }
            Button(destinationExists ? "Overwrite Cutout" : "Save Cutout") {
                guard let destinationURL, state.save(to: destinationURL) else { return }
                onSaved(destinationURL)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!state.hasCutout || destinationURL == nil)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Canvas

    @ViewBuilder private var canvas: some View {
        GeometryReader { geometry in
            let rect = displayRect(in: geometry.size)
            ZStack(alignment: .topLeading) {
                Color.clear

                switch state.stage {
                case .loading:
                    centered { ProgressView() }
                case .failed(let message):
                    centered {
                        Text(message)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(40)
                    }
                case .working(let detail):
                    centered {
                        VStack(spacing: 10) {
                            ProgressView()
                            Text(detail).foregroundStyle(.secondary)
                        }
                    }
                case .ready:
                    imageStack(in: rect)
                        .frame(width: rect.width, height: rect.height)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .offset(x: rect.minX, y: rect.minY)

                    if mode == .split {
                        splitHandle(in: rect)
                        splitLabels(in: rect)
                    }
                    if canPaint, let hoverPoint, rect.contains(hoverPoint) {
                        brushCursor(at: hoverPoint, in: rect)
                    }
                }
            }
            // topLeading, not the default centre: once zoomed the image is wider than
            // the canvas, and a centring frame shifts everything drawn inside the stack
            // while the pointer's coordinates stay put — which is what pulled the brush
            // away from its cursor.
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let point): hoverPoint = point
                case .ended: hoverPoint = nil
                }
            }
            .highPriorityGesture(panGesture)
            .gesture(canvasGesture(in: rect))
            .overlay(alignment: .bottomTrailing) { zoomControls }
            .overlay {
                TrackpadInput(
                    onScroll: { delta, modifiers in handleScroll(delta, modifiers: modifiers) },
                    onMagnify: { magnification, point in
                        setZoom(zoom * (1 + magnification), around: point)
                    }
                )
                .allowsHitTesting(false)
            }
            .onAppear { canvasSize = geometry.size }
            .onChange(of: geometry.size) { _, newSize in canvasSize = newSize }
        }
        .padding(20)
    }

    @ViewBuilder private func centered<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack { Spacer(); VStack { Spacer(); content(); Spacer() }; Spacer() }
    }

    @ViewBuilder private func imageStack(in rect: CGRect) -> some View {
        switch mode {
        case .cutout:
            ZStack {
                CheckerboardBackground(square: 10)
                if let source = state.sourceImage, originalOpacity > 0 {
                    Image(nsImage: source)
                        .resizable()
                        .opacity(originalOpacity)
                }
                if let preview = state.previewImage {
                    Image(nsImage: preview).resizable()
                }
            }

        case .original:
            ZStack {
                originalBackdrop
                if let source = state.sourceImage {
                    Image(nsImage: source).resizable()
                }
            }

        case .split:
            ZStack {
                ZStack {
                    originalBackdrop
                    if let source = state.sourceImage {
                        Image(nsImage: source).resizable()
                    }
                }
                .mask(alignment: .leading) {
                    Rectangle().frame(width: rect.width * splitFraction)
                }

                ZStack {
                    CheckerboardBackground(square: 10)
                    if let preview = state.previewImage {
                        Image(nsImage: preview).resizable()
                    }
                }
                .mask(alignment: .trailing) {
                    Rectangle().frame(width: rect.width * (1 - splitFraction))
                }
            }
        }
    }

    private func splitHandle(in rect: CGRect) -> some View {
        Rectangle()
            .fill(.white.opacity(0.85))
            .frame(width: 2, height: rect.height)
            .overlay {
                Circle()
                    .fill(.white.opacity(0.85))
                    .frame(width: 20, height: 20)
                    .overlay {
                        Image(systemName: "arrow.left.and.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.black.opacity(0.7))
                    }
            }
            .offset(x: rect.minX + rect.width * splitFraction - 1, y: rect.minY)
            .allowsHitTesting(false)
    }

    private func splitLabels(in rect: CGRect) -> some View {
        HStack {
            Text("Original").padding(.leading, 10)
            Spacer()
            Text("Cutout").padding(.trailing, 10)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.white.opacity(0.75))
        .shadow(radius: 2)
        .frame(width: rect.width)
        .offset(x: rect.minX, y: rect.maxY - 22)
        .allowsHitTesting(false)
    }

    /// The brush is shown at its real size, at the pointer, so what you see is what
    /// the stroke will cover.
    private func brushCursor(at point: CGPoint, in rect: CGRect) -> some View {
        let diameter = state.brushDiameter * displayScale(in: rect)
        return ZStack {
            Circle().strokeBorder(.black.opacity(0.55), lineWidth: 2)
            Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1)
        }
        .frame(width: diameter, height: diameter)
        .position(point)
        .allowsHitTesting(false)
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button { setZoom(zoom / 1.5) } label: { Image(systemName: "minus") }
                .disabled(zoom <= 1.01)
            Text("\(Int(zoom * 100))%")
                .font(.caption.monospacedDigit())
                .frame(width: 46)
            Button { setZoom(zoom * 1.5) } label: { Image(systemName: "plus") }
                .disabled(zoom >= Self.maximumZoom - 0.01)
            Button("Fit") { setZoom(1) }
                .disabled(zoom <= 1.01 && pan == .zero)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .padding(12)
        .help("Pinch or Command-scroll to zoom, two fingers to pan")
    }

    // MARK: - Geometry

    /// Where the image sits once fitted into the canvas — the same maths the brush,
    /// the divider and the zoom all read, so they can never disagree.
    private func displayRect(in size: CGSize) -> CGRect {
        let pixels = state.pixelSize
        guard pixels.width > 0, pixels.height > 0 else {
            return CGRect(origin: .zero, size: size)
        }
        let fit = min(size.width / pixels.width, size.height / pixels.height)
        let width = pixels.width * fit * zoom
        let height = pixels.height * fit * zoom
        return CGRect(
            x: (size.width - width) / 2 + pan.width,
            y: (size.height - height) / 2 + pan.height,
            width: width,
            height: height
        )
    }

    private func displayScale(in rect: CGRect) -> CGFloat {
        guard state.pixelSize.width > 0 else { return 1 }
        return rect.width / state.pixelSize.width
    }

    private func setZoom(_ value: CGFloat, around anchor: CGPoint? = nil) {
        let previous = displayRect(in: canvasSize)
        let newZoom = min(Self.maximumZoom, max(1, value))

        if let anchor, previous.width > 0, previous.height > 0, newZoom > 1 {
            // Keep whatever sits under the pointer pinned there.
            let unit = CGPoint(
                x: (anchor.x - previous.minX) / previous.width,
                y: (anchor.y - previous.minY) / previous.height
            )
            let ratio = newZoom / zoom
            let size = CGSize(width: previous.width * ratio, height: previous.height * ratio)
            zoom = newZoom
            pan = CGSize(
                width: anchor.x - unit.x * size.width - (canvasSize.width - size.width) / 2,
                height: anchor.y - unit.y * size.height - (canvasSize.height - size.height) / 2
            )
        } else {
            zoom = newZoom
        }

        if zoom <= 1.01 {
            zoom = 1
            pan = .zero
        }
        clampPan()

        // Keep the gesture baselines in step, or the next pinch or pan jumps.
        zoomAtGestureStart = zoom
        panAtGestureStart = pan
    }

    /// Panning stops at the edges, so a zoomed-in image can never be pushed out of
    /// view and lost.
    private func clampPan() {
        let rect = displayRect(in: canvasSize)
        let limitX = max(0, (rect.width - canvasSize.width) / 2)
        let limitY = max(0, (rect.height - canvasSize.height) / 2)
        pan = CGSize(
            width: min(limitX, max(-limitX, pan.width)),
            height: min(limitY, max(-limitY, pan.height))
        )
    }

    /// Two fingers pan; pinch or Command-scroll zooms. That is what these gestures do
    /// everywhere else on the platform.
    private func handleScroll(_ delta: CGSize, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            setZoom(zoom * (1 + delta.height * 0.01), around: hoverPoint)
            return
        }
        pan = CGSize(width: pan.width + delta.width, height: pan.height + delta.height)
        clampPan()
        panAtGestureStart = pan
    }

    // MARK: - Gestures

    /// One gesture for the whole canvas: in Cutout it paints, in Compare it moves the
    /// divider. Two competing drag gestures is what stopped the divider moving at all.
    private func canvasGesture(in rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard rect.width > 0 else { return }
                hoverPoint = value.location
                switch mode {
                case .cutout:
                    guard state.hasCutout else { return }
                    let scale = state.pixelSize.width / rect.width
                    let point = CGPoint(
                        x: (value.location.x - rect.minX) * scale,
                        y: (value.location.y - rect.minY) * scale
                    )
                    // Read the live modifier rather than a gesture modifier, so the same
                    // drag can start as a shift-click and carry on as a normal stroke.
                    let straight = NSEvent.modifierFlags.contains(.shift)
                    state.paint(to: point, continuingLine: straight)
                case .split:
                    splitFraction = min(1, max(0, (value.location.x - rect.minX) / rect.width))
                case .original:
                    break
                }
            }
            .onEnded { _ in state.endStroke() }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .modifiers(.option)
            .onChanged { value in
                pan = CGSize(
                    width: panAtGestureStart.width + value.translation.width,
                    height: panAtGestureStart.height + value.translation.height
                )
                clampPan()
            }
            .onEnded { _ in panAtGestureStart = pan }
    }
}
