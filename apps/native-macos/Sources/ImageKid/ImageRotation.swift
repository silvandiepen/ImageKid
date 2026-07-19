import AppKit

/// Bakes a rotation/flip into a flattened image. Rotation is destructive by design
/// (see the feature plan): the caller renders the current image, rotates the bitmap,
/// and installs the result as a fresh session.
enum ImageRotator {
    /// - Parameters:
    ///   - degrees: clockwise rotation, as shown in the UI.
    ///   - resizeCanvas: expand the canvas to the rotated bounding box; otherwise keep
    ///     the original pixel dimensions and let the corners clip.
    ///   - fillColor: solid colour for the empty corners; `nil` leaves them transparent.
    static func rotate(
        _ image: NSImage,
        degrees: Double,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        resizeCanvas: Bool = true,
        fillColor: NSColor? = nil
    ) -> NSImage? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let srcW = CGFloat(source.width)
        let srcH = CGFloat(source.height)

        // Core Graphics rotates counter-clockwise for positive angles; the UI is clockwise.
        let radians = -degrees * .pi / 180
        let absCos = abs(cos(radians))
        let absSin = abs(sin(radians))

        let canvasW: Int
        let canvasH: Int
        if resizeCanvas {
            canvasW = max(1, Int((srcW * absCos + srcH * absSin).rounded()))
            canvasH = max(1, Int((srcW * absSin + srcH * absCos).rounded()))
        } else {
            canvasW = max(1, Int(srcW))
            canvasH = max(1, Int(srcH))
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: canvasW,
            height: canvasH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high

        if let fillColor, let rgb = fillColor.usingColorSpace(.sRGB) {
            context.setFillColor(
                red: rgb.redComponent,
                green: rgb.greenComponent,
                blue: rgb.blueComponent,
                alpha: rgb.alphaComponent
            )
            context.fill(CGRect(x: 0, y: 0, width: canvasW, height: canvasH))
        }

        context.translateBy(x: CGFloat(canvasW) / 2, y: CGFloat(canvasH) / 2)
        context.rotate(by: radians)
        context.scaleBy(x: flipHorizontal ? -1 : 1, y: flipVertical ? -1 : 1)
        context.draw(source, in: CGRect(x: -srcW / 2, y: -srcH / 2, width: srcW, height: srcH))

        guard let rotated = context.makeImage() else { return nil }
        return NSImage(cgImage: rotated, size: NSSize(width: canvasW, height: canvasH))
    }
}
