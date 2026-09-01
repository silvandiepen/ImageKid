import CoreML
import Foundation
import ImageKidInference

@main
struct Cutout {
    static let version = "0.1.0"

    static func main() async {
        let rawArguments = Array(CommandLine.arguments.dropFirst())

        let arguments: Arguments
        do {
            arguments = try Arguments.parse(rawArguments)
        } catch ArgumentError.showHelp {
            print(Arguments.usage)
            exit(0)
        } catch ArgumentError.showVersion {
            print("cutout \(version)")
            exit(0)
        } catch {
            fail(error.localizedDescription)
        }

        do {
            let remover = try makeRemover(for: arguments.quality, strength: arguments.strength)
            if let folder = arguments.watchFolder {
                try await watch(folder: folder, arguments: arguments, remover: remover)
                return
            }
            let failures = await run(arguments, remover: remover)
            exit(failures == 0 ? 0 : 2)
        } catch {
            fail(error.localizedDescription)
        }
    }

    static func run(_ arguments: Arguments, remover: BackgroundRemover) async -> Int {
        var failures = 0

        for input in arguments.inputs {
            let output = outputURL(for: input, arguments: arguments)

            if FileManager.default.fileExists(atPath: output.path) && !arguments.force {
                report(input, problem: "\(output.path) already exists. Use --force to overwrite.")
                failures += 1
                continue
            }

            do {
                let source = try ImageFile.read(input)
                let result = try await remover.removeBackground(from: source, progress: nil)
                try ImageFile.writePNG(result, to: output)
                print("\(input.lastPathComponent) → \(output.path)")
            } catch {
                report(input, problem: error.localizedDescription)
                failures += 1
            }
        }

        if failures > 0 {
            let total = arguments.inputs.count
            FileHandle.standardError.write(Data("\(failures) of \(total) images failed.\n".utf8))
        }
        return failures
    }

    @MainActor
    private static func watch(
        folder: URL,
        arguments: Arguments,
        remover: BackgroundRemover
    ) async throws {
        let watcher = try FolderWatchController(folder: folder) { files in
            var runArguments = arguments
            runArguments.inputs = files
            let failures = await run(runArguments, remover: remover)
            if failures == 0 {
                print("Watching \(folder.path) — waiting for images…")
            }
        }
        print("Watching \(folder.path) → \(arguments.destination.path)")
        await watcher.run()
    }

    private static func makeRemover(for quality: Quality, strength: Double) throws -> BackgroundRemover {
        switch quality {
        case .fast:
            return VisionBackgroundRemover()
        case .flat:
            return FlatBackgroundRemover(tolerance: max(0.004, strength * 0.24))
        case .best:
            guard let package = ModelCatalog.birefnetPackageURL() else {
                throw CutoutError.bestQualityNotInstalled
            }
            // Mirrors the Cutout app: BiRefNet is run on the CPU, where its output
            // matches the reference implementation.
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuOnly
            return CoreMLBackgroundRemover(
                modelProvider: PackageModelProvider(packageURL: package, configuration: configuration)
            )
        }
    }

    private static func outputURL(for input: URL, arguments: Arguments) -> URL {
        guard arguments.destinationIsDirectory else { return arguments.destination }
        let name = input.deletingPathExtension().lastPathComponent
        return arguments.destination.appendingPathComponent(name).appendingPathExtension("png")
    }

    private static func report(_ input: URL, problem: String) {
        FileHandle.standardError.write(Data("\(input.lastPathComponent): \(problem)\n".utf8))
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        exit(1)
    }
}

enum CutoutError: LocalizedError {
    case bestQualityNotInstalled

    var errorDescription: String? {
        switch self {
        case .bestQualityNotInstalled:
            return """
            Best Quality is not installed. Open Cutout, pick Best Quality, and press \
            Install — cutout reads the same local model cache.
            """
        }
    }
}
