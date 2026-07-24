// swift-tools-version: 5.10
import PackageDescription

// BrushRender — the family's shared Metal compositor for BrushKit dabs.
//
// The live GPU path: stamp textured dabs into a caller-owned target texture and
// composite layers, at canvas resolution and interactive frame rates. Kept apart
// from BrushKit so the engine stays CPU-testable; both Inka and (later) ImageKid
// route through here. `.metal` shaders compile into the module bundle's
// default.metallib, loaded via `Bundle.module`.
let package = Package(
    name: "BrushRender",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "BrushRender", targets: ["BrushRender"])
    ],
    dependencies: [
        .package(path: "../BrushKit")
    ],
    targets: [
        .target(
            name: "BrushRender",
            dependencies: ["BrushKit"]),
        .testTarget(name: "BrushRenderTests", dependencies: ["BrushRender"]),
    ],
    swiftLanguageVersions: [.v5]
)
