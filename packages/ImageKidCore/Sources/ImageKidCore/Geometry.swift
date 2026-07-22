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
