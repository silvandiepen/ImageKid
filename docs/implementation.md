# Implementation status

## Build foundation

The repository is a Swift Package Manager executable targeting macOS 14. Open `Package.swift` in Xcode 16 and run the `ImageKid` scheme on My Mac, or use `swift build`, `swift test`, and `swift run ImageKid` from Terminal.

The package form keeps the initial repository small, reviewable, and directly testable. Distribution work will require a signed application target, bundle metadata, assets, sandbox entitlements, archive configuration, and notarisation or App Store configuration.

## Implemented

- SwiftUI application lifecycle and native command menus.
- Empty drop state.
- Open panel, drag and drop, URL paste, and image paste.
- Image loading with `NSImage`.
- Video loading and playback with AVFoundation and AVKit.
- Image fit, mouse pan, two-finger trackpad pan, pinch zoom, and view reset.
- Correct top-to-bottom press-and-drag image colour sampling with a large live swatch.
- Persistent colour panel with multi-selection, removal, colour adjustment, expanded HEX/RGB/RGBA/HSL/SwiftUI values, copy formats, and file export.
- Crop overlay with corner and edge handles, rule-of-thirds guides, ratio choices, editable pixel dimensions, reset, cancel, Escape cancellation, and apply.
- Applied crop immediately reframes the working canvas and remains the basis for viewing, picking, annotations, and further crops.
- Resize sheet with exact size and percentage presets.
- Editable rectangles, ellipses, lines, arrows, and freehand annotations.
- Reliable freehand input from mouse-down through mouse-up, including short and fast strokes.
- Drawing settings for mode, stroke colour, fill, thickness, and opacity.
- Text annotations that remain editable, movable, and resizable.
- Contextual text settings for content, font family, size, weight, alignment, and colour.
- Draggable vertical contextual panels with a dark translucent surface and large corner radius.
- Image export sheet with PNG, JPEG, HEIC, TIFF, BMP, and GIF, quality, scale, transparency background, and Finder reveal controls.
- Full-resolution image export rendered from source media and edit state.
- Geometry, crop-coordinate, freehand-input, and colour-coordinate mapping unit tests.
- macOS CI build and test workflow.

## Incomplete or provisional

- The live colour picker currently presents a colour swatch rather than a pixel-grid magnifier.
- Palette extraction from dominant image colours remains.
- Blur, pixelation, annotation ordering, duplication, and rotation remain.
- Text editing is performed through the contextual panel rather than direct inline canvas typing.
- Undo, redo, close protection, recovery, and document lifecycle remain.
- Video currently provides viewing and playback only. Video colour picking, crop, resize, annotations, and export remain a separate major technical slice.
- Metadata preservation and advanced colour-profile controls remain. Current exports intentionally render a fresh file without source metadata.
- The Swift package does not yet define production signing, sandboxing, or distribution settings.

## Deferred

AI upscaling and all model/runtime work are deferred. No Core ML model, model registry, provider interface, runtime download, cloud provider, or upscaling UI should be added while the core milestones remain unfinished.
