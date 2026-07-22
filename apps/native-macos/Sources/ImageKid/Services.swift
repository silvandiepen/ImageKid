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

protocol PromptImageEditProvider {
    var name: String { get }

    @MainActor
    func edit(image: NSImage, prompt: String) async throws -> NSImage
}

enum PromptImageEditError: LocalizedError {
    case missingCredential(String)
    case imageEncodingFailed
    case invalidResponse(String)
    case apiError(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .missingCredential(let providerName):
            "Add a \(providerName) credential in Settings before using prompted edits."
        case .imageEncodingFailed:
            "ImageKid could not prepare this image for prompted editing."
        case .invalidResponse(let providerName):
            "\(providerName) did not return an edited image."
        case .apiError(let message):
            message
        case .timedOut:
            "Magic took too long. Try again with a smaller selection, or check your connection."
        }
    }
}

enum PromptImageEditService {
    @MainActor
    static func edit(image: NSImage, prompt: String, provider: PromptImageEditProvider) async throws -> NSImage {
        try await provider.edit(image: image, prompt: prompt)
    }
}

enum PromptImageEditPayloadScope: Equatable {
    case fullImage
    case selection(CGRect)
}

struct PromptImageEditPayload {
    let image: NSImage
    let sourceImage: NSImage
    let scope: PromptImageEditPayloadScope
}

enum PromptImageEditPayloadBuilder {
    @MainActor
    static func payload(for session: ImageSession) throws -> PromptImageEditPayload {
        guard let sourceImage = ImageRenderer.render(session) else {
            throw PromptImageEditError.imageEncodingFailed
        }

        guard session.hasImageSelection, let selectionRect = session.selectionRect else {
            return PromptImageEditPayload(
                image: sourceImage,
                sourceImage: sourceImage,
                scope: .fullImage
            )
        }

        guard let cropped = ImageSelectionRenderer.crop(sourceImage, normalizedRect: selectionRect) else {
            throw PromptImageEditError.imageEncodingFailed
        }

        return PromptImageEditPayload(
            image: cropped,
            sourceImage: sourceImage,
            scope: .selection(selectionRect)
        )
    }
}

struct OpenAIPromptImageEditProvider: PromptImageEditProvider {
    private static let endpoint = URL(string: "https://api.openai.com/v1/images/edits")!
    private static let model = "gpt-image-1.5"

    let apiKey: String
    var name: String { "OpenAI" }

    @MainActor
    func edit(image: NSImage, prompt: String) async throws -> NSImage {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw PromptImageEditError.missingCredential(name) }
        guard let imageData = ImageRenderer.pngData(for: image) else {
            throw PromptImageEditError.imageEncodingFailed
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")

        let boundary = "ImageKid-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(
            fields: [
                "model": Self.model,
                "prompt": trimmedPrompt,
                "size": "auto",
                "quality": "medium",
                "output_format": "png"
            ],
            files: [
                MultipartFile(
                    fieldName: "image",
                    fileName: "imagekid-source.png",
                    mimeType: "image/png",
                    data: imageData
                )
            ],
            boundary: boundary
        )

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 300
        configuration.timeoutIntervalForResource = 420
        let session = URLSession(configuration: configuration)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw PromptImageEditError.timedOut
        }
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw PromptImageEditError.apiError(Self.apiErrorMessage(from: data) ?? "\(name) image editing failed.")
        }

        let editResponse = try JSONDecoder().decode(OpenAIImagesResponse.self, from: data)
        guard
            let base64 = editResponse.data?.first?.b64Json,
            let editedData = Data(base64Encoded: base64),
            let editedImage = NSImage(data: editedData)
        else {
            throw PromptImageEditError.invalidResponse(name)
        }

        return editedImage
    }

    private static func apiErrorMessage(from data: Data) -> String? {
        guard let response = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) else {
            return nil
        }
        return response.error.message
    }

    private static func multipartBody(
        fields: [String: String],
        files: [MultipartFile],
        boundary: String
    ) -> Data {
        var body = Data()

        for (name, value) in fields {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }

        for file in files {
            body.append("--\(boundary)\r\n")
            body.append(
                "Content-Disposition: form-data; name=\"\(file.fieldName)\"; filename=\"\(file.fileName)\"\r\n"
            )
            body.append("Content-Type: \(file.mimeType)\r\n\r\n")
            body.append(file.data)
            body.append("\r\n")
        }

        body.append("--\(boundary)--\r\n")
        return body
    }
}

private struct MultipartFile {
    let fieldName: String
    let fileName: String
    let mimeType: String
    let data: Data
}

