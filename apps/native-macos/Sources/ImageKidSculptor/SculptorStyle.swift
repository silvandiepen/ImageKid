import Foundation

/// Which way a model is built.
///
/// Three genuinely different things, not three settings of one thing.
///
/// Detailed reconstructs a surface and works from a single image. Shapes carves
/// the subject out of the flat-coloured regions its panels are drawn from — a
/// body, a muzzle, the inside of an ear — and needs several views to carve
/// against. Blocks does the same carve but keeps the grid it was carved on,
/// which is the point: coarse on purpose reads as a choice, where a smoothed
/// reconstruction at the same fidelity reads as a failure.
enum SculptorStyle: String, CaseIterable, Identifiable, Sendable {
    case detailed
    case shapes
    case blocks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .detailed: "Detailed"
        case .shapes: "Shapes"
        case .blocks: "Blocks"
        }
    }

    var detail: String {
        switch self {
        case .detailed:
            "Reconstructs a surface. Works from a single image."
        case .shapes:
            "Builds the subject from its own flat-coloured shapes. "
            + "Best with several views."
        case .blocks:
            "Builds the subject out of coloured blocks. "
            + "With several views it takes seconds and never guesses."
        }
    }

    /// Cells across the model. Twenty-eight keeps a cow's horns and ears while
    /// still reading as blocks; much coarser loses them, much finer stops
    /// looking deliberate.
    var blockGrid: Int { 28 }
}
