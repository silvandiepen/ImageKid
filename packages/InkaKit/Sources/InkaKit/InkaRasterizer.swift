import BrushKit
import CoreGraphics
import Foundation
import ImageIO
import ImageKidCore

/// Flattens an `InkaDocument` to a single image, honouring layer order,
/// visibility and opacity. Stroke layers are re-generated through the brush
/// engine here — this is the non-destructive part: nothing is baked until
/// export, so changing a brush or a stroke re-renders cleanly.
///
/// Uses BrushKit's CoreGraphics `ReferenceRenderer` so it is portable and
/// testable without Metal. The live editing canvas uses BrushRender's GPU path;
/// both stamp the same `Dab`s, so they agree. The app supplies the brush lookup
/// (the document's table).
public enum InkaRasterizer {
    /// Compose the visible layers into one RGBA8 image at the document's size.
    public static func flatten(_ document: InkaDocument) -> CGImage? {
        let w = document.width
        let h = document.height
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
            let ctx = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        for layer in document.layers where layer.isVisible {
            guard let image = render(layer: layer, in: document) else { continue }
            ctx.saveGState()
            ctx.setAlpha(CGFloat(max(0, min(1, layer.opacity))))
            ctx.setBlendMode(blendMode(layer.blendMode))
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }

    /// One PNG per visible layer, named `NN-<layer>` (index-prefixed so names
    /// stay unique and ordered). For "export layers".
    public static func layerPNGs(_ document: InkaDocument) -> [(name: String, data: Data)] {
        var out: [(String, Data)] = []
        for (i, layer) in document.layers.enumerated() where layer.isVisible {
            guard let cg = render(layer: layer, in: document),
                let data = InkaImageFit.pngData(cg)
            else { continue }
            let safe = layer.name.replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            out.append((String(format: "%02d-%@", i + 1, safe), data))
        }
        return out
    }

    /// The flattened document as PNG data.
    public static func flattenedPNG(_ document: InkaDocument) -> Data? {
        guard let cg = flatten(document) else { return nil }
        return InkaImageFit.pngData(cg)
    }

    /// Render a single layer to an image at the document's size (the raster
    /// cache a `.strokes` layer would keep). Public so the app can re-render one
    /// layer after an edit without flattening the whole stack.
    public static func render(layer: Layer, in document: InkaDocument) -> CGImage? {
        switch layer.content {
        case .strokes(let strokes):
            // Composite strokes in order so eraser strokes (destination-out)
            // remove the paint beneath them. Consecutive paint strokes batch
            // into one render; an eraser flushes the batch, then erases.
            let w = document.width
            let h = document.height
            guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
                let ctx = CGContext(
                    data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            let rect = CGRect(x: 0, y: 0, width: w, height: h)

            var batch: [Dab] = []
            func flush() {
                guard !batch.isEmpty,
                    let img = ReferenceRenderer.render(dabs: batch, size: document.size)
                else { batch = []; return }
                ctx.setBlendMode(.normal)
                ctx.draw(img, in: rect)
                batch = []
            }
            for stroke in strokes {
                guard let brush = document.brush(id: stroke.brushID) else { continue }
                let dabs = stroke.dabs(using: brush)
                if stroke.erase {
                    flush()
                    guard let img = ReferenceRenderer.render(dabs: dabs, size: document.size)
                    else { continue }
                    ctx.setBlendMode(.destinationOut)
                    ctx.draw(img, in: rect)
                } else {
                    batch.append(contentsOf: dabs)
                }
            }
            flush()
            return ctx.makeImage()
        case .raster(let png), .imported(let png):
            return decodePNG(png)
        }
    }

    private static func decodePNG(_ png: PNGImage) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(png.data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func blendMode(_ name: String) -> CGBlendMode {
        switch name {
        case "multiply": return .multiply
        case "screen": return .screen
        case "overlay": return .overlay
        case "darken": return .darken
        case "lighten": return .lighten
        case "add", "plusLighter": return .plusLighter
        default: return .normal
        }
    }
}
