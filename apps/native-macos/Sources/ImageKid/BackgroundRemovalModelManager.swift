import Foundation

enum BackgroundRemovalModelConfiguration {
    static let modelFileName = "isnet-general-use.onnx"
    static let modelName = "isnet-general-use"
    static let modelURL = URL(string: "https://huggingface.co/fofr/comfyui/resolve/main/rembg/isnet-general-use.onnx")!

    static var modelsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("ImageKid", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("BackgroundRemoval", isDirectory: true)
    }

    static var runtimeDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("ImageKid", isDirectory: true)
            .appendingPathComponent("Runtime", isDirectory: true)
            .appendingPathComponent("rembg", isDirectory: true)
    }

    static var managedRembgExecutableURL: URL {
        runtimeDirectory
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("rembg")
    }
}

@MainActor
final class BackgroundRemovalModelManager: ObservableObject {
    @Published private(set) var isInstalling = false
    @Published private(set) var isInstallingRuntime = false
    @Published private(set) var errorMessage: String?

    var modelFileURL: URL {
        modelsDirectory.appendingPathComponent(BackgroundRemovalModelConfiguration.modelFileName)
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: modelFileURL.path)
    }

    var isRuntimeInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: BackgroundRemovalModelConfiguration.managedRembgExecutableURL.path)
    }

    var installedSizeLabel: String {
        guard
            let values = try? modelFileURL.resourceValues(forKeys: [.fileSizeKey]),
            let size = values.fileSize
        else {
            return "Not installed"
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }

    func install() {
        guard !isInstalling else { return }
        isInstalling = true
        errorMessage = nil

        Task {
            do {
                try FileManager.default.createDirectory(
                    at: modelsDirectory,
                    withIntermediateDirectories: true
                )

                let (temporaryURL, _) = try await URLSession.shared.download(from: BackgroundRemovalModelConfiguration.modelURL)
                if FileManager.default.fileExists(atPath: modelFileURL.path) {
                    try FileManager.default.removeItem(at: modelFileURL)
                }
                try FileManager.default.moveItem(at: temporaryURL, to: modelFileURL)
                objectWillChange.send()
            } catch {
                errorMessage = error.localizedDescription
            }

            isInstalling = false
        }
    }

    func installRuntime() {
        guard !isInstallingRuntime else { return }
        isInstallingRuntime = true
        errorMessage = nil

        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try installManagedRuntime()
                }.value
                objectWillChange.send()
            } catch {
                errorMessage = error.localizedDescription
            }

            isInstallingRuntime = false
        }
    }

    func remove() {
        do {
            if FileManager.default.fileExists(atPath: modelFileURL.path) {
                try FileManager.default.removeItem(at: modelFileURL)
            }
            objectWillChange.send()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeRuntime() {
        do {
            if FileManager.default.fileExists(atPath: BackgroundRemovalModelConfiguration.runtimeDirectory.path) {
                try FileManager.default.removeItem(at: BackgroundRemovalModelConfiguration.runtimeDirectory)
            }
            objectWillChange.send()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var modelsDirectory: URL { BackgroundRemovalModelConfiguration.modelsDirectory }
}

private func installManagedRuntime() throws {
    let runtimeDirectory = BackgroundRemovalModelConfiguration.runtimeDirectory
    let fileManager = FileManager.default
    try fileManager.createDirectory(
        at: runtimeDirectory.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )

    if fileManager.fileExists(atPath: runtimeDirectory.path) {
        try fileManager.removeItem(at: runtimeDirectory)
    }

    let pythonURL = try pythonExecutableURL()
    try run(pythonURL, arguments: ["-m", "venv", runtimeDirectory.path])

    let pipURL = runtimeDirectory
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("pip")
    try run(pipURL, arguments: ["install", "--upgrade", "pip"])
    try run(pipURL, arguments: ["install", "rembg[cpu,cli]"])
}

private func pythonExecutableURL() throws -> URL {
    let candidates = [
        "/opt/homebrew/bin/python3",
        "/usr/local/bin/python3",
        "/usr/bin/python3"
    ].map(URL.init(fileURLWithPath:))

    if let match = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
        return match
    }

    throw RuntimeInstallError.pythonMissing
}

private func run(_ executableURL: URL, arguments: [String]) throws {
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments

    let errorPipe = Pipe()
    process.standardError = errorPipe
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        throw RuntimeInstallError.commandFailed(message ?? "\(executableURL.lastPathComponent) exited with status \(process.terminationStatus).")
    }
}

private enum RuntimeInstallError: LocalizedError {
    case pythonMissing
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .pythonMissing:
            "ImageKid could not find python3 on this Mac. Install Python 3, then try again."
        case .commandFailed(let message):
            "Add-on setup failed: \(message)"
        }
    }
}
