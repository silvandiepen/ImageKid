import CoreGraphics
import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers

/// The image formats the iOS app can export.
enum ExportFormat: String, CaseIterable, Identifiable {
    case png
    case jpeg
    case heic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .heic: return "HEIC"
        }
    }

    var utType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .heic: return .heic
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .heic: return "heic"
        }
    }

    /// PNG is lossless and keeps alpha; the others take a quality value and
    /// flatten transparency.
    var supportsQuality: Bool { self != .png }
    var preservesTransparency: Bool { self == .png }
}

enum ImageExporter {
    /// Encodes a `CGImage` to the given format. `quality` is ignored for PNG.
    /// Formats without alpha are flattened onto white first.
    static func encode(_ image: CGImage, format: ExportFormat, quality: CGFloat) -> Data? {
        let prepared = format.preservesTransparency ? image : flattenOnWhite(image)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            format.utType.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, prepared, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private static func flattenOnWhite(_ image: CGImage) -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return image
        }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage() ?? image
    }

    /// Encodes and writes to a temporary file, returning its URL (for sharing or
    /// saving to Photos).
    static func writeTemporary(
        _ image: CGImage,
        format: ExportFormat,
        quality: CGFloat,
        name: String = "ImageKid"
    ) -> URL? {
        guard let data = encode(image, format: format, quality: quality) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString).\(format.fileExtension)")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

enum PhotoSaverError: LocalizedError {
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "ImageKid needs permission to add photos. Enable it in Settings > Photos."
        }
    }
}

enum PhotoSaver {
    /// Saves a file to the photo library, requesting add-only access first.
    static func save(fileURL: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw PhotoSaverError.notAuthorized
        }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: fileURL, options: nil)
        }
    }
}
