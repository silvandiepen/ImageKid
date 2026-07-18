import CoreGraphics
import CoreImage
import CoreVideo
import Foundation

/// Cross-platform image helpers shared by the engines. Everything is expressed
/// in `CGImage` and `CVPixelBuffer` so the package never imports AppKit or
/// UIKit and works unchanged on macOS and iOS.
enum ImageConversion {
    /// A shared, GPU-backed Core Image context for encode/decode work.
    static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// Draws `image` into a freshly allocated 32BGRA `CVPixelBuffer` of the given
    /// size, scaling to fill. Suitable as a Core ML image input.
    static func makeBGRAPixelBuffer(from image: CGImage, width: Int, height: Int) -> CVPixelBuffer? {
        makePixelBuffer(width: width, height: height, pixelFormat: kCVPixelFormatType_32BGRA) { context in
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// Allocates a `CVPixelBuffer` and lets `draw` render into a `CGContext`
    /// backed by it. Returns `nil` if allocation or context creation fails.
    static func makePixelBuffer(
        width: Int,
        height: Int,
        pixelFormat: OSType,
        draw: (CGContext) -> Void
    ) -> CVPixelBuffer? {
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]

        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            pixelFormat,
            attributes as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer = buffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard
            let base = CVPixelBufferGetBaseAddress(pixelBuffer),
            let context = CGContext(
                data: base,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: sRGB,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            )
        else {
            return nil
        }

        draw(context)
        return pixelBuffer
    }

    /// Renders a `CVPixelBuffer` back into a `CGImage`.
    static func makeCGImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        return ciContext.createCGImage(ciImage, from: ciImage.extent)
    }

    /// Resizes `image` to an exact pixel size with high-quality interpolation.
    static func resize(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        let safeWidth = max(1, width)
        let safeHeight = max(1, height)
        guard let context = CGContext(
            data: nil,
            width: safeWidth,
            height: safeHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: safeWidth, height: safeHeight))
        return context.makeImage()
    }

    /// Crops a pixel rectangle out of `image`, clamped to the image bounds.
    static func crop(_ image: CGImage, to rect: CGRect) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let clamped = rect.intersection(bounds).integral
        guard !clamped.isEmpty else { return nil }
        return image.cropping(to: clamped)
    }
}
