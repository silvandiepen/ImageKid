import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum CompanionImageIO {
    static let readableTypes: [UTType] = [.jpeg, .png, .webP, .tiff, .gif, .heic, .bmp]

    static func loadImage(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw CompanionProcessingError.unreadableImage
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            throw CompanionProcessingError.unreadableImage
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height)
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw CompanionProcessingError.unreadableImage
        }
        return image
    }

    static func properties(at url: URL) -> (width: Int, height: Int)? {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            return nil
        }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if [5, 6, 7, 8].contains(orientation) {
            return (height, width)
        }
        return (width, height)
    }

    static func thumbnail(at url: URL, maxPixelSize: CGFloat = 128) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        try write(image, to: url, type: UTType.png.identifier as CFString, options: [:])
    }

    static func writeJPEG(_ image: CGImage, to url: URL, quality: Double = 0.92) throws {
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: max(0.0, min(1.0, quality))
        ]
        try write(image, to: url, type: UTType.jpeg.identifier as CFString, options: options)
    }

    static func destinationURL(
        for source: URL,
        operationFolderName: String,
        suffix: String,
        extension preferredExtension: String,
        customFolder: URL?,
        overwriteOriginals: Bool
    ) throws -> URL {
        if overwriteOriginals, source.pathExtension.lowercased() == preferredExtension.lowercased() {
            return source
        }

        let directory: URL
        if let customFolder {
            directory = customFolder
        } else {
            directory = source.deletingLastPathComponent().appendingPathComponent(operationFolderName, isDirectory: true)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let baseName = source.deletingPathExtension().lastPathComponent + suffix
        var candidate = directory.appendingPathComponent(baseName).appendingPathExtension(preferredExtension)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-\(counter)").appendingPathExtension(preferredExtension)
            counter += 1
        }
        return candidate
    }

    private static func write(
        _ image: CGImage,
        to url: URL,
        type: CFString,
        options: [CFString: Any]
    ) throws {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let temporaryURL = directory.appendingPathComponent(
            ".\(url.lastPathComponent).\(UUID().uuidString).tmp"
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }

        guard let destination = CGImageDestinationCreateWithURL(temporaryURL as CFURL, type, 1, nil) else {
            throw CompanionProcessingError.cannotWriteImage
        }
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CompanionProcessingError.cannotWriteImage
        }

        do {
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: url)
            }
        } catch {
            throw CompanionProcessingError.cannotWriteImage
        }
    }
}

enum CompanionProcessingError: LocalizedError {
    case unreadableImage
    case cannotWriteImage
    case cancelled
    case modelMissing(String)

    var errorDescription: String? {
        switch self {
        case .unreadableImage: "That image could not be opened."
        case .cannotWriteImage: "The finished image could not be written."
        case .cancelled: "The batch was stopped."
        case .modelMissing(let message): message
        }
    }
}
