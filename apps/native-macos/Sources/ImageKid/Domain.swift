import Foundation
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

enum DrawingMode: String, CaseIterable, Identifiable {
    case rectangle
    case ellipse
    case line
    case arrow
    case freehand

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .line: "Line"
        case .arrow: "Arrow"
        case .freehand: "Freehand"
        }
    }

    var symbolName: String {
        switch self {
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .freehand: "pencil.tip"
        }
    }

    var supportsFill: Bool {
        self == .rectangle || self == .ellipse
    }
}

struct SampledColor: Identifiable {
    let id: UUID
    var color: NSColor

    init(id: UUID = UUID(), color: NSColor) {
        self.id = id
        self.color = color
    }

    var sRGB: NSColor {
        color.usingColorSpace(.sRGB) ?? color
    }

    var hex: String {
        let value = sRGB
        let includeAlpha = value.alphaComponent < 0.999
        return String(
            format: includeAlpha ? "#%02X%02X%02X%02X" : "#%02X%02X%02X",
            Int((value.redComponent * 255).rounded()),
            Int((value.greenComponent * 255).rounded()),
            Int((value.blueComponent * 255).rounded()),
            Int((value.alphaComponent * 255).rounded())
        )
    }

    var rgb: String {
        let value = sRGB
        return String(
            format: "rgb(%d, %d, %d)",
            Int((value.redComponent * 255).rounded()),
            Int((value.greenComponent * 255).rounded()),
            Int((value.blueComponent * 255).rounded())
        )
    }

    var rgba: String {
        let value = sRGB
        return String(
            format: "rgba(%d, %d, %d, %.3f)",
            Int((value.redComponent * 255).rounded()),
            Int((value.greenComponent * 255).rounded()),
            Int((value.blueComponent * 255).rounded()),
            value.alphaComponent
        )
    }

    var hsl: String {
        let value = sRGB
        let r = value.redComponent
        let g = value.greenComponent
        let b = value.blueComponent
        let maximum = max(r, g, b)
        let minimum = min(r, g, b)
        let delta = maximum - minimum
        let lightness = (maximum + minimum) / 2
        let saturation = delta == 0 ? 0 : delta / (1 - abs(2 * lightness - 1))
        var hue: CGFloat = 0
        if delta != 0 {
            if maximum == r {
                hue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maximum == g {
                hue = 60 * (((b - r) / delta) + 2)
            } else {
                hue = 60 * (((r - g) / delta) + 4)
            }
        }
        if hue < 0 { hue += 360 }
        return String(format: "hsl(%.0f, %.0f%%, %.0f%%)", hue, saturation * 100, lightness * 100)
    }

    var cssVariable: String { "--color: \(hex);" }

    var swiftUIColor: String {
        let value = sRGB
        return String(
            format: "Color(red: %.3f, green: %.3f, blue: %.3f, opacity: %.3f)",
            value.redComponent,
            value.greenComponent,
            value.blueComponent,
            value.alphaComponent
        )
    }
}

enum AnnotationFontWeight: String, CaseIterable, Identifiable {
    case regular
    case medium
    case semibold
    case bold

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var swiftUIWeight: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }

    var appKitWeight: NSFont.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }

    var fontManagerWeight: Int {
        switch self {
        case .regular: 5
        case .medium: 7
        case .semibold: 8
        case .bold: 9
        }
    }
}

enum AnnotationTextAlignment: String, CaseIterable, Identifiable {
    case leading
    case center
    case trailing

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var swiftUIAlignment: Alignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var paragraphAlignment: NSTextAlignment {
        switch self {
        case .leading: .left
        case .center: .center
        case .trailing: .right
        }
    }
}

/// Stroke line style for shapes and lines.
enum ShapeStrokeStyle: String, CaseIterable, Identifiable, Hashable {
    case solid, dashed, dotted
    var id: String { rawValue }
    var label: String {
        switch self {
        case .solid: return "Solid"
        case .dashed: return "Dashed"
        case .dotted: return "Dotted"
        }
    }
    /// Dash pattern scaled to the stroke width (empty = solid line).
    func dashPattern(lineWidth: CGFloat) -> [CGFloat] {
        let w = max(lineWidth, 1)
        switch self {
        case .solid: return []
        case .dashed: return [w * 3, w * 2.2]
        case .dotted: return [w * 0.05, w * 1.8]
        }
    }
}

struct Annotation: Identifiable {
    enum Kind {
        case rectangle
        case ellipse
        case line(start: CGPoint, end: CGPoint)
        case arrow(start: CGPoint, end: CGPoint)
        case freehand(points: [CGPoint])
        case text(String)
    }

