import Foundation
import ImageKidCore
import AppKit
import SwiftUI
import AVFoundation
import AVKit
import CoreGraphics

public enum Tool: String, CaseIterable, Identifiable {
    case view
    case select
    case pickColor
    case crop
    case resize
    case rotate
    case refineBackground
    case draw
    case text

    public var id: String { rawValue }

    var label: String {
        switch self {
        case .view: "View"
        case .select: "Select"
        case .pickColor: "Pick"
        case .crop: "Crop"
        case .resize: "Resize"
        case .rotate: "Rotate"
        case .refineBackground: "Refine"
        case .draw: "Draw"
        case .text: "Text"
        }
    }

    var symbolName: String {
        switch self {
        case .view: "hand.draw"
        case .select: "cursorarrow"
        case .pickColor: "eyedropper"
        case .crop: "crop"
        case .resize: "arrow.up.left.and.arrow.down.right"
        case .rotate: "rotate.right"
        case .refineBackground: "paintbrush.pointed"
        case .draw: "pencil.tip.crop.circle"
        case .text: "textformat"
        }
    }

    var menuShortcutKey: KeyEquivalent {
        switch self {
        case .view: "v"
        case .select: "s"
        case .pickColor: "p"
        case .crop: "c"
        case .resize: "r"
        case .rotate: "r"
        case .refineBackground: "b"
        case .draw: "d"
        case .text: "t"
        }
    }

    var menuShortcutModifiers: EventModifiers {
        [.command, .option]
    }
}

enum MaskViewMode: String, CaseIterable, Identifiable {
    case overlay
    case blackWhite

    var id: String { rawValue }
    var label: String {
        switch self {
        case .overlay: "Overlay"
        case .blackWhite: "Black & White"
        }
    }
}

enum BackgroundRefinementMode: String, CaseIterable, Identifiable {
    case keep
    case remove

    var id: String { rawValue }

    var label: String {
        switch self {
        case .keep: "Keep"
        case .remove: "Remove"
        }
    }
}

enum ViewportMode: String, CaseIterable, Identifiable {
    case contain
    case cover
    case original

    var id: String { rawValue }

    var label: String {
        switch self {
        case .contain: "Contain"
        case .cover: "Cover"
        case .original: "Original"
        }
    }
}

enum CropAspectRatio: String, CaseIterable, Identifiable {
    case free
    case original
    case square
    case fourThree
    case threeTwo
    case sixteenNine

    var id: String { rawValue }

    var label: String {
        switch self {
        case .free: "Free"
        case .original: "Original"
        case .square: "1:1"
        case .fourThree: "4:3"
        case .threeTwo: "3:2"
        case .sixteenNine: "16:9"
        }
    }

    func ratio(for imageSize: CGSize) -> CGFloat? {
        switch self {
        case .free: nil
        case .original: imageSize.width / max(imageSize.height, 1)
        case .square: 1
        case .fourThree: 4 / 3
        case .threeTwo: 3 / 2
        case .sixteenNine: 16 / 9
        }
    }
}

// MARK: - AppKit rendering conveniences for the shared model

extension AnnotationFontWeight {
    var appKitWeight: NSFont.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}

extension AnnotationTextAlignment {
    var paragraphAlignment: NSTextAlignment {
        switch self {
        case .leading: .left
        case .center: .center
        case .trailing: .right
        }
    }
}

extension ImageLayer {
    /// The image as it should render — masked when a mask is present and enabled.
    var renderedImage: NSImage {
        guard isMaskEnabled, let mask else { return image }
        return MaskCompositor.apply(mask: mask, to: image) ?? image
    }
}

@MainActor
final class ImageSession: ObservableObject {
    let sourceURL: URL?
    let sourceImage: NSImage

    /// URL of the saved .imagekid work file, if this session was opened from or
    /// saved to one.
    @Published var documentURL: URL?

    @Published var zoom: CGFloat = 1
    @Published var pan: CGSize = .zero
    @Published var viewportMode: ViewportMode = .contain
    @Published var cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    @Published var draftCropRect: CGRect?
    @Published var cropAspectRatio: CropAspectRatio = .free
    /// When on, applying a crop deletes layers/annotations left fully outside it
    /// (rather than keeping them off-canvas).
    @Published var cropTrimsOutsideContent = false
    @Published var outputSize: CGSize?
    @Published var draftOutputSize: CGSize?
    @Published var resizePreservesAspect = true
    @Published var annotations: [Annotation] = []
    @Published var imageLayers: [ImageLayer] = []
    @Published var layerGroups: [LayerGroup] = []
    /// When true the base image has been promoted to a normal (movable/rotatable)
    /// layer and the canvas base is transparent.
    @Published var baseUnlocked = false
    @Published var selectedAnnotationID: UUID?
    @Published var selectedLayerID: UUID?
    @Published var selectedLayerIDs: Set<UUID> = []

    // Mask editing (for the selected image layer's mask).
    @Published var maskEditLayerID: UUID?
    @Published var maskViewMode: MaskViewMode = .blackWhite
    /// How strongly the black/white mask is shown over the layer while editing
    /// (1 = solid B/W, 0 = just the image).
    @Published var maskViewOpacity: Double = 1
    @Published var maskBrushReveal = false
    @Published var maskBrushSize: CGFloat = 48
    @Published var maskBrushSoftness: CGFloat = 0.4
    /// Distance between dabs along a stroke as a fraction of the brush diameter
    /// (0.02 = dense/smooth, 1.0 = widely spaced dabs).
    @Published var maskBrushSpacing: CGFloat = 0.15
    @Published var maskBrushOpacity: Double = 1
    /// Brush height as a fraction of its width (1 = circle, <1 = ellipse).
    @Published var maskBrushRoundness: CGFloat = 1
    /// Brush rotation in degrees (only visible when roundness < 1).
    @Published var maskBrushAngle: Double = 0
    @Published var maskWandMode = false
    @Published var maskWandTolerance: CGFloat = 0.15

