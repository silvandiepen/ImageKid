import CoreGraphics
import Foundation
import UniformTypeIdentifiers

/// What Save actually writes: the format, how big, and what it is called.
///
/// Kept as a value type with no UI in it so the export path and the tests can
/// both reason about it, and so it can be stored in preferences whole.
struct ExportOptions: Equatable, Codable {
    enum Format: String, CaseIterable, Identifiable, Codable {
        /// Keep the source's format where Image I/O can write it, PNG otherwise.
        case sameAsSource
        case png
        case jpeg
        case heic
        case tiff

        var id: String { rawValue }

        var label: String {
            switch self {
            case .sameAsSource: "Same as source"
            case .png: "PNG"
            case .jpeg: "JPEG"
            case .heic: "HEIC"
            case .tiff: "TIFF"
            }
        }

        /// Lossy formats are the only ones a quality setting means anything for.
        var isLossy: Bool { self == .jpeg || self == .heic }

        var type: UTType? {
            switch self {
            case .sameAsSource: nil
            case .png: .png
            case .jpeg: .jpeg
            case .heic: .heic
            case .tiff: .tiff
            }
        }
    }

    /// How the output size is decided.
    enum Sizing: String, CaseIterable, Identifiable, Codable {
        /// Whatever the slice measures, optionally scaled by a percentage.
        case actual
        /// Every file the same width and height, whatever the slice measures.
        case fixed

        var id: String { rawValue }

        var label: String {
            switch self {
            case .actual: "Slice size"
            case .fixed: "Fixed size"
            }
        }
    }

    /// What to do when the slice's shape does not match the output's.
    enum Fit: String, CaseIterable, Identifiable, Codable {
        /// Whole slice visible, padded to fill the rest.
        case contain
        /// Output filled edge to edge, overflow cropped away.
        case cover

        var id: String { rawValue }

        var label: String {
            switch self {
            case .contain: "Contain"
            case .cover: "Cover"
            }
        }

        var detail: String {
            switch self {
            case .contain: "The whole slice fits, and the rest is padded."
            case .cover: "The output is filled, and the overflow is cropped."
            }
        }
    }

    /// What fills the space Contain leaves over.
    enum Padding: String, CaseIterable, Identifiable, Codable {
        case transparent, white, black

        var id: String { rawValue }

        var label: String {
            switch self {
            case .transparent: "Transparent"
            case .white: "White"
            case .black: "Black"
            }
        }

        /// Nil means leave it clear. A format without alpha will flatten that
        /// to black, which is why the choice exists.
        var color: CGColor? {
            switch self {
            case .transparent: nil
            case .white: CGColor(red: 1, green: 1, blue: 1, alpha: 1)
            case .black: CGColor(red: 0, green: 0, blue: 0, alpha: 1)
            }
        }
    }

    var format: Format = .sameAsSource
    var sizing: Sizing = .actual
    var outputWidth: Int = 512
    var outputHeight: Int = 512
    var fit: Fit = .contain
    var padding: Padding = .transparent
    /// 0…1, used only by the lossy formats.
    var quality: Double = 0.9
    /// A whole-number percentage, so the UI and the stored value agree exactly.
    var scalePercent: Int = 100
    /// Prepended to every exported filename.
    var namePrefix: String = ""

    static let scaleRange = 10...400
    static let presetScales = [25, 50, 100, 200, 400]
    static let sizeRange = 1...16384

    var scale: CGFloat { CGFloat(scalePercent) / 100 }

    /// Whether the cropped region has to be redrawn at all. An export that
    /// changes nothing should not pay for a resample.
    var needsResampling: Bool {
        sizing == .fixed || scalePercent != 100
    }

