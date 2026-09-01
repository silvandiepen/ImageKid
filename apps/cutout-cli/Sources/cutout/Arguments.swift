import Foundation

enum Quality: String {
    case fast
    case best
    case flat

    init?(argument: String) {
        switch argument.lowercased() {
        case "fast", "builtin", "built-in", "vision": self = .fast
        case "best", "bestquality", "best-quality": self = .best
        case "flat", "backdrop", "flat-background": self = .flat
        default: return nil
        }
    }
}

struct Arguments {
    var inputs: [URL]
    /// A folder to monitor continuously. When set, `inputs` is intentionally empty
    /// until the watcher discovers a compatible image.
    var watchFolder: URL?
    var destination: URL
    /// True when `destination` names a folder to write into rather than a file to write.
    var destinationIsDirectory: Bool
    var quality: Quality
    var strength: Double
    var force: Bool

    static let usage = """
    cutout — remove image backgrounds locally, on this Mac.

    USAGE
      cutout <input>... <destination> [options]

    EXAMPLES
      cutout photo.jpg cutouts/photo.png
      cutout shots/*.jpg cutouts/ --quality=best
      cutout watch inbox/ cutouts/ --quality=best

    OPTIONS
      -q, --quality <fast|best|flat>
                                  fast uses Apple Vision and needs no download.
                                  best uses the BiRefNet Core ML model installed by
                                  Cutout. flat keys out a single flat backdrop, which
                                  suits renders and product shots. Default: fast.
      -s, --strength <0-1>        How much the flat backdrop takes. Default 0.5.
      -f, --force                 Overwrite an existing output file.
      -h, --help                  Show this help.
      -v, --version               Show the version.

    WATCH
      `cutout watch <folder> <destination>` processes compatible images already in
      the folder and then keeps running for new or changed images. It watches that
      folder only, not its subfolders. Choose a different destination folder so a
      generated PNG is never treated as a new input.

    The destination is a folder when it already exists as one or ends with "/";
    outputs are then written as <name>.png inside it. A single input may instead be
    given an explicit output file path. Cutouts are always PNG, so transparency is real.
    """
}

enum ArgumentError: LocalizedError {
    case showHelp
    case showVersion
    case unknownOption(String)
    case missingQuality
    case invalidQuality(String)
    case notEnoughArguments
    case multipleInputsNeedFolder
    case missingInput(URL)
    case watchNeedsFolderAndDestination
    case watchFolderNotDirectory(URL)
    case watchDestinationIsSourceFolder

    var errorDescription: String? {
        switch self {
        case .showHelp, .showVersion:
            return nil
        case .unknownOption(let option):
            return "Unknown option \(option). Run cutout --help."
        case .missingQuality:
            return "--quality needs a value: fast or best."
        case .invalidQuality(let value):
            return "\(value) is not a quality. Use fast or best."
        case .notEnoughArguments:
            return "Give at least one input image and a destination. Run cutout --help."
        case .multipleInputsNeedFolder:
            return "Several inputs need a destination folder, not a file path."
        case .missingInput(let url):
            return "No such file: \(url.path)"
        case .watchNeedsFolderAndDestination:
            return "Watch needs a folder and a destination. Try: cutout watch inbox/ cutouts/"
        case .watchFolderNotDirectory(let url):
            return "Watch folder is not a readable folder: \(url.path)"
        case .watchDestinationIsSourceFolder:
            return "The watch destination must be different from the watch folder."
        }
    }
}

extension Arguments {
    static func parse(_ rawArguments: [String]) throws -> Arguments {
        var positionals: [String] = []
        var quality = Quality.fast
        var strength = 0.5
        var force = false

        var index = 0
        while index < rawArguments.count {
            let argument = rawArguments[index]
            index += 1

            switch argument {
            case "-h", "--help":
                throw ArgumentError.showHelp
            case "-v", "--version":
                throw ArgumentError.showVersion
            case "-f", "--force":
                force = true
            case "-s", "--strength":
                guard index < rawArguments.count, let value = Double(rawArguments[index]) else {
                    throw ArgumentError.missingQuality
                }
                index += 1
                strength = min(1, max(0, value))
            case "-q", "--q", "--quality":
                guard index < rawArguments.count else { throw ArgumentError.missingQuality }
                let value = rawArguments[index]
                index += 1
                guard let parsed = Quality(argument: value) else {
                    throw ArgumentError.invalidQuality(value)
                }
                quality = parsed
            default:
                if let value = argument.optionValue(forAnyOf: ["--strength", "-s"]),
                   let number = Double(value) {
                    strength = min(1, max(0, number))
                } else if let value = argument.optionValue(forAnyOf: ["--quality", "--q", "-q"]) {
                    guard let parsed = Quality(argument: value) else {
                        throw ArgumentError.invalidQuality(value)
                    }
                    quality = parsed
                } else if argument.hasPrefix("-") && argument != "-" {
                    throw ArgumentError.unknownOption(argument)
                } else {
                    positionals.append(argument)
                }
            }
        }

        if positionals.first == "watch" {
            positionals.removeFirst()
            guard positionals.count == 2 else { throw ArgumentError.watchNeedsFolderAndDestination }

            let watchFolder = URL(fileURLWithPath: positionals[0]).standardizedFileURL
            guard watchFolder.isExistingDirectory else {
                throw ArgumentError.watchFolderNotDirectory(watchFolder)
            }

            let destination = URL(fileURLWithPath: positionals[1]).standardizedFileURL
            guard destination.standardizedFileURL != watchFolder else {
                throw ArgumentError.watchDestinationIsSourceFolder
            }
            return Arguments(
                inputs: [],
                watchFolder: watchFolder,
                destination: destination,
                destinationIsDirectory: true,
                quality: quality,
                strength: strength,
                force: force
            )
        }

        guard positionals.count >= 2 else { throw ArgumentError.notEnoughArguments }

        let destinationArgument = positionals.removeLast()
        let inputs = positionals.map { URL(fileURLWithPath: $0).standardizedFileURL }
        for input in inputs where !FileManager.default.isReadableFile(atPath: input.path) {
            throw ArgumentError.missingInput(input)
        }

        let destination = URL(fileURLWithPath: destinationArgument).standardizedFileURL
        let isDirectory = destinationArgument.hasSuffix("/")
            || destination.isExistingDirectory
            || destination.pathExtension.isEmpty

        if !isDirectory && inputs.count > 1 {
            throw ArgumentError.multipleInputsNeedFolder
        }

        return Arguments(
            inputs: inputs,
            watchFolder: nil,
            destination: destination,
            destinationIsDirectory: isDirectory,
            quality: quality,
            strength: strength,
            force: force
        )
    }
}

private extension String {
    /// Reads `--quality=best` / `--q=best` style options, which is how the flag is
    /// most often typed even though the space-separated form also works.
    func optionValue(forAnyOf names: [String]) -> String? {
        for name in names where hasPrefix(name + "=") {
            return String(dropFirst(name.count + 1))
        }
        return nil
    }
}

extension URL {
    var isExistingDirectory: Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}
