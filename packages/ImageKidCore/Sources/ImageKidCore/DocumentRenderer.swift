import CoreGraphics
import CoreText
import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Flattens an `ImageKidDocument` (or a live model triple) into a single image,
/// portably on macOS and iOS. This is the shared compositor: base image, then
/// image layers (with masks, rotation, flip, opacity), then vector annotations
/// (shapes via CoreGraphics, text via CoreText). It mirrors the macOS export
/// renderer so a document composites the same on both platforms.
public enum DocumentRenderer {
    /// Flatten a decoded document to an image at its cropped natural pixel size.
    public static func flatten(_ document: ImageKidDocument) -> PlatformImage? {
        guard let baseImage = IKImageCoder.decode(document.baseImage),
              let sourceCG = baseImage.cgImageForRendering else { return nil }

        let working = IKImageCoder.decode(document.backgroundRemovedImage)?.cgImageForRendering ?? sourceCG
        let crop = document.cropRect.cg
        let sourceSize = CGSize(width: sourceCG.width, height: sourceCG.height)

        let pixelCrop = CGRect(
            x: crop.minX * CGFloat(working.width),
            y: crop.minY * CGFloat(working.height),
            width: crop.width * CGFloat(working.width),
            height: crop.height * CGFloat(working.height)
        ).integral
        guard let cropped = working.cropping(to: pixelCrop) else { return nil }
        let targetSize = CGSize(width: cropped.width, height: cropped.height)

        let layers = document.imageLayers.compactMap(\.layer)
        let annotations = document.annotations.map(\.annotation)

        return render(
            base: (document.baseUnlocked ?? false) ? nil : cropped,
            targetSize: targetSize,
            crop: crop,
            sourceSize: sourceSize,
            layers: layers,
            annotations: annotations
        )
    }

    /// Core compositor over a CoreGraphics (bottom-left, y-up) context.
    public static func render(
        base cropped: CGImage?,
        targetSize: CGSize,
        crop: CGRect,
        sourceSize: CGSize,
        layers: [ImageLayer],
        annotations: [Annotation]
    ) -> PlatformImage {
        PlatformRender.image(size: targetSize) { ctx in
            let full = CGRect(origin: .zero, size: targetSize)
            ctx.interpolationQuality = .high
            if let cropped {
                ctx.draw(cropped, in: full)
            }
            for layer in layers.sorted(by: { $0.z < $1.z }) where layer.isVisible {
                drawLayer(layer, crop: crop, targetSize: targetSize, in: ctx)
            }
            for annotation in annotations.sorted(by: { $0.z < $1.z }) where annotation.isVisible {
                drawAnnotation(annotation, crop: crop, sourceSize: sourceSize, targetSize: targetSize, in: ctx)
            }
        }
    }

    // MARK: - Layers

