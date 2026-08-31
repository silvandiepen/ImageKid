import SwiftUI
import UniformTypeIdentifiers

/// The Slicer window: a compact unified toolbar and the canvas below it.
struct SlicerWindow: View {
    @ObservedObject var model: SlicerDocumentModel

    @State private var showExportOptions = false

    var body: some View {
        content
            .frame(minWidth: 760, minHeight: 540)
            .background(VisualEffectBackground())
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                model.handleDrop(providers: providers)
            }
            .alert(item: $model.alert) { alert in
                Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
            }
            .background(SlicerWindowAccessor(onWindow: SlicerWindowCoordinator.adopt))
            .toolbar { toolbarContent }
    }

    // MARK: - Toolbar
    //
    // A real unified toolbar rather than a bar drawn into the content: it is
    // the compact native height, it stays out of the traffic lights' way on
    // its own, and it drags the window.

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                model.openImage()
            } label: {
                Image(systemName: "folder")
            }
            .toolTip("Open an image (⌘O)")
            .accessibilityLabel("Open")
            .accessibilityIdentifier("slicer.open")
        }

        ToolbarItem(placement: .navigation) {
            HStack(spacing: 8) {
                if let source = model.source {
                    Text(source.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(Int(source.pixelSize.width))×\(Int(source.pixelSize.height))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Text(statusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("slicer.sliceCount")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 8) {
                if let summary = model.lastExport {
                    exportSummary(summary)
                }

                if model.isExporting {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Saving")
                }

                if let source = model.source {
                    Button {
                        showExportOptions.toggle()
                    } label: {
                        Label(
                            model.exports.options.summary(
                                sourceType: source.outputType,
                                sourceExtension: source.fileExtension
                            ),
                            systemImage: "slider.horizontal.3"
                        )
                    }
                    .toolTip("Export options — format, scale, quality, naming")
                    .accessibilityIdentifier("slicer.exportOptions")
                    .popover(isPresented: $showExportOptions, arrowEdge: .bottom) {
                        ExportOptionsView(model: model, store: model.exports, source: source)
                    }
                }

                if model.hasMultipleImages, model.activeTool != .crop {
                    Button("Export All…") { model.exportAll() }
                        .disabled(!model.canExportAll)
                        .accessibilityIdentifier("slicer.exportAll")
                }

                primaryAction
            }
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        if model.activeTool == .crop {
            Button("Crop & Save…") { model.cropAndSave() }
                .keyboardShortcut("s")
                .buttonStyle(.borderedProminent)
                .disabled(!model.canCropAndSave)
                .accessibilityIdentifier("slicer.cropSave")
        } else if !model.slices.isEmpty {
            Button("Save") { model.save() }
                .keyboardShortcut("s")
                .buttonStyle(.borderedProminent)
                .disabled(!model.canSave)
                .accessibilityIdentifier("slicer.save")
        }
    }

    private var statusLabel: String {
        if model.activeTool == .crop {
            guard let crop = model.cropPixelRect else { return "Drag a crop region" }
            return "Crop \(Int(crop.width)) × \(Int(crop.height))"
        }
        let count = model.slices.count
        guard count > 0 else { return "No slices yet" }
        return "\(count) \(count == 1 ? "slice" : "slices")"
    }

    private func exportSummary(_ summary: SlicerDocumentModel.ExportSummary) -> some View {
        HStack(spacing: 6) {
            Text(summary.headline)
                .font(.caption)
                .foregroundStyle(summary.failures.isEmpty ? .secondary : Color.orange)
                .lineLimit(1)
                .accessibilityIdentifier("slicer.exportSummary")
            if !summary.created.isEmpty {
                Button("Reveal") { model.revealLastExport() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .toolTip(summary.failures.map { "\($0.sliceName): \($0.message)" }.joined(separator: "\n"))
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let source = model.source {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    SlicerCanvas(model: model, source: source)
                        .accessibilityIdentifier("slicer.canvas")
                        .overlay(alignment: .bottom) {
                            SlicerToolbar(model: model)
                                .padding(.bottom, 18)
                        }

                    if model.isSidebarVisible {
                        SliceListSidebar(model: model, source: source)
                    }
                }

                if model.hasMultipleImages {
                    SlicerFilmstrip(model: model)
                }
            }
            // A fresh canvas per image: the drag state and draft rectangles
            // belong to the image they were started on.
            .id(model.currentImageID)
        } else if model.isLoading {
            centered { ProgressView("Opening image…") }
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        centered {
            VStack(spacing: 14) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 44, weight: .ultraLight))
                    .foregroundStyle(.secondary)
                    .padding(22)
                    .background { SlicerSurface.glass(Circle()) }
                    .overlay(Circle().strokeBorder(SlicerSurface.hairline))
                Text("Drop an image here")
                    .font(.title3)
                Text("Draw the regions you want, then Save to create every slice as its own file.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                Button("Open Image…") { model.openImage() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("o")
                    .accessibilityIdentifier("slicer.openEmptyState")
            }
        }
    }

    private func centered<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
