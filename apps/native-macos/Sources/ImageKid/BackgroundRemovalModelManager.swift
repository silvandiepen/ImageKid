import CryptoKit
import Foundation

enum BackgroundRemovalModelConfiguration {
    static let modelFileName = "isnet-general-use.onnx"
    static let modelName = "isnet-general-use"
    static let modelURL = URL(string: "https://huggingface.co/fofr/comfyui/resolve/main/rembg/isnet-general-use.onnx")!
    static let modelByteCount = 178_648_008
    static let modelSHA256 = "60920e99c45464f2ba57bee2ad08c919a52bbf852739e96947fbb4358c0d964a"
    static let rembgVersion = "2.0.76"
    static let runtimeManifestFileName = "imagekid-runtime-manifest.txt"
    static var rembgPackageRequirement: String { "rembg[cpu,cli]==\(rembgVersion)" }

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

    static var runtimeManifestURL: URL {
        runtimeDirectory.appendingPathComponent(runtimeManifestFileName)
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
        (try? BackgroundRemovalAssetVerifier.validateModel(at: modelFileURL)) != nil
    }

    var isRuntimeInstalled: Bool {
        BackgroundRemovalAssetVerifier.isManagedRuntimeInstalled
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
                let fileManager = FileManager.default
                try fileManager.createDirectory(
                    at: modelsDirectory,
                    withIntermediateDirectories: true
                )

                let (temporaryURL, _) = try await URLSession.shared.download(from: BackgroundRemovalModelConfiguration.modelURL)
                try BackgroundRemovalAssetVerifier.validateModel(at: temporaryURL)

                let stagedURL = modelsDirectory
                    .appendingPathComponent("\(BackgroundRemovalModelConfiguration.modelFileName).installing-\(UUID().uuidString)")
                try fileManager.moveItem(at: temporaryURL, to: stagedURL)
                try BackgroundRemovalAssetVerifier.validateModel(at: stagedURL)
                if fileManager.fileExists(atPath: modelFileURL.path) {
                    _ = try fileManager.replaceItemAt(modelFileURL, withItemAt: stagedURL)
                } else {
                    try fileManager.moveItem(at: stagedURL, to: modelFileURL)
                }
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

enum BackgroundRemovalAssetVerifier {
    static var isManagedRuntimeInstalled: Bool {
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: BackgroundRemovalModelConfiguration.managedRembgExecutableURL.path),
              let manifest = try? String(
                contentsOf: BackgroundRemovalModelConfiguration.runtimeManifestURL,
                encoding: .utf8
              )
        else {
            return false
        }
        return manifest.contains("rembg=\(BackgroundRemovalModelConfiguration.rembgVersion)")
            && manifest.contains("model-sha256=\(BackgroundRemovalModelConfiguration.modelSHA256)")
    }

    static func validateModel(at url: URL) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard values.fileSize == BackgroundRemovalModelConfiguration.modelByteCount else {
            throw RuntimeInstallError.integrityFailed("The background model has an unexpected size.")
        }

        let hash = try sha256Hex(for: url)
        guard hash == BackgroundRemovalModelConfiguration.modelSHA256 else {
            throw RuntimeInstallError.integrityFailed("The background model did not match ImageKid's approved copy.")
        }
    }

    static func sha256Hex(for url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
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
    try run(pipURL, arguments: [
        "install",
        "--no-cache-dir",
        "--only-binary=:all:",
        BackgroundRemovalModelConfiguration.rembgPackageRequirement
    ])

    let manifest = """
    rembg=\(BackgroundRemovalModelConfiguration.rembgVersion)
    model=\(BackgroundRemovalModelConfiguration.modelName)
    model-sha256=\(BackgroundRemovalModelConfiguration.modelSHA256)
    """
    try manifest.write(to: BackgroundRemovalModelConfiguration.runtimeManifestURL, atomically: true, encoding: .utf8)
    guard BackgroundRemovalAssetVerifier.isManagedRuntimeInstalled else {
        throw RuntimeInstallError.integrityFailed("The managed add-on could not be verified after setup.")
    }
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
    case integrityFailed(String)

    var errorDescription: String? {
        switch self {
        case .pythonMissing:
            "ImageKid could not find python3 on this Mac. Install Python 3, then try again."
        case .commandFailed(let message):
            "Add-on setup failed: \(message)"
        case .integrityFailed(let message):
            "Add-on setup failed: \(message)"
        }
    }
}
