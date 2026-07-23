//
//  Platform.swift
//  Cross-platform primitives so the shared core works on macOS (AppKit) and
//  iOS (UIKit). ImageKid's model and document layers use these instead of
//  NSImage/NSColor directly, so both apps can share one core.
//

import CoreGraphics
import CoreImage
import Foundation

#if canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
public typealias PlatformColor = NSColor
#elseif canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
public typealias PlatformColor = UIColor
#endif

// MARK: - Rendering bridges

public extension PlatformImage {
    /// The backing CGImage, resolved on both platforms.
    var cgImageForRendering: CGImage? {
        #if canImport(AppKit)
        return cgImage(forProposedRect: nil, context: nil, hints: nil)
        #elseif canImport(UIKit)
        return cgImage
        #else
        return nil
        #endif
    }

    /// Wrap a CGImage in a platform image at the given point size.
    static func fromCGImage(_ cgImage: CGImage, size: CGSize) -> PlatformImage {
        #if canImport(AppKit)
        return NSImage(cgImage: cgImage, size: size)
        #elseif canImport(UIKit)
        return UIImage(cgImage: cgImage)
        #else
        return PlatformImage()
        #endif
    }
}

/// Shared CoreImage/CoreGraphics rendering utilities used by the mask engine.
public enum PlatformRender {
    /// Shared GPU-backed CoreImage context.
    public static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Render a CIImage into a platform image at the given point size.
    public static func image(from ciImage: CIImage, size: CGSize, cropTo extent: CGRect? = nil) -> PlatformImage? {
        let bounds = extent ?? ciImage.extent
        guard let cg = ciContext.createCGImage(ciImage, from: bounds) else { return nil }
        return .fromCGImage(cg, size: size)
    }

    /// Draw into an image with a bottom-left origin, y-up CoreGraphics context —
    /// matching AppKit's `NSImage.lockFocus` convention on both platforms.
    public static func image(size: CGSize, _ draw: (CGContext) -> Void) -> PlatformImage {
        #if canImport(AppKit)
        let image = NSImage(size: size)
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            draw(ctx)
        }
        image.unlockFocus()
        return image
        #elseif canImport(UIKit)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { rendererContext in
            let ctx = rendererContext.cgContext
            // Flip UIKit's top-left origin to bottom-left y-up to match AppKit.
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1, y: -1)
            draw(ctx)
        }
        #else
        return PlatformImage()
        #endif
    }
}

public extension PlatformColor {
    /// Construct a color in the sRGB space on both platforms.
    static func sRGB(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> PlatformColor {
        #if canImport(AppKit)
        return PlatformColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
        #elseif canImport(UIKit)
        return PlatformColor(red: red, green: green, blue: blue, alpha: alpha)
        #else
        return PlatformColor()
        #endif
    }

    /// sRGB (red, green, blue, alpha) components in 0…1, resolved on both platforms.
    var sRGBComponents: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        #if canImport(AppKit)
        let c = usingColorSpace(.sRGB) ?? self
        return (c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
        #elseif canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
        #else
        return (0, 0, 0, 1)
        #endif
    }
}

public enum PlatformImageCoding {
    /// Encode an image as base64-encoded PNG (used by the .imagekid format).
    public static func pngBase64(_ image: PlatformImage) -> String? {
        pngData(image)?.base64EncodedString()
    }

    public static func image(fromBase64 string: String?) -> PlatformImage? {
        guard let string, let data = Data(base64Encoded: string) else { return nil }
        return PlatformImage(data: data)
    }

    public static func pngData(_ image: PlatformImage) -> Data? {
        #if canImport(AppKit)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
        #elseif canImport(UIKit)
        return image.pngData()
        #else
        return nil
        #endif
    }
}
