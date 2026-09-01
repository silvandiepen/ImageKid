import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageFileError: LocalizedError {
    case unreadable(URL)
    case unwritable(URL)

    var errorDescription: String? {
        switch self {
        case .unreadable(let url): "Could not read \(url.lastPathComponent)."
        case .unwritable(let url): "Could not write \(url.path)."
        }
    }
}

enum ImageFile {
    static let extensions: Set<String> = ["jpg", "jpeg", "png", "webp", "tif", "tiff", "gif", "heic", "bmp"]

    static func read(_ url: URL) throws -> CGImage {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(
                source,
                0,
                [kCGImageSourceShouldCache: true] as CFDictionary
            )
        else {
            throw ImageFileError.unreadable(url)
        }
        return image
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else {
            throw ImageFileError.unwritable(url)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageFileError.unwritable(url)
        }
    }
}
