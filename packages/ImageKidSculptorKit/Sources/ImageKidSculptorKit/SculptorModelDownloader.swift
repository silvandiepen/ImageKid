import Foundation

/// Downloads reconstruction weights into the shared App Group.
///
/// Same shape as ImageKid's existing `ModelDownloader` for the Core ML models,
/// with byte-level progress because Sculptor's weights are gigabytes rather
/// than megabytes and a spinner would be unacceptable.
///
/// The download is the *only* network access in Sculptor. Once weights are
/// installed, generation is entirely local and works offline.
@MainActor
public final class SculptorModelDownloader: NSObject, ObservableObject {
    public enum State: Equatable {
        case notDownloaded
        case downloading(received: Int64, expected: Int64)
        case installing
        case ready
        case failed(String)

        public var fraction: Double? {
            guard case .downloading(let received, let expected) = self, expected > 0 else {
                return nil
            }
            return Double(received) / Double(expected)
        }
    }

    @Published public private(set) var state: State

    private let model: SculptorModel
    private let baseURL: URL
    private var session: URLSession!
    private var remaining: [String] = []
    /// Remaining sources to try for the file currently downloading.
    private var sources: [URL] = []
    private var completedBytes: Int64 = 0
    private var totalExpectedBytes: Int64 = 0
    private var currentTask: URLSessionDownloadTask?

    public init(
        model: SculptorModel = .triposr,
        baseURL: URL = URL(string: "https://models-data.hakobs.com/v1")!
    ) {
        self.model = model
        self.baseURL = baseURL
        self.state = model.isInstalled ? .ready : .notDownloaded
        super.init()
        self.session = URLSession(
            configuration: .default, delegate: self, delegateQueue: nil
        )
    }

    public var isInstalled: Bool { model.isInstalled }

    public func download() {
        guard case .downloading = state else {
            beginDownload()
            return
        }
    }

    private func beginDownload() {
        guard !model.isInstalled else {
            state = .ready
            return
        }
        remaining = model.files
        completedBytes = 0
        totalExpectedBytes = 0
        state = .downloading(received: 0, expected: 0)
        startNext()
    }

    private func startNext() {
        guard let file = remaining.first else {
            finishInstall()
            return
        }
        sources = model.downloadSources(for: file, mirror: baseURL)
        startCurrentSource()
    }

    /// Tries the current file's next source. Falling through the list is what
    /// lets the install work before anything has been mirrored.
    private func startCurrentSource() {
        guard let url = sources.first else {
            failed("Could not download \(remaining.first ?? "the model").")
            return
        }
        let task = session.downloadTask(with: url)
        currentTask = task
        task.resume()
    }

    /// Moves to the next source for the current file, or fails if exhausted.
    fileprivate func tryNextSource(reason: String) {
        guard !sources.isEmpty else { return }
        sources.removeFirst()
        if sources.isEmpty {
            failed(reason)
        } else {
            startCurrentSource()
        }
    }

    private func finishInstall() {
        state = model.isInstalled ? .ready : .failed("The model did not install correctly.")
    }

    public func cancel() {
        currentTask?.cancel()
        currentTask = nil
        remaining.removeAll()
        state = model.isInstalled ? .ready : .notDownloaded
    }

    /// Removes the weights. Generated models the user has exported are theirs
    /// and are never touched by this.
    public func remove() {
        try? FileManager.default.removeItem(at: model.directory)
        state = .notDownloaded
    }

    fileprivate func handle(location: URL, for task: URLSessionDownloadTask) {
        guard let file = remaining.first else { return }

        // A 404 still arrives here, with the error page as the body. Saving it
        // would leave a "model" that reads as installed and fails at load time,
        // so anything but success falls through to the next source.
        if let http = task.response as? HTTPURLResponse, http.statusCode != 200 {
            try? FileManager.default.removeItem(at: location)
            tryNextSource(
                reason: "\(file) is not available (HTTP \(http.statusCode))."
            )
            return
        }

        let destination = model.directory.appendingPathComponent(file)
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: model.directory, withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            // Must move synchronously: the temporary file is deleted as soon as
            // the delegate callback returns.
            try fileManager.moveItem(at: location, to: destination)
        } catch {
            failed(error.localizedDescription)
            return
        }
        completedBytes += task.countOfBytesReceived
        remaining.removeFirst()
        sources.removeAll()
        startNext()
    }

    fileprivate func failed(_ message: String) {
        // Leave no half-written weights behind; a partial model would read as
        // installed and fail confusingly at load time.
        try? FileManager.default.removeItem(at: model.directory)
        remaining.removeAll()
        currentTask = nil
        state = .failed(message)
    }

    fileprivate func progressed(received: Int64, expectedForTask: Int64) {
        let expected = totalExpectedBytes > 0
            ? totalExpectedBytes
            : completedBytes + max(expectedForTask, 0)
        state = .downloading(received: completedBytes + received, expected: expected)
    }
}

extension SculptorModelDownloader: URLSessionDownloadDelegate {
    nonisolated public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The temporary file dies when this returns, so move it here rather
        // than hopping to the main actor first.
        let fileManager = FileManager.default
        let staged = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? fileManager.moveItem(at: location, to: staged)
        Task { @MainActor in
            self.handle(location: staged, for: downloadTask)
        }
    }

    nonisolated public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        Task { @MainActor in
            self.progressed(
                received: totalBytesWritten, expectedForTask: totalBytesExpectedToWrite
            )
        }
    }

    nonisolated public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        let isCancellation = (error as NSError).code == NSURLErrorCancelled
        let description = error.localizedDescription
        Task { @MainActor in
            guard !isCancellation else { return }
            // A transport failure on one source is not fatal while others
            // remain — the mirror may be unreachable when upstream is fine.
            self.tryNextSource(reason: description)
        }
    }
}