private struct OpenAIImagesResponse: Decodable {
    let data: [OpenAIImageResponse]?
}

private struct OpenAIImageResponse: Decodable {
    let b64Json: String?

    enum CodingKeys: String, CodingKey {
        case b64Json = "b64_json"
    }
}

private struct OpenAIErrorResponse: Decodable {
    let error: OpenAIError
}

private struct OpenAIError: Decodable {
    let message: String
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}

@MainActor
struct WorkspaceItem: Identifiable {
    let id = UUID()
    var media: MediaItem

    var title: String {
        switch media {
        case .image(let session):
            return session.sourceURL?.lastPathComponent ?? "Pasted Image"
        case .video(let session):
            return session.sourceURL.lastPathComponent
        }
    }

    var isDirty: Bool {
        switch media {
        case .image(let session): session.isDirty
        case .video: false
        }
    }

    var thumbnail: NSImage? {
        switch media {
        case .image(let session): session.workingSourceImage
        case .video: nil
        }
    }
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
    static func pngData(for image: NSImage) -> Data? {
        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff)
        else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }

    static func render(_ session: ImageSession, options: ImageExportOptions = ImageExportOptions()) -> NSImage? {
        let targetSize = finalSize(for: session, options: options)
        return render(session, targetSize: targetSize, options: options, includesAnnotations: true)
    }

    static func renderedImage(
        for session: ImageSession,
        targetSize: CGSize,
        format: ImageExportFormat = .png,
        backgroundColor: NSColor = .white,
        upscaleEngine: UpscaleEngine = .standard,
        upscaleContentMode: UpscaleContentMode = .textAndUI
    ) throws -> NSImage {
        let naturalSize = session.croppedPixelSize
        let effectiveContentMode = ImageUpscaleService.resolvedContentMode(
            for: session.workingSourceImage,
            requestedMode: upscaleContentMode
        )
        let shouldUseBestQuality = upscaleEngine == .bestQuality
            && (effectiveContentMode == .textAndUI || ImageUpscaleService.isBestQualityRuntimeAvailable)
            && (targetSize.width > naturalSize.width || targetSize.height > naturalSize.height)

        let renderSize = shouldUseBestQuality ? naturalSize : targetSize
        let options = ImageExportOptions(format: format, backgroundColor: backgroundColor)
        guard var image = render(
            session,
            targetSize: renderSize,
            options: options,
            includesAnnotations: !shouldUseBestQuality
        ) else {
            throw ImageRenderError.renderFailed
        }

        if shouldUseBestQuality {
            image = try ImageUpscaleService.upscale(image, to: targetSize, contentMode: upscaleContentMode)
            return drawAnnotations(on: image, session: session, targetSize: targetSize)
        }

        if upscaleEngine == .bestQuality
            && (targetSize.width > naturalSize.width || targetSize.height > naturalSize.height) {
            throw ImageRenderError.upscaleRuntimeMissing
        }

        return image
    }

    static func renderUpscaleBase(
        for session: ImageSession,
        targetSize: CGSize,
        format: ImageExportFormat = .png,
        backgroundColor: NSColor = .white,
        upscaleEngine: UpscaleEngine,
        upscaleContentMode: UpscaleContentMode
    ) throws -> NSImage {
        let naturalSize = session.croppedPixelSize
        let effectiveContentMode = ImageUpscaleService.resolvedContentMode(
            for: session.workingSourceImage,
            requestedMode: upscaleContentMode
        )
        let shouldUseBestQuality = upscaleEngine == .bestQuality
            && (effectiveContentMode == .textAndUI || ImageUpscaleService.isBestQualityRuntimeAvailable)
            && (targetSize.width > naturalSize.width || targetSize.height > naturalSize.height)

        let renderSize = shouldUseBestQuality ? naturalSize : targetSize
        let options = ImageExportOptions(format: format, backgroundColor: backgroundColor)
        guard let image = render(
            session,
            targetSize: renderSize,
            options: options,
            includesAnnotations: !shouldUseBestQuality
        ) else {
            throw ImageRenderError.renderFailed
        }
        return image
    }

    /// Renders the current image at its natural (cropped) pixel size without
    /// annotations — the clean base an Enhance engine upscales, before annotations
    /// are redrawn at the enlarged size.
    static func renderEnhanceBase(for session: ImageSession, backgroundColor: NSColor = .white) throws -> NSImage {
        let options = ImageExportOptions(format: .png, backgroundColor: backgroundColor)
        guard let image = render(
            session,
            targetSize: session.croppedPixelSize,
            options: options,
            includesAnnotations: false
        ) else {
            throw ImageRenderError.renderFailed
        }
        return image
    }

    static func drawAnnotationsOnImage(_ image: NSImage, session: ImageSession, targetSize: CGSize) -> NSImage {
        drawAnnotations(on: image, session: session, targetSize: targetSize)
    }

    static func write(_ session: ImageSession, to url: URL, options: ImageExportOptions) throws {
        let targetSize = finalSize(for: session, options: options)
        guard let image = render(
            session,
            targetSize: targetSize,
            options: options,
            includesAnnotations: true
        ) else {
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
        } else if options.format.supportsCompression {
            properties[.compressionFactor] = options.pngCompression
        }

        guard let data = bitmap.representation(using: bitmapType, properties: properties) else {
            throw ImageRenderError.encodeFailed
        }
        try data.write(to: url, options: .atomic)
    }

    private static func finalSize(for session: ImageSession, options: ImageExportOptions) -> CGSize {
        let baseSize = session.effectivePixelSize
        return CGSize(
            width: max(1, baseSize.width.rounded()),
            height: max(1, baseSize.height.rounded())
        )
    }

    private static func render(
        _ session: ImageSession,
        targetSize: CGSize,
        options: ImageExportOptions,
        includesAnnotations: Bool
    ) -> NSImage? {
        guard let source = session.workingSourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let pixelCrop = CGRect(
            x: session.cropRect.minX * CGFloat(source.width),
            y: session.cropRect.minY * CGFloat(source.height),
            width: session.cropRect.width * CGFloat(source.width),
            height: session.cropRect.height * CGFloat(source.height)
        ).integral

        guard let cropped = source.cropping(to: pixelCrop) else { return nil }
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

        drawImageLayers(session: session, targetSize: targetSize)

        if includesAnnotations {
            drawAnnotations(session: session, targetSize: targetSize)
        }

        return result
    }

    private static func drawImageLayers(session: ImageSession, targetSize: CGSize) {
        let crop = session.cropRect
        for layer in session.imageLayers where session.isLayerEffectivelyVisible(layer) {
            let relativeFrame = CGRect(
                x: (layer.frame.minX - crop.minX) / crop.width,
                y: (layer.frame.minY - crop.minY) / crop.height,
                width: layer.frame.width / crop.width,
                height: layer.frame.height / crop.height
            )
            guard relativeFrame.maxX > 0, relativeFrame.maxY > 0,
                  relativeFrame.minX < 1, relativeFrame.minY < 1 else { continue }
            // Normalised frame uses a top-left origin; AppKit draws bottom-up.
            let rect = CGRect(
                x: relativeFrame.minX * targetSize.width,
                y: (1 - relativeFrame.maxY) * targetSize.height,
                width: relativeFrame.width * targetSize.width,
                height: relativeFrame.height * targetSize.height
            )
            if layer.rotation != 0 || layer.flipH || layer.flipV {
                NSGraphicsContext.current?.saveGraphicsState()
                let transform = NSAffineTransform()
                transform.translateX(by: rect.midX, yBy: rect.midY)
                if layer.rotation != 0 {
                    transform.rotate(byDegrees: -layer.rotation) // AppKit is CCW-positive; match SwiftUI CW.
                }
                transform.scaleX(by: layer.flipH ? -1 : 1, yBy: layer.flipV ? -1 : 1)
                transform.concat()
                layer.renderedImage.draw(
                    in: CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height),
                    from: .zero, operation: .sourceOver, fraction: layer.opacity
                )
                NSGraphicsContext.current?.restoreGraphicsState()
            } else {
                layer.renderedImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: layer.opacity)
            }
        }
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

    private static func drawAnnotations(on image: NSImage, session: ImageSession, targetSize: CGSize) -> NSImage {
        let result = image.copy() as? NSImage ?? image
        result.lockFocus()
        defer { result.unlockFocus() }
        drawAnnotations(session: session, targetSize: targetSize)
        return result
    }

    private static func drawAnnotations(session: ImageSession, targetSize: CGSize) {
        for annotation in session.annotations where annotation.isVisible {
            draw(annotation, cropRect: session.cropRect, sourceSize: session.pixelSize, targetSize: targetSize)
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
            let radius = annotation.cornerRadius * lineScale
            let shift = -annotation.strokeAlignment.edgeShift * lineWidth
            let strokeRect = rect.insetBy(dx: shift, dy: shift)
            let strokeRadius = max(0, radius + annotation.strokeAlignment.edgeShift * lineWidth)
            if let fill = annotation.fillColor {
                fill.setFill()
                roundedOutputPath(rect, radius: radius).fill()
            }
            let path = roundedOutputPath(strokeRect, radius: strokeRadius)
            stroke(path, annotation: annotation, lineWidth: lineWidth, scale: lineScale)

        case .ellipse:
            let shift = -annotation.strokeAlignment.edgeShift * lineWidth
            let strokeRect = rect.insetBy(dx: shift, dy: shift)
            if let fill = annotation.fillColor {
                fill.setFill()
                NSBezierPath(ovalIn: rect).fill()
            }
            stroke(NSBezierPath(ovalIn: strokeRect), annotation: annotation, lineWidth: lineWidth, scale: lineScale)

        case .line(let start, let end):
            let path = NSBezierPath()
            path.move(to: outputPoint(start, in: rect))
            path.line(to: outputPoint(end, in: rect))
            stroke(path, annotation: annotation, lineWidth: lineWidth, scale: lineScale)

        case .arrow(let start, let end):
            drawArrow(
                from: outputPoint(start, in: rect),
                to: outputPoint(end, in: rect),
                color: annotation.strokeColor,
                lineWidth: lineWidth,
                annotation: annotation,
                scale: lineScale
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
            stroke(path, annotation: annotation, lineWidth: lineWidth, scale: lineScale)

        case .text(let value):
            let scale = targetSize.width / max(sourceSize.width * cropRect.width, 1)
            let size = max(8, annotation.fontSize * scale)
            let font: NSFont
            if annotation.fontFamily.isEmpty {
                font = NSFont.systemFont(ofSize: size, weight: annotation.fontWeight.appKitWeight)
            } else {
                let weightedFont = NSFontManager.shared.font(
                    withFamily: annotation.fontFamily,
                    traits: [],
                    weight: annotation.fontWeight.fontManagerWeight,
                    size: size
                )
                let baseFont = NSFont(name: annotation.fontFamily, size: size)
                    ?? NSFont.systemFont(ofSize: size, weight: annotation.fontWeight.appKitWeight)
                font = weightedFont ?? baseFont
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = annotation.textAlignment.paragraphAlignment
            paragraph.minimumLineHeight = size * annotation.lineHeight
            paragraph.maximumLineHeight = size * annotation.lineHeight
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: annotation.strokeColor,
                .paragraphStyle: paragraph
            ]
            value.draw(in: rect, withAttributes: attributes)
        }
    }

    private static func roundedOutputPath(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
        guard radius > 0 else { return NSBezierPath(rect: rect) }
        let r = min(radius, min(abs(rect.width), abs(rect.height)) / 2)
        return NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
    }

    /// Stroke a shape/line path with the annotation's dash and colour.
    private static func stroke(_ path: NSBezierPath, annotation: Annotation, lineWidth: CGFloat, scale: CGFloat) {
        path.lineWidth = lineWidth
        applyDash(path, annotation: annotation, lineWidth: lineWidth, scale: scale)
        annotation.strokeColor.setStroke()
        path.stroke()
    }

    /// Plain stroke with an explicit colour (no dash) — used for arrow heads.
    private static func stroke(_ path: NSBezierPath, color: NSColor, lineWidth: CGFloat) {
        path.lineWidth = lineWidth
        color.setStroke()
        path.stroke()
    }

    private static func applyDash(_ path: NSBezierPath, annotation: Annotation, lineWidth: CGFloat, scale: CGFloat) {
        let pattern = annotation.effectiveDash(lineWidth: annotation.lineWidth, scale: scale)
        guard !pattern.isEmpty else { return }
        if annotation.dashLength <= 0 && annotation.strokeStyle == .dotted { path.lineCapStyle = .round }
        path.setLineDash(pattern, count: pattern.count, phase: annotation.dashOffset * scale)
    }

    private static func outputPoint(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + point.x * rect.width,
            y: rect.maxY - point.y * rect.height
        )
    }

    private static func drawArrow(from start: CGPoint, to end: CGPoint, color: NSColor, lineWidth: CGFloat, annotation: Annotation, scale: CGFloat) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        stroke(path, annotation: annotation, lineWidth: lineWidth, scale: scale)

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
    case upscaleRuntimeMissing

    var errorDescription: String? {
        switch self {
        case .renderFailed: "The image could not be rendered."
        case .encodeFailed: "The image could not be encoded."
        case .upscaleRuntimeMissing: "Best Quality is not ready yet. Turn it on in Settings > Upscale."
        }
    }
}
