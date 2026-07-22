//
//  Platform.swift
//  Cross-platform primitives so the shared core works on macOS (AppKit) and
//  iOS (UIKit). ImageKid's model and document layers use these instead of
//  NSImage/NSColor directly, so both apps can share one core.
//

import CoreGraphics
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
