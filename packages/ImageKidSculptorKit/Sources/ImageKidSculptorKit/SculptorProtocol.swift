import Foundation

/// The wire protocol shared with `tools/sculptor-engine`.
///
/// One JSON object per line in each direction. The Python side emits camelCase
/// keys deliberately so these types decode with a plain `JSONDecoder` and no key
/// strategy — if you add a case here, add it there too.

// MARK: - Requests (app -> worker)

/// Per-job knobs. None are exposed in the normal UI; they exist so the engine
/// spike and tests can drive the worker deterministically.
public struct SculptorOptions: Codable, Equatable, Sendable {
    public var cropPadding: Double?
    public var inputSize: Int?
    public var fragmentThreshold: Double?
    public var normaliseScale: Bool?
    /// Degrees of pitch undoing the source camera's elevation. See
    /// ``SourceViewpoint``.
    public var pitchCorrection: Double?
    public var alignGround: Bool?
    public var seed: Int?
    public var device: String?
    public var lowMemory: Bool?

    public init(
        cropPadding: Double? = nil,
        inputSize: Int? = nil,
        fragmentThreshold: Double? = nil,
        normaliseScale: Bool? = nil,
        pitchCorrection: Double? = nil,
        alignGround: Bool? = nil,
        seed: Int? = nil,
        device: String? = nil,
        lowMemory: Bool? = nil
    ) {
        self.cropPadding = cropPadding
        self.inputSize = inputSize
        self.fragmentThreshold = fragmentThreshold
        self.normaliseScale = normaliseScale
        self.pitchCorrection = pitchCorrection
        self.alignGround = alignGround
        self.seed = seed
        self.device = device
        self.lowMemory = lowMemory
    }
}

/// Where the source image was seen from.
///
/// Reconstruction happens in the input camera's frame, so an image shot or
/// rendered from above produces a model tilted back by that elevation. This is
/// the one thing about the source the app cannot infer reliably, and getting it
/// wrong lays the object on its side, so it is worth asking.
///
/// Measured across the Tiko Media catalogue: those isometric renders need -60°.
public enum SourceViewpoint: String, CaseIterable, Identifiable, Sendable {
    case eyeLevel
    case raised
    case overhead

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .eyeLevel: "Eye level"
        case .raised: "Slightly above"
        case .overhead: "Isometric or from above"
        }
    }

    public var detail: String {
        switch self {
        case .eyeLevel: "A photo taken level with the object."
        case .raised: "Looking down a little, as most product shots do."
        case .overhead: "A steep three-quarter view, like a game or map asset."
        }
    }

    public var pitchCorrection: Double {
        switch self {
        case .eyeLevel: 0
        case .raised: -30
        case .overhead: -60
        }
    }
}

public struct GenerateRequest: Codable, Equatable, Sendable {
    public let type = "generate"
    public let jobId: String
    public let sourcePath: String
    public let workspace: String
    public let maskPath: String?
    public let options: SculptorOptions?

    private enum CodingKeys: String, CodingKey {
        case type, jobId, sourcePath, workspace, maskPath, options
    }

    public init(
        jobId: String,
        sourcePath: String,
        workspace: String,
        maskPath: String? = nil,
        options: SculptorOptions? = nil
    ) {
        self.jobId = jobId
        self.sourcePath = sourcePath
        self.workspace = workspace
        self.maskPath = maskPath
        self.options = options
    }
}

// MARK: - Responses (worker -> app)

/// User-facing progress stages, in the order the worker visits them.
public enum SculptorStage: String, Codable, CaseIterable, Sendable {
    case preparingImage
    case isolatingObject
    case reconstructing
    case buildingHiddenSides
    case cleaningModel
    case preparingPreview

    /// Copy for the processing state. Describes what the user is waiting for
    /// rather than naming any engine internals.
    public var title: String {
        switch self {
        case .preparingImage: "Preparing image"
        case .isolatingObject: "Isolating object"
        case .reconstructing: "Reconstructing 3D"
        case .buildingHiddenSides: "Building hidden sides"
        case .cleaningModel: "Cleaning model"
        case .preparingPreview: "Preparing preview"
        }
    }
}

/// Failures the worker classifies. The app owns the copy.
public enum SculptorErrorCode: String, Codable, Sendable {
    case unsupportedImage
    case corruptImage
    case noForegroundFound
    case modelNotInstalled
    case insufficientDiskSpace
    case insufficientMemory
    case inferenceFailed
    case invalidMesh
    case exportFailed
    case cancelled
    case malformedRequest
    case internalError
}

public struct ReadyMessage: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let engine: String
    public let engineAvailable: Bool
    public let detail: String?
}

public struct ProgressMessage: Codable, Equatable, Sendable {
    public let jobId: String
    public let stage: SculptorStage
    public let stageFraction: Double
    /// Overall 0...1 progress across every stage.
    public let fraction: Double
}

public struct ResultMessage: Codable, Equatable, Sendable {
    public let jobId: String
    /// The canonical asset the user exports.
    public let glbPath: String
    /// Viewer-compatible copy: Model I/O cannot read GLB. Disposable.
    public let previewPath: String
    public let preparedImagePath: String
    public let triangleCount: Int
    public let vertexCount: Int
    public let hasTexture: Bool
    public let appliedScale: Double
    public let boundingBoxLongestEdge: Double
    public let upAxis: String
    public let originConvention: String
    public let durationSeconds: Double
}

public struct ErrorMessage: Codable, Equatable, Sendable {
    public let jobId: String?
    public let code: SculptorErrorCode
    public let message: String
    /// Whether the user can retry without re-importing the source image.
    public let recoverable: Bool
}

/// One decoded line from the worker.
public enum WorkerMessage: Sendable {
    case ready(ReadyMessage)
    case progress(ProgressMessage)
    case result(ResultMessage)
    case failure(ErrorMessage)

    private struct Envelope: Decodable {
        let type: String
    }

    /// Decodes one protocol line, or returns `nil` for a message type this
    /// build does not know about.
    ///
    /// Unknown types are ignored rather than fatal so a newer worker paired
    /// with an older app degrades instead of dying.
    public static func decode(_ data: Data, using decoder: JSONDecoder) throws -> WorkerMessage? {
        let envelope = try decoder.decode(Envelope.self, from: data)
        switch envelope.type {
        case "ready": return .ready(try decoder.decode(ReadyMessage.self, from: data))
        case "progress": return .progress(try decoder.decode(ProgressMessage.self, from: data))
        case "result": return .result(try decoder.decode(ResultMessage.self, from: data))
        case "error": return .failure(try decoder.decode(ErrorMessage.self, from: data))
        default: return nil
        }
    }
}
