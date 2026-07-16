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
- Image fit, pan, pinch zoom, and view reset.
- Click-based image pixel sampling.
- Session colour strip and HEX copy.
- Crop selection state and export crop application.
- Resize sheet with exact size and 50%, 100%, and 200% presets.
- Rectangle and text annotation creation.
- PNG, JPEG, and TIFF image export rendered from source media and edit state.
- Geometry mapping unit tests.
- macOS CI build and test workflow.

## Incomplete or provisional

- Pixel sampling currently uses a click instead of a magnified live loupe.
- Colour conversion and unusual bitmap formats require broader tests.
- Applied crop is represented in edit state; the live canvas still needs a cropped working preview and draggable crop handles.
- Annotation tools currently cover rectangle and placeholder text only.
- Annotation selection, movement, resizing, styling, ordering, and native text editing remain.
- Undo, redo, close protection, recovery, and document lifecycle remain.
- Video currently provides viewing and playback only. Video colour picking, crop, resize, annotations, and export are the next major technical slice.
- Export format controls, metadata policy, colour-profile controls, and transparency warnings remain.
- The Swift package does not yet define production signing, sandboxing, or distribution settings.

## Deferred

AI upscaling and all model/runtime work are deferred. No Core ML model, model registry, provider interface, runtime download, cloud provider, or upscaling UI should be added while the core milestones remain unfinished.
