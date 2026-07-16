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

On open:

- media is centred and fitted;
- surrounding chrome is minimal;
- pointer movement reveals actions;
- pinch zooms around the pointer;
- dragging pans when zoomed;
- Command-0 fits;
- Command-1 shows actual size;
- double-click toggles Fit and Actual Size;
- a temporary zoom percentage appears during zooming.

Transparent images use a user-selectable checkerboard, light, or dark viewing background.

## Video viewer

The video playback strip appears near the bottom and contains:

- play/pause;
- current time and duration;
- compact scrubber;
- frame backward and forward when paused;
- volume and mute;
- optional playback speed in More.

Pausing enables precise frame inspection. Activating colour picker, crop, or annotation pauses playback. The scrubber remains a single clip strip; it must not visually imply multitrack editing.

## Floating action bar

Default order:

1. Pick Colour
2. Crop
3. Annotate
4. Resize / Upscale
5. Copy
6. Export
7. More

The bar floats above the lower centre of the canvas using native material with an opaque accessibility fallback. It appears on pointer movement or keyboard focus, stays visible while a tool is active, and fades during idle viewing.

The bar changes context instead of growing. Crop mode replaces it with crop controls. Annotation mode replaces it with annotation tools. Upscale opens a focused sheet.

## Menus

### File

- New Window
- Open…
- Open Recent
- Close
- Export…
- Share

### Edit

- Undo / Redo
- Copy
- Copy Processed Image
- Copy Current Video Frame
- Paste
- Duplicate Annotation
- Delete Annotation
- Select All Annotations

### View

- Fit to Window
- Actual Size
- Zoom In / Out
- Reset View
- Canvas Background
- Show Media Information
- Video playback commands when applicable

### Tools

- Pick Colour
- Extract Palette
- Crop
- Annotate
- Resize
- AI Upscale

### Arrange

- Bring Forward
- Bring to Front
- Send Backward
- Send to Back

## Colour picker

1. Choose Pick Colour or press P.
2. Video pauses on the current frame.
3. The pointer becomes a loupe showing a nearest-neighbour pixel grid, centre marker, swatch, and current value.
4. Click stores the colour.
5. Stored colours appear in a compact strip attached to the floating bar.
6. Clicking a swatch copies the preferred representation.
7. A context menu offers formats, rename, duplicate, and remove.
8. Extract Palette opens a small popover for 5, 8, or 12 colours.
9. Escape exits while retaining the session palette.

The loupe flips near window edges and must remain aligned with the true sampled pixel.

## Crop

- Enter with C, menu, or floating action.
- Excluded media is dimmed.
- Handles resize and move the crop region.
- Controls show Free, Original, 1:1, 4:3, 3:2, 16:9, dimensions, Reset, Cancel, and Apply.
- Return applies; Escape cancels.
- For video, the chosen crop applies to the complete clip and can be previewed at several scrub positions.

## Resize and upscale sheet

The sheet begins with two clearly separated methods:

### Standard

- width and height;
- pixels or percentage;
- Exact, Fit, or Fill;
- lock aspect ratio;
- prevent upscaling;
- high-quality interpolation.

### AI Upscale

- model: General or Illustration when available;
- output: 2x, 3x, or 4x;
- detail strength or denoise only when the bundled model supports it predictably;
- expected dimensions;
- local-processing note;
- warning that generated detail may differ from the original.

For images, a draggable before/after divider previews a representative region or downsampled result.

For video, the sheet previews several representative frames: current frame, an earlier frame, and a later frame. It also states that the first video mode processes frames independently and can shimmer. The final job begins only after Export or Apply to Session is confirmed.

## Annotation mode

Action bar:

- Select
- Arrow
- Rectangle
- Ellipse
- Draw
- Text
- Marker
- Blur
- More: Line and Pixelate
- Done

Selection shows restrained handles and a contextual property popover. There is no permanent inspector.

Relevant properties include stroke, fill, opacity, width, arrowhead, font, size, weight, alignment, marker number, blur strength, and pixel size.

### Video timing

Every new annotation defaults to the full clip. A compact timing control in the contextual popover provides:

- Entire Clip;
- From Current Time;
- Until Current Time;
- Custom Start and End.

A thin indicator on the scrubber may show the selected annotation’s visible range. There are no keyframes, tracks, or animated positions.

## Copy

Copy Processed Image is a primary action for screenshots and images. Video provides Copy Current Frame. A brief non-modal confirmation appears after copying.

## Export

### Images

Format controls adapt to PNG, JPEG, HEIC, or TIFF and show final dimensions, alpha behaviour, quality, metadata, and colour profile.

### Video

Controls show container, codec, quality, dimensions, frame rate behaviour, audio handling, estimated size, and whether AI upscaling is active.

Long jobs display:

- current stage;
- progress bar;
- processed frames and total when known;
- elapsed time;
- Cancel.

Do not promise an exact completion time when processing speed varies. Completion and errors are non-destructive.

## Visual style

- Native typography and controls.
- Neutral backgrounds.
- Minimal borders.
- No decorative gradients.
- Rounded floating controls at macOS utility scale, not oversized mobile pills.
- SF Symbols where appropriate.
- Strong focus and selected-tool states.
- Brief functional animation respecting Reduce Motion.
- Opaque controls when Reduce Transparency or Increased Contrast requires them.

## Keyboard defaults

- Command-O: Open
- Command-W: Close
- Shift-Command-S: Export As
- Command-C: Contextual copy
- Command-Z / Shift-Command-Z: Undo / Redo
- Command-Plus / Command-Minus: Zoom
- Command-0: Fit
- Command-1: Actual Size
- Space: Temporary pan or play/pause in video viewer depending focus and active tool
- P: Pick Colour
- C: Crop
- A: Annotate
- R: Resize / Upscale
- Left / Right: Frame step while paused when the canvas has focus
- Escape: Cancel or leave current tool

Single-letter shortcuts never fire while editing text or numeric fields.