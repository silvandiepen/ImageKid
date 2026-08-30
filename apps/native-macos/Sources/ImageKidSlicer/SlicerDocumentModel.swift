import AppKit
import CoreGraphics
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// The whole of Slicer's state: one source image and the rectangles drawn on
/// it. There is no project, no document format, and nothing to configure —
/// closing the window is the end of the session.
@MainActor
final class SlicerDocumentModel: ObservableObject {
    /// The loaded image, in the orientation the user sees it.
    struct Source {
        let url: URL?
        let displayName: String
        /// Full-resolution, orientation-corrected. Slices are cut from this.
        let image: CGImage
        /// Display-sized copy used by the canvas so dragging never re-decodes.
        let preview: NSImage
        let outputType: UTType
        let fileExtension: String

        var pixelSize: CGSize { CGSize(width: image.width, height: image.height) }
        var pixelAspect: CGFloat { pixelSize.width / max(pixelSize.height, 1) }
    }

    /// One open image and everything drawn on it. Slicer holds several of
    /// these — the filmstrip switches between them — but each keeps its own
    /// slices, guides, crop, selection, and view transform, so switching never
    /// disturbs work in progress.
    struct ImageSession: Identifiable {
        let id = UUID()
        let source: Source

        var slices: [Slice] = []
        var guides: [SliceGuide] = []
        var cropRect: CGRect?
        var selectedSliceID: Slice.ID?
        var selectedGuideID: SliceGuide.ID?
        var zoom: CGFloat = 1
        var panOffset: CGSize = .zero

        /// False as soon as a slice is added or edited after this image's last
        /// successful save — the only thing close protection needs to know.
        var slicesSavedSinceLastEdit = true

        var hasUnsavedSlices: Bool { !slices.isEmpty && !slicesSavedSinceLastEdit }
    }

    struct ExportSummary {
        let folder: URL
        let created: [URL]
        let failures: [SliceExportOutcome.Failure]
        var isCrop = false
        /// Set when the run covered more than one image.
        var imageCount = 1

        var headline: String {
            if imageCount > 1 {
                return "Saved \(created.count) files from \(imageCount) images to \(folder.lastPathComponent)."
            }
            if isCrop {
                return "Saved \(created.first?.lastPathComponent ?? "the crop") to \(folder.lastPathComponent)."
            }
            let count = created.count
            let noun = count == 1 ? "slice" : "slices"
            if failures.isEmpty {
                return "Saved \(count) \(noun) to \(folder.lastPathComponent)."
            }
            return "Saved \(count) \(noun); \(failures.count) failed."
        }
    }

    struct AlertContent: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    /// Every open image, in the order they were opened — the filmstrip's order.
    @Published private(set) var images: [ImageSession] = []
    @Published var currentImageID: ImageSession.ID?
    /// The slice whose inspector popover is open, if any.
    @Published var inspectingSliceID: Slice.ID?
    @Published private(set) var isLoading = false
    @Published fileprivate(set) var isExporting = false
    @Published var alert: AlertContent?
    @Published private(set) var lastExport: ExportSummary?


    /// What a drag on the canvas does.
    @Published var activeTool: SlicerTool = .slice



    @Published var grid = SliceGrid()
    /// The slices list beside the canvas. Off by default: the canvas is the
    /// interface until the user asks for the list.
    @Published var isSidebarVisible = false
    @Published var isSnappingEnabled = true
    @Published var snapsToCentreLines = true

    let templates: SliceTemplateStore
    let exports: ExportOptionsStore

    /// The stores are injectable so tests never touch real preferences; a
    /// default argument cannot build them, because it would be evaluated
    /// outside the main actor.
    init(templates: SliceTemplateStore? = nil, exports: ExportOptionsStore? = nil) {
        self.templates = templates ?? SliceTemplateStore()
        self.exports = exports ?? ExportOptionsStore()
    }

    // MARK: - The current image
    //
    // Everything below proxies into the current session, so the rest of the
    // app — and every one of these call sites — carries on working on "the
    // slices" without caring how many images are open.

    private var currentIndex: Int? {
        guard let currentImageID else { return nil }
        return images.firstIndex { $0.id == currentImageID }
    }

    var current: ImageSession? {
        guard let currentIndex else { return nil }
        return images[currentIndex]
    }

