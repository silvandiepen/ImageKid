# ImageKidInference

Cross-platform (macOS 14+, iOS 17+) on-device image inference for ImageKid:
Best Quality upscaling and background removal, plus the built-in fallbacks.
Everything runs in-process through Apple frameworks — Core ML, Vision, Core
Image — with no subprocess, no Python runtime, and no downloaded executable, so
the same package serves a future iOS app as well as macOS.

The package works entirely in `CGImage` / `CVPixelBuffer` and never imports
AppKit or UIKit, which is what keeps it cross-platform.

## What it provides

| Type | Role |
| --- | --- |
| `CoreImageUpscaler` | Deterministic Lanczos + unsharp upscaling. Always available, no model. Cross-platform equivalent of the app's "Standard" engine. |
| `CoreMLUpscaler` | Real-ESRGAN through Core ML, with overlapped tiling. Replaces the macOS `ncnn-vulkan` subprocess. |
| `VisionBackgroundRemover` | Apple Vision foreground instance mask. Cross-platform equivalent of the "Built-in" engine. |
| `CoreMLBackgroundRemover` | ISNet through Core ML. Replaces the macOS `rembg` Python subprocess; matches its min-max mask normalisation. |
| `ModelProvider` | Where the Core ML model comes from. `BundledModelProvider` for app-bundled / On-Demand Resources; `PackageModelProvider` for a downloaded `.mlpackage`. |
| `TilePlanner` | Pure-geometry overlapped tiling used by `CoreMLUpscaler`. Unit-tested. |

## Model storage is pluggable

The engines depend only on `ModelProvider`, so the model-storage decision stays
open:

- **Runtime download** (matches today's macOS UX): download the `.mlpackage`
  into Application Support and use `PackageModelProvider`. First load compiles
  it on-device once and caches the result.
- **Bundled / On-Demand Resources**: ship the model in the app (Xcode compiles
  it to `.mlmodelc`) and use `BundledModelProvider`.

## Usage

```swift
import ImageKidInference

// Best Quality upscale from a downloaded model.
let provider = PackageModelProvider(packageURL: downloadedRealESRGANURL)
let upscaler = CoreMLUpscaler(modelProvider: provider)
let enlarged = try await upscaler.upscale(sourceCGImage, to: targetSize) { progress in
    // progress.detail, progress.fraction — hop to the main actor to show it
}

// Best Quality background removal from a bundled model.
let isnet = BundledModelProvider(name: "ISNet", bundle: .main)
let remover = CoreMLBackgroundRemover(modelProvider: isnet)
let cutout = try await remover.removeBackground(from: sourceCGImage)

// Built-in fallbacks (no model):
let standard = try await CoreImageUpscaler(sharpening: .textAndUI).upscale(sourceCGImage, to: targetSize)
let visionCutout = try await VisionBackgroundRemover().removeBackground(from: sourceCGImage)
```

## Producing the models

The Core ML models are not committed here — they are generated from the
published weights by the scripts in
[`tools/coreml-conversion`](../../tools/coreml-conversion). The feature names
and sizes those scripts emit must match `CoreMLUpscalerConfiguration` and
`CoreMLBackgroundRemoverConfiguration`.

## Building

This package requires Apple frameworks (Core ML, Vision, Core Image) and builds
only on macOS with Xcode 16 / Swift 5.10+:

```bash
cd packages/ImageKidInference
swift build
swift test        # runs the TilePlanner geometry tests
```

It cannot be built on Linux. The unit tests cover the tiling geometry and mask
shape handling; the model-dependent paths require a device or Mac with the
converted models present.

## Integration

`apps/native-macos` does not yet depend on this package. To adopt it, add it as
a local package dependency and route `UpscaleService` / `BackgroundRemovalService`
through these engines, replacing the downloaded `ncnn-vulkan` and `rembg`
runtimes. See `docs/ios-feasibility.md` for the migration rationale.
