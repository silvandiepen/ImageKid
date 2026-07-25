import BrushKit
import CoreGraphics
import Metal
import XCTest

@testable import BrushRender

/// Metal is device-backed; these skip cleanly on a machine without a usable GPU
/// (headless CI) rather than fail. On a Mac they run for real.
final class BrushCompositorTests: XCTestCase {

    private func makeCompositor() throws -> BrushCompositor {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal device on this machine")
        }
        return try BrushCompositor()
    }

    private func alpha(of image: CGImage, x: Int, y: Int) -> Double {
        guard let data = image.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else {
            return 0
        }
        return Double(ptr[y * image.bytesPerRow + x * 4 + 3]) / 255
    }

    func testStampsPaintWhereTheDabIs() throws {
        let compositor = try makeCompositor()
        let dab = Dab(
            position: CGPoint(x: 64, y: 64), diameter: 60, angle: 0, roundness: 1,
            alpha: 1, hardness: 1, color: RGBA(r: 0, g: 0, b: 0))
        let image = try XCTUnwrap(
            compositor.renderImage(dabs: [dab], size: CGSize(width: 128, height: 128)))
        XCTAssertGreaterThan(alpha(of: image, x: 64, y: 64), 0.9, "the dab centre is opaque")
        XCTAssertEqual(alpha(of: image, x: 4, y: 4), 0, accuracy: 0.02, "the corner stays clear")
    }

    /// `clear: false` accumulates — a second batch of dabs paints ON TOP of the
    /// first without wiping it. This is exactly how the app's canvas renderer
    /// commits successive strokes into one texture, so it is worth pinning.
    func testStampAccumulatesWhenNotClearing() throws {
        let compositor = try makeCompositor()
        let device = compositor.device
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 128, height: 128, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        let target = try XCTUnwrap(device.makeTexture(descriptor: desc))

        func dab(_ x: CGFloat, _ y: CGFloat) -> Dab {
            Dab(
                position: CGPoint(x: x, y: y), diameter: 24, angle: 0, roundness: 1,
                alpha: 1, hardness: 1, color: RGBA(r: 0, g: 0, b: 0))
        }
        compositor.stamp([dab(32, 32)], into: target, clear: true)   // first "stroke"
        compositor.stamp([dab(96, 96)], into: target, clear: false)  // committed on top
        let image = try XCTUnwrap(BrushCompositor.cgImage(from: target))
        XCTAssertGreaterThan(alpha(of: image, x: 32, y: 32), 0.9, "the first stroke survived")
        XCTAssertGreaterThan(alpha(of: image, x: 96, y: 96), 0.9, "the second stroke landed")
    }

    /// Grain: the Metal shader mirrors BrushKit's `GrainNoise`, so a grained dab
    /// lays down less ink than a smooth one on the GPU too — and by a similar
    /// fraction to the CPU reference renderer.
    func testGrainReducesInkAndTracksTheReferenceRenderer() throws {
        let compositor = try makeCompositor()
        let size = CGSize(width: 100, height: 100)
        func dab(grain: Double) -> Dab {
            Dab(
                position: CGPoint(x: 50, y: 50), diameter: 70, angle: 0, roundness: 1,
                alpha: 1, hardness: 1, color: RGBA(r: 0, g: 0, b: 0),
                grainDepth: grain, grainCell: 6, grainSeed: 5)
        }
        func ink(_ image: CGImage) -> Double {
            guard let data = image.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else {
                return 0
            }
            var s = 0.0
            for y in 0..<image.height {
                for x in 0..<image.width { s += Double(ptr[y * image.bytesPerRow + x * 4 + 3]) }
            }
            return s
        }
        let gpuSmooth = ink(try XCTUnwrap(compositor.renderImage(dabs: [dab(grain: 0)], size: size)))
        let gpuGrain = ink(try XCTUnwrap(compositor.renderImage(dabs: [dab(grain: 0.8)], size: size)))
        let cpuSmooth = ink(try XCTUnwrap(ReferenceRenderer.render(dabs: [dab(grain: 0)], size: size)))
        let cpuGrain = ink(try XCTUnwrap(ReferenceRenderer.render(dabs: [dab(grain: 0.8)], size: size)))

        XCTAssertLessThan(gpuGrain, gpuSmooth * 0.9, "GPU grain removes ink")
        // The fraction removed should be close on both renderers (same noise).
        let gpuFraction = gpuGrain / gpuSmooth
        let cpuFraction = cpuGrain / cpuSmooth
        XCTAssertEqual(gpuFraction, cpuFraction, accuracy: 0.1, "GPU and CPU grain agree")
    }

    /// The GPU output should broadly agree with the CPU reference renderer:
    /// paint in the same place, clear in the same place. (Not pixel-identical —
    /// different rasterisers — so this checks coverage agreement, not equality.)
    func testAgreesWithReferenceRendererOnCoverage() throws {
        let compositor = try makeCompositor()
        let input = StrokeInput(samples: [
            StrokeSample(position: CGPoint(x: 20, y: 64)),
            StrokeSample(position: CGPoint(x: 236, y: 64)),
        ])
        var brush = Brush(name: "Flat", tip: Brush.Tip(hardness: 1, spacing: 0.05), size: 30)
        brush.smoothing = 0
        brush.dynamics = Brush.Dynamics(pressureToSize: 0, pressureToOpacity: 0)
        let dabs = BrushEngine.dabs(for: input, brush: brush, color: RGBA(r: 0, g: 0, b: 0))
        let size = CGSize(width: 256, height: 128)

        let gpu = try XCTUnwrap(compositor.renderImage(dabs: dabs, size: size))
        let cpu = try XCTUnwrap(ReferenceRenderer.render(dabs: dabs, size: size))
        // Both paint the stroke centre and leave the top corner clear.
        XCTAssertGreaterThan(alpha(of: gpu, x: 128, y: 64), 0.8)
        XCTAssertGreaterThan(alpha(of: cpu, x: 128, y: 64), 0.8)
        XCTAssertEqual(alpha(of: gpu, x: 128, y: 4), 0, accuracy: 0.05)
        XCTAssertEqual(alpha(of: cpu, x: 128, y: 4), 0, accuracy: 0.05)
    }
}
