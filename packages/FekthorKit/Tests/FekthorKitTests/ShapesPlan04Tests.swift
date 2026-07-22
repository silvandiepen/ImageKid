import XCTest

@testable import FekthorKit

final class ShapesPlan04Tests: XCTestCase {
    func testAutoPaletteUsesExactModeWhenBucketIsDominated() {
        let w = 20
        let h = 10
        var data = [UInt8](repeating: 255, count: w * h * 4)
        for i in 0..<(w * h) {
            let o = i * 4
            data[o] = i < 140 ? 17 : 19
            data[o + 1] = 34
            data[o + 2] = 51
            data[o + 3] = 255
        }
        let img = RasterImage(width: w, height: h, data: data)
        let q = ColorQuantizer.quantizeAuto(img, maxColors: 2, minFraction: 0.1)
        XCTAssertTrue(q.palette.contains { $0 == (17, 34, 51) })
        XCTAssertGreaterThanOrEqual(q.paletteExactCount, 1)
    }

    func testTinyDistinctRegionSurvivesMaxSimplicity() throws {
        let w = 40
        let h = 40
        var data = [UInt8](repeating: 255, count: w * h * 4)
        let dot = (20 * w + 20) * 4
        data[dot] = 255
        data[dot + 1] = 0
        data[dot + 2] = 0
        data[dot + 3] = 255
        let img = RasterImage(width: w, height: h, data: data)
        let result = try Fekthor.convert(
            img, mode: .shapes,
            options: Fekthor.Options(
                colors: 4, epsilon: 0.7, simplicity: 1, autoColorMinFraction: 0.0001))
        XCTAssertTrue(result.svg.contains("#ff0000"), "distinct red detail was absorbed")
    }

    func testTransparentBorderDoesNotEmitCanvasSizedFace() throws {
        let w = 80
        let h = 80
        var data = [UInt8](repeating: 0, count: w * h * 4)
        for y in 20..<60 {
            for x in 20..<60 {
                let o = (y * w + x) * 4
                data[o] = 20
                data[o + 1] = 120
                data[o + 2] = 220
                data[o + 3] = 255
            }
        }
        let img = RasterImage(width: w, height: h, data: data)
        let result = try Fekthor.convert(
            img, mode: .shapes,
            options: Fekthor.Options(
                colors: 4, epsilon: 0.8, simplicity: 0.1, autoColorMinFraction: 0.002))
        XCTAssertEqual(result.detail["backgroundTransparent"], 1)
        XCTAssertFalse(result.svg.contains("<rect"))
        for element in result.document.elements {
            guard case .fill(let fill) = element else { continue }
            let maxArea = fill.rings.map { abs(Geometry.area($0)) }.max() ?? 0
            XCTAssertLessThan(maxArea, Double(w * h) * 0.95)
        }
    }

