import BrushKit
import CoreGraphics
import Foundation
import ImageIO
import InkaKit
import UniformTypeIdentifiers

// Headless InkaKit harness: build a two-layer document (a stroke over a tint),
// round-trip it through `.inka`, and flatten to a PNG — proving the document,
// codec and non-destructive rasterizer end to end without an app.
//
//   swift run inka <output-dir>

let outDir =
    CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1]) : URL(fileURLWithPath: ".")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

var doc = InkaDocument.blank(width: 512, height: 256)

// A pressure-swelling stroke on the default layer.
var samples: [StrokeSample] = []
for i in 0...48 {
    let t = Double(i) / 48
    samples.append(
        StrokeSample(
            position: CGPoint(x: 24 + t * 464, y: 128 + sin(t * .pi * 2) * 60),
            pressure: max(0.05, sin(t * .pi)), timestamp: t * 0.4))
}
let stroke = BrushStroke(
    brushID: BrushLibrary.pencil.id, color: RGBA(r: 0.1, g: 0.12, b: 0.16),
    input: StrokeInput(samples: samples), seed: 7)
doc.layers[0].content = .strokes([stroke])

// Round-trip through the workfile.
let data = try InkaWorkfile.encode(doc)
try data.write(to: outDir.appendingPathComponent("demo.inka"))
let reloaded = try InkaWorkfile.decode(data)
print("workfile: \(data.count) bytes, \(reloaded.layers.count) layer(s)")

// Flatten and write a PNG.
if let image = InkaRasterizer.flatten(reloaded),
    let dest = CGImageDestinationCreateWithURL(
        outDir.appendingPathComponent("demo.png") as CFURL, UTType.png.identifier as CFString, 1,
        nil)
{
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("flattened → demo.png (\(image.width)×\(image.height))")
} else {
    FileHandle.standardError.write(Data("flatten failed\n".utf8))
}
