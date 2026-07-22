import AppKit
import ImageKidCore
import CoreGraphics

struct WorkingImageGeometry {
    static func sourcePoint(fromDisplayNormalized point: CGPoint, cropRect: CGRect) -> CGPoint {
        CGPoint(
            x: cropRect.minX + point.x * cropRect.width,
            y: cropRect.minY + point.y * cropRect.height
        )
    }

    static func sourceRect(fromDisplayNormalized rect: CGRect, cropRect: CGRect) -> CGRect {
        GeometryMapper.clampedNormalizedRect(
            CGRect(
                x: cropRect.minX + rect.minX * cropRect.width,
                y: cropRect.minY + rect.minY * cropRect.height,
                width: rect.width * cropRect.width,
                height: rect.height * cropRect.height
            )
        )
    }

    static func displayRect(fromSourceNormalized rect: CGRect, cropRect: CGRect) -> CGRect? {
        guard cropRect.width > 0, cropRect.height > 0, rect.intersects(cropRect) else {
            return nil
        }

        return CGRect(
            x: (rect.minX - cropRect.minX) / cropRect.width,
            y: (rect.minY - cropRect.minY) / cropRect.height,
            width: rect.width / cropRect.width,
            height: rect.height / cropRect.height
        )
    }

    static func sourceTranslation(fromDisplayNormalized translation: CGSize, cropRect: CGRect) -> CGSize {
        CGSize(
            width: translation.width * cropRect.width,
            height: translation.height * cropRect.height
        )
    }

    static func croppedPixelSize(sourceSize: CGSize, cropRect: CGRect) -> CGSize {
        CGSize(
            width: max(1, (sourceSize.width * cropRect.width).rounded()),
            height: max(1, (sourceSize.height * cropRect.height).rounded())
        )
    }
}

struct FreehandStrokeBuilder {
    static func append(
        points: [CGPoint],
        start: CGPoint,
        location: CGPoint,
        inside bounds: CGRect,
        minimumDistance: CGFloat = 1.5
    ) -> [CGPoint] {
        var result = points

        if result.isEmpty, bounds.contains(start) {
            result.append(start)
        }

        guard bounds.contains(location) else { return result }
        if let last = result.last,
           hypot(last.x - location.x, last.y - location.y) < minimumDistance {
            return result
        }

        result.append(location)
        return result
    }
}

@MainActor
enum WorkingImagePreview {
    static func croppedImage(from image: NSImage, cropRect: CGRect) -> NSImage {
        guard cropRect != CGRect(x: 0, y: 0, width: 1, height: 1),
              let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }

        let sourceBounds = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(source.width),
            height: CGFloat(source.height)
        )
        let pixelRect = CGRect(
            x: cropRect.minX * CGFloat(source.width),
            y: cropRect.minY * CGFloat(source.height),
            width: cropRect.width * CGFloat(source.width),
            height: cropRect.height * CGFloat(source.height)
        )
        .integral
        .intersection(sourceBounds)

        guard pixelRect.width > 0,
              pixelRect.height > 0,
              let cropped = source.cropping(to: pixelRect) else {
            return image
        }

        return NSImage(
            cgImage: cropped,
            size: CGSize(width: CGFloat(cropped.width), height: CGFloat(cropped.height))
        )
    }
}
