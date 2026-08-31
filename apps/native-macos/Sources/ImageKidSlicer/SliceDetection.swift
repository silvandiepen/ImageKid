import CoreGraphics
import Foundation

/// Finding the gutters in a sheet: the runs of uninterrupted background that
/// separate one tile from the next.
///
/// This is an accelerator, not a mode. It produces ordinary guides the user
/// can drag, delete, or ignore — Auto Slice then cuts along them exactly as if
/// they had been dragged out by hand.
enum SliceDetection {
    struct Suggestion: Equatable {
        var vertical: [CGFloat] = []
        var horizontal: [CGFloat] = []

        var isEmpty: Bool { vertical.isEmpty && horizontal.isEmpty }
        var count: Int { vertical.count + horizontal.count }
    }

    /// How far a channel may drift from the background and still count as
    /// background. Generous enough for JPEG ringing around a tile edge.
    static let defaultTolerance = 14
    /// A gutter thinner than this is noise, not a deliberate gap.
    static let defaultMinimumRun = 2
    /// The analysis is done at this size at most: a gutter is a large-scale
    /// feature, and a 12000px scan does not need 12000 columns of work.
    static let analysisMaxSize = 1400

    /// Guides down the middle of every interior gutter.
    static func gutters(
        in image: CGImage,
        tolerance: Int = defaultTolerance,
        minimumRun: Int = defaultMinimumRun
    ) -> Suggestion {
        guard let projection = Projection(image: image, tolerance: tolerance) else { return Suggestion() }
        return Suggestion(
            vertical: centres(ofRunsIn: projection.columns, minimumRun: minimumRun),
            horizontal: centres(ofRunsIn: projection.rows, minimumRun: minimumRun)
        )
    }

    /// Where the content actually starts and stops — the borders of the tiles
    /// rather than the middle of the gaps between them.
    ///
    /// These are what a dragged slice sticks to, so pulling an edge near a
    /// square lands it exactly on that square instead of a pixel or two off.
    static func contentEdges(
        in image: CGImage,
        tolerance: Int = defaultTolerance,
        minimumRun: Int = defaultMinimumRun
    ) -> Suggestion {
        guard let projection = Projection(image: image, tolerance: tolerance) else { return Suggestion() }
        return Suggestion(
            vertical: edges(ofContentIn: projection.columns, minimumRun: minimumRun),
            horizontal: edges(ofContentIn: projection.rows, minimumRun: minimumRun)
        )
    }

    /// The normalised boundary either side of every run of content long enough
    /// to count. Boundaries sitting on the image edge are dropped: the image's
    /// own edges are already snap targets in their own right.
    static func edges(ofContentIn backgroundFlags: [Bool], minimumRun: Int) -> [CGFloat] {
        guard backgroundFlags.count > 2 else { return [] }

        var edges: [CGFloat] = []
        var runStart: Int?

        func closeRun(at end: Int) {
            guard let start = runStart else { return }
            runStart = nil
            guard end - start >= minimumRun else { return }
            if start > 0 { edges.append(CGFloat(start) / CGFloat(backgroundFlags.count)) }
            if end < backgroundFlags.count { edges.append(CGFloat(end) / CGFloat(backgroundFlags.count)) }
        }

        for index in backgroundFlags.indices {
            if backgroundFlags[index] {
                closeRun(at: index)
            } else if runStart == nil {
                runStart = index
            }
        }
        closeRun(at: backgroundFlags.count)

        return edges
    }

    // MARK: - Elements

    /// A box around every separate thing in the image.
    ///
    /// Where gutter finding projects the whole image onto one axis — and so
    /// can only ever describe a grid — this walks the pixels and groups the
    /// ones that touch. That finds three boxes scattered across a collage,
    /// which no amount of projecting will.
    ///
    /// Boxes are returned in reading order, so the slices they become are
    /// numbered the way the sheet is read.
    static func elements(
        in image: CGImage,
        tolerance: Int = defaultTolerance,
        minimumSide: CGFloat = 0.012,
        mergeGap: Int = 3
    ) -> [CGRect] {
        guard let sample = Sample(image: image) else { return [] }
        let width = sample.width
        let height = sample.height
        let background = sample.backgroundColour()

        var isContent = [Bool](repeating: false, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                isContent[y * width + x] = !sample.matches(background, x: x, y: y, tolerance: tolerance)
            }
        }

