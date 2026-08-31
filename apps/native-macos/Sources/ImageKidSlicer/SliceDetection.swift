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

        /// Rows are drawn bottom-up into the context, so y is flipped back here
        /// to match the top-left origin every slice rectangle uses.
        private func offset(x: Int, y: Int) -> Int {
            ((height - 1 - y) * width + x) * 4
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
