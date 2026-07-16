# ImageKid

ImageKid is a small, native macOS utility for viewing, inspecting, resizing, upscaling, cropping, and annotating images and basic video.

The product is intentionally image- and video-first. Drop, paste, or open a file and it appears immediately. The media fills the window like Quick Look or Preview. Moving the pointer reveals a compact floating action bar; the same commands are available through the macOS menu bar and keyboard shortcuts.

ImageKid is not a timeline editor, photo suite, or Photoshop replacement. It handles the common media tasks that should not require opening a large application.

## Core capabilities

- View images and videos in a clean native window.
- Zoom, pan, play, pause, scrub, and inspect individual video frames.
- Pick exact colours from an image or the current video frame.
- Collect sampled colours and extract dominant palettes.
- Crop and resize images or complete video clips.
- Upscale images and video locally using bundled open-source models.
- Add text, arrows, lines, shapes, freehand strokes, numbered markers, blur, and pixelation.
- Give video annotations an optional start and end time without introducing a full editing timeline.
- Copy images or video frames and export the processed result.

## Offline by design

ImageKid must work without an internet connection.

- No account.
- No cloud processing.
- No paid API or SDK.
- No model downloads after installation.
- No third-party analytics.
- Media never leaves the Mac.
- Open-source model weights required by the product are included in the application bundle.

AI upscaling is implemented through an internal provider interface, but the first and default provider is entirely local. The intended runtime is Core ML so inference can use the CPU, GPU, and Neural Engine available on the Mac.

## Initial upscaling direction

The first practical implementation should use a converted Real-ESRGAN-family model for general images and frame-based video upscaling. A smaller illustration/anime model may also be bundled. Frame-by-frame processing is predictable and shippable, but may produce temporal flicker in difficult video.

A true temporal video super-resolution model such as BasicVSR++ is a later quality tier. It should only be bundled after conversion, memory use, licensing, and Apple Silicon performance have been validated. It must never require Python, PyTorch, a server, or an internet connection at runtime.

## Proposed native stack

- Swift 6
- SwiftUI for the application shell, menus, sheets, and floating controls
- AppKit for the precision media canvas and pointer interaction
- Core Graphics and Core Image for rendering and effects
- Core ML for bundled upscaling models
- AVFoundation and VideoToolbox for video decoding, timing, audio handling, and hardware-assisted export
- Image I/O for image metadata and encoding

## Documentation

- [Documentation index](docs/README.md)
- [Product definition](docs/product.md)
- [Requirements](docs/requirements.md)
- [User experience](docs/ux.md)
- [Architecture](docs/architecture.md)
- [Offline AI upscaling](docs/upscaling.md)
- [Decisions](docs/decisions.md)
- [Testing](docs/testing.md)
- [Roadmap](docs/roadmap.md)
- [Third-party notices policy](THIRD_PARTY_NOTICES.md)

## Repository state

The repository currently contains the product and technical foundation. Application source code has not yet been scaffolded.

## License

No license has been selected for ImageKid itself. Model, framework, and third-party notices must be completed before a distributable build is produced.