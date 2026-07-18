# iOS feasibility: upscaling and background removal

This document records whether an iOS build of ImageKid can offer the same
upscaling and background-removal capabilities as the macOS app, and what it
would take. It reflects the shipping macOS implementation, not planned work.

## How the macOS app works today

Both features are two-tier: a built-in engine using Apple frameworks, and an
optional "Best Quality" engine that downloads a runtime and executes it as a
subprocess.

| Feature | Built-in engine | Best Quality engine |
| --- | --- | --- |
| Background removal | Apple Vision `VNGenerateForegroundInstanceMaskRequest`, on-device | Downloads the `isnet-general-use` ONNX model (~178 MB), builds a Python virtual environment, `pip install rembg`, and runs the `rembg` CLI through `Process()` |
| Upscaling | Core Image Lanczos plus unsharp masking for text and UI content | Downloads the Real-ESRGAN `ncnn-vulkan` executable and `realesrgan-x4plus` model weights, then runs the executable through `Process()` |

The Best Quality engines share one mechanism: **download a native runtime at
run time and launch it as a child process.** The downloaded artefacts are
executable code (a compiled Vulkan binary; a Python interpreter environment
and pip packages), not just data.

Source: `UpscaleService.swift`, `BackgroundRemovalService.swift`, and
`BackgroundRemovalModelManager.swift`.

## Why the Best Quality mechanism cannot move to iOS

The download-a-runtime-and-exec-it pattern hits four hard iOS limits:

1. **No subprocesses.** `Process` / `NSTask` does not exist on iOS. There is
   no way to launch `realesrgan-ncnn-vulkan` or the `rembg` CLI.
2. **No downloading and executing code.** App Store Review Guideline 2.5.2
   prohibits downloading executable code — native binaries, a Python
   interpreter, or pip packages. This is a rejection, not a technicality.
3. **No system Python.** iOS has no `/usr/bin/python3`; `venv` and `pip` have
   nothing to bootstrap from.
4. **No Vulkan.** iOS is Metal-only. The `ncnn-vulkan` binary is the wrong
   backend for the platform even before the download problem.

Downloading the *model weights* (the `.onnx` file, the `.param` / `.bin`
files) remains allowed — those are data. Only the runtime/executable half is
impossible.

## The iOS-compatible approach: Core ML

The same user-facing behaviour (a fast built-in tier plus an optional
higher-quality tier) is achievable by changing the engine, not the feature.

- **Built-in background removal ports directly.** Vision's foreground instance
  mask request is available on iOS 17+. The code is nearly identical.
- **Built-in upscaling ports directly.** Core Image (`CILanczosScaleTransform`,
  `CIUnsharpMask`) runs unchanged on iOS. MetalFX spatial upscaling is an
  additional native option.
- **Best Quality becomes an in-process Core ML model.** Convert the same
  networks to Core ML (`.mlpackage`) with `coremltools` and run them through
  Core ML / Vision on the Neural Engine or GPU. The download, if any, is then
  just model weights — allowed — delivered by bundling, On-Demand Resources,
  or Background Assets. No executable, no Python, no subprocess.

### "Can we make a Swift build of Real-ESRGAN for iOS?"

Not in the literal sense. Real-ESRGAN `ncnn-vulkan` is a C++ program built on
the ncnn inference framework with a Vulkan compute backend; it is not Swift,
and Swift is not the blocker. Two real options exist:

- **Convert the model to Core ML (recommended).** The Real-ESRGAN generator is
  a fully-convolutional RRDBNet. Converting the `realesrgan-x4plus` weights to
  a `.mlpackage` runs the identical network through Apple's inference stack.
- **Statically compile ncnn into the app.** ncnn can be built for iOS with a
  Metal-translation layer (MoltenVK over Vulkan), with the `.param` / `.bin`
  weights bundled. This keeps the exact same runtime and output but adds build
  weight and complexity, and it must be compiled into the app at build time —
  it still cannot be downloaded and executed.

Either way the inference runs in-process from a build-time or bundled artefact,
never from a downloaded executable.

### Will the quality be the same?

Yes, when the same weights are used. Image quality is a property of the model,
not the runtime. Running `realesrgan-x4plus` through Core ML instead of
`ncnn-vulkan` produces essentially identical output; Core ML FP16 execution can
introduce tiny numerical differences that are not visible. The tiling pass and
the tile-corruption retry loop in `UpscaleService` are separate scaffolding
that would be reimplemented around the Core ML inference, not part of the model
quality itself.

The same logic applies to background removal: converting `isnet-general-use`
to Core ML reproduces the macOS Best Quality mask, because it is the same
network. Apple Vision remains the fast built-in tier on both platforms, but it
is a different (Apple) model and does not match ISNet output exactly.

## Should macOS adopt Core ML too?

Recommended: yes. Moving macOS from the downloaded `ncnn-vulkan` binary and the
`rembg` Python runtime to Core ML would let both platforms share one inference
path, and it removes the parts of the current design that are hardest to ship
and maintain:

- No runtime binary download, no unzip step, no Vulkan dependency, no Python
  virtual environment or pip install, no subprocess management, no
  runtime-integrity manifest.
- Inference on the Neural Engine or GPU, with faster cold start.
- Alignment with existing principles the current runtime-download approach
  contradicts — "Apple frameworks first" (D-007) and offline operation without
  a separately installed runtime.

Costs to weigh: converting and validating each model, bundling the Core ML
weights (or delivering them as data via On-Demand Resources / Background
Assets), handling flexible input shapes or tiling for Real-ESRGAN, and
verifying that converted output matches the current runtime on representative
images.

## Summary

- Same features and same fast-plus-better UX on iOS: achievable.
- Same mechanism (download a CLI or Python runtime and exec it): impossible on
  iOS and disqualifying under App Store review.
- Same quality: yes, when the same model weights run through Core ML.
- Recommended direction: convert Real-ESRGAN and ISNet to Core ML, run them
  in-process on both platforms, and retire the downloaded-runtime approach on
  macOS so the two apps share one engine.

## Scaffolding

A first cut of the shared engine exists in `packages/ImageKidInference` — a
cross-platform (macOS 14+, iOS 17+) Swift package that runs both features
through Core ML / Vision / Core Image in-process, with no subprocess or
downloaded executable. It provides `CoreMLUpscaler` (Real-ESRGAN, tiled),
`CoreMLBackgroundRemover` (ISNet), and the `CoreImageUpscaler` /
`VisionBackgroundRemover` built-in fallbacks, behind a `ModelProvider` seam so
the model-storage strategy (runtime download, bundled, or On-Demand Resources)
stays open. The Core ML models are generated by `tools/coreml-conversion` from
the same published weights the macOS app downloads today; they are not committed
to the repository. The package is not yet wired into `apps/native-macos`, and it
builds only on macOS (it needs Apple frameworks).

A first iOS app consuming the package lives in `apps/native-ios` — a SwiftUI
app (iOS 17+, generated with XcodeGen) that picks a photo, removes its
background or upscales it through `ImageKidInference`, and shares the result.
Built-in engines (Vision, Core Image) work immediately; the Best Quality Core ML
engines light up once the converted models are added to the app bundle. It does
not touch `apps/native-macos`. See `apps/native-ios/README.md`.

## Effort shape

- Built-in tiers (Vision mask, Core Image / MetalFX resize): light port.
- Best Quality tiers: a Core ML rewrite — model conversion plus a Vision /
  Core ML inference path — rather than a lift-and-shift of the current code.
