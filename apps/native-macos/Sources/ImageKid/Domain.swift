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
        case .refineBackground: "paintbrush.pointed"
        case .draw: "pencil.tip.crop.circle"
        case .text: "textformat"
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
    var opacity: Double
    var fontFamily: String
    var fontSize: CGFloat
    var fontWeight: AnnotationFontWeight
    var lineHeight: CGFloat
    var textAlignment: AnnotationTextAlignment

    init(
        id: UUID = UUID(),
        kind: Kind,
        frame: CGRect,
        strokeColor: NSColor = .systemRed,
        fillColor: NSColor? = nil,
        lineWidth: CGFloat = 3,
        opacity: Double = 1,
        fontFamily: String = "",
        fontSize: CGFloat = 48,
        fontWeight: AnnotationFontWeight = .semibold,
        lineHeight: CGFloat = 1.1,
        textAlignment: AnnotationTextAlignment = .leading
    ) {
        self.id = id
        self.kind = kind
        self.frame = frame
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.lineWidth = lineWidth
        self.opacity = opacity
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.lineHeight = lineHeight
        self.textAlignment = textAlignment
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
    @Published var selectedAnnotationID: UUID?
    @Published var selectionRect: CGRect?
    @Published var sampledColors: [SampledColor] = []
    @Published var selectedColorIDs: Set<UUID> = []
    @Published var liveSampleColor: NSColor?
    @Published var liveSampleLocation: CGPoint?
    @Published var drawingMode: DrawingMode = .rectangle
    @Published var drawingStrokeColor: NSColor = .systemRed
    @Published var drawingFillColor: NSColor?
    @Published var drawingLineWidth: CGFloat = 4
    @Published var drawingOpacity: Double = 1
    @Published var backgroundRemovedImage: NSImage?
    @Published var backgroundRefinementUndoImage: NSImage?
    @Published var backgroundRefinementMode: BackgroundRefinementMode = .remove
    @Published var backgroundBrushSize: CGFloat = 36
    @Published var backgroundBrushSoftness: CGFloat = 0.45
    @Published var backgroundBrushStrength: CGFloat = 1
    @Published var isDirty = false

    init(sourceURL: URL?, sourceImage: NSImage) {
        self.sourceURL = sourceURL
        self.sourceImage = sourceImage
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
    }

    func removeSamples(_ ids: Set<UUID>) {
        sampledColors.removeAll(where: { ids.contains($0.id) })
        selectedColorIDs.subtract(ids)
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
        isDirty = true
    }

    func applyDraftCrop() {
        guard let draftCropRect, draftCropRect.width > 0.01, draftCropRect.height > 0.01 else { return }
        cropRect = GeometryMapper.clampedNormalizedRect(draftCropRect)
        self.draftCropRect = nil
        selectionRect = nil
        isDirty = true
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
        isDirty = true
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
        isDirty = true
    }

    func cancelDraftResize() {
        draftOutputSize = nil
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
