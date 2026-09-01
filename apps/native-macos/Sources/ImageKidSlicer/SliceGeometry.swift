import CoreGraphics
import Foundation
import ImageKidCore

/// One rectangular region of the source image.
///
/// `rect` is normalised (0…1) against the *orientation-corrected* source
/// image, with a top-left origin — the same convention `CGImage.cropping(to:)`
/// uses — so window size and zoom never change what gets exported.
struct Slice: Identifiable, Equatable {
    let id: UUID
    var rect: CGRect
    /// A user-chosen name. `nil` means "use the automatic `Slice n` name".
    var name: String?
    /// A locked slice is inert to the pointer: it cannot be selected, moved,
    /// resized, or deleted, and a drag that starts on top of it draws a new
    /// slice instead. It still exports, and still acts as a snap target.
    var isLocked: Bool

    init(id: UUID = UUID(), rect: CGRect, name: String? = nil, isLocked: Bool = false) {
        self.id = id
        self.rect = rect
        self.name = name
        self.isLocked = isLocked
    }

    /// The label shown on the canvas: the custom name, or the creation-order
    /// default supplied by the caller.
    func displayName(at index: Int) -> String {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        return "Slice \(index + 1)"
    }
}

/// Which part of a slice a drag is manipulating.
enum SliceHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomRight, .bottomLeft: true
        case .top, .right, .bottom, .left: false
        }
    }

    /// The handle's position inside a rect, as a unit offset from its origin.
    var unitAnchor: CGPoint {
        switch self {
        case .topLeft: CGPoint(x: 0, y: 0)
        case .top: CGPoint(x: 0.5, y: 0)
        case .topRight: CGPoint(x: 1, y: 0)
        case .right: CGPoint(x: 1, y: 0.5)
        case .bottomRight: CGPoint(x: 1, y: 1)
        case .bottom: CGPoint(x: 0.5, y: 1)
        case .bottomLeft: CGPoint(x: 0, y: 1)
        case .left: CGPoint(x: 0, y: 0.5)
        }
    }
}

/// The point of a slice that stays put while it grows or shrinks — the nine
/// positions of the anchor grid in the slice inspector.
enum SliceAnchor: String, CaseIterable, Identifiable {
    case topLeft, top, topRight
    case left, centre, right
    case bottomLeft, bottom, bottomRight

    var id: String { rawValue }

    /// Where the anchor sits inside a rectangle, as a unit offset.
    var unitPoint: CGPoint {
        switch self {
        case .topLeft: CGPoint(x: 0, y: 0)
        case .top: CGPoint(x: 0.5, y: 0)
        case .topRight: CGPoint(x: 1, y: 0)
        case .left: CGPoint(x: 0, y: 0.5)
        case .centre: CGPoint(x: 0.5, y: 0.5)
        case .right: CGPoint(x: 1, y: 0.5)
        case .bottomLeft: CGPoint(x: 0, y: 1)
        case .bottom: CGPoint(x: 0.5, y: 1)
        case .bottomRight: CGPoint(x: 1, y: 1)
        }
    }

    var label: String {
        switch self {
        case .topLeft: "Top left"
        case .top: "Top"
        case .topRight: "Top right"
        case .left: "Left"
        case .centre: "Centre"
        case .right: "Right"
        case .bottomLeft: "Bottom left"
        case .bottom: "Bottom"
        case .bottomRight: "Bottom right"
        }
    }
}

/// Pure slice geometry. Everything here works in normalised source-image
/// space, so it is independent of the canvas, the window, and the zoom level.
enum SliceGeometry {
    /// Below this the drag was almost certainly a mis-click rather than a slice.
    static let minimumNormalizedSize: CGFloat = 0.004

    // MARK: - Creation

    /// The rectangle spanned by a drag from `start` to `end`, both in
    /// normalised source space. `pixelAspect` is source width ÷ height and is
    /// only needed when `square` is set, so that "square" means square in
    /// pixels rather than square in normalised units.
    static func rect(from start: CGPoint, to end: CGPoint, square: Bool = false, pixelAspect: CGFloat = 1) -> CGRect {
        var width = end.x - start.x
        var height = end.y - start.y

        if square, pixelAspect > 0 {
            // Equal pixel extent: nw * W == nh * H, so nw == nh / pixelAspect.
            let pixelWidth = abs(width) * pixelAspect
            let pixelHeight = abs(height)
            let side = max(pixelWidth, pixelHeight)
            width = (side / pixelAspect) * (width < 0 ? -1 : 1)
            height = side * (height < 0 ? -1 : 1)
        }

        let rect = CGRect(
            x: min(start.x, start.x + width),
            y: min(start.y, start.y + height),
            width: abs(width),
            height: abs(height)
        )
        return clamped(rect)
    }

    /// Whether a freshly drawn rectangle is big enough to keep.
    static func isMeaningful(_ rect: CGRect) -> Bool {
        rect.width >= minimumNormalizedSize && rect.height >= minimumNormalizedSize
    }

    // MARK: - Clamping

