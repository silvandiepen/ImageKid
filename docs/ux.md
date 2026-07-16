# User experience

## Design direction

ImageKid should feel like Quick Look or Preview with temporarily revealed tools. The media is dominant; controls are contextual and disappear when not needed.

Visual priority:

1. image or video;
2. current interaction;
3. temporary controls;
4. window chrome.

Avoid permanent sidebars, large card layouts, decorative gradients, web-style dashboards, visible layer stacks, and full video timelines.

## Window model

- One media item per window.
- The title shows the filename.
- Multiple dropped files open separate windows.
- The window remembers useful size and placement.
- Images and paused video frames share the same zoomable canvas.
- Video adds a compact playback strip, not a multitrack editor.

## Empty state

The empty window contains a quiet drop target, “Drop an image or video,” an Open action, and optional text for paste or Command-O. The entire content area accepts drops.

## Viewer

On open, media is centred and fitted. Pointer movement reveals actions. Pinch zooms around the pointer, dragging pans, Command-0 fits, Command-1 shows actual size, and double-click toggles Fit and Actual Size.

Transparent images use a user-selectable checkerboard, light, or dark viewing background.

## Video viewer

The playback strip contains play/pause, current time, duration, a compact scrubber, frame stepping while paused, volume, and mute.

Activating colour picker, crop, or annotation pauses playback. The scrubber remains a single clip strip and must not imply multitrack editing.

## Floating action bar

Default order:

1. Pick Colour
2. Crop
3. Annotate
4. Resize
5. Copy
6. Export
7. More

The bar floats above the lower centre of the canvas using native material with an opaque accessibility fallback. It appears on pointer movement or keyboard focus, stays visible while a tool is active, and fades during idle viewing.

The bar changes context instead of growing. Crop mode replaces it with crop controls. Annotation mode replaces it with annotation tools. Resize opens a compact sheet.

## Menus

File contains New Window, Open, Open Recent, Close, Export, and Share. Edit contains Undo, Redo, contextual copy, paste, and annotation commands. View contains fit, actual size, zoom, background, information, and video playback commands. Tools contains colour picking, palette extraction, crop, annotation, and resize. Arrange contains annotation ordering commands.

## Colour picker

1. Choose Pick Colour or press P.
2. Video pauses on the current frame.
3. The pointer becomes a nearest-neighbour loupe with a centre marker, swatch, and current value.
4. Click stores the colour.
5. Stored colours appear in a compact strip attached to the floating bar.
6. Clicking a swatch copies the preferred representation.
7. A context menu offers formats, rename, duplicate, and remove.
8. Extract Palette offers 5, 8, or 12 colours.
9. Escape exits while retaining the session palette.

## Crop

- Enter with C, menu, or floating action.
- Excluded media is dimmed.
- Handles resize and move the crop region.
- Controls show Free, Original, 1:1, 4:3, 3:2, 16:9, dimensions, Reset, Cancel, and Apply.
- Return applies; Escape cancels.
- For video, the crop applies to the complete clip.

## Resize sheet

The sheet contains width, height, pixels or percentage, Exact/Fit/Fill, aspect lock, Prevent Upscaling, high-quality interpolation, and resulting dimensions.

The current scaffold exposes exact dimensions and 50%, 100%, and 200% presets. The complete control set belongs to the crop and resize milestone.

## Annotation mode

The contextual bar contains Select, Arrow, Rectangle, Ellipse, Draw, Text, Marker, Blur, Line, Pixelate, and Done. Selection shows restrained handles and a contextual property popover rather than a permanent inspector.

For video, every annotation defaults to the complete clip. A compact timing control supports Entire Clip, From Current Time, Until Current Time, and Custom Start and End. There are no keyframes, tracks, or animated positions.

## Export

Image controls adapt to PNG, JPEG, HEIC, or TIFF and show dimensions, alpha behaviour, quality, metadata, and colour profile.

Video controls show container, codec, quality, dimensions, frame-rate behaviour, audio handling, and estimated size. Long jobs show current stage, progress, processed frames when known, elapsed time, and Cancel.

## Visual style

- Native typography and controls.
- Neutral backgrounds.
- Minimal borders.
- No decorative gradients.
- Rounded floating controls at macOS utility scale.
- SF Symbols where appropriate.
- Strong focus and selected-tool states.
- Brief functional animation respecting Reduce Motion.
- Opaque controls when accessibility settings require them.

## Keyboard defaults

- Command-O: Open
- Command-W: Close
- Shift-Command-S: Export As
- Command-C: Contextual copy
- Command-Z / Shift-Command-Z: Undo / Redo
- Command-Plus / Command-Minus: Zoom
- Command-0: Fit
- Command-1: Actual Size
- Space: temporary pan or video play/pause depending focus and tool
- P: Pick Colour
- C: Crop
- A: Annotate
- R: Resize
- Left / Right: frame step while paused
- Escape: cancel or leave current tool

Single-letter shortcuts never fire while editing text or numeric fields.
