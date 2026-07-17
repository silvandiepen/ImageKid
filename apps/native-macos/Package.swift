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
    targets: [
        .executableTarget(
            name: "ImageKid",
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
