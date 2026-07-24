// swift-tools-version: 5.10
import PackageDescription

// BrushKit — the family's shared, app-neutral brush engine.
//
// A portable, UI-free painting core: brush presets (.inkbrush), captured stroke
// input with smoothing, deterministic stamp-based dab generation, and a
// CoreGraphics reference renderer. The live GPU path lives in BrushRender; this
// package stays CPU-testable so both Inka and (later) ImageKid can build on it.
let package = Package(
    name: "BrushKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "BrushKit", targets: ["BrushKit"]),
        .executable(name: "brush", targets: ["brush"]),
    ],
    dependencies: [
        .package(path: "../ImageKidCore")
    ],
    targets: [
        .target(
            name: "BrushKit",
            dependencies: [.product(name: "ImageKidCore", package: "ImageKidCore")],
            // The dab loop is per-sample math; keep it optimised even in Debug,
            // like FekthorKit does for its per-pixel passes.
            swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))]),
        .executableTarget(name: "brush", dependencies: ["BrushKit"]),
        .testTarget(name: "BrushKitTests", dependencies: ["BrushKit"]),
    ],
    swiftLanguageVersions: [.v5]
)
