import BrushKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// A tiny headless harness for the brush engine: renders a canonical S-curve
// stroke with each built-in brush to PNGs, so the engine can be eyeballed and
// regression-compared without an app or Metal.
//
//   swift run brush <output-dir>
//
// Mirrors FekthorKit's `fekthor` CLI role.

let args = CommandLine.arguments
let outDir = args.count > 1 ? URL(fileURLWithPath: args[1]) : URL(fileURLWithPath: ".")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

/// A pressure-swelling S-curve across a 512×256 canvas, so taper, spacing and
/// pressure→size all show. Pressure rises then falls (a natural stroke).
func canonicalStroke() -> StrokeInput {
    var samples: [StrokeSample] = []
    let count = 64
    for i in 0...count {
        let t = Double(i) / Double(count)
        let x = 24 + t * 464
        let y = 128 + sin(t * .pi * 2) * 70
        let pressure = sin(t * .pi)  // 0 → 1 → 0
        samples.append(
            StrokeSample(
                position: CGPoint(x: x, y: y), pressure: max(0.05, pressure),
                timestamp: t * 0.5))
    }
    return StrokeInput(samples: samples)
}

func writePNG(_ image: CGImage, to url: URL) {
    guard
        let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let stroke = canonicalStroke()
let ink = RGBA(r: 0.1, g: 0.12, b: 0.16)
let size = CGSize(width: 512, height: 256)

for brush in BrushLibrary.all {
    guard
        let image = ReferenceRenderer.render(
            stroke: stroke, brush: brush, color: ink, size: size,
            background: RGBA(r: 1, g: 1, b: 1), seed: 42)
    else {
        FileHandle.standardError.write(Data("render failed: \(brush.name)\n".utf8))
        continue
    }
    let url = outDir.appendingPathComponent("\(brush.id).png")
    writePNG(image, to: url)
    let dabCount = BrushEngine.dabs(for: stroke, brush: brush, color: ink, seed: 42).count
    print("\(brush.name): \(dabCount) dabs → \(url.lastPathComponent)")
}
