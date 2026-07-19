import PhotosUI
import SwiftUI

struct ContentView: View {
    @StateObject private var model = InferenceModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var isExporting = false
    @State private var isCropping = false
    @State private var isResizing = false
    @State private var isAnnotating = false
    @State private var isSampling = false
    @State private var isRefining = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                preview
                ScrollView { controls }
                    .frame(maxHeight: 340)
                statusRow
            }
            .padding()
            .navigationTitle("ImageKid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Choose", systemImage: "photo.on.rectangle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if model.workingImage != nil {
                        Button {
                            isExporting = true
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .onChange(of: pickerItem) { _, newValue in
                loadPickedImage(newValue)
            }
            .sheet(isPresented: $isExporting) {
                if let cgImage = model.workingImage?.normalizedCGImage() {
                    ExportView(image: cgImage)
                }
            }
            .sheet(isPresented: $isCropping) {
                if let image = model.workingImage {
                    CropView(image: image) { rect in
                        model.applyCrop(normalizedRect: rect)
                    }
                }
            }
            .sheet(isPresented: $isResizing) {
                if let cgImage = model.workingImage?.normalizedCGImage() {
                    ResizeView(pixelSize: CGSize(width: cgImage.width, height: cgImage.height)) { width, height in
                        model.applyResize(width: width, height: height)
                    }
                }
            }
            .sheet(isPresented: $isAnnotating) {
                if let image = model.workingImage {
                    AnnotateView(image: image) { rendered in
                        model.applyEditedImage(rendered, status: "Annotated")
                    }
                }
            }
            .sheet(isPresented: $isSampling) {
                if let cgImage = model.workingImage?.normalizedCGImage() {
                    ColorSampleView(image: cgImage)
                }
            }
            .sheet(isPresented: $isRefining) {
                if let original = model.sourceImage?.normalizedCGImage(),
                   let current = model.workingImage?.normalizedCGImage() {
                    RefineView(original: original, current: current) { rendered in
                        model.applyEditedImage(rendered, status: "Refined")
                    }
                }
            }
            .alert(
                "Something went wrong",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                ),
                actions: { Button("OK", role: .cancel) {} },
                message: { Text(model.errorMessage ?? "") }
            )
        }
    }

    private var preview: some View {
        ZStack {
            CheckerboardBackground()
            if let display = model.workingImage {
                ZoomableImageView(image: display)
                    .padding(8)
            } else {
                ContentUnavailableView(
                    "No image",
                    systemImage: "photo",
                    description: Text("Choose a photo to upscale or remove its background.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            if model.isBusy {
                ProgressView(value: model.progress)
                    .progressViewStyle(.circular)
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            section("Background") {
                actionButton("Remove (Built-in)", systemImage: "person.crop.rectangle") {
                    model.removeBackground(bestQuality: false)
                }
                actionButton(
                    "Remove (Best Quality)",
                    systemImage: "sparkles",
                    enabled: model.bestQualityBackgroundAvailable
                ) {
                    model.removeBackground(bestQuality: true)
                }
                actionButton("Refine cutout", systemImage: "lasso") { isRefining = true }
            }

            section("Upscale") {
                actionButton("2× (Standard)", systemImage: "arrow.up.left.and.arrow.down.right") {
                    model.upscale(scale: 2, bestQuality: false)
                }
                actionButton(
                    "4× (Best Quality)",
                    systemImage: "sparkles",
                    enabled: model.bestQualityUpscaleAvailable
                ) {
                    model.upscale(scale: 4, bestQuality: true)
                }
            }

            section("Transform") {
                actionButton("Crop", systemImage: "crop") { isCropping = true }
                actionButton("Resize", systemImage: "arrow.up.left.and.arrow.down.right.square") { isResizing = true }
            }

            section("Annotate") {
                actionButton("Draw, shapes, text", systemImage: "pencil.tip.crop.circle") { isAnnotating = true }
            }

            section("Inspect") {
                actionButton("Colour picker", systemImage: "eyedropper") { isSampling = true }
            }

            if !model.bestQualityBackgroundAvailable || !model.bestQualityUpscaleAvailable {
                Text("Best Quality needs the Core ML models bundled in the app. See tools/coreml-conversion.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 16) {
            if let statusText = model.statusText {
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.sourceImage != nil {
                Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!model.canUndo)
                Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!model.canRedo)
                if model.isEdited {
                    Button("Revert") { model.revertToOriginal() }
                        .font(.subheadline)
                }
            }
        }
        .frame(minHeight: 20)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            HStack(spacing: 10) { content() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!enabled || model.isBusy || model.sourceImage == nil)
    }

    private func loadPickedImage(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task { @MainActor in
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                model.setSource(image)
            }
        }
    }
}

/// A light/dark checkerboard so transparent results read clearly.
private struct CheckerboardBackground: View {
    var square: CGFloat = 16

    var body: some View {
        Canvas { context, size in
            let columns = Int((size.width / square).rounded(.up))
            let rows = Int((size.height / square).rounded(.up))
            for row in 0..<max(rows, 1) {
                for column in 0..<max(columns, 1) where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(
                        x: CGFloat(column) * square,
                        y: CGFloat(row) * square,
                        width: square,
                        height: square
                    )
                    context.fill(Path(rect), with: .color(.gray.opacity(0.18)))
                }
            }
        }
        .background(Color(.secondarySystemBackground))
    }
}

#Preview {
    ContentView()
}