    var isEditingMask: Bool { maskEditLayerID != nil }
    var maskEditLayer: ImageLayer? {
        guard let id = maskEditLayerID else { return nil }
        return imageLayers.first(where: { $0.id == id })
    }
    @Published var selectionRect: CGRect?
    @Published var sampledColors: [SampledColor] = []
    @Published var selectedColorIDs: Set<UUID> = []
    @Published var liveSampleColor: NSColor?
    @Published var liveSampleLocation: CGPoint?
    @Published var drawingMode: DrawingMode = .rectangle
    @Published var drawingStrokeColor: NSColor = .systemRed
    @Published var drawingFillColor: NSColor?
    @Published var drawingLineWidth: CGFloat = 4
    @Published var drawingStrokeStyle: ShapeStrokeStyle = .solid
    @Published var drawingStrokeAlignment: StrokeAlignment = .center
    @Published var drawingCornerRadius: CGFloat = 0
    @Published var drawingDashLength: CGFloat = 0
    @Published var drawingDashGap: CGFloat = 0
    @Published var drawingDashOffset: CGFloat = 0
    @Published var drawingBlendMode: ShapeBlendMode = .normal
    @Published var drawingOpacity: Double = 1
    /// Freehand brush smoothing (0 = raw, 1 = heavily smoothed sampling).
    @Published var drawingSmoothing: Double = 0.3
    @Published var backgroundRemovedImage: NSImage?
    @Published var backgroundRefinementUndoImage: NSImage?
    @Published var backgroundRefinementMode: BackgroundRefinementMode = .remove
    @Published var backgroundBrushSize: CGFloat = 36
    @Published var backgroundBrushSoftness: CGFloat = 0.45
    @Published var backgroundBrushStrength: CGFloat = 1

    // Rotate tool — draft state; applied by baking a rotated image.
    @Published var rotationDraft: Double = 0            // degrees, clockwise
    @Published var rotationFlipHorizontal = false
    @Published var rotationFlipVertical = false
    @Published var rotationResizesCanvas = true
    @Published var rotationFillsGaps = false
    @Published var rotationFillColor: NSColor = .white

    @Published var isDirty = false

    // Grid overlay + snapping.
    @Published var showGrid = false
    @Published var snapToGrid = false
    @Published var gridSizePx: CGFloat = 64
    /// Grid line colour (hex). A mid grey so it reads on both light and dark canvases.
    @Published var gridColorHex: String = "#808080"
    /// Grid line opacity, 0…1.
    @Published var gridOpacity: Double = 0.5
    /// Number of finer subdivisions drawn between the main grid lines (1 = none).
    @Published var gridSubdivisions: Int = 1
    /// Whether the floating Grid settings panel is showing.
    @Published var showGridPanel = false

    var gridColor: NSColor { ColorHex.color(from: gridColorHex) ?? .white }

    /// Snap a normalised source-space frame to the grid.
    /// - Parameter keepSize: snap only the origin (moves); otherwise snap all edges (resizes).
    func gridSnapped(_ frame: CGRect, keepSize: Bool = true) -> CGRect {
        guard snapToGrid, gridSizePx > 0 else { return frame }
        let px = pixelSize
        let gx = gridSizePx / max(px.width, 1)
        let gy = gridSizePx / max(px.height, 1)
        let minX = (frame.minX / gx).rounded() * gx
        let minY = (frame.minY / gy).rounded() * gy
        if keepSize {
            return CGRect(x: minX, y: minY, width: frame.width, height: frame.height)
        }
        let maxX = (frame.maxX / gx).rounded() * gx
        let maxY = (frame.maxY / gy).rounded() * gy
        return CGRect(x: minX, y: minY, width: max(maxX - minX, gx), height: max(maxY - minY, gy))
    }

    /// Snap a rect expressed in normalised display space (0…1 over the displayed
    /// image) to the visible grid. Used for the selection and crop regions so
    /// they line up with the same grid lines shown on the canvas.
    /// - Parameter keepSize: snap only the origin (for moves); otherwise snap all edges.
    func gridSnappedDisplayNormalized(_ rect: CGRect, keepSize: Bool = false) -> CGRect {
        guard snapToGrid, gridSizePx > 0 else { return rect }
        let px = effectivePixelSize
        let sx = gridSizePx / max(px.width, 1)
        let sy = gridSizePx / max(px.height, 1)
        guard sx > 0, sy > 0 else { return rect }
        let minX = (rect.minX / sx).rounded() * sx
        let minY = (rect.minY / sy).rounded() * sy
        if keepSize {
            return CGRect(x: minX, y: minY, width: rect.width, height: rect.height)
        }
        let maxX = (rect.maxX / sx).rounded() * sx
        let maxY = (rect.maxY / sy).rounded() * sy
        return CGRect(x: minX, y: minY, width: max(maxX - minX, sx), height: max(maxY - minY, sy))
    }

    // MARK: - Undo / Redo

    /// Snapshot of the reversible edit intent. View state (zoom/pan/viewport) and
    /// transient selection are intentionally excluded so undo maps to real edits.
    struct EditSnapshot {
        var cropRect: CGRect
        var cropAspectRatio: CropAspectRatio
        var outputSize: CGSize?
        var resizePreservesAspect: Bool
        var annotations: [Annotation]
        var imageLayers: [ImageLayer]
        var layerGroups: [LayerGroup]
        var selectedAnnotationID: UUID?
        var selectedLayerID: UUID?
        var sampledColors: [SampledColor]
        var selectedColorIDs: Set<UUID>
        var backgroundRemovedImage: NSImage?
        var baseUnlocked: Bool
    }

