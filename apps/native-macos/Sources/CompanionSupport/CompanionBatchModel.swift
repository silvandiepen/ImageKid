import AppKit
import CoreML
import Foundation
import ImageKidInference
import UniformTypeIdentifiers

@MainActor
final class CompanionBatchModel: ObservableObject {
    enum UpscaleEngine: String, CaseIterable, Identifiable {
        case standard
        case bestQuality

        var id: String { rawValue }

        var label: String {
            switch self {
            case .standard: "Standard"
            case .bestQuality: "Best Quality"
            }
        }
    }

    enum CutoutEngine: String, CaseIterable, Identifiable {
        case builtIn
        case bestQuality
        case flatBackground

        var id: String { rawValue }

        var label: String {
            switch self {
            case .builtIn: "Subject"
            case .bestQuality: "Best Subject"
            case .flatBackground: "Flat Backdrop"
            }
        }

        var explanation: String {
            switch self {
            case .builtIn:
                "Apple's subject finder. Fast, and needs no download."
            case .bestQuality:
                "BiRefNet. Slower, with much cleaner edges on photos and people."
            case .flatBackground:
                "For renders and product shots on one flat colour. Keeps everything the "
                + "backdrop does not touch \u{2014} water, shadows, base plates."
            }
        }
    }

    enum Operation {
        case upscale(scale: Int, contentMode: UpscaleContentMode, engine: UpscaleEngine)
        case cutout(engine: CutoutEngine)
    }

    /// What a run should do with images whose result file is already on disk.
    enum ExistingResultPolicy {
        case overwrite
        case skip
    }

    @Published var items: [BatchItem] = []
    /// Set by the view from its current settings. The queue needs it to work out where
    /// each image would land before a run starts.
    @Published var operation: Operation? { didSet { refreshExistingResults(); refreshFolderWatcher() } }
    @Published var customDestinationURL: URL? { didSet { refreshExistingResults(); refreshFolderWatcher() } }
    @Published var overwriteOriginals = false { didSet { refreshExistingResults(); refreshFolderWatcher() } }
    /// Batch-wide removal strength. Only the Flat Backdrop engine reads it: the subject
    /// finders take their own view, and are corrected per image in the editor.
    @Published var cutoutStrength: Double = 0.5
    /// Set when the destination folder is missing, trashed or has moved.
    @Published private(set) var destinationWarning: String?
    @Published var isProcessing = false
    @Published var overallProgress = 0.0
    @Published private(set) var isWatchingFolder = false
    @Published private(set) var watchedFolderURL: URL?
    @Published private(set) var watcherMessage: String?

    /// What to do with each input file once its result is written. Opt-in: `.keep`
    /// leaves the originals alone, which is what every earlier version did.
    @Published var sourceAction: SourceFileAction = .keep { didSet { persistSourceAction() } }
    @Published var sourceActionFolderURL: URL?

    private var processingTask: Task<Void, Never>?
    /// Output paths this run has already claimed, so a batch never eats its own output.
    private var usedOutputPaths: Set<String> = []
    /// Source folders the user granted write access to, so a Move/Trash/Delete action can
    /// take a file out of the folder it was dropped from. Remembered across launches:
    /// being asked for the same inbox folder every session is the whole annoyance.
    private let sourceFolderGrants = SecurityScopedFolderSet(defaultsKey: "companion.sourceFolderBookmarks")
    /// Source folders this session has already raised, granted or not.
    private var askedSourceFolders: Set<String> = []

    private let destinationFolder = SecurityScopedFolder(defaultsKey: "companion.destinationBookmark")
    private let sourceActionFolder = SecurityScopedFolder(defaultsKey: "companion.sourceActionBookmark")
    private let watchedFolder = SecurityScopedFolder(defaultsKey: "companion.watchedFolderBookmark")
    private var folderWatcher: FolderWatcher?
    private var watchNeedsRun = false

