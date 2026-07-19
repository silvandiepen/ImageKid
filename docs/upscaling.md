# Upscaling

ImageKid provides two upscaling paths.

## Standard (built-in)

Deterministic high-quality interpolation using Core Image (Lanczos scaling with
unsharp masking for text and UI content). Always available, offline, no
download.

## Best Quality (optional add-on)

Optional AI upscaling through an app-managed local Real-ESRGAN `ncnn-vulkan`
runtime. The runtime and `realesrgan-x4plus` model weights are downloaded from
Settings, stored in Application Support, and executed on-device as a subprocess
during exports that enlarge the cropped source. It is opt-in, runs locally, and
makes no cloud or paid-API calls.

Source: `apps/native-macos/Sources/ImageKid/UpscaleService.swift`.

## Direction

The download-a-runtime-and-execute approach is macOS-specific and cannot move
to iOS (no subprocesses; App Store review prohibits downloading executable
code; no Vulkan). The intended direction is to convert the same model to Core
ML and run inference in-process on both platforms, which also lets macOS retire
the downloaded runtime. See [ios-feasibility.md](ios-feasibility.md).

## History

Earlier documentation deferred AI upscaling entirely and treated any local
model runtime as out of scope. That guidance is superseded by the shipping
Best Quality add-on described above.
