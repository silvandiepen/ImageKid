# Roadmap

The roadmap is ordered to reduce technical risk before broad UI polish. Each milestone should leave a demonstrable, testable application.

## Milestone 0 — Model and platform feasibility

Before scaffolding the complete product:

- convert one candidate Real-ESRGAN-compatible checkpoint to Core ML;
- run it from a minimal Swift macOS harness;
- verify output against the reference implementation;
- prototype overlapping tiles;
- measure speed and memory on representative Apple Silicon Macs;
- test screenshots, photos, text, faces, illustrations, and alpha handling;
- verify code and model-weight redistribution terms;
- prototype `AVAssetReader` → model → `AVAssetWriter` on a short clip;
- measure temporal shimmer and audio synchronisation.

Exit criteria: one legally usable model can be bundled and produces acceptable local image output; frame-based video processing is proven end to end.

## Milestone 1 — Native media viewer

- SwiftUI app and window lifecycle.
- Empty drop state.
- Open, paste, Open With, recent files.
- One media item per window.
- Image decode and metadata.
- Video playback, scrub, pause, frame step, mute, and metadata.
- AppKit zoomable/pannable canvas.
- Fit, actual size, menus, and shortcuts.
- Error handling for unsupported media.

Exit criteria: ImageKid is already useful as a clean image and basic video viewer.

## Milestone 2 — Colour inspection

- Exact pixel sampler.
- Video current-frame sampler.
- Magnified loupe.
- Session colour strip.
- Copy formats.
- Dominant image/current-frame palette extraction.
- Colour-profile handling and tests.

Exit criteria: values remain identical at every zoom and across supported orientation cases.

## Milestone 3 — Crop and standard resize

- Non-destructive crop state.
- Ratio presets and keyboard controls.
- Resize sheet with Exact, Fit, Fill, percent, and aspect lock.
- Full-resolution image export.
- Streaming standard video crop/resize export.
- Undo and close protection.

Exit criteria: output dimensions, timing, orientation, and audio match requirements.

## Milestone 4 — Image annotation

- Select, Arrow, Line, Rectangle, Ellipse, Freehand, Text, Marker, Blur, Pixelate.
- Contextual properties.
- Object hit testing, handles, ordering, duplication, and deletion.
- Native text editing.
- Source-space rendering.
- Copy processed image.
- Accessibility representation for annotations.

Exit criteria: annotations remain editable and export accurately at multiple scales.

## Milestone 5 — Video annotation

- Reuse source-space annotations on frames.
- Full-clip visibility by default.
- Start/end time ranges.
- Scrubber range indication.
- Frame-accurate compositing during preview and export.
- Copy current processed frame.

Exit criteria: annotation boundaries are correct and export preserves synchronisation.

## Milestone 6 — Bundled image AI upscale

- Core ML model registry and manifest.
- General model bundled in the signed app.
- Adaptive tiling and seam-safe blending.
- 2x, 3x, and 4x output.
- Alpha reconstruction path.
- Before/after region preview.
- Progress, cancellation, memory handling, and notices.
- Optional illustration model only after licence verification.

Exit criteria: the app works with networking disabled and beats standard resize on the approved benchmark set without unacceptable distortion.

## Milestone 7 — Frame-based video AI upscale

- Streaming reader/inference/writer pipeline.
- Backpressure and bounded memory.
- Audio passthrough/re-encode path.
- Annotation compositing.
- Representative-frame preview.
- Clear temporal-flicker warning.
- Long-job progress, cancellation, atomic output, and sleep activity handling.

Exit criteria: short and medium clips export reliably with correct duration and audio sync.

## Milestone 8 — Product hardening

- Crash recovery where justified.
- Accessibility audit.
- Performance matrix and minimum hardware decision.
- Memory-pressure handling.
- Third-party notices and model information UI.
- Sandboxing, signing, notarisation, and App Store feasibility review.
- Complete offline release test.

## Future research

These are not commitments:

- Temporal video super-resolution using BasicVSR++, BasicVSR, RealBasicVSR, or a newer redistributable model.
- Scene-cut-aware temporal windows.
- Local denoise and deblur models.
- Batch queue.
- Trim and simple clip extraction.
- Screenshot and screen-recording capture.
- Pixel-art-specific integer upscaling.
- Local face restoration, only with conservative defaults and strong disclosure.
- HDR image and video preservation.
- A recoverable `.imagekid` session format.

## Permanently out of direction unless explicitly reconsidered

- Cloud inference.
- Paid APIs or SDKs.
- Accounts or subscriptions required for core operation.
- Runtime model downloads.
- Advertising and behavioural analytics.
- Full nonlinear video editing.
- A Photoshop-style permanent editor layout.