    private func mutateCurrent(_ body: (inout ImageSession) -> Void) {
        guard let currentIndex else { return }
        body(&images[currentIndex])
    }

    var source: Source? { current?.source }

    var slices: [Slice] {
        get { current?.slices ?? [] }
        set { mutateCurrent { $0.slices = newValue } }
    }

    var guides: [SliceGuide] {
        get { current?.guides ?? [] }
        set { mutateCurrent { $0.guides = newValue } }
    }

    var cropRect: CGRect? {
        get { current?.cropRect }
        set { mutateCurrent { $0.cropRect = newValue } }
    }

    var selectedSliceID: Slice.ID? {
        get { current?.selectedSliceID }
        set { mutateCurrent { $0.selectedSliceID = newValue } }
    }

    var selectedGuideID: SliceGuide.ID? {
        get { current?.selectedGuideID }
        set { mutateCurrent { $0.selectedGuideID = newValue } }
    }

    /// View transform. Slice geometry is stored against the source image, so
    /// these only ever affect what is drawn — and each image keeps its own.
    var zoom: CGFloat {
        get { current?.zoom ?? 1 }
        set { mutateCurrent { $0.zoom = newValue } }
    }

    var panOffset: CGSize {
        get { current?.panOffset ?? .zero }
        set { mutateCurrent { $0.panOffset = newValue } }
    }

    private var slicesSavedSinceLastEdit: Bool {
        get { current?.slicesSavedSinceLastEdit ?? true }
        set { mutateCurrent { $0.slicesSavedSinceLastEdit = newValue } }
    }

    static let minimumZoom: CGFloat = 1
    static let maximumZoom: CGFloat = 12
    private static let previewMaxPixelSize: CGFloat = 4096

    var hasSource: Bool { source != nil }
    var canSave: Bool { source != nil && !slices.isEmpty && !isExporting }
    var hasUnsavedSlices: Bool { !slices.isEmpty && !slicesSavedSinceLastEdit }

    var selectedSlice: Slice? {
        guard let selectedSliceID else { return nil }
        return slices.first { $0.id == selectedSliceID }
    }

    // MARK: - Opening

