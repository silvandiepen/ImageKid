import AppKit
import UniformTypeIdentifiers

@MainActor
enum MediaLoader {
    static func load(url: URL) throws -> MediaItem {
        let type = try url.resourceValues(forKeys: [.contentTypeKey]).contentType

        if type?.conforms(to: .movie) == true || type?.conforms(to: .video) == true {
            return .video(VideoSession(sourceURL: url))
        }

        guard let image = NSImage(contentsOf: url) else {
            throw MediaLoaderError.unsupportedFile
        }
        return .image(ImageSession(sourceURL: url, sourceImage: image))
    }
}

enum MediaLoaderError: LocalizedError {
    case unsupportedFile

    var errorDescription: String? {
        "ImageKid could not open this file."
    }
}

enum MediaItem {
    case image(ImageSession)
    case video(VideoSession)
}

struct PixelSampler {
    static func color(in image: NSImage, at normalizedPoint: CGPoint) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let x = min(max(Int(normalizedPoint.x * CGFloat(cgImage.width)), 0), cgImage.width - 1)
        let y = min(max(Int((1 - normalizedPoint.y) * CGFloat(cgImage.height)), 0), cgImage.height - 1)
        return bitmap.colorAt(x: x, y: y)
    }
}

@MainActor
enum ImageRenderer {
    static func render(_ session: ImageSession, options: ImageExportOptions = ImageExportOptions()) -> NSImage? {
        guard let source = session.sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let pixelCrop = CGRect(
            x: session.cropRect.minX * CGFloat(source.width),
            y: session.cropRect.minY * CGFloat(source.height),
            width: session.cropRect.width * CGFloat(source.width),
            height: session.cropRect.height * CGFloat(source.height)
        ).integral

        guard let cropped = source.cropping(to: pixelCrop) else { return nil }
        let baseSize = session.effectivePixelSize
        let targetSize = CGSize(
            width: max(1, (baseSize.width * options.scale).rounded()),
            height: max(1, (baseSize.height * options.scale).rounded())
        )
        let result = NSImage(size: targetSize)

        result.lockFocus()
        defer { result.unlockFocus() }

        if !options.format.supportsAlpha {
            options.backgroundColor.setFill()
            NSBezierPath(rect: CGRect(origin: .zero, size: targetSize)).fill()
        }

        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: cropped, size: targetSize).draw(
            in: CGRect(origin: .zero, size: targetSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )

        for annotation in session.annotations {
            draw(annotation, cropRect: session.cropRect, sourceSize: session.pixelSize, targetSize: targetSize)
        }

        return result
    }

    static func write(_ session: ImageSession, to url: URL, options: ImageExportOptions) throws {
        guard
            let image = render(session, options: options),
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff)
        else {
            throw ImageRenderError.renderFailed
        }

        var properties: [NSBitmapImageRep.PropertyKey: Any] = [:]
        if options.format.supportsQuality {
            properties[.compressionFactor] = options.quality
        }

        guard let data = bitmap.representation(using: options.format.bitmapType, properties: properties) else {
            throw ImageRenderError.encodeFailed
        }
        try data.write(to: url, options: .atomic)
    }

    private static func draw(
        _ annotation: Annotation,
        cropRect: CGRect,
        sourceSize: CGSize,
        targetSize: CGSize
    ) {
        let relativeFrame = CGRect(
            x: (annotation.frame.minX - cropRect.minX) / cropRect.width,
            y: (annotation.frame.minY - cropRect.minY) / cropRect.height,
            width: annotation.frame.width / cropRect.width,
            height: annotation.frame.height / cropRect.height
        )

        guard relativeFrame.maxX > 0, relativeFrame.maxY > 0, relativeFrame.minX < 1, relativeFrame.minY < 1 else {
            return
        }

        let rect = CGRect(
            x: relativeFrame.minX * targetSize.width,
            y: (1 - relativeFrame.maxY) * targetSize.height,
            width: relativeFrame.width * targetSize.width,
            height: relativeFrame.height * targetSize.height
        )

        switch annotation.kind {
        case .rectangle:
            let path = NSBezierPath(rect: rect)
            path.lineWidth = annotation.lineWidth * max(1, targetSize.width / max(sourceSize.width, 1))
            if let fill = annotation.fillColor {
                fill.setFill()
                path.fill()
            }
            annotation.strokeColor.setStroke()
            path.stroke()

        case .text(let value):
            let scale = targetSize.width / max(sourceSize.width * cropRect.width, 1)
            let size = max(8, annotation.fontSize * scale)
            let font: NSFont
            if annotation.fontFamily.isEmpty {
                font = NSFont.systemFont(ofSize: size, weight: annotation.fontWeight.appKitWeight)
            } else {
                font = NSFont(name: annotation.fontFamily, size: size)
                    ?? NSFont.systemFont(ofSize: size, weight: annotation.fontWeight.appKitWeight)
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = annotation.textAlignment.paragraphAlignment
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: annotation.strokeColor,
                .paragraphStyle: paragraph
            ]
            value.draw(in: rect, withAttributes: attributes)
        }
    }
}

enum ImageRenderError: LocalizedError {
    case renderFailed
    case encodeFailed

    var errorDescription: String? {
        switch self {
        case .renderFailed: "The image could not be rendered."
        case .encodeFailed: "The image could not be encoded."
        }
    }
}
