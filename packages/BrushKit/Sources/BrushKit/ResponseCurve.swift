import Foundation

/// How an input (0…1) maps to its effect (0…1) before a dynamic applies it.
/// A pencil that barely marks under light pressure and darkens fast is an
/// ease-in; a marker that hits full strength quickly is an ease-out. Real pens
/// are not linear, so a serious brush needs the curve.
public enum ResponseCurve: String, Equatable, Sendable, Codable, CaseIterable {
    case linear
    case easeIn
    case easeOut
    case easeInOut

    public var label: String {
        switch self {
        case .linear: "Linear"
        case .easeIn: "Ease In"
        case .easeOut: "Ease Out"
        case .easeInOut: "Ease In-Out"
        }
    }

    /// Shape `t` (clamped to 0…1).
    public func apply(_ t: Double) -> Double {
        let x = Swift.min(Swift.max(t, 0), 1)
        switch self {
        case .linear: return x
        case .easeIn: return x * x
        case .easeOut: return 1 - (1 - x) * (1 - x)
        case .easeInOut: return x < 0.5 ? 2 * x * x : 1 - 2 * (1 - x) * (1 - x)
        }
    }
}