    func openImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = SliceImageIO.readableTypes
        panel.prompt = "Open"
        guard panel.runModal() == .OK else { return }
        load(urls: panel.urls)
    }

    func load(urls: [URL]) {
        for url in urls { load(url: url) }
    }

    /// Opening an image adds it to the filmstrip rather than replacing what is
    /// already open, so nothing drawn is ever lost by opening something else.
    func load(url: URL) {
        if let existing = images.first(where: { $0.source.url == url }) {
            currentImageID = existing.id
            return
        }
        loadSource(named: url.deletingPathExtension().lastPathComponent) {
            let imageSource = try SliceImageIO.imageSource(at: url)
            return try Self.makeSource(from: imageSource, url: url, displayName: url.deletingPathExtension().lastPathComponent)
        }
    }

    /// `Command-V` when the pasteboard holds an image. There is no source file
    /// to name the output after, so pasted sheets export as `pasted-slice-01`.
    func pasteImage() {
        let types: [NSPasteboard.PasteboardType] = [.png, .tiff]
        guard
            let type = NSPasteboard.general.availableType(from: types),
            let data = NSPasteboard.general.data(forType: type)
        else {
            alert = AlertContent(title: "Nothing to paste", message: "The clipboard does not contain an image.")
            return
        }
        loadSource(named: "pasted") {
            guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
                throw SliceError.unreadableImage
            }
            return try Self.makeSource(from: imageSource, url: nil, displayName: "pasted")
        }
    }

    /// Drag-and-drop from Finder — any number of images at once.
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }

        for provider in fileProviders {
            _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                guard let url, let self else { return }
                Task { @MainActor in
                    guard SliceImageIO.readableTypes.contains(where: { url.pathExtension.lowercased() == $0.preferredFilenameExtension })
                            || UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true else {
                        self.alert = AlertContent(title: "Unsupported file", message: "\(url.lastPathComponent) is not an image Slicer can open.")
                        return
                    }
                    self.load(url: url)
                }
            }
        }
        return true
    }

    private func loadSource(named name: String, _ make: @escaping () throws -> Source) {
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let result = Result { try make() }
            await MainActor.run {
                self.isLoading = false
                switch result {
                case .success(let source):
                    self.append(source)
                case .failure(let error):
                    self.alert = AlertContent(
                        title: "Could not open \(name)",
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    /// Add a decoded source to the filmstrip and make it current.
    func append(_ source: Source) {
        let session = ImageSession(source: source)
        images.append(session)
        currentImageID = session.id
        inspectingSliceID = nil
        lastExport = nil
    }

    /// Replace everything with one image — the single-image entry point.
    func adopt(_ source: Source) {
        images = []
        append(source)
    }

    // MARK: - The filmstrip

    var hasMultipleImages: Bool { images.count > 1 }

    func select(imageID: ImageSession.ID) {
        guard images.contains(where: { $0.id == imageID }) else { return }
        currentImageID = imageID
        inspectingSliceID = nil
    }

    /// Close one image. Anything unsaved on it is confirmed first, because
    /// closing is the only way to lose a session's work.
    func close(imageID: ImageSession.ID) {
        guard let index = images.firstIndex(where: { $0.id == imageID }) else { return }
        if images[index].hasUnsavedSlices, !UITestMode.enabled {
            let alert = NSAlert()
            let count = images[index].slices.count
            alert.messageText = "Close \(images[index].source.displayName)?"
            alert.informativeText = "It has \(count) unsaved \(count == 1 ? "slice" : "slices")."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Close")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        images.remove(at: index)
        inspectingSliceID = nil
        if currentImageID == imageID {
            currentImageID = images.indices.contains(index) ? images[index].id : images.last?.id
        }
    }

    func closeCurrentImage() {
        guard let currentImageID else { return }
        close(imageID: currentImageID)
    }

    /// Copy the current image's slices and guides onto every other open image.
    /// Everything is stored in normalised source coordinates, so one layout
    /// lands correctly on sheets of different pixel sizes.
    func applyLayoutToAllImages() {
        guard let current, hasMultipleImages else { return }
        let slices = current.slices
        let guides = current.guides

        for index in images.indices where images[index].id != current.id {
            // Locked slices are the user saying "not this one", on every image.
            let locked = images[index].slices.filter(\.isLocked)
            images[index].slices = locked + slices.map {
                Slice(rect: $0.rect, name: $0.name, isLocked: false)
            }
            images[index].guides = guides.map { SliceGuide(axis: $0.axis, position: $0.position) }
            images[index].selectedSliceID = nil
            images[index].selectedGuideID = nil
            images[index].slicesSavedSinceLastEdit = false
        }
        lastExport = nil
    }

    private static func makeSource(from imageSource: CGImageSource, url: URL?, displayName: String) throws -> Source {
        let image = try SliceImageIO.loadOrientedImage(from: imageSource)
        let previewImage = SliceImageIO.preview(from: imageSource, maxPixelSize: previewMaxPixelSize) ?? image
        let preview = NSImage(
            cgImage: previewImage,
            size: NSSize(width: previewImage.width, height: previewImage.height)
        )
        let output = SliceImageIO.outputType(for: imageSource)
        return Source(
            url: url,
            displayName: displayName,
            image: image,
            preview: preview,
            outputType: output.type,
            fileExtension: output.fileExtension
        )
    }

    // MARK: - Slice editing

    func addSlice(_ rect: CGRect) {
        guard SliceGeometry.isMeaningful(rect) else { return }
        let slice = Slice(rect: SliceGeometry.clamped(rect))
        slices.append(slice)
        selectedSliceID = slice.id
        selectedGuideID = nil
        markEdited()
    }

    func updateSlice(id: Slice.ID, rect: CGRect) {
        guard let index = slices.firstIndex(where: { $0.id == id }), !slices[index].isLocked else { return }
        slices[index].rect = SliceGeometry.clamped(rect)
        markEdited()
    }

    /// Resize to an exact pixel size from the inspector, holding one anchor
    /// point still.
    func resize(id: Slice.ID, toPixelSize size: CGSize, anchor: SliceAnchor) {
        guard let source, let index = slices.firstIndex(where: { $0.id == id }), !slices[index].isLocked else { return }
        slices[index].rect = SliceGeometry.resized(
            slices[index].rect,
            toPixelSize: size,
            anchor: anchor,
            pixelSize: source.pixelSize
        )
        markEdited()
    }

    /// Move to an exact pixel position from the inspector.
    func move(id: Slice.ID, toPixelOrigin origin: CGPoint) {
        guard let source, let index = slices.firstIndex(where: { $0.id == id }), !slices[index].isLocked else { return }
        slices[index].rect = SliceGeometry.moved(
            slices[index].rect,
            toPixelOrigin: origin,
            pixelSize: source.pixelSize
        )
        markEdited()
    }

    func inspect(id: Slice.ID) {
        selectedSliceID = slices.first { $0.id == id && !$0.isLocked }?.id
        selectedGuideID = nil
        inspectingSliceID = id
    }

    func inspectSelectedSlice() {
        guard let selectedSliceID else { return }
        inspectingSliceID = selectedSliceID
    }

    func rename(id: Slice.ID, to name: String) {
        guard let index = slices.firstIndex(where: { $0.id == id }) else { return }
        slices[index].name = SliceExporter.sanitized(name)
        markEdited()
    }

    func deleteSelectedSlice() {
        guard let selectedSliceID else { return }
        delete(id: selectedSliceID)
    }

    func delete(id: Slice.ID) {
        guard let index = slices.firstIndex(where: { $0.id == id }), !slices[index].isLocked else { return }
        slices.remove(at: index)
        if inspectingSliceID == id { inspectingSliceID = nil }
        if selectedSliceID == id {
            selectedSliceID = slices.indices.contains(index) ? slices[index].id : slices.last?.id
        }
        markEdited()
    }

    func duplicateSelectedSlice() {
        guard let slice = selectedSlice else { return }
        let copy = Slice(rect: SliceGeometry.duplicated(slice.rect), name: nil, isLocked: false)
        slices.append(copy)
        selectedSliceID = copy.id
        markEdited()
    }

    func clearSelection() {
        selectedSliceID = nil
        selectedGuideID = nil
    }

    private func markEdited() {
        slicesSavedSinceLastEdit = false
        lastExport = nil
    }

    /// Replace every slice at once — how templates and Auto Slice apply.
    /// Locked slices are kept: locking one is how the user says "not this one".
    func replaceSlices(with rects: [CGRect]) {
        inspectingSliceID = nil
        let kept = slices.filter(\.isLocked)
        slices = kept + rects.map { Slice(rect: SliceGeometry.clamped($0)) }
        selectedGuideID = nil
        selectedSliceID = slices.first(where: { !$0.isLocked })?.id
        markEdited()
    }

    // MARK: - Nudging, copying, dragging out

    /// Move the selection by whole source pixels. A guide moves along its own
    /// axis; anything perpendicular to it is ignored.
    func nudgeSelection(dx: Int, dy: Int) {
        guard let source else { return }
        let step = CGSize(
            width: CGFloat(dx) / source.pixelSize.width,
            height: CGFloat(dy) / source.pixelSize.height
        )

        if let selectedGuideID, let index = guides.firstIndex(where: { $0.id == selectedGuideID }) {
            let delta = guides[index].axis == .vertical ? step.width : step.height
            guides[index].position = min(max(guides[index].position + delta, 0), 1)
            return
        }

        guard let id = selectedSliceID,
              let index = slices.firstIndex(where: { $0.id == id }),
              !slices[index].isLocked
        else { return }
        slices[index].rect = SliceGeometry.moved(slices[index].rect, by: step)
        markEdited()
    }

    var canCopySelectedSlice: Bool { selectedSlice != nil }

    /// Put the selected slice on the pasteboard as an image, so it can be
    /// pasted straight into something else without a round trip through disk.
    func copySelectedSliceToClipboard() {
        guard let slice = selectedSlice, let image = croppedImage(for: slice) else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )])
    }

    /// A real file for one slice, written into the app's own temporary
    /// directory so it can be dragged out to the Finder. Named exactly as the
    /// export would name it, honouring the current export options.
    func temporaryFile(for sliceID: Slice.ID) -> URL? {
        guard
            let source,
            let index = slices.firstIndex(where: { $0.id == sliceID }),
            let image = croppedImage(for: slices[index])
        else { return nil }

        let options = exports.options
        let output = options.resolved(sourceType: source.outputType, sourceExtension: source.fileExtension)
        let base = SliceExporter.fileName(
            sourceName: source.displayName,
            index: index,
            count: slices.count,
            customName: slices[index].name,
            prefix: options.sanitizedPrefix
        )

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("dragged-slices", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = SliceExporter.uniqueURL(in: folder, baseName: base, fileExtension: output.fileExtension)

        do {
            let bounds = CGRect(origin: .zero, size: CGSize(width: image.width, height: image.height))
            let resampled = options.isScaled
                ? try SliceImageIO.scaled(image, to: options.outputPixelSize(for: bounds))
                : image
            try SliceImageIO.writeAtomically(
                resampled,
                to: url,
                type: output.type,
                quality: options.isLossy(sourceType: source.outputType) ? options.quality : nil
            )
            return url
        } catch {
            return nil
        }
    }

    /// The slice's own pixels, cut from the full-resolution source.
    private func croppedImage(for slice: Slice) -> CGImage? {
        guard
            let source,
            let pixelRect = SliceGeometry.pixelRect(slice.rect, pixelSize: source.pixelSize)
        else { return nil }
        return source.image.cropping(to: pixelRect)
    }

    // MARK: - Locking

    var selectedSliceIsLocked: Bool { selectedSlice?.isLocked ?? false }

    var hasLockedSlices: Bool { slices.contains(where: \.isLocked) }

    func setLocked(_ locked: Bool, id: Slice.ID) {
        guard let index = slices.firstIndex(where: { $0.id == id }) else { return }
        slices[index].isLocked = locked
        // A locked slice cannot be the selection: it no longer answers the
        // pointer, so leaving handles on it would be a lie.
        if locked, selectedSliceID == id { selectedSliceID = nil }
    }

    func toggleLockOnSelection() {
        guard let slice = selectedSlice else { return }
        setLocked(!slice.isLocked, id: slice.id)
    }

    func unlockAllSlices() {
        for index in slices.indices { slices[index].isLocked = false }
    }

    // MARK: - Crop

    /// The crop in whole source pixels, for the readout in the bar.
    var cropPixelRect: CGRect? {
        guard let source, let cropRect else { return nil }
        return SliceGeometry.pixelRect(cropRect, pixelSize: source.pixelSize)
    }

    var canCropAndSave: Bool { source != nil && cropRect != nil && !isExporting }

    /// Entering the Crop tool with nothing cropped yet starts from the whole
    /// image, so the first drag pulls an edge in rather than starting from
    /// nothing.
    func prepareCropIfNeeded() {
        guard hasSource, cropRect == nil else { return }
        cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    func setCrop(_ rect: CGRect) {
        cropRect = SliceGeometry.clamped(rect)
    }

    func resetCrop() {
        cropRect = hasSource ? CGRect(x: 0, y: 0, width: 1, height: 1) : nil
    }

    /// Crop the source to the region and write it as one file.
    func cropAndSave() {
        guard let source, let cropRect else { return }

        let options = exports.options
        let output = options.resolved(sourceType: source.outputType, sourceExtension: source.fileExtension)
        let suggestedName = "\(options.sanitizedPrefix)\(SliceExporter.sanitized(source.displayName) ?? "image")-crop"
        let url: URL

        if let folder = UITestMode.saveFolder {
            url = SliceExporter.uniqueURL(
                in: folder,
                baseName: suggestedName,
                fileExtension: output.fileExtension
            )
        } else {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [output.type]
            panel.nameFieldStringValue = "\(suggestedName).\(output.fileExtension)"
            panel.prompt = "Save Crop"
            if let parent = source.url?.deletingLastPathComponent() {
                panel.directoryURL = parent
            }
            guard panel.runModal() == .OK, let chosen = panel.url else { return }
            url = chosen
        }

        isExporting = true
        let image = source.image
        let quality = options.isLossy(sourceType: source.outputType) ? options.quality : nil
        Task.detached(priority: .userInitiated) {
            let result = Result {
                try SliceExporter.exportCrop(
                    image,
                    rect: cropRect,
                    outputType: output.type,
                    options: options,
                    quality: quality,
                    to: url
                )
            }
            await MainActor.run {
                self.isExporting = false
                switch result {
                case .success:
                    self.lastExport = ExportSummary(
                        folder: url.deletingLastPathComponent(),
                        created: [url],
                        failures: [],
                        isCrop: true
                    )
                case .failure(let error):
                    self.alert = AlertContent(
                        title: "The crop could not be saved",
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    // MARK: - Guides

    func addGuide(axis: SliceGuide.Axis, at position: CGFloat) {
        let guide = SliceGuide(axis: axis, position: position)
        guides.append(guide)
        selectedGuideID = guide.id
        selectedSliceID = nil
    }

    func updateGuide(id: SliceGuide.ID, position: CGFloat) {
        guard let index = guides.firstIndex(where: { $0.id == id }) else { return }
        guides[index].position = min(max(position, 0), 1)
    }

    func delete(guideID: SliceGuide.ID) {
        guides.removeAll { $0.id == guideID }
        if selectedGuideID == guideID { selectedGuideID = nil }
    }

    func clearGuides() {
        guides.removeAll()
        selectedGuideID = nil
    }

    /// `Delete` acts on whatever is selected — a guide if one is, otherwise
    /// the selected slice.
    func deleteSelection() {
        if let selectedGuideID {
            delete(guideID: selectedGuideID)
            return
        }
        deleteSelectedSlice()
    }

    var hasSelection: Bool { selectedSliceID != nil || selectedGuideID != nil }

    // MARK: - Auto slice and templates

    /// Every cut line currently on the canvas: the guides, plus the grid when
    /// it is switched on.
    var cutLines: (vertical: [CGFloat], horizontal: [CGFloat]) {
        var vertical = guides.filter { $0.axis == .vertical }.map(\.position)
        var horizontal = guides.filter { $0.axis == .horizontal }.map(\.position)
        vertical.append(contentsOf: grid.verticalLines)
        horizontal.append(contentsOf: grid.horizontalLines)
        return (vertical, horizontal)
    }

    var canAutoSlice: Bool {
        guard hasSource else { return false }
        let lines = cutLines
        return !lines.vertical.isEmpty || !lines.horizontal.isEmpty
    }

    /// Turn the cut lines into one slice per cell.
    func autoSlice() {
        guard canAutoSlice else { return }
        let lines = cutLines
        let rects = SliceAutoLayout.rects(verticalCuts: lines.vertical, horizontalCuts: lines.horizontal)
        guard !rects.isEmpty, confirmReplacingSlices(with: rects.count) else { return }
        replaceSlices(with: rects)
    }

    /// Lay a template over the whole image: its grid becomes the visible grid,
    /// and its cells become the slices.
    func apply(_ template: SliceTemplate) {
        guard hasSource else { return }
        let rects = template.rects
        guard !rects.isEmpty, confirmReplacingSlices(with: rects.count) else { return }
        grid.columns = template.columns
        grid.rows = template.rows
        replaceSlices(with: rects)
    }

    func saveCurrentGridAsTemplate(named name: String) {
        templates.save(name: name, columns: grid.columns, rows: grid.rows)
    }

    /// Replacing hand-drawn work has no undo, so ask first — but only when
    /// there is unsaved work to lose.
    private func confirmReplacingSlices(with count: Int) -> Bool {
        guard hasUnsavedSlices, !UITestMode.enabled else { return true }

        let alert = NSAlert()
        let losing = slices.filter { !$0.isLocked }.count
        guard losing > 0 else { return true }
        alert.messageText = "Replace \(losing) unsaved \(losing == 1 ? "slice" : "slices")?"
        alert.informativeText = "This lays out \(count) new \(count == 1 ? "slice" : "slices") over the whole image."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - View transform

    func resetView() {
        zoom = 1
        panOffset = .zero
    }

    func zoomIn() { setZoom(zoom * 1.25) }
    func zoomOut() { setZoom(zoom / 1.25) }

    func setZoom(_ value: CGFloat) {
        zoom = min(max(value, Self.minimumZoom), Self.maximumZoom)
        if zoom == Self.minimumZoom { panOffset = .zero }
    }

    // MARK: - Saving

    func save() {
        guard let source else { return }
        guard !slices.isEmpty else {
            alert = AlertContent(title: "No slices yet", message: SliceError.noSlices.localizedDescription)
            return
        }

        if let folder = UITestMode.saveFolder {
            export(source: source, to: folder)
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Save Slices"
        panel.message = "Choose where to save \(slices.count) \(slices.count == 1 ? "slice" : "slices")."
        if let parent = source.url?.deletingLastPathComponent() {
            panel.directoryURL = parent
        }
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        export(source: source, to: folder)
    }

    private func export(source: Source, to folder: URL) {
        let request = SliceExportRequest(
            sourceName: source.displayName,
            image: source.image,
            sourceType: source.outputType,
            sourceExtension: source.fileExtension,
            slices: slices,
            folder: folder,
            options: exports.options
        )

        isExporting = true
        Task.detached(priority: .userInitiated) {
            let outcome = SliceExporter.export(request)
            await MainActor.run {
                self.isExporting = false
                self.lastExport = ExportSummary(
                    folder: folder,
                    created: outcome.created,
                    failures: outcome.failures
                )
                if outcome.failures.isEmpty {
                    self.slicesSavedSinceLastEdit = true
                } else if outcome.created.isEmpty {
                    self.alert = AlertContent(
                        title: "No slices were saved",
                        message: outcome.failures.map(\.message).joined(separator: "\n")
                    )
                }
            }
        }
    }

    /// Every image's slices, in one run: one subfolder per image inside the
    /// folder the user picks, so 8 sheets do not land as 72 loose files.
    var canExportAll: Bool { images.contains { !$0.slices.isEmpty } && !isExporting }

    func exportAll() {
        let ready = images.filter { !$0.slices.isEmpty }
        guard !ready.isEmpty else {
            alert = AlertContent(title: "Nothing to export", message: SliceError.noSlices.localizedDescription)
            return
        }

        let root: URL
        if let folder = UITestMode.saveFolder {
            root = folder
        } else {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "Export All"
            panel.message = "Each image gets its own folder here."
            guard panel.runModal() == .OK, let chosen = panel.url else { return }
            root = chosen
        }

        let options = exports.options
        let requests: [(name: String, request: SliceExportRequest)] = ready.map { session in
            let name = SliceExporter.sanitized(session.source.displayName) ?? "image"
            return (name, SliceExportRequest(
                sourceName: session.source.displayName,
                image: session.source.image,
                sourceType: session.source.outputType,
                sourceExtension: session.source.fileExtension,
                slices: session.slices,
                folder: root.appendingPathComponent(name, isDirectory: true),
                options: options
            ))
        }
        let exportedIDs = ready.map(\.id)

        isExporting = true
        Task.detached(priority: .userInitiated) {
            var created: [URL] = []
            var failures: [SliceExportOutcome.Failure] = []

            for entry in requests {
                do {
                    try FileManager.default.createDirectory(at: entry.request.folder, withIntermediateDirectories: true)
                } catch {
                    failures.append(.init(sliceName: entry.name, message: error.localizedDescription))
                    continue
                }
                let outcome = SliceExporter.export(entry.request)
                created.append(contentsOf: outcome.created)
                failures.append(contentsOf: outcome.failures)
            }

            let finalCreated = created
            let finalFailures = failures
            await MainActor.run {
                self.isExporting = false
                self.lastExport = ExportSummary(
                    folder: root,
                    created: finalCreated,
                    failures: finalFailures,
                    imageCount: requests.count
                )
                if finalFailures.isEmpty {
                    for id in exportedIDs {
                        guard let index = self.images.firstIndex(where: { $0.id == id }) else { continue }
                        self.images[index].slicesSavedSinceLastEdit = true
                    }
                } else if finalCreated.isEmpty {
                    self.alert = AlertContent(
                        title: "No slices were saved",
                        message: finalFailures.map(\.message).joined(separator: "\n")
                    )
                }
            }
        }
    }

    func revealLastExport() {
        guard let lastExport, !lastExport.created.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(lastExport.created)
    }

    // MARK: - Discard protection

    /// Every image with unsaved slices, not just the one on screen — quitting
    /// loses all of them.
    var imagesWithUnsavedSlices: [ImageSession] { images.filter(\.hasUnsavedSlices) }

    /// Returns `true` when it is safe to throw every open session away.
    @discardableResult
    func confirmDiscardingSlices(actionTitle: String) -> Bool {
        let unsaved = imagesWithUnsavedSlices
        guard !unsaved.isEmpty else { return true }
        // A modal NSAlert would hang the XCUITest runner's own launch/quit.
        guard !UITestMode.enabled else { return true }

        let count = unsaved.reduce(0) { $0 + $1.slices.count }
        let alert = NSAlert()
        alert.messageText = "Discard \(count) unsaved \(count == 1 ? "slice" : "slices")?"
        alert.informativeText = unsaved.count == 1
            ? "The slices you drew have not been saved yet."
            : "Across \(unsaved.count) images, none of them saved yet."
        alert.alertStyle = .warning
        alert.addButton(withTitle: actionTitle)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