    let id: UUID
    var kind: Kind
    var frame: CGRect
    var strokeColor: NSColor
    var fillColor: NSColor?
    var lineWidth: CGFloat
    var strokeStyle: ShapeStrokeStyle
    var opacity: Double
    var fontFamily: String
    var fontSize: CGFloat
    var fontWeight: AnnotationFontWeight
    var lineHeight: CGFloat
    var textAlignment: AnnotationTextAlignment
    var customName: String?
    var isVisible: Bool

    init(
        id: UUID = UUID(),
        kind: Kind,
        frame: CGRect,
        strokeColor: NSColor = .systemRed,
        fillColor: NSColor? = nil,
        lineWidth: CGFloat = 3,
        strokeStyle: ShapeStrokeStyle = .solid,
        opacity: Double = 1,
        fontFamily: String = "",
        fontSize: CGFloat = 48,
        fontWeight: AnnotationFontWeight = .semibold,
        lineHeight: CGFloat = 1.1,
        textAlignment: AnnotationTextAlignment = .leading,
        customName: String? = nil,
        isVisible: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.frame = frame
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.lineWidth = lineWidth
        self.strokeStyle = strokeStyle
        self.opacity = opacity
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.lineHeight = lineHeight
        self.textAlignment = textAlignment
        self.customName = customName
        self.isVisible = isVisible
    }

    var textValue: String? {
        get {
            guard case .text(let value) = kind else { return nil }
            return value
        }
        set {
            guard case .text = kind, let newValue else { return }
            kind = .text(newValue)
        }
    }

    var isText: Bool {
        if case .text = kind { return true }
        return false
    }

    var isDrawable: Bool { !isText }

    var drawingMode: DrawingMode? {
        switch kind {
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .line: .line
        case .arrow: .arrow
        case .freehand: .freehand
        case .text: nil
        }
    }

    mutating func changeDrawingMode(_ mode: DrawingMode) {
        switch mode {
        case .rectangle:
            kind = .rectangle
        case .ellipse:
            kind = .ellipse
        case .line:
            kind = .line(start: .zero, end: CGPoint(x: 1, y: 1))
        case .arrow:
            kind = .arrow(start: .zero, end: CGPoint(x: 1, y: 1))
        case .freehand:
            kind = .freehand(points: [.zero, CGPoint(x: 1, y: 1)])
        }
    }
}

/// A placed raster image composited above the base image and below vector
/// annotations. `frame` is normalised in the base-image source space (0…1),
/// matching `Annotation.frame`.
struct ImageLayer: Identifiable {
    let id: UUID
    var name: String
    var image: NSImage
    var frame: CGRect
    var opacity: Double
    var isVisible: Bool
    /// Rotation in degrees, clockwise, about the layer's centre.
    var rotation: Double
    var flipH: Bool
    var flipV: Bool
    /// Non-destructive alpha mask (white = keep, black = hide). Applied to the
    /// layer image when `isMaskEnabled` is true; the original pixels are kept.
    var mask: NSImage?
    var isMaskEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        image: NSImage,
        frame: CGRect,
        opacity: Double = 1,
        isVisible: Bool = true,
        rotation: Double = 0,
        flipH: Bool = false,
        flipV: Bool = false,
        mask: NSImage? = nil,
        isMaskEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.image = image
        self.frame = frame
        self.opacity = opacity
        self.isVisible = isVisible
        self.rotation = rotation
        self.flipH = flipH
        self.flipV = flipV
        self.mask = mask
        self.isMaskEnabled = isMaskEnabled
    }

    var hasMask: Bool { mask != nil }

    /// The image as it should render — masked when a mask is present and enabled.
    var renderedImage: NSImage {
        guard isMaskEnabled, let mask else { return image }
        return MaskCompositor.apply(mask: mask, to: image) ?? image
    }
}

/// An organisational group over image layers. Toggling group visibility gates
/// all members; members keep their own z-order in the flat layer stack.
struct LayerGroup: Identifiable {
    let id: UUID
    var name: String
    var memberIDs: [UUID]
    var isVisible: Bool
    var isCollapsed: Bool

    init(id: UUID = UUID(), name: String, memberIDs: [UUID], isVisible: Bool = true, isCollapsed: Bool = false) {
        self.id = id
        self.name = name
        self.memberIDs = memberIDs
        self.isVisible = isVisible
        self.isCollapsed = isCollapsed
    }
}

@MainActor
final class ImageSession: ObservableObject {
    let sourceURL: URL?
    let sourceImage: NSImage