    struct HistoryEntry: Identifiable {
        let id = UUID()
        let name: String
        let systemImage: String
        let snapshot: EditSnapshot
    }

    /// Linear, named history timeline. `historyIndex` points at the current state.
    /// Entry 0 is always the opened image. Steps after `historyIndex` are redoable.
    @Published private(set) var history: [HistoryEntry] = []
    @Published private(set) var historyIndex = 0
    private var isRestoringHistory = false
    private let historyLimit = 200

    var canUndo: Bool { historyIndex > 0 }
    var canRedo: Bool { historyIndex < history.count - 1 }

    private func currentSnapshot() -> EditSnapshot {
        EditSnapshot(
            cropRect: cropRect,
            cropAspectRatio: cropAspectRatio,
            outputSize: outputSize,
            resizePreservesAspect: resizePreservesAspect,
            annotations: annotations,
            imageLayers: imageLayers,
            layerGroups: layerGroups,
            selectedAnnotationID: selectedAnnotationID,
            selectedLayerID: selectedLayerID,
            sampledColors: sampledColors,
            selectedColorIDs: selectedColorIDs,
            backgroundRemovedImage: backgroundRemovedImage,
            baseUnlocked: baseUnlocked
        )
    }

    private func restore(_ snapshot: EditSnapshot) {
        cropRect = snapshot.cropRect
        cropAspectRatio = snapshot.cropAspectRatio
        outputSize = snapshot.outputSize
        resizePreservesAspect = snapshot.resizePreservesAspect
        annotations = snapshot.annotations
        imageLayers = snapshot.imageLayers
        layerGroups = snapshot.layerGroups
        selectedAnnotationID = snapshot.selectedAnnotationID
        selectedLayerID = snapshot.selectedLayerID
        sampledColors = snapshot.sampledColors
        selectedColorIDs = snapshot.selectedColorIDs
        backgroundRemovedImage = snapshot.backgroundRemovedImage
        baseUnlocked = snapshot.baseUnlocked
    }

    // MARK: - Unified layer stack (image layers + annotations share a z order)

    /// z value for a brand-new item so it lands on top of everything.
    var nextStackZ: Double {
        ((imageLayers.map(\.z) + annotations.map(\.z)).max() ?? 0) + 1
    }

    /// Lowest z in the stack (used to place an unlocked background at the bottom).
    var minStackZ: Double {
        (imageLayers.map(\.z) + annotations.map(\.z)).min() ?? 0
    }

    /// Image layers + annotations as one stack, bottom-to-top (z ascending).
    var stackBottomToTop: [StackItem] {
        (imageLayers.map(StackItem.layer) + annotations.map(StackItem.annotation))
            .sorted { $0.z < $1.z }
    }

    /// Top-to-bottom (for the Layers panel).
    var stackTopToBottom: [StackItem] { stackBottomToTop.reversed() }

    /// Give every item a distinct z. Legacy sessions (all z == 0) migrate to the
    /// old implicit order: image layers below, annotations on top.
    func normalizeStackZ() {
        struct Ref { let z: Double; let kind: Int; let idx: Int; let isLayer: Bool; let id: UUID }
        var refs: [Ref] = []
        for (i, l) in imageLayers.enumerated() { refs.append(Ref(z: l.z, kind: 0, idx: i, isLayer: true, id: l.id)) }
        for (i, a) in annotations.enumerated() { refs.append(Ref(z: a.z, kind: 1, idx: i, isLayer: false, id: a.id)) }
        refs.sort { lhs, rhs in
            if lhs.z != rhs.z { return lhs.z < rhs.z }
            if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
            return lhs.idx < rhs.idx
        }
        for (newZ, ref) in refs.enumerated() {
            if ref.isLayer {
                if let i = imageLayers.firstIndex(where: { $0.id == ref.id }) { imageLayers[i].z = Double(newZ) }
            } else {
                if let i = annotations.firstIndex(where: { $0.id == ref.id }) { annotations[i].z = Double(newZ) }
            }
        }
    }

    /// Drag-reorder in the unified stack: move `sourceID` so it takes `targetID`'s
    /// slot (dropping just above the target visually).
    func reorderStack(moving sourceID: UUID, above targetID: UUID) {
        guard sourceID != targetID else { return }
        normalizeStackZ()
        var order = stackTopToBottom.map(\.id) // top-to-bottom
        guard let from = order.firstIndex(of: sourceID) else { return }
        let moved = order.remove(at: from)
        guard let to = order.firstIndex(of: targetID) else { return }
        order.insert(moved, at: to)
        // order is top-to-bottom → assign descending z.
        let count = order.count
        for (i, id) in order.enumerated() {
            let newZ = Double(count - 1 - i)
            if let li = imageLayers.firstIndex(where: { $0.id == id }) { imageLayers[li].z = newZ }
            else if let ai = annotations.firstIndex(where: { $0.id == id }) { annotations[ai].z = newZ }
        }
        record("Reorder layer", systemImage: "arrow.up.arrow.down")
    }

    /// Move an item one step up (forward) or down (backward) in the unified stack.
    func moveStackItem(_ id: UUID, up: Bool) {
        normalizeStackZ()
        let ordered = stackBottomToTop
        guard let idx = ordered.firstIndex(where: { $0.id == id }) else { return }
        let neighbor = up ? idx + 1 : idx - 1
        guard neighbor >= 0, neighbor < ordered.count else { return }
        let a = id, b = ordered[neighbor].id
        let za = stackZ(of: a), zb = stackZ(of: b)
        setStackZ(a, zb)
        setStackZ(b, za)
        record(up ? "Bring forward" : "Send backward", systemImage: "square.3.layers.3d")
    }

    private func stackZ(of id: UUID) -> Double {
        if let l = imageLayers.first(where: { $0.id == id }) { return l.z }
        if let a = annotations.first(where: { $0.id == id }) { return a.z }
        return 0
    }