    private static let sourceActionKey = "companion.sourceAction"
    private static let watchingFolderKey = "companion.isWatchingFolder"
    private static var watcherOwnerExists = false

    private static func claimWatcherOwnership() -> Bool {
        guard !watcherOwnerExists else { return false }
        watcherOwnerExists = true
        return true
    }

    init() {
        customDestinationURL = destinationFolder.restore()
        updateDestinationWarning()
        sourceActionFolderURL = sourceActionFolder.restore()
        watchedFolderURL = watchedFolder.restore()
        sourceAction = Self.restoredSourceAction()
        // Single-owner on purpose: a second window restoring the watcher would process
        // every dropped file twice, both writing to the same destination.
        isWatchingFolder = watchedFolderURL != nil
            && UserDefaults.standard.bool(forKey: Self.watchingFolderKey)
            && Self.claimWatcherOwnership()
        sourceFolderGrants.restoreAll()
    }

    var finishedCount: Int {
        items.filter(\.isDone).count
    }

    /// Images whose result file is already sitting in the destination.
    var existingResultCount: Int {
        items.filter(\.wouldOverwriteExistingFile).count
    }

    var needsExistingResultDecision: Bool {
        existingResultCount > 0
    }

    func openFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = CompanionImageIO.readableTypes
        if panel.runModal() == .OK {
            addFiles(panel.urls)
        }
    }

    func chooseDestinationFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        if panel.runModal() == .OK, let url = panel.url {
            setDestination(url)
        }
    }

    /// Chooses and remembers a single Cutout inbox. The selected folder's security
    /// scope stays open, which is what allows background filesystem events to remain
    /// useful after the app is relaunched.
    func chooseWatchedFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Watch Folder"
        panel.message = "Images placed directly in this folder will be processed automatically."
        if panel.runModal() == .OK, let url = panel.url {
            watchedFolder.adopt(url)
            watchedFolderURL = url
            setWatchingFolder(true)
        }
    }

    func setWatchingFolder(_ enabled: Bool) {
        guard enabled else {
            isWatchingFolder = false
            UserDefaults.standard.set(false, forKey: Self.watchingFolderKey)
            watcherMessage = nil
            folderWatcher?.stop()
            folderWatcher = nil
            return
        }

        guard watchedFolderURL != nil else {
            chooseWatchedFolder()
            return
        }
        if customDestinationURL == nil {
            chooseDestinationFolder()
            guard customDestinationURL != nil else { return }
        }
        isWatchingFolder = true
        UserDefaults.standard.set(true, forKey: Self.watchingFolderKey)
        refreshFolderWatcher()
    }

    private func setDestination(_ url: URL) {
        destinationFolder.adopt(url)
        customDestinationURL = url
        updateDestinationWarning()
    }

    /// What is wrong with the destination, if anything. A bookmark keeps working when
    /// the folder it points at is renamed, moved or thrown away, so results can keep
    /// being written somewhere the user is no longer looking — or into the Trash, to be
    /// erased the next time it is emptied.
    enum DestinationProblem: Equatable {
        case missing
        case inTrash
        case moved(from: String)
    }

    func destinationProblem() -> DestinationProblem? {
        guard let url = customDestinationURL else { return nil }
        let path = url.standardizedFileURL.path

        if path.contains("/.Trash/") || path.hasSuffix("/.Trash") { return .inTrash }

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        guard exists, isDirectory.boolValue else { return .missing }

        if let granted = destinationFolder.grantedPath, granted != path {
            return .moved(from: granted)
        }
        return nil
    }

    private func updateDestinationWarning() {
        switch destinationProblem() {
        case .none:
            destinationWarning = nil
        case .missing:
            destinationWarning = "This folder no longer exists. Choose another before running."
        case .inTrash:
            destinationWarning = "This folder is in the Trash. Anything written to it will be erased."
        case .moved(let from):
            destinationWarning = "This folder moved from \(from). Results go to its new place."
        }
    }

    /// Never write into a destination that has gone missing, been thrown away, or moved
    /// out from under the user. This is the difference between "the results are in that
    /// folder" and "the results are gone", so it stops the run rather than guessing.
    private func confirmDestination() -> Bool {
        updateDestinationWarning()
        guard let problem = destinationProblem(), let url = customDestinationURL else { return true }
        let name = url.lastPathComponent

        let alert = NSAlert()
        alert.alertStyle = .critical
        switch problem {
        case .missing:
            alert.messageText = "\u{201C}\(name)\u{201D} no longer exists"
            alert.informativeText = "The destination folder has been deleted. Nothing has been "
                + "written. Choose a folder that exists and run again."
        case .inTrash:
            alert.messageText = "\u{201C}\(name)\u{201D} is in the Trash"
            alert.informativeText = "The destination folder was thrown away, and anything written "
                + "to it is erased the next time the Trash is emptied. Nothing has been written."
        case .moved(let from):
            alert.messageText = "\u{201C}\(name)\u{201D} is not where it was"
            alert.informativeText = "It was \(from).\nIt is now \(url.path).\n\nNothing has been "
                + "written. Choose the folder you actually want."
        }
        alert.addButton(withTitle: "Choose Folder...")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        chooseDestinationFolder()
        return customDestinationURL != nil && destinationProblem() == nil
    }

    func addFiles(_ urls: [URL]) {
        // Both paths: an item whose original was filed away by a When Done action still
        // owns the path it arrived on, and re-queueing that path would process a file
        // that is no longer there.
        var existing = Set(items.map(\.sourceURL.standardizedFileURL))
        existing.formUnion(items.map(\.originalSourceURL.standardizedFileURL))

        let newItems = urls
            .filter { url in
                guard existing.insert(url.standardizedFileURL).inserted else { return false }
                return CompanionImageIO.readableTypes.contains { url.conforms(to: $0) }
            }
            .map { url in
                var item = BatchItem(sourceURL: url, originalSourceURL: url)
                if let properties = CompanionImageIO.properties(at: url) {
                    item.pixelSize = CGSize(width: properties.width, height: properties.height)
                }
                item.thumbnail = CompanionImageIO.thumbnail(at: url)
                return item
            }
        items.append(contentsOf: newItems)
        refreshExistingResults()
    }

    func removeItems(_ ids: Set<BatchItem.ID>) {
        guard !isProcessing else { return }
        items.removeAll { ids.contains($0.id) }
    }

    /// Put items back in the queue so the next run picks them up again — the way out
    /// of a batch that failed for a reason the user has since fixed.
    func resetItems(_ ids: Set<BatchItem.ID>) {
        guard !isProcessing else { return }
        for index in items.indices where ids.contains(items[index].id) {
            items[index].state = .waiting
            items[index].outputThumbnail = nil
            items[index].sourceActionNote = nil
            items[index].sourceActionFailed = false
        }
        refreshExistingResults()
    }

    func clearCompleted() {
        guard !isProcessing else { return }
        items.removeAll(where: \.isDone)
    }

    func cancel() {
        processingTask?.cancel()
    }

    func generate(existingResults policy: ExistingResultPolicy = .overwrite) {
        guard !isProcessing, let operation else { return }

        if customDestinationURL == nil, !canWriteBesideSources(for: operation) {
            guard requestDestinationFolder() else { return }
        }
        guard confirmDestination() else { return }

        if sourceAction.needsFolder, sourceActionFolderURL == nil {
            chooseSourceActionFolder()
            guard sourceActionFolderURL != nil else { return }
        }
        if sourceAction.removesOriginal {
            let unasked = blockedSourceFolders()
                .filter { !askedSourceFolders.contains($0.standardizedFileURL.path) }
            if !unasked.isEmpty {
                // Asked once per folder per session. Re-asking on every Generate is what
                // turned a tidying preference into something that blocked the batch.
                unasked.forEach { askedSourceFolders.insert($0.standardizedFileURL.path) }
                guard requestSourceFolderAccess() else { return }
            }
        }
        refreshExistingResults()

        var targets: [BatchItem.ID] = []
        for index in items.indices {
            if policy == .skip, items[index].wouldOverwriteExistingFile {
                items[index].state = .skipped
                continue
            }
            targets.append(items[index].id)
        }
        guard !targets.isEmpty else { return }

        usedOutputPaths = []
        isProcessing = true
        overallProgress = 0
        processingTask = Task {
            defer {
                isProcessing = false
                processingTask = nil
                overallProgress = 1
                refreshExistingResults()
            }

            let total = targets.count
            for (offset, id) in targets.enumerated() {
                if Task.isCancelled {
                    update(id: id, state: .failed(CompanionProcessingError.cancelled.localizedDescription))
                    continue
                }

                update(id: id, state: .processing("Opening image", nil))
                do {
                    let output = try await processItem(
                        id: id,
                        operation: operation,
                        overwriteExisting: policy == .overwrite
                    )
                    update(id: id, state: .done(output))
                    if let index = items.firstIndex(where: { $0.id == id }) {
                        items[index].outputThumbnail = CompanionImageIO.thumbnail(at: output)
                    }
                    applySourceAction(to: id, output: output)
                } catch is CancellationError {
                    update(id: id, state: .failed(CompanionProcessingError.cancelled.localizedDescription))
                } catch {
                    update(id: id, state: .failed(error.localizedDescription))
                }
                overallProgress = Double(offset + 1) / Double(total)
            }
        }
    }

    /// The folder a Move or Copy action files the originals into. Remembered across
    /// launches the same way the output folder is.
    func chooseSourceActionFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.message = "Originals are filed here once their result has been written."
        if panel.runModal() == .OK, let url = panel.url {
            sourceActionFolder.adopt(url)
            sourceActionFolderURL = url
        }
    }

    private static func restoredSourceAction() -> SourceFileAction {
        guard
            let raw = UserDefaults.standard.string(forKey: sourceActionKey),
            let action = SourceFileAction(rawValue: raw)
        else {
            return .keep
        }
        return action
    }

    private func persistSourceAction() {
        UserDefaults.standard.set(sourceAction.rawValue, forKey: Self.sourceActionKey)
    }

    /// Files the input away once its result exists. A failure here is reported on the row
    /// and never fails the item: the image was processed, the tidying was not.
    private func applySourceAction(to id: BatchItem.ID, output: URL) {
        guard sourceAction != .keep, let index = items.firstIndex(where: { $0.id == id }) else { return }
        let source = items[index].sourceURL

        // With "Overwrite originals" on, the original *is* the result. Moving or deleting
        // it would take the finished image with it.
        guard source.standardizedFileURL != output.standardizedFileURL else {
            items[index].sourceActionNote = "Original kept \u{2014} it is the result"
            return
        }

        do {
            let outcome = try SourceFileActionRunner.apply(
                sourceAction,
                to: source,
                folder: sourceActionFolderURL
            )
            if case .relocated(let moved) = outcome {
                items[index].sourceURL = moved
            }
            items[index].sourceActionNote = outcome.note
            items[index].sourceActionFailed = false
        } catch {
            items[index].sourceActionNote = error.localizedDescription
            items[index].sourceActionFailed = true
        }
    }

    /// Taking a file out of its folder needs write access to that folder, which dropping
    /// the file does not grant. Probed by writing, because `isWritableFile` reports POSIX
    /// permission bits, which say nothing about what the sandbox will allow.
    private func canModifySourceFolders() -> Bool {
        blockedSourceFolders().isEmpty
    }

    private func sourceFolders() -> [URL] {
        var seen: Set<String> = []
        return items
            .filter { !$0.isDone }
            .map { $0.sourceURL.deletingLastPathComponent() }
            .filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private func blockedSourceFolders() -> [URL] {
        sourceFolders().filter { !canCreateAndRemoveFile(in: $0) }
    }

    private func canCreateAndRemoveFile(in folder: URL) -> Bool {
        let probe = folder.appendingPathComponent(".imagekid-write-probe-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: probe.path, contents: nil) else { return false }
        try? FileManager.default.removeItem(at: probe)
        return true
    }

    private func requestSourceFolderAccess() -> Bool {
        guard let first = blockedSourceFolders().first else { return true }
        let name = first.lastPathComponent

        let alert = NSAlert()
        alert.messageText = "Allow \(Self.appName) to take images out of \u{201C}\(name)\u{201D}"
        alert.informativeText = "Dropping images grants access to the images, not to the folder "
            + "around them, so the originals cannot be moved yet. Choose "
            + "\u{201C}\(name)\u{201D} itself \u{2014} not the folder they are moving to \u{2014} "
            + "and the choice is remembered. The batch can also run and leave the originals alone."
        alert.addButton(withTitle: "Choose \u{201C}\(name)\u{201D}...")
        alert.addButton(withTitle: "Process Without Moving")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            break
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        // Open the *parent*, so the folder itself is in the list and can be clicked.
        // Opening inside it is the trap: there is nothing in there to select.
        panel.directoryURL = first.deletingLastPathComponent()
        panel.message = "Select \u{201C}\(name)\u{201D} \u{2014} the folder the images came from."
        panel.prompt = "Allow Access"
        guard panel.runModal() == .OK else { return false }

        for url in panel.urls {
            sourceFolderGrants.adopt(url)
        }
        // Whether or not the grant landed, the run goes ahead: any folder still out of
        // reach is reported per row rather than stopping the batch.
        return true
    }

    /// Starts, restarts or stops the inbox watcher to match the current settings.
    private func refreshFolderWatcher() {
        folderWatcher?.stop()
        folderWatcher = nil

        guard isWatchingFolder, let folder = watchedFolderURL else {
            watcherMessage = nil
            return
        }
        guard let destination = customDestinationURL else {
            watcherMessage = "Choose an output folder before watching."
            return
        }
        guard destination.standardizedFileURL != folder.standardizedFileURL else {
            watcherMessage = "The output folder cannot be the watched folder."
            return
        }

        let watcher = FolderWatcher(folder: folder) { [weak self] urls in
            self?.ingestWatchedFiles(urls)
        }
        folderWatcher = watcher
        watcher.start()
        // The Watching row already names the folder; this line is for problems only.
        watcherMessage = nil
    }

    /// New files in the inbox join the queue and are processed. Anything that already
    /// has a result is skipped, so a folder that is re-scanned is not redone.
    private func ingestWatchedFiles(_ urls: [URL]) {
        addFiles(urls)
        guard !isProcessing else { return }
        generate(existingResults: .skip)
    }

    private static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? ProcessInfo.processInfo.processName
    }

    /// Look at the destination and mark every queued image that would land on a file
    /// that already exists, so the queue can say so before anything runs.
    func refreshExistingResults() {
        updateDestinationWarning()
        guard let operation else { return }
        for index in items.indices {
            let source = items[index].sourceURL
            let planned = plannedOutputURL(for: source, operation: operation)
            items[index].plannedOutputURL = planned
            // Writing back over the original is a deliberate choice, not a collision.
            items[index].hasExistingResult = planned != source
                && FileManager.default.fileExists(atPath: planned.path)
        }
    }

    private func plannedOutputURL(for source: URL, operation: Operation) -> URL {
        CompanionImageIO.plannedDestinationURL(
            for: source,
            operationFolderName: outputFolderName(for: operation),
            suffix: outputSuffix(for: operation),
            extension: outputExtension(for: operation, source: source),
            customFolder: customDestinationURL,
            overwriteOriginals: overwriteOriginals
        )
    }

    private func outputSuffix(for operation: Operation) -> String {
        switch operation {
        case .upscale(let scale, _, _): "-\(scale)x"
        case .cutout: "-cutout"
        }
    }

    private func outputExtension(for operation: Operation, source: URL) -> String {
        switch operation {
        case .upscale: source.preferredRasterExtension(defaultExtension: "png")
        case .cutout: "png"
        }
    }

    private func outputFolderName(for operation: Operation) -> String {
        switch operation {
        case .upscale: "ImageKid Upscaled"
        case .cutout: "ImageKid Cutouts"
        }
    }

    /// Dropping a file grants access to that file, not to the folder holding it, so the
    /// default sibling output folder often cannot be created. Find that out once, before
    /// the batch, instead of failing on every image in it.
    private func canWriteBesideSources(for operation: Operation) -> Bool {
        let folderName = outputFolderName(for: operation)
        let parents = Set(items.map { $0.sourceURL.deletingLastPathComponent() })
        return parents.allSatisfy { parent in
            let folder = parent.appendingPathComponent(folderName, isDirectory: true)
            return (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil
        }
    }

    private func requestDestinationFolder() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Choose where the results should go"
        alert.informativeText = "macOS only lets this app write into folders you point it at. "
            + "Dropping images grants access to those files, not to the folder around them."
        alert.addButton(withTitle: "Choose Folder...")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        chooseDestinationFolder()
        return customDestinationURL != nil
    }

    private func processItem(
        id: BatchItem.ID,
        operation: Operation,
        overwriteExisting: Bool
    ) async throws -> URL {
        guard let sourceURL = items.first(where: { $0.id == id })?.sourceURL else {
            throw CompanionProcessingError.unreadableImage
        }
        // Say so before any work, rather than letting a vanished file surface later as a
        // black image or as a confusing failure to tidy up afterwards.
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw CompanionProcessingError.sourceMissing(sourceURL.lastPathComponent)
        }
        let customDestinationURL = customDestinationURL
        let overwriteOriginals = overwriteOriginals
        let folderName = outputFolderName(for: operation)
        let strength = cutoutStrength

        // Overwriting the file that was already there is the user's call; overwriting a
        // file this same run just produced never is, so that one still gets a new name.
        let planned = plannedOutputURL(for: sourceURL, operation: operation)
        let overwrite = overwriteExisting && !usedOutputPaths.contains(planned.path)
        usedOutputPaths.insert(planned.path)

        return try await Task.detached(priority: .userInitiated) {
            if Task.isCancelled { throw CancellationError() }
            let source = try CompanionImageIO.loadImage(at: sourceURL)

            switch operation {
            case .upscale(let scale, let contentMode, let engine):
                let target = CGSize(width: source.width * scale, height: source.height * scale)
                let resolved = UpscaleContentMode.resolved(contentMode, for: source)
                let output: CGImage
                if engine == .bestQuality && resolved != .textAndUI {
                    guard CoreMLModel.realESRGAN.isDownloaded else {
                        throw CompanionProcessingError.modelMissing("Install Best Quality first.")
                    }
                    let upscaler = CoreMLUpscaler(
                        modelProvider: PackageModelProvider(packageURL: CoreMLModel.realESRGAN.localPackageURL),
                        configuration: CoreMLUpscalerConfiguration(fixedInputSize: CGSize(width: 256, height: 256))
                    )
                    output = try await upscaler.upscale(source, to: target) { progress in
                        Task { @MainActor in
                            self.update(id: id, state: .processing(progress.detail, progress.fraction))
                        }
                    }
                } else {
                    let sharpening: CoreImageUpscaler.Sharpening = resolved == .textAndUI ? .textAndUI : .photoArtwork
                    let upscaler = CoreImageUpscaler(sharpening: sharpening)
                    output = try await upscaler.upscale(source, to: target) { progress in
                        Task { @MainActor in
                            self.update(id: id, state: .processing(progress.detail, progress.fraction))
                        }
                    }
                }
                let url = try CompanionImageIO.destinationURL(
                    for: sourceURL,
                    operationFolderName: folderName,
                    suffix: "-\(scale)x",
                    extension: sourceURL.preferredRasterExtension(defaultExtension: "png"),
                    customFolder: customDestinationURL,
                    overwriteOriginals: overwriteOriginals,
                    overwriteExisting: overwrite
                )
                try CompanionImageIO.writeImagePreservingPreferredFormat(output, to: url)
                return url

            case .cutout(let engine):
                let remover = try Self.backgroundRemover(for: engine, strength: strength)
                let output = try await remover.removeBackground(from: source) { progress in
                    Task { @MainActor in
                        self.update(id: id, state: .processing(progress.detail, progress.fraction))
                    }
                }
                let url = try CompanionImageIO.destinationURL(
                    for: sourceURL,
                    operationFolderName: folderName,
                    suffix: "-cutout",
                    extension: "png",
                    customFolder: customDestinationURL,
                    overwriteOriginals: overwriteOriginals,
                    overwriteExisting: overwrite
                )
                try CompanionImageIO.writePNG(output, to: url)
                return url
            }
        }.value
    }

    nonisolated static func backgroundRemover(
        for engine: CutoutEngine,
        strength: Double = 0.5
    ) throws -> BackgroundRemover {
        if engine == .flatBackground {
            // Strength reads the same way here as on a model mask: more removes more.
            // 0.5 lands on the 0.12 tolerance that suits a clean render.
            return FlatBackgroundRemover(tolerance: max(0.004, strength * 0.24))
        }
        guard engine == .bestQuality else { return VisionBackgroundRemover() }
        guard CoreMLModel.birefnet.isDownloaded else {
            throw CompanionProcessingError.modelMissing("Install Best Quality first.")
        }
        // BiRefNet is run on the CPU, where its output matches the reference implementation.
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        return CoreMLBackgroundRemover(
            modelProvider: PackageModelProvider(
                packageURL: CoreMLModel.birefnet.localPackageURL,
                configuration: configuration
            )
        )
    }

    /// Cuts out a single image with the current engine, for the editor — no queue,
    /// no file written.
    func makeCutout(from source: CGImage, strength: Double = 0.5) async throws -> CGImage {
        guard case .cutout(let engine)? = operation else {
            throw CompanionProcessingError.unreadableImage
        }
        let remover = try Self.backgroundRemover(for: engine, strength: strength)
        return try await Task.detached(priority: .userInitiated) {
            try await remover.removeBackground(from: source, progress: nil)
        }.value
    }

    /// Records a cutout the editor wrote, so the row shows the corrected result.
    func acceptEditedResult(id: BatchItem.ID, url: URL) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].state = .done(url)
        items[index].outputThumbnail = CompanionImageIO.thumbnail(at: url)
        refreshExistingResults()
    }

    private func update(id: BatchItem.ID, state: BatchItem.State) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].state = state
        if case .processing = state {
            items[index].outputThumbnail = nil
        }
    }
}

private extension URL {
    func conforms(to type: UTType) -> Bool {
        guard let contentType = try? resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return false
        }
        return contentType.conforms(to: type)
    }

    func preferredRasterExtension(defaultExtension: String) -> String {
        let value = pathExtension.lowercased()
        if ["jpg", "jpeg", "png"].contains(value) {
            return value == "jpg" ? "jpeg" : value
        }
        return defaultExtension
    }
}

private extension CompanionImageIO {
    static func writeImagePreservingPreferredFormat(_ image: CGImage, to url: URL) throws {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            try writeJPEG(image, to: url)
        default:
            try writePNG(image, to: url)
        }
    }
}
