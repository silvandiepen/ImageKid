// swift-tools-version: 5.10
import PackageDescription

// InkaKit — Inka's document & workflow model (UI-free, tested).
//
// The hybrid canvas: layers that are either editable brush strokes (rendered
// non-destructively through BrushKit), flat raster, or an imported image. Owns
// the `.inka` workfile and the brush-preset table; the shared painting lives in
// BrushKit/BrushRender, so this stays Inka-specific and CPU-testable.
let package = Package(
    name: "InkaKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "InkaKit", targets: ["InkaKit"]),
        .executable(name: "inka", targets: ["inka"]),
    ],
    dependencies: [
        .package(path: "../BrushKit"),
        .package(path: "../ImageKidCore"),
    ],
    targets: [
        .target(
            name: "InkaKit",
            dependencies: [
                "BrushKit",
                .product(name: "ImageKidCore", package: "ImageKidCore"),
            ]),
        .executableTarget(name: "inka", dependencies: ["InkaKit"]),
        .testTarget(name: "InkaKitTests", dependencies: ["InkaKit"]),
    ],
    swiftLanguageVersions: [.v5]
)
