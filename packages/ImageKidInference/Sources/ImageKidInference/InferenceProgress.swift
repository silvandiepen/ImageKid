import Foundation

/// A coarse progress update emitted while a model runs.
///
/// `fraction` is `nil` when the stage cannot report a meaningful ratio (for
/// example while a model is loading), and a value in `0...1` otherwise. `detail`
/// is a short, user-facing status string.
public struct InferenceProgress: Sendable, Equatable {
    public let detail: String
    public let fraction: Double?

    public init(detail: String, fraction: Double? = nil) {
        self.detail = detail
        self.fraction = fraction
    }
}

/// A closure that receives progress updates. It may be called on any thread, so
/// callers that update UI must hop to the main actor themselves.
public typealias InferenceProgressHandler = @Sendable (InferenceProgress) -> Void