    private func setStackZ(_ id: UUID, _ z: Double) {
        if let i = imageLayers.firstIndex(where: { $0.id == id }) { imageLayers[i].z = z }
        else if let i = annotations.firstIndex(where: { $0.id == id }) { annotations[i].z = z }
    }

    /// Seed the timeline with the opened image as the first step.
    func seedHistory() {
        normalizeStackZ()
        history = [HistoryEntry(name: "Open", systemImage: "photo", snapshot: currentSnapshot())]
        historyIndex = 0
    }

    /// Record a named history step capturing the state *after* a completed edit.
    /// Truncates any redoable steps ahead of the cursor.
    func record(_ name: String, systemImage: String) {
        guard !isRestoringHistory else { return }
        if history.isEmpty { seedHistory() }
        if historyIndex < history.count - 1 {
            history.removeSubrange((historyIndex + 1)...)
        }
        history.append(HistoryEntry(name: name, systemImage: systemImage, snapshot: currentSnapshot()))
        if history.count > historyLimit + 1 {
            history.removeFirst(history.count - (historyLimit + 1))
        }
        historyIndex = history.count - 1
        isDirty = historyIndex != 0
    }

    func undo() { jump(to: historyIndex - 1) }
    func redo() { jump(to: historyIndex + 1) }

    /// Restore the state at a given timeline index.
    func jump(to index: Int) {
        guard index >= 0, index < history.count, index != historyIndex else { return }
        isRestoringHistory = true
        restore(history[index].snapshot)
        isRestoringHistory = false
        historyIndex = index
        draftCropRect = nil
        draftOutputSize = nil
        selectionRect = nil
        isDirty = index != 0
    }

    init(sourceURL: URL?, sourceImage: NSImage) {
        self.sourceURL = sourceURL
        self.sourceImage = sourceImage
        seedHistory()
        drawingStrokeColor = autoContrastColor
    }

    /// White on dark images, black on light images — a legible default for new
    /// text and shape annotations. Computed from the image's average luminance.
    var autoContrastColor: NSColor {
        let luminance = PaletteExtractor.averageLuminance(of: workingSourceImage) ?? 0.5
        return luminance < 0.5 ? .white : .black
    }

