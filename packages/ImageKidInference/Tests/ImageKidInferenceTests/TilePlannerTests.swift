import CoreGraphics
import XCTest
@testable import ImageKidInference

final class TilePlannerTests: XCTestCase {
    func testSmallImageProducesSingleFullTile() {
        let tiles = TilePlanner.plan(sourceWidth: 200, sourceHeight: 150, tileSize: 256, overlap: 16)
        XCTAssertEqual(tiles.count, 1)
        XCTAssertEqual(tiles[0].readRect, CGRect(x: 0, y: 0, width: 200, height: 150))
        XCTAssertEqual(tiles[0].coreRect, CGRect(x: 0, y: 0, width: 200, height: 150))
    }

    func testTilesCoverEveryPixelWithoutGaps() {
        let width = 900
        let height = 700
        let tiles = TilePlanner.plan(sourceWidth: width, sourceHeight: height, tileSize: 256, overlap: 16)

        var covered = Array(repeating: false, count: width * height)
        for tile in tiles {
            let rect = tile.coreRect
            for y in Int(rect.minY)..<Int(rect.maxY) {
                for x in Int(rect.minX)..<Int(rect.maxX) {
                    covered[y * width + x] = true
                }
            }
        }
        XCTAssertFalse(covered.contains(false), "every pixel must belong to exactly one core tile")
    }

    func testCoreRectsDoNotOverlap() {
        let tiles = TilePlanner.plan(sourceWidth: 800, sourceHeight: 600, tileSize: 256, overlap: 24)
        for i in tiles.indices {
            for j in (i + 1)..<tiles.count {
                XCTAssertFalse(
                    tiles[i].coreRect.intersects(tiles[j].coreRect),
                    "core tiles must be disjoint"
                )
            }
        }
    }

    func testReadRectContainsCoreRectAndStaysInBounds() {
        let width = 800
        let height = 600
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let tiles = TilePlanner.plan(sourceWidth: width, sourceHeight: height, tileSize: 256, overlap: 24)
        for tile in tiles {
            XCTAssertTrue(tile.readRect.contains(tile.coreRect))
            XCTAssertTrue(bounds.contains(tile.readRect))
        }
    }

    func testMaskDimensionsFromCommonShapes() {
        XCTAssertEqual(CoreMLBackgroundRemover.maskDimensions(from: [1, 1, 1024, 512])?.width, 512)
        XCTAssertEqual(CoreMLBackgroundRemover.maskDimensions(from: [1, 1, 1024, 512])?.height, 1024)
        XCTAssertEqual(CoreMLBackgroundRemover.maskDimensions(from: [1024, 768])?.width, 768)
        XCTAssertEqual(CoreMLBackgroundRemover.maskDimensions(from: [1024, 768])?.height, 1024)
    }
}
