import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum CompanionImageIO {
    static let readableTypes: [UTType] = [.jpeg, .png, .webP, .tiff, .gif, .heic, .bmp]

    /// Reads the file into memory and decodes it there and then.
    ///
    /// A `CGImage` made from a URL decodes lazily, so its pixels are pulled from disk
    /// long after this returns. If the file moves in between — which a When Done action
    /// does on purpose — the decode quietly yields black instead of failing, and a batch
    /// writes out perfectly-masked black silhouettes. Holding the bytes makes that
    /// impossible: either the image is real, or this throws.
    static func loadImage(at url: URL) throws -> CGImage {
        guard let data = try? Data(contentsOf: url) else {
            throw CompanionProcessingError.sourceMissing(url.lastPathComponent)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
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

    /// Creates the folder a file is about to be written into.
    static func prepareDirectory(for url: URL) throws {
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw CompanionProcessingError.destinationNotWritable(directory.lastPathComponent)
        }
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

    /// Where a run would write this source, with no side effects and no collision
    /// avoidance. This is the path the queue checks against to say "already there".
    static func plannedDestinationURL(
        for source: URL,
        operationFolderName: String,
        suffix: String,
        extension preferredExtension: String,
        customFolder: URL?,
        overwriteOriginals: Bool
    ) -> URL {
        if overwriteOriginals, source.pathExtension.lowercased() == preferredExtension.lowercased() {
            return source
        }

        let directory = customFolder
            ?? source.deletingLastPathComponent().appendingPathComponent(operationFolderName, isDirectory: true)

        // The suffix only earns its place when the result would sit next to the original.
        // In a folder of its own the plain name is what anyone wants to work with.
        let sourceDirectory = source.deletingLastPathComponent().standardizedFileURL
        let landsBesideSource = directory.standardizedFileURL == sourceDirectory
        let baseName = source.deletingPathExtension().lastPathComponent + (landsBesideSource ? suffix : "")
        return directory.appendingPathComponent(baseName).appendingPathExtension(preferredExtension)
    }

    /// The planned path, with its folder created. Unless `overwriteExisting` is set, an
    /// occupied path is stepped to `name-2`, `name-3`, … so nothing is clobbered by accident.
    static func destinationURL(
        for source: URL,
        operationFolderName: String,
        suffix: String,
        extension preferredExtension: String,
        customFolder: URL?,
        overwriteOriginals: Bool,
        overwriteExisting: Bool = false
    ) throws -> URL {
        let planned = plannedDestinationURL(
            for: source,
            operationFolderName: operationFolderName,
            suffix: suffix,
            extension: preferredExtension,
            customFolder: customFolder,
            overwriteOriginals: overwriteOriginals
        )
        guard planned != source else { return source }

        let directory = planned.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw CompanionProcessingError.destinationNotWritable(directory.lastPathComponent)
        }
        guard !overwriteExisting else { return planned }
        return uniqueURL(for: planned)
    }

    /// Steps `name` to `name-2`, `name-3`, ... until the path is free, so nothing on disk
    /// is clobbered by accident.
    static func uniqueURL(for planned: URL, fileManager: FileManager = .default) -> URL {
        guard fileManager.fileExists(atPath: planned.path) else { return planned }

        let directory = planned.deletingLastPathComponent()
        let baseName = planned.deletingPathExtension().lastPathComponent
        let ext = planned.pathExtension
        var counter = 2
        while true {
            var candidate = directory.appendingPathComponent("\(baseName)-\(counter)")
            if !ext.isEmpty {
                candidate = candidate.appendingPathExtension(ext)
            }
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
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

        let replacesExistingFile = fileManager.fileExists(atPath: url.path)
        // A Powerbox grant for an opened file permits replacing that file, but
        // does not permit creating an arbitrary hidden sibling. Stage explicit
        // overwrites in the app container and coordinate the replacement.
        let stagingDirectory = replacesExistingFile ? fileManager.temporaryDirectory : directory
        let temporaryURL = stagingDirectory.appendingPathComponent(
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
            if replacesExistingFile {
                try coordinatedReplaceItem(at: url, with: temporaryURL, fileManager: fileManager)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: url)
            }
        } catch {
            throw CompanionProcessingError.cannotWriteImage
        }
    }

    private static func coordinatedReplaceItem(
        at destinationURL: URL,
        with replacementURL: URL,
        fileManager: FileManager
    ) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var replacementError: Error?
        coordinator.coordinate(
            writingItemAt: destinationURL,
            options: .forReplacing,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                _ = try fileManager.replaceItemAt(coordinatedURL, withItemAt: replacementURL)
            } catch {
                replacementError = error
            }
        }
        if let error = replacementError ?? coordinationError {
            throw error
        }
    }
}

enum CompanionProcessingError: LocalizedError {
    case unreadableImage
    case cannotWriteImage
    case cancelled
    case modelMissing(String)
    case destinationNotWritable(String)
    case sourceMissing(String)

    var errorDescription: String? {
        switch self {
        case .unreadableImage: "That image could not be opened."
        case .cannotWriteImage: "The finished image could not be written."
        case .cancelled: "The batch was stopped."
        case .modelMissing(let message): message
        case .sourceMissing(let name):
            "\u{201C}\(name)\u{201D} is no longer where it was, so it could not be read."
        case .destinationNotWritable(let folder):
            "No permission to write into \u{201C}\(folder)\u{201D}. Choose an output folder under Destination."
        }
    }
}
