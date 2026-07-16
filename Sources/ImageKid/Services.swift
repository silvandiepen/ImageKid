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
    static func render(_ session: ImageSession) -> NSImage? {
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
        let targetSize = session.effectivePixelSize
        let result = NSImage(size: targetSize)

        result.lockFocus()
        defer { result.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: cropped, size: targetSize).draw(
            in: CGRect(origin: .zero, size: targetSize),
            from: .zero,
            operation: .copy,
            fraction: 1
        )

        for annotation in session.annotations {
            draw(annotation, in: targetSize)
        }

        return result
    }

    static func write(_ session: ImageSession, to url: URL, type: UTType) throws {
        guard
            let image = render(session),
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff)
        else {
            throw ImageRenderError.renderFailed
        }

        let fileType: NSBitmapImageRep.FileType
        let properties: [NSBitmapImageRep.PropertyKey: Any]

        if type == .jpeg {
            fileType = .jpeg
            properties = [.compressionFactor: 0.92]
        } else if type == .tiff {
            fileType = .tiff
            properties = [:]
        } else {
            fileType = .png
            properties = [:]
        }

        guard let data = bitmap.representation(using: fileType, properties: properties) else {
            throw ImageRenderError.encodeFailed
        }
        try data.write(to: url, options: .atomic)
    }

    private static func draw(_ annotation: Annotation, in size: CGSize) {
        let rect = CGRect(
            x: annotation.frame.minX * size.width,
            y: (1 - annotation.frame.maxY) * size.height,
            width: annotation.frame.width * size.width,
            height: annotation.frame.height * size.height
        )

        switch annotation.kind {
        case .rectangle:
            let path = NSBezierPath(rect: rect)
            path.lineWidth = annotation.lineWidth
            if let fill = annotation.fillColor {
                fill.setFill()
                path.fill()
            }
            annotation.strokeColor.setStroke()
            path.stroke()

        case .text(let value):
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: max(14, rect.height * 0.4), weight: .semibold),
                .foregroundColor: annotation.strokeColor
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
