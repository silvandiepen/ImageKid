// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ImageKidInference",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "ImageKidInference", targets: ["ImageKidInference"])
    ],
    targets: [
        .target(
            name: "ImageKidInference",
            path: "Sources/ImageKidInference"
        ),
        .testTarget(
            name: "ImageKidInferenceTests",
            dependencies: ["ImageKidInference"],
            path: "Tests/ImageKidInferenceTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
