import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ImageExportOptions {
    var format: ImageExportFormat = .png
    var quality: Double = 0.92
    var pngCompression: Double = 0.82
    var removesMetadata = true
    var backgroundColor: NSColor = .white
    var revealAfterExport = false
    var upscaleEngine: UpscaleEngine = .standard
    var upscaleContentMode: UpscaleContentMode = .automatic
}

enum ImageExportFormat: String, CaseIterable, Identifiable {
    case png
    case jpeg
    case heic
    case tiff
    case bmp
    case gif

    var id: String { rawValue }

    var label: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        case .tiff: "TIFF"
        case .bmp: "BMP"
        case .gif: "GIF"
        }
    }

    var fileExtension: String { rawValue == "jpeg" ? "jpg" : rawValue }

    var contentType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        case .tiff: .tiff
        case .bmp: .bmp
        case .gif: .gif
        }
    }

    var supportsAlpha: Bool {
        switch self {
        case .png, .tiff, .gif: true
        case .jpeg, .heic, .bmp: false
        }
    }

    var supportsQuality: Bool {
        self == .jpeg || self == .heic
    }

    var supportsCompression: Bool {
        self == .png
    }

    var bitmapType: NSBitmapImageRep.FileType? {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: nil
        case .tiff: .tiff
        case .bmp: .bmp
        case .gif: .gif
        }
    }

    init?(url: URL) {
        switch url.pathExtension.lowercased() {
        case "png": self = .png
        case "jpg", "jpeg": self = .jpeg
        case "heic", "heif": self = .heic
        case "tif", "tiff": self = .tiff
        case "bmp": self = .bmp
        case "gif": self = .gif
        default: return nil
        }
    }
}

struct ExportSheet: View {
    let imageSize: CGSize
    let initialFormat: ImageExportFormat
    let itemCount: Int
    let onExport: (ImageExportOptions) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var options: ImageExportOptions

    init(
        imageSize: CGSize,
        initialFormat: ImageExportFormat,
        itemCount: Int = 1,
        onExport: @escaping (ImageExportOptions) -> Void
    ) {
        self.imageSize = imageSize
        self.initialFormat = initialFormat
        self.itemCount = itemCount
        self.onExport = onExport
        _options = State(initialValue: ImageExportOptions(format: initialFormat))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(itemCount > 1 ? "Export Images" : "Export Image")
                        .font(.title2.weight(.semibold))
                    Text(itemCount > 1 ? "Give the whole batch a clean send-off." : "Make the file small, sharp, and ready to go.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Form {
                Picker("Format", selection: $options.format) {
                    ForEach(ImageExportFormat.allCases) { format in
                        Text(format.label).tag(format)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent("Size") {
                    Text("\(Int(imageSize.width)) × \(Int(imageSize.height)) px")
                        .font(.system(.body, design: .monospaced))
                }

                if options.format.supportsQuality {
                    LabeledContent("Quality") {
                        HStack {
                            Slider(value: $options.quality, in: 0.2...1, step: 0.01)
                                .frame(width: 190)
                            Text("\(Int(options.quality * 100))%")
                                .font(.system(.caption, design: .monospaced))
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }

                if options.format.supportsCompression {
                    LabeledContent("PNG compression") {
                        HStack {
                            Slider(value: $options.pngCompression, in: 0...1, step: 0.01)
                                .frame(width: 190)
                            Text("\(Int(options.pngCompression * 100))%")
                                .font(.system(.caption, design: .monospaced))
                                .frame(width: 40, alignment: .trailing)
                        }
                    }

                    Text("PNG stays lossless. Higher compression may take a little longer, but keeps the pixels intact.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !options.format.supportsAlpha {
                    LabeledContent("Background") {
                        ColorPicker(
                            "Background colour",
                            selection: backgroundBinding,
                            supportsOpacity: false
                        )
                        .labelsHidden()
                    }

                    Text("\(options.format.label) cannot preserve transparent pixels. Transparent areas will use this background colour.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("Remove metadata", isOn: $options.removesMetadata)

                Toggle("Reveal exported file in Finder", isOn: $options.revealAfterExport)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Choose Location…") {
                    onExport(options)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 530)
    }

    private var backgroundBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: options.backgroundColor) },
            set: { options.backgroundColor = NSColor($0) }
        )
    }
}
