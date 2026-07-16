# Roadmap

The roadmap is ordered so every milestone leaves a demonstrable, testable application. AI upscaling is intentionally excluded.

## Milestone 0 — Buildable foundation

Status: implemented in the current scaffold.

- Swift package and native macOS application lifecycle.
- Empty drop state.
- Open, paste, drag and drop.
- Image loading and basic video playback.
- Initial menus and keyboard commands.
- Geometry tests and macOS CI.

Exit criteria: the repository builds and tests on macOS through SwiftPM and runs from Xcode.

## Milestone 1 — Complete native viewer

- One media item per window and multiple-window opening.
- Recent files and Finder Open With.
- AppKit-backed precision canvas if SwiftUI interaction proves insufficient.
- Fit, actual size, anchored zoom, pan, and background selection.
- Image and video metadata.
- Video mute, frame stepping, exact time display, and paused-frame ownership.
- Unsupported media and protected-content errors.

Exit criteria: ImageKid is useful as a clean image and basic video viewer.

## Milestone 2 — Colour inspection

- Exact orientation-aware pixel sampler.
- Magnified live loupe.
- Current-frame video sampler.
- Session colour strip management.
- All copy formats.
- Dominant image, region, and current-frame palette extraction.
- Colour-profile handling and tests.

Exit criteria: sampled values remain identical across zoom levels, view sizes, and orientation cases.

## Milestone 3 — Crop and standard resize

- Cropped working preview.
- Drag handles and ratio presets.
- Exact, percentage, Fit, Fill, and Prevent Upscaling resize modes.
- Full-resolution image export through Image I/O.
- Format, quality, alpha, metadata, and colour-profile controls.
- Undo and dirty-close protection.

Exit criteria: exported image dimensions, geometry, colour, and transparency match the preview and selected settings.

## Milestone 4 — Complete image annotation

- Select, Arrow, Line, Rectangle, Ellipse, Freehand, Text, Marker, Blur, and Pixelate.
- Contextual properties.
- Hit testing, handles, ordering, duplication, deletion, and keyboard movement.
- Native text editing.
- Source-space rendering and processed-image copy.
- Accessibility representation for annotation objects.

Exit criteria: annotations remain editable and export accurately at multiple output scales.

## Milestone 5 — Basic video processing

- Stable current-frame provider.
- Colour picking from paused frames.
- Complete-clip crop and resize.
- Streaming `AVAssetReader` and `AVAssetWriter` pipeline.
- H.264 and HEVC output.
- Audio passthrough or local re-encode.
- Atomic export, progress, and cancellation.

Exit criteria: representative clips preserve orientation, duration, timestamps, frame rate, and audio synchronisation.

## Milestone 6 — Video annotation

- Reuse source-space annotation types on video frames.
- Full-clip visibility by default.
- Start and end time ranges.
- Scrubber range indication without a full timeline.
- Frame-accurate preview and export compositing.
- Copy processed current frame.

Exit criteria: annotation boundaries are frame-correct and exports remain synchronised.

## Milestone 7 — Product hardening

- Crash recovery where justified.
- Accessibility audit.
- Performance and memory matrix.
- Very large image preview strategy.
- Sandboxing and security-scoped file access.
- Signed application target, icon, versioning, archive, and notarisation.
- Complete offline release test.
- Final project licence and contribution policy.

## Future research, not commitments

- Batch processing.
- Trim and simple clip extraction.
- Screenshot and screen-recording capture.
- Pixel-art-specific scaling.
- HDR image and video preservation.
- Recoverable `.imagekid` sessions.
- Local AI upscaling only after the complete core product is stable.

## Permanently out of direction unless explicitly reconsidered

- Cloud processing.
- Paid APIs or SDKs.
- Accounts or subscriptions required for core operation.
- Runtime model downloads.
- Advertising and behavioural analytics.
- Full nonlinear video editing.
- A Photoshop-style permanent editor layout.
