import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// Real image fixtures — generated, encoded, and read back through Image I/O,
/// so the tests exercise the same path the app does.
enum TestImages {
    struct Pixel: Equatable {
        let red: Int
        let green: Int
        let blue: Int
        let alpha: Int
    }

    /// Opaque red on the left half, blue on the right.
    static func halves(width: Int, height: Int) throws -> CGImage {
        try draw(width: width, height: height) { context in
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
            context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
            context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        }
    }

    /// Fully transparent on the left half, opaque green on the right.
    static func transparentLeftHalf(width: Int, height: Int) throws -> CGImage {
        try draw(width: width, height: height) { context in
            context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
            context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        }
    }

    static func write(
        _ image: CGImage,
        as type: UTType,
        to url: URL,
        orientation: CGImagePropertyOrientation? = nil
    ) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            type.identifier as CFString,
            1,
            nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }

        var properties: [CFString: Any] = [:]
        if let orientation {
            properties[kCGImagePropertyOrientation] = orientation.rawValue
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    static func load(_ url: URL) throws -> CGImage {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw CocoaError(.fileReadUnknown)
        }
        return image
    }

    /// The pixel at the centre of the image, read back through a known
    /// straight-alpha RGBA buffer.
    static func centrePixel(_ image: CGImage) throws -> Pixel {
        var bytes = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &bytes,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CocoaError(.fileReadUnknown)
        }

        // Draw the image scaled so that its centre pixel lands in the 1×1
        // context without sampling its neighbours.
        context.draw(
            image,
            in: CGRect(
                x: -CGFloat(image.width / 2),
                y: -CGFloat(image.height / 2),
                width: CGFloat(image.width),
                height: CGFloat(image.height)
            )
        )

        return Pixel(red: Int(bytes[0]), green: Int(bytes[1]), blue: Int(bytes[2]), alpha: Int(bytes[3]))
    }

    private static func draw(width: Int, height: Int, _ body: (CGContext) -> Void) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        body(context)
        guard let image = context.makeImage() else {
            throw CocoaError(.fileWriteUnknown)
        }
        return image
    }
}
