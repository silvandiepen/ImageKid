// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ImageKid",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ImageKid", targets: ["ImageKid"]),
        .executable(name: "ImageKidSlicer", targets: ["ImageKidSlicer"])
    ],
    dependencies: [
        .package(path: "../../packages/ImageKidInference"),
        .package(path: "../../packages/ImageKidKit"),
        .package(path: "../../packages/ImageKidCore")
    ],
    targets: [
        .executableTarget(
            name: "ImageKid",
            dependencies: [
                .product(name: "ImageKidInference", package: "ImageKidInference"),
                .product(name: "ImageKidKit", package: "ImageKidKit"),
                .product(name: "ImageKidCore", package: "ImageKidCore")
            ],
            path: "Sources/ImageKid",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "ImageKidSlicer",
            dependencies: [
                .product(name: "ImageKidCore", package: "ImageKidCore"),
                .product(name: "ImageKidKit", package: "ImageKidKit")
            ],
            path: "Sources/ImageKidSlicer",
            exclude: ["ImageKidSlicer.entitlements", "Info.plist", "PrivacyInfo.xcprivacy"]
        ),
        .testTarget(
            name: "ImageKidTests",
            dependencies: [
                "ImageKid",
                .product(name: "ImageKidCore", package: "ImageKidCore")
            ],
            path: "Tests/ImageKidTests"
        ),
        .testTarget(
            name: "ImageKidSlicerTests",
            dependencies: ["ImageKidSlicer"],
            path: "Tests/ImageKidSlicerTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
