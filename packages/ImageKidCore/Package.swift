// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ImageKidCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "ImageKidCore", targets: ["ImageKidCore"])
    ],
    targets: [
        .target(name: "ImageKidCore", path: "Sources/ImageKidCore")
    ],
    swiftLanguageVersions: [.v5]
)
