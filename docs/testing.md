# Testing strategy

## Build gate

Every pull request must pass on a supported macOS runner:

```bash
swift build
swift test
```

Warnings should be reviewed, especially AVFoundation deprecations and concurrency diagnostics introduced during Swift 6 migration.

## Unit tests

Prioritise deterministic logic:

- aspect-fit and aspect-fill geometry;
- view-to-media and media-to-view conversion;
- normalised crop rectangles;
- rotated and mirrored orientation cases;
- annotation geometry after crop and resize;
- colour string formatting;
- output dimension calculation;
- annotation time-range inclusion;
- export configuration validation.

## Image fixtures

Maintain small legal fixtures covering sRGB PNG with alpha, Display P3, JPEG EXIF orientation, grayscale and unusual bitmap layouts, HEIC where available, extreme aspect ratios, transparent edge pixels, and a large image suitable for downsampled preview tests.

Golden-image tests should compare rendered outputs with explicit tolerances rather than window screenshots.

## Video fixtures

Maintain short locally generated clips covering MOV and MP4, H.264 and HEVC where supported, portrait transforms, representative frame timing, stereo audio, no audio, exact annotation boundaries, and a clip long enough to expose audio drift.

## Interaction tests

Verify open, paste, drop, toolbar reveal, keyboard access, zoom, pan, fit, pixel stability across zoom, crop apply and cancel, annotation editing, resize validation, dirty-close protection, and export cancellation and recovery.

## Accessibility tests

- Complete primary workflows with keyboard only.
- Inspect controls and annotations with VoiceOver.
- Verify focus does not jump when floating controls appear.
- Test Increased Contrast, Reduce Transparency, Reduce Motion, and larger text.
- Ensure colour swatches expose values as text.

## Performance tests

Measure time to first preview, zoom and pan frame stability, memory use for large images, palette extraction duration, full-resolution image export, video processing throughput, queued frames, cancellation latency, and audio drift.

## Offline release gate

Before release:

1. disable networking;
2. open, inspect, edit, copy, and export supported images;
3. open, inspect, edit, and export supported videos;
4. confirm no account, download, activation, telemetry, or remote resource is requested;
5. inspect the final app bundle for unexpected network or third-party runtime dependencies.

## Distribution gate

A distributable build additionally requires a signed application target, sandbox entitlement review, security-scoped file tests, hardened runtime, archive and notarisation validation, correct bundle metadata, a selected project licence, and completed notices.
