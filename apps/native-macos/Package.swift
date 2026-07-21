// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ImageKid",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ImageKid", targets: ["ImageKid"])
    ],
    dependencies: [
        .package(path: "../../packages/ImageKidInference"),
        .package(path: "../../packages/ImageKidKit")
    ],
    targets: [
        .executableTarget(
            name: "ImageKid",
            dependencies: [
                .product(name: "ImageKidInference", package: "ImageKidInference"),
                .product(name: "ImageKidKit", package: "ImageKidKit")
            ],
            path: "Sources/ImageKid",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ImageKidTests",
            dependencies: ["ImageKid"],
            path: "Tests/ImageKidTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
