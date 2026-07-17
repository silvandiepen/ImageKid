import AppKit

enum BackgroundMaskEditor {
    static func applyBrush(
        to image: NSImage,
        sourceImage: NSImage,
        normalizedPoint: CGPoint,
        diameter: CGFloat,
        softness: CGFloat,
        strength: CGFloat,
        mode: BackgroundRefinementMode
    ) -> NSImage? {
        guard
            let targetCG = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let sourceCG = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return nil
        }

        guard
            let target = rgbaBitmap(from: targetCG),
            let source = rgbaBitmap(from: sourceCG)
        else {
            return nil
        }

        let width = target.pixelsWide
        let height = target.pixelsHigh
        guard width > 0, height > 0 else { return nil }

        let centerX = min(max(Int(normalizedPoint.x * CGFloat(width)), 0), width - 1)
        let centerY = min(max(Int(normalizedPoint.y * CGFloat(height)), 0), height - 1)
        let radius = max(1, Int((diameter / 2).rounded()))
        let radiusValue = CGFloat(radius)
        let innerRadius = radiusValue * (1 - min(max(softness, 0), 0.95))
        let clampedStrength = min(max(strength, 0), 1)

        for y in max(0, centerY - radius)...min(height - 1, centerY + radius) {
            for x in max(0, centerX - radius)...min(width - 1, centerX + radius) {
                let dx = CGFloat(x - centerX)
                let dy = CGFloat(y - centerY)
                let distance = hypot(dx, dy)
                guard distance <= radiusValue else { continue }

                let falloff: CGFloat
                if distance <= innerRadius {
                    falloff = 1
                } else {
                    let t = (distance - innerRadius) / max(radiusValue - innerRadius, 1)
                    falloff = 1 - smoothstep(t)
                }
                let amount = falloff * clampedStrength

                switch mode {
                case .remove:
                    let existing = target.colorAt(x: x, y: y) ?? .clear
                    let alpha = existing.alphaComponent * (1 - amount)
                    target.setColor(
                        NSColor(
                            calibratedRed: existing.redComponent,
                            green: existing.greenComponent,
                            blue: existing.blueComponent,
                            alpha: alpha
                        ),
                        atX: x,
                        y: y
                    )

                case .keep:
                    let sourceX = min(max(Int(CGFloat(x) / CGFloat(width) * CGFloat(source.pixelsWide)), 0), source.pixelsWide - 1)
                    let sourceY = min(max(Int(CGFloat(y) / CGFloat(height) * CGFloat(source.pixelsHigh)), 0), source.pixelsHigh - 1)
                    let restored = source.colorAt(x: sourceX, y: sourceY) ?? .clear
                    let existing = target.colorAt(x: x, y: y) ?? .clear
                    let alpha = existing.alphaComponent + (1 - existing.alphaComponent) * amount
                    target.setColor(restored.withAlphaComponent(alpha), atX: x, y: y)
                }
            }
        }

        let result = NSImage(size: image.size)
        result.addRepresentation(target)
        return result
    }

    private static func rgbaBitmap(from image: CGImage) -> NSBitmapImageRep? {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: image.width,
            pixelsHigh: image.height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: image.width * 4,
            bitsPerPixel: 32
        ) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(
            cgImage: image,
            size: CGSize(width: image.width, height: image.height)
        )
        .draw(
            in: CGRect(x: 0, y: 0, width: image.width, height: image.height),
            from: .zero,
            operation: .copy,
            fraction: 1
        )

        return bitmap
    }

    private static func smoothstep(_ value: CGFloat) -> CGFloat {
        let x = min(max(value, 0), 1)
        return x * x * (3 - 2 * x)
    }
}
