import AVKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject var model: InferenceModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var player: AVPlayer?
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var preferredColumn: NavigationSplitViewColumn = .detail
    @State private var isExporting = false
    @State private var isCropping = false
    @State private var isResizing = false
    @State private var isSampling = false
    @State private var isRefining = false
    @State private var isPromptEditing = false
    @State private var isBackgroundTool = false
    @State private var isDrawing = false
    @State private var isTexting = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $preferredColumn) {
            gallerySidebar
        } detail: {
            NavigationStack {
                withEditorSheets(editorContent)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var editorContent: some View {
        ZStack(alignment: .bottom) {
            preview
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 10) {
                statusOverlay
                if model.videoURL != nil {
                    Text("Video playback only. Editing tools apply to images.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                } else if model.workingImage != nil {
                    bottomToolbar
                }
            }
            .padding(.bottom, 6)
        }
        .navigationTitle("ImageKid")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { editorToolbar }
        .onChange(of: pickerItem) { _, newValue in
            loadPickedImage(newValue)
        }
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            PhotosPicker(selection: $pickerItem, matching: .any(of: [.images, .videos])) {
                Label("Choose", systemImage: "photo.on.rectangle")
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if model.workingImage != nil {
                Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!model.canUndo)
                Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!model.canRedo)
                Button { isExporting = true } label: { Image(systemName: "square.and.arrow.up") }
            }
        }
    }

    /// The tool sheets and error alert, split out to keep `body` type-checkable.
    @ViewBuilder
    private func withEditorSheets(_ content: some View) -> some View {
        content
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
                    ResizeView(model: model, pixelSize: CGSize(width: cgImage.width, height: cgImage.height)) { width, height in
                        model.applyResize(width: width, height: height)
                    }
                }
            }
            .sheet(isPresented: $isDrawing) {
                if let image = model.workingImage {
                    AnnotateView(image: image, initialKind: .freehand) { rendered in
                        model.applyEditedImage(rendered, status: "Annotated")
                    }
                }
            }
            .sheet(isPresented: $isTexting) {
                if let image = model.workingImage {
                    AnnotateView(image: image, initialKind: .text) { rendered in
                        model.applyEditedImage(rendered, status: "Annotated")
                    }
                }
            }
            .sheet(isPresented: $isSampling) {
                if let cgImage = model.workingImage?.normalizedCGImage() {
                    ColorSampleView(image: cgImage, model: model)
                }
            }
            .sheet(isPresented: $isRefining) {
                if let original = model.refineRestoreImage?.normalizedCGImage(),
                   let current = model.workingImage?.normalizedCGImage() {
                    RefineView(original: original, current: current) { rendered in
                        model.applyEditedImage(rendered, status: "Refined")
                    }
                }
            }
            .sheet(isPresented: $isPromptEditing) {
                PromptEditView { prompt, apiKey in
                    model.promptEdit(prompt: prompt, apiKey: apiKey)
                }
            }
            .sheet(isPresented: $isBackgroundTool) {
                BackgroundToolSheet(model: model) { isRefining = true }
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

    private var isRegularWidth: Bool { horizontalSizeClass == .regular }

    /// On iPad the canvas is framed and centred instead of stretching edge-to-edge.
    private var canvasMaxWidth: CGFloat { isRegularWidth ? 1000 : .infinity }

    private var preview: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(isRegularWidth ? 24 : 10)
                    .frame(maxWidth: canvasMaxWidth)
            } else if let display = model.workingImage {
                // Checkerboard only sits behind an actual image (transparency read-out).
                ZStack {
                    CheckerboardBackground()
                    ZoomableImageView(image: display).padding(8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color(.separator), lineWidth: 1)
                )
                .padding(isRegularWidth ? 24 : 8)
                .frame(maxWidth: canvasMaxWidth)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if model.isBusy {
                ProgressView(value: model.progress)
                    .progressViewStyle(.circular)
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    /// Friendly empty state with a prominent add affordance (works on iPhone and iPad).
    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 54))
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text("No pictures yet")
                    .font(.title2.weight(.bold))
                Text("Add a photo to edit, or a video to play. Everything you open stays in your workspace above.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            PhotosPicker(selection: $pickerItem, matching: .any(of: [.images, .videos])) {
                Label("Add Photo or Video", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(Capsule())
        }
        .frame(maxWidth: 460)
        .padding(40)
    }

    /// Sidebar listing every picture in the workspace (toggleable, not always shown).
    private var gallerySidebar: some View {
        List(selection: sidebarSelection) {
            if model.items.isEmpty {
                Text("No pictures yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.items) { item in
                    HStack(spacing: 12) {
                        Image(uiImage: item.current)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 46, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(Color(.separator))
                            )
                        Text(itemLabel(item))
                    }
                    .tag(item.id)
                }
                .onDelete { offsets in
                    for index in offsets { model.removeItem(model.items[index].id) }
                }
            }
        }
        .navigationTitle("Pictures")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PhotosPicker(selection: $pickerItem, matching: .any(of: [.images, .videos])) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add picture")
            }
        }
    }

    private var sidebarSelection: Binding<UUID?> {
        Binding(
            get: { model.selectedItemID },
            set: { newValue in
                if let id = newValue {
                    player = nil
                    model.selectItem(id)
                    preferredColumn = .detail
                }
            }
        )
    }

    private func itemLabel(_ item: EditorItem) -> String {
        if let index = model.items.firstIndex(where: { $0.id == item.id }) {
            return "Picture \(index + 1)"
        }
        return "Picture"
    }

    /// Floating status pill above the toolbar (mirrors the macOS viewport status).
    @ViewBuilder
    private var statusOverlay: some View {
        if let statusText = model.statusText, !statusText.isEmpty {
            HStack(spacing: 8) {
                if model.isBusy { ProgressView().controlSize(.small) }
                Text(statusText).font(.subheadline)
                if model.isEdited && !model.isBusy {
                    Divider().frame(height: 14)
                    Button("Revert") { model.revertToOriginal() }
                        .font(.subheadline)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        }
    }

    /// macOS-style floating tool bar; each tool opens a sheet. Order mirrors the
    /// macOS toolbar (pan/select are omitted — on touch you pan/zoom directly).
    private var bottomToolbar: some View {
        HStack(spacing: 5) {
            toolButton("eyedropper", "Colour picker") { isSampling = true }
            toolButton("crop", "Crop") { isCropping = true }
            toolButton("arrow.up.left.and.arrow.down.right", "Resize") { isResizing = true }
            toolButton("pencil.tip.crop.circle", "Draw") { isDrawing = true }
            toolButton("textformat", "Text") { isTexting = true }
            Divider().frame(height: 26).padding(.horizontal, 2)
            toolButton("eraser", "Remove background") { isBackgroundTool = true }
            toolButton("sparkles", "Magic edit") { isPromptEditing = true }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        )
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        .disabled(model.isBusy)
    }

    private func toolButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func loadPickedImage(_ item: PhotosPickerItem?) {
        guard let item else { return }
        let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
        Task { @MainActor in
            if isVideo {
                if let movie = try? await item.loadTransferable(type: Movie.self) {
                    model.setVideo(movie.url)
                    player = AVPlayer(url: movie.url)
                }
            } else if let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) {
                player = nil
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
    ContentView(model: InferenceModel())
}
