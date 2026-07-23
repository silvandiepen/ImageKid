import Foundation

/// Where one path crosses others — and anchors inserted exactly there.
///
/// "Add crossing points": right-clicking a line that crosses another inserts
/// anchors at the exact intersections, so the crossing becomes editable
/// (break, join, snap). Detection samples cubics adaptively and intersects
/// flat segments; each hit maps back to the crossed path's (segment, t) so
/// `Editing.insertingAnchor`'s exact de Casteljau split places the anchor.
public enum PathCrossings {
    public struct Crossing: Equatable, Sendable {
        /// Segment index in the CUBICIZED form of the path (the same
        /// convention `Editing.insertingAnchor` consumes).
        public var segment: Int
        /// Parameter within that segment, 0..1.
        public var t: Double
        public var point: Pt
    }

    /// Samples per cubic segment when flattening for intersection tests.
    /// Crossing positions come from flat-segment intersections, so this
    /// bounds positional error to well under a pixel at icon scale.
    static let cubicSamples = 32

    // MARK: - Detection

    /// All points where `path` crosses any of `others`, ordered along the
    /// path (segment, then t). Touches at the path's own anchors are skipped
    /// (there is already a point there); duplicate hits within `weld`
    /// distance collapse to one.
    public static func crossings(
        of path: RefinedPath, with others: [RefinedPath], weld: Double = 0.5
    ) -> [Crossing] {
        let subject = flatten(Editing.cubicized(path))
        guard !subject.isEmpty else { return [] }
        let obstacleChains = others.map { flatten(Editing.cubicized($0)).map(\.point) }

        var out: [Crossing] = []
        for i in 0..<(subject.count - 1) {
            let a = subject[i]
            let b = subject[i + 1]
            for chain in obstacleChains {
                guard chain.count > 1 else { continue }
                for j in 0..<(chain.count - 1) {
                    guard
                        let hit = segmentIntersection(
                            a.point, b.point, chain[j], chain[j + 1])
                    else { continue }
                    // Parameter along the subject's flat piece → original t.
                    let t = a.t + (b.t - a.t) * hit.u
                    // Skip hits sitting on an existing anchor.
                    if t < 0.005 || t > 0.995, a.segment == b.segment { continue }
                    let crossing = Crossing(
                        segment: a.segment, t: min(max(t, 0.001), 0.999),
                        point: hit.point)
                    if !out.contains(where: {
                        hypot($0.point.x - crossing.point.x, $0.point.y - crossing.point.y) < weld
                    }) {
                        out.append(crossing)
                    }
                }
            }
        }
        out.sort { ($0.segment, $0.t) < ($1.segment, $1.t) }
        return out
    }

    /// The path with anchors inserted at every crossing. Insertions run
    /// last-first; several hits inside one segment remap their `t` onto the
    /// shrinking front piece so nothing drifts.
    public static func insertingCrossings(
        _ path: RefinedPath, with others: [RefinedPath], weld: Double = 0.5
    ) -> RefinedPath {
        let hits = crossings(of: path, with: others, weld: weld)
        guard !hits.isEmpty else { return path }
        var out = Editing.cubicized(path)
        var bySegment: [Int: [Double]] = [:]
        for hit in hits { bySegment[hit.segment, default: []].append(hit.t) }
        for segment in bySegment.keys.sorted(by: >) {
            var previous = 1.0
            for t in bySegment[segment]!.sorted(by: >) {
                let remapped = t / previous
                out = Editing.insertingAnchor(out, segment: segment, t: remapped)
                previous = t
            }
        }
        return out
    }

    // MARK: - Internals

    struct Sample {
        var point: Pt
        var segment: Int
        var t: Double
    }

    /// Flat polyline over a cubicized path, remembering (segment, t) per
    /// vertex. Lines contribute their endpoints; cubics a fixed fan.
    static func flatten(_ path: RefinedPath) -> [Sample] {
        var out: [Sample] = [Sample(point: path.start, segment: 0, t: 0)]
        var from = path.start
        for (i, segment) in path.segments.enumerated() {
            switch segment {
            case .line(let to):
                out.append(Sample(point: to, segment: i, t: 1))
                from = to
            case .cubic(let c1, let c2, let to):
                for s in 1...cubicSamples {
                    let t = Double(s) / Double(cubicSamples)
                    out.append(
                        Sample(
                            point: cubicPoint(from, c1, c2, to, t), segment: i, t: t))
                }
                from = to
            case .arc:
                // Unreachable post-cubicize; treat as a chord if it appears.
                out.append(Sample(point: segment.endPoint, segment: i, t: 1))
                from = segment.endPoint
            }
        }
        return out
    }

    static func cubicPoint(_ p0: Pt, _ c1: Pt, _ c2: Pt, _ p3: Pt, _ t: Double) -> Pt {
        let u = 1 - t
        let x =
            u * u * u * p0.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x
            + t * t * t * p3.x
        let y =
            u * u * u * p0.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y
            + t * t * t * p3.y
        return Pt(x, y)
    }

    /// Proper-crossing intersection of segments ab and cd; returns the hit
    /// point and the parameter u along ab, or nil for parallel/apart/touch
    /// at shared endpoints.
    static func segmentIntersection(
        _ a: Pt, _ b: Pt, _ c: Pt, _ d: Pt
    ) -> (point: Pt, u: Double)? {
        let r = Pt(b.x - a.x, b.y - a.y)
        let s = Pt(d.x - c.x, d.y - c.y)
        let denominator = r.x * s.y - r.y * s.x
        guard abs(denominator) > 1e-12 else { return nil }
        let ac = Pt(c.x - a.x, c.y - a.y)
        let u = (ac.x * s.y - ac.y * s.x) / denominator
        let v = (ac.x * r.y - ac.y * r.x) / denominator
        let eps = 1e-9
        // Subject: strict interior (its own anchors are already points).
        // Obstacle: half-open [0, 1) so a crossing exactly at one of its
        // sample vertices counts once instead of never (or twice).
        guard u > eps, u < 1 - eps, v >= 0, v < 1 - eps else { return nil }
        return (Pt(a.x + r.x * u, a.y + r.y * u), u)
    }
}
