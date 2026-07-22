import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ImageKidKit

@MainActor
private enum ActiveAppModel {
    static weak var current: AppModel?
    static var pendingOpenURLs: [URL] = []
    static var didQueueCommandLineFileURLs = false

    static func register(_ appModel: AppModel) {
        current = appModel
        queueCommandLineFileURLs()

        guard !pendingOpenURLs.isEmpty else { return }
        let urls = pendingOpenURLs
        pendingOpenURLs.removeAll()
        appModel.load(urls)
    }

    static func open(_ urls: [URL]) {
        guard !urls.isEmpty else { return }

        if let current {
            current.load(urls)
        } else {
            pendingOpenURLs.append(contentsOf: urls)
        }
    }

    private static func queueCommandLineFileURLs() {
        guard !didQueueCommandLineFileURLs else { return }
        didQueueCommandLineFileURLs = true

        // Only treat arguments that point at a real file as documents to open.
        // macOS/Xcode inject option pairs such as `-NSDocumentRevisionsDebugMode YES`,
        // and the bare value ("YES") must not be mistaken for a file path.
        let urls = CommandLine.arguments.dropFirst().compactMap { argument -> URL? in
            guard !argument.hasPrefix("-") else { return nil }
            let candidate = URL(fileURLWithPath: argument).standardizedFileURL
            guard FileManager.default.fileExists(atPath: candidate.path) else { return nil }
            return candidate
        }

        guard !urls.isEmpty else { return }
        pendingOpenURLs.append(contentsOf: urls)
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var items: [WorkspaceItem] = []
    @Published var selectedItemID: UUID?
    @Published var selectedItemIDs: Set<UUID> = []
    @Published var activeTool: Tool = .view
    let panelDock = PanelDockModel<DockablePanel>.makeDefault()
    @Published var errorMessage: String?
    @Published var isShowingResize = false
    @Published var isShowingExport = false
    @Published var isShowingPromptEdit = false
    @Published var isShowingEnhance = false
    @Published var isRemovingBackground = false
    @Published var isApplyingResize = false
    @Published var isApplyingEnhance = false
    @Published var isApplyingPromptEdit = false
    @Published var operationProgress: OperationProgress?
    @Published var isWorkspaceSidebarCollapsed: Bool {
        didSet {
            UserDefaults.standard.set(isWorkspaceSidebarCollapsed, forKey: "workspaceSidebarCollapsed")
        }
    }
    var dirtyCloseConfirmation: (String) -> Bool = { title in
        let alert = NSAlert()
        alert.messageText = "Close \(title)?"
        alert.informativeText = "This image has unsaved changes. Save or export it before closing, or discard the changes."
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
    private var didApplyScreenshotScenario = false

    init() {
        isWorkspaceSidebarCollapsed = UserDefaults.standard.bool(forKey: "workspaceSidebarCollapsed")
    }

    var media: MediaItem? {
        selectedItem?.media
    }

    var imageSession: ImageSession? {
        if case .image(let session) = media { return session }
        return nil
    }

    var selectedItem: WorkspaceItem? {
        guard let selectedItemID else { return nil }
        return items.first(where: { $0.id == selectedItemID })
    }

    var exportTargetItems: [WorkspaceItem] {
        let selectedItems = items.filter { selectedItemIDs.contains($0.id) }
        if !selectedItems.isEmpty { return selectedItems }
        return selectedItem.map { [$0] } ?? []
    }

    var selectedItemIndex: Int? {
        guard let selectedItemID else { return nil }
        return items.firstIndex(where: { $0.id == selectedItemID })
    }

    var canRemoveBackground: Bool {
        if case .image = media { return !isRemovingBackground }
        return false
    }

    var promptEditProviderName: String {
        "OpenAI"
    }

    var hasPromptEditCredential: Bool {
        guard let apiKey = KeychainStore.string(for: "openai-api-key") else { return false }
        return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var promptEditSendsSelectionOnly: Bool {
        if case .image(let session) = media {
            return session.hasImageSelection
        }
        return false
    }

    var hasRemovedBackground: Bool {
        if case .image(let session) = media {
            return session.backgroundRemovedImage != nil
        }
        return false
    }

    var canDeleteSelection: Bool {
        if case .image(let session) = media {
            return session.selectedLayerID != nil || session.selectedAnnotationID != nil || session.hasImageSelection
        }
        return false
    }

    var canCopyImageSelection: Bool {
        if case .image(let session) = media {
            return session.hasImageSelection
        }
        return false
    }

    var canToggleFilesSheet: Bool {
        !items.isEmpty
    }

    var canCloseSelectedItem: Bool {
        selectedItemID != nil
    }

    func toggleFilesSheet() {
        guard canToggleFilesSheet else { return }
        isWorkspaceSidebarCollapsed.toggle()
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK else { return }
        load(panel.urls)
    }

    func load(_ url: URL) {
        load([url])
    }

    func load(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        var firstLoadedID: UUID?

        for url in urls {
            do {
                let media = try MediaLoader.load(url: url)
                let item = WorkspaceItem(media: media)
                items.append(item)
                if firstLoadedID == nil { firstLoadedID = item.id }
                NSDocumentController.shared.noteNewRecentDocumentURL(url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        if let firstLoadedID {
            selectedItemID = firstLoadedID
            selectedItemIDs = [firstLoadedID]
            activeTool = .view
        }
    }

    func configureScreenshotScenarioIfNeeded(settings: AppSettings) {
        guard !didApplyScreenshotScenario else { return }
        guard ProcessInfo.processInfo.environment["IMAGEKID_SCREENSHOT"] == "1" else { return }
        didApplyScreenshotScenario = true

        switch ProcessInfo.processInfo.environment["IMAGEKID_SCREENSHOT_COLOR_MODE"] {
        case "light":
            settings.appearanceMode = .light
            settings.canvasBackground = .light
        case "dark":
            settings.appearanceMode = .dark
            settings.canvasBackground = .dark
        default:
            settings.appearanceMode = .light
            settings.canvasBackground = .checkerboard
        }

        let scenario = ProcessInfo.processInfo.environment["IMAGEKID_SCREENSHOT_SCENARIO"] ?? "empty"
        guard scenario != "empty" else { return }
        guard let session = screenshotImageSession() else { return }

        let item = WorkspaceItem(media: .image(session))
        items = [item]
        selectedItemID = item.id
        selectedItemIDs = [item.id]
        isWorkspaceSidebarCollapsed = true
        activeTool = .view

        switch scenario {
        case "workspace":
            session.viewportMode = .contain

        case "color":
            session.sampledColors = [
                SampledColor(color: NSColor(red: 0.24, green: 0.63, blue: 0.82, alpha: 1)),
                SampledColor(color: NSColor(red: 0.95, green: 0.41, blue: 0.22, alpha: 1)),
                SampledColor(color: NSColor(red: 0.05, green: 0.18, blue: 0.29, alpha: 1))
            ]
            session.selectedColorIDs = Set(session.sampledColors.prefix(1).map(\.id))
            session.liveSampleColor = session.sampledColors.first?.color
            session.liveSampleLocation = CGPoint(x: 0.48, y: 0.42)
            activeTool = .pickColor

        case "crop":
            session.draftCropRect = CGRect(x: 0.12, y: 0.10, width: 0.72, height: 0.70)
            session.cropAspectRatio = .sixteenNine
            activeTool = .crop

        case "resize":
            session.beginResize()
            session.setDraftOutputSize(CGSize(width: 1600, height: 960))
            activeTool = .resize

        case "annotate":
            let arrow = Annotation(
                kind: .arrow(start: CGPoint(x: 0.12, y: 0.80), end: CGPoint(x: 0.88, y: 0.20)),
                frame: CGRect(x: 0.18, y: 0.15, width: 0.58, height: 0.55),
                strokeColor: .systemOrange,
                lineWidth: 7
            )
            let label = Annotation(
                kind: .text("Ready for review"),
                frame: CGRect(x: 0.10, y: 0.08, width: 0.42, height: 0.14),
                strokeColor: .white,
                fontSize: 46,
                fontWeight: .bold
            )
            session.annotations = [arrow, label]
            session.selectedAnnotationID = arrow.id
            activeTool = .draw

        case "background":
            session.backgroundRemovedImage = session.sourceImage
            session.backgroundBrushSize = 72
            session.backgroundBrushSoftness = 0.35
            session.backgroundBrushStrength = 0.85
            activeTool = .view

        case "magic":
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                isShowingPromptEdit = true
            }

        case "export":
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                isShowingExport = true
            }

        default:
            break
        }
    }

    private func screenshotImageSession() -> ImageSession? {
        let shouldUseDemoImage = ProcessInfo.processInfo.environment["IMAGEKID_SCREENSHOT_MEDIA"] == "demo"
            || ProcessInfo.processInfo.environment["IMAGEKID_SCREENSHOT"] == "1"
        let preferredImage = shouldUseDemoImage ? ImageKidAsset.image(named: "ImageKidDemoImage") : nil
        let image = preferredImage
            ?? ImageKidAsset.image(named: "ImageKidEmptyState")
            ?? ImageKidAsset.image(named: "ImageKidCharacter")
            ?? ImageKidAsset.image(named: "ImageKidAppIcon")
        guard let image else { return nil }
        return ImageSession(sourceURL: nil, sourceImage: image)
    }

    func selectItem(_ id: UUID) {
        selectedItemID = id
        selectedItemIDs = [id]
        activeTool = .view
    }

    func toggleItemSelection(_ id: UUID) {
        if selectedItemIDs.contains(id) {
            selectedItemIDs.remove(id)
            if selectedItemID == id {
                selectedItemID = selectedItemIDs.first ?? items.first?.id
            }
        } else {
            selectedItemIDs.insert(id)
            selectedItemID = id
        }
        activeTool = .view
    }

    func closeItem(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items[index]
        if item.isDirty, !dirtyCloseConfirmation(item.title) {
            return
        }
        let wasSelected = selectedItemID == id
        items.remove(at: index)
        selectedItemIDs.remove(id)

        if wasSelected {
            selectedItemID = items.indices.contains(index)
                ? items[index].id
                : items.last?.id
            activeTool = .view
        }
        if selectedItemIDs.isEmpty, let selectedItemID {
            selectedItemIDs = [selectedItemID]
        }
    }

    func closeSelectedItem() {
        guard let selectedItemID else { return }
        closeItem(selectedItemID)
    }

    func replaceSelectedMedia(_ media: MediaItem) {
        guard let selectedItemID else { return }
        replaceMedia(media, for: selectedItemID)
    }

    @discardableResult
    func replaceMedia(_ media: MediaItem, for itemID: UUID) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            return false
        }
        items[index].media = media
        return true
    }

    func loadReplacingSelected(_ url: URL) {
        do {
            let media = try MediaLoader.load(url: url)
            replaceSelectedMedia(media)
            activeTool = .view
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func paste() {
        if let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self]) as? [URL], let url = urls.first {
            load(url)
            return
        }

        if let image = NSImage(pasteboard: .general) {
            let item = WorkspaceItem(media: .image(ImageSession(sourceURL: nil, sourceImage: image)))
            items.append(item)
            selectedItemID = item.id
            selectedItemIDs = [item.id]
            activeTool = .view
            return
        }

        errorMessage = "The clipboard does not contain a supported image or video file."
    }

    func resetView() {
        switch media {
        case .image(let session): session.resetView()
        case .video(let session):
            session.zoom = 1
            session.pan = .zero
        case nil: break
        }
    }

    func zoomIn() {
        switch media {
        case .image(let session):
            session.zoom = min(12, session.zoom * 1.2)
        case .video(let session):
            session.zoom = min(12, session.zoom * 1.2)
        case nil:
            break
        }
    }

    func zoomOut() {
        switch media {
        case .image(let session):
            session.zoom = max(0.1, session.zoom / 1.2)
        case .video(let session):
            session.zoom = max(0.1, session.zoom / 1.2)
        case nil:
            break
        }
    }

    func cancelCurrentTool() {
        if case .image(let session) = media {
            if session.selectionRect != nil {
                session.selectionRect = nil
                activeTool = .view
                return
            }
            if activeTool == .crop {
                session.cancelCrop()
            }
            if activeTool == .resize {
                session.cancelDraftResize()
            }
            if activeTool == .rotate {
                session.beginRotation()
            }
            session.liveSampleColor = nil
            session.liveSampleLocation = nil
        }
        activeTool = .view
    }

    func deleteSelection() {
        guard case .image(let session) = media else {
            return
        }

        if session.isEditingMask { return }

        if let layerID = session.selectedLayerID {
            session.removeImageLayer(id: layerID)
            return
        }

        if let selectedAnnotationID = session.selectedAnnotationID {
            session.removeAnnotation(id: selectedAnnotationID)
            return
        }

        session.selectionRect = nil
    }

    var hasSelectedAnnotation: Bool {
        imageSession?.selectedAnnotationID != nil
    }

    /// Add another open file's image into `session` as a new placed layer.
    @discardableResult
    func addDraggedImageAsLayer(_ idString: String, into session: ImageSession) -> Bool {
        guard let item = items.first(where: { $0.id.uuidString == idString }),
              case .image(let source) = item.media else { return false }
        session.addImageLayer(source.workingSourceImage, name: item.title)
        return true
    }

    func duplicateSelectedAnnotation() {
        guard let session = imageSession, let id = session.selectedAnnotationID else { return }
        session.duplicateAnnotation(id: id)
    }

    func moveSelectedAnnotation(toFront: Bool) {
        guard let session = imageSession, let id = session.selectedAnnotationID else { return }
        session.moveAnnotation(id: id, toFront: toFront)
    }

    func moveSelectedAnnotation(forward: Bool) {
        guard let session = imageSession, let id = session.selectedAnnotationID else { return }
        session.moveAnnotation(id: id, forward: forward)
    }

    func selectAllImage() {
        guard case .image(let session) = media else { return }
        session.selectFullImage()
        activeTool = .select
    }

    func copyImageSelectionToClipboard() {
        guard case .image(let session) = media,
              let selectionRect = session.selectionRect,
              let image = ImageRenderer.render(session) else {
            return
        }

        guard let cropped = ImageSelectionRenderer.crop(image, normalizedRect: selectionRect) else {
            errorMessage = "ImageKid could not copy that selection."
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([cropped])
    }

    func cropSelection() {
        guard case .image(let session) = media,
              let selectionRect = session.selectionRect,
              session.hasImageSelection else {
            return
        }

        session.draftCropRect = WorkingImageGeometry.sourceRect(
            fromDisplayNormalized: selectionRect,
            cropRect: session.cropRect
        )
        activeTool = .crop
    }

    func copyCurrentImageToClipboard() {
        guard case .image(let session) = media,
              let image = ImageRenderer.render(session) else {
            errorMessage = "Open an image first."
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    func applyResizeToCurrentImage(
        targetSize: CGSize,
        upscaleEngine: UpscaleEngine,
        upscaleContentMode: UpscaleContentMode
    ) {
        guard !isApplyingResize else { return }
        guard let itemID = selectedItemID else {
            errorMessage = "Open an image first."
            return
        }
        guard case .image(let session) = media else {
            errorMessage = "Open an image first."
            return
        }

        let normalizedTargetSize = CGSize(
            width: max(1, targetSize.width.rounded()),
            height: max(1, targetSize.height.rounded())
        )
        let effectiveContentMode = ImageUpscaleService.resolvedContentMode(
            for: session.workingSourceImage,
            requestedMode: upscaleContentMode
        )
        let isUpscaling = normalizedTargetSize.width > session.croppedPixelSize.width
            || normalizedTargetSize.height > session.croppedPixelSize.height

        if upscaleEngine == .bestQuality,
           isUpscaling,
           effectiveContentMode != .textAndUI,
           !ImageUpscaleService.isBestQualityRuntimeAvailable {
            errorMessage = "Best Quality is not ready yet. Turn it on in Settings > Upscale."
            return
        }

        let shouldRenderNow = upscaleEngine == .bestQuality
            && isUpscaling
            && (effectiveContentMode == .textAndUI || ImageUpscaleService.isBestQualityRuntimeAvailable)

        if !shouldRenderNow {
            session.setDraftOutputSize(normalizedTargetSize)
            session.applyDraftResize()
            activeTool = .view
            return
        }

        let sourceURL = session.sourceURL
        session.cancelDraftResize()
        activeTool = .view

        do {
            let baseImage = try ImageRenderer.renderUpscaleBase(
                for: session,
                targetSize: normalizedTargetSize,
                upscaleEngine: upscaleEngine,
                upscaleContentMode: upscaleContentMode
            )
            let hasAnnotations = !session.annotations.isEmpty
            isApplyingResize = true
            operationProgress = OperationProgress(
                title: "Stretching it up",
                detail: "Getting ready for \(Int(normalizedTargetSize.width)) × \(Int(normalizedTargetSize.height)) px",
                startedAt: Date(),
                fraction: nil
            )

            Task {
                do {
                    let progressHandler: @Sendable (UpscaleProgressUpdate) -> Void = { [weak self] update in
                        Task { @MainActor in
                            self?.operationProgress?.detail = update.detail
                            self?.operationProgress?.fraction = update.fraction
                        }
                    }
                    var image = try await Task.detached(priority: .utility) {
                        try ImageUpscaleService.upscale(
                            baseImage,
                            to: normalizedTargetSize,
                            contentMode: upscaleContentMode,
                            progress: progressHandler
                        )
                    }.value

                    operationProgress?.detail = "Putting the picture back together"
                    image = ImageUpscaleService.imageWithExactPixelSize(image, size: normalizedTargetSize)
                    if hasAnnotations {
                        image = ImageRenderer.drawAnnotationsOnImage(
                            image,
                            session: session,
                            targetSize: normalizedTargetSize
                        )
                    }

                    let resizedSession = ImageSession(sourceURL: sourceURL, sourceImage: image)
                    resizedSession.isDirty = true
                    if !replaceMedia(.image(resizedSession), for: itemID) {
                        errorMessage = "That image was closed before the resize finished."
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }

                isApplyingResize = false
                operationProgress = nil
            }
        } catch {
            errorMessage = error.localizedDescription
            operationProgress = nil
        }
    }

    /// Quick 90° rotation from the Image menu (no empty corners, so no fill needed).
    func rotate90(clockwise: Bool) {
        bakeRotation(degrees: clockwise ? 90 : -90, flipHorizontal: false, flipVertical: false, resizeCanvas: true, fill: nil)
    }

    /// Flip from the Image menu. `horizontal == true` mirrors left↔right, otherwise top↔bottom.
    func flipImage(horizontal: Bool) {
        bakeRotation(degrees: 0, flipHorizontal: horizontal, flipVertical: !horizontal, resizeCanvas: true, fill: nil)
    }

    /// Apply the rotate tool's draft (arbitrary angle + flips) using its canvas/fill options.
    func applyRotationToCurrentImage() {
        guard case .image(let session) = media else {
            errorMessage = "Open an image first."
            return
        }
        let fill: NSColor? = session.rotationFillsGaps ? session.rotationFillColor : nil
        bakeRotation(
            degrees: session.rotationDraft,
            flipHorizontal: session.rotationFlipHorizontal,
            flipVertical: session.rotationFlipVertical,
            resizeCanvas: session.rotationResizesCanvas,
            fill: fill
        )
        activeTool = .view
    }

    private func bakeRotation(degrees: Double, flipHorizontal: Bool, flipVertical: Bool, resizeCanvas: Bool, fill: NSColor?) {
        guard let itemID = selectedItemID, case .image(let session) = media else {
            errorMessage = "Open an image first."
            return
        }
        guard degrees != 0 || flipHorizontal || flipVertical else { return }

        guard let rendered = ImageRenderer.render(session) else {
            errorMessage = "Couldn't render the image to rotate."
            return
        }
        // render() bakes at the screen backing scale; normalize to the true pixel
        // size so rotating doesn't silently inflate the image (e.g. 2× on Retina).
        let flattened = ImageUpscaleService.imageWithExactPixelSize(rendered, size: session.effectivePixelSize)
        guard let rotated = ImageRotator.rotate(
            flattened,
            degrees: degrees,
            flipHorizontal: flipHorizontal,
            flipVertical: flipVertical,
            resizeCanvas: resizeCanvas,
            fillColor: fill
        ) else {
            errorMessage = "Rotation failed."
            return
        }

        let rotatedSession = ImageSession(sourceURL: session.sourceURL, sourceImage: rotated)
        rotatedSession.isDirty = true
        if !replaceMedia(.image(rotatedSession), for: itemID) {
            errorMessage = "That image was closed before the rotation finished."
        }
    }

    func requestExport() {
        guard case .image = media else {
            errorMessage = "Video export is not implemented in the current foundation build."
            return
        }
        isShowingExport = true
    }

    func requestPromptEdit() {
        guard case .image = media else {
            errorMessage = "Open an image first."
            return
        }
        isShowingPromptEdit = true
    }

    func applyPromptEdit(prompt: String) {
        guard !isApplyingPromptEdit else { return }
        guard let itemID = selectedItemID else {
            errorMessage = "Open an image first."
            return
        }
        guard case .image(let session) = media else {
            errorMessage = "Open an image first."
            return
        }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            errorMessage = "Describe the edit you want ImageKid to make."
            return
        }

        guard let apiKey = KeychainStore.string(for: "openai-api-key"),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = PromptImageEditError.missingCredential("OpenAI").localizedDescription
            return
        }

        let payload: PromptImageEditPayload
        do {
            payload = try PromptImageEditPayloadBuilder.payload(for: session)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        let selectionRect: CGRect?
        if case .selection(let rect) = payload.scope {
            selectionRect = rect
        } else {
            selectionRect = nil
        }

        let sourceURL = session.sourceURL
        isShowingPromptEdit = false
        isApplyingPromptEdit = true
        operationProgress = OperationProgress(
            title: "Prompted edit",
            detail: selectionRect == nil ? "Uploading the image" : "Uploading the selected bit",
            startedAt: Date(),
            fraction: nil
        )

        Task {
            do {
                let provider = OpenAIPromptImageEditProvider(apiKey: apiKey)
                let editedImage = try await PromptImageEditService.edit(
                    image: payload.image,
                    prompt: trimmedPrompt,
                    provider: provider
                )
                let finalImage: NSImage
                if let selectionRect {
                    finalImage = Self.composite(
                        editedImage,
                        into: payload.sourceImage,
                        normalizedRect: selectionRect
                    ) ?? editedImage
                } else {
                    finalImage = editedImage
                }
                let editedSession = ImageSession(sourceURL: sourceURL, sourceImage: finalImage)
                editedSession.isDirty = true
                if !replaceMedia(.image(editedSession), for: itemID) {
                    errorMessage = "That image was closed before Magic finished."
                }
                activeTool = .view
            } catch {
                errorMessage = error.localizedDescription
            }

            isApplyingPromptEdit = false
            operationProgress = nil
        }
    }

    func requestEnhance() {
        guard case .image = media else {
            errorMessage = "Open an image first."
            return
        }
        isShowingEnhance = true
    }

    /// Direct Smart Upscale from the Resize panel — uses the saved quality grade.
    func smartUpscale(_ size: EnhanceSize) {
        let quality = EnhanceQuality(rawValue: UserDefaults.standard.string(forKey: "enhanceQuality") ?? "") ?? .high
        applyEnhance(quality: quality, size: size)
    }

    /// Magic ▸ Enhance Image. Improves detail (and optionally enlarges) with the
    /// chosen quality grade, running the engine off the main thread.
    func applyEnhance(quality: EnhanceQuality, size: EnhanceSize) {
        guard !isApplyingEnhance else { return }
        guard let itemID = selectedItemID else {
            errorMessage = "Open an image first."
            return
        }
        guard case .image(let session) = media else {
            errorMessage = "Open an image first."
            return
        }
        if let model = quality.requiredModel, !model.isDownloaded {
            errorMessage = "Download the \(quality.label) quality add-on in Settings first."
            return
        }

        let targetSize = CGSize(
            width: max(1, (session.croppedPixelSize.width * size.factor).rounded()),
            height: max(1, (session.croppedPixelSize.height * size.factor).rounded())
        )
        let sourceURL = session.sourceURL
        let hasAnnotations = !session.annotations.isEmpty

        let baseImage: NSImage
        do {
            baseImage = try ImageRenderer.renderEnhanceBase(for: session)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        isShowingEnhance = false
        activeTool = .view
        isApplyingEnhance = true
        operationProgress = OperationProgress(
            title: "Enhancing",
            detail: "Improving detail",
            startedAt: Date(),
            fraction: nil
        )

        Task {
            do {
                let progressHandler: @Sendable (UpscaleProgressUpdate) -> Void = { [weak self] update in
                    Task { @MainActor in
                        self?.operationProgress?.detail = update.detail
                        self?.operationProgress?.fraction = update.fraction
                    }
                }
                var image = try await Task.detached(priority: .utility) {
                    try ImageUpscaleService.enhance(
                        baseImage,
                        to: targetSize,
                        quality: quality,
                        progress: progressHandler
                    )
                }.value

                image = ImageUpscaleService.imageWithExactPixelSize(image, size: targetSize)
                if hasAnnotations {
                    image = ImageRenderer.drawAnnotationsOnImage(image, session: session, targetSize: targetSize)
                }

                let enhancedSession = ImageSession(sourceURL: sourceURL, sourceImage: image)
                enhancedSession.isDirty = true
                if !replaceMedia(.image(enhancedSession), for: itemID) {
                    errorMessage = "That image was closed before Enhance finished."
                }
            } catch {
                errorMessage = error.localizedDescription
            }

            isApplyingEnhance = false
            operationProgress = nil
        }
    }

    private static func composite(_ editedImage: NSImage, into baseImage: NSImage, normalizedRect: CGRect) -> NSImage? {
        guard let baseCGImage = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let baseSize = CGSize(width: baseCGImage.width, height: baseCGImage.height)
        let rect = GeometryMapper.clampedNormalizedRect(normalizedRect)
        let targetRect = CGRect(
            x: rect.minX * baseSize.width,
            y: rect.minY * baseSize.height,
            width: rect.width * baseSize.width,
            height: rect.height * baseSize.height
        ).integral

        let result = NSImage(size: baseSize)
        result.lockFocus()
        defer { result.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .high
        baseImage.draw(
            in: CGRect(origin: .zero, size: baseSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        editedImage.draw(
            in: targetRect,
            from: CGRect(origin: .zero, size: editedImage.size),
            operation: .sourceOver,
            fraction: 1
        )

        return result
    }

    func exportImage(options: ImageExportOptions) {
        let targets = exportTargetItems.compactMap { item -> (WorkspaceItem, ImageSession)? in
            guard case .image(let session) = item.media else { return nil }
            return (item, session)
        }

        guard !targets.isEmpty else {
            errorMessage = "Video export is not implemented in the current foundation build."
            return
        }

        if targets.count > 1 {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "Export"
            panel.message = "Choose where ImageKid should place the exported images."

            guard panel.runModal() == .OK, let directory = panel.url else { return }

            do {
                for (_, session) in targets {
                    let url = uniqueExportURL(
                        in: directory,
                        preferredName: suggestedExportName(for: session, format: options.format)
                    )
                    try ImageRenderer.write(session, to: url, options: options)
                    session.isDirty = false
                }
                if options.revealAfterExport {
                    NSWorkspace.shared.activateFileViewerSelecting([directory])
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        let session = targets[0].1
        let panel = NSSavePanel()
        panel.allowedContentTypes = [options.format.contentType]
        panel.nameFieldStringValue = suggestedExportName(for: session, format: options.format)

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try ImageRenderer.write(session, to: url, options: options)
            session.isDirty = false
            if options.revealAfterExport {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveImage() {
        guard let itemID = selectedItemID else {
            errorMessage = "Open an image first."
            return
        }
        guard case .image(let session) = media else {
            errorMessage = "Open an image first."
            return
        }

        guard let sourceURL = session.sourceURL else {
            requestExport()
            return
        }

        guard let format = ImageExportFormat(url: sourceURL) else {
            errorMessage = "ImageKid cannot save over this file type yet. Use Export instead."
            return
        }

        guard session.isDirty else {
            activeTool = .view
            return
        }

        let options = ImageExportOptions(format: format)
        if !format.supportsAlpha, session.containsTransparency {
            let alert = NSAlert()
            alert.messageText = "\(format.label) cannot preserve transparency"
            alert.informativeText = "Saving will flatten transparent pixels onto a white background. Use Export to choose PNG or TIFF if you need transparency."
            alert.addButton(withTitle: "Save Anyway")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        do {
            try ImageRenderer.write(session, to: sourceURL, options: options)
            let savedImage = try reloadedImage(from: sourceURL)
            _ = replaceMedia(.image(ImageSession(sourceURL: sourceURL, sourceImage: savedImage)), for: itemID)
            activeTool = .view
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveAllImages() {
        let dirtyImageSessions = items.compactMap { item -> ImageSession? in
            guard case .image(let session) = item.media, session.isDirty else { return nil }
            return session
        }
        guard !dirtyImageSessions.isEmpty else {
            activeTool = .view
            return
        }
        saveDirtyImages(dirtyImageSessions)
    }

    private func saveDirtyImages(_ sessions: [ImageSession]) {
        guard sessions.allSatisfy({ $0.sourceURL != nil }) else {
            errorMessage = "Some images are new. Use Export so ImageKid knows where to put them."
            return
        }

        let formats = sessions.compactMap { session -> ImageExportFormat? in
            guard let sourceURL = session.sourceURL else { return nil }
            return ImageExportFormat(url: sourceURL)
        }
        guard formats.count == sessions.count else {
            errorMessage = "One of these file types needs Export instead of Save."
            return
        }

        if sessions.enumerated().contains(where: { index, session in
            !formats[index].supportsAlpha && session.containsTransparency
        }) {
            let alert = NSAlert()
            alert.messageText = "Some files cannot preserve transparency"
            alert.informativeText = "Saving will flatten transparent pixels onto a white background for formats like JPEG. Use Export if you need to choose PNG or TIFF."
            alert.addButton(withTitle: "Save Anyway")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        do {
            for (index, session) in sessions.enumerated() {
                guard let sourceURL = session.sourceURL else { continue }
                try ImageRenderer.write(
                    session,
                    to: sourceURL,
                    options: ImageExportOptions(format: formats[index])
                )
                session.isDirty = false
            }
            activeTool = .view
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reloadedImage(from url: URL) throws -> NSImage {
        let data = try Data(contentsOf: url)
        guard let image = NSImage(data: data) else {
            throw MediaLoaderError.unsupportedFile
        }
        return image
    }

    func removeBackground() {
        guard let itemID = selectedItemID else {
            errorMessage = "Background removal is available for images only."
            return
        }
        guard case .image(let session) = media else {
            errorMessage = "Background removal is available for images only."
            return
        }

        // If an image layer is selected, mask *that* layer instead of the base.
        if session.selectedLayerID != nil {
            removeBackgroundFromSelectedLayer()
            return
        }

        if session.backgroundRemovedImage != nil {
            session.restoreBackground()
            if activeTool == .refineBackground {
                activeTool = .view
            }
            return
        }

        guard let source = session.sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            errorMessage = "ImageKid could not prepare this image for background removal."
            return
        }

        isRemovingBackground = true
        operationProgress = OperationProgress(
            title: "Peeling off the background",
            detail: "Finding the edges",
            startedAt: Date(),
            fraction: nil
        )

        Task {
            do {
                let output = try await Task.detached(priority: .userInitiated) {
                    let engine = BackgroundRemovalEngine(
                        rawValue: UserDefaults.standard.string(forKey: "backgroundRemovalEngine")
                            ?? BackgroundRemovalEngine.builtIn.rawValue
                    ) ?? .builtIn
                    return try await BackgroundRemovalService.removeBackground(from: source, engine: engine)
                }.value

                session.backgroundRemovedImage = NSImage(
                    cgImage: output,
                    size: CGSize(width: output.width, height: output.height)
                )
                session.recordBackgroundRemoval()
                if selectedItemID == itemID {
                    activeTool = .view
                }
            } catch {
                errorMessage = error.localizedDescription
            }

            isRemovingBackground = false
            operationProgress = nil
        }
    }

    var canRemoveBackgroundFromLayer: Bool {
        guard case .image(let session) = media else { return false }
        return session.selectedLayerID != nil && !isRemovingBackground
    }

    /// Remove the background of the selected image layer non-destructively,
    /// storing the result as an editable, toggleable mask on that layer.
    func removeBackgroundFromSelectedLayer() {
        guard case .image(let session) = media,
              let layerID = session.selectedLayerID,
              let layer = session.imageLayers.first(where: { $0.id == layerID }),
              let source = layer.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        isRemovingBackground = true
        operationProgress = OperationProgress(
            title: "Masking the layer",
            detail: "Finding the edges",
            startedAt: Date(),
            fraction: nil
        )

        Task {
            do {
                let output = try await Task.detached(priority: .userInitiated) {
                    let engine = BackgroundRemovalEngine(
                        rawValue: UserDefaults.standard.string(forKey: "backgroundRemovalEngine")
                            ?? BackgroundRemovalEngine.builtIn.rawValue
                    ) ?? .builtIn
                    return try await BackgroundRemovalService.removeBackground(from: source, engine: engine)
                }.value

                if let mask = MaskCompositor.alphaMask(from: output) {
                    session.setLayerMask(id: layerID, mask: mask)
                } else {
                    errorMessage = "ImageKid could not build a mask for this layer."
                }
            } catch {
                errorMessage = error.localizedDescription
            }

            isRemovingBackground = false
            operationProgress = nil
        }
    }

    private func suggestedExportName(for session: ImageSession, format: ImageExportFormat) -> String {
        let sourceName = session.sourceURL?.deletingPathExtension().lastPathComponent ?? "ImageKid Export"
        return sourceName + "-edited." + format.fileExtension
    }

    private func uniqueExportURL(in directory: URL, preferredName: String) -> URL {
        let baseURL = directory.appendingPathComponent(preferredName)
        guard FileManager.default.fileExists(atPath: baseURL.path) else { return baseURL }

        let baseName = baseURL.deletingPathExtension().lastPathComponent
        let fileExtension = baseURL.pathExtension
        var index = 2
        while true {
            let candidate = directory
                .appendingPathComponent("\(baseName)-\(index)")
                .appendingPathExtension(fileExtension)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }
}

struct AppCommands: Commands {
    @FocusedObject private var appModel: AppModel?

    private var currentAppModel: AppModel? {
        appModel ?? ActiveAppModel.current
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open…") { currentAppModel?.openPanel() }
                .keyboardShortcut("o")
                .disabled(currentAppModel == nil)

            Button("Close Image") { currentAppModel?.closeSelectedItem() }
                .keyboardShortcut("w")
                .disabled(currentAppModel?.canCloseSelectedItem != true)
        }

        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { currentAppModel?.imageSession?.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(currentAppModel?.imageSession?.canUndo != true)

            Button("Redo") { currentAppModel?.imageSession?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(currentAppModel?.imageSession?.canRedo != true)
        }

        CommandGroup(replacing: .pasteboard) {
            Button("Cut") {
                _ = NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("x")
            .disabled(currentAppModel == nil)

            Button("Copy") {
                let handledByResponder = NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                if !handledByResponder {
                    currentAppModel?.copyImageSelectionToClipboard()
                }
            }
            .keyboardShortcut("c")
            .disabled(currentAppModel == nil)

            Button("Select All") {
                let handledByResponder = NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: nil)
                if !handledByResponder {
                    currentAppModel?.selectAllImage()
                }
            }
            .keyboardShortcut("a")
            .disabled(currentAppModel == nil)

            Button("Paste") {
                let handledByResponder = NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                if !handledByResponder {
                    currentAppModel?.paste()
                }
            }
            .keyboardShortcut("v")
            .disabled(currentAppModel == nil)

            Button("Delete") {
                currentAppModel?.deleteSelection()
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(currentAppModel?.canDeleteSelection != true)

            Divider()

            Button("Duplicate") { currentAppModel?.duplicateSelectedAnnotation() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(currentAppModel?.hasSelectedAnnotation != true)

            Button("Bring to Front") { currentAppModel?.moveSelectedAnnotation(toFront: true) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(currentAppModel?.hasSelectedAnnotation != true)
            Button("Bring Forward") { currentAppModel?.moveSelectedAnnotation(forward: true) }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(currentAppModel?.hasSelectedAnnotation != true)
            Button("Send Backward") { currentAppModel?.moveSelectedAnnotation(forward: false) }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(currentAppModel?.hasSelectedAnnotation != true)
            Button("Send to Back") { currentAppModel?.moveSelectedAnnotation(toFront: false) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(currentAppModel?.hasSelectedAnnotation != true)
        }

        // Whole-image operations live under a dedicated "Image" menu.
        CommandMenu("Image") {
            Button("Resize…") { currentAppModel?.activeTool = .resize }
                .keyboardShortcut(Tool.resize.menuShortcutKey, modifiers: Tool.resize.menuShortcutModifiers)
                .disabled(currentAppModel == nil)

            Menu("Rotate") {
                Button("Rotate 90° Clockwise") { currentAppModel?.rotate90(clockwise: true) }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Rotate 90° Counterclockwise") { currentAppModel?.rotate90(clockwise: false) }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Divider()
                Button("Flip Horizontal") { currentAppModel?.flipImage(horizontal: true) }
                Button("Flip Vertical") { currentAppModel?.flipImage(horizontal: false) }
                Divider()
                Button("Rotate…") { currentAppModel?.activeTool = .rotate }
            }
            .disabled(currentAppModel == nil)

            Divider()

            Button(currentAppModel?.hasRemovedBackground == true ? "Restore Background" : "Remove Background") {
                currentAppModel?.removeBackground()
            }
            .keyboardShortcut(Tool.refineBackground.menuShortcutKey, modifiers: Tool.refineBackground.menuShortcutModifiers)
            .disabled(currentAppModel?.canRemoveBackground != true)

            Divider()

            Menu("Magic") {
                Button("Enhance Image…") { currentAppModel?.requestEnhance() }
                    .disabled(currentAppModel == nil)
                // No key equivalent: ⌥⌘M is the system "Minimize All" shortcut.
                Button("AI Edit…") { currentAppModel?.requestPromptEdit() }
                    .disabled(currentAppModel == nil)
            }
            .disabled(currentAppModel == nil)
        }

        CommandGroup(after: .sidebar) {
            Button((currentAppModel?.panelDock.presented.contains(.files) == true ? "Hide" : "Show") + " Files") {
                currentAppModel?.panelDock.toggle(.files)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(currentAppModel?.imageSession == nil)

            Button((currentAppModel?.panelDock.presented.contains(.layers) == true ? "Hide" : "Show") + " Layers") {
                currentAppModel?.panelDock.toggle(.layers)
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(currentAppModel?.imageSession == nil)

            Button((currentAppModel?.panelDock.presented.contains(.history) == true ? "Hide" : "Show") + " History") {
                currentAppModel?.panelDock.toggle(.history)
            }
            .keyboardShortcut("y", modifiers: [.command, .shift])
            .disabled(currentAppModel?.imageSession == nil)

            Button((currentAppModel?.panelDock.presented.contains(.swatches) == true ? "Hide" : "Show") + " Swatches") {
                currentAppModel?.panelDock.toggle(.swatches)
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
            .disabled(currentAppModel?.imageSession == nil)

            Divider()

            Button((currentAppModel?.imageSession?.showGrid == true ? "Hide" : "Show") + " Grid") {
                currentAppModel?.imageSession?.showGrid.toggle()
            }
            .keyboardShortcut("'", modifiers: .command)
            .disabled(currentAppModel?.imageSession == nil)

            Button((currentAppModel?.imageSession?.snapToGrid == true ? "Disable" : "Enable") + " Snap to Grid") {
                currentAppModel?.imageSession?.snapToGrid.toggle()
            }
            .keyboardShortcut("'", modifiers: [.command, .shift])
            .disabled(currentAppModel?.imageSession == nil)

            Button((currentAppModel?.imageSession?.showGridPanel == true ? "Hide" : "Show") + " Grid Settings…") {
                currentAppModel?.imageSession?.showGridPanel.toggle()
            }
            .disabled(currentAppModel?.imageSession == nil)

            Divider()

            Button(currentAppModel?.isWorkspaceSidebarCollapsed == true ? "Show Files Sheet" : "Minimize Files Sheet") {
                currentAppModel?.toggleFilesSheet()
            }
            .keyboardShortcut("1", modifiers: [.command, .option])
            .disabled(currentAppModel?.canToggleFilesSheet != true)

            Divider()

            Button("Zoom In") { currentAppModel?.zoomIn() }
                .keyboardShortcut("+")
                .disabled(currentAppModel == nil)

            Button("Zoom Out") { currentAppModel?.zoomOut() }
                .keyboardShortcut("-")
                .disabled(currentAppModel == nil)

            Button("Fit to Window") { currentAppModel?.resetView() }
                .keyboardShortcut("0", modifiers: [])
                .disabled(currentAppModel == nil)

            Divider()
        }

        // Interactive tools only.
        CommandMenu("Tools") {
            Button("View") { currentAppModel?.activeTool = .view }
                .keyboardShortcut(Tool.view.menuShortcutKey, modifiers: Tool.view.menuShortcutModifiers)
                .disabled(currentAppModel == nil)
            Button("Select") { currentAppModel?.activeTool = .select }
                .keyboardShortcut(Tool.select.menuShortcutKey, modifiers: Tool.select.menuShortcutModifiers)
                .disabled(currentAppModel == nil)
            Button("Pick Colour") { currentAppModel?.activeTool = .pickColor }
                .keyboardShortcut(Tool.pickColor.menuShortcutKey, modifiers: Tool.pickColor.menuShortcutModifiers)
                .disabled(currentAppModel == nil)
            Button("Crop") { currentAppModel?.activeTool = .crop }
                .keyboardShortcut(Tool.crop.menuShortcutKey, modifiers: Tool.crop.menuShortcutModifiers)
                .disabled(currentAppModel == nil)
            Divider()
            Button("Draw") { currentAppModel?.activeTool = .draw }
                .keyboardShortcut(Tool.draw.menuShortcutKey, modifiers: Tool.draw.menuShortcutModifiers)
                .disabled(currentAppModel == nil)
            Button("Text") { currentAppModel?.activeTool = .text }
                .keyboardShortcut(Tool.text.menuShortcutKey, modifiers: Tool.text.menuShortcutModifiers)
                .disabled(currentAppModel == nil)
            Divider()
            Button("Cancel Current Tool") { currentAppModel?.cancelCurrentTool() }
                .keyboardShortcut(.cancelAction)
                .disabled(currentAppModel == nil)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") { currentAppModel?.saveImage() }
                .keyboardShortcut("s")
                .disabled(currentAppModel == nil)

            Button("Save All") { currentAppModel?.saveAllImages() }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(currentAppModel == nil)

            Button("Export…") { currentAppModel?.requestExport() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(currentAppModel == nil)
        }
    }
}

final class ImageKidApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let icon = ImageKidIconRenderer.makeNSImage() {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        ActiveAppModel.open(urls)
        sender.reply(toOpenOrPrint: .success)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        ActiveAppModel.open(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

struct OperationProgress {
    var title: String
    var detail: String
    var startedAt: Date
    var fraction: Double?
}

struct AppWindowRoot: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var appModel = AppModel()

    var body: some View {
        ContentView()
            .environmentObject(appModel)
            .focusedSceneObject(appModel)
            .onAppear {
                ActiveAppModel.register(appModel)
                appModel.configureScreenshotScenarioIfNeeded(settings: settings)
            }
            .frame(minWidth: 720, minHeight: 480)
            .preferredColorScheme(settings.appearanceMode.colorScheme)
    }
}

@main
struct ImageKidApp: App {
    @NSApplicationDelegateAdaptor(ImageKidApplicationDelegate.self) private var applicationDelegate
    @StateObject private var settings = AppSettings()
    @StateObject private var colorLibrary = ColorLibrary()
    private let quickActionLaunch: Result<QuickActionLaunch?, Error>
    private let quickActionModel: QuickActionModel?

    @MainActor
    init() {
        let launchResult = Result { try QuickActionRunner.parse() }
        quickActionLaunch = launchResult

        if case .success(let launch?) = quickActionLaunch {
            let model = QuickActionModel(launch: launch)
            quickActionModel = model
            FileHandle.standardOutput.write(
                Data("ImageKid quick action launch: \(launch.definition.id), \(launch.sourceURLs.count) file(s)\n".utf8)
            )
            Task {
                await model.start()
            }
        } else {
            quickActionModel = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            switch quickActionLaunch {
            case .success(.some):
                Group {
                    if let quickActionModel {
                        QuickActionProgressView(model: quickActionModel)
                    } else {
                        QuickActionErrorView(message: "ImageKid could not prepare this quick action.")
                    }
                }
                .preferredColorScheme(settings.appearanceMode.colorScheme)
            case .success(nil):
                AppWindowRoot()
                    .environmentObject(settings)
                    .environmentObject(colorLibrary)
            case .failure(let error):
                QuickActionErrorView(message: error.localizedDescription)
                    .preferredColorScheme(settings.appearanceMode.colorScheme)
            }
        }
        .defaultSize(width: 940, height: 720)
        .commands {
            AppCommands()
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .preferredColorScheme(settings.appearanceMode.colorScheme)
        }
    }
}