    var pixelSize: CGSize {
        if let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return CGSize(width: cgImage.width, height: cgImage.height)
        }
        if let representation = sourceImage.representations.first {
            return CGSize(width: representation.pixelsWide, height: representation.pixelsHigh)
        }
        return sourceImage.size
    }

    var workingSourceImage: NSImage {
        backgroundRemovedImage ?? sourceImage
    }

    var croppedPixelSize: CGSize {
        CGSize(
            width: max(1, (pixelSize.width * cropRect.width).rounded()),
            height: max(1, (pixelSize.height * cropRect.height).rounded())
        )
    }

    var resizePreviewSize: CGSize {
        draftOutputSize ?? outputSize ?? croppedPixelSize
    }

    var containsTransparency: Bool {
        if backgroundRemovedImage != nil { return true }
        guard let cgImage = workingSourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return false
        }
        switch cgImage.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        default:
            return true
        }
    }

    var effectivePixelSize: CGSize {
        if let outputSize { return outputSize }
        return croppedPixelSize
    }

    var selectedAnnotation: Annotation? {
        guard let selectedAnnotationID else { return nil }
        return annotations.first(where: { $0.id == selectedAnnotationID })
    }

    var hasImageSelection: Bool {
        guard let selectionRect else { return false }
        return selectionRect.width > 0.002 && selectionRect.height > 0.002
    }

    func selectFullImage() {
        selectionRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        selectedAnnotationID = nil
    }

    func addSample(_ color: NSColor) {
        let sample = SampledColor(color: color)
        sampledColors.append(sample)
        selectedColorIDs = [sample.id]
        record("Pick colour", systemImage: "eyedropper")
    }

    func removeSamples(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        sampledColors.removeAll(where: { ids.contains($0.id) })
        selectedColorIDs.subtract(ids)
        record("Remove colour", systemImage: "eyedropper")
    }

    /// Extract dominant colours from the working image and append them as samples.
    func extractPalette(count: Int = 6) {
        let colors = PaletteExtractor.dominantColors(from: workingSourceImage, count: count)
        guard !colors.isEmpty else { return }
        let samples = colors.map { SampledColor(color: $0) }
        sampledColors.append(contentsOf: samples)
        selectedColorIDs = Set(samples.map(\.id))
        record("Extract palette", systemImage: "paintpalette")
    }

    func updateSample(id: UUID, color: NSColor) {
        guard let index = sampledColors.firstIndex(where: { $0.id == id }) else { return }
        sampledColors[index].color = color
    }

    func updateAnnotation(id: UUID, _ update: (inout Annotation) -> Void) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        update(&annotations[index])
        isDirty = true
    }

    func removeAnnotation(id: UUID) {
        annotations.removeAll(where: { $0.id == id })
        if selectedAnnotationID == id { selectedAnnotationID = nil }
        record("Delete", systemImage: "trash")
    }

    func toggleAnnotationVisibility(id: UUID) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[index].isVisible.toggle()
        record(annotations[index].isVisible ? "Show layer" : "Hide layer", systemImage: "eye")
    }

    /// Resize a text annotation's box to fit its content at the current font.
    func fitAnnotationToText(id: UUID) {
        guard let index = annotations.firstIndex(where: { $0.id == id }),
              case .text(let text) = annotations[index].kind else { return }
        let a = annotations[index]
        let content = text.isEmpty ? " " : text
        let baseFont = NSFont(name: a.fontFamily, size: max(a.fontSize, 1))
            ?? NSFont.systemFont(ofSize: max(a.fontSize, 1), weight: a.fontWeight.appKitWeight)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = a.textAlignment.paragraphAlignment
        paragraph.lineHeightMultiple = max(a.lineHeight, 0.01)
        let attrs: [NSAttributedString.Key: Any] = [.font: baseFont, .paragraphStyle: paragraph]
        // Use the layout manager's *used* rect — the tight bounds of the laid-out
        // glyphs — instead of boundingRect, which pads with extra line leading and
        // makes single-line boxes look like they have a trailing blank line.
        let storage = NSTextStorage(string: content, attributes: attrs)
        let container = NSTextContainer(
            size: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        )
        container.lineFragmentPadding = 0
        let layoutManager = NSLayoutManager()
        layoutManager.usesFontLeading = false
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)
        let bounds = layoutManager.usedRect(for: container)
        let pad = max(a.fontSize * 0.18, 4)
        let px = pixelSize
        let w = min((bounds.width + pad * 2) / max(px.width, 1), 1)
        let h = min((bounds.height + pad * 2) / max(px.height, 1), 1)
        var frame = a.frame
        frame.size = CGSize(width: max(w, 0.01), height: max(h, 0.01))
        annotations[index].frame = GeometryMapper.clampedNormalizedRect(frame)
        record("Fit to text", systemImage: "arrow.down.right.and.arrow.up.left")
    }

    func renameAnnotation(id: UUID, to name: String) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        annotations[index].customName = trimmed.isEmpty ? nil : trimmed
        record("Rename layer", systemImage: "pencil")
    }

    func renameImageLayer(id: UUID, to name: String) {
        guard let index = imageLayers.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        imageLayers[index].name = trimmed.isEmpty ? imageLayers[index].name : trimmed
        record("Rename layer", systemImage: "pencil")
    }

    /// Duplicate an annotation, offset slightly so it is visible, and select the copy.
    @discardableResult
    func duplicateAnnotation(id: UUID, offset: CGFloat = 0.02) -> UUID? {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return nil }
        let src = annotations[index]
        let copy = Annotation(
            id: UUID(),
            kind: src.kind,
            frame: CGRect(
                x: min(max(src.frame.minX + offset, 0), max(0, 1 - src.frame.width)),
                y: min(max(src.frame.minY + offset, 0), max(0, 1 - src.frame.height)),
                width: src.frame.width,
                height: src.frame.height
            ),
            strokeColor: src.strokeColor,
            fillColor: src.fillColor,
            lineWidth: src.lineWidth,
            strokeStyle: src.strokeStyle,
            strokeAlignment: src.strokeAlignment,
            cornerRadius: src.cornerRadius,
            dashLength: src.dashLength,
            dashGap: src.dashGap,
            dashOffset: src.dashOffset,
            blendMode: src.blendMode,
            opacity: src.opacity,
            fontFamily: src.fontFamily,
            fontSize: src.fontSize,
            fontWeight: src.fontWeight,
            lineHeight: src.lineHeight,
            textAlignment: src.textAlignment,
            customName: src.customName,
            isVisible: src.isVisible,
            z: nextStackZ
        )
        annotations.insert(copy, at: index + 1)
        selectedAnnotationID = copy.id
        record("Duplicate", systemImage: "plus.square.on.square")
        return copy.id
    }

    /// Duplicate an image layer, returning the new layer's id.
    @discardableResult
    func duplicateImageLayer(id: UUID, offset: CGFloat = 0.02) -> UUID? {
        guard let index = imageLayers.firstIndex(where: { $0.id == id }) else { return nil }
        let src = imageLayers[index]
        let newLayer = ImageLayer(
            id: UUID(), name: src.name + " copy", image: src.image,
            frame: CGRect(
                x: min(max(src.frame.minX + offset, 0), max(0, 1 - src.frame.width)),
                y: min(max(src.frame.minY + offset, 0), max(0, 1 - src.frame.height)),
                width: src.frame.width, height: src.frame.height
            ),
            opacity: src.opacity, isVisible: src.isVisible,
            rotation: src.rotation, flipH: src.flipH, flipV: src.flipV,
            mask: src.mask, isMaskEnabled: src.isMaskEnabled, z: nextStackZ
        )
        imageLayers.insert(newLayer, at: index + 1)
        selectedLayerID = newLayer.id
        selectedLayerIDs = [newLayer.id]
        record("Duplicate layer", systemImage: "plus.square.on.square")
        return newLayer.id
    }

    /// Reorder an annotation in the draw stack. Later entries render on top.
    func moveAnnotation(id: UUID, toFront: Bool) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        let annotation = annotations.remove(at: index)
        if toFront {
            annotations.append(annotation)
        } else {
            annotations.insert(annotation, at: 0)
        }
        record(toFront ? "Bring to front" : "Send to back", systemImage: "square.3.layers.3d")
    }

    func moveAnnotation(id: UUID, forward: Bool) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        let target = forward ? index + 1 : index - 1
        guard target >= 0, target < annotations.count else { return }
        annotations.swapAt(index, target)
        record(forward ? "Bring forward" : "Send backward", systemImage: "square.3.layers.3d")
    }

    /// Move an annotation to an explicit stack index (used by the Layers panel).
    func moveAnnotation(id: UUID, toIndex destination: Int) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        let clamped = max(0, min(destination, annotations.count - 1))
        guard clamped != index else { return }
        let annotation = annotations.remove(at: index)
        annotations.insert(annotation, at: clamped)
        record("Reorder layer", systemImage: "square.3.layers.3d")
    }

    /// Drag-reorder in the Layers panel's visual (front-to-back) order: move the
    /// dragged annotation so it takes the target's slot.
    func reorderAnnotationVisual(moving sourceID: UUID, onto targetID: UUID) {
        guard sourceID != targetID else { return }
        var visual = Array(annotations.reversed())
        guard let from = visual.firstIndex(where: { $0.id == sourceID }) else { return }
        let moved = visual.remove(at: from)
        guard let targetIdx = visual.firstIndex(where: { $0.id == targetID }) else { return }
        visual.insert(moved, at: targetIdx)
        annotations = Array(visual.reversed())
        record("Reorder layer", systemImage: "arrow.up.arrow.down")
    }

    /// Drag-reorder image layers in the Layers panel's visual (front-to-back) order.
    func reorderImageLayerVisual(moving sourceID: UUID, onto targetID: UUID) {
        guard sourceID != targetID else { return }
        var visual = Array(imageLayers.reversed())
        guard let from = visual.firstIndex(where: { $0.id == sourceID }) else { return }
        let moved = visual.remove(at: from)
        guard let targetIdx = visual.firstIndex(where: { $0.id == targetID }) else { return }
        visual.insert(moved, at: targetIdx)
        imageLayers = Array(visual.reversed())
        record("Reorder layer", systemImage: "arrow.up.arrow.down")
    }

    // MARK: - Image layers

    /// Add a placed image as a new layer, centred and scaled to ~half the canvas.
    @discardableResult
    func addImageLayer(_ image: NSImage, name: String) -> UUID {
        let layerAspect = image.size.width / max(image.size.height, 1)
        let base = pixelSize
        let baseAspect = base.width / max(base.height, 1)
        var w: CGFloat = 0.5
        var h: CGFloat = 0.5 * baseAspect / max(layerAspect, 0.0001)
        if h > 0.8 { h = 0.8; w = h * layerAspect / max(baseAspect, 0.0001) }
        w = min(max(w, 0.05), 1)
        h = min(max(h, 0.05), 1)
        let layer = ImageLayer(
            name: name,
            image: image,
            frame: CGRect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h),
            z: nextStackZ
        )
        imageLayers.append(layer)
        selectedLayerID = layer.id
        selectedAnnotationID = nil
        record("Add image layer", systemImage: "photo.on.rectangle")
        return layer.id
    }

    func updateImageLayer(id: UUID, _ update: (inout ImageLayer) -> Void) {
        guard let index = imageLayers.firstIndex(where: { $0.id == id }) else { return }
        update(&imageLayers[index])
        isDirty = true
    }

    /// Promote the locked base image to a normal, transformable layer at the
    /// bottom of the stack; the canvas base becomes transparent.
    @discardableResult
    func unlockBackground() -> UUID? {
        guard !baseUnlocked else { return nil }
        let layer = ImageLayer(
            name: "Background",
            image: workingSourceImage,
            frame: CGRect(x: 0, y: 0, width: 1, height: 1),
            z: minStackZ - 1
        )
        imageLayers.insert(layer, at: 0)
        baseUnlocked = true
        selectedLayerID = layer.id
        selectedLayerIDs = [layer.id]
        selectedAnnotationID = nil
        record("Unlock background", systemImage: "lock.open")
        return layer.id
    }

    func removeImageLayer(id: UUID) {
        imageLayers.removeAll(where: { $0.id == id })
        if selectedLayerID == id { selectedLayerID = nil }
        selectedLayerIDs.remove(id)
        for i in layerGroups.indices { layerGroups[i].memberIDs.removeAll { $0 == id } }
        layerGroups.removeAll { $0.memberIDs.isEmpty }
        record("Delete layer", systemImage: "trash")
    }

    // MARK: - Layer groups

    func groupID(forLayer id: UUID) -> UUID? {
        layerGroups.first(where: { $0.memberIDs.contains(id) })?.id
    }

    /// A layer draws only if it is visible and its group (if any) is visible.
    func isLayerEffectivelyVisible(_ layer: ImageLayer) -> Bool {
        guard layer.isVisible else { return false }
        if let group = layerGroups.first(where: { $0.memberIDs.contains(layer.id) }) {
            return group.isVisible
        }
        return true
    }

    /// Group the current multi-selection (or the single selected layer) of image layers.
    @discardableResult
    func groupSelectedLayers() -> UUID? {
        var ids = selectedLayerIDs
        if ids.isEmpty, let single = selectedLayerID { ids = [single] }
        // Keep only real, not-already-grouped layers, in stack order.
        let ordered = imageLayers.map(\.id).filter { ids.contains($0) && groupID(forLayer: $0) == nil }
        guard ordered.count >= 1 else { return nil }
        let group = LayerGroup(name: "Group \(layerGroups.count + 1)", memberIDs: ordered)
        layerGroups.append(group)
        record("Group layers", systemImage: "folder")
        return group.id
    }

    func ungroup(id: UUID) {
        guard layerGroups.contains(where: { $0.id == id }) else { return }
        layerGroups.removeAll { $0.id == id }
        record("Ungroup", systemImage: "folder.badge.minus")
    }

    func toggleGroupVisibility(id: UUID) {
        guard let index = layerGroups.firstIndex(where: { $0.id == id }) else { return }
        layerGroups[index].isVisible.toggle()
        record(layerGroups[index].isVisible ? "Show group" : "Hide group", systemImage: "eye")
    }

    func toggleGroupCollapsed(id: UUID) {
        guard let index = layerGroups.firstIndex(where: { $0.id == id }) else { return }
        layerGroups[index].isCollapsed.toggle()
    }

    func renameGroup(id: UUID, to name: String) {
        guard let index = layerGroups.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        layerGroups[index].name = trimmed
        record("Rename group", systemImage: "pencil")
    }

    func toggleImageLayerVisibility(id: UUID) {
        guard let index = imageLayers.firstIndex(where: { $0.id == id }) else { return }
        imageLayers[index].isVisible.toggle()
        record(imageLayers[index].isVisible ? "Show layer" : "Hide layer", systemImage: "eye")
    }

    // MARK: - Layer masks

    func setLayerMask(id: UUID, mask: NSImage) {
        guard let index = imageLayers.firstIndex(where: { $0.id == id }) else { return }
        imageLayers[index].mask = mask
        imageLayers[index].isMaskEnabled = true
        record("Add mask", systemImage: "theatermask.and.paintbrush")
    }

    func toggleLayerMask(id: UUID) {
        guard let index = imageLayers.firstIndex(where: { $0.id == id }), imageLayers[index].hasMask else { return }
        imageLayers[index].isMaskEnabled.toggle()
        record(imageLayers[index].isMaskEnabled ? "Enable mask" : "Disable mask", systemImage: "theatermask.and.paintbrush")
    }

    func removeLayerMask(id: UUID) {
        guard let index = imageLayers.firstIndex(where: { $0.id == id }), imageLayers[index].hasMask else { return }
        imageLayers[index].mask = nil
        record("Remove mask", systemImage: "trash")
    }

    /// Add a full-white mask (everything shown) to a layer that has none.
    func addLayerMask(id: UUID) {
        guard let index = imageLayers.firstIndex(where: { $0.id == id }), imageLayers[index].mask == nil else { return }
        imageLayers[index].mask = MaskPainter.fullMask(size: imageLayers[index].image.size)
        imageLayers[index].isMaskEnabled = true
        record("Add mask", systemImage: "theatermask.and.paintbrush")
    }

    /// Invert a layer's mask (swap shown/hidden). Creates a white mask first if none,
    /// so the layer becomes fully hidden.
    func invertLayerMask(id: UUID) {
        guard let index = imageLayers.firstIndex(where: { $0.id == id }) else { return }
        if imageLayers[index].mask == nil {
            imageLayers[index].mask = MaskPainter.fullMask(size: imageLayers[index].image.size)
        }
        if let mask = imageLayers[index].mask {
            imageLayers[index].mask = MaskPainter.invert(mask)
            imageLayers[index].isMaskEnabled = true
        }
        record("Invert mask", systemImage: "circle.righthalf.filled")
    }

    /// Invert whichever mask is active — the one being edited, else the selected layer's.
    func invertActiveMask() {
        if let id = maskEditLayerID ?? selectedLayerID {
            invertLayerMask(id: id)
        }
    }

    // MARK: - Mask editing

    /// Enter mask-edit mode for a layer, creating an empty (fully-revealed) mask
    /// if the layer doesn't have one yet.
    func beginMaskEdit(layerID: UUID) {
        guard let index = imageLayers.firstIndex(where: { $0.id == layerID }) else { return }
        if imageLayers[index].mask == nil {
            imageLayers[index].mask = MaskPainter.fullMask(size: imageLayers[index].image.size)
        }
        imageLayers[index].isMaskEnabled = true
        selectedLayerID = layerID
        maskEditLayerID = layerID
    }

    func endMaskEdit() { maskEditLayerID = nil }

    /// Paint a soft dab into the editing layer's mask (live, unrecorded).
    func paintMaskDab(atNormalized point: CGPoint) {
        guard let id = maskEditLayerID,
              let index = imageLayers.firstIndex(where: { $0.id == id }),
              let mask = imageLayers[index].mask else { return }
        imageLayers[index].mask = MaskPainter.paint(
            on: mask, atNormalized: point,
            diameter: maskBrushSize, softness: maskBrushSoftness,
            reveal: maskBrushReveal, opacity: maskBrushOpacity,
            roundness: maskBrushRoundness, angle: maskBrushAngle
        )
        isDirty = true
    }

    /// Rasterise a whole accumulated brush stroke into the mask in one pass
    /// (called on release), spacing dabs by `maskBrushSpacing × diameter`.
    /// Records a single undo step.
    func applyMaskStroke(normalizedPoints path: [CGPoint]) {
        guard !path.isEmpty,
              let id = maskEditLayerID,
              let index = imageLayers.firstIndex(where: { $0.id == id }),
              let mask = imageLayers[index].mask else { return }
        let size = mask.size
        let stepPx = max(maskBrushSpacing, 0.02) * max(maskBrushSize, 1)

        // Interpolate dabs along every segment of the accumulated path.
        var dabs: [CGPoint] = [path[0]]
        for i in 1..<path.count {
            let a = path[i - 1], b = path[i]
            let dxPx = (b.x - a.x) * size.width
            let dyPx = (b.y - a.y) * size.height
            let distPx = (dxPx * dxPx + dyPx * dyPx).squareRoot()
            let steps = max(1, Int((distPx / max(stepPx, 1)).rounded(.up)))
            for s in 1...steps {
                let t = CGFloat(s) / CGFloat(steps)
                dabs.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }

        imageLayers[index].mask = MaskPainter.paintStroke(
            on: mask, normalizedPoints: dabs,
            diameter: maskBrushSize, softness: maskBrushSoftness,
            reveal: maskBrushReveal, opacity: maskBrushOpacity,
            roundness: maskBrushRoundness, angle: maskBrushAngle
        )
        record(maskBrushReveal ? "Reveal mask" : "Hide mask", systemImage: "paintbrush.pointed")
    }

    /// Flood-hide a connected region in the editing layer's mask (magic wand).
    func floodHideMask(atNormalized point: CGPoint) {
        guard let id = maskEditLayerID,
              let index = imageLayers.firstIndex(where: { $0.id == id }),
              let mask = imageLayers[index].mask else { return }
        if let updated = MaskPainter.floodHide(
            mask: mask, layerImage: imageLayers[index].image,
            atNormalized: point, tolerance: maskWandTolerance
        ) {
            imageLayers[index].mask = updated
            record("Erase region", systemImage: "wand.and.stars")
        }
    }

    func recordMaskEdit() {
        record("Edit mask", systemImage: "paintbrush.pointed")
    }

    func moveImageLayer(id: UUID, forward: Bool) {
        guard let index = imageLayers.firstIndex(where: { $0.id == id }) else { return }
        let target = forward ? index + 1 : index - 1
        guard target >= 0, target < imageLayers.count else { return }
        imageLayers.swapAt(index, target)
        record(forward ? "Bring layer forward" : "Send layer backward", systemImage: "square.3.layers.3d")
    }

    // MARK: - Layer transform

    func rotateLayer90(id: UUID, clockwise: Bool) {
        guard let i = imageLayers.firstIndex(where: { $0.id == id }) else { return }
        imageLayers[i].rotation += clockwise ? 90 : -90
        record("Rotate layer", systemImage: "rotate.right")
    }

    func flipLayer(id: UUID, horizontal: Bool) {
        guard let i = imageLayers.firstIndex(where: { $0.id == id }) else { return }
        if horizontal { imageLayers[i].flipH.toggle() } else { imageLayers[i].flipV.toggle() }
        record(horizontal ? "Flip layer horizontally" : "Flip layer vertically",
               systemImage: horizontal ? "arrow.left.and.right.righttriangle.left.righttriangle.right" : "arrow.up.and.down.righttriangle.up.righttriangle.down")
    }

    func setLayerRotation(id: UUID, degrees: Double) {
        guard let i = imageLayers.firstIndex(where: { $0.id == id }) else { return }
        imageLayers[i].rotation = degrees
        isDirty = true
    }

    func resetLayerTransform(id: UUID) {
        guard let i = imageLayers.firstIndex(where: { $0.id == id }) else { return }
        imageLayers[i].rotation = 0
        imageLayers[i].flipH = false
        imageLayers[i].flipV = false
        record("Reset transform", systemImage: "arrow.counterclockwise")
    }

    func scaleLayer(id: UUID, factor: CGFloat) {
        guard let i = imageLayers.firstIndex(where: { $0.id == id }) else { return }
        var f = imageLayers[i].frame
        let cx = f.midX, cy = f.midY
        let w = min(max(f.width * factor, 0.02), 1)
        let h = min(max(f.height * factor, 0.02), 1)
        f = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
        imageLayers[i].frame = GeometryMapper.clampedNormalizedRect(f)
        record("Resize layer", systemImage: "arrow.up.left.and.arrow.down.right")
    }

    func fitLayerToCanvas(id: UUID) {
        guard let i = imageLayers.firstIndex(where: { $0.id == id }) else { return }
        imageLayers[i].frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        record("Fit layer to canvas", systemImage: "arrow.up.left.and.arrow.down.right")
    }

    func applyDraftCrop() {
        guard let draftCropRect, draftCropRect.width > 0.01, draftCropRect.height > 0.01 else { return }
        let newCrop = GeometryMapper.clampedNormalizedRect(draftCropRect)
        cropRect = newCrop
        self.draftCropRect = nil
        selectionRect = nil
        if cropTrimsOutsideContent {
            annotations.removeAll { !$0.frame.intersects(newCrop) }
            imageLayers.removeAll { !$0.frame.intersects(newCrop) }
        }
        record("Crop", systemImage: "crop")
    }

    func cancelCrop() {
        draftCropRect = nil
    }

    func resetView() {
        zoom = 1
        pan = .zero
        viewportMode = .contain
    }

    func restoreBackground() {
        backgroundRemovedImage = nil
        backgroundRefinementUndoImage = nil
        record("Restore background", systemImage: "photo")
    }

    /// Record a history step for a completed background removal (called by the service).
    func recordBackgroundRemoval() {
        record("Remove background", systemImage: "person.crop.rectangle")
    }

    func undoLastBackgroundRefinement() {
        guard let backgroundRefinementUndoImage else { return }
        backgroundRemovedImage = backgroundRefinementUndoImage
        self.backgroundRefinementUndoImage = nil
        isDirty = true
    }

    func beginResize() {
        draftOutputSize = resizePreviewSize
    }

    func setDraftOutputSize(_ size: CGSize) {
        draftOutputSize = CGSize(
            width: max(1, size.width.rounded()),
            height: max(1, size.height.rounded())
        )
    }

    func applyDraftResize() {
        guard let draftOutputSize, draftOutputSize.width > 0, draftOutputSize.height > 0 else { return }
        outputSize = draftOutputSize
        self.draftOutputSize = nil
        record("Resize", systemImage: "arrow.up.left.and.arrow.down.right")
    }

    func cancelDraftResize() {
        draftOutputSize = nil
    }

    /// Reset the in-progress rotation (angle and flips); keeps canvas/fill preferences.
    func beginRotation() {
        rotationDraft = 0
        rotationFlipHorizontal = false
        rotationFlipVertical = false
    }

    var hasRotationEdits: Bool {
        rotationDraft != 0 || rotationFlipHorizontal || rotationFlipVertical
    }
}

@MainActor
final class VideoSession: ObservableObject {
    let sourceURL: URL
    let asset: AVAsset
    let player: AVPlayer

    @Published var zoom: CGFloat = 1
    @Published var pan: CGSize = .zero
    @Published var cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    @Published var outputSize: CGSize?
    @Published var annotations: [Annotation] = []
    @Published var sampledColors: [SampledColor] = []
    @Published private(set) var naturalSize = CGSize(width: 16, height: 9)

    init(sourceURL: URL) {
        self.sourceURL = sourceURL
        let asset = AVURLAsset(url: sourceURL)
        self.asset = asset
        self.player = AVPlayer(playerItem: AVPlayerItem(asset: asset))

        Task { [weak self] in
            await self?.loadNaturalSize()
        }
    }

    private func loadNaturalSize() async {
        do {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { return }
            let size = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let transformed = size.applying(transform)
            naturalSize = CGSize(width: abs(transformed.width), height: abs(transformed.height))
        } catch {
            naturalSize = CGSize(width: 16, height: 9)
        }
    }
}
