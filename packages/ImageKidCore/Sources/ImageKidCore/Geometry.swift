import CoreGraphics

/// Pure geometry helpers shared by both apps: map between view-space points and
/// the normalised (0…1) coordinate space used for annotations and layer frames.
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

    /// A rounded-rectangle path with independent corner radii (visual order
    /// top-left, top-right, bottom-right, bottom-left). Pass `flipped: true` for
    /// a bottom-left-origin (y-up) context like the AppKit export renderer, so
    /// the visual "top" corners map to the larger-y edge.
    public static func roundedRectPath(
        _ rect: CGRect,
        topLeft: CGFloat, topRight: CGFloat, bottomRight: CGFloat, bottomLeft: CGFloat,
        flipped: Bool = false
    ) -> CGPath {
        let maxR = min(abs(rect.width), abs(rect.height)) / 2
        func clamp(_ r: CGFloat) -> CGFloat { min(max(r, 0), maxR) }
        let tl = clamp(topLeft), tr = clamp(topRight), br = clamp(bottomRight), bl = clamp(bottomLeft)

        let topY = flipped ? rect.maxY : rect.minY
        let bottomY = flipped ? rect.minY : rect.maxY
        let leftX = rect.minX, rightX = rect.maxX

        let topLeftCorner = CGPoint(x: leftX, y: topY)
        let topRightCorner = CGPoint(x: rightX, y: topY)
        let bottomRightCorner = CGPoint(x: rightX, y: bottomY)
        let bottomLeftCorner = CGPoint(x: leftX, y: bottomY)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: (leftX + rightX) / 2, y: topY))
        path.addArc(tangent1End: topRightCorner, tangent2End: bottomRightCorner, radius: tr)
        path.addArc(tangent1End: bottomRightCorner, tangent2End: bottomLeftCorner, radius: br)
        path.addArc(tangent1End: bottomLeftCorner, tangent2End: topLeftCorner, radius: bl)
        path.addArc(tangent1End: topLeftCorner, tangent2End: topRightCorner, radius: tl)
        path.closeSubpath()
        return path
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
