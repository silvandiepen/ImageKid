import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The export settings, as a sheet.
///
/// These grew from one format picker into format, quality, sizing, fit,
/// padding and naming — unrelated decisions that had no business sharing one
/// column in a popover. Grouping them into tabs keeps each screen to one
/// question, and gives the live preview the room it needs to be worth having:
/// Contain and Cover are far easier to choose between by looking than by
/// reading.
struct ExportOptionsSheet: View {
    @ObservedObject var model: SlicerDocumentModel
    @ObservedObject var store: ExportOptionsStore
    let source: SlicerDocumentModel.Source

    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .format

    enum Tab: String, CaseIterable, Identifiable {
        case format, size, naming

        var id: String { rawValue }

        var label: String {
            switch self {
            case .format: "Format"
            case .size: "Size"
            case .naming: "Naming"
            }
        }

        var symbol: String {
            switch self {
            case .format: "photo"
            case .size: "aspectratio"
            case .naming: "textformat"
            }
        }
    }

    private var options: Binding<ExportOptions> { $store.options }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            TabView(selection: $tab) {
                formatTab
                    .tabItem { Label(Tab.format.label, systemImage: Tab.format.symbol) }
                    .tag(Tab.format)
                sizeTab
                    .tabItem { Label(Tab.size.label, systemImage: Tab.size.symbol) }
                    .tag(Tab.size)
                namingTab
                    .tabItem { Label(Tab.naming.label, systemImage: Tab.naming.symbol) }
                    .tag(Tab.naming)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            Divider()
            footer
        }
        .frame(width: 560, height: 440)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Export Options")
                    .font(.headline)
                    // Identifies the sheet. Deliberately on the title rather
                    // than the root: an identifier on a container propagates
                    // down and overwrites every child's own.
                    .accessibilityIdentifier("slicer.export.sheet")
                Text("Applies to Save, Crop & Save, Export All, and slices dragged out.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(store.options.summary(sourceType: source.outputType, sourceExtension: source.fileExtension))
                .font(.caption.monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.08), in: Capsule())
                .accessibilityIdentifier("slicer.export.summary")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: - Format

