import AVKit
import ImageKidInference
import ImageKidKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var model: InferenceModel
    @State private var isShowingSettings = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var player: AVPlayer?
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var preferredColumn: NavigationSplitViewColumn = .detail
    @State private var isExporting = false
    @State private var isRefining = false
    @State private var isPromptEditing = false
    @State private var isEnhancing = false
    @State private var activeTool: EditorTool?
    @State private var cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var annotations: [Annotation] = []
    @State private var draftAnnotation: Annotation?
    @State private var annotationKind: Annotation.Kind = .freehand
    @State private var annotationColor: Color = .red
    @State private var annotationWidthFraction: CGFloat = 0.008
    @State private var textSizeFraction: CGFloat = 0.05
    @State private var isEnteringText = false
    @State private var textInput = ""
    @State private var pendingTextLocation: CGPoint?
    @State private var selectedAnnotationID: UUID?
    @State private var editingAnnotationID: UUID?
    @State private var isShowingLayersSheet = false
    @State private var currentSample: SampledColor?
    @State private var sampleLocation: CGPoint?

    // The iPad Draw/Text options float over the canvas as a shared-kit panel
    // (same mechanic and chrome as the Mac apps); its resting spot and
    // minimized state survive relaunches.
    @AppStorage("ipad.annotatePanel.offset.x") private var annotatePanelX: Double = 0
    @AppStorage("ipad.annotatePanel.offset.y") private var annotatePanelY: Double = 0
    @AppStorage("ipad.annotatePanel.minimized") private var isAnnotatePanelMinimized = false

    // The Layers panel follows the same pattern: toggled from the toolbar,
    // floating on regular widths, with its resting spot persisted.
    @AppStorage("ipad.layersPanel.shown") private var isLayersPanelShown = false
    @AppStorage("ipad.layersPanel.offset.x") private var layersPanelX: Double = 0
    @AppStorage("ipad.layersPanel.offset.y") private var layersPanelY: Double = 0
    @AppStorage("ipad.layersPanel.minimized") private var isLayersPanelMinimized = false

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
                    if !usesFloatingAnnotatePanel {
                        toolInspector
                    }
                    bottomToolbar
                }
            }
            .padding(.bottom, 6)
        }
        .overlay(alignment: .topLeading) {
            if usesFloatingAnnotatePanel {
                annotateFloatingPanel
                    .padding(16)
            }
        }
        .overlay(alignment: .topTrailing) {
            if usesFloatingLayersPanel {
                layersFloatingPanel
                    .padding(16)
            }
        }
        .background { hardwareDeleteShortcut }
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
            if model.workingImage != nil, model.videoURL == nil {
                Button {
                    if isRegularWidth {
                        isLayersPanelShown.toggle()
                        isLayersPanelMinimized = false
                    } else {
                        isShowingLayersSheet = true
                    }
                } label: {
                    Image(systemName: "square.3.layers.3d")
                }
                .accessibilityLabel("Layers")
            }
            if model.workingImage != nil {
                Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!model.canUndo)
                Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!model.canRedo)
                Button { isExporting = true } label: { Image(systemName: "square.and.arrow.up") }
            }
            Button { isShowingSettings = true } label: { Image(systemName: "gearshape") }
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
            .sheet(isPresented: $isRefining) {
                if let original = model.refineRestoreImage?.normalizedCGImage(),
                   let current = model.workingImage?.normalizedCGImage() {
                    RefineView(original: original, current: current) { rendered in
                        model.applyEditedImage(rendered, status: "Refined")
                        activeTool = nil
                    }
                }
            }
            .sheet(isPresented: $isPromptEditing) {
                PromptEditView { prompt, apiKey in
                    model.promptEdit(prompt: prompt, apiKey: apiKey)
                }
            }
            .sheet(isPresented: $isEnhancing) {
                if let cgImage = model.workingImage?.normalizedCGImage() {
                    EnhanceView(model: model, pixelSize: CGSize(width: cgImage.width, height: cgImage.height))
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $isShowingLayersSheet) {
                NavigationStack {
                    LayersPanelContent(
                        annotations: $annotations,
                        selectedAnnotationID: $selectedAnnotationID
                    )
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .navigationTitle("Layers")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { isShowingLayersSheet = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .alert("Add text", isPresented: $isEnteringText) {
                TextField("Text", text: $textInput)
                Button("Add") { addTextAnnotation() }
                Button("Cancel", role: .cancel) {
                    pendingTextLocation = nil
                    textInput = ""
                }
            } message: {
                Text("Type the words to place on the picture.")
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

    /// iPad only: Draw/Text options leave the bottom stack and float over the
    /// canvas. Compact widths keep the existing inline inspector.
    private var usesFloatingAnnotatePanel: Bool {
        isRegularWidth && model.workingImage != nil && model.videoURL == nil
            && (activeTool == .draw || activeTool == .text)
    }

    private var annotatePanelOffset: Binding<CGSize> {
        Binding(
            get: { CGSize(width: annotatePanelX, height: annotatePanelY) },
            set: { newValue in
                annotatePanelX = newValue.width
                annotatePanelY = newValue.height
            }
        )
    }

    /// The shared-kit floating panel hosting the Draw/Text options — draggable
    /// from its header, snapping to the same 20pt grid as the Mac apps, and
    /// minimizable to the shared chip.
    @ViewBuilder
    private var annotateFloatingPanel: some View {
        let isText = activeTool == .text
        if isAnnotatePanelMinimized {
            MinimizedPanelChip(
                systemImage: isText ? "textformat" : "pencil.tip.crop.circle",
                isActive: true
            ) {
                isAnnotatePanelMinimized = false
            }
        } else {
            FloatingToolPanel(
                title: isText ? "Text" : "Draw",
                systemImage: isText ? "textformat" : "pencil.tip.crop.circle",
                width: 340,
                offset: annotatePanelOffset,
                onMinimize: { isAnnotatePanelMinimized = true },
                snapStep: 20
            ) {
                AnnotationControls(
                    selectedTool: $annotationKind,
                    color: $annotationColor,
                    widthFraction: $annotationWidthFraction,
                    textSizeFraction: $textSizeFraction,
                    annotations: $annotations,
                    selectedAnnotationID: $selectedAnnotationID,
                    defaultKind: isText ? .text : .freehand,
                    onCancel: {
                        resetAnnotations()
                        activeTool = nil
                    },
                    onApply: applyAnnotations
                )
                .darkPanelControl()
                // Native controls (segmented picker, bordered buttons) should
                // render their dark variants on the dark-glass chrome.
                .environment(\.colorScheme, .dark)
            }
        }
    }

    /// The Layers panel floats on regular widths whenever an image is open;
    /// compact widths get the same content as a sheet from the toolbar button.
    private var usesFloatingLayersPanel: Bool {
        isRegularWidth && isLayersPanelShown && model.workingImage != nil && model.videoURL == nil
    }

    private var layersPanelOffset: Binding<CGSize> {
        Binding(
            get: { CGSize(width: layersPanelX, height: layersPanelY) },
            set: { newValue in
                layersPanelX = newValue.width
                layersPanelY = newValue.height
            }
        )
    }

    @ViewBuilder
    private var layersFloatingPanel: some View {
        if isLayersPanelMinimized {
            MinimizedPanelChip(systemImage: "square.3.layers.3d", isActive: true) {
                isLayersPanelMinimized = false
            }
        } else {
            FloatingToolPanel(
                title: "Layers",
                systemImage: "square.3.layers.3d",
                width: 300,
                offset: layersPanelOffset,
                onMinimize: { isLayersPanelMinimized = true },
                snapStep: 20
            ) {
                LayersPanelContent(
                    annotations: $annotations,
                    selectedAnnotationID: $selectedAnnotationID,
                    listMaxHeight: 280
                )
                .darkPanelControl()
                .environment(\.colorScheme, .dark)
            }
        }
    }

    /// Hidden button so Backspace/Delete on a hardware keyboard removes the
    /// selected annotation — but never while typing into a text field.
    private var hardwareDeleteShortcut: some View {
        Button(action: deleteSelectedAnnotation) {
            EmptyView()
        }
        .keyboardShortcut(.delete, modifiers: [])
        .disabled(selectedAnnotationID == nil || editingAnnotationID != nil || isEnteringText)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func deleteSelectedAnnotation() {
        guard let id = selectedAnnotationID else { return }
        annotations.removeAll { $0.id == id }
        selectedAnnotationID = nil
        if editingAnnotationID == id { editingAnnotationID = nil }
    }

    /// The canvas fills the whole editor area; the image sits on top with a border
    /// that marks its exact bounds (like the macOS viewport).
    private var preview: some View {
        ZStack {
            canvasBackground.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea(edges: .bottom)
            } else if let display = model.workingImage {
                editingPreview(for: display)
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

    @ViewBuilder
    private func editingPreview(for display: UIImage) -> some View {
        Group {
            if let activeTool, activeTool.usesEditingCanvas {
                InlineEditingCanvas(
                    image: display,
                    activeTool: activeTool,
                    cornerRadius: settings.imageCornerRadius,
                    borderColor: settings.canvasBorderColor,
                    showBorder: settings.showCanvasBorder,
                    cropRect: $cropRect,
                    annotations: $annotations,
                    draftAnnotation: $draftAnnotation,
                    selectedAnnotationID: $selectedAnnotationID,
                    editingAnnotationID: $editingAnnotationID,
                    annotationKind: annotationToolKind,
                    annotationColor: annotationColor,
                    annotationWidthFraction: annotationWidthFraction,
                    textSizeFraction: textSizeFraction,
                    currentSample: $currentSample,
                    sampleLocation: $sampleLocation,
                    onTextLocation: { location in
                        pendingTextLocation = location
                        textInput = ""
                        isEnteringText = true
                    }
                )
            } else {
                ZoomableImageView(
                    image: display,
                    cornerRadius: settings.imageCornerRadius,
                    borderColor: settings.canvasBorderColor,
                    showBorder: settings.showCanvasBorder
                )
            }
        }
        .padding(isRegularWidth ? 16 : 8)
    }

    /// Full-bleed canvas backdrop: checkerboard or a solid colour, from Settings.
    @ViewBuilder
    private var canvasBackground: some View {
        if settings.canvasBackground == .checkerboard {
            CheckerboardBackground()
        } else {
            settings.canvasColor
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

    /// macOS-style floating tool bar. Touch gestures still own pan/zoom; tools
    /// that need supporting controls reveal an inspector above the canvas.
    private var bottomToolbar: some View {
        HStack(spacing: 5) {
            toolButton(.colour)
            toolButton(.crop)
            toolButton(.resize)
            toolButton(.draw)
            toolButton(.text)
            Divider().frame(height: 26).padding(.horizontal, 2)
            toolButton(.background)
            magicMenu
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

    @ViewBuilder
    private var toolInspector: some View {
        if let currentTool = activeTool {
            switch currentTool {
            case .resize:
                if let cgImage = model.workingImage?.normalizedCGImage() {
                    ResizeInspector(model: model, pixelSize: CGSize(width: cgImage.width, height: cgImage.height)) {
                        self.activeTool = nil
                    }
                }
            case .background:
                BackgroundInspector(model: model, onRefine: {
                    isRefining = true
                }, onClose: {
                    self.activeTool = nil
                })
            case .colour:
                ColourInspector(model: model, current: currentSample, onSave: {
                    if let currentSample { model.addSampledColor(currentSample) }
                }, onClose: {
                    self.activeTool = nil
                })
            case .crop:
                CropInspector(image: model.workingImage, crop: $cropRect, onCancel: {
                    cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                    activeTool = nil
                }, onApply: {
                    model.applyCrop(normalizedRect: cropRect)
                    cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                    activeTool = nil
                })
            case .draw, .text:
                AnnotationInspector(
                    selectedTool: $annotationKind,
                    color: $annotationColor,
                    widthFraction: $annotationWidthFraction,
                    textSizeFraction: $textSizeFraction,
                    annotations: $annotations,
                    selectedAnnotationID: $selectedAnnotationID,
                    defaultKind: activeTool == .text ? .text : .freehand,
                    onCancel: {
                        resetAnnotations()
                        activeTool = nil
                    },
                    onApply: applyAnnotations
                )
            }
        }
    }

    private func toolButton(_ tool: EditorTool) -> some View {
        Button {
            switch tool {
            case .crop:
                activate(tool)
            case .draw:
                activate(tool)
            case .text:
                activate(tool)
            case .resize, .background, .colour:
                activate(tool)
            }
        } label: {
            Image(systemName: tool.symbolName)
                .font(.system(size: 18, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(activeTool == tool ? .white : .primary)
                .frame(width: 40, height: 40)
                .background(
                    activeTool == tool ? Color.accentColor : Color.primary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tool.label)
    }

    private var annotationToolKind: Annotation.Kind {
        activeTool == .text ? .text : annotationKind
    }

    private func activate(_ tool: EditorTool) {
        if activeTool == tool {
            activeTool = nil
            return
        }
        if tool != .draw, tool != .text { resetAnnotations() }
        if tool != .colour {
            currentSample = nil
            sampleLocation = nil
        }
        if tool == .crop {
            cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        if tool == .draw, annotationKind == .text {
            annotationKind = .freehand
        }
        if tool == .text {
            annotationKind = .text
        }
        activeTool = tool
    }

    private func resetAnnotations() {
        annotations = []
        draftAnnotation = nil
        pendingTextLocation = nil
        textInput = ""
        selectedAnnotationID = nil
        editingAnnotationID = nil
    }

    private func addTextAnnotation() {
        let trimmed = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let pendingTextLocation else { return }
        var annotation = Annotation(kind: .text, color: annotationColor, widthFraction: annotationWidthFraction)
        annotation.start = pendingTextLocation
        annotation.text = trimmed
        annotation.fontFraction = textSizeFraction
        annotations.append(annotation)
        selectedAnnotationID = annotation.id
        self.pendingTextLocation = nil
        textInput = ""
    }

    private func applyAnnotations() {
        guard let base = model.workingImage?.normalizedCGImage(),
              let rendered = AnnotationRasterizer.render(annotations, onto: base) else { return }
        model.applyEditedImage(rendered, status: "Annotated")
        resetAnnotations()
        activeTool = nil
    }

    /// The "Magic" entry point: a context menu grouping AI-powered actions —
    /// on-device Enhance, prompt-based AI Edit (and, in future, filters).
    private var magicMenu: some View {
        Menu {
            Button {
                activeTool = nil
                isEnhancing = true
            } label: {
                Label("Enhance Image", systemImage: "wand.and.stars")
            }
            .disabled(model.workingImage == nil)
            Button {
                activeTool = nil
                isPromptEditing = true
            } label: {
                Label("AI Edit…", systemImage: "text.bubble")
            }
            .disabled(model.workingImage == nil)
        } label: {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 18, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .accessibilityLabel("Magic")
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

private enum EditorTool: String, CaseIterable, Identifiable {
    case colour
    case crop
    case resize
    case draw
    case text
    case background

    var id: String { rawValue }

    var label: String {
        switch self {
        case .colour: "Colour picker"
        case .crop: "Crop"
        case .resize: "Resize"
        case .draw: "Draw"
        case .text: "Text"
        case .background: "Remove background"
        }
    }

    var symbolName: String {
        switch self {
        case .colour: "eyedropper"
        case .crop: "crop"
        case .resize: "arrow.up.left.and.arrow.down.right"
        case .draw: "pencil.tip.crop.circle"
        case .text: "textformat"
        case .background: "eraser"
        }
    }

    var usesEditingCanvas: Bool {
        switch self {
        case .colour, .crop, .draw, .text: true
        case .resize, .background: false
        }
    }
}

private struct InspectorPanel<Content: View>: View {
    let title: String
    let systemImage: String
    let onClose: () -> Void
    @ViewBuilder var content: Content
    @State private var panelOffset: CGSize = .zero
    @State private var dragStartOffset: CGSize = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close \(title)")
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        panelOffset = CGSize(
                            width: dragStartOffset.width + value.translation.width,
                            height: dragStartOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        dragStartOffset = panelOffset
                    }
            )
            content
        }
        .padding(14)
        .frame(maxWidth: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.14))
        )
        .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
        .padding(.horizontal, 14)
        .offset(panelOffset)
    }
}

private struct ResizeInspector: View {
    @ObservedObject var model: InferenceModel
    let pixelSize: CGSize
    let onClose: () -> Void

    @State private var width: Int
    @State private var height: Int
    @State private var lockAspect = true

    private let aspect: CGFloat

    init(model: InferenceModel, pixelSize: CGSize, onClose: @escaping () -> Void) {
        self.model = model
        self.pixelSize = pixelSize
        self.onClose = onClose
        _width = State(initialValue: max(1, Int(pixelSize.width.rounded())))
        _height = State(initialValue: max(1, Int(pixelSize.height.rounded())))
        aspect = pixelSize.width / max(pixelSize.height, 1)
    }

    var body: some View {
        InspectorPanel(title: "Resize", systemImage: "arrow.up.left.and.arrow.down.right", onClose: onClose) {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    DimensionField(label: "W", value: $width) { syncHeight() }
                    DimensionField(label: "H", value: $height) {}
                        .disabled(lockAspect)
                    Toggle("Lock", isOn: $lockAspect)
                        .labelsHidden()
                        .onChange(of: lockAspect) { _, locked in
                            if locked { syncHeight() }
                        }
                }

                HStack(spacing: 8) {
                    ForEach([50, 100, 200, 400], id: \.self) { percent in
                        Button("\(percent)%") { applyPercent(percent) }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                    }
                }

                Button {
                    model.applyResize(width: max(1, width), height: max(1, height))
                    onClose()
                } label: {
                    Label("Apply Resize", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Text("Want to enlarge with more detail? Use Magic ▸ Enhance Image.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func syncHeight() {
        if lockAspect {
            height = max(1, Int((CGFloat(width) / aspect).rounded()))
        }
    }

    private func applyPercent(_ percent: Int) {
        let factor = CGFloat(percent) / 100
        width = max(1, Int((pixelSize.width * factor).rounded()))
        height = max(1, Int((pixelSize.height * factor).rounded()))
    }
}

private struct DimensionField: View {
    let label: String
    @Binding var value: Int
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(label, value: $value, format: .number)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .onChange(of: value) { _, _ in onChange() }
            Text("px")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct BackgroundInspector: View {
    @ObservedObject var model: InferenceModel
    let onRefine: () -> Void
    let onClose: () -> Void

    private var pendingModels: [ModelDownloader.Model] {
        [.birefnet, .u2net].filter { !model.downloader.isDownloaded($0) }
    }

    var body: some View {
        InspectorPanel(title: "Background", systemImage: "eraser", onClose: onClose) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.availableBackgroundEngines) { engine in
                    Button {
                        model.removeBackground(engine: engine)
                        onClose()
                    } label: {
                        Label(engine.title, systemImage: engine.systemImage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    onRefine()
                } label: {
                    Label("Refine cutout", systemImage: "lasso")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .disabled(model.refineRestoreImage == nil)

                ForEach(pendingModels) { downloadable in
                    ModelDownloadRow(model: model, downloadable: downloadable)
                }
            }
        }
    }
}

private struct CropInspector: View {
    let image: UIImage?
    @Binding var crop: CGRect
    let onCancel: () -> Void
    let onApply: () -> Void

    var body: some View {
        InspectorPanel(title: "Crop", systemImage: "crop", onClose: onCancel) {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    presetButton("Free", ratio: nil)
                    presetButton("1:1", ratio: (1, 1))
                    presetButton("4:3", ratio: (4, 3))
                    presetButton("3:2", ratio: (3, 2))
                    presetButton("16:9", ratio: (16, 9))
                }
                HStack {
                    Button("Cancel", role: .cancel, action: onCancel)
                        .buttonStyle(.bordered)
                    Button(action: onApply) {
                        Label("Apply Crop", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func presetButton(_ title: String, ratio: (CGFloat, CGFloat)?) -> some View {
        Button(title) {
            withAnimation(.snappy) {
                crop = ratio.map { centeredCrop(ratioW: $0.0, ratioH: $0.1) } ?? CGRect(x: 0, y: 0, width: 1, height: 1)
            }
        }
        .buttonStyle(.bordered)
        .font(.subheadline)
        .frame(maxWidth: .infinity)
    }

    private func centeredCrop(ratioW: CGFloat, ratioH: CGFloat) -> CGRect {
        guard let image else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let targetAspect = ratioW / ratioH
        let imageAspect = image.size.width / max(image.size.height, 1)
        let normalizedWidth: CGFloat
        let normalizedHeight: CGFloat
        if targetAspect > imageAspect {
            normalizedWidth = 1
            normalizedHeight = (image.size.width / targetAspect) / max(image.size.height, 1)
        } else {
            normalizedHeight = 1
            normalizedWidth = (image.size.height * targetAspect) / max(image.size.width, 1)
        }
        return CGRect(
            x: (1 - normalizedWidth) / 2,
            y: (1 - normalizedHeight) / 2,
            width: normalizedWidth,
            height: normalizedHeight
        )
    }
}

private struct AnnotationInspector: View {
    @Binding var selectedTool: Annotation.Kind
    @Binding var color: Color
    @Binding var widthFraction: CGFloat
    @Binding var textSizeFraction: CGFloat
    @Binding var annotations: [Annotation]
    @Binding var selectedAnnotationID: UUID?
    let defaultKind: Annotation.Kind
    let onCancel: () -> Void
    let onApply: () -> Void

    var body: some View {
        InspectorPanel(title: defaultKind == .text ? "Text" : "Draw", systemImage: defaultKind == .text ? "textformat" : "pencil.tip.crop.circle", onClose: onCancel) {
            AnnotationControls(
                selectedTool: $selectedTool,
                color: $color,
                widthFraction: $widthFraction,
                textSizeFraction: $textSizeFraction,
                annotations: $annotations,
                selectedAnnotationID: $selectedAnnotationID,
                defaultKind: defaultKind,
                onCancel: onCancel,
                onApply: onApply
            )
        }
    }
}

/// The Draw/Text option controls, host-agnostic: the compact inline inspector
/// and the iPad floating panel both wrap this.
private struct AnnotationControls: View {
    @Binding var selectedTool: Annotation.Kind
    @Binding var color: Color
    @Binding var widthFraction: CGFloat
    @Binding var textSizeFraction: CGFloat
    @Binding var annotations: [Annotation]
    @Binding var selectedAnnotationID: UUID?
    let defaultKind: Annotation.Kind
    let onCancel: () -> Void
    let onApply: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if defaultKind != .text {
                Picker("Tool", selection: $selectedTool) {
                    ForEach(Annotation.Kind.allCases.filter { $0 != .text }) { kind in
                        Image(systemName: kind.systemImage).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
            }

            HStack(spacing: 14) {
                ColorPicker("Colour", selection: $color, supportsOpacity: false)
                    .labelsHidden()
                VStack(alignment: .leading, spacing: 2) {
                    Text(defaultKind == .text ? "Text size" : "Thickness")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(
                        value: defaultKind == .text ? $textSizeFraction : $widthFraction,
                        in: defaultKind == .text ? 0.02...0.15 : 0.002...0.02
                    )
                }
                Button {
                    if !annotations.isEmpty { annotations.removeLast() }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(annotations.isEmpty)
                if defaultKind == .text {
                    // Deletes the SELECTED text (the per-layer delete the
                    // canvas selection pairs with); the trash below still
                    // clears everything.
                    Button(role: .destructive) {
                        if let id = selectedAnnotationID {
                            annotations.removeAll { $0.id == id }
                            selectedAnnotationID = nil
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .tint(.red)
                    .disabled(selectedAnnotationID == nil)
                    .accessibilityLabel("Delete selected text")
                }
            }

            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
                Button(role: .destructive) {
                    annotations.removeAll()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(annotations.isEmpty)
                Button(action: onApply) {
                    Label("Apply", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(annotations.isEmpty)
            }
        }
    }
}

/// The annotation layer stack, topmost first (annotations draw in array
/// order, so the last element sits on top). Shared by the iPad floating
/// panel and the compact-width sheet; ports the macOS LayersPanel semantics
/// to the iOS annotation model: tap to select, eye to hide, arrows to
/// reorder, trash to delete.
private struct LayersPanelContent: View {
    @Binding var annotations: [Annotation]
    @Binding var selectedAnnotationID: UUID?
    var listMaxHeight: CGFloat?

    /// Front-most first (last in the draw array renders on top).
    private var orderedLayers: [Annotation] { annotations.reversed() }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if annotations.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "square.3.layers.3d")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Draw or add text with the tools below — every mark shows up here as a layer.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 110)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(orderedLayers) { layer in
                            row(layer)
                        }
                    }
                }
                .frame(maxHeight: listMaxHeight ?? .infinity)
                .scrollBounceBehavior(.basedOnSize)

                controlBar
            }
        }
    }

    private func row(_ layer: Annotation) -> some View {
        let isSelected = selectedAnnotationID == layer.id
        return HStack(spacing: 10) {
            Image(systemName: layer.kind.systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 22)
                .opacity(layer.isHidden ? 0.4 : 1)
            Text(label(for: layer))
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .opacity(layer.isHidden ? 0.5 : 1)
            Spacer()
            Button {
                toggleHidden(layer.id)
            } label: {
                Image(systemName: layer.isHidden ? "eye.slash" : "eye")
                    .font(.system(size: 12))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(layer.isHidden ? "Show layer" : "Hide layer")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected ? Color.accentColor.opacity(0.30) : Color.primary.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedAnnotationID = layer.id
        }
    }

    private var controlBar: some View {
        HStack(spacing: 6) {
            control("arrow.up", label: "Bring forward") { moveSelected(forward: true) }
            control("arrow.down", label: "Send backward") { moveSelected(forward: false) }
            Spacer()
            control("trash", label: "Delete layer", role: .destructive) { deleteSelected() }
                .foregroundStyle(.red)
        }
        .disabled(selectedAnnotationID == nil)
        .padding(.top, 2)
    }

    private func control(
        _ symbol: String,
        label: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 34, height: 30)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func label(for layer: Annotation) -> String {
        if layer.isText {
            let text = layer.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? "Text" : text
        }
        return layer.kind.label
    }

    private func selectedIndex() -> Int? {
        guard let id = selectedAnnotationID else { return nil }
        return annotations.firstIndex { $0.id == id }
    }

    /// Forward = towards the viewer = later in the array.
    private func moveSelected(forward: Bool) {
        guard let index = selectedIndex() else { return }
        let target = forward ? index + 1 : index - 1
        guard annotations.indices.contains(target) else { return }
        annotations.swapAt(index, target)
    }

    private func deleteSelected() {
        guard let index = selectedIndex() else { return }
        annotations.remove(at: index)
        selectedAnnotationID = nil
    }

    private func toggleHidden(_ id: UUID) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[index].isHidden.toggle()
    }
}

private struct ColourInspector: View {
    @ObservedObject var model: InferenceModel
    let current: SampledColor?
    let onSave: () -> Void
    let onClose: () -> Void

    var body: some View {
        InspectorPanel(title: "Colours", systemImage: "eyedropper", onClose: onClose) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(current?.color ?? Color(.tertiarySystemFill))
                        .frame(width: 52, height: 52)
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(current?.hex ?? "Pick a pixel")
                            .font(.headline.monospaced())
                        Text(current?.rgb ?? "Drag on the image to sample a colour.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: onSave) {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(current == nil)
                }
                if model.sampledColors.isEmpty {
                    Text("No saved colours yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(model.sampledColors) { swatch in
                                Menu {
                                    Button("Copy \(swatch.hex)") { UIPasteboard.general.string = swatch.hex }
                                    Button("Copy \(swatch.rgb)") { UIPasteboard.general.string = swatch.rgb }
                                    Button("Remove", role: .destructive) { model.removeSampledColor(swatch.id) }
                                } label: {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(swatch.color)
                                        .frame(width: 44, height: 44)
                                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.quaternary))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct InlineEditingCanvas: View {
    let image: UIImage
    let activeTool: EditorTool
    let cornerRadius: CGFloat
    let borderColor: Color
    let showBorder: Bool
    @Binding var cropRect: CGRect
    @Binding var annotations: [Annotation]
    @Binding var draftAnnotation: Annotation?
    @Binding var selectedAnnotationID: UUID?
    @Binding var editingAnnotationID: UUID?
    let annotationKind: Annotation.Kind
    let annotationColor: Color
    let annotationWidthFraction: CGFloat
    let textSizeFraction: CGFloat
    @Binding var currentSample: SampledColor?
    @Binding var sampleLocation: CGPoint?
    let onTextLocation: (CGPoint) -> Void

    @State private var dragStartCrop: CGRect?
    @State private var zoomScale: CGFloat = 1
    @State private var committedZoomScale: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var committedPanOffset: CGSize = .zero
    @State private var isPanning = false
    /// In-flight move of an existing text annotation (id + its start at
    /// gesture begin), so a drag repositions instead of adding new text.
    @State private var textDrag: (id: UUID, origin: CGPoint)?
    /// Whether the inline editor was open when the current touch went down.
    /// The double-tap recogniser can open it between this drag's touch-down
    /// and touch-up, and that fresh editor must not be committed by its own
    /// second tap.
    @State private var wasEditingAtTouchDown = false
    @State private var editingText = ""
    @FocusState private var inlineEditorFocused: Bool

    var body: some View {
        GeometryReader { geo in
            let fitRect = AVMakeRect(
                aspectRatio: image.size,
                insideRect: CGRect(origin: .zero, size: geo.size)
            )
            let imageRect = transformedRect(fitRect)

            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: imageRect.width, height: imageRect.height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay {
                        if showBorder {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(borderColor, lineWidth: 1)
                        }
                    }
                    .position(x: imageRect.midX, y: imageRect.midY)

                if activeTool == .crop {
                    cropOverlay(in: imageRect)
                }

                if activeTool == .draw || activeTool == .text {
                    annotationOverlay(in: imageRect)
                    if let editing = annotations.first(where: { $0.id == editingAnnotationID }) {
                        inlineTextEditor(for: editing, in: imageRect)
                    }
                }

                if activeTool == .colour, let sampleLocation {
                    let point = CGPoint(
                        x: imageRect.minX + sampleLocation.x * imageRect.width,
                        y: imageRect.minY + sampleLocation.y * imageRect.height
                    )
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 2)
                        .background(Circle().strokeBorder(Color.black.opacity(0.45), lineWidth: 4))
                        .frame(width: 30, height: 30)
                        .position(point)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(canvasGesture(in: imageRect))
            .simultaneousGesture(doubleTapGesture(in: imageRect))
            .simultaneousGesture(zoomGesture())
            .overlay(alignment: .topTrailing) {
                zoomControls
                    .padding(12)
            }
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 0) {
            zoomButton("minus") { setZoom(zoomScale / 1.5) }
                .disabled(zoomScale <= 1.01)
            Button { fitCanvas() } label: {
                Text(zoomScale <= 1.01 ? "Fit" : "\(Int((zoomScale * 100).rounded()))%")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .frame(minWidth: 46)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            zoomButton("plus") { setZoom(zoomScale * 1.5) }
                .disabled(zoomScale >= 8)
            Button {
                isPanning.toggle()
            } label: {
                Image(systemName: isPanning ? "hand.draw.fill" : "hand.draw")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 36)
                    .contentShape(Rectangle())
                    .foregroundStyle(isPanning ? .white : .primary)
                    .background(isPanning ? Color.accentColor : Color.clear, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPanning ? "Stop moving canvas" : "Move canvas")
        }
        .foregroundStyle(.primary)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
    }

    private func zoomButton(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 40, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func cropOverlay(in imageRect: CGRect) -> some View {
        let rect = viewRect(for: cropRect, in: imageRect)
        ZStack {
            Path { path in
                path.addRect(imageRect)
                path.addRect(rect)
            }
            .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))

            Rectangle()
                .strokeBorder(Color.white, lineWidth: 1.5)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)

            cropHandle(.topLeft, in: imageRect)
            cropHandle(.topRight, in: imageRect)
            cropHandle(.bottomLeft, in: imageRect)
            cropHandle(.bottomRight, in: imageRect)
        }
    }

    private func cropHandle(_ corner: CropCorner, in imageRect: CGRect) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.black.opacity(0.25)))
            .frame(width: 26, height: 26)
            .position(viewPoint(for: corner, in: imageRect))
            .gesture(cropCornerGesture(corner, in: imageRect))
    }

    @ViewBuilder
    private func annotationOverlay(in imageRect: CGRect) -> some View {
        // The Canvas is framed to the image and positioned over it, so its
        // drawing space starts at the image's top-left — map annotations into
        // a zero-origin rect, not into `imageRect` (which would shift them by
        // the image's letterbox/zoom offset a second time).
        let localRect = CGRect(origin: .zero, size: imageRect.size)
        Canvas { context, _ in
            for annotation in annotations + [draftAnnotation].compactMap({ $0 }) {
                if annotation.isHidden || annotation.id == editingAnnotationID { continue }
                if annotation.isText {
                    let resolved = context.resolve(
                        Text(annotation.text.isEmpty ? " " : annotation.text)
                            .font(.system(size: annotation.fontSize(in: localRect)))
                            .foregroundColor(annotation.color)
                    )
                    context.draw(resolved, at: annotation.textOrigin(in: localRect), anchor: .topLeading)
                } else {
                    context.stroke(
                        Path(annotation.path(in: localRect)),
                        with: .color(annotation.color),
                        style: StrokeStyle(
                            lineWidth: annotation.strokeWidth(in: localRect),
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                }
            }

            // Selection border: a white casing under a dashed accent line so
            // it reads against any image content.
            if let selected = annotations.first(where: { $0.id == selectedAnnotationID }),
               !selected.isHidden, selected.id != editingAnnotationID {
                let bounds = selected.selectionBounds(in: localRect).insetBy(dx: -8, dy: -8)
                let border = Path(roundedRect: bounds, cornerRadius: 10)
                context.stroke(
                    border,
                    with: .color(.white.opacity(0.85)),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                context.stroke(
                    border,
                    with: .color(.accentColor),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: [7, 5])
                )
            }
        }
        .frame(width: imageRect.width, height: imageRect.height)
        .position(x: imageRect.midX, y: imageRect.midY)
        .allowsHitTesting(false)
    }

    /// A focused TextField floating at the annotation's spot, styled to match
    /// the text it replaces while the edit is in flight.
    private func inlineTextEditor(for annotation: Annotation, in imageRect: CGRect) -> some View {
        let bounds = annotation.textBounds(in: imageRect)
        let editorWidth = max(bounds.width + 90, 200)
        return TextField("Text", text: $editingText)
            .font(.system(size: annotation.fontSize(in: imageRect)))
            .foregroundStyle(annotation.color)
            .textFieldStyle(.plain)
            .focused($inlineEditorFocused)
            .submitLabel(.done)
            .onSubmit { commitInlineEdit() }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
            )
            .frame(width: editorWidth)
            .position(x: bounds.minX - 8 + editorWidth / 2, y: bounds.midY)
            .onAppear {
                editingText = annotation.text
                inlineEditorFocused = true
            }
            .onDisappear {
                // Tool switches or Apply can dismiss the editor without a
                // submit; commit whatever was typed (no-ops if already done).
                commitInlineEdit()
            }
    }

    private func beginInlineEdit(_ annotation: Annotation) {
        selectedAnnotationID = annotation.id
        editingText = annotation.text
        editingAnnotationID = annotation.id
        inlineEditorFocused = true
    }

    private func commitInlineEdit() {
        guard let id = editingAnnotationID else { return }
        editingAnnotationID = nil
        inlineEditorFocused = false
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            // Clearing the text deletes the annotation, like Backspace would.
            annotations.remove(at: index)
            if selectedAnnotationID == id { selectedAnnotationID = nil }
        } else {
            annotations[index].text = trimmed
        }
    }

    /// Topmost visible text annotation under `location` (view space), with a
    /// small touch slop around the measured text bounds.
    private func textAnnotation(at location: CGPoint, in imageRect: CGRect) -> Annotation? {
        annotations.reversed().first { annotation in
            annotation.isText && !annotation.isHidden
                && annotation.textBounds(in: imageRect).insetBy(dx: -12, dy: -12).contains(location)
        }
    }

    /// Double tap (touch) or double click (trackpad) on a text annotation
    /// starts editing it in place.
    private func doubleTapGesture(in imageRect: CGRect) -> some Gesture {
        SpatialTapGesture(count: 2, coordinateSpace: .local)
            .onEnded { value in
                guard activeTool == .text, !isPanning else { return }
                guard let hit = textAnnotation(at: value.location, in: imageRect) else { return }
                beginInlineEdit(hit)
            }
    }

    private func canvasGesture(in imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if isPanning {
                    panOffset = CGSize(
                        width: committedPanOffset.width + value.translation.width,
                        height: committedPanOffset.height + value.translation.height
                    )
                    return
                }
                switch activeTool {
                case .colour:
                    guard let cgImage = image.normalizedCGImage() else { return }
                    let normalized = normalized(value.location, in: imageRect)
                    sampleLocation = normalized
                    currentSample = PixelSampler.sample(cgImage, at: normalized)
                case .crop:
                    let start = dragStartCrop ?? cropRect
                    if dragStartCrop == nil { dragStartCrop = cropRect }
                    var moved = start
                    moved.origin.x = min(max(0, start.minX + value.translation.width / imageRect.width), 1 - start.width)
                    moved.origin.y = min(max(0, start.minY + value.translation.height / imageRect.height), 1 - start.height)
                    cropRect = moved
                case .draw:
                    let point = normalized(value.location, in: imageRect)
                    if draftAnnotation == nil {
                        var new = Annotation(kind: annotationKind, color: annotationColor, widthFraction: annotationWidthFraction)
                        new.start = point
                        new.end = point
                        new.points = [point]
                        draftAnnotation = new
                    } else {
                        draftAnnotation?.end = point
                        if annotationKind == .freehand { draftAnnotation?.points.append(point) }
                    }
                case .text:
                    wasEditingAtTouchDown = editingAnnotationID != nil
                    // Dragging from an existing text annotation moves it;
                    // taps fall through to selection/placement on end.
                    if textDrag == nil, editingAnnotationID == nil,
                       let hit = textAnnotation(at: value.startLocation, in: imageRect) {
                        textDrag = (hit.id, hit.start)
                        selectedAnnotationID = hit.id
                    }
                    if let textDrag, let index = annotations.firstIndex(where: { $0.id == textDrag.id }) {
                        annotations[index].start = CGPoint(
                            x: min(max(textDrag.origin.x + value.translation.width / imageRect.width, 0), 1),
                            y: min(max(textDrag.origin.y + value.translation.height / imageRect.height, 0), 1)
                        )
                    }
                case .resize, .background:
                    break
                }
            }
            .onEnded { value in
                if isPanning {
                    committedPanOffset = panOffset
                    return
                }
                switch activeTool {
                case .crop:
                    dragStartCrop = nil
                case .draw:
                    if let draftAnnotation { annotations.append(draftAnnotation) }
                    draftAnnotation = nil
                case .text:
                    let wasMovingText = textDrag != nil
                    textDrag = nil
                    if wasEditingAtTouchDown {
                        // Tapping outside the inline editor commits the edit.
                        commitInlineEdit()
                    } else if !wasMovingText,
                              hypot(value.translation.width, value.translation.height) < 6 {
                        // A tap on empty canvas clears the selection and asks
                        // for new text at that spot (the existing flow).
                        selectedAnnotationID = nil
                        onTextLocation(normalized(value.location, in: imageRect))
                    }
                case .colour, .resize, .background:
                    break
                }
            }
    }

    private func zoomGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoomScale = clampedZoom(committedZoomScale * value)
            }
            .onEnded { _ in
                committedZoomScale = zoomScale
                if zoomScale <= 1.01 {
                    panOffset = .zero
                    committedPanOffset = .zero
                }
            }
    }

    private func transformedRect(_ fitRect: CGRect) -> CGRect {
        CGRect(
            x: fitRect.midX + panOffset.width - (fitRect.width * zoomScale / 2),
            y: fitRect.midY + panOffset.height - (fitRect.height * zoomScale / 2),
            width: fitRect.width * zoomScale,
            height: fitRect.height * zoomScale
        )
    }

    private func setZoom(_ value: CGFloat) {
        withAnimation(.snappy) {
            zoomScale = clampedZoom(value)
            committedZoomScale = zoomScale
            if zoomScale <= 1.01 {
                panOffset = .zero
                committedPanOffset = .zero
            }
        }
    }

    private func fitCanvas() {
        withAnimation(.snappy) {
            zoomScale = 1
            committedZoomScale = 1
            panOffset = .zero
            committedPanOffset = .zero
        }
    }

    private func clampedZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, 1), 8)
    }

    private func cropCornerGesture(_ corner: CropCorner, in imageRect: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragStartCrop ?? cropRect
                if dragStartCrop == nil { dragStartCrop = cropRect }
                cropRect = resized(
                    start,
                    corner: corner,
                    dx: value.translation.width / imageRect.width,
                    dy: value.translation.height / imageRect.height
                )
            }
            .onEnded { _ in dragStartCrop = nil }
    }

    private func normalized(_ point: CGPoint, in imageRect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max((point.x - imageRect.minX) / imageRect.width, 0), 1),
            y: min(max((point.y - imageRect.minY) / imageRect.height, 0), 1)
        )
    }

    private func viewRect(for normalized: CGRect, in imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + normalized.minX * imageRect.width,
            y: imageRect.minY + normalized.minY * imageRect.height,
            width: normalized.width * imageRect.width,
            height: normalized.height * imageRect.height
        )
    }

    private func viewPoint(for corner: CropCorner, in imageRect: CGRect) -> CGPoint {
        let rect = viewRect(for: cropRect, in: imageRect)
        switch corner {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    private func resized(_ start: CGRect, corner: CropCorner, dx: CGFloat, dy: CGFloat) -> CGRect {
        let minSize: CGFloat = 0.1
        var minX = start.minX
        var minY = start.minY
        var maxX = start.maxX
        var maxY = start.maxY

        switch corner {
        case .topLeft:
            minX += dx
            minY += dy
        case .topRight:
            maxX += dx
            minY += dy
        case .bottomLeft:
            minX += dx
            maxY += dy
        case .bottomRight:
            maxX += dx
            maxY += dy
        }

        minX = min(max(0, minX), maxX - minSize)
        minY = min(max(0, minY), maxY - minSize)
        maxX = max(min(1, maxX), minX + minSize)
        maxY = max(min(1, maxY), minY + minSize)

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private enum CropCorner {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
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
        .environmentObject(AppSettings())
}