        var boxes = boundingBoxes(ofComponentsIn: isContent, width: width, height: height)

        // A thing is rarely one component: a letter, a shadow, an outline and
        // its fill all touch nothing. Merging near neighbours puts them back
        // together before anything is measured.
        boxes = merged(boxes, within: mergeGap)

        let minimumWidth = minimumSide * CGFloat(width)
        let minimumHeight = minimumSide * CGFloat(height)
        boxes = boxes.filter { $0.width >= minimumWidth && $0.height >= minimumHeight }

        return readingOrder(boxes).map { box in
            SliceGeometry.clamped(CGRect(
                x: box.minX / CGFloat(width),
                y: box.minY / CGFloat(height),
                width: box.width / CGFloat(width),
                height: box.height / CGFloat(height)
            ))
        }
    }

    /// One box per group of touching content pixels, found with an explicit
    /// stack — a recursive fill would blow through the stack on a large image.
    static func boundingBoxes(ofComponentsIn isContent: [Bool], width: Int, height: Int) -> [CGRect] {
        guard width > 0, height > 0, isContent.count == width * height else { return [] }

        var visited = [Bool](repeating: false, count: width * height)
        var boxes: [CGRect] = []
        var stack: [Int] = []

        for start in 0..<(width * height) where isContent[start] && !visited[start] {
            visited[start] = true
            stack.removeAll(keepingCapacity: true)
            stack.append(start)

            var minX = start % width, maxX = minX
            var minY = start / width, maxY = minY

            while let index = stack.popLast() {
                let x = index % width
                let y = index / width
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }

                // Eight-connected: a diagonal touch is still the same thing.
                for dy in -1...1 {
                    for dx in -1...1 where !(dx == 0 && dy == 0) {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                        let neighbour = ny * width + nx
                        guard isContent[neighbour], !visited[neighbour] else { continue }
                        visited[neighbour] = true
                        stack.append(neighbour)
                    }
                }
            }

            boxes.append(CGRect(
                x: CGFloat(minX), y: CGFloat(minY),
                width: CGFloat(maxX - minX + 1), height: CGFloat(maxY - minY + 1)
            ))
        }
        return boxes
    }

    /// Union any boxes that overlap once grown by `gap`, repeatedly, until
    /// nothing more merges.
    static func merged(_ boxes: [CGRect], within gap: Int) -> [CGRect] {
        var result = boxes
        var didMerge = true

        while didMerge {
            didMerge = false
            var next: [CGRect] = []

            for box in result {
                let grown = box.insetBy(dx: -CGFloat(gap), dy: -CGFloat(gap))
                if let index = next.firstIndex(where: { $0.insetBy(dx: -CGFloat(gap), dy: -CGFloat(gap)).intersects(grown) }) {
                    next[index] = next[index].union(box)
                    didMerge = true
                } else {
                    next.append(box)
                }
            }
            result = next
        }
        return result
    }

    /// Left to right, top to bottom — boxes that overlap vertically count as
    /// the same row, however ragged their tops are.
    static func readingOrder(_ boxes: [CGRect]) -> [CGRect] {
        var remaining = boxes.sorted { $0.minY < $1.minY }
        var ordered: [CGRect] = []

        while !remaining.isEmpty {
            let first = remaining.removeFirst()
            var row = [first]
            var rowBottom = first.maxY

            var index = 0
            while index < remaining.count {
                if remaining[index].minY < rowBottom {
                    let box = remaining.remove(at: index)
                    rowBottom = max(rowBottom, box.maxY)
                    row.append(box)
                } else {
                    index += 1
                }
            }
            ordered.append(contentsOf: row.sorted { $0.minX < $1.minX })
        }
        return ordered
    }

    /// Which columns and rows are entirely background. Gutter finding and
    /// content edges read the image the same way, so the scan happens once.
    private struct Projection {
        /// `true` where the whole column is background.
        let columns: [Bool]
        /// `true` where the whole row is background.
        let rows: [Bool]

        init?(image: CGImage, tolerance: Int) {
            guard let sample = Sample(image: image) else { return nil }
            let background = sample.backgroundColour()
            columns = (0..<sample.width).map { x in
                (0..<sample.height).allSatisfy { y in
                    sample.matches(background, x: x, y: y, tolerance: tolerance)
                }
            }
            rows = (0..<sample.height).map { y in
                (0..<sample.width).allSatisfy { x in
                    sample.matches(background, x: x, y: y, tolerance: tolerance)
                }
            }
        }
    }

    /// The normalised centre of every run of `true` long enough to count.
    ///
    /// Runs touching an edge are skipped: those are the sheet's own margin,
    /// and a cut line inside the margin would only carve off a blank strip.
    static func centres(ofRunsIn flags: [Bool], minimumRun: Int) -> [CGFloat] {
        guard flags.count > 2 else { return [] }

        var centres: [CGFloat] = []
        var runStart: Int?

        func closeRun(at end: Int) {
            guard let start = runStart else { return }
            runStart = nil
            let length = end - start
            guard length >= minimumRun, start > 0, end < flags.count else { return }
            let middle = CGFloat(start + end) / 2
            centres.append(middle / CGFloat(flags.count))
        }

        for index in flags.indices {
            if flags[index] {
                if runStart == nil { runStart = index }
            } else {
                closeRun(at: index)
            }
        }
        closeRun(at: flags.count)

        return centres
    }

    /// A downsampled RGBA copy of the source, so the scan is bounded no matter
    /// how large the sheet is.
    private struct Sample {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        init?(image: CGImage) {
            let longest = max(image.width, image.height)
            let scale = longest > SliceDetection.analysisMaxSize
                ? CGFloat(SliceDetection.analysisMaxSize) / CGFloat(longest)
                : 1
            let width = max(Int((CGFloat(image.width) * scale).rounded()), 1)
            let height = max(Int((CGFloat(image.height) * scale).rounded()), 1)

            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            guard let context = CGContext(
                data: &bytes,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }

            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

            self.width = width
            self.height = height
            self.bytes = bytes
        }

        /// A bitmap context's memory runs top-down even though its drawing
        /// origin is bottom-left, so row 0 is already the visual top — the
        /// same top-left origin every slice rectangle uses. No flip.
        private func offset(x: Int, y: Int) -> Int {
            (y * width + x) * 4
        }

        func pixel(x: Int, y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
            let i = offset(x: x, y: y)
            return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]), Int(bytes[i + 3]))
        }

        func matches(_ colour: (r: Int, g: Int, b: Int, a: Int), x: Int, y: Int, tolerance: Int) -> Bool {
            let p = pixel(x: x, y: y)
            // Transparent is background whatever its colour channels say.
            if p.a <= 8, colour.a <= 8 { return true }
            return abs(p.r - colour.r) <= tolerance
                && abs(p.g - colour.g) <= tolerance
                && abs(p.b - colour.b) <= tolerance
                && abs(p.a - colour.a) <= tolerance
        }

        /// The median of the border pixels — a sheet's background is whatever
        /// surrounds it, and a median shrugs off a tile that runs to the edge.
        func backgroundColour() -> (r: Int, g: Int, b: Int, a: Int) {
            var reds: [Int] = [], greens: [Int] = [], blues: [Int] = [], alphas: [Int] = []

            func add(_ x: Int, _ y: Int) {
                let p = pixel(x: x, y: y)
                reds.append(p.r); greens.append(p.g); blues.append(p.b); alphas.append(p.a)
            }
            for x in 0..<width { add(x, 0); add(x, height - 1) }
            for y in 0..<height { add(0, y); add(width - 1, y) }

            func median(_ values: [Int]) -> Int {
                guard !values.isEmpty else { return 0 }
                return values.sorted()[values.count / 2]
            }
            return (median(reds), median(greens), median(blues), median(alphas))
        }
    }
}
