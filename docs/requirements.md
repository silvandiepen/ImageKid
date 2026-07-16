# Requirements

`MUST` is required for the first intended release. `SHOULD` is expected unless a documented constraint prevents it. `MAY` is optional.

## 1. General media handling

1. The app MUST accept supported media through drag and drop, File > Open, Command-O, pasteboard data, Finder Open With, and file association.
2. One window MUST own one image or one video session.
3. Dropping multiple files SHOULD open one window per file.
4. Opening new media in a window with unexported changes MUST offer Export, Discard, and Cancel.
5. Unsupported, damaged, encrypted, or protected media MUST produce a clear error without destroying the current session.
6. Image orientation and video transforms MUST be normalised consistently before viewing, sampling, cropping, annotation, or export.
7. The app MUST never overwrite the source automatically.

## 2. Offline and privacy

1. Every feature MUST function with networking disabled.
2. All inference and media processing MUST execute on the Mac.
3. Required model weights MUST be included in the application bundle.
4. The app MUST NOT require an account, licence server, API key, remote activation, subscription, or paid third-party SDK.
5. The app MUST NOT upload media, palettes, metadata, prompts, diagnostics, or usage information.
6. Clipboard contents MUST only be read after an explicit paste action.
7. Temporary frames and exports MUST be stored in app-owned locations and removed when no longer needed.
8. No third-party analytics or advertising SDK is permitted.

## 3. Empty state and viewer

1. An empty window MUST show a restrained drop target and Open action.
2. Open media MUST be centred and initially fitted to the available area.
3. The user MUST be able to zoom, pan, fit to window, show actual size, and reset the view.
4. Pinch zoom SHOULD remain anchored beneath the pointer.
5. Spacebar SHOULD temporarily pan unless text input has focus.
6. Double-click SHOULD toggle Fit and Actual Size.
7. Transparent image regions MUST be visible against a configurable checkerboard, light, or dark viewing background.
8. Video playback MUST provide play, pause, scrub, mute, volume, current time, duration, and frame stepping while paused.
9. Zooming or panning a video SHOULD pause playback automatically when precision interaction begins.
10. The title SHOULD show the filename; dimensions, format, duration, frame rate, codec, alpha, and colour profile MUST be available through an information view.

## 4. Floating actions and menus

1. The default viewer MUST not contain permanent editor sidebars or a visible layer panel.
2. Pointer movement or keyboard focus MUST reveal a compact floating action bar.
3. The default bar MUST expose Pick Colour, Crop, Annotate, Resize/Upscale, Copy, Export, and More.
4. Video additionally MUST expose playback and scrubbing without becoming a multitrack timeline.
5. The bar MUST remain visible while a tool is active.
6. Every action MUST also be accessible through native menus and keyboard navigation.
7. Floating controls MUST not block the current precision target.

## 5. Colour picking

1. Colour picking MUST work on images and the current decoded video frame.
2. The pointer MUST show a magnified, nearest-neighbour pixel loupe with an exact centre marker.
3. Sampling MUST read canonical media pixel data, not a screenshot of the composited window.
4. The current value MUST show at least HEX, RGB, and alpha.
5. Clicking MUST append the sample to a session colour list.
6. A saved colour MUST be copyable as HEX/HEXA, RGB/RGBA, HSL/HSLA, CSS, SwiftUI `Color`, AppKit `NSColor`, JSON, and plain values.
7. Default copied values SHOULD be converted to sRGB while source-profile values remain inspectable.
8. Transparent pixels MUST preserve alpha.
9. Duplicate or near-identical samples SHOULD be consolidated or indicated.
10. Escape MUST exit the tool without deleting collected colours.

## 6. Palette extraction

