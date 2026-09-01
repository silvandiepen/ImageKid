import Darwin
import Foundation

/// Watches one folder (not its descendants) and turns its filesystem events into
/// batches of changed images. A short debounce lets Finder, cameras and browsers
/// finish copying a file before Core Graphics tries to open it.
@MainActor
final class FolderWatchController {
    typealias ProcessFiles = ([URL]) async -> Void

    private let folder: URL
    private let processFiles: ProcessFiles
    private let queue = DispatchQueue(label: "com.hakobs.imagekid.cutout.watch")
    private var source: DispatchSourceFileSystemObject?
    private var pendingScan: DispatchWorkItem?
    private var observed: [URL: ImageFileSignature] = [:]

    init(folder: URL, processFiles: @escaping ProcessFiles) throws {
        self.folder = folder.standardizedFileURL
        self.processFiles = processFiles
        guard self.folder.isExistingDirectory else {
            throw ArgumentError.watchFolderNotDirectory(folder)
        }
    }

    func run() async {
        installSource()
        scheduleScan(after: 0)
        await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
    }

    deinit {
        pendingScan?.cancel()
        source?.cancel()
    }

    private func installSource() {
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .extend, .attrib],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.scheduleScan(after: 0.75) }
        }
        source.setCancelHandler { close(descriptor) }
        self.source = source
        source.resume()
    }

    private func scheduleScan(after delay: TimeInterval) {
        pendingScan?.cancel()
        let scan = DispatchWorkItem { [weak self] in
            Task { @MainActor in await self?.scan() }
        }
        pendingScan = scan
        queue.asyncAfter(deadline: .now() + delay, execute: scan)
    }

    private func scan() async {
        let current = ImageFolderScanner.images(in: folder)
        var changed: [URL] = []
        var latest: [URL: ImageFileSignature] = [:]

        for url in current {
            guard let signature = ImageFileSignature(url: url) else { continue }
            latest[url] = signature
            if observed[url] != signature {
                changed.append(url)
            }
        }
        observed = latest

        guard !changed.isEmpty else { return }
        await processFiles(changed)
    }
}

struct ImageFileSignature: Equatable {
    let modificationDate: Date
    let byteCount: Int

    init?(url: URL) {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let modificationDate = values.contentModificationDate,
              let byteCount = values.fileSize else {
            return nil
        }
        self.modificationDate = modificationDate
        self.byteCount = byteCount
    }
}

enum ImageFolderScanner {
    static func images(in folder: URL, fileManager: FileManager = .default) -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isHiddenKey]
        let urls = (try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls.filter { url in
            guard
                let values = try? url.resourceValues(forKeys: keys),
                values.isRegularFile == true
            else { return false }
            return ImageFile.extensions.contains(url.pathExtension.lowercased())
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
