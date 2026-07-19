import CoreGraphics
import CoreML
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ImageKidInference

/// Renders a side-by-side montage comparing the background-removal models on one
/// real photo, so their edge quality can be judged visually. Opt-in via env:
///   IMAGEKID_MODELS_DIR  — folder with ISNet/BiRefNet/U2Net .mlpackage files
///   IMAGEKID_TEST_IMAGE  — path to a source photo (a portrait with hair works best)
///   IMAGEKID_MONTAGE_OUT — path to write the comparison PNG
final class BackgroundModelComparisonTests: XCTestCase {
    private struct ModelSpec {
        let name: String
        let file: String
        let inputSize: CGFloat
    }

    private let specs = [
        ModelSpec(name: "BiRefNet-lite", file: "BiRefNet.mlpackage", inputSize: 1024),
        ModelSpec(name: "U\u{00B2}-Net", file: "U2Net.mlpackage", inputSize: 320)
    ]

    /// BiRefNet must run in fp32 on the CPU: the Neural Engine and GPU run it in
    /// fp16 and overflow on high-activation regions, returning NaNs.
    private func fp32Configuration() -> MLModelConfiguration {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        return configuration
    }

    func testRenderComparisonMontage() async throws {
        let env = ProcessInfo.processInfo.environment
        guard
            let dir = env["IMAGEKID_MODELS_DIR"],
            let imagePath = env["IMAGEKID_TEST_IMAGE"],
            let outPath = env["IMAGEKID_MONTAGE_OUT"]
        else {
            throw XCTSkip("Set IMAGEKID_MODELS_DIR, IMAGEKID_TEST_IMAGE and IMAGEKID_MONTAGE_OUT.")
        }
        let modelsDir = URL(fileURLWithPath: dir, isDirectory: true)
        let source = try loadImage(URL(fileURLWithPath: imagePath))

        var tiles: [(title: String, subtitle: String, image: CGImage)] = [
            (title: "Original", subtitle: "\(source.width)\u{00D7}\(source.height)", image: source)
        ]

        for spec in specs {
            let package = modelsDir.appendingPathComponent(spec.file)
            guard FileManager.default.fileExists(atPath: package.path) else {
                print("SKIP \(spec.name): \(spec.file) missing")
                continue
            }
            let remover = CoreMLBackgroundRemover(
                modelProvider: PackageModelProvider(packageURL: package, configuration: fp32Configuration()),
                configuration: CoreMLBackgroundRemoverConfiguration(
                    inputSize: CGSize(width: spec.inputSize, height: spec.inputSize)
                )
            )
            // Warm the model (first call compiles + loads), then time inference.
            _ = try await remover.removeBackground(from: source)
            let start = ContinuousClock.now
            let cutout = try await remover.removeBackground(from: source)
            let ms = Int(Double((ContinuousClock.now - start).components.attoseconds) / 1e15)
            let sizeMB = directorySizeMB(package)
            tiles.append((
                title: spec.name,
                subtitle: "\(sizeMB) MB \u{00B7} \(ms) ms",
                image: cutout
            ))
            print("\(spec.name): \(sizeMB) MB, \(ms) ms warm inference")
        }

        let montage = try renderMontage(tiles)
        try writePNG(montage, to: URL(fileURLWithPath: outPath))
        print("MONTAGE written to \(outPath) (\(montage.width)\u{00D7}\(montage.height))")
    }

    // MARK: - Montage rendering (bottom-left CoreGraphics coordinate space)

    private func renderMontage(_ tiles: [(title: String, subtitle: String, image: CGImage)]) throws -> CGImage {
        let cols = 2
        let cellW = 560
        let imgH = 470
        let labelH = 54
        let pad = 28
        let cellH = imgH + labelH
        let rows = (tiles.count + cols - 1) / cols
        let canvasW = pad + cols * cellW + (cols - 1) * pad + pad
        let canvasH = pad + rows * cellH + (rows - 1) * pad + pad

        guard let ctx = CGContext(
            data: nil, width: canvasW, height: canvasH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw XCTSkip("Could not create montage context.") }

        ctx.setFillColor(CGColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: canvasW, height: canvasH))

        for (index, tile) in tiles.enumerated() {
            let col = index % cols
            let row = index / cols
            let cellX = pad + col * (cellW + pad)
            let cellTopFromTop = pad + row * (cellH + pad)
            // Convert top-origin to bottom-left origin.
            let cellBottomY = canvasH - cellTopFromTop - cellH

            let imageRect = CGRect(x: cellX, y: cellBottomY + labelH, width: cellW, height: imgH)
            drawCheckerboard(in: imageRect, ctx: ctx)
            let fitted = aspectFit(CGSize(width: tile.image.width, height: tile.image.height), into: imageRect)
            ctx.draw(tile.image, in: fitted)

            // Label bar at the bottom of the cell.
            let labelRect = CGRect(x: cellX, y: cellBottomY, width: cellW, height: labelH)
            ctx.setFillColor(CGColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1))
            ctx.fill(labelRect)
            drawText(tile.title, in: ctx, x: CGFloat(cellX) + 16, baselineY: CGFloat(cellBottomY) + 32,
                     size: 22, weight: 0.3, color: CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            drawText(tile.subtitle, in: ctx, x: CGFloat(cellX) + 16, baselineY: CGFloat(cellBottomY) + 11,
                     size: 15, weight: 0, color: CGColor(red: 0.66, green: 0.68, blue: 0.72, alpha: 1))
        }

        guard let image = ctx.makeImage() else { throw XCTSkip("Could not finalize montage.") }
        return image
    }

    private func aspectFit(_ size: CGSize, into rect: CGRect) -> CGRect {
        let scale = min(rect.width / size.width, rect.height / size.height)
        let w = size.width * scale
        let h = size.height * scale
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }

    private func drawCheckerboard(in rect: CGRect, ctx: CGContext) {
        let cell = 16
        ctx.saveGState()
        ctx.clip(to: rect)
        let light = CGColor(red: 0.82, green: 0.82, blue: 0.84, alpha: 1)
        let dark = CGColor(red: 0.68, green: 0.68, blue: 0.70, alpha: 1)
        var y = Int(rect.minY)
        var rowIndex = 0
        while y < Int(rect.maxY) {
            var x = Int(rect.minX)
            var colIndex = 0
            while x < Int(rect.maxX) {
                ctx.setFillColor((rowIndex + colIndex) % 2 == 0 ? light : dark)
                ctx.fill(CGRect(x: x, y: y, width: cell, height: cell))
                x += cell; colIndex += 1
            }
            y += cell; rowIndex += 1
        }
        ctx.restoreGState()
    }

    private func drawText(_ string: String, in ctx: CGContext, x: CGFloat, baselineY: CGFloat,
                          size: CGFloat, weight: CGFloat, color: CGColor) {
        let font = CTFontCreateWithName("HelveticaNeue-Medium" as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let attributed = NSAttributedString(string: string, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)
        ctx.textPosition = CGPoint(x: x, y: baselineY)
        CTLineDraw(line, ctx)
    }

    // MARK: - IO

    private func loadImage(_ url: URL) throws -> CGImage {
        guard
            let src = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { throw XCTSkip("Could not load test image at \(url.path).") }
        return image
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw XCTSkip("Could not create PNG destination.")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw XCTSkip("Could not write PNG.") }
    }

    private func directorySizeMB(_ url: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        var bytes = 0
        for case let fileURL as URL in enumerator {
            bytes += (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return bytes / 1_000_000
    }
}
