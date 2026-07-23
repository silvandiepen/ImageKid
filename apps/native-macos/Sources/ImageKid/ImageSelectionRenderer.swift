import AppKit
import ImageKidCore

enum ImageSelectionRenderer {
    static func crop(_ image: NSImage, normalizedRect: CGRect) -> NSImage? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let rect = GeometryMapper.clampedNormalizedRect(normalizedRect)
        let pixelRect = CGRect(
            x: rect.minX * CGFloat(source.width),
            y: rect.minY * CGFloat(source.height),
            width: rect.width * CGFloat(source.width),
            height: rect.height * CGFloat(source.height)
        ).integral

        guard let cropped = source.cropping(to: pixelRect) else { return nil }
        return NSImage(cgImage: cropped, size: CGSize(width: cropped.width, height: cropped.height))
    }
}