    private static func drawLayer(_ layer: ImageLayer, crop: CGRect, targetSize: CGSize, in ctx: CGContext) {
        let relative = CGRect(
            x: (layer.frame.minX - crop.minX) / crop.width,
            y: (layer.frame.minY - crop.minY) / crop.height,
            width: layer.frame.width / crop.width,
            height: layer.frame.height / crop.height
        )
        guard relative.maxX > 0, relative.maxY > 0, relative.minX < 1, relative.minY < 1 else { return }

        let rect = CGRect(
            x: relative.minX * targetSize.width,
            y: (1 - relative.maxY) * targetSize.height,
            width: relative.width * targetSize.width,
            height: relative.height * targetSize.height
        )

        let composited: PlatformImage
        if layer.isMaskEnabled, let mask = layer.mask,
           let masked = MaskCompositor.apply(mask: mask, to: layer.image) {
            composited = masked
        } else {
            composited = layer.image
        }
        guard let cg = composited.cgImageForRendering else { return }

        ctx.saveGState()
        ctx.setAlpha(CGFloat(layer.opacity))
        if layer.rotation != 0 || layer.flipH || layer.flipV {
            ctx.translateBy(x: rect.midX, y: rect.midY)
            if layer.rotation != 0 {
                ctx.rotate(by: CGFloat(-layer.rotation) * .pi / 180)
            }
            ctx.scaleBy(x: layer.flipH ? -1 : 1, y: layer.flipV ? -1 : 1)
            ctx.draw(cg, in: CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height))
        } else {
            ctx.draw(cg, in: rect)
        }
        ctx.restoreGState()
    }

    // MARK: - Annotations

    private static func drawAnnotation(
        _ annotation: Annotation,
        crop: CGRect,
        sourceSize: CGSize,
        targetSize: CGSize,
        in ctx: CGContext
    ) {
        let relative = CGRect(
            x: (annotation.frame.minX - crop.minX) / crop.width,
            y: (annotation.frame.minY - crop.minY) / crop.height,
            width: annotation.frame.width / crop.width,
            height: annotation.frame.height / crop.height
        )
        guard relative.maxX > 0, relative.maxY > 0, relative.minX < 1, relative.minY < 1 else { return }

        let rect = CGRect(
            x: relative.minX * targetSize.width,
            y: (1 - relative.maxY) * targetSize.height,
            width: relative.width * targetSize.width,
            height: relative.height * targetSize.height
        )
        let lineScale = max(1, targetSize.width / max(sourceSize.width * crop.width, 1))
        let lineWidth = annotation.lineWidth * lineScale

        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setAlpha(CGFloat(annotation.opacity))
        ctx.setBlendMode(annotation.blendMode.cg)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        func setDash() {
            let pattern = annotation.effectiveDash(lineWidth: annotation.lineWidth, scale: lineScale)
            if pattern.isEmpty {
                ctx.setLineDash(phase: 0, lengths: [])
            } else {
                ctx.setLineDash(phase: annotation.dashOffset * lineScale, lengths: pattern)
            }
        }

        switch annotation.kind {
        case .rectangle:
            let radius = annotation.cornerRadius * lineScale
            if let fill = annotation.fillColor {
                ctx.setFillColor(fill.cgColor)
                ctx.addPath(roundedPath(rect, radius: radius))
                ctx.fillPath()
            }
            let shift = -annotation.strokeAlignment.edgeShift * lineWidth
            let strokeRect = rect.insetBy(dx: shift, dy: shift)
            let strokeRadius = max(0, radius + annotation.strokeAlignment.edgeShift * lineWidth)
            setDash()
            ctx.setStrokeColor(annotation.strokeColor.cgColor)
            ctx.setLineWidth(lineWidth)
            ctx.addPath(roundedPath(strokeRect, radius: strokeRadius))
            ctx.strokePath()

        case .ellipse:
            if let fill = annotation.fillColor {
                ctx.setFillColor(fill.cgColor)
                ctx.fillEllipse(in: rect)
            }
            let shift = -annotation.strokeAlignment.edgeShift * lineWidth
            setDash()
            ctx.setStrokeColor(annotation.strokeColor.cgColor)
            ctx.setLineWidth(lineWidth)
            ctx.strokeEllipse(in: rect.insetBy(dx: shift, dy: shift))

        case .line(let start, let end):
            setDash()
            ctx.setStrokeColor(annotation.strokeColor.cgColor)
            ctx.setLineWidth(lineWidth)
            ctx.move(to: outputPoint(start, in: rect))
            ctx.addLine(to: outputPoint(end, in: rect))
            ctx.strokePath()

        case .arrow(let start, let end):
            drawArrow(from: outputPoint(start, in: rect), to: outputPoint(end, in: rect),
                      annotation: annotation, lineWidth: lineWidth, scale: lineScale, in: ctx, setDash: setDash)

        case .freehand(let points):
            let mapped = points.map { outputPoint($0, in: rect) }
            guard let first = mapped.first else { break }
            let path = CGMutablePath()
            path.move(to: first)
            if mapped.count < 3 {
                for p in mapped.dropFirst() { path.addLine(to: p) }
            } else {
                for i in 1..<(mapped.count - 1) {
                    let cur = mapped[i], next = mapped[i + 1]
                    let mid = CGPoint(x: (cur.x + next.x) / 2, y: (cur.y + next.y) / 2)
                    path.addQuadCurve(to: mid, control: cur)
                }
                path.addLine(to: mapped[mapped.count - 1])
            }
            setDash()
            ctx.setStrokeColor(annotation.strokeColor.cgColor)
            ctx.setLineWidth(lineWidth)
            ctx.addPath(path)
            ctx.strokePath()

        case .text(let value):
            drawText(value, annotation: annotation, rect: rect, crop: crop, sourceSize: sourceSize,
                     targetSize: targetSize, in: ctx)
        }
    }

    private static func outputPoint(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + point.x * rect.width, y: rect.maxY - point.y * rect.height)
    }

    private static func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
        guard radius > 0 else { return CGPath(rect: rect, transform: nil) }
        let r = min(radius, min(abs(rect.width), abs(rect.height)) / 2)
        return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
    }

    private static func drawArrow(
        from start: CGPoint, to end: CGPoint, annotation: Annotation,
        lineWidth: CGFloat, scale: CGFloat, in ctx: CGContext, setDash: () -> Void
    ) {
        setDash()
        ctx.setStrokeColor(annotation.strokeColor.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.move(to: start)
        ctx.addLine(to: end)
        ctx.strokePath()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(10, lineWidth * 4)
        let spread: CGFloat = .pi / 7
        let left = CGPoint(x: end.x - cos(angle - spread) * headLength, y: end.y - sin(angle - spread) * headLength)
        let right = CGPoint(x: end.x - cos(angle + spread) * headLength, y: end.y - sin(angle + spread) * headLength)
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.move(to: left)
        ctx.addLine(to: end)
        ctx.addLine(to: right)
        ctx.strokePath()
    }

    private static func drawText(
        _ value: String, annotation: Annotation, rect: CGRect,
        crop: CGRect, sourceSize: CGSize, targetSize: CGSize, in ctx: CGContext
    ) {
        let scale = targetSize.width / max(sourceSize.width * crop.width, 1)
        let size = max(8, annotation.fontSize * scale)
        let font = ctFont(family: annotation.fontFamily, size: size, weight: annotation.fontWeight)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = textAlignment(annotation.textAlignment)
        paragraph.minimumLineHeight = size * annotation.lineHeight
        paragraph.maximumLineHeight = size * annotation.lineHeight

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: annotation.strokeColor.cgColor,
            .paragraphStyle: paragraph
        ]
        let attributed = NSAttributedString(string: value, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
        let framePath = CGPath(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), framePath, nil)
        CTFrameDraw(frame, ctx)
    }

    private static func ctFont(family: String, size: CGFloat, weight: AnnotationFontWeight) -> CTFont {
        #if canImport(AppKit)
        let ns: NSFont
        if family.isEmpty {
            ns = NSFont.systemFont(ofSize: size, weight: nsWeight(weight))
        } else {
            ns = NSFont(name: family, size: size) ?? NSFont.systemFont(ofSize: size, weight: nsWeight(weight))
        }
        return ns as CTFont
        #elseif canImport(UIKit)
        let ui: UIFont
        if family.isEmpty {
            ui = UIFont.systemFont(ofSize: size, weight: uiWeight(weight))
        } else {
            ui = UIFont(name: family, size: size) ?? UIFont.systemFont(ofSize: size, weight: uiWeight(weight))
        }
        return ui as CTFont
        #else
        return CTFontCreateWithName("Helvetica" as CFString, size, nil)
        #endif
    }

    #if canImport(AppKit)
    private static func nsWeight(_ w: AnnotationFontWeight) -> NSFont.Weight {
        switch w {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }
    #elseif canImport(UIKit)
    private static func uiWeight(_ w: AnnotationFontWeight) -> UIFont.Weight {
        switch w {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }
    #endif

    private static func textAlignment(_ a: AnnotationTextAlignment) -> NSTextAlignment {
        switch a {
        case .leading: return .left
        case .center: return .center
        case .trailing: return .right
        }
    }
}