    /// Confine a rectangle to the source image, keeping its size where it fits
    /// and trimming it where it does not.
    static func clamped(_ rect: CGRect) -> CGRect {
        guard rect.width.isFinite, rect.height.isFinite, rect.minX.isFinite, rect.minY.isFinite else {
            return .zero
        }
        let width = min(max(rect.width, 0), 1)
        let height = min(max(rect.height, 0), 1)
        let x = min(max(rect.minX, 0), 1 - width)
        let y = min(max(rect.minY, 0), 1 - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    // MARK: - Editing

    /// Translate a slice, keeping it whole inside the source image. Unlike a
    /// plain clamp this never shrinks the rectangle — it stops at the edge.
    static func moved(_ rect: CGRect, by delta: CGSize) -> CGRect {
        let width = min(rect.width, 1)
        let height = min(rect.height, 1)
        let x = min(max(rect.minX + delta.width, 0), 1 - width)
        let y = min(max(rect.minY + delta.height, 0), 1 - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Drag one handle of `rect` to `point` (normalised source space).
    ///
    /// Edges may cross: dragging the left edge past the right one flips the
    /// rectangle rather than collapsing it, which is what direct manipulation
    /// should do.
    static func resized(
        _ rect: CGRect,
        handle: SliceHandle,
        to point: CGPoint,
        square: Bool = false,
        pixelAspect: CGFloat = 1
    ) -> CGRect {
        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY

        let target = CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))

        switch handle {
        case .topLeft, .left, .bottomLeft: minX = target.x
        case .topRight, .right, .bottomRight: maxX = target.x
        case .top, .bottom: break
        }
        switch handle {
        case .topLeft, .top, .topRight: minY = target.y
        case .bottomLeft, .bottom, .bottomRight: maxY = target.y
        case .left, .right: break
        }

        var result = CGRect(
            x: min(minX, maxX),
            y: min(minY, maxY),
            width: abs(maxX - minX),
            height: abs(maxY - minY)
        )

        if square, handle.isCorner, pixelAspect > 0 {
            result = squared(result, anchoredAt: handle, pixelAspect: pixelAspect)
        }

        return clamped(result)
    }

    /// Make a corner resize square *in pixels*, growing from the corner
    /// opposite the one being dragged so that corner stays put.
    private static func squared(_ rect: CGRect, anchoredAt handle: SliceHandle, pixelAspect: CGFloat) -> CGRect {
        let side = max(rect.width * pixelAspect, rect.height)
        let width = side / pixelAspect
        let height = side

        let movesLeftEdge = handle == .topLeft || handle == .bottomLeft
        let movesTopEdge = handle == .topLeft || handle == .topRight

        let x = movesLeftEdge ? rect.maxX - width : rect.minX
        let y = movesTopEdge ? rect.maxY - height : rect.minY
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Offset a duplicate so it is visibly its own rectangle, without letting
    /// it slide off the image.
    static func duplicated(_ rect: CGRect, offset: CGFloat = 0.02) -> CGRect {
        moved(rect, by: CGSize(width: offset, height: offset))
    }

    // MARK: - Export resolution

    // MARK: - Typed sizes and positions

    /// Resize a slice to an exact pixel size, holding `anchor` still.
    ///
    /// This is the inspector's job: type 512 × 512 with the top-left anchor and
    /// the top-left corner does not move, while the same numbers on the centre
    /// anchor grow the slice outwards in every direction.
    static func resized(
        _ rect: CGRect,
        toPixelSize size: CGSize,
        anchor: SliceAnchor,
        pixelSize: CGSize
    ) -> CGRect {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return rect }

        let width = min(max(size.width, 1) / pixelSize.width, 1)
        let height = min(max(size.height, 1) / pixelSize.height, 1)

        let held = CGPoint(
            x: rect.minX + anchor.unitPoint.x * rect.width,
            y: rect.minY + anchor.unitPoint.y * rect.height
        )
        return clamped(CGRect(
            x: held.x - anchor.unitPoint.x * width,
            y: held.y - anchor.unitPoint.y * height,
            width: width,
            height: height
        ))
    }

    /// Move a slice so its top-left corner sits on an exact source pixel,
    /// keeping its size.
    static func moved(_ rect: CGRect, toPixelOrigin origin: CGPoint, pixelSize: CGSize) -> CGRect {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return rect }
        let target = CGPoint(x: origin.x / pixelSize.width, y: origin.y / pixelSize.height)
        return moved(rect, by: CGSize(width: target.x - rect.minX, height: target.y - rect.minY))
    }

    /// Resolve a normalised slice to whole source pixels.
    ///
    /// Edges round to the nearest pixel so the crop matches what was drawn;
    /// a rectangle that rounds away to nothing is widened to a single pixel
    /// rather than dropped, and a genuinely empty rectangle returns `nil`.
    static func pixelRect(_ normalized: CGRect, pixelSize: CGSize) -> CGRect? {
        let width = pixelSize.width.rounded()
        let height = pixelSize.height.rounded()
        guard width >= 1, height >= 1 else { return nil }

        let rect = clamped(normalized)
        guard rect.width > 0, rect.height > 0 else { return nil }

        var minX = (rect.minX * width).rounded()
        var minY = (rect.minY * height).rounded()
        var maxX = (rect.maxX * width).rounded()
        var maxY = (rect.maxY * height).rounded()

        minX = min(max(minX, 0), width - 1)
        minY = min(max(minY, 0), height - 1)
        maxX = min(max(maxX, minX + 1), width)
        maxY = min(max(maxY, minY + 1), height)

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// Maps between canvas points and normalised source coordinates for one frame.
///
/// The canvas owns zoom and pan; slices never do. Everything the pointer does
/// is converted through here, which is why resizing the window or zooming in
/// cannot move a slice on the source image.
struct SliceCanvasLayout {
    /// Where the source image is drawn, in canvas coordinates.
    let imageRect: CGRect

    static func make(
        pixelSize: CGSize,
        bounds: CGRect,
        zoom: CGFloat,
        pan: CGSize,
        padding: CGFloat = 0
    ) -> SliceCanvasLayout {
        let available = bounds.insetBy(dx: padding, dy: padding)
        let fitted = GeometryMapper.aspectFitRect(contentSize: pixelSize, in: available)
        guard fitted.width > 0, fitted.height > 0 else {
            return SliceCanvasLayout(imageRect: .zero)
        }

        let size = CGSize(width: fitted.width * zoom, height: fitted.height * zoom)
        let origin = CGPoint(
            x: bounds.midX - size.width / 2 + pan.width,
            y: bounds.midY - size.height / 2 + pan.height
        )
        return SliceCanvasLayout(imageRect: CGRect(origin: origin, size: size))
    }

    var isUsable: Bool { imageRect.width > 0 && imageRect.height > 0 }

    func viewRect(for normalized: CGRect) -> CGRect {
        GeometryMapper.viewRect(from: normalized, in: imageRect)
    }

    /// Unclamped on purpose: a drag that leaves the image still has to produce
    /// a coordinate, and `SliceGeometry` decides where it lands.
    func normalizedPoint(_ point: CGPoint) -> CGPoint {
        guard isUsable else { return .zero }
        return CGPoint(
            x: (point.x - imageRect.minX) / imageRect.width,
            y: (point.y - imageRect.minY) / imageRect.height
        )
    }

    func normalizedDelta(_ translation: CGSize) -> CGSize {
        guard isUsable else { return .zero }
        return CGSize(
            width: translation.width / imageRect.width,
            height: translation.height / imageRect.height
        )
    }

    /// The pan offset that keeps `anchor` — a point in canvas coordinates —
    /// under the pointer while the zoom is multiplied by `factor`.
    ///
    /// Zooming about the centre is fine for taking in the whole sheet and
    /// useless for inspecting a corner: the thing being looked at slides away
    /// exactly when it gets big enough to see.
    func panOffset(keeping anchor: CGPoint, scaledBy factor: CGFloat, in bounds: CGRect) -> CGSize {
        guard isUsable, factor > 0 else { return .zero }

        // Where the anchor sits on the image now, as a fraction of it.
        let unit = CGPoint(
            x: (anchor.x - imageRect.minX) / imageRect.width,
            y: (anchor.y - imageRect.minY) / imageRect.height
        )
        let scaled = CGSize(width: imageRect.width * factor, height: imageRect.height * factor)

        // The origin that puts that same fraction back under the anchor, minus
        // where a centred image of the new size would already sit.
        return CGSize(
            width: anchor.x - unit.x * scaled.width - (bounds.midX - scaled.width / 2),
            height: anchor.y - unit.y * scaled.height - (bounds.midY - scaled.height / 2)
        )
    }

    /// Keep at least a corner of the image on screen, so a stray gesture
    /// cannot fling it somewhere it has to be hunted for.
    static func clampedPan(
        _ pan: CGSize,
        imageSize: CGSize,
        bounds: CGRect,
        keepingVisible margin: CGFloat = 60
    ) -> CGSize {
        let maximumX = max(bounds.width / 2 + imageSize.width / 2 - margin, 0)
        let maximumY = max(bounds.height / 2 + imageSize.height / 2 - margin, 0)
        return CGSize(
            width: min(max(pan.width, -maximumX), maximumX),
            height: min(max(pan.height, -maximumY), maximumY)
        )
    }

    /// The handle under the pointer, if any. Corners win over edges so the
    /// overlapping hit areas at a rectangle's corners behave predictably.
    func handle(at point: CGPoint, of normalized: CGRect, tolerance: CGFloat) -> SliceHandle? {
        let rect = viewRect(for: normalized)
        let ordered: [SliceHandle] = [
            .topLeft, .topRight, .bottomLeft, .bottomRight,
            .top, .bottom, .left, .right
        ]
        return ordered.first { handle in
            let anchor = CGPoint(
                x: rect.minX + handle.unitAnchor.x * rect.width,
                y: rect.minY + handle.unitAnchor.y * rect.height
            )
            return abs(point.x - anchor.x) <= tolerance && abs(point.y - anchor.y) <= tolerance
        }
    }
}
