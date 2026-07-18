# ImageKid for iOS

A SwiftUI iOS app (iOS 17+) that runs ImageKid's upscaling and background
removal through the shared [`ImageKidInference`](../../packages/ImageKidInference)
package — entirely on-device, no subprocess, no downloaded executable.

This is a focused first target: pick a photo, remove its background or upscale
it, and share the result. It deliberately does not reimplement the macOS app's
viewer, crop, resize, or annotation tools yet, and it does not touch
`apps/native-macos`.

## What it does

- **Remove background** — Built-in (Apple Vision) always; Best Quality (ISNet
  via Core ML) when the model is bundled.
- **Upscale** — 2× Standard (Core Image) always; 4× Best Quality (Real-ESRGAN
  via Core ML) when the model is bundled.
- **Share** the result as a PNG (alpha preserved).

## Requirements

- macOS with Xcode 16+, Swift 5.10+.
- [XcodeGen](https://github.com/yonyz/XcodeGen) to generate the project.

This app cannot be built on Linux; it needs the iOS SDK and Apple frameworks.

## Build and run

```bash
cd apps/native-ios
xcodegen generate          # or: npm run ios:project  (from the repo root)
open ImageKidiOS.xcodeproj
```

Select an iOS 17+ simulator or device and run. The generated project resolves
the local `ImageKidInference` package automatically.

## Enabling Best Quality

The Core ML models are not committed. Generate them and add them to the target:

1. Produce `RealESRGAN.mlpackage` and `ISNet.mlpackage` with the scripts in
   [`tools/coreml-conversion`](../../tools/coreml-conversion).
2. Drag both into the `ImageKidiOS` target in Xcode (Xcode compiles each
   `.mlpackage` to an `.mlmodelc` in the app bundle).
3. Rebuild. The Best Quality buttons enable automatically once
   `BundledModelProvider` finds `RealESRGAN.mlmodelc` and `ISNet.mlmodelc`.

The feature names/sizes the scripts emit must match `CoreMLUpscalerConfiguration`
and `CoreMLBackgroundRemoverConfiguration` in the package.

## Structure

```text
apps/native-ios/
├── project.yml                       # XcodeGen project (local package dependency)
└── Sources/ImageKidiOS/
    ├── ImageKidApp.swift             # @main App entry
    ├── ContentView.swift             # photo picker, actions, preview, share
    ├── InferenceModel.swift          # wires the UI to ImageKidInference
    └── ImageIO.swift                 # UIImage <-> CGImage, PNG share file
```
