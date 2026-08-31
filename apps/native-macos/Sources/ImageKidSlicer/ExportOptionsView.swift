import SwiftUI
import UniformTypeIdentifiers

/// The export settings popover: what Save writes, how big, and what it is
/// called — with the resulting filename shown live so none of it is a guess.
struct ExportOptionsView: View {
    @ObservedObject var model: SlicerDocumentModel
    /// Observed separately from the model: the options live in their own
    /// store so they can be persisted and injected on their own.
    @ObservedObject var store: ExportOptionsStore
    let source: SlicerDocumentModel.Source

    private var options: Binding<ExportOptions> { $store.options }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            format
            if store.options.isLossy(sourceType: source.outputType) {
                quality
            }
            sizing
            if store.options.sizing == .fixed {
                fixedSize
            } else {
                scale
            }
            naming

            Divider()

            preview
        }
        .padding(16)
        .frame(width: 320)
    }

    private var format: some View {
        VStack(alignment: .leading, spacing: 5) {
            label("Format")
            Picker("Format", selection: options.format) {
                ForEach(ExportOptions.Format.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .labelsHidden()
            .accessibilityIdentifier("slicer.export.format")
            Text(sourceFormatNote)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var sourceFormatNote: String {
        let resolved = store.options.resolved(
            sourceType: source.outputType,
            sourceExtension: source.fileExtension
        )
        return "Writes .\(resolved.fileExtension) — the source is .\(source.fileExtension)."
    }

    private var quality: some View {
        VStack(alignment: .leading, spacing: 5) {
            label("Quality — \(Int((store.options.quality * 100).rounded()))%")
            Slider(value: options.quality, in: 0.1...1)
                .accessibilityIdentifier("slicer.export.quality")
        }
    }

    private var sizing: some View {
        VStack(alignment: .leading, spacing: 5) {
            label("Size")
            Picker("Size", selection: options.sizing) {
                ForEach(ExportOptions.Sizing.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .accessibilityIdentifier("slicer.export.sizing")
        }
    }

    /// Every file the same shape, whatever the slices measure.
    private var fixedSize: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField("", value: options.outputWidth, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                    .accessibilityIdentifier("slicer.export.width")
                Text("×").foregroundStyle(.secondary)
                TextField("", value: options.outputHeight, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                    .accessibilityIdentifier("slicer.export.height")
                Text("px").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            Picker("Fit", selection: options.fit) {
                ForEach(ExportOptions.Fit.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .accessibilityIdentifier("slicer.export.fit")

            Text(store.options.fit.detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if store.options.fit == .contain {
                HStack(spacing: 6) {
                    Text("Padding").font(.caption).foregroundStyle(.secondary)
                    Picker("Padding", selection: options.padding) {
                        ForEach(ExportOptions.Padding.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                    .accessibilityIdentifier("slicer.export.padding")
                }
                if store.options.padding == .transparent,
                   !store.options.resolved(sourceType: source.outputType, sourceExtension: source.fileExtension)
                    .type.conforms(to: .png) {
                    Text("This format has no transparency; the padding will come out black.")
                        .font(.caption2)
                        .foregroundStyle(Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var scale: some View {
        VStack(alignment: .leading, spacing: 5) {
            label("Scale")
            HStack(spacing: 6) {
                ForEach(ExportOptions.presetScales, id: \.self) { percent in
                    Button("\(percent)%") {
                        store.options.scalePercent = percent
                    }
                    .buttonStyle(.bordered)
                    .tint(store.options.scalePercent == percent ? .accentColor : nil)
                    .accessibilityIdentifier("slicer.export.scale.\(percent)")
                }
            }
            .controlSize(.small)

            HStack(spacing: 6) {
                TextField("", value: options.scalePercent, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 66)
                    .accessibilityIdentifier("slicer.export.scalePercent")
                Text("%").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(scaleNote)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// What the setting does to a real region, so the numbers mean something.
    private var scaleNote: String {
        let reference = model.slices.first?.rect
            ?? model.cropRect
            ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        guard let pixels = SliceGeometry.pixelRect(reference, pixelSize: source.pixelSize) else { return "" }
        let out = store.options.outputPixelSize(for: pixels)
        return "\(Int(pixels.width))×\(Int(pixels.height)) → \(Int(out.width))×\(Int(out.height))"
    }

    private var naming: some View {
        VStack(alignment: .leading, spacing: 5) {
            label("Filename prefix")
            TextField("none", text: options.namePrefix)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("slicer.export.prefix")
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 3) {
            label("First file")
            Text(firstFileName)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityIdentifier("slicer.export.preview")
        }
    }

    private var firstFileName: String {
        let options = store.options
        let output = options.resolved(sourceType: source.outputType, sourceExtension: source.fileExtension)
        let base = SliceExporter.fileName(
            sourceName: source.displayName,
            index: 0,
            count: max(model.slices.count, 1),
            customName: model.slices.first?.name,
            prefix: options.sanitizedPrefix
        )
        return "\(base).\(output.fileExtension)"
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}