    @Published var zoom: CGFloat = 1
    @Published var pan: CGSize = .zero
    @Published var viewportMode: ViewportMode = .contain
    @Published var cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    @Published var draftCropRect: CGRect?
    @Published var cropAspectRatio: CropAspectRatio = .free
    @Published var outputSize: CGSize?
    @Published var draftOutputSize: CGSize?
    @Published var resizePreservesAspect = true
    @Published var annotations: [Annotation] = []
    @Published var imageLayers: [ImageLayer] = []
    @Published var layerGroups: [LayerGroup] = []
    @Published var selectedAnnotationID: UUID?
    @Published var selectedLayerID: UUID?
    @Published var selectedLayerIDs: Set<UUID> = []

    // Mask editing (for the selected image layer's mask).
    @Published var maskEditLayerID: UUID?
    @Published var maskViewMode: MaskViewMode = .overlay
    @Published var maskBrushReveal = false
    @Published var maskBrushSize: CGFloat = 48
    @Published var maskBrushSoftness: CGFloat = 0.4
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
    /// Grid line colour (hex). Default subtle white.
    @Published var gridColorHex: String = "#FFFFFF"
    /// Grid line opacity, 0…1.
    @Published var gridOpacity: Double = 0.18
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
            backgroundRemovedImage: backgroundRemovedImage
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
    }

    /// Seed the timeline with the opened image as the first step.
    func seedHistory() {
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
        let bounds = (content as NSString).boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
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
    func duplicateAnnotation(id: UUID) -> UUID? {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = annotations[index]
        let offset: CGFloat = 0.02
        copy = Annotation(
            id: UUID(),
            kind: copy.kind,
            frame: CGRect(
                x: min(copy.frame.minX + offset, 1 - copy.frame.width),
                y: min(copy.frame.minY + offset, 1 - copy.frame.height),
                width: copy.frame.width,
                height: copy.frame.height
            ),
            strokeColor: copy.strokeColor,
            fillColor: copy.fillColor,
            lineWidth: copy.lineWidth,
            opacity: copy.opacity,
            fontFamily: copy.fontFamily,
            fontSize: copy.fontSize,
            fontWeight: copy.fontWeight,
            lineHeight: copy.lineHeight,
            textAlignment: copy.textAlignment,
            customName: copy.customName,
            isVisible: copy.isVisible
        )
        annotations.insert(copy, at: index + 1)
        selectedAnnotationID = copy.id
        record("Duplicate", systemImage: "plus.square.on.square")
        return copy.id
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
            frame: CGRect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)
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
            diameter: maskBrushSize, softness: maskBrushSoftness, reveal: maskBrushReveal
        )
        isDirty = true
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
        cropRect = GeometryMapper.clampedNormalizedRect(draftCropRect)
        self.draftCropRect = nil
        selectionRect = nil
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

public enum GeometryMapper {
    public static func aspectFitRect(contentSize: CGSize, in bounds: CGRect) -> CGRect {
        guard contentSize.width > 0, contentSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return .zero
        }

        let scale = min(bounds.width / contentSize.width, bounds.height / contentSize.height)
        let size = CGSize(width: contentSize.width * scale, height: contentSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    public static func normalizedPoint(_ point: CGPoint, in imageRect: CGRect) -> CGPoint? {
        guard imageRect.contains(point), imageRect.width > 0, imageRect.height > 0 else { return nil }
        return CGPoint(
            x: (point.x - imageRect.minX) / imageRect.width,
            y: (point.y - imageRect.minY) / imageRect.height
        )
    }

    public static func normalizedRect(from first: CGPoint, to second: CGPoint, in imageRect: CGRect) -> CGRect? {
        guard let a = normalizedPoint(first, in: imageRect), let b = normalizedPoint(second, in: imageRect) else {
            return nil
        }
        return clampedNormalizedRect(CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        ))
    }

    public static func viewRect(from normalizedRect: CGRect, in imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + normalizedRect.minX * imageRect.width,
            y: imageRect.minY + normalizedRect.minY * imageRect.height,
            width: normalizedRect.width * imageRect.width,
            height: normalizedRect.height * imageRect.height
        )
    }

    public static func clampedNormalizedRect(_ rect: CGRect, minimumSize: CGFloat = 0.01) -> CGRect {
        let width = min(max(rect.width, minimumSize), 1)
        let height = min(max(rect.height, minimumSize), 1)
        let x = min(max(rect.minX, 0), 1 - width)
        let y = min(max(rect.minY, 0), 1 - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    public static func applyingAspectRatio(_ ratio: CGFloat?, to rect: CGRect, anchor: CGPoint = .zero) -> CGRect {
        guard let ratio, ratio > 0 else { return clampedNormalizedRect(rect) }
        var result = rect
        let proposedHeight = result.width / ratio
        if proposedHeight <= 1 {
            result.size.height = proposedHeight
        } else {
            result.size.width = result.height * ratio
        }
        return clampedNormalizedRect(result)
    }
}
