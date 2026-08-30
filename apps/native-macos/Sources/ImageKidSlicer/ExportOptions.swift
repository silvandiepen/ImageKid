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

    var format: Format = .sameAsSource
    /// 0…1, used only by the lossy formats.
    var quality: Double = 0.9
    /// A whole-number percentage, so the UI and the stored value agree exactly.
    var scalePercent: Int = 100
    /// Prepended to every exported filename.
    var namePrefix: String = ""

    static let scaleRange = 10...400
    static let presetScales = [25, 50, 100, 200, 400]

    var scale: CGFloat { CGFloat(scalePercent) / 100 }
    var isScaled: Bool { scalePercent != 100 }

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
        guard isScaled else { return pixelRect.size }
        return CGSize(
            width: max((pixelRect.width * scale).rounded(), 1),
            height: max((pixelRect.height * scale).rounded(), 1)
        )
    }

    /// A one-line summary for the button that opens the options.
    func summary(sourceType: UTType, sourceExtension: String) -> String {
        var parts = [resolved(sourceType: sourceType, sourceExtension: sourceExtension).fileExtension.uppercased()]
        if isScaled { parts.append("\(scalePercent)%") }
        if isLossy(sourceType: sourceType) { parts.append("q\(Int((quality * 100).rounded()))") }
        return parts.joined(separator: " · ")
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
