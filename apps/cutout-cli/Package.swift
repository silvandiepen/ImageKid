// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "cutout",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "cutout", targets: ["cutout"])
    ],
    dependencies: [
        .package(path: "../../packages/ImageKidInference")
    ],
    targets: [
        .executableTarget(
            name: "cutout",
            dependencies: [
                .product(name: "ImageKidInference", package: "ImageKidInference")
            ],
            path: "Sources/cutout"
        ),
        .testTarget(
            name: "cutoutTests",
            dependencies: ["cutout"],
            path: "Tests/cutoutTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
