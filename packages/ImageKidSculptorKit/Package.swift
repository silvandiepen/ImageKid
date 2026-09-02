// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ImageKidSculptorKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ImageKidSculptorKit", targets: ["ImageKidSculptorKit"])
    ],
    targets: [
        .target(
            name: "ImageKidSculptorKit",
            path: "Sources/ImageKidSculptorKit"
        ),
        .testTarget(
            name: "ImageKidSculptorKitTests",
            dependencies: ["ImageKidSculptorKit"],
            path: "Tests/ImageKidSculptorKitTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
