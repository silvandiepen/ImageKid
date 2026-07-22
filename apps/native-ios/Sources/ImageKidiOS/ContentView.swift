import AVKit
import ImageKidInference
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
    @State private var draftAnnotation: Annotation?
    @State private var isEditingTextInline = false
    @State private var selectedAnnotationID: UUID?
    @State private var editingTextID: UUID?
    @State private var annotationKind: Annotation.Kind = .freehand
    @State private var annotationColor: Color = .red
    @State private var annotationWidthFraction: CGFloat = 0.008
    @State private var textSizeFraction: CGFloat = 0.05
    @State private var isEnteringText = false
    @State private var textInput = ""
    @State private var pendingTextLocation: CGPoint?
    @State private var currentSample: SampledColor?
    @State private var sampleLocation: CGPoint?

    /// Editable, non-destructive annotations for the selected picture.
    private var annotations: Binding<[Annotation]> {
        Binding(get: { model.annotations }, set: { model.annotations = $0 })
    }

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
                    if activeTextID != nil {
                        // A text is selected or being typed → the text bar replaces
                        // the toolbar. Keyboard avoidance lifts it above the
                        // keyboard while typing.
                        textBar
                    } else {
                        toolInspector
                        bottomToolbar
                    }
                }
            }
            .padding(.bottom, 6)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { editorToolbar }
        .onChange(of: pickerItem) { _, newValue in
            loadPickedImage(newValue)
        }
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if model.workingImage != nil {
                Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!model.canUndo)
                // Show redo only when there's something to redo.
                if model.canRedo {
                    Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                }
            }
            Menu {
                if model.workingImage != nil {
                    Button { isExporting = true } label: { Label("Export…", systemImage: "square.and.arrow.up") }
                }
                Button { isShowingSettings = true } label: { Label("Settings", systemImage: "gearshape") }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    /// The tool sheets and error alert, split out to keep `body` type-checkable.
    @ViewBuilder
    private func withEditorSheets(_ content: some View) -> some View {
        content
            .sheet(isPresented: $isExporting) {
                if let base = model.workingImage,
                   let cgImage = displayWithAnnotations(base).normalizedCGImage() {
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
                    annotations: annotations,
                    draftAnnotation: $draftAnnotation,
                    annotationKind: annotationToolKind,
                    annotationColor: annotationColor,
                    annotationWidthFraction: annotationWidthFraction,
                    textSizeFraction: textSizeFraction,
                    currentSample: $currentSample,
                    sampleLocation: $sampleLocation,
                    isEditingText: $isEditingTextInline,
                    selectedAnnotationID: $selectedAnnotationID,
                    editingTextID: $editingTextID,
                    onTextLocation: { _ in }
                )
            } else {
                ZoomableImageView(
                    image: displayWithAnnotations(display),
                    cornerRadius: settings.imageCornerRadius,
                    borderColor: settings.canvasBorderColor,
                    showBorder: settings.showCanvasBorder
                )
            }
        }
        .padding(isRegularWidth ? 16 : 8)
        // Let the canvas extend up behind the floating top bar so the image is
        // visible (and pannable) in the header area, not clipped below it.
        .ignoresSafeArea(edges: .top)
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
            toolButton(.select)
            toolButton(.colour)
            toolButton(.crop)
            toolButton(.resize)
            toolButton(.draw)
            toolButton(.text)
            Divider().frame(height: 26).padding(.horizontal, 2)
            toolButton(.background)
            magicMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        // More rounded, darker, more transparent (per feedback): a thin blur
        // with a dark tint over it.
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Color.black.opacity(0.34))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(.white.opacity(0.10))
        )
        .shadow(color: .black.opacity(0.30), radius: 20, y: 8)
        .environment(\.colorScheme, .dark) // keep icons light on the dark bar
        .disabled(model.isBusy)
    }

    /// Compact bar shown in place of the toolbar while a text is active: current
    /// colour, size, and font (each adjustable), plus a check to dismiss.
    @ViewBuilder
    private var textBar: some View {
        if let id = activeTextID {
            TextToolbar(annotation: textBinding(id: id), onDone: dismissText)
        }
    }

    /// Finish with a text: drop it if empty, then clear selection/editing so the
    /// normal toolbar returns.
    private func dismissText() {
        if let id = editingTextID ?? selectedAnnotationID,
           let i = model.annotations.firstIndex(where: { $0.id == id }),
           model.annotations[i].isText,
           model.annotations[i].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.annotations.remove(at: i)
        }
        editingTextID = nil
        isEditingTextInline = false
        selectedAnnotationID = nil
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
            case .draw:
                // Shape/brush controls. Text has no panel here — the text bar
                // (and keyboard bar) handle all text settings.
                if activeTextID == nil, !isEditingTextInline {
                    AnnotationInspector(
                        selectedTool: $annotationKind,
                        color: $annotationColor,
                        widthFraction: $annotationWidthFraction,
                        textSizeFraction: $textSizeFraction,
                        annotations: annotations,
                        defaultKind: .freehand,
                        onCancel: {
                            resetAnnotations()
                            activeTool = nil
                        },
                        onApply: applyAnnotations
                    )
                }
            case .select, .text:
                EmptyView()
            }
        }
    }

    private func toolButton(_ tool: EditorTool) -> some View {
        Button {
            activate(tool)
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
        if tool != .draw, tool != .text, tool != .select { resetAnnotations() }
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

    /// The id of the text annotation currently being edited or selected (if any).
    private var activeTextID: UUID? {
        let id = editingTextID ?? selectedAnnotationID
        guard let id, model.annotations.first(where: { $0.id == id })?.isText == true else { return nil }
        return id
    }

    /// A binding to the annotation with `id`, looked up live so it survives
    /// reordering / mutation of the array.
    private func textBinding(id: UUID) -> Binding<Annotation> {
        Binding(
            get: {
                model.annotations.first(where: { $0.id == id })
                    ?? Annotation(kind: .text, color: .red, widthFraction: 0.008)
            },
            set: { newValue in
                if let i = model.annotations.firstIndex(where: { $0.id == id }) {
                    model.annotations[i] = newValue
                }
            }
        )
    }

    /// Clears only the in-progress draft — annotations themselves persist and
    /// stay editable (they are never baked except on export).
    private func resetAnnotations() {
        draftAnnotation = nil
        pendingTextLocation = nil
        textInput = ""
    }

    /// "Done": leave the annotation tools. Annotations stay editable; nothing is
    /// flattened into the image (that only happens on export).
    private func applyAnnotations() {
        activeTool = nil
    }

    /// A UIImage with the current annotations flattened on top, for view-mode
    /// display and export. Returns the base unchanged when there are none.
    private func displayWithAnnotations(_ base: UIImage) -> UIImage {
        guard !model.annotations.isEmpty,
              let cg = base.normalizedCGImage(),
              let rendered = AnnotationRasterizer.render(model.annotations, onto: cg) else {
            return base
        }
        return UIImage(cgImage: rendered)
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
    case select
    case colour
    case crop
    case resize
    case draw
    case text
    case background

    var id: String { rawValue }

    var label: String {
        switch self {
        case .select: "Select"
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
        case .select: "cursorarrow"
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
        case .select, .colour, .crop, .draw, .text: true
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
    @State private var quality: EnhanceQuality = .quick

    private let aspect: CGFloat

    init(model: InferenceModel, pixelSize: CGSize, onClose: @escaping () -> Void) {
        self.model = model
        self.pixelSize = pixelSize
        self.onClose = onClose
        _width = State(initialValue: max(1, Int(pixelSize.width.rounded())))
        _height = State(initialValue: max(1, Int(pixelSize.height.rounded())))
        aspect = pixelSize.width / max(pixelSize.height, 1)
    }

    /// Enlarging → route through AI upscaling (the user only picks quality).
    private var isEnlarging: Bool {
        CGFloat(width) > pixelSize.width || CGFloat(height) > pixelSize.height
    }

    private var qualityReady: Bool { model.enhanceReady(quality) }

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

                // Enlarging always uses AI upscaling — the only choice is quality.
                if isEnlarging {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("AI upscale quality")
                            .font(.caption).foregroundStyle(.secondary)
                        Picker("Quality", selection: $quality) {
                            ForEach(EnhanceQuality.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Text(quality.detail)
                            .font(.caption2).foregroundStyle(.secondary)
                        if !qualityReady, let downloadable = quality.requiredModel {
                            ModelDownloadRow(model: model, downloadable: downloadable)
                        }
                    }
                }

                Button {
                    if isEnlarging {
                        model.applyResize(width: max(1, width), height: max(1, height), upscaleQuality: quality)
                    } else {
                        model.applyResize(width: max(1, width), height: max(1, height))
                    }
                    onClose()
                } label: {
                    Label(isEnlarging ? "Upscale with AI" : "Apply Resize", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isEnlarging && !qualityReady)
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

    @State private var ratioLabel = "Free"

    private let presets: [(String, (CGFloat, CGFloat)?)] = [
        ("Free", nil), ("1:1", (1, 1)), ("4:3", (4, 3)), ("3:2", (3, 2)), ("16:9", (16, 9))
    ]

    var body: some View {
        InspectorPanel(title: "Crop", systemImage: "crop", onClose: onCancel) {
            // Compact single row: ratio presets collapse under one menu button.
            HStack(spacing: 8) {
                Menu {
                    ForEach(presets, id: \.0) { preset in
                        Button(preset.0) { apply(label: preset.0, ratio: preset.1) }
                    }
                } label: {
                    Label(ratioLabel, systemImage: "aspectratio")
                        .frame(minWidth: 74)
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 4)

                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
                Button(action: onApply) {
                    Label("Apply", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func apply(label: String, ratio: (CGFloat, CGFloat)?) {
        ratioLabel = label
        withAnimation(.snappy) {
            crop = ratio.map { centeredCrop(ratioW: $0.0, ratioH: $0.1) } ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        }
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
    let defaultKind: Annotation.Kind
    let onCancel: () -> Void
    let onApply: () -> Void

    var body: some View {
        InspectorPanel(title: defaultKind == .text ? "Text" : "Draw", systemImage: defaultKind == .text ? "textformat" : "pencil.tip.crop.circle", onClose: onCancel) {
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
}

/// Font choices offered for text annotations (label, PostScript name; nil = system).
/// All are built into iOS — no download needed.
let textFontChoices: [(name: String, psName: String?)] = [
    ("System", nil),
    ("Helvetica Neue", "HelveticaNeue"),
    ("Avenir Next", "AvenirNext-Regular"),
    ("Avenir", "Avenir-Book"),
    ("Futura", "Futura-Medium"),
    ("Gill Sans", "GillSans"),
    ("Optima", "Optima-Regular"),
    ("Trebuchet MS", "TrebuchetMS"),
    ("Verdana", "Verdana"),
    ("Arial", "ArialMT"),
    ("Georgia", "Georgia"),
    ("Times New Roman", "TimesNewRomanPSMT"),
    ("Palatino", "Palatino-Roman"),
    ("Baskerville", "Baskerville"),
    ("Didot", "Didot"),
    ("Hoefler Text", "HoeflerText-Regular"),
    ("Cochin", "Cochin"),
    ("American Typewriter", "AmericanTypewriter"),
    ("Courier New", "CourierNewPSMT"),
    ("Menlo", "Menlo-Regular"),
    ("Copperplate", "Copperplate"),
    ("Marker Felt", "MarkerFelt-Thin"),
    ("Noteworthy", "Noteworthy-Light"),
    ("Bradley Hand", "BradleyHandITCTT-Bold"),
    ("Snell Roundhand", "SnellRoundhand"),
    ("Chalkboard", "ChalkboardSE-Regular"),
    ("Chalkduster", "Chalkduster"),
    ("Papyrus", "Papyrus"),
    ("Zapfino", "Zapfino")
]

func textFontLabel(_ psName: String?) -> String {
    textFontChoices.first(where: { $0.psName == psName })?.name ?? "Font"
}

/// A ready-made colour palette (like the macOS app) for quick picks.
let textColorPalette: [Color] = [
    Color(white: 0.0), Color(white: 0.25), Color(white: 0.5), Color(white: 0.75), .white,
    .red, .orange, .yellow, .green, .mint,
    .teal, .cyan, .blue, .indigo, .purple,
    .pink, .brown,
    Color(red: 0.86, green: 0.16, blue: 0.16), Color(red: 0.90, green: 0.49, blue: 0.13), Color(red: 0.95, green: 0.77, blue: 0.06),
    Color(red: 0.18, green: 0.55, blue: 0.34), Color(red: 0.10, green: 0.46, blue: 0.55), Color(red: 0.17, green: 0.24, blue: 0.31),
    Color(red: 0.20, green: 0.29, blue: 0.70), Color(red: 0.42, green: 0.24, blue: 0.60), Color(red: 0.78, green: 0.22, blue: 0.52)
]

/// Compact dark bar shown in place of the toolbar when a text is active:
/// current colour, size and font (each opens a proper picker), plus a check to
/// dismiss. Lifts above the keyboard while typing.
private struct TextToolbar: View {
    @Binding var annotation: Annotation
    let onDone: () -> Void

    @State private var showColor = false
    @State private var showSize = false
    @State private var showFont = false

    var body: some View {
        HStack(spacing: 10) {
            Button { showColor = true } label: {
                chip {
                    Circle().fill(annotation.color).frame(width: 20, height: 20)
                        .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1))
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showColor) {
                ColorPalettePopover(color: $annotation.color).presentationCompactAdaptation(.popover)
            }

            Button { showSize = true } label: {
                chip {
                    HStack(spacing: 5) {
                        Image(systemName: "textformat.size").font(.system(size: 13, weight: .semibold))
                        Text("\(Int((annotation.fontFraction * 100).rounded()))").font(.footnote.weight(.semibold))
                    }
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showSize) {
                SizePopover(fraction: $annotation.fontFraction).presentationCompactAdaptation(.popover)
            }

            Button { showFont = true } label: {
                chip {
                    Text(textFontLabel(annotation.fontName)).font(.footnote.weight(.semibold)).lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showFont) {
                FontPopover(fontName: $annotation.fontName).presentationCompactAdaptation(.popover)
            }

            Spacer(minLength: 4)

            Button(action: onDone) {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor, in: Circle())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Color.black.opacity(0.34))
            }
        )
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(.white.opacity(0.10)))
        .shadow(color: .black.opacity(0.30), radius: 20, y: 8)
        .environment(\.colorScheme, .dark)
    }

    private func chip<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.12), in: Capsule())
            .foregroundStyle(.white)
    }
}

/// Ready-made palette grid + a custom picker for the text colour.
private struct ColorPalettePopover: View {
    @Binding var color: Color
    private let columns = Array(repeating: GridItem(.fixed(32), spacing: 10), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Palette").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(textColorPalette.enumerated()), id: \.offset) { _, swatch in
                    Button { color = swatch } label: {
                        Circle().fill(swatch).frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(.primary.opacity(0.2)))
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider()
            ColorPicker("Custom colour", selection: $color, supportsOpacity: false)
        }
        .padding(16)
        .frame(width: 280)
    }
}

/// Fine size control with a slider and quick presets.
private struct SizePopover: View {
    @Binding var fraction: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Text size").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Image(systemName: "textformat.size.smaller")
                Slider(value: $fraction, in: 0.01...0.4)
                Image(systemName: "textformat.size.larger")
                Text("\(Int((fraction * 100).rounded()))")
                    .font(.footnote.monospacedDigit().weight(.semibold))
                    .frame(width: 30, alignment: .trailing)
            }
            HStack(spacing: 8) {
                ForEach([0.03, 0.05, 0.08, 0.12, 0.2], id: \.self) { value in
                    Button("\(Int(value * 100))") { fraction = CGFloat(value) }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

/// Scrollable font list, each name shown in its own typeface.
private struct FontPopover: View {
    @Binding var fontName: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(textFontChoices, id: \.name) { choice in
                    Button { fontName = choice.psName } label: {
                        HStack {
                            Text(choice.name)
                                .font(choice.psName.map { .custom($0, size: 18) } ?? .system(size: 18))
                            Spacer()
                            if fontName == choice.psName {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                        .padding(.vertical, 9)
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(width: 270, height: 380)
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
                    if let current {
                        Menu {
                            copyButtons(for: current)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                    }
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
                    HStack {
                        Text("Saved").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Menu {
                            Button("Copy HEX list") { copyPalette(\.hex) }
                            Button("Copy RGB list") { copyPalette(\.rgb) }
                            Button("Copy CSS variables") { copyPalette(\.cssVariable) }
                            Button("Copy JSON") { copyPaletteJSON() }
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                                .font(.caption)
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(model.sampledColors) { swatch in
                                Menu {
                                    copyButtons(for: swatch)
                                    Divider()
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

    @ViewBuilder
    private func copyButtons(for c: SampledColor) -> some View {
        Button("Copy \(c.hex)") { UIPasteboard.general.string = c.hex }
        Button("Copy \(c.rgb)") { UIPasteboard.general.string = c.rgb }
        Button("Copy \(c.hsl)") { UIPasteboard.general.string = c.hsl }
        Button("Copy CSS variable") { UIPasteboard.general.string = c.cssVariable }
    }

    private func copyPalette(_ keyPath: KeyPath<SampledColor, String>) {
        UIPasteboard.general.string = model.sampledColors.map { $0[keyPath: keyPath] }.joined(separator: "\n")
    }

    private func copyPaletteJSON() {
        let items = model.sampledColors.map { "  \"\($0.hex)\"" }.joined(separator: ",\n")
        UIPasteboard.general.string = "[\n\(items)\n]"
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
    let annotationKind: Annotation.Kind
    let annotationColor: Color
    let annotationWidthFraction: CGFloat
    let textSizeFraction: CGFloat
    @Binding var currentSample: SampledColor?
    @Binding var sampleLocation: CGPoint?
    @Binding var isEditingText: Bool
    @Binding var selectedAnnotationID: UUID?
    @Binding var editingTextID: UUID?
    let onTextLocation: (CGPoint) -> Void

    @State private var dragStartCrop: CGRect?
    @State private var zoomScale: CGFloat = 1
    @State private var committedZoomScale: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var committedPanOffset: CGSize = .zero
    @State private var isPanning = false
    // Drag-to-move an existing annotation (e.g. reposition a text after placing).
    @State private var movingAnnotationIndex: Int?
    @State private var moveOriginalAnnotation: Annotation?
    @State private var didHitTestThisDrag = false
    @State private var dragMoved = false
    @FocusState private var textEditorFocused: Bool

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

                if activeTool == .draw || activeTool == .text || activeTool == .select {
                    annotationOverlay(in: imageRect)
                    selectionOverlay(in: imageRect)
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
            .simultaneousGesture(zoomGesture())
            .overlay(alignment: .topLeading) {
                inlineTextEditor(in: imageRect)
            }
            .overlay(alignment: .topTrailing) {
                zoomControls
                    .padding(.trailing, 12)
                    .padding(.top, canvasTopControlInset())
            }
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 0) {
            zoomButton("minus") { setZoom(zoomScale / 1.5) }
                .disabled(zoomScale <= 0.26)
            Menu {
                Button("Fit") { fitCanvas() }
                Button("25%") { setZoom(0.25) }
                Button("50%") { setZoom(0.5) }
                Button("100%") { setZoom(1) }
                Button("200%") { setZoom(2) }
                Button("400%") { setZoom(4) }
                Button("800%") { setZoom(8) }
            } label: {
                Text((zoomScale > 0.99 && zoomScale < 1.01) ? "Fit" : "\(Int((zoomScale * 100).rounded()))%")
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
        Canvas { context, _ in
            for annotation in annotations + [draftAnnotation].compactMap({ $0 }) {
                if annotation.isText {
                    if annotation.id == editingTextID { continue } // shown live in the text field
                    let resolved = context.resolve(
                        Text(annotation.text.isEmpty ? " " : annotation.text)
                            .font(annotation.swiftUIFont(in: imageRect))
                            .foregroundColor(annotation.color)
                    )
                    context.draw(resolved, at: annotation.textOrigin(in: imageRect), anchor: .topLeading)
                } else {
                    context.stroke(
                        Path(annotation.path(in: imageRect)),
                        with: .color(annotation.color),
                        style: StrokeStyle(
                            lineWidth: annotation.strokeWidth(in: imageRect),
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                }
            }
        }
        // The Canvas fills the whole container and draws at container-space
        // coordinates (the same space as hit-testing and the gesture), so text
        // and shapes render exactly where they can be selected. (A framed-and-
        // positioned Canvas double-offsets by the image margin.)
        .allowsHitTesting(false)
    }

    /// Dashed outline around the selected annotation (Select tool).
    @ViewBuilder
    private func selectionOverlay(in imageRect: CGRect) -> some View {
        if activeTool == .select, editingTextID == nil,
           let id = selectedAnnotationID,
           let annotation = annotations.first(where: { $0.id == id }) {
            let box = annotation.hitBounds(in: imageRect)
            if !box.isNull, !box.isInfinite {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .frame(width: box.width, height: box.height)
                    .position(x: box.midX, y: box.midY)
                    .allowsHitTesting(false)
            }
        }
    }

    /// On-canvas text field for the text annotation being edited (inline, no sheet).
    @ViewBuilder
    private func inlineTextEditor(in imageRect: CGRect) -> some View {
        if let id = editingTextID, let idx = annotations.firstIndex(where: { $0.id == id }) {
            let origin = annotations[idx].textOrigin(in: imageRect)
            TextField("Text", text: Binding(
                get: { annotations.indices.contains(idx) ? annotations[idx].text : "" },
                set: { if annotations.indices.contains(idx) { annotations[idx].text = $0 } }
            ), axis: .vertical)
            .font(annotations[idx].swiftUIFont(in: imageRect))
            .foregroundColor(annotations[idx].color)
            .textInputAutocapitalization(.sentences)
            .autocorrectionDisabled(false)
            .focused($textEditorFocused)
            .submitLabel(.done)
            .onSubmit { commitTextEditing() }
            .frame(maxWidth: max(80, imageRect.maxX - origin.x))
            .fixedSize(horizontal: false, vertical: true)
            .offset(x: origin.x, y: origin.y)
        }
    }

    /// Begin inline editing of a text annotation.
    private func beginTextEditing(_ id: UUID) {
        selectedAnnotationID = id
        editingTextID = id
        isEditingText = true
        DispatchQueue.main.async { textEditorFocused = true }
    }

    /// Finish inline editing; discard the annotation if left empty.
    private func commitTextEditing() {
        textEditorFocused = false
        if let id = editingTextID,
           let idx = annotations.firstIndex(where: { $0.id == id }),
           annotations[idx].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            annotations.remove(at: idx)
            selectedAnnotationID = nil
        }
        editingTextID = nil
        isEditingText = false
    }

    /// Topmost annotation whose hit area contains `point` (view space), if any.
    private func hitTestAnnotation(at point: CGPoint, in imageRect: CGRect) -> Int? {
        for idx in annotations.indices.reversed() where annotations[idx].hitBounds(in: imageRect).contains(point) {
            return idx
        }
        return nil
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
                // Track whether this gesture has actually dragged (vs a tap).
                if abs(value.translation.width) > 4 || abs(value.translation.height) > 4 {
                    dragMoved = true
                }
                // Select/Text tools: if the drag starts on an existing annotation,
                // move it (this is how a placed text/shape is repositioned).
                // Decided once, on the first change of the drag.
                if activeTool == .select || activeTool == .text {
                    if !didHitTestThisDrag {
                        didHitTestThisDrag = true
                        if draftAnnotation == nil,
                           let idx = hitTestAnnotation(at: value.startLocation, in: imageRect) {
                            movingAnnotationIndex = idx
                            moveOriginalAnnotation = annotations[idx]
                            selectedAnnotationID = annotations[idx].id
                        }
                    }
                    if let idx = movingAnnotationIndex, let original = moveOriginalAnnotation,
                       annotations.indices.contains(idx) {
                        let dx = (value.location.x - value.startLocation.x) / imageRect.width
                        let dy = (value.location.y - value.startLocation.y) / imageRect.height
                        annotations[idx] = original.translated(dx: dx, dy: dy)
                        return
                    }
                    // Select tool: dragging empty space pans the canvas freely.
                    if activeTool == .select {
                        panOffset = CGSize(
                            width: committedPanOffset.width + value.translation.width,
                            height: committedPanOffset.height + value.translation.height
                        )
                        return
                    }
                }
                switch activeTool {
                case .select:
                    break // handled above (select/move only, never draws)
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
                    break
                case .resize, .background:
                    break
                }
            }
            .onEnded { value in
                if isPanning {
                    committedPanOffset = panOffset
                    return
                }
                // Finish a move (select/text tools): if we were repositioning an
                // annotation, commit it and don't also draw or add new text.
                let wasMoving = movingAnnotationIndex != nil
                let tapped = !dragMoved
                defer {
                    didHitTestThisDrag = false
                    movingAnnotationIndex = nil
                    moveOriginalAnnotation = nil
                    dragMoved = false
                }
                if wasMoving { return }

                // Any tap while inline-editing a text commits that edit first.
                if editingTextID != nil, tapped {
                    commitTextEditing()
                    return
                }

                switch activeTool {
                case .select:
                    guard tapped else {
                        committedPanOffset = panOffset // finish a free pan
                        break
                    }
                    if let idx = hitTestAnnotation(at: value.location, in: imageRect) {
                        let hitID = annotations[idx].id
                        // Tapping an already-selected text a second time edits it inline.
                        if selectedAnnotationID == hitID, annotations[idx].isText {
                            beginTextEditing(hitID)
                        } else {
                            selectedAnnotationID = hitID
                        }
                    } else {
                        selectedAnnotationID = nil
                    }
                case .crop:
                    dragStartCrop = nil
                case .draw:
                    if let draftAnnotation { annotations.append(draftAnnotation) }
                    draftAnnotation = nil
                case .text:
                    guard tapped else { break }
                    // Tap an existing text to edit it; otherwise create a new one
                    // and start typing inline (no sheet).
                    if let idx = hitTestAnnotation(at: value.location, in: imageRect),
                       annotations[idx].isText {
                        beginTextEditing(annotations[idx].id)
                    } else {
                        var new = Annotation(kind: .text, color: annotationColor, widthFraction: annotationWidthFraction)
                        new.start = normalized(value.location, in: imageRect)
                        new.text = ""
                        new.fontFraction = textSizeFraction
                        annotations.append(new)
                        beginTextEditing(new.id)
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
        min(max(value, 0.25), 8)
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
