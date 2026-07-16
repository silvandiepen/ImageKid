# Product definition

## Summary

ImageKid is a native macOS utility for quickly viewing, inspecting, resizing, upscaling, cropping, and annotating images and basic video.

The media itself is the interface. A file is dropped, pasted, or opened and immediately fills the window. Viewer controls remain hidden until the pointer moves, keyboard focus reaches them, or a tool becomes active. The same actions are available from the macOS menu bar.

## Problem

Simple media work is spread across oversized tools. Picking a colour, scaling an asset, marking a screenshot, or enlarging a short clip should not require a full photo editor, video timeline, account, upload, or subscription.

ImageKid combines those small tasks in one fast local utility without becoming a general creative suite.

## Audience

- Designers inspecting assets and colours.
- Developers preparing UI images and videos.
- Product and QA teams annotating screenshots and recordings.
- Support teams marking problems in images or short clips.
- Writers preparing media for documentation.
- General Mac users who need a simpler Preview-like tool.

## Product promise

> Drop media into a native window, inspect it immediately, make the small change you need, and export it without uploading anything.

## Product principles

### Media-first

The image or video occupies the window. No permanent sidebar, layer list, inspector, or timeline appears in the default state.

### Immediate

Opening media does not create a project or show an import workflow. The first visible result is the media itself.

### Progressive

Tools appear only when relevant. Resize uses a compact sheet. Annotation properties use contextual popovers. Video timing uses a small scrubber rather than a multitrack timeline.

### Offline

Every feature works without a connection. Models are included with the app. No cloud fallback, account, API key, remote telemetry, or paid service is permitted.

### Native

Menus, keyboard shortcuts, drag and drop, pasteboard handling, trackpad gestures, file panels, colour management, hardware video encoding, accessibility, and window behaviour follow macOS conventions.

### Reversible

Crop, resize, upscale settings, and annotations remain non-destructive during the session. The original file is never overwritten implicitly.

### Focused

ImageKid handles one image or one video per window. It does not become a photo catalogue, compositing suite, or nonlinear video editor.

## Image use cases

- View and zoom an image.
- Inspect dimensions, format, alpha, metadata, and colour profile.
- Pick exact pixels with a magnified loupe.
- Collect colours and export palettes.
- Crop or resize.
- Compare normal scaling with AI upscaling.
- Annotate with text, arrows, shapes, markers, drawing, blur, and pixelation.
- Copy or export the flattened result.

## Video use cases

- Play, pause, scrub, mute, and step through frames.
- Zoom and pan a paused frame.
- Pick colours from the current decoded frame.
- Apply one crop or output size to the complete clip.
- Upscale every frame locally while preserving timing and audio.
- Add static annotations over the complete clip or limit an annotation to a start and end time.
- Export a new self-contained video.

## First release scope

### Shared

- One media item per window.
- Drag, paste, Open, Open With, and recent files.
- Fit, actual size, zoom, pan, and information display.
- Crop, resize, annotations, undo, copy, and export.
- Fully local processing.
- Accessibility and keyboard support.

### Images

- PNG, JPEG, HEIC/HEIF, TIFF, GIF first frame, and formats supported safely by Image I/O.
- Exact colour sampling and palette extraction.
- Standard high-quality resize.
- Bundled general AI upscaler.
- Optional bundled illustration/anime upscaler if its redistribution terms are verified.

### Video

- Common unprotected MOV and MP4 input supported by AVFoundation.
- Playback and frame inspection.
- Crop, resize, colour sampling, and annotations.
- Frame-based AI upscaling using the bundled image model.
- H.264 and HEVC export with audio retained where compatible.

## Explicit non-goals for the first release

- Multiple tracks, clips, transitions, titles, or timeline editing.
- Motion tracking or keyframed annotation movement.
- Trimming, splitting, speed changes, or audio editing.
- RAW photo development.
- Animated GIF editing.
- AI generation, background removal, OCR, or object recognition.
- Cloud models, downloadable models, paid SDKs, or online activation.
- Batch processing.
- Accounts, collaboration, comments, or sync.
- A permanent layers panel.
- A proprietary project format unless crash recovery proves insufficient.

## Success criteria

- A first-time user can drop a file and use the primary actions without onboarding.
- Normal viewing remains visually quiet.
- Pixel colour results are stable at every zoom level.
- Exported geometry and colours match the preview.
- Image upscaling is materially better than standard interpolation on appropriate inputs.
- Video processing preserves frame timing, duration, and audio synchronisation.
- Long local jobs show progress, support cancellation, and never require a connection.
- Every core workflow is usable with keyboard and VoiceOver.
- Model attribution and redistribution rights are documented before release.