1. Dominant palette extraction MUST work on a complete image or a selected image region.
2. For video, extraction MUST work on the current frame; multi-frame palette analysis MAY be added later.
3. The user MUST be able to request at least 5, 8, or 12 colours.
4. Transparent pixels MUST be ignored by default.
5. Near-identical colours SHOULD be merged using a perceptual threshold.
6. Extraction MUST run outside the main actor and support cancellation.
7. Results MUST support the same copy formats as manually sampled colours.

## 7. Crop

1. Crop MUST work for images and complete video clips.
2. Crop mode MUST dim excluded media and provide draggable corner and edge handles.
3. The crop region MUST remain within media bounds.
4. Free, original, 1:1, 4:3, 3:2, 16:9, and custom ratios MUST be supported.
5. Pixel dimensions MUST be visible while editing.
6. Apply and Cancel MUST be explicit and keyboard accessible.
7. Applied crop MUST be non-destructive and undoable.
8. Video crop MUST apply identically to every frame.
9. Existing annotations MUST retain correct geometry after crop; annotations outside the crop remain recoverable through undo.

## 8. Standard resize

1. Resize MUST support exact width and height, percentage, Fit, Fill, and common scale presets.
2. Aspect ratio MUST be locked by default.
3. Prevent Upscaling MUST be available for standard interpolation.
4. Resulting dimensions MUST be shown before applying.
5. Image resizing MUST use a high-quality final interpolation method.
6. Video resize MUST preserve presentation timestamps and audio synchronisation.
7. Resize MUST be non-destructive and undoable.

## 9. Offline AI upscale

1. AI upscale MUST be presented as a distinct choice from standard resize.
2. At least one general-purpose open-source model MUST be bundled.
3. A second specialised illustration/anime model SHOULD be bundled only after its model-weight redistribution rights are verified.
4. The runtime MUST not depend on Python, PyTorch, a shell command, a network service, or a separately installed package.
5. Core ML is the preferred inference runtime; any replacement runtime must be local, redistributable, signed with the app, and documented.
6. The app MUST provide 2x and 4x output choices. 3x MAY be produced by model output followed by deterministic high-quality downscaling.
7. Large inputs MUST be processed in overlapping tiles with seam-safe blending.
8. Tile size MUST adapt to available memory.
9. The original media MUST remain unchanged.
10. The UI MUST explain that AI reconstruction may invent or alter fine detail.
11. A before/after comparison MUST be available for images and representative video frames.
12. Long jobs MUST show progress, elapsed processing state, expected output dimensions, and Cancel.
13. Processing SHOULD prevent idle sleep while an active export is running, without preventing explicit user sleep.
14. Failure or cancellation MUST preserve the session and partial output MUST not replace a completed export.
15. Every bundled model MUST have a manifest containing name, version, source, checksum, architecture, input constraints, licence, attribution, and conversion provenance.

## 10. Video AI upscale

1. The first implementation MAY upscale frames independently using the bundled image model.
2. Frame-based processing MUST preserve frame order, presentation timestamps, duration, orientation, and audio synchronisation.
3. The UI MUST state that independent frame processing may cause temporal shimmer or flicker.
4. The pipeline MUST avoid writing all decoded frames to disk when streaming processing is possible.
5. Processing MUST be resumable only if a safe deterministic checkpoint design is implemented; otherwise interrupted jobs restart clearly.
6. A true temporal model MAY be added as a higher-quality mode only after it meets memory, licensing, Core ML compatibility, and performance acceptance criteria.
7. Temporal mode MUST remain fully local and bundled.
8. The app MUST not imply real-time video upscaling unless benchmarks prove it on the supported hardware.

## 11. Annotation

1. Annotation MUST support Select, Arrow, Line, Rectangle, Ellipse, Freehand, Text, Numbered Marker, Blur, and Pixelate.
2. Annotations MUST remain editable until export.
3. Geometry MUST be stored in orientation-normalised media coordinates, independent of zoom and window size.
4. Users MUST be able to move, resize, duplicate, delete, and reorder annotations.
5. Contextual controls MUST expose relevant colour, fill, opacity, width, typography, arrowhead, blur, and pixelation options.
6. Native text selection, editing, spelling, and accessibility SHOULD be preserved.
7. Freehand strokes SHOULD be simplified after drawing without visible deformation.
8. Image annotations are always visible unless hidden.
9. Video annotations MUST have a start and end time; the default is the full clip duration.
10. Video annotations remain static in position during their visible range. Motion tracking and keyframes are out of scope.
11. Region blur and pixelation MUST use underlying media pixels rather than a screenshot of the preview.
12. Every creation and modification MUST support undo and redo.

## 12. Clipboard

1. A dedicated Copy Image command MUST copy the flattened image with alpha when supported.
2. For video, Copy Current Frame MUST copy the processed current frame.
3. Copy Colour MUST write plain text and appropriate colour representations.
4. Command-C behaviour MUST remain predictable based on selection; menus must expose unambiguous alternatives.
5. Paste MUST accept image data. Video paste MAY be supported when the pasteboard provides a file URL.

## 13. Export

### Images

1. PNG, JPEG, HEIC/HEIF, and TIFF MUST be supported where available.
2. Format-specific quality, alpha, metadata, and colour-profile controls MUST be shown.
3. The app MUST warn when a chosen format cannot preserve transparency.

### Video

1. Common MOV and MP4 export MUST be supported.
2. H.264 and HEVC MUST be offered when supported by the machine and selected container.
3. Hardware encoding SHOULD be used through VideoToolbox where available.
4. Original audio SHOULD be passed through when compatible; otherwise it may be re-encoded locally with an explicit format choice.
5. Frame rate and timestamps MUST be preserved by default.
6. Output codec, dimensions, estimated size, duration, and audio handling MUST be visible before export.
7. Protected media MUST not be exported or bypassed.

### Shared

1. Export MUST use a native save panel and sandbox-compatible access.
2. Full-resolution exports MUST be rendered from source media and edit state, never from a window screenshot.
3. Export MUST be cancellable and atomic: incomplete files must not appear as successful output.
4. Export failure MUST preserve the complete session.

## 14. Undo, close, and recovery

1. Command-Z and Shift-Command-Z MUST work.
2. Continuous drags MUST coalesce into meaningful operations.
3. Viewport changes and playback do not create document undo entries.
4. Crop, resize, upscale configuration, annotation geometry, timing, order, style, and deletion do create entries.
5. Closing with changes MUST not silently lose work.
6. Lightweight crash recovery SHOULD be implemented before public release if long video jobs or annotations can otherwise be lost.

## 15. Accessibility

1. Every core workflow MUST be keyboard operable.
2. Every control MUST expose an accessible name, state, and shortcut where relevant.
3. Floating controls MUST not steal focus when they appear.
4. Tool changes, crop dimensions, selected annotation properties, export progress, and errors SHOULD be announced by VoiceOver.
5. Colour swatches MUST expose textual values and not rely on colour alone.
6. Annotation objects MUST be reachable through accessibility APIs even without a visible layer list.
7. Increased Contrast, Reduce Transparency, Reduce Motion, and larger text MUST be respected.

## 16. Performance and reliability

1. Typical images and video thumbnails SHOULD appear immediately while full decoding continues asynchronously.
2. Decode, palette extraction, AI inference, effects, and export MUST not block the main actor.
3. Zoom, pan, playback, and annotation interaction SHOULD remain smooth on supported Macs.
4. Very large media MUST use downsampled previews and bounded-memory processing.
5. Video pipelines SHOULD stream frames instead of retaining the complete clip in memory.
6. Picking the same source pixel at different zoom levels MUST return the same value.
7. Exported annotation geometry MUST match preview geometry within an explicit pixel tolerance.
8. Video duration, timestamps, and audio drift MUST be covered by automated tests.
9. The app MUST report insufficient storage, unsupported codecs, memory pressure, and model failures clearly.