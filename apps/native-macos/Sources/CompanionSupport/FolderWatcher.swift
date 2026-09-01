import Darwin
import Foundation
import UniformTypeIdentifiers

/// A lightweight, non-recursive inbox watcher. Filesystem events are intentionally
/// debounced: Finder copies, cameras and browsers commonly announce a new file before
/// its final bytes are on disk.
@MainActor
final class FolderWatcher {
    private let folder: URL
    private let handler: ([URL]) -> Void
    private let queue = DispatchQueue(label: "com.hakobs.imagekid.folder-watcher")
    private var source: DispatchSourceFileSystemObject?
    private var pendingScan: DispatchWorkItem?
    private var observed: [URL: FileSignature] = [:]

    init(folder: URL, handler: @escaping ([URL]) -> Void) {
        self.folder = folder.standardizedFileURL
        self.handler = handler
    }

    func start() {
        guard source == nil else { return }
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
        scheduleScan(after: 0)
    }

    func stop() {
        pendingScan?.cancel()
        pendingScan = nil
        source?.cancel()
        source = nil
        observed = [:]
    }

    deinit {
        pendingScan?.cancel()
        source?.cancel()
    }

    private func scheduleScan(after delay: TimeInterval) {
        pendingScan?.cancel()
        let scan = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.scan() }
        }
        pendingScan = scan
        queue.asyncAfter(deadline: .now() + delay, execute: scan)
    }

    private func scan() {
        let files = FolderWatchScanner.images(in: folder)
        var latest: [URL: FileSignature] = [:]
        var changed: [URL] = []

        for file in files {
            guard let signature = FileSignature(file: file) else { continue }
            latest[file] = signature
            if observed[file] != signature {
                changed.append(file)
            }
        }
        observed = latest

        if !changed.isEmpty {
            handler(changed)
        }
    }
}

struct FileSignature: Equatable {
    let modificationDate: Date
    let byteCount: Int

    init?(file: URL) {
        guard
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
            let modificationDate = values.contentModificationDate,
            let byteCount = values.fileSize
        else {
            return nil
        }
        self.modificationDate = modificationDate
        self.byteCount = byteCount
    }
}

enum FolderWatchScanner {
    static func images(in folder: URL, fileManager: FileManager = .default) -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isHiddenKey, .contentTypeKey]
        let files = (try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )) ?? []

        return files.filter { file in
            guard
                let values = try? file.resourceValues(forKeys: keys),
                values.isRegularFile == true,
                let contentType = values.contentType
            else { return false }
            return CompanionImageIO.readableTypes.contains(where: contentType.conforms(to:))
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
