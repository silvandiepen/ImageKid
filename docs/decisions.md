# Decisions

Accepted decisions are appended here. A later change should add a superseding entry instead of silently rewriting history.

## D-001 — Native macOS application

**Status:** Accepted

Build ImageKid in Swift using native Apple frameworks.

**Why:** Precision pointer input, gestures, menus, accessibility, colour management, media decoding, hardware encoding, and local model execution are central product requirements.

**Consequences:** The first product is macOS-only. Electron, Tauri, Catalyst, and a browser implementation are rejected for the initial app.

## D-002 — Images and basic video share one product

**Status:** Accepted

The viewer, colour picker, crop, resize, upscale, annotation, and export concepts apply to both images and videos.

**Consequences:** Domain and rendering layers use a media abstraction. Video adds time, playback, codecs, and audio but not a full editor timeline.

## D-003 — Media-first interface

**Status:** Accepted

The media fills the window. Permanent sidebars, inspectors, layer lists, and timeline tracks are excluded from the default interface.

**Consequences:** Tools use a floating action bar, compact sheets, contextual popovers, menus, and shortcuts.

## D-004 — Floating controls are not the only controls

**Status:** Accepted

Every floating action is mirrored in native menus and keyboard navigation.

**Consequences:** Command state must be centralised and accessible. Hover cannot be required for discoverability or operation.

## D-005 — SwiftUI shell with AppKit canvas

**Status:** Accepted

SwiftUI manages windows, commands, sheets, and high-level UI. A custom `NSView` handles the precision media canvas.

**Consequences:** The SwiftUI/AppKit bridge remains narrow and is mediated by a canvas controller.

## D-006 — One media item per window

**Status:** Accepted

Each window owns one image or video session.

**Consequences:** Multiple drops create multiple windows. Tabs, libraries, and batch queues are deferred.

## D-007 — Non-destructive transient sessions

**Status:** Accepted

The source remains immutable. Crop, resize, upscale selection, and annotations are edit state until export.

**Consequences:** Undo does not store full media copies. Closing with changes requires explicit handling. A public project format is deferred.

## D-008 — Source-relative geometry

**Status:** Accepted

Annotation and crop geometry use orientation-normalised media coordinates rather than window coordinates.

**Consequences:** A dedicated coordinate converter is mandatory and heavily tested across zoom, crop, output scale, Retina, and video transforms.

## D-009 — Exact colour sampling from source media

**Status:** Accepted

Colour is sampled from canonical image data or the current decoded video frame, never from a screenshot of the window.

**Consequences:** Sampling is stable across zoom and overlays. Video YCbCr conversion metadata must be respected.

## D-010 — sRGB is the default copied colour space

**Status:** Accepted

Portable HEX, RGB, HSL, CSS, and code values default to sRGB while source colour information remains available.

**Consequences:** Out-of-gamut colours may need indication. Export colour policy remains independent.

## D-011 — Fully offline product

**Status:** Accepted

No feature may require a connection, account, API key, paid service, activation server, cloud model, or runtime download.

**Consequences:** Models are bundled. Application size is accepted as a trade-off. Any future online feature would require an explicit reversal of this decision and is outside the current product.

## D-012 — No Topaz dependency

**Status:** Accepted

Topaz may be a quality reference, but its products, SDKs, and automation are not dependencies.

**Consequences:** ImageKid uses redistributable open-source models and native runtimes. There are no ongoing inference costs.

## D-013 — Core ML is the first AI runtime

**Status:** Accepted

Converted bundled models run through Core ML.

**Why:** It is native, on-device, Swift-compatible, and can use Apple hardware acceleration without embedding Python or PyTorch.

**Consequences:** Model selection depends partly on conversion feasibility. A different native runtime requires a new decision.

## D-014 — Real-ESRGAN family is the first model candidate

**Status:** Proposed pending checkpoint licence verification and benchmarks

Use a Real-ESRGAN-compatible general x4 checkpoint for the first image upscaler and frame-based video mode.

**Why:** It is designed for practical real-world restoration, has available image and video inference examples, supports tiled processing, and has a comparatively simple frame model.

**Consequences:** Conversion accuracy, model-weight redistribution terms, Core ML operator support, tile seams, screenshots, faces, text, and Apple Silicon performance must be validated before acceptance.

## D-015 — Frame upscale is the first video AI mode

**Status:** Accepted

The first video upscaler applies the image model independently to each decoded frame.

**Why:** It is achievable with the same bundled model and native streaming video pipeline.

**Consequences:** The UI clearly warns about possible shimmer. It is called Frame Upscale, not temporal restoration.

## D-016 — Temporal video model is a later quality tier

**Status:** Accepted

BasicVSR++, BasicVSR, RealBasicVSR, or another temporal model is research scope until native conversion, memory, licensing, and quality are proven.

**Consequences:** Temporal mode is not promised for the first release and remains hidden until production-ready.

## D-017 — AVFoundation and VideoToolbox instead of bundled FFmpeg

**Status:** Accepted

Use Apple media frameworks for common video decode, timing, audio, and export.

**Why:** They are native, signed with the OS, avoid an additional binary and licence matrix, and provide hardware encoding.

**Consequences:** The first format and codec range is intentionally narrower than FFmpeg. Unsupported files receive a clear error rather than a hidden external dependency.

## D-018 — Static video annotations with time ranges

**Status:** Accepted

Video annotations can appear for the whole clip or a chosen start/end range, but do not move or track objects.

**Consequences:** A compact scrubber is enough. Keyframes, tracking, and timeline tracks remain out of scope.

## D-019 — Full-resolution source-based export

**Status:** Accepted

Exports are rendered from source media plus edit state, never from a canvas screenshot.

**Consequences:** Preview and export may use different resolutions but must share geometry, colour, and effect semantics.

## D-020 — Apple Silicon is the AI performance target

**Status:** Accepted

AI features are designed and benchmarked primarily for Apple Silicon.

**Consequences:** Intel support is not promised for AI until benchmarks prove it useful. The minimum supported hardware is decided after model prototypes exist.

## D-021 — Model licence and provenance are release blockers

**Status:** Accepted

A model cannot ship until code licence, weight redistribution terms, exact source, checksum, conversion steps, and attribution are documented.

**Consequences:** A technically successful but legally ambiguous checkpoint is rejected.

## D-022 — No model downloads after installation

**Status:** Accepted

Required models ship inside the app bundle.

**Consequences:** The installer is larger, but first launch and permanent offline use are predictable. Optional online model packs are not part of this product direction.

## D-023 — No implicit AI claims

**Status:** Accepted

The UI differentiates Standard Resize, AI General, AI Illustration, Frame Upscale, and any future Temporal Upscale.

**Consequences:** Users are told that generated detail may not be faithful and that frame processing may flicker.