import AppKit
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Decoding, orientation normalisation, and encoding for Slicer.
///
/// Deliberately separate from `CompanionSupport`: the batch companions carry a
/// queue model and an inference dependency that Slicer has no use for.
enum SliceImageIO {
    static let readableTypes: [UTType] = [.png, .jpeg, .heic, .heif, .tiff, .gif, .bmp, .webP]

    /// Types we can hand straight back to Image I/O. Anything else falls back
    /// to PNG so a slice is never silently re-encoded into a format the
    /// destination cannot represent.
    private static let writableTypes: Set<String> = [
        UTType.png.identifier,
        UTType.jpeg.identifier,
        UTType.heic.identifier,
        UTType.tiff.identifier
    ]

    // MARK: - Loading

    /// Decode a source image with its EXIF orientation baked in, so every
    /// coordinate downstream is in the orientation the user actually sees.
    static func loadOrientedImage(from source: CGImageSource) throws -> CGImage {
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: true] as CFDictionary) else {
            throw SliceError.unreadableImage
        }

        let orientation = orientation(of: source)
        guard orientation != .up else { return image }

        let oriented = CIImage(cgImage: image).oriented(orientation)
        guard let rendered = CIContext(options: [.useSoftwareRenderer: false])
            .createCGImage(oriented, from: oriented.extent) else {
            throw SliceError.unreadableImage
        }
        return rendered
    }

    static func imageSource(at url: URL) throws -> CGImageSource {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw SliceError.unreadableImage
        }
        return source
    }

    static func orientation(of source: CGImageSource) -> CGImagePropertyOrientation {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let raw = properties[kCGImagePropertyOrientation] as? UInt32,
            let orientation = CGImagePropertyOrientation(rawValue: raw)
        else {
            return .up
        }
        return orientation
    }

    /// A display-sized copy for the canvas. Dragging rectangles must never pay
    /// for re-decoding the full-resolution source.
    static func preview(from source: CGImageSource, maxPixelSize: CGFloat) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The type a slice of this source should be written as, and the file
    /// extension that goes with it.
    static func outputType(for source: CGImageSource) -> (type: UTType, fileExtension: String) {
        if
            let identifier = CGImageSourceGetType(source) as String?,
            writableTypes.contains(identifier),
            let type = UTType(identifier),
            let ext = type.preferredFilenameExtension
        {
            return (type, ext)
        }
        return (.png, "png")
    }

    // MARK: - Writing

    /// Draw a cropped region as the export options ask for it: at its own
    /// size, scaled by a percentage, or fitted into a fixed output.
    ///
    /// Fixed output is what makes a set of differently-shaped slices usable as
    /// one set of assets — every file the same width and height, with the
    /// slice either contained inside it or covering it.
    static func rendered(_ image: CGImage, options: ExportOptions) throws -> CGImage {
        guard options.needsResampling else { return image }

        let source = CGSize(width: image.width, height: image.height)
        let output = options.outputPixelSize(for: CGRect(origin: .zero, size: source))

        switch options.sizing {
        case .actual:
            return try scaled(image, to: output)
        case .fixed:
            return try fitted(
                image,
                into: output,
                fit: options.fit,
                background: options.padding.color
            )
        }
    }

    /// Redraw an image into an exact canvas, contained or covering.
    static func fitted(
        _ image: CGImage,
        into size: CGSize,
        fit: ExportOptions.Fit,
        background: CGColor?
    ) throws -> CGImage {
        let width = Int(max(size.width.rounded(), 1))
        let height = Int(max(size.height.rounded(), 1))

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw SliceError.cannotWriteImage
        }

        if let background {
            context.setFillColor(background)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }

        context.interpolationQuality = .high
        // Cover deliberately draws beyond the canvas; the context clips it.
        context.draw(image, in: ExportOptions.drawRect(
            for: CGSize(width: image.width, height: image.height),
            in: CGSize(width: width, height: height),
            fit: fit
        ))

        guard let rendered = context.makeImage() else { throw SliceError.cannotWriteImage }
        return rendered
    }

    /// Resample a cropped region. Only called when the export is scaled, so
    /// an unscaled export never pays for a redraw.
    static func scaled(_ image: CGImage, to size: CGSize) throws -> CGImage {
        let width = Int(max(size.width.rounded(), 1))
        let height = Int(max(size.height.rounded(), 1))
        guard width != image.width || height != image.height else { return image }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw SliceError.cannotWriteImage
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let resampled = context.makeImage() else { throw SliceError.cannotWriteImage }
        return resampled
    }

    /// Write one slice, temporary-file-first so a failure never leaves a
    /// half-written image sitting where a good one should be.
    ///
    /// `quality` is passed only for the lossy formats; Image I/O ignores it
    /// elsewhere, but sending it anyway would be misleading.
    static func writeAtomically(_ image: CGImage, to url: URL, type: UTType, quality: Double? = nil) throws {
        let directory = url.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".\(UUID().uuidString).\(url.pathExtension)")

        guard let destination = CGImageDestinationCreateWithURL(
            temporary as CFURL,
            type.identifier as CFString,
            1,
            nil
        ) else {
            throw SliceError.cannotWriteImage
        }

        var properties: [CFString: Any] = [:]
        if let quality {
            properties[kCGImageDestinationLossyCompressionQuality] = max(0, min(1, quality))
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: temporary)
            throw SliceError.cannotWriteImage
        }

        do {
            try FileManager.default.moveItem(at: temporary, to: url)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
}

enum SliceError: LocalizedError {
    case unreadableImage
    case cannotWriteImage
    case emptySlice
    case noSlices
    case unreadableSession

    var errorDescription: String? {
        switch self {
        case .unreadableImage: "That image could not be opened."
        case .cannotWriteImage: "The slice could not be written."
        case .emptySlice: "That slice is too small to export."
        case .noSlices: "Draw at least one slice first."
        case .unreadableSession: "That session was saved by a newer version of Slicer."
        }
    }
}
