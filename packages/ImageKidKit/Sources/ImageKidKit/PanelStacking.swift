import CoreGraphics
import Foundation

/// Pure, host-agnostic model for magnetic panel stacking: which floating
/// panels are stuck together, in what vertical order, plus the geometry
/// helpers hosts use to detect a stick on release and to lay a stack out
/// flush. Panels are keyed by opaque id strings so any host state model
/// (Fekthor's palette enum, ImageKid's dock ids) can drive it.
public struct PanelStacks: Equatable, Codable {
    /// Every current stack, each ordered top → bottom. Invariants: a panel
    /// appears in at most one stack, and every stack has at least two members
    /// (a lone panel is simply unstacked).
    public private(set) var stacks: [[String]]

    public init(stacks: [[String]] = []) {
        self.stacks = stacks.filter { $0.count >= 2 }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(stacks: try container.decode([[String]].self, forKey: .stacks))
    }

    private enum CodingKeys: String, CodingKey { case stacks }

    // MARK: - Queries

    /// The stack the panel belongs to (top → bottom), or nil when unstacked.
    public func stack(containing id: String) -> [String]? {
        stacks.first { $0.contains(id) }
    }

    public func isStacked(_ id: String) -> Bool {
        stack(containing: id) != nil
    }

    /// The top-most member of the panel's stack, or nil when unstacked.
    public func head(of id: String) -> String? {
        stack(containing: id)?.first
    }

    /// True when the panel is stacked AND on top (it drags its stack along).
    public func isHead(_ id: String) -> Bool {
        head(of: id) == id
    }

    /// True when the panel sits below another one (its header drag detaches).
    public func isFollower(_ id: String) -> Bool {
        guard let head = head(of: id) else { return false }
        return head != id
    }

    /// Everything below the panel in its stack, top → bottom.
    public func followers(of id: String) -> [String] {
        guard let stack = stack(containing: id),
            let index = stack.firstIndex(of: id)
        else { return [] }
        return Array(stack.dropFirst(index + 1))
    }

    // MARK: - Mutations

    /// Stick `id` — together with everything already stacked below it —
    /// directly under `other`. Panels previously below `other` move down
    /// below the inserted run. No-op when it would stack a panel below
    /// itself or one of its own followers.
    public mutating func attach(_ id: String, below other: String) {
        guard id != other else { return }
        let chain = [id] + followers(of: id)
        guard !chain.contains(other) else { return }
        removeRun(chain)
        if let index = stacks.firstIndex(where: { $0.contains(other) }) {
            let insertAt = (stacks[index].firstIndex(of: other) ?? stacks[index].count - 1) + 1
            stacks[index].insert(contentsOf: chain, at: insertAt)
        } else {
            stacks.append([other] + chain)
        }
    }

    /// Pull `id` out of its stack. The panels below close the gap and stay
    /// attached to whatever remains above ([A,B,C] minus B leaves [A,C]).
    public mutating func detach(_ id: String) {
        guard let index = stacks.firstIndex(where: { $0.contains(id) }) else { return }
        stacks[index].removeAll { $0 == id }
        prune()
    }

    /// Remove a contiguous run (a panel plus its followers) from its stack.
    private mutating func removeRun(_ run: [String]) {
        guard let first = run.first,
            let index = stacks.firstIndex(where: { $0.contains(first) })
        else { return }
        stacks[index].removeAll { run.contains($0) }
        prune()
    }

    private mutating func prune() {
        stacks.removeAll { $0.count < 2 }
    }

    // MARK: - Geometry

    /// Default vertical stick distance in points.
    public static let snapTolerance: CGFloat = 14

    /// The panel the released `frame` should stick under, or nil: another
    /// panel whose BOTTOM edge lies within `tolerance` of the dragged panel's
    /// TOP edge, horizontally overlapping it by at least half the dragged
    /// width. Excluded: the dragged panel itself, its own followers, and
    /// panels that already have another panel stuck below them (only a
    /// stack's tail — or a lone panel — is a stick target). The closest
    /// candidate wins (vertical gap first, then horizontal misalignment).
    public func snapCandidate(
        for id: String,
        frame: CGRect,
        others: [String: CGRect],
        tolerance: CGFloat = PanelStacks.snapTolerance
    ) -> String? {
        let chain = Set([id] + followers(of: id))
        var best: (id: String, distance: CGFloat, misalignment: CGFloat)?
        for (candidate, candidateFrame) in others {
            guard !chain.contains(candidate) else { continue }
            guard followers(of: candidate).isEmpty else { continue }
            let distance = abs(candidateFrame.maxY - frame.minY)
            guard distance <= tolerance else { continue }
            let overlap =
                min(candidateFrame.maxX, frame.maxX) - max(candidateFrame.minX, frame.minX)
            guard overlap >= frame.width * 0.5 else { continue }
            let misalignment = abs(candidateFrame.minX - frame.minX)
            if let best, (best.distance, best.misalignment) <= (distance, misalignment) {
                continue
            }
            best = (candidate, distance, misalignment)
        }
        return best?.id
    }

    /// Flush top → bottom origins for a stack: every member takes the head's
    /// x, and each sits exactly below the previous one (0pt gap).
    public static func layout(
        stack: [String],
        headOrigin: CGPoint,
        sizes: [String: CGSize]
    ) -> [String: CGPoint] {
        var origins: [String: CGPoint] = [:]
        var y = headOrigin.y
        for id in stack {
            origins[id] = CGPoint(x: headOrigin.x, y: y)
            y += sizes[id]?.height ?? 0
        }
        return origins
    }
}
