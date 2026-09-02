import Foundation

/// Something that happened while a generation was running.
public enum SculptorEvent: Sendable {
    case progress(ProgressMessage)
    case finished(ResultMessage)
}

/// Failures raised by the bridge itself, as opposed to those the worker reports.
public enum SculptorWorkerError: LocalizedError, Equatable {
    case workerNotFound(String)
    case workerFailedToStart(String)
    case workerStopped
    case engineUnavailable(String)
    case reported(SculptorErrorCode, String, recoverable: Bool)

    public var errorDescription: String? {
        switch self {
        case .workerNotFound(let detail):
            "The reconstruction engine could not be located. \(detail)"
        case .workerFailedToStart(let detail):
            "The reconstruction engine could not be started. \(detail)"
        case .workerStopped:
            "The reconstruction engine stopped unexpectedly."
        case .engineUnavailable(let detail):
            detail
        case .reported(_, let message, _):
            message
        }
    }

    /// Whether the user can retry without re-importing the source image.
    public var isRecoverable: Bool {
        switch self {
        case .reported(_, _, let recoverable): recoverable
        case .engineUnavailable, .workerStopped: true
        case .workerNotFound, .workerFailedToStart: false
        }
    }
}

/// Drives the local reconstruction worker over its line protocol.
///
/// One worker process is kept alive for the life of the app: loading model
/// weights costs far more than running a generation. The process is a hard
/// boundary — a crash inside PyTorch takes down the worker, not the UI, and
/// terminating it reclaims all GPU memory at once.
public actor SculptorWorker {
    private let executable: URL
    private let arguments: [String]
    private let environment: [String: String]?

    private var process: Process?
    private var standardInput: FileHandle?

    private var ready: ReadyMessage?
    private var readyWaiters: [CheckedContinuation<ReadyMessage, Error>] = []

    /// Continuations for the job currently running, keyed by job id.
    private var activeJobs: [String: AsyncThrowingStream<SculptorEvent, Error>.Continuation] = [:]

    /// Waiters for in-flight analyse requests, keyed by request id.
    private var analyses: [String: CheckedContinuation<AnalysisMessage, Error>] = [:]

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(launch: WorkerLaunchConfiguration) {
        self.executable = launch.executable
        self.arguments = launch.arguments
        self.environment = launch.environment
    }

    // MARK: - Lifecycle

    /// Starts the worker and waits for its `ready` line.
    @discardableResult
    public func start() async throws -> ReadyMessage {
        if let ready { return ready }
        if process == nil { try launch() }

        return try await withCheckedThrowingContinuation { continuation in
            if let ready {
                continuation.resume(returning: ready)
            } else {
                readyWaiters.append(continuation)
            }
        }
    }

    private func launch() throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        // stderr is the worker's diagnostic channel and must never be merged
        // into stdout, which carries the protocol.
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw SculptorWorkerError.workerFailedToStart(error.localizedDescription)
        }

        self.process = process
        self.standardInput = inputPipe.fileHandleForWriting

        // `readabilityHandler` rather than `FileHandle.bytes.lines`: the async
        // sequence blocks a cooperative-pool thread per handle for the life of
        // the pipe, and with one reader on stdout and another on stderr that
        // starves the executor and the worker never appears to answer.
        installProtocolReader(on: outputPipe.fileHandleForReading)
        installDiagnosticsDrain(on: errorPipe.fileHandleForReading)
    }

    /// Reassembles newline-delimited lines from arbitrary pipe chunks.
    ///
    /// `readabilityHandler` fires on a queue outside the actor and may do so
    /// concurrently, so the partial line is guarded rather than captured.
    private final class LineBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()

        /// Appends a chunk and returns whatever complete lines it completed.
        func take(_ chunk: Data) -> [Data] {
            lock.lock()
            defer { lock.unlock() }
            buffer.append(chunk)
            var lines: [Data] = []
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer = Data(buffer[buffer.index(after: newline)...])
                if !line.isEmpty { lines.append(Data(line)) }
            }
            return lines
        }
    }

    private func installProtocolReader(on handle: FileHandle) {
        let lines = LineBuffer()
        handle.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                Task { await self?.handleWorkerExit() }
                return
            }
            for line in lines.take(chunk) {
                Task { await self?.receive(line) }
            }
        }
    }

    /// Drains stderr so the pipe cannot fill and block the worker.
    ///
    /// A worker that blocks writing diagnostics stops emitting protocol lines
    /// too, so this drain is load-bearing even when nothing reads the output.
    private func installDiagnosticsDrain(on handle: FileHandle) {
        handle.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            #if DEBUG
            FileHandle.standardError.write(chunk)
            #endif
        }
    }

    /// Decodes one protocol line and routes it.
    ///
    /// Undecodable lines are dropped rather than fatal: a newer worker paired
    /// with an older app should degrade, not die.
    private func receive(_ line: Data) {
        guard let message = try? WorkerMessage.decode(line, using: decoder) else { return }
        dispatch(message)
    }

    private func dispatch(_ message: WorkerMessage) {
        switch message {
        case .ready(let ready):
            self.ready = ready
            let waiters = readyWaiters
            readyWaiters.removeAll()
            for waiter in waiters { waiter.resume(returning: ready) }

        case .progress(let progress):
            activeJobs[progress.jobId]?.yield(.progress(progress))

        case .result(let result):
            guard let continuation = activeJobs.removeValue(forKey: result.jobId) else { return }
            continuation.yield(.finished(result))
            continuation.finish()

        case .analysis(let analysis):
            analyses.removeValue(forKey: analysis.requestId)?.resume(returning: analysis)

        case .failure(let failure):
            let error = SculptorWorkerError.reported(
                failure.code, failure.message, recoverable: failure.recoverable
            )
            // Errors from an analyse carry no job id, and neither does a
            // malformed request. Fail any waiting analysis first, then jobs,
            // rather than leaving either hanging forever.
            guard let jobId = failure.jobId else {
                if !analyses.isEmpty {
                    let waiting = analyses
                    analyses.removeAll()
                    for (_, continuation) in waiting { continuation.resume(throwing: error) }
                    return
                }
                failAllJobs(with: error)
                return
            }
            activeJobs.removeValue(forKey: jobId)?.finish(throwing: error)
        }
    }

    private func handleWorkerExit() {
        let waiters = readyWaiters
        readyWaiters.removeAll()
        for waiter in waiters { waiter.resume(throwing: SculptorWorkerError.workerStopped) }

        failAllJobs(with: SculptorWorkerError.workerStopped)
        process = nil
        standardInput = nil
        ready = nil
    }

    private func failAllJobs(with error: Error) {
        let jobs = activeJobs
        activeJobs.removeAll()
        for (_, continuation) in jobs { continuation.finish(throwing: error) }

        let waiting = analyses
        analyses.removeAll()
        for (_, continuation) in waiting { continuation.resume(throwing: error) }
    }

    /// Stops the worker. Safe to call more than once.
    public func shutdown() {
        send(["type": "shutdown"])
        process?.terminate()
        process = nil
        standardInput = nil
        ready = nil
        failAllJobs(with: SculptorWorkerError.workerStopped)
    }

    // MARK: - Jobs

    /// Runs one generation, streaming progress until a result or an error.
    public func generate(_ request: GenerateRequest) -> AsyncThrowingStream<SculptorEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let ready = try await self.start()
                    guard ready.engineAvailable else {
                        throw SculptorWorkerError.engineUnavailable(
                            ready.detail ?? "The 3D model is not installed."
                        )
                    }
                    self.register(request.jobId, continuation: continuation)
                    try self.write(request)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func register(
        _ jobId: String,
        continuation: AsyncThrowingStream<SculptorEvent, Error>.Continuation
    ) {
        activeJobs[jobId] = continuation
    }

    /// Rates a source image without reconstructing it.
    ///
    /// Answered on the worker's reader thread, so it returns promptly even
    /// while a generation is running.
    public func analyse(_ request: AnalyseRequest) async throws -> AnalysisMessage {
        let ready = try await start()
        // Analysis is engine-free, so an uninstalled model must not block it —
        // knowing an image is a poor candidate is most useful *before* the
        // user has gone and downloaded gigabytes of weights.
        _ = ready

        let data = try encoder.encode(request)
        return try await withCheckedThrowingContinuation { continuation in
            analyses[request.requestId] = continuation
            writeLine(data)
        }
    }

    /// Asks the worker to stop a job. Cancellation lands at the next stage
    /// boundary; the forward pass itself is not interruptible.
    public func cancel(jobId: String) {
        send(["type": "cancel", "jobId": jobId])
    }

    // MARK: - Writing

    private func write(_ request: GenerateRequest) throws {
        let data = try encoder.encode(request)
        writeLine(data)
    }

    private func send(_ payload: [String: String]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        writeLine(data)
    }

    private func writeLine(_ data: Data) {
        guard let standardInput else { return }
        var line = data
        line.append(0x0A)
        try? standardInput.write(contentsOf: line)
    }
}
