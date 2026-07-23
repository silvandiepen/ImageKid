import CoreGraphics
import ImageKidCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

extension UTType {
    static let imagekid = UTType(filenameExtension: "imagekid") ?? .data
}

/// A `.imagekid` file for SwiftUI's fileExporter / fileImporter.
struct ImageKidFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.imagekid, .data] }
    static var writableContentTypes: [UTType] { [.imagekid] }

    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Bridges the iOS editor state (its own Annotation / EditorLayer types) to and
/// from the shared `.imagekid` document format in ImageKidCore, so files
/// round-trip with the macOS app.
enum ImageKidBridge {
    // MARK: iOS -> core

    static func makeDocumentData(base: UIImage, annotations: [Annotation], layers: [EditorLayer]) -> Data? {
        guard let baseCG = base.normalizedCGImage() else { return nil }
        let baseSize = CGSize(width: baseCG.width, height: baseCG.height)
        guard let baseStr = IKImageCoder.encode(UIImage(cgImage: baseCG)) else { return nil }

        let coreAnnotations = annotations.map { IKAnnotation(coreAnnotation(from: $0, baseSize: baseSize)) }
        let coreLayers = layers.compactMap { layer -> IKLayer? in
            IKLayer(ImageKidCore.ImageLayer(
                name: layer.name, image: layer.image, frame: layer.frame,
                opacity: layer.opacity, isVisible: layer.isVisible, z: layer.z
            ))
        }
        let document = ImageKidDocument(
            baseImage: baseStr,
            backgroundRemovedImage: nil,
            cropRect: IKRect(CGRect(x: 0, y: 0, width: 1, height: 1)),
            outputSize: nil,
            viewportMode: "contain",
            grid: IKGrid(show: false, snap: false, size: 32, colorHex: "#808080", opacity: 0.5, subdivisions: 2),
            annotations: coreAnnotations,
            imageLayers: coreLayers,
            layerGroups: [],
            baseUnlocked: false
        )
        return try? document.encoded()
    }

    // MARK: core -> iOS

    static func load(_ data: Data) -> (base: UIImage, annotations: [Annotation], layers: [EditorLayer])? {
        guard let document = try? ImageKidDocument.decoded(from: data),
              let base = IKImageCoder.decode(document.baseImage) else { return nil }
        let baseCG = base.normalizedCGImage()
        let baseSize = CGSize(width: baseCG?.width ?? Int(base.size.width), height: baseCG?.height ?? Int(base.size.height))

        let annotations = document.annotations.map { iosAnnotation(from: $0.annotation, baseSize: baseSize) }
        let layers: [EditorLayer] = document.imageLayers.compactMap { dto in
            guard let core = dto.layer else { return nil }
            var layer = EditorLayer(name: core.name, image: core.image, originalImage: core.image, frame: core.frame,
                                    opacity: core.opacity, isVisible: core.isVisible)
            layer.z = core.z
            return layer
        }
        return (base, annotations, layers)
    }

    // MARK: - Annotation mapping

    private static func coreAnnotation(from a: Annotation, baseSize: CGSize) -> ImageKidCore.Annotation {
        let minSide = min(baseSize.width, baseSize.height)
        let lineWidth = a.widthFraction * minSide
        let stroke = UIColor(a.color)

        func bbox(_ p1: CGPoint, _ p2: CGPoint) -> CGRect {
            CGRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y), width: abs(p1.x - p2.x), height: abs(p1.y - p2.y))
        }
        func bbox(points: [CGPoint]) -> CGRect {
            guard let first = points.first else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
            var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
            for p in points { minX = min(minX, p.x); minY = min(minY, p.y); maxX = max(maxX, p.x); maxY = max(maxY, p.y) }
            return CGRect(x: minX, y: minY, width: max(maxX - minX, 0.0001), height: max(maxY - minY, 0.0001))
        }
        func local(_ p: CGPoint, in frame: CGRect) -> CGPoint {
            CGPoint(x: frame.width > 0 ? (p.x - frame.minX) / frame.width : 0,
                    y: frame.height > 0 ? (p.y - frame.minY) / frame.height : 0)
        }

        switch a.kind {
        case .rectangle, .ellipse:
            let frame = bbox(a.start, a.end)
            let kind: ImageKidCore.Annotation.Kind = a.kind == .rectangle ? .rectangle : .ellipse
            return ImageKidCore.Annotation(kind: kind, frame: frame, strokeColor: stroke, lineWidth: lineWidth, z: a.z)
        case .line, .arrow:
            let frame = bbox(a.start, a.end)
            let s = local(a.start, in: frame), e = local(a.end, in: frame)
            let kind: ImageKidCore.Annotation.Kind = a.kind == .line ? .line(start: s, end: e) : .arrow(start: s, end: e)
            return ImageKidCore.Annotation(kind: kind, frame: frame, strokeColor: stroke, lineWidth: lineWidth, z: a.z)
        case .freehand:
            let frame = bbox(points: a.points)
            let pts = a.points.map { local($0, in: frame) }
            return ImageKidCore.Annotation(kind: .freehand(points: pts), frame: frame, strokeColor: stroke, lineWidth: lineWidth, z: a.z)
        case .text:
            let fontSize = a.fontFraction * baseSize.height
            let frame = CGRect(x: a.start.x, y: a.start.y, width: max(0.1, 1 - a.start.x), height: max(0.05, a.fontFraction * 1.6))
            return ImageKidCore.Annotation(kind: .text(a.text), frame: frame, strokeColor: stroke,
                                           fontFamily: a.fontName ?? "", fontSize: fontSize, z: a.z)
        }
    }

    private static func iosAnnotation(from a: ImageKidCore.Annotation, baseSize: CGSize) -> Annotation {
        let minSide = min(baseSize.width, baseSize.height)
        let widthFraction = max(minSide > 0 ? a.lineWidth / minSide : 0.008, 0.001)
        let color = Color(uiColor: a.strokeColor)

        func abs(_ p: CGPoint) -> CGPoint {
            CGPoint(x: a.frame.minX + p.x * a.frame.width, y: a.frame.minY + p.y * a.frame.height)
        }

        var out: Annotation
        switch a.kind {
        case .rectangle, .ellipse:
            out = Annotation(kind: a.kind.isRect ? .rectangle : .ellipse, color: color, widthFraction: widthFraction)
            out.start = a.frame.origin
            out.end = CGPoint(x: a.frame.maxX, y: a.frame.maxY)
        case .line(let s, let e):
            out = Annotation(kind: .line, color: color, widthFraction: widthFraction)
            out.start = abs(s); out.end = abs(e)
        case .arrow(let s, let e):
            out = Annotation(kind: .arrow, color: color, widthFraction: widthFraction)
            out.start = abs(s); out.end = abs(e)
        case .freehand(let pts):
            out = Annotation(kind: .freehand, color: color, widthFraction: widthFraction)
            out.points = pts.map { abs($0) }
            if let f = out.points.first { out.start = f }
            if let l = out.points.last { out.end = l }
        case .text(let value):
            out = Annotation(kind: .text, color: color, widthFraction: widthFraction)
            out.start = a.frame.origin
            out.text = value
            out.fontFraction = baseSize.height > 0 ? a.fontSize / baseSize.height : 0.05
            out.fontName = a.fontFamily.isEmpty ? nil : a.fontFamily
        }
        out.z = a.z
        return out
    }
}

private extension ImageKidCore.Annotation.Kind {
    var isRect: Bool { if case .rectangle = self { return true }; return false }
}
