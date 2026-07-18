import CoreML
import Foundation

/// Locates and loads a Core ML model, hiding the storage strategy from the
/// engines that consume it.
///
/// This is the seam that keeps the model-storage decision open. The engines
/// only need an `MLModel`; whether it was bundled in the app, downloaded into
/// Application Support, or delivered through On-Demand Resources / Background
/// Assets is entirely the provider's concern.
///
/// Not `Sendable`: it holds an `MLModelConfiguration` (a non-Sendable class).
/// The engines that use it are actors, which isolate it safely.
public protocol ModelProvider {
    /// Whether a usable model currently exists on disk. Cheap; does not load.
    var isAvailable: Bool { get }

    /// Loads (compiling first if necessary) and returns the model.
    func loadModel() async throws -> MLModel
}

public extension ModelProvider {
    /// Shared configuration: let Core ML pick the Neural Engine, GPU, or CPU.
    static var defaultConfiguration: MLModelConfiguration {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        return configuration
    }
}

/// Loads a model that Xcode already compiled into a bundle as an `.mlmodelc`.
///
/// Use this for the bundled / On-Demand Resources strategy. `name` is the model
/// file name without extension (e.g. `"RealESRGAN"`).
public struct BundledModelProvider: ModelProvider {
    private let name: String
    private let bundle: Bundle
    private let configuration: MLModelConfiguration

    public init(
        name: String,
        bundle: Bundle,
        configuration: MLModelConfiguration = BundledModelProvider.defaultConfiguration
    ) {
        self.name = name
        self.bundle = bundle
        self.configuration = configuration
    }

    private var compiledURL: URL? {
        bundle.url(forResource: name, withExtension: "mlmodelc")
    }

    public var isAvailable: Bool { compiledURL != nil }

    public func loadModel() async throws -> MLModel {
        guard let compiledURL else { throw InferenceError.modelUnavailable }
        do {
            return try MLModel(contentsOf: compiledURL, configuration: configuration)
        } catch {
            throw InferenceError.modelLoadFailed(error.localizedDescription)
        }
    }
}

/// Loads a model from an `.mlpackage` on disk, compiling it once to an
/// `.mlmodelc` kept next to it.
///
/// Use this for the runtime-download strategy: download the `.mlpackage` into
/// Application Support, point this provider at it, and the first load compiles
/// it on-device. Subsequent loads reuse the cached compiled copy.
public struct PackageModelProvider: ModelProvider {
    private let packageURL: URL
    private let compiledURL: URL
    private let configuration: MLModelConfiguration

    /// - Parameters:
    ///   - packageURL: location of the downloaded `.mlpackage`.
    ///   - compiledURL: where the compiled `.mlmodelc` should be cached. Defaults
    ///     to the package URL with an `.mlmodelc` extension.
    public init(
        packageURL: URL,
        compiledURL: URL? = nil,
        configuration: MLModelConfiguration = PackageModelProvider.defaultConfiguration
    ) {
        self.packageURL = packageURL
        self.compiledURL = compiledURL ?? packageURL.deletingPathExtension().appendingPathExtension("mlmodelc")
        self.configuration = configuration
    }

    public var isAvailable: Bool {
        FileManager.default.fileExists(atPath: packageURL.path)
    }

    public func loadModel() async throws -> MLModel {
        guard isAvailable else { throw InferenceError.modelUnavailable }

        let resolvedCompiledURL: URL
        if FileManager.default.fileExists(atPath: compiledURL.path) {
            resolvedCompiledURL = compiledURL
        } else {
            do {
                let freshlyCompiled = try await MLModel.compileModel(at: packageURL)
                if FileManager.default.fileExists(atPath: compiledURL.path) {
                    try FileManager.default.removeItem(at: compiledURL)
                }
                try FileManager.default.moveItem(at: freshlyCompiled, to: compiledURL)
                resolvedCompiledURL = compiledURL
            } catch {
                throw InferenceError.modelLoadFailed(error.localizedDescription)
            }
        }

        do {
            return try MLModel(contentsOf: resolvedCompiledURL, configuration: configuration)
        } catch {
            throw InferenceError.modelLoadFailed(error.localizedDescription)
        }
    }
}
