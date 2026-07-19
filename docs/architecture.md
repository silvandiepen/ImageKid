# Technical architecture

## Goals

The architecture must provide exact pixel inspection, smooth native media viewing, reversible edits, deterministic full-resolution export, and frame-accurate video processing while remaining small, offline, and dependency-light.

## Current platform

- Swift 5.10 language mode, prepared for Swift 6 migration.
- Swift Package Manager executable targeting macOS 14.
- SwiftUI application lifecycle, command system, sheets, and floating controls.
- AppKit for file panels, pasteboard, image representation, and future precision canvas work.
- Core Graphics and Core Image for image rendering and effects.
- AVFoundation and AVKit for video loading and playback.
- VideoToolbox for future hardware-assisted video export.
- Image I/O and Uniform Type Identifiers for media decoding, metadata, and format handling.

No third-party runtime dependency is currently required.

## Repository structure

```text
ImageKid/
├── apps/
│   ├── native-macos/
│   │   ├── Package.swift
│   │   ├── Sources/ImageKid/
│   │   └── Tests/ImageKidTests/
│   ├── native-ios/          # SwiftUI iOS app using the Core ML engines
│   └── website/
│       ├── src/
│       │   ├── components/
│       │   ├── composables/
│       │   ├── pages/
│       │   └── styles/
│       └── public/
├── docs/
├── packages/
│   └── ImageKidInference/   # cross-platform Core ML / Vision inference engines
├── tools/
│   └── coreml-conversion/   # scripts that generate the Core ML models
├── package.json
└── package-lock.json
```

The monorepo keeps native product behavior and the static website in separate app boundaries. Native services and domain types should be split further only when their responsibilities become substantial; reusable cross-app code belongs in `packages`.

## Session ownership

Each window instantiates and owns its own `AppModel`, which contains one active `MediaItem`, either an `ImageSession` or `VideoSession`. Focused scene commands resolve the model for the active window. The source remains immutable. The session stores view state and non-destructive edit intent.

Observable UI state may contain lightweight values such as zoom, pan, crop geometry, output dimensions, annotations, and sampled colours. Large pixel buffers and decoded video frames must remain service-owned rather than observable state.

## Coordinate systems

The app must explicitly distinguish encoded source coordinates, orientation-normalised source pixels, working coordinates after crop and resize, video-frame coordinates, canvas coordinates, view coordinates, and Retina backing pixels.

`GeometryMapper` is the shared authority for fitted media geometry and normalised edit coordinates. Picking, crop, annotation, preview, and export must not invent independent conversion paths.

Annotation and crop geometry are stored as normalised values relative to orientation-correct media. UI handles remain view-space decorations.

## Image preview and export

The current scaffold renders with `NSImage`, then applies crop, target dimensions, and annotations during export. The next iteration should separate an immutable downsampled source preview, working preview transforms, interaction overlays, and full-resolution export rendering.

Full-resolution export order:

1. resolve orientation-normalised source pixels;
2. apply crop;
3. apply standard resize;
4. apply blur or pixelation regions;
5. render vector and text annotations at output scale;
6. apply colour-profile and metadata policy;
7. encode atomically.

The app must never export a screenshot of its window.

## Video playback and frame access

Normal playback uses `AVPlayer`. Precision tools require a frame provider that returns an orientation-correct pixel buffer or `CGImage` for the exact displayed timestamp.

While playback is active, the player owns presentation. When the user pauses for sampling or annotation, the workspace should use a stable decoded frame representation so pointer interaction and pixel access cannot race with playback.

## Video processing pipeline

Use a bounded streaming pipeline:

1. `AVAssetReader` reads video samples in presentation order.
2. Frame transforms normalise orientation.
3. Crop and standard resize are applied.
4. Visible annotations and region effects are composited for the frame timestamp.
5. `AVAssetWriter` writes each frame using the intended presentation timestamp.
6. Audio is passed through where compatible or re-encoded locally.
7. Output is finalised atomically and moved to the user-selected URL only on success.

Do not materialise an entire clip as image files unless a bounded fallback is explicitly required.

## Concurrency

- UI state changes stay on the main actor.
- Image decoding, palette extraction, full-resolution rendering, video frame decoding, and export run away from the main actor.
- Cancellation is represented explicitly and checked between expensive operations.
- Services avoid unbounded task creation and large retained frame queues.

## Package versus distributable app

The Swift package is the current build and test foundation. A distributable product still requires:

- bundle identifier and versioning;
- app icon and asset catalogue;
- App Sandbox entitlements and user-selected file access;
- signing and hardened runtime;
- archive configuration;
- notarisation or App Store metadata.

Buildability and distribution readiness are separate milestones.

## Best Quality add-on architecture

Two opt-in Best Quality add-ons run alongside the built-in engines. AI upscaling uses an app-managed Real-ESRGAN `ncnn-vulkan` runtime with a tile planner and corruption-retry pass; AI background removal uses a downloaded ONNX model plus a locally built `rembg` Python runtime. Both are downloaded on demand, stored in Application Support, and executed on-device as subprocesses. See `apps/native-macos/Sources/ImageKid/UpscaleService.swift` and `BackgroundRemovalService.swift`.

This downloaded-runtime approach is macOS-specific and does not port to iOS. The intended cross-platform direction is Core ML inference in-process, which would also let macOS retire the binary download, the Vulkan dependency, and the Python runtime. See `ios-feasibility.md`.

The `packages/ImageKidInference` Swift package scaffolds that direction: cross-platform (macOS 14+, iOS 17+) `CGImage`-based engines for both features — `CoreMLUpscaler` (Real-ESRGAN), `CoreMLBackgroundRemover` (ISNet), and the `VisionBackgroundRemover` / `CoreImageUpscaler` built-in fallbacks — behind a `ModelProvider` seam that keeps the model-storage strategy pluggable. It is not yet wired into `apps/native-macos`. The models are generated by `tools/coreml-conversion` and are not committed.
