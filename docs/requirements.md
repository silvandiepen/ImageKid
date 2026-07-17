# Requirements

`MUST` is required for the intended first release. `SHOULD` is expected unless a documented constraint prevents it. `MAY` is optional.

## 1. General media handling

1. The app MUST accept supported media through drag and drop, File > Open, Command-O, pasteboard data, Finder Open With, and file association.
2. One window MUST own one image or one video session.
3. Dropping multiple files SHOULD open one window per file.
4. Opening new media in a window with unexported changes MUST offer Export, Discard, and Cancel.
5. Unsupported, damaged, encrypted, or protected media MUST produce a clear error without destroying the current session.
6. Image orientation and video transforms MUST be normalised consistently before viewing, sampling, editing, or export.
7. The source MUST never be overwritten automatically.

## 2. Offline and privacy

1. Core viewing, inspection, editing, and export features MUST function with networking disabled.
2. Local media processing MUST execute on the Mac.
3. The app MUST NOT require an account, licence server, API key, remote activation, subscription, runtime download, or paid third-party SDK for core workflows.
4. The app MUST NOT upload media, palettes, metadata, diagnostics, or usage information unless the user explicitly starts a provider-backed prompted edit.
5. Clipboard contents MUST only be read after an explicit paste action.
6. Temporary media MUST remain in app-owned local storage and be removed when no longer required.
7. No analytics or advertising SDK is permitted.
8. Prompted image edits MAY use a provider API. They MUST be explicit user actions, use user-supplied credentials stored in the keychain, and must not run as a fallback for local tools.

## 3. Viewer

1. An empty window MUST show a restrained drop target and Open action.
2. Open media MUST be centred and initially fitted to the available area.
3. The user MUST be able to zoom, pan, fit to window, show actual size, and reset the view.
4. Pinch zoom SHOULD remain anchored beneath the pointer.
5. Spacebar SHOULD temporarily pan unless text input has focus.
6. Double-click SHOULD toggle Fit and Actual Size.
7. Transparent image regions MUST be visible against a checkerboard, light, or dark background.
8. Video playback MUST provide play, pause, scrub, mute, volume, current time, duration, and frame stepping while paused.
9. Dimensions, format, duration, frame rate, codec, alpha, and colour profile MUST be available through an information view where applicable.

## 4. Controls and menus

1. The default viewer MUST not contain permanent editor sidebars, layer lists, or a multitrack timeline.
2. Pointer movement or keyboard focus MUST reveal a compact floating action bar.
3. The primary bar MUST expose Pick Colour, Crop, Annotate, Resize, Copy, Export, and More as appropriate for the media type.
4. The bar MUST remain visible while a tool is active.
5. Every primary action MUST also be accessible through native menus and keyboard navigation.
6. Floating controls MUST not block the current precision target.

## 5. Colour inspection

1. Colour picking MUST work on images and the current decoded video frame.
2. The pointer MUST show a magnified nearest-neighbour loupe with an exact centre marker.
3. Sampling MUST read canonical media pixels, not a screenshot of the window.
4. The current value MUST show HEX, RGB, and alpha.
5. Clicking MUST append the sample to a session colour list.
6. Saved colours MUST be copyable as HEX/HEXA, RGB/RGBA, HSL/HSLA, CSS, SwiftUI `Color`, AppKit `NSColor`, JSON, and plain values.
7. Default copied values SHOULD be converted to sRGB while source-profile values remain inspectable.
8. Dominant palette extraction MUST support the complete image, a selected region, or the current video frame.
9. Palette extraction MUST offer at least 5, 8, and 12 colours and ignore transparent pixels by default.
10. The same source pixel MUST return the same value at every zoom level.

## 6. Crop

1. Crop MUST work for images and complete video clips.
2. Crop mode MUST dim excluded media and provide draggable corner and edge handles.
3. The crop region MUST remain within media bounds.
4. Free, original, 1:1, 4:3, 3:2, 16:9, and custom ratios MUST be supported.
5. Pixel dimensions MUST be visible while editing.
6. Apply and Cancel MUST be explicit and keyboard accessible.
7. Crop MUST remain non-destructive and undoable.
8. Video crop MUST apply identically to every frame.
9. Existing annotations MUST retain correct geometry after crop.

## 7. Resize

1. Resize MUST support exact width and height, percentage, Fit, Fill, and common scale presets.
2. Aspect ratio MUST be locked by default.
3. Prevent Upscaling MUST be available for standard interpolation.
4. Resulting dimensions MUST be shown before applying.
5. Image resizing MUST use high-quality interpolation.
6. Video resize MUST preserve presentation timestamps and audio synchronisation.
7. Resize MUST remain non-destructive and undoable.

## 8. Annotation

1. Annotation MUST support Select, Arrow, Line, Rectangle, Ellipse, Freehand, Text, Numbered Marker, Blur, and Pixelate.
2. Annotations MUST remain editable until export.
3. Geometry MUST be stored in orientation-normalised media coordinates, independent of zoom and window size.
4. Users MUST be able to move, resize, duplicate, delete, and reorder annotations.
5. Contextual controls MUST expose relevant colour, fill, opacity, width, typography, arrowhead, blur, and pixelation options.
6. Native text selection, editing, spelling, and accessibility SHOULD be preserved.
7. Image annotations are always visible unless hidden.
8. Video annotations MUST have a start and end time; the default is the full clip duration.
9. Video annotations remain static during their visible range. Motion tracking and keyframes are out of scope.
10. Region blur and pixelation MUST use underlying media pixels.
11. Every creation and modification MUST support undo and redo.

## 9. Clipboard

1. Copy Image MUST copy the flattened image with alpha when supported.
2. Copy Current Frame MUST copy the processed current video frame.
3. Copy Colour MUST write plain text and appropriate colour representations.
4. Command-C behaviour MUST remain predictable based on selection.
5. Paste MUST accept image data. Video paste MAY be supported when the pasteboard provides a file URL.

## 10. Export

### Images

1. PNG, JPEG, HEIC/HEIF, and TIFF MUST be supported where available.
2. Format-specific quality, alpha, metadata, and colour-profile controls MUST be shown.
3. The app MUST warn when a selected format cannot preserve transparency.

### Video

1. Common MOV and MP4 export MUST be supported.
2. H.264 and HEVC MUST be offered when supported by the machine and selected container.
3. Hardware encoding SHOULD be used through VideoToolbox.
4. Original audio SHOULD be passed through when compatible; otherwise it may be re-encoded locally with an explicit format choice.
5. Frame rate and timestamps MUST be preserved by default.
6. Output codec, dimensions, estimated size, duration, and audio handling MUST be visible before export.
7. Protected media MUST not be exported or bypassed.

### Shared

1. Export MUST use a native save panel and sandbox-compatible access.
2. Full-resolution exports MUST be rendered from source media and edit state, never from a window screenshot.
3. Export MUST be cancellable and atomic.
4. Export failure MUST preserve the complete session.

## 11. Undo, close, and recovery

1. Command-Z and Shift-Command-Z MUST work.
2. Continuous drags MUST coalesce into meaningful operations.
3. Viewport changes and playback MUST NOT create document undo entries.
4. Crop, resize, annotation geometry, timing, order, style, and deletion MUST create undo entries.
5. Closing with changes MUST not silently lose work.
6. Lightweight crash recovery SHOULD be implemented before public release where practical.

## 12. Accessibility

1. Every core workflow MUST be keyboard operable.
2. Every control MUST expose an accessible name, state, and shortcut where relevant.
3. Floating controls MUST not steal focus when they appear.
4. Tool changes, crop dimensions, selected annotation properties, export progress, and errors SHOULD be announced by VoiceOver.
5. Colour swatches MUST expose textual values and not rely on colour alone.
6. Annotation objects MUST be reachable through accessibility APIs even without a visible layer list.
7. Increased Contrast, Reduce Transparency, Reduce Motion, and larger text MUST be respected.

## 13. Performance and reliability

1. Typical images and video thumbnails SHOULD appear immediately while full decoding continues asynchronously.
2. Decode, palette extraction, effects, and export MUST not block the main actor.
3. Zoom, pan, playback, and annotation interaction SHOULD remain smooth on supported Macs.
4. Very large media MUST use downsampled previews and bounded-memory processing.
5. Video pipelines SHOULD stream frames instead of retaining the complete clip in memory.
6. Exported annotation geometry MUST match preview geometry within an explicit pixel tolerance.
7. Video duration, timestamps, and audio drift MUST be covered by automated tests.
8. The app MUST report insufficient storage, unsupported codecs, and memory pressure clearly.

## Local model requirements

Best Quality background removal and Best Quality image upscaling MAY use app-managed local runtime installs. They MUST be explicit user actions from Settings, run on-device, store assets in Application Support, and fail with actionable install errors instead of falling back to cloud processing.
