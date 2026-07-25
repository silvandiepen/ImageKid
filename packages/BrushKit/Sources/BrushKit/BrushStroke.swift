import CoreGraphics
import Foundation

/// A persisted brush stroke: the captured input, which brush laid it down, and
/// the colour — everything needed to re-generate its dabs later. This is the
/// reusable "vector stroke" of the hybrid model: Inka stores these on
/// `.vectorStrokes` layers and re-rasterizes them non-destructively, and
/// ImageKid can persist editable freehand the same way. It lives in BrushKit,
/// not Inka, precisely so it is shareable.
public struct BrushStroke: Equatable, Sendable, Codable, Identifiable {
    public var id: UUID
    /// The brush preset used, by `Brush.id`. The document owns the preset table.
    public var brushID: String
    public var color: RGBA
    public var input: StrokeInput
    /// The jitter seed captured at draw time, so re-rendering is identical.
    public var seed: UInt64

    public init(
        id: UUID = UUID(), brushID: String, color: RGBA, input: StrokeInput, seed: UInt64 = 0
    ) {
        self.id = id
        self.brushID = brushID
        self.color = color
        self.input = input
        self.seed = seed
    }

    /// Regenerate this stroke's dabs against a resolved brush preset.
    public func dabs(using brush: Brush) -> [Dab] {
        BrushEngine.dabs(for: input, brush: brush, color: color, seed: seed)
    }
}
