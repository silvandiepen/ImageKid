import CoreGraphics
import Foundation

/// The lines a dragged slice can snap to, in normalised source coordinates.
struct SnapTargets {
    var vertical: [CGFloat] = []
    var horizontal: [CGFloat] = []

    var isEmpty: Bool { vertical.isEmpty && horizontal.isEmpty }
}

/// What a snap actually latched onto, so the canvas can draw the line the user
/// snapped to instead of leaving them guessing.
struct SnapResult {
    var rect: CGRect
    var verticalLines: [CGFloat] = []
    var horizontalLines: [CGFloat] = []
}

/// Edge snapping for slice rectangles.
///
/// Everything is normalised, and the thresholds arrive per axis because the
/// canvas converts one on-screen tolerance into two different normalised
/// distances on a non-square image.
enum SliceSnapping {
    /// Every line worth snapping to: the image edges and centre, the other
    /// slices' edges and centres, the guides, and the grid.
    static func targets(
        slices: [Slice],
        excluding excludedID: Slice.ID?,
        guides: [SliceGuide],
        grid: SliceGrid,
        includeCentreLines: Bool
    ) -> SnapTargets {
        var targets = SnapTargets(vertical: [0, 1], horizontal: [0, 1])

        if includeCentreLines {
            targets.vertical.append(0.5)
            targets.horizontal.append(0.5)
        }

        for slice in slices where slice.id != excludedID {
            targets.vertical.append(contentsOf: [slice.rect.minX, slice.rect.maxX])
            targets.horizontal.append(contentsOf: [slice.rect.minY, slice.rect.maxY])
            if includeCentreLines {
                targets.vertical.append(slice.rect.midX)
                targets.horizontal.append(slice.rect.midY)
            }
        }

        for guide in guides {
            switch guide.axis {
            case .vertical: targets.vertical.append(guide.position)
            case .horizontal: targets.horizontal.append(guide.position)
            }
        }

        targets.vertical.append(contentsOf: grid.verticalLines)
        targets.horizontal.append(contentsOf: grid.horizontalLines)

        return targets
    }

    /// The nearest target within `threshold`, or `nil` when nothing is close.
    static func snap(_ value: CGFloat, to candidates: [CGFloat], threshold: CGFloat) -> CGFloat? {
        guard threshold > 0 else { return nil }
        var best: CGFloat?
        var bestDistance = threshold
        for candidate in candidates {
            let distance = abs(candidate - value)
            if distance <= bestDistance {
                bestDistance = distance
                best = candidate
            }
        }
        return best
    }

    /// Snap a slice that is being **moved**: the whole rectangle shifts by
    /// whichever of its leading edge, centre, or trailing edge is closest to a
    /// target, so the size never changes.
    static func snapMoved(
        _ rect: CGRect,
        targets: SnapTargets,
        thresholdX: CGFloat,
        thresholdY: CGFloat
    ) -> SnapResult {
        var result = SnapResult(rect: rect)

        if let (offset, line) = bestOffset(
            for: [rect.minX, rect.midX, rect.maxX],
            targets: targets.vertical,
            threshold: thresholdX
        ) {
            result.rect.origin.x += offset
            result.verticalLines.append(line)
        }

        if let (offset, line) = bestOffset(
            for: [rect.minY, rect.midY, rect.maxY],
            targets: targets.horizontal,
            threshold: thresholdY
        ) {
            result.rect.origin.y += offset
            result.horizontalLines.append(line)
        }

        return SnapResult(
            rect: SliceGeometry.clamped(result.rect),
            verticalLines: result.verticalLines,
            horizontalLines: result.horizontalLines
        )
    }

    /// Snap a slice that is being **drawn or resized**: only the edges the
    /// pointer is actually moving latch on, so the opposite edge stays put.
    static func snapEdges(
        _ rect: CGRect,
        movingLeft: Bool,
        movingRight: Bool,
        movingTop: Bool,
        movingBottom: Bool,
        targets: SnapTargets,
        thresholdX: CGFloat,
        thresholdY: CGFloat
    ) -> SnapResult {
        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY
        var verticalLines: [CGFloat] = []
        var horizontalLines: [CGFloat] = []

        if movingLeft, let line = snap(minX, to: targets.vertical, threshold: thresholdX) {
            minX = line
            verticalLines.append(line)
        }
        if movingRight, let line = snap(maxX, to: targets.vertical, threshold: thresholdX) {
            maxX = line
            verticalLines.append(line)
        }
        if movingTop, let line = snap(minY, to: targets.horizontal, threshold: thresholdY) {
            minY = line
            horizontalLines.append(line)
        }
        if movingBottom, let line = snap(maxY, to: targets.horizontal, threshold: thresholdY) {
            maxY = line
            horizontalLines.append(line)
        }

        let snapped = CGRect(
            x: min(minX, maxX),
            y: min(minY, maxY),
            width: abs(maxX - minX),
            height: abs(maxY - minY)
        )
        return SnapResult(
            rect: SliceGeometry.clamped(snapped),
            verticalLines: verticalLines,
            horizontalLines: horizontalLines
        )
    }

    /// Snap a guide being dragged onto the same target set.
    static func snapGuide(
        _ position: CGFloat,
        axis: SliceGuide.Axis,
        targets: SnapTargets,
        threshold: CGFloat
    ) -> CGFloat {
        let candidates = axis == .vertical ? targets.vertical : targets.horizontal
        return snap(position, to: candidates, threshold: threshold) ?? position
    }

    /// The smallest shift that lands one of `values` on a target.
    private static func bestOffset(
        for values: [CGFloat],
        targets: [CGFloat],
        threshold: CGFloat
    ) -> (offset: CGFloat, line: CGFloat)? {
        var best: (offset: CGFloat, line: CGFloat)?
        var bestDistance = threshold

        for value in values {
            for target in targets {
                let distance = abs(target - value)
                if distance <= bestDistance {
                    bestDistance = distance
                    best = (target - value, target)
                }
            }
        }
        return best
    }
}
