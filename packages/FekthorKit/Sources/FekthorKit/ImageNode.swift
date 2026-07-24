import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Placed raster images (Document Model v2)
//
// A pasted or dropped raster stays a raster: it lands as an `<image>` node
// with its pixels embedded as a base64 data URI, so the document remains ONE
// self-contained SVG (no sidecar files, no external references to go stale).
// The node keeps its own rect and transform like any other node — it moves,
// scales and rotates with the selection — and Vectorize replaces it with the
// traced geometry.

/// An `<image>` element: a rect in user space plus the pixels it shows.
public struct ImageNode: Equatable, Sendable {
    /// Deterministic in-document id (selection/undo); never serialized.
    public var id: Int
    /// The `href` value, verbatim. Images placed by the app carry a
    /// `data:image/png;base64,…` URI; foreign files may reference anything
    /// else, which round-trips untouched (and simply does not render).
    public var href: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    /// `preserveAspectRatio`, preserved verbatim. The app writes nothing:
    /// placed images get a rect with the source's own aspect ratio, so the
    /// SVG default ("xMidYMid meet") is already exact.
    public var preserveAspectRatio: String?
    public var style: Style
    public var attributes: NodeAttributes
    public var transform: TransformValue?

    public init(
        id: Int, href: String, x: Double, y: Double, width: Double, height: Double,
        preserveAspectRatio: String? = nil, style: Style = Style(),
        attributes: NodeAttributes = NodeAttributes(), transform: TransformValue? = nil
    ) {
        self.id = id
        self.href = href
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.preserveAspectRatio = preserveAspectRatio
        self.style = style
        self.attributes = attributes
        self.transform = transform
    }

    /// The placement rect's four corners in document space (transform baked).
    public var corners: [Pt] {
        let raw = [
            Pt(x, y), Pt(x + width, y), Pt(x + width, y + height), Pt(x, y + height),
        ]
        guard let transform else { return raw }
        return raw.map { transform.apply($0) }
    }

    /// Document-space bounds (axis-aligned, transform baked).
    public var bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        let pts = corners
        var minX = pts[0].x
        var minY = pts[0].y
        var maxX = pts[0].x
        var maxY = pts[0].y
        for p in pts.dropFirst() {
            minX = Swift.min(minX, p.x)
            minY = Swift.min(minY, p.y)
            maxX = Swift.max(maxX, p.x)
            maxY = Swift.max(maxY, p.y)
        }
        return (minX, minY, maxX, maxY)
    }

    /// Effective style for rendering (images carry no class styles).
    public var effectiveStyle: Style { style }

    // MARK: Transforms

    /// A document-space transform applied AFTER whatever the node already
    /// carries. Pure translations and positive scales fold into the rect so
    /// untransformed images keep clean `x`/`y`/`width`/`height` attributes;
    /// anything else (rotation, skew, mirroring) composes onto the transform,
    /// because a rect cannot express it.
    public func applying(_ m: TransformValue) -> ImageNode {
        var out = self
        if transform == nil, m.matrix[1] == 0, m.matrix[2] == 0,
            m.matrix[0] > 0, m.matrix[3] > 0
        {
            out.x = m.matrix[0] * x + m.matrix[4]
            out.y = m.matrix[3] * y + m.matrix[5]
            out.width = m.matrix[0] * width
            out.height = m.matrix[3] * height
            return out
        }
        out.transform = TransformValue.composed(m, transform)
        return out
    }

    public func translated(dx: Double, dy: Double) -> ImageNode {
        applying(ImageNode.matrixTransform([1, 0, 0, 1, dx, dy]))
    }

    public func scaled(sx: Double, sy: Double, around c: Pt) -> ImageNode {
        applying(ImageNode.matrixTransform([sx, 0, 0, sy, c.x - sx * c.x, c.y - sy * c.y]))
    }

    public func rotated(by radians: Double, around c: Pt) -> ImageNode {
        let ca = cos(radians)
        let sa = sin(radians)
        return applying(
            ImageNode.matrixTransform([
                ca, sa, -sa, ca,
                c.x - ca * c.x + sa * c.y, c.y - sa * c.x - ca * c.y,
            ]))
    }

    /// A transform whose `raw` text matches its matrix — never empty, so a
    /// composed transform always survives the writer.
    static func matrixTransform(_ m: [Double]) -> TransformValue {
        TransformValue(
            raw: "matrix(" + m.map { SVGNum.text($0) }.joined(separator: " ") + ")", matrix: m)
    }
}

// MARK: - Embedded pixels

/// Encoding and decoding for the pixels an `ImageNode` carries.
///
/// Placed images are embedded as PNG data URIs: lossless, universally
/// readable, and self-contained (the SVG stays one file). Decoding is cached
/// by href — the canvas redraws constantly and base64-decoding a multi-megabyte
/// image per frame would stall it.
public enum ImageEmbed {
    public static let pngPrefix = "data:image/png;base64,"

    /// PNG-encode a CGImage.
    public static func encodePNG(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard
            let dest = CGImageDestinationCreateWithData(
                data as CFMutableData, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// A `data:image/png;base64,…` href for a CGImage.
    public static func dataURI(for image: CGImage) -> String? {
        guard let png = encodePNG(image) else { return nil }
        return pngPrefix + png.base64EncodedString()
    }

    /// A `data:image/png;base64,…` href for a raster buffer.
    public static func dataURI(for raster: RasterImage) -> String? {
        guard let cg = raster.cgImage() else { return nil }
        return dataURI(for: cg)
    }

    /// Decode an href into pixels. Only `data:` URIs decode — external
    /// references (file/http) are preserved by the reader and writer but never
    /// fetched: Fekthor stays local-first and self-contained.
    public static func decode(_ href: String) -> CGImage? {
        if let hit = cache.object(forKey: href as NSString) { return hit.image }
        guard let data = payload(of: href),
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        cache.setObject(Box(image), forKey: href as NSString)
        return image
    }

    /// Decode an href into an RGBA8 buffer (the trace pipeline's input).
    public static func rasterImage(_ href: String) -> RasterImage? {
        guard let cg = decode(href) else { return nil }
        return try? RasterImage.from(cgImage: cg)
    }

    /// The bytes a `data:` URI carries (base64 or percent-encoded).
    static func payload(of href: String) -> Data? {
        guard href.hasPrefix("data:"), let comma = href.firstIndex(of: ",") else { return nil }
        let meta = href[href.startIndex..<comma]
        let body = String(href[href.index(after: comma)...])
        if meta.hasSuffix(";base64") {
            return Data(
                base64Encoded: body.filter { !$0.isWhitespace },
                options: .ignoreUnknownCharacters)
        }
        return body.removingPercentEncoding.map { Data($0.utf8) }
    }

    private final class Box: @unchecked Sendable {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    private static let cache: NSCache<NSString, Box> = {
        let c = NSCache<NSString, Box>()
        c.countLimit = 32
        return c
    }()
}
