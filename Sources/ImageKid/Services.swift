import AppKit
import ImageIO
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
        let coordinates = pixelCoordinates(
            normalizedPoint: normalizedPoint,
            width: cgImage.width,
            height: cgImage.height
        )
        return bitmap.colorAt(x: coordinates.x, y: coordinates.y)
    }

    static func pixelCoordinates(normalizedPoint: CGPoint, width: Int, height: Int) -> (x: Int, y: Int) {
        let x = min(max(Int(normalizedPoint.x * CGFloat(width)), 0), max(width - 1, 0))
        let y = min(max(Int(normalizedPoint.y * CGFloat(height)), 0), max(height - 1, 0))
        return (x, y)
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
        guard let image = render(session, options: options) else {
            throw ImageRenderError.renderFailed
        }

        if options.format == .heic {
            try writeHEIC(image, to: url, quality: options.quality)
            return
        }

        guard
            let bitmapType = options.format.bitmapType,
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff)
        else {
            throw ImageRenderError.renderFailed
        }

        var properties: [NSBitmapImageRep.PropertyKey: Any] = [:]
        if options.format.supportsQuality {
            properties[.compressionFactor] = options.quality
        }

        guard let data = bitmap.representation(using: bitmapType, properties: properties) else {
            throw ImageRenderError.encodeFailed
        }
        try data.write(to: url, options: .atomic)
    }

    private static func writeHEIC(_ image: NSImage, to url: URL, quality: Double) throws {
        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard
            let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil),
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.heic.identifier as CFString,
                1,
                nil
            )
        else {
            throw ImageRenderError.encodeFailed
        }

        let properties: CFDictionary = [
            kCGImageDestinationLossyCompressionQuality: quality
        ] as CFDictionary
        CGImageDestinationAddImage(destination, cgImage, properties)

        guard CGImageDestinationFinalize(destination) else {
            throw ImageRenderError.encodeFailed
        }
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

        let lineScale = max(1, targetSize.width / max(sourceSize.width * cropRect.width, 1))
        let lineWidth = annotation.lineWidth * lineScale

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current?.cgContext.setAlpha(annotation.opacity)

        switch annotation.kind {
        case .rectangle:
            drawClosedPath(NSBezierPath(rect: rect), annotation: annotation, lineWidth: lineWidth)

        case .ellipse:
            drawClosedPath(NSBezierPath(ovalIn: rect), annotation: annotation, lineWidth: lineWidth)

        case .line(let start, let end):
            let path = NSBezierPath()
            path.move(to: outputPoint(start, in: rect))
            path.line(to: outputPoint(end, in: rect))
            stroke(path, color: annotation.strokeColor, lineWidth: lineWidth)

        case .arrow(let start, let end):
            drawArrow(
                from: outputPoint(start, in: rect),
                to: outputPoint(end, in: rect),
                color: annotation.strokeColor,
                lineWidth: lineWidth
            )

        case .freehand(let points):
            guard let first = points.first else { return }
            let path = NSBezierPath()
            path.move(to: outputPoint(first, in: rect))
            for point in points.dropFirst() {
                path.line(to: outputPoint(point, in: rect))
            }
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            stroke(path, color: annotation.strokeColor, lineWidth: lineWidth)

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

    private static func drawClosedPath(_ path: NSBezierPath, annotation: Annotation, lineWidth: CGFloat) {
        path.lineWidth = lineWidth
        if let fill = annotation.fillColor {
            fill.setFill()
            path.fill()
        }
        annotation.strokeColor.setStroke()
        path.stroke()
    }

    private static func stroke(_ path: NSBezierPath, color: NSColor, lineWidth: CGFloat) {
        path.lineWidth = lineWidth
        color.setStroke()
        path.stroke()
    }

    private static func outputPoint(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + point.x * rect.width,
            y: rect.maxY - point.y * rect.height
        )
    }

    private static func drawArrow(from start: CGPoint, to end: CGPoint, color: NSColor, lineWidth: CGFloat) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        stroke(path, color: color, lineWidth: lineWidth)

        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(10, lineWidth * 4)
        let spread: CGFloat = .pi / 7
        let left = CGPoint(
            x: end.x - cos(angle - spread) * headLength,
            y: end.y - sin(angle - spread) * headLength
        )
        let right = CGPoint(
            x: end.x - cos(angle + spread) * headLength,
            y: end.y - sin(angle + spread) * headLength
        )
        let head = NSBezierPath()
        head.move(to: left)
        head.line(to: end)
        head.line(to: right)
        head.lineCapStyle = .round
        head.lineJoinStyle = .round
        stroke(head, color: color, lineWidth: lineWidth)
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