    func testSyntheticLogoRoundelExportsCircleAndExactColours() throws {
        let red: RGB = (230, 20, 50)
        let w = 120
        let h = 120
        var data = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let dx = Double(x) + 0.5 - 50
                let dy = Double(y) + 0.5 - 60
                guard dx * dx + dy * dy <= 28 * 28 else { continue }
                let o = (y * w + x) * 4
                data[o] = red.r
                data[o + 1] = red.g
                data[o + 2] = red.b
                data[o + 3] = 255
            }
        }
        let img = RasterImage(width: w, height: h, data: data)
        let result = try Fekthor.convert(
            img, mode: .shapes,
            options: Fekthor.Options(
                colors: 6, epsilon: 0.9, simplicity: 0.1, smoothing: 0.35,
                straighten: 0.8, autoColorMinFraction: 0.002))
        XCTAssertTrue(result.svg.contains("#e61432"))
        XCTAssertLessThanOrEqual(result.document.nodeCount, 120)
    }

    func testSyntheticDiamondKeepsFourSharpCorners() throws {
        let green: RGB = (0, 160, 110)
        let doc = VectorDocument(
            width: 120, height: 120,
            elements: [
                .fill(
                    FillShape(
                        id: "diamond", color: green,
                        geometry: .rect(
                            center: Pt(60, 60), w: 54, h: 54, rotation: .pi / 4,
                            cornerRadius: 0)))
            ])
        let img = Self.harden(Rasterizer.render(doc, smoothing: 1, background: nil), colors: [green])
        let result = try Fekthor.convert(
            img, mode: .shapes,
            options: Fekthor.Options(
                colors: 4, epsilon: 0.8, simplicity: 0.1, smoothing: 0.35,
                straighten: 0.8, autoColorMinFraction: 0.002))
        XCTAssertTrue(result.svg.contains("#00a06e"))
        XCTAssertLessThanOrEqual(result.document.nodeCount, 120)
        XCTAssertLessThanOrEqual(result.document.nodeCount, 8, "diamond should keep four sharp corners")
    }

    /// Regression for the transparent-PNG tracing bug: a square on a transparent
    /// background must stay a square (4 sharp corners), and an annulus must stay
    /// two concentric rings — not snap to circles or bulging blobs. The old
    /// pipeline lost every corner of symmetric shapes (no strict local-max turn
    /// exists when all four turns tie) and then circle-fit the rounded result.
    func testTransparentSquareAndAnnulusKeepTheirGeometry() throws {
        let w = 260
        let h = 260
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let mauve: RGB = (178, 128, 178)
        let purple: RGB = (124, 102, 204)
        func put(_ x: Int, _ y: Int, _ c: RGB) {
            let o = (y * w + x) * 4
            data[o] = c.r
            data[o + 1] = c.g
            data[o + 2] = c.b
            data[o + 3] = 255
        }
        for y in 20..<120 {
            for x in 20..<120 { put(x, y, mauve) }
        }
        for y in 0..<h {
            for x in 0..<w {
                let dx = Double(x) + 0.5 - 180
                let dy = Double(y) + 0.5 - 180
                let d2 = dx * dx + dy * dy
                if d2 <= 60 * 60 && d2 >= 25 * 25 { put(x, y, purple) }
            }
        }
        let img = RasterImage(width: w, height: h, data: data)
        let result = try Fekthor.convert(
            img, mode: .shapes,
            options: Fekthor.Options(
                colors: 8, epsilon: 1.0, simplicity: 0.3, smoothing: 1.0,
                straighten: 0.5, autoColorMinFraction: 0.004))
        XCTAssertEqual(result.detail["backgroundTransparent"], 1)
        XCTAssertEqual(result.document.fillCount, 2)
        for element in result.document.elements {
            guard case .fill(let fill) = element else { continue }
            let outer = fill.rings.max { abs(Geometry.area($0)) < abs(Geometry.area($1)) } ?? []
            let bb = PrimitiveDetect.bbox(outer)
            for ring in fill.rings {
                for p in ring {
                    XCTAssertTrue(
                        p.x >= -1 && p.x <= Double(w) + 1 && p.y >= -1 && p.y <= Double(h) + 1,
                        "boundary point escapes the canvas: \(p)")
                }
            }
            if bb.maxx <= 130 {
                // The square: area must match side², not a circumscribed circle
                // (a circle fit to a square carries ~1.5× its area).
                let area = abs(Geometry.area(outer))
                XCTAssertEqual(area, 100.0 * 100.0, accuracy: 100.0 * 100.0 * 0.05)
                XCTAssertLessThanOrEqual(fill.nodeCount, 6, "square should be 4 corners")
            } else {
                // The annulus: two rings whose areas match the true radii.
                XCTAssertEqual(fill.rings.count, 2)
                let inner = fill.rings.min { abs(Geometry.area($0)) < abs(Geometry.area($1)) } ?? []
                XCTAssertEqual(
                    abs(Geometry.area(outer)), .pi * 60 * 60, accuracy: .pi * 60 * 60 * 0.05)
                XCTAssertEqual(
                    abs(Geometry.area(inner)), .pi * 25 * 25, accuracy: .pi * 25 * 25 * 0.08)
            }
        }
    }

    private static func harden(_ img: RasterImage, colors: [RGB]) -> RasterImage {
        var data = img.data
        for i in 0..<(img.width * img.height) {
            let o = i * 4
            guard data[o + 3] >= 128 else {
                data[o] = 0
                data[o + 1] = 0
                data[o + 2] = 0
                data[o + 3] = 0
                continue
            }
            let c: RGB = (data[o], data[o + 1], data[o + 2])
            let nearest = colors.min {
                ColorQuantizer.dist2(c, $0) < ColorQuantizer.dist2(c, $1)
            } ?? c
            data[o] = nearest.r
            data[o + 1] = nearest.g
            data[o + 2] = nearest.b
            data[o + 3] = 255
        }
        return RasterImage(width: img.width, height: img.height, data: data)
    }
}
