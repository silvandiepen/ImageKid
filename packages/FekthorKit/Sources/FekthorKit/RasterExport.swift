import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// PNG and PDF export for Document Model v2, drawing through
/// `GraphicRenderer` so exports match the editor canvas and thumbnails.
///
/// - PNG renders a bitmap and encodes via `CGImageDestination`. Encoded bytes
///   may differ across OS versions (encoder settings), so compare decoded
///   pixels, not bytes.
/// - PDF is true vector output: the same `GraphicRenderer.draw` path-building
///   runs against a `CGPDFContext`, so shapes stay resolution-independent —
///   no rasterized bitmap is embedded.
public enum RasterExport {
    // MARK: - PNG

    /// PNG at `scale` pixels per document unit (output is `viewBox * scale`).
    /// Transparent background unless `background` is given. Nil for a
    /// degenerate viewBox or encoder failure.
    public static func pngData(_ doc: GraphicDocument, scale: Double = 1, background: RGB? = nil)
        -> Data?
    {
        guard let image = GraphicRenderer.render(doc, scale: scale, background: background)
        else { return nil }
        return encodePNG(image)
    }

    /// PNG at an exact pixel size; the viewBox is fitted per `fit`
    /// (letterboxed for `.contain`, uncovered pixels stay background).
    public static func pngData(
        _ doc: GraphicDocument, width: Int, height: Int, fit: GraphicRenderer.Fit = .contain,
        background: RGB? = nil
    ) -> Data? {
        guard
            let image = GraphicRenderer.render(
                doc, width: width, height: height, fit: fit, background: background)
        else { return nil }
        return encodePNG(image)
    }

    static func encodePNG(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard
            let dest = CGImageDestinationCreateWithData(
                data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    // MARK: - PDF

    /// Single-page vector PDF. The page is `size` points (default: the
    /// viewBox size, 1 document unit = 1 pt); the document is fitted
    /// `.contain` into the page. Nil for a degenerate viewBox.
    public static func pdfData(_ doc: GraphicDocument, size: CGSize? = nil) -> Data? {
        let vb = doc.viewBox
        guard vb.width > 0, vb.height > 0 else { return nil }
        let pageSize = size ?? CGSize(width: vb.width, height: vb.height)
        guard pageSize.width > 0, pageSize.height > 0,
            let content = GraphicRenderer.contentRect(for: vb, in: pageSize, fit: .contain)
        else { return nil }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data),
            let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { return nil }
        ctx.beginPDFPage(nil)
        GraphicRenderer.draw(doc, in: ctx, contextHeight: pageSize.height, content: content)
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }
}
