import Foundation

/// Errors raised by the inference engines.
public enum InferenceError: LocalizedError {
    /// The Core ML model could not be located by its `ModelProvider`.
    case modelUnavailable
    /// The model was found but failed to load or compile.
    case modelLoadFailed(String)
    /// The input image could not be turned into the pixel format the model needs.
    case inputPreparationFailed
    /// The model ran but produced no usable output feature.
    case outputMissing
    /// The model output could not be turned back into a `CGImage`.
    case outputDecodingFailed
    /// No foreground subject was detected (Vision background removal).
    case noForegroundFound

    public var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            return "The model is not installed yet."
        case .modelLoadFailed(let message):
            return "The model could not be loaded: \(message)"
        case .inputPreparationFailed:
            return "The image could not be prepared for the model."
        case .outputMissing:
            return "The model finished without returning a result."
        case .outputDecodingFailed:
            return "The model result could not be turned back into an image."
        case .noForegroundFound:
            return "No clear foreground subject was found in this image."
        }
    }
}