    /// The fixed output, clamped to something writable.
    var fixedSize: CGSize {
        CGSize(
            width: min(max(outputWidth, Self.sizeRange.lowerBound), Self.sizeRange.upperBound),
            height: min(max(outputHeight, Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
        )
    }

    /// Whether quality applies, given the source (which decides the format when
    /// the option is "same as source").
    func isLossy(sourceType: UTType) -> Bool {
        format == .sameAsSource ? (sourceType == .jpeg || sourceType == .heic) : format.isLossy
    }

    /// The type and file extension one exported file should use.
    func resolved(sourceType: UTType, sourceExtension: String) -> (type: UTType, fileExtension: String) {
        guard let chosen = format.type else {
            return (sourceType, sourceExtension)
        }
        return (chosen, chosen.preferredFilenameExtension ?? sourceExtension)
    }

    /// The pixel size a region of `pixelRect` will be written at.
    func outputPixelSize(for pixelRect: CGRect) -> CGSize {
        switch sizing {
        case .fixed:
            return fixedSize
        case .actual:
            guard scalePercent != 100 else { return pixelRect.size }
            return CGSize(
                width: max((pixelRect.width * scale).rounded(), 1),
                height: max((pixelRect.height * scale).rounded(), 1)
            )
        }
    }

    /// Where the slice is drawn inside a fixed-size output, and how big.
    ///
    /// Contain scales until the whole slice fits and centres it; Cover scales
    /// until nothing is left over and lets the excess fall outside the canvas.
    static func drawRect(for source: CGSize, in output: CGSize, fit: Fit) -> CGRect {
        guard source.width > 0, source.height > 0 else {
            return CGRect(origin: .zero, size: output)
        }
        let scaleX = output.width / source.width
        let scaleY = output.height / source.height
        let scale = fit == .contain ? min(scaleX, scaleY) : max(scaleX, scaleY)

        let size = CGSize(width: source.width * scale, height: source.height * scale)
        return CGRect(
            x: (output.width - size.width) / 2,
            y: (output.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    /// A one-line summary for the button that opens the options.
    func summary(sourceType: UTType, sourceExtension: String) -> String {
        var parts = [resolved(sourceType: sourceType, sourceExtension: sourceExtension).fileExtension.uppercased()]
        switch sizing {
        case .fixed:
            parts.append("\(Int(fixedSize.width))×\(Int(fixedSize.height)) \(fit.rawValue)")
        case .actual:
            if scalePercent != 100 { parts.append("\(scalePercent)%") }
        }
        if isLossy(sourceType: sourceType) { parts.append("q\(Int((quality * 100).rounded()))") }
        return parts.joined(separator: " · ")
    }

    init() {}

    /// Decoded with defaults for anything absent, so preferences or a session
    /// written before a setting existed still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(Format.self, forKey: .format) ?? .sameAsSource
        sizing = try c.decodeIfPresent(Sizing.self, forKey: .sizing) ?? .actual
        outputWidth = try c.decodeIfPresent(Int.self, forKey: .outputWidth) ?? 512
        outputHeight = try c.decodeIfPresent(Int.self, forKey: .outputHeight) ?? 512
        fit = try c.decodeIfPresent(Fit.self, forKey: .fit) ?? .contain
        padding = try c.decodeIfPresent(Padding.self, forKey: .padding) ?? .transparent
        quality = try c.decodeIfPresent(Double.self, forKey: .quality) ?? 0.9
        scalePercent = try c.decodeIfPresent(Int.self, forKey: .scalePercent) ?? 100
        namePrefix = try c.decodeIfPresent(String.self, forKey: .namePrefix) ?? ""
    }

    var sanitizedPrefix: String {
        SliceExporter.sanitized(namePrefix).map { $0 + "-" } ?? ""
    }
}

/// Where the export options live between launches.
@MainActor
final class ExportOptionsStore: ObservableObject {
    @Published var options: ExportOptions {
        didSet { persist() }
    }

    private let defaultsKey = "slicer.exportOptions"
    private let store: UserDefaults

    init(store: UserDefaults = SlicerDefaults.store) {
        self.store = store
        if
            let data = store.data(forKey: defaultsKey),
            let decoded = try? JSONDecoder().decode(ExportOptions.self, from: data)
        {
            options = decoded
        } else {
            options = ExportOptions()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(options) else { return }
        store.set(data, forKey: defaultsKey)
    }
}
