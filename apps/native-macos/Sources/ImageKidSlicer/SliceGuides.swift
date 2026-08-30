import CoreGraphics
import Foundation

/// A cutting line across the whole source image — Photoshop's guides, except
/// these are what **Auto Slice** cuts along.
struct SliceGuide: Identifiable, Equatable {
    enum Axis: String, Equatable {
        /// A vertical line at `position` on the x axis: cuts left from right.
        case vertical
        /// A horizontal line at `position` on the y axis: cuts top from bottom.
        case horizontal
    }

    let id: UUID
    var axis: Axis
    /// Normalised 0…1 along the guide's axis, against the oriented source.
    var position: CGFloat

    init(id: UUID = UUID(), axis: Axis, position: CGFloat) {
        self.id = id
        self.axis = axis
        self.position = min(max(position, 0), 1)
    }
}

/// An optional regular grid drawn over the source. It is a snapping and
/// auto-slice aid only — it is never exported and never edits a slice by
/// itself.
struct SliceGrid: Equatable {
    var isEnabled: Bool = false
    var columns: Int = 3
    var rows: Int = 3

    static let range = 1...64

    /// Normalised x positions of the interior column lines.
    var verticalLines: [CGFloat] {
        guard isEnabled, columns > 1 else { return [] }
        return (1..<columns).map { CGFloat($0) / CGFloat(columns) }
    }

    /// Normalised y positions of the interior row lines.
    var horizontalLines: [CGFloat] {
        guard isEnabled, rows > 1 else { return [] }
        return (1..<rows).map { CGFloat($0) / CGFloat(rows) }
    }
}

/// Turning cutting lines into slices.
enum SliceAutoLayout {
    /// Every cell the cutting lines carve the image into, in reading order
    /// (left to right, top to bottom) so the exported numbering matches what
    /// the user sees.
    ///
    /// Cells thinner than `minimumSize` on either axis are dropped: two guides
    /// dragged almost on top of each other should not produce a sliver file.
    static func rects(
        verticalCuts: [CGFloat],
        horizontalCuts: [CGFloat],
        minimumSize: CGFloat = SliceGeometry.minimumNormalizedSize
    ) -> [CGRect] {
        let xEdges = edges(verticalCuts)
        let yEdges = edges(horizontalCuts)

        var rects: [CGRect] = []
        for y in 0..<(yEdges.count - 1) {
            for x in 0..<(xEdges.count - 1) {
                let rect = CGRect(
                    x: xEdges[x],
                    y: yEdges[y],
                    width: xEdges[x + 1] - xEdges[x],
                    height: yEdges[y + 1] - yEdges[y]
                )
                guard rect.width >= minimumSize, rect.height >= minimumSize else { continue }
                rects.append(SliceGeometry.clamped(rect))
            }
        }
        return rects
    }

    /// Cut positions plus the image's own edges, sorted and de-duplicated.
    private static func edges(_ cuts: [CGFloat]) -> [CGFloat] {
        var values = cuts.filter { $0 > 0 && $0 < 1 } + [0, 1]
        values.sort()
        var unique: [CGFloat] = []
        for value in values where unique.last.map({ abs($0 - value) > 1e-9 }) ?? true {
            unique.append(value)
        }
        return unique
    }
}
