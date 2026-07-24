import AppKit
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum QuickActionStep: Codable, Equatable, Identifiable {
    case removeBackground
    case upscale(scale: Double)
    case canvas(width: Int, height: Int)

    var id: String {
        switch self {
        case .removeBackground: "remove-background"
        case .upscale(let scale): "upscale-\(Int(scale))x"
        case .canvas(let width, let height): "canvas-\(width)x\(height)"
        }
    }

    var label: String {
        switch self {
        case .removeBackground:
            "Remove Background"
        case .upscale(let scale):
            "Upscale \(Int(scale))x"
        case .canvas(let width, let height):
            "Canvas \(width) x \(height)"
        }
    }
}

struct QuickActionDefinition: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var isEnabled: Bool
    var steps: [QuickActionStep]

    var outputSuffix: String {
        id.replacingOccurrences(of: "_", with: "-")
    }

    var prefersPNGOutput: Bool {
        steps.contains { step in
            if case .removeBackground = step { return true }
            if case .canvas = step { return true }
            return false
        }
    }
}

enum QuickActionDefaults {
    static let definitions: [QuickActionDefinition] = [
        QuickActionDefinition(
            id: "upscale-2x",
            title: "Upscale 2x",
            isEnabled: true,
            steps: [.upscale(scale: 2)]
        ),
        QuickActionDefinition(
            id: "upscale-4x",
            title: "Upscale 4x",
            isEnabled: true,
            steps: [.upscale(scale: 4)]
        ),
        QuickActionDefinition(
            id: "remove-background",
            title: "Remove Background",
            isEnabled: true,
            steps: [.removeBackground]
        ),
        QuickActionDefinition(
            id: "remove-background-upscale-2x",
            title: "Remove Background + Upscale 2x",
            isEnabled: true,
            steps: [.removeBackground, .upscale(scale: 2)]
        ),
        QuickActionDefinition(
            id: "marketplace-square",
            title: "Product Square 1024",
            isEnabled: true,
            steps: [.removeBackground, .upscale(scale: 2), .canvas(width: 1024, height: 1024)]
        )
    ]

    static func customDefinition() -> QuickActionDefinition {
        QuickActionDefinition(
            id: "custom-\(UUID().uuidString)",
            title: "Custom Quick Action",
            isEnabled: true,
            steps: [.removeBackground, .upscale(scale: 2), .canvas(width: 1024, height: 1024)]
        )
    }

    static func isDefault(id: String) -> Bool {
        definitions.contains { $0.id == id }
    }
}

struct QuickActionLaunch {
    let definition: QuickActionDefinition
    let sourceURLs: [URL]
}

enum QuickActionError: LocalizedError {
    case missingAction
    case unknownAction(String)
    case missingPaths
    case unsupportedMedia
    case unsupportedFormat
    case imagePreparationFailed
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .missingAction:
            "Missing quick action. Use --quick-action with a configured action id."
        case .unknownAction(let value):
            "\(value) is not an enabled quick action."
        case .missingPaths:
            "Missing image paths for the quick action."
        case .unsupportedMedia:
            "Quick actions are available for images only."
        case .unsupportedFormat:
            "ImageKid cannot export this image type from a quick action yet."
        case .imagePreparationFailed:
            "ImageKid could not prepare this image."
        case .pngEncodingFailed:
            "ImageKid could not encode the background-removed image."
        }
    }
}

enum QuickActionRunner {
    static func parse(arguments: [String] = CommandLine.arguments) throws -> QuickActionLaunch? {
        if let legacy = try parseLegacyQuickUpscale(arguments: arguments) {
            return legacy
        }

        guard let flagIndex = arguments.firstIndex(of: "--quick-action") else {
            return nil
        }

        let actionIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(actionIndex) else {
            throw QuickActionError.missingAction
        }

        let actionValue = arguments[actionIndex]
        guard let definition = configuredDefinitions().first(where: { $0.id == actionValue && $0.isEnabled }) else {
            throw QuickActionError.unknownAction(actionValue)
        }

        let pathStartIndex = arguments.index(after: actionIndex)
        let paths = arguments[pathStartIndex...]
        guard !paths.isEmpty else {
            throw QuickActionError.missingPaths
        }

        return QuickActionLaunch(
            definition: definition,
            sourceURLs: paths.map { URL(fileURLWithPath: $0) }
        )
    }