    private var formatTab: some View {
        Form {
            Section {
                Picker("Format", selection: options.format) {
                    ForEach(ExportOptions.Format.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .accessibilityIdentifier("slicer.export.format")

                LabeledContent("Writes") {
                    Text(".\(resolved.fileExtension)")
                        .font(.body.monospaced())
                }
            } header: {
                Text("File type")
            } footer: {
                Text("The source is .\(source.fileExtension). “Same as source” keeps it where it can be written, and falls back to PNG where it cannot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if store.options.isLossy(sourceType: source.outputType) {
                Section {
                    Slider(value: options.quality, in: 0.1...1) {
                        Text("Quality")
                    } minimumValueLabel: {
                        Text("10%").font(.caption2)
                    } maximumValueLabel: {
                        Text("100%").font(.caption2)
                    }
                    .accessibilityIdentifier("slicer.export.quality")

                    LabeledContent("Quality") {
                        Text("\(Int((store.options.quality * 100).rounded()))%")
                            .font(.body.monospacedDigit())
                    }
                } footer: {
                    Text("Only lossy formats use this.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var resolved: (type: UTType, fileExtension: String) {
        store.options.resolved(sourceType: source.outputType, sourceExtension: source.fileExtension)
    }

    // MARK: - Size

    private var sizeTab: some View {
        Form {
            Section {
                Picker("Size", selection: options.sizing) {
                    ForEach(ExportOptions.Sizing.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("slicer.export.sizing")
            } footer: {
                Text(store.options.sizing == .fixed
                     ? "Every file comes out the same, whatever the slice measures."
                     : "Each file keeps the shape of its own slice.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if store.options.sizing == .fixed {
                Section("Output") {
                    LabeledContent("Width") {
                        TextField("", value: options.outputWidth, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            .accessibilityIdentifier("slicer.export.width")
                    }
                    LabeledContent("Height") {
                        TextField("", value: options.outputHeight, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            .accessibilityIdentifier("slicer.export.height")
                    }
                }

                Section {
                    Picker("Fit", selection: options.fit) {
                        ForEach(ExportOptions.Fit.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("slicer.export.fit")

                    if store.options.fit == .contain {
                        Picker("Padding", selection: options.padding) {
                            ForEach(ExportOptions.Padding.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .accessibilityIdentifier("slicer.export.padding")
                    }
                } header: {
                    Text("Fit")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.options.fit.detail)
                        if store.options.fit == .contain,
                           store.options.padding == .transparent,
                           !resolved.type.conforms(to: .png) {
                            Text("This format has no transparency; the padding will come out black.")
                                .foregroundStyle(Color.orange)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } else {
                Section("Scale") {
                    HStack(spacing: 6) {
                        ForEach(ExportOptions.presetScales, id: \.self) { percent in
                            Button("\(percent)%") { store.options.scalePercent = percent }
                                .buttonStyle(.bordered)
                                .tint(store.options.scalePercent == percent ? .accentColor : nil)
                                .accessibilityIdentifier("slicer.export.scale.\(percent)")
                        }
                        Spacer(minLength: 0)
                    }
                    .controlSize(.small)

                    LabeledContent("Exact") {
                        HStack(spacing: 4) {
                            TextField("", value: options.scalePercent, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 74)
                                .accessibilityIdentifier("slicer.export.scalePercent")
                            Text("%").foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Naming

    private var namingTab: some View {
        Form {
            Section {
                LabeledContent("Prefix") {
                    TextField("none", text: options.namePrefix)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .accessibilityIdentifier("slicer.export.prefix")
                }
            } header: {
                Text("Filename")
            } footer: {
                Text("Slices keep their own names where they have one, and are numbered in order where they do not. Anything unsafe for a filename is replaced.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Files this would write") {
                ForEach(Array(exampleNames.enumerated()), id: \.offset) { index, name in
                    Text(name)
                        .font(.body.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .accessibilityIdentifier("slicer.export.example.\(index)")
                }
            }
        }
        .formStyle(.grouped)
    }

    /// The first few filenames, so a prefix can be judged before committing.
    private var exampleNames: [String] {
        let count = max(model.slices.count, 1)
        return (0..<min(count, 3)).map { index in
            let base = SliceExporter.fileName(
                sourceName: source.displayName,
                index: index,
                count: count,
                customName: model.slices.indices.contains(index) ? model.slices[index].name : nil,
                prefix: store.options.sanitizedPrefix
            )
            return "\(base).\(resolved.fileExtension)"
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            ExportPreview(source: source, slice: model.slices.first, options: store.options)

            VStack(alignment: .leading, spacing: 3) {
                Text("Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(previewDescription)
                    .font(.caption.monospacedDigit())
                    .accessibilityIdentifier("slicer.export.previewSize")
            }

            Spacer(minLength: 0)

            Button("Reset") { store.options = ExportOptions() }
                .accessibilityIdentifier("slicer.export.reset")

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("slicer.export.done")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var previewDescription: String {
        let reference = model.slices.first?.rect
            ?? model.cropRect
            ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        guard let pixels = SliceGeometry.pixelRect(reference, pixelSize: source.pixelSize) else {
            return "—"
        }
        let out = store.options.outputPixelSize(for: pixels)
        return "\(Int(pixels.width))×\(Int(pixels.height)) → \(Int(out.width))×\(Int(out.height))"
    }
}

/// A live render of what one slice will actually look like once written.
///
/// Drawn from the display preview rather than the full-resolution source, so
/// typing in a size field does not resample a 12000px crop on every keystroke.
private struct ExportPreview: View {
    let source: SlicerDocumentModel.Source
    let slice: Slice?
    let options: ExportOptions

    private static let box = CGSize(width: 104, height: 78)

    var body: some View {
        ZStack {
            CheckerboardBackground()
            if let image = rendered {
                Image(nsImage: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: Self.box.width, height: Self.box.height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15))
        )
        .accessibilityHidden(true)
    }

    private var rendered: CGImage? {
        guard let preview = source.preview.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let previewSize = CGSize(width: preview.width, height: preview.height)
        let rect = slice?.rect ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        guard
            let pixelRect = SliceGeometry.pixelRect(rect, pixelSize: previewSize),
            let cropped = preview.cropping(to: pixelRect)
        else { return nil }

        // Render at the real aspect the options ask for, but no larger than
        // the box needs — the point is to show shape and padding, not detail.
        var preview​Options = options
        if options.sizing == .fixed {
            let scale = min(
                Self.box.width / options.fixedSize.width,
                Self.box.height / options.fixedSize.height,
                1
            )
            preview​Options.outputWidth = max(Int(options.fixedSize.width * scale), 1)
            preview​Options.outputHeight = max(Int(options.fixedSize.height * scale), 1)
        } else {
            preview​Options.scalePercent = 100
        }
        return try? SliceImageIO.rendered(cropped, options: preview​Options)
    }
}

/// The transparency checkerboard behind the preview, so transparent padding
/// reads as transparent rather than as white.
private struct CheckerboardBackground: View {
    private let square: CGFloat = 7

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(0.16)))
            var row = 0
            var y: CGFloat = 0
            while y < size.height {
                var column = 0
                var x: CGFloat = 0
                while x < size.width {
                    if (row + column).isMultiple(of: 2) {
                        context.fill(
                            Path(CGRect(x: x, y: y, width: square, height: square)),
                            with: .color(.black.opacity(0.22))
                        )
                    }
                    x += square
                    column += 1
                }
                y += square
                row += 1
            }
        }
    }
}
