# ImageKid for iOS

A SwiftUI iOS app (iOS 17+) that runs ImageKid's upscaling and background
removal through the shared [`ImageKidInference`](../../packages/ImageKidInference)
package — entirely on-device, no subprocess, no downloaded executable.

Pick a photo, edit it, and export. It does not touch `apps/native-macos`.

## What it does

- **Remove background** — Built-in (Apple Vision) always; Best Quality (ISNet
  via Core ML) when the model is bundled.
- **Refine cutout** — Erase / Restore brushes to fix a mask by hand (also a
  plain eraser).
- **Upscale** — 2× Standard (Core Image) always; 4× Best Quality (Real-ESRGAN
  via Core ML) when the model is bundled.
- **Crop** — draggable handles, movable region, aspect presets.
- **Resize** — exact width/height with aspect lock, percentage presets.
- **Annotate** — rectangle, ellipse, line, arrow, freehand, and text with
  colour and thickness.
- **Colour picker** — sample pixels, save swatches, copy HEX / RGB.
- **View** — pinch zoom, pan, double-tap reset, checkerboard for transparency.
- **Export** — PNG / JPEG / HEIC with quality, Save to Photos, or Share.

Edits compose: each operation acts on the current working image, and Reset
returns to the original photo.

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
    ├── ContentView.swift             # tool sections, preview, sheets
    ├── InferenceModel.swift          # working-image state and edit pipeline
    ├── ImageIO.swift                 # UIImage <-> CGImage, resize, share file
    ├── ZoomableImageView.swift       # pinch zoom / pan viewer
    ├── ImageExport.swift             # encode PNG/JPEG/HEIC, save to Photos
    ├── ExportView.swift              # export sheet
    ├── CropView.swift                # crop editor
    ├── ResizeView.swift              # resize editor
    ├── Annotation.swift              # annotation model + rasterizer
    ├── AnnotateView.swift            # annotation editor
    ├── ColorSample.swift             # pixel sampler + colour model
    ├── ColorSampleView.swift         # colour picker
    └── RefineView.swift              # cutout refinement brushes
```