    @MainActor
    static func run(definition: QuickActionDefinition, sourceURL: URL) async throws -> URL {
        var image = try image(from: sourceURL)

        for step in definition.steps {
            image = try await apply(step, to: image)
        }

        let format = outputFormat(for: definition, sourceURL: sourceURL)
        let outputURL = uniqueOutputURL(
            for: sourceURL,
            suffix: definition.outputSuffix,
            fileExtension: format.fileExtension
        )
        try write(image, to: outputURL, format: format)
        return outputURL
    }

    static func uniqueOutputURL(for sourceURL: URL, suffix: String, fileExtension: String) -> URL {
        let directory = sourceURL.deletingLastPathComponent()
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let preferredURL = directory.appendingPathComponent("\(baseName)-\(suffix).\(fileExtension)")

        guard FileManager.default.fileExists(atPath: preferredURL.path) else {
            return preferredURL
        }

        var index = 2
        while true {
            let url = directory.appendingPathComponent("\(baseName)-\(suffix)-\(index).\(fileExtension)")
            if !FileManager.default.fileExists(atPath: url.path) {
                return url
            }
            index += 1
        }
    }

    private static func parseLegacyQuickUpscale(arguments: [String]) throws -> QuickActionLaunch? {
        guard let flagIndex = arguments.firstIndex(of: "--quick-upscale") else {
            return nil
        }

        let scaleIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(scaleIndex) else {
            throw QuickActionError.missingAction
        }

        let scaleValue = arguments[scaleIndex]
        let definition: QuickActionDefinition
        switch scaleValue {
        case "2", "2.0":
            definition = QuickActionDefaults.definitions[0]
        case "4", "4.0":
            definition = QuickActionDefaults.definitions[1]
        default:
            throw QuickActionError.unknownAction("upscale \(scaleValue)x")
        }

        let pathStartIndex = arguments.index(after: scaleIndex)
        let paths = arguments[pathStartIndex...]
        guard !paths.isEmpty else {
            throw QuickActionError.missingPaths
        }

        return QuickActionLaunch(
            definition: definition,
            sourceURLs: paths.map { URL(fileURLWithPath: $0) }
        )
    }

    static func configuredDefinitions() -> [QuickActionDefinition] {
        guard let data = UserDefaults.standard.string(forKey: "quickActionsJSON")?.data(using: .utf8),
              let definitions = try? JSONDecoder().decode([QuickActionDefinition].self, from: data),
              !definitions.isEmpty else {
            return QuickActionDefaults.definitions
        }
        return definitions
    }

    @MainActor
    private static func apply(_ step: QuickActionStep, to image: NSImage) async throws -> NSImage {
        switch step {
        case .removeBackground:
            guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw QuickActionError.imagePreparationFailed
            }
            let output = try await BackgroundRemovalService.removeBackground(
                from: source, engine: BackgroundRemovalService.effectiveEngine)
            return NSImage(cgImage: output, size: CGSize(width: output.width, height: output.height))

        case .upscale(let scale):
            let pixelSize = pixelSize(of: image)
            let targetSize = CGSize(
                width: max(1, (pixelSize.width * scale).rounded()),
                height: max(1, (pixelSize.height * scale).rounded())
            )
            let contentMode = UpscaleContentMode(
                rawValue: UserDefaults.standard.string(forKey: "upscaleContentMode") ?? ""
            ) ?? .textAndUI
            if UserDefaults.standard.string(forKey: "upscaleEngine") == UpscaleEngine.bestQuality.rawValue,
               contentMode == .textAndUI || ImageUpscaleService.isBestQualityRuntimeAvailable {
                return try ImageUpscaleService.upscale(image, to: targetSize, contentMode: contentMode)
            }
            return resize(image, to: targetSize)

        case .canvas(let width, let height):
            return drawCanvas(image, size: CGSize(width: width, height: height))
        }
    }

    private static func outputFormat(for definition: QuickActionDefinition, sourceURL: URL) -> ImageExportFormat {
        if definition.prefersPNGOutput {
            return .png
        }
        return ImageExportFormat(url: sourceURL) ?? .png
    }

    @MainActor
    private static func image(from url: URL) throws -> NSImage {
        let data = try Data(contentsOf: url)
        guard let image = NSImage(data: data) else {
            throw QuickActionError.unsupportedMedia
        }
        return image
    }

    private static func resize(_ image: NSImage, to targetSize: CGSize) -> NSImage {
        let result = NSImage(size: targetSize)
        result.lockFocus()
        defer { result.unlockFocus() }
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: CGRect(origin: .zero, size: targetSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        return result
    }

    private static func drawCanvas(_ image: NSImage, size: CGSize) -> NSImage {
        let result = NSImage(size: size)
        let imageSize = pixelSize(of: image)
        let scale = min(size.width / max(imageSize.width, 1), size.height / max(imageSize.height, 1))
        let fittedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let rect = CGRect(
            x: (size.width - fittedSize.width) / 2,
            y: (size.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )

        result.lockFocus()
        defer { result.unlockFocus() }
        NSColor.clear.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        return result
    }

    private static func pixelSize(of image: NSImage) -> CGSize {
        if let representation = image.representations.first {
            return CGSize(width: representation.pixelsWide, height: representation.pixelsHigh)
        }
        return image.size
    }

    private static func write(_ image: NSImage, to url: URL, format: ImageExportFormat) throws {
        if format == .heic {
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString, 1, nil) else {
                throw QuickActionError.pngEncodingFailed
            }
            CGImageDestinationAddImage(destination, cgImage, nil)
            guard CGImageDestinationFinalize(destination) else {
                throw QuickActionError.pngEncodingFailed
            }
            return
        }

        guard let bitmapType = format.bitmapType,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: bitmapType, properties: [:]) else {
            throw QuickActionError.pngEncodingFailed
        }
        try data.write(to: url, options: .atomic)
    }
}

@MainActor
final class QuickActionModel: ObservableObject {
    enum ItemState: Equatable {
        case pending
        case processing
        case finished(URL)
        case failed(String)

        var label: String {
            switch self {
            case .pending: "Waiting"
            case .processing: "Processing"
            case .finished: "Done"
            case .failed: "Failed"
            }
        }
    }

    struct Item: Identifiable, Equatable {
        let id = UUID()
        let sourceURL: URL
        var state: ItemState = .pending
    }

    let definition: QuickActionDefinition
    @Published var items: [Item]
    @Published var didStart = false

    init(launch: QuickActionLaunch) {
        definition = launch.definition
        items = launch.sourceURLs.map { Item(sourceURL: $0) }
    }

    var isComplete: Bool {
        items.allSatisfy { item in
            switch item.state {
            case .finished, .failed: true
            case .pending, .processing: false
            }
        }
    }

    var summary: String {
        let finishedCount = items.filter {
            if case .finished = $0.state { return true }
            return false
        }.count
        let failedCount = items.filter {
            if case .failed = $0.state { return true }
            return false
        }.count

        if isComplete {
            if failedCount == 0 {
                return "\(finishedCount) completed"
            }
            return "\(finishedCount) completed, \(failedCount) failed"
        }

        return "Processing \(items.count) file\(items.count == 1 ? "" : "s")"
    }

    func start() async {
        guard !didStart else { return }
        didStart = true
        FileHandle.standardOutput.write(Data("ImageKid quick action started: \(definition.id)\n".utf8))

        for index in items.indices {
            items[index].state = .processing
            do {
                let outputURL = try await QuickActionRunner.run(definition: definition, sourceURL: items[index].sourceURL)
                items[index].state = .finished(outputURL)
                FileHandle.standardOutput.write(Data("Wrote \(outputURL.path)\n".utf8))
            } catch {
                items[index].state = .failed(error.localizedDescription)
                FileHandle.standardError.write(
                    Data("ImageKid quick action failed for \(items[index].sourceURL.path): \(error.localizedDescription)\n".utf8)
                )
            }
        }
    }
}

struct QuickActionProgressView: View {
    @ObservedObject private var model: QuickActionModel

    init(model: QuickActionModel) {
        self.model = model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: model.definition.steps.contains(.removeBackground) ? "person.crop.rectangle" : "arrow.up.left.and.arrow.down.right")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.definition.title)
                        .font(.title3.weight(.semibold))
                    Text(model.summary)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !model.isComplete {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            List(model.items) { item in
                HStack(spacing: 12) {
                    statusImage(for: item.state)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.sourceURL.lastPathComponent)
                            .lineLimit(1)
                        detailText(for: item.state)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 3)
            }
            .frame(minHeight: 160)

            HStack {
                Spacer()
                Button(model.isComplete ? "Close" : "Cancel") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(22)
        .frame(width: 520, height: 320)
    }

    @ViewBuilder
    private func statusImage(for state: QuickActionModel.ItemState) -> some View {
        switch state {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
        case .processing:
            ProgressView()
                .controlSize(.small)
        case .finished:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func detailText(for state: QuickActionModel.ItemState) -> some View {
        switch state {
        case .pending, .processing:
            Text(state.label)
        case .finished(let url):
            Text(url.lastPathComponent)
        case .failed(let message):
            Text(message)
        }
    }
}
