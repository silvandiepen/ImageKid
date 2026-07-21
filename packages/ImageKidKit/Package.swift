// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ImageKidKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "ImageKidKit", targets: ["ImageKidKit"])
    ],
    targets: [
        .target(name: "ImageKidKit", path: "Sources/ImageKidKit")
    ],
    swiftLanguageVersions: [.v5]
)
