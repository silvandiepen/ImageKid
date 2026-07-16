import Foundation
import AppKit
import SwiftUI
import AVFoundation
import AVKit
import CoreGraphics

public enum Tool: String, CaseIterable, Identifiable {
    case view
    case pickColor
    case crop
    case rectangle
    case text

    public var id: String { rawValue }

    var label: String {
        switch self {
        case .view: "View"
        case .pickColor: "Pick"
        case .crop: "Crop"
        case .rectangle: "Rectangle"
        case .text: "Text"
        }
    }

    var symbolName: String {
        switch self {
        case .view: "hand.draw"
        case .pickColor: "eyedropper"
        case .crop: "crop"
        case .rectangle: "rectangle"
        case .text: "textformat"
        }
    }
}

struct SampledColor: Identifiable {
    let id = UUID()
    let color: NSColor

    var sRGB: NSColor {
        color.usingColorSpace(.sRGB) ?? color
    }

    var hex: String {
        let value = sRGB
        return String(
            format: "#%02X%02X%02X",
            Int((value.redComponent * 255).rounded()),
            Int((value.greenComponent * 255).rounded()),
            Int((value.blueComponent * 255).rounded())
        )
    }

    var rgba: String {
        let value = sRGB
        return String(
            format: "rgba(%d, %d, %d, %.3f)",
            Int((value.redComponent * 255).rounded()),
            Int((value.greenComponent * 255).rounded()),
            Int((value.blueComponent * 255).rounded()),
            value.alphaComponent
        )
    }
}

struct Annotation: Identifiable {
    enum Kind {
        case rectangle
        case text(String)
    }

    let id: UUID
    var kind: Kind
    var frame: CGRect
    var strokeColor: NSColor
    var fillColor: NSColor?
    var lineWidth: CGFloat

    init(
        id: UUID = UUID(),
        kind: Kind,
        frame: CGRect,
        strokeColor: NSColor = .systemRed,
        fillColor: NSColor? = nil,
        lineWidth: CGFloat = 3
    ) {
        self.id = id
        self.kind = kind
        self.frame = frame
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.lineWidth = lineWidth
    }
}

@MainActor
final class ImageSession: ObservableObject {
    let sourceURL: URL?
    let sourceImage: NSImage

    @Published var zoom: CGFloat = 1
    @Published var pan: CGSize = .zero
    @Published var cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    @Published var draftCropRect: CGRect?
    @Published var outputSize: CGSize?
    @Published var annotations: [Annotation] = []
    @Published var sampledColors: [SampledColor] = []
    @Published var isDirty = false

    init(sourceURL: URL?, sourceImage: NSImage) {
        self.sourceURL = sourceURL
        self.sourceImage = sourceImage
    }

    var pixelSize: CGSize {
        if let representation = sourceImage.representations.first {
            return CGSize(width: representation.pixelsWide, height: representation.pixelsHigh)
        }
        return sourceImage.size
    }

    var effectivePixelSize: CGSize {
        if let outputSize { return outputSize }
        return CGSize(
            width: max(1, (pixelSize.width * cropRect.width).rounded()),
            height: max(1, (pixelSize.height * cropRect.height).rounded())
        )
    }

    func addSample(_ color: NSColor) {
        sampledColors.append(SampledColor(color: color))
    }

    func applyDraftCrop() {
        guard let draftCropRect, draftCropRect.width > 0.01, draftCropRect.height > 0.01 else { return }
        cropRect = draftCropRect
        self.draftCropRect = nil
        isDirty = true
    }

    func resetView() {
        zoom = 1
        pan = .zero
    }
}

@MainActor
final class VideoSession: ObservableObject {
    let sourceURL: URL
    let asset: AVAsset
    let player: AVPlayer

    @Published var zoom: CGFloat = 1
    @Published var pan: CGSize = .zero
    @Published var cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    @Published var outputSize: CGSize?
    @Published var annotations: [Annotation] = []
    @Published var sampledColors: [SampledColor] = []

    init(sourceURL: URL) {
        self.sourceURL = sourceURL
        let asset = AVURLAsset(url: sourceURL)
        self.asset = asset
        self.player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
    }

    var naturalSize: CGSize {
        guard let track = asset.tracks(withMediaType: .video).first else {
            return CGSize(width: 16, height: 9)
        }
        let transformed = track.naturalSize.applying(track.preferredTransform)
        return CGSize(width: abs(transformed.width), height: abs(transformed.height))
    }
}

public enum GeometryMapper {
    public static func aspectFitRect(contentSize: CGSize, in bounds: CGRect) -> CGRect {
        guard contentSize.width > 0, contentSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return .zero
        }

        let scale = min(bounds.width / contentSize.width, bounds.height / contentSize.height)
        let size = CGSize(width: contentSize.width * scale, height: contentSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    public static func normalizedPoint(_ point: CGPoint, in imageRect: CGRect) -> CGPoint? {
        guard imageRect.contains(point), imageRect.width > 0, imageRect.height > 0 else { return nil }
        return CGPoint(
            x: (point.x - imageRect.minX) / imageRect.width,
            y: (point.y - imageRect.minY) / imageRect.height
        )
    }

    public static func normalizedRect(from first: CGPoint, to second: CGPoint, in imageRect: CGRect) -> CGRect? {
        guard let a = normalizedPoint(first, in: imageRect), let b = normalizedPoint(second, in: imageRect) else {
            return nil
        }
        return CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }

    public static func viewRect(from normalizedRect: CGRect, in imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + normalizedRect.minX * imageRect.width,
            y: imageRect.minY + normalizedRect.minY * imageRect.height,
            width: normalizedRect.width * imageRect.width,
            height: normalizedRect.height * imageRect.height
        )
    }
}
