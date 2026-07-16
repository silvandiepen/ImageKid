# Product definition

## Summary

ImageKid is a native macOS utility for quickly viewing, inspecting, resizing, cropping, and annotating images and basic video.

The media itself is the interface. A file is dropped, pasted, or opened and immediately fills the window. Controls remain hidden until the pointer moves, keyboard focus reaches them, or a tool becomes active. The same actions remain available from the macOS menu bar.

## Problem

Simple media work is spread across oversized tools. Picking a colour, scaling an asset, marking a screenshot, or preparing a short recording should not require a full photo editor, nonlinear video timeline, account, upload, or subscription.

ImageKid combines those small tasks in one fast local utility without becoming a general creative suite.

## Product promise

> Drop local media into a native window, inspect it immediately, make the small change you need, and export it without uploading anything.

## Audience

- Designers inspecting assets and colours.
- Developers preparing UI images and recordings.
- Product and QA teams annotating screenshots and short videos.
- Support teams marking problems in visual material.
- Writers preparing media for documentation.
- Mac users who need a simpler Preview-like tool.

## Product principles

### Media-first

The image or video occupies the window. No permanent sidebar, layer list, inspector, or multitrack timeline appears in the default state.

### Immediate

Opening media does not create a project or show an import workflow. The first result is the media itself.

### Progressive

Tools appear only when relevant. Resize uses a compact sheet. Annotation properties use contextual controls. Video timing uses a small scrubber rather than a timeline editor.

### Offline

Every feature works without a connection. No cloud fallback, account, API key, remote telemetry, paid service, or runtime download is permitted.

### Native

Menus, keyboard shortcuts, drag and drop, pasteboard handling, trackpad gestures, file panels, colour management, hardware video encoding, accessibility, and window behaviour follow macOS conventions.

### Reversible

Crop, resize, and annotations remain non-destructive during the session. The source file is never overwritten implicitly.

### Focused

One window handles one image or one video. ImageKid does not become a photo catalogue, compositing suite, or nonlinear video editor.

## Image use cases

- View, zoom, and pan an image.
- Inspect dimensions, format, alpha, metadata, and colour profile.
- Pick exact pixels with a magnified loupe.
- Collect colours and extract dominant palettes.
- Crop or resize.
- Annotate with text, arrows, shapes, markers, drawing, blur, and pixelation.
- Copy or export the flattened result.

## Video use cases

- Play, pause, scrub, mute, and step through frames.
- Zoom and pan a paused frame.
- Pick colours from the current frame.
- Apply one crop or output size to the complete clip.
- Add static annotations over the complete clip or restrict them to a start and end time.
- Export a new self-contained video while preserving timing and audio.

## First release scope

### Shared

- One media item per window.
- Drag, paste, Open, Open With, and recent files.
- Fit, actual size, zoom, pan, and information display.
- Crop, resize, annotations, undo, copy, and export.
- Fully local processing.
- Accessibility and keyboard support.

### Images

- PNG, JPEG, HEIC/HEIF, TIFF, GIF first frame, and safely supported Image I/O formats.
- Exact colour sampling and dominant palette extraction.
- High-quality standard resize.
- Full annotation toolset.

### Video

- Common unprotected MOV and MP4 input supported by AVFoundation.
- Playback and frame inspection.
- Crop, resize, colour sampling, and static time-ranged annotations.
- H.264 and HEVC export with audio retained where compatible.

## Explicit non-goals for the first release

- AI upscaling or other bundled machine-learning models.
- Multiple tracks, clips, transitions, titles, or timeline editing.
- Motion tracking or keyframed annotation movement.
- Trimming, splitting, speed changes, or audio editing.
- RAW photo development.
- Animated GIF editing.
- AI generation, background removal, OCR, or object recognition.
- Batch processing.
- Accounts, collaboration, comments, or sync.
- A permanent layer panel.

## Success criteria

- A first-time user can drop a file and use primary actions without onboarding.
- Normal viewing remains visually quiet.
- Pixel colour results remain stable at every zoom level.
- Exported geometry and colours match the preview.
- Video export preserves frame timing, duration, orientation, and audio synchronisation.
- Every core workflow works with networking disabled.
- Every core workflow is usable with keyboard and VoiceOver.
