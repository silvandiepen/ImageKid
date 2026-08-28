# ImageKid Slicer

## Summary

**ImageKid Slicer** is a deliberately tiny native macOS companion app for turning one image sheet into multiple image files.

The core workflow is intentionally limited to:

1. Open or drop one image.
2. Draw rectangular slices over the parts to extract.
3. Adjust the slices directly on the image.
4. Click **Save**.
5. Choose an output folder.
6. ImageKid Slicer creates every slice as a separate image file.

There is no project setup, layer system, inspector, batch queue, AI detection, account, cloud processing, or general-purpose image editing. The image and the slice rectangles are the interface.

## Product position

ImageKid Slicer belongs to the same family as ImageKid Upscale and ImageKid Cutout, but it is interaction-driven rather than queue-driven.

- **ImageKid** is the complete local image utility for inspection, editing, correction, annotation, and export.
- **ImageKid Upscale** performs one repeated batch operation: upscale images.
- **ImageKid Cutout** performs one repeated batch operation: remove image backgrounds.
- **ImageKid Slicer** performs one focused manual operation: define regions on one source image and export all regions at once.

The companion-app principle still applies: one obvious job, local processing, no account, no subscription, no credits, and no dependency on the main ImageKid app.

## Primary use cases

- Split an AI-generated image sheet containing multiple views or variations.
- Extract icons or sprites from a larger source image.
- Split a contact sheet or reference sheet into individual images.
- Pull several screenshots, cards, panels, or assets from one composite image.
- Prepare multiple crop regions without repeatedly reopening and cropping the source.

## Product principles

### One image, one task

A window contains one source image. Opening another image replaces the current unsaved slicing session only after normal close/discard protection if slices exist.

### Media-first

The source image occupies almost the entire window. There is no permanent sidebar, layer list, inspector, thumbnail browser, or settings panel.

### Direct manipulation

Slices are created, moved, resized, selected, and deleted directly on top of the image.

### Immediate

Opening an image shows the image immediately. The user does not create a project, choose a template, configure export settings, or enter an import flow first.

### Local-first

All decoding, geometry, cropping, and encoding happens on-device. There is no account, telemetry, hosted processing, remote activation, or runtime service dependency.

### Source-safe

The source image is never modified or overwritten. Slices are exported as new files.

### Native

Use standard macOS open/save panels, drag and drop, menus, keyboard shortcuts, accessibility, window behavior, and file permissions.

## Window and UI

The default window should be visually minimal:

```text
┌──────────────────────────────────────────────────────┐
│  Open                                        Save    │
├──────────────────────────────────────────────────────┤
│                                                      │
│        ┌──────────┐        ┌──────────────┐          │
│        │ Slice 1  │        │   Slice 2    │          │
│        │          │        │              │          │
│        └──────────┘        └──────────────┘          │
│                                                      │
│                   SOURCE IMAGE                       │
│                                                      │
│             ┌────────────────┐                       │
│             │    Slice 3     │                       │
│             └────────────────┘                       │
│                                                      │
└──────────────────────────────────────────────────────┘
```

Required visible controls:

- **Open** when a source is loaded or a large open/drop affordance when empty.
- **Save** when at least one valid slice exists.
- The image canvas.
- Slice rectangles and selection handles.

Everything else should be native menu commands, contextual behavior, or only appear while relevant.

## Empty state

When no source image is loaded:

- show a simple centered **Open Image** action;
- accept Finder drag and drop anywhere in the window;
- support `Command-O`;
- optionally accept an image from the pasteboard through `Command-V` when the pasteboard contains image data.

Do not show onboarding, recent projects, templates, presets, or configuration.

## Slice interaction

### Create

- Drag on empty image area to create a rectangular slice.
- The rectangle is clamped to the source image bounds.
- Very small accidental drags below a minimum threshold are discarded.
- A new slice becomes selected immediately.
- Holding `Shift` while drawing constrains the new slice to a square.

### Select

- Click inside a slice to select it.
- Only one slice needs to be selected in the first release.
- The selected slice shows resize handles and a stronger outline.
- Unselected slices remain clearly visible without obscuring the source image.

### Move

- Drag inside the selected slice to move it.
- Movement is clamped so the entire slice remains within the source image.

### Resize

- Drag edge or corner handles to resize.
- Resize remains clamped to source bounds.
- Holding `Shift` while resizing preserves a 1:1 aspect ratio.
- Slice edges resolve to source-image pixels during export; view zoom must never affect the exported geometry.

### Delete

- `Delete` or `Backspace` removes the selected slice.
- A context-menu **Delete Slice** action may also exist.

### Duplicate

`Command-D` may duplicate the selected rectangle with a small offset. This is useful for similarly sized grid content but is secondary to the core workflow and must not add visible UI clutter.

### Naming

Slices are automatically named in creation order:

- `Slice 1`
- `Slice 2`
- `Slice 3`

Explicit renaming is optional for the first release. If included, it should be lightweight, for example double-clicking the slice label or using a context-menu **Rename** action. A rename field must not become a permanent sidebar or inspector.

## Zoom and navigation

The app needs only enough canvas navigation to define accurate rectangles:

- fit image to window by default;
- pinch or `Command-+` / `Command--` to zoom;
- `Command-0` to fit/reset;
- pan with trackpad/two-finger interaction or Space-drag when zoomed;
- slice geometry remains attached to source-image coordinates at every zoom level.

A permanent zoom control is not required.

## Save and export

**Save** means export all defined slices. It does not create a Slicer project file in the first release.

Workflow:

1. User clicks **Save** or presses `Command-S`.
2. A native folder picker asks where the generated slices should be written.
3. The app validates all slice rectangles.
4. Every slice is cropped from the original-resolution source image.
5. Files are written atomically.
6. A compact completion state reports how many files were created and offers **Reveal in Finder**.

There is no separate export screen in the first release.

### Output naming

Default deterministic naming:

```text
{source-name}-slice-01.{ext}
{source-name}-slice-02.{ext}
{source-name}-slice-03.{ext}
```

If explicit slice names are supported, a valid custom name can replace `slice-01`, while still applying collision protection.

Numbers should be zero-padded based on the slice count where practical so Finder sorting remains stable.

### Output format

The first release should avoid an export-settings panel.

Default behavior:

- preserve the source format for PNG, JPEG, HEIC/HEIF, and TIFF where Image I/O can safely encode it;
- preserve alpha when the source format supports alpha;
- fall back to PNG when preserving the source encoding is not safe or practical;
- preserve the source colour profile where practical;
- do not intentionally rescale or recompress more than required by the chosen output encoding.

Format conversion can be added later only if there is a demonstrated need. It should not complicate the primary workflow.

### Collision handling

Never overwrite an existing file by default.

If a generated output path already exists, append a numeric suffix such as:

```text
sheet-slice-01-2.png
```

The first release does not need an overwrite mode.

## Session behavior

Slicer does not need persistent project documents in the first release.

While the window remains open, the app keeps:

- source URL or pasted source image;
- source orientation and pixel dimensions;
- current zoom/pan view state;
- slice rectangles;
- slice order;
- optional slice names.

If the user attempts to close the window or replace the source after defining slices that have not been saved, show standard discard protection.

After a successful Save, the current session may remain open so the user can adjust rectangles and save again.

## Coordinate model

Follow ImageKid's existing normalized-media-coordinate decision while keeping export pixel-exact.

Each slice stores geometry relative to the orientation-correct source image, independent of the current window size and zoom. At export time:

1. resolve normalized geometry against the source image's oriented pixel dimensions;
2. clamp to valid source bounds;
3. align the crop rectangle to integer pixel boundaries;
4. crop the original-resolution pixel buffer, never the fitted screen preview.

This keeps interaction stable across resizing/zooming while guaranteeing deterministic source-resolution crops.

## Native implementation direction

The app should stay small and use Apple frameworks first:

- SwiftUI for app/window structure and lightweight controls;
- AppKit where pointer tracking, cursor behavior, drag/drop, menus, or native panels are better served directly;
- Core Graphics for source-resolution cropping;
- Image I/O for decoding, metadata, colour profile handling, and output encoding;
- Uniform Type Identifiers for supported image types.

No inference package, network entitlement, database, external service, or third-party image library is required.

Useful existing ImageKid code may be shared through `ImageKidKit` or `ImageKidCore` when the dependency stays clean, especially:

- image loading and orientation normalization;
- coordinate mapping;
- file type handling;
- image writing;
- zoom/pan helpers.

Slicer must not import the main ImageKid application's UI or turn shared packages into a dumping ground for app-specific view state.

## Proposed app target

When implementation begins, add a separate macOS target:

- Target: `ImageKidSlicer`
- Display name: `ImageKid Slicer`
- Bundle identifier: `com.hakobs.imagekid.slicer`
- Category: Graphics & Design
- Minimum macOS target: follow the repository's current macOS deployment target.
- Sandbox: enabled.
- File entitlement: user-selected read/write.
- Network entitlement: none.

Suggested source shape:

```text
apps/native-macos/Sources/ImageKidSlicer/
├── ImageKidSlicerApp.swift
├── SlicerDocumentModel.swift
├── SlicerCanvas.swift
├── SliceOverlay.swift
├── SliceGeometry.swift
├── SliceExporter.swift
└── SlicerCommands.swift
```

If image I/O or coordinate helpers are already reusable, keep them in existing shared packages rather than copying them into the Slicer target.

## Keyboard commands

First-release commands:

- `Command-O` — open image.
- `Command-S` — save/create all slices.
- `Command-0` — fit image to window.
- `Command-+` / `Command--` — zoom.
- `Delete` / `Backspace` — delete selected slice.
- `Escape` — cancel the current drag/resize operation or clear selection when idle.
- `Command-D` — duplicate selected slice, if duplication ships.

Menus should expose the same actions for discoverability and accessibility.

## Accessibility

The core workflow must not require pixel-perfect mouse use only.

At minimum:

- every slice is represented as an accessible element with its number/name and pixel dimensions;
- selection state is exposed;
- Delete works from the keyboard;
- Save and Open are keyboard/menu accessible;
- resize handles have accessible descriptions where feasible;
- future arrow-key nudging can be added if manual positioning proves difficult for keyboard users.

## Performance

Slicer should feel instant for normal image sheets.

- Do not repeatedly decode the source while dragging rectangles.
- Use a display-sized preview for canvas rendering when needed, while retaining the original source for export.
- Export from original-resolution pixels.
- Cropping and encoding must run off the main actor.
- Large sources should not create one full-size duplicate of the entire source per slice before writing when streaming/sequential export can avoid it.
- Process slice exports serially by default to keep memory pressure predictable.

## Safety and file rules

- Never modify the source file.
- Never overwrite generated files by default.
- Clamp every slice to source bounds before export.
- Reject zero-sized or invalid rectangles.
- Write each output to a temporary sibling file first, then atomically move it into place.
- If one slice fails, continue exporting the remaining valid slices and report the failed slice at completion.
- A failed write must not leave a misleading partial output file.

## Explicit non-goals for the first release

Do not add:

- automatic object detection;
- AI-powered slice detection;
- grid recognition;
- automatic whitespace detection;
- OCR;
- sprite metadata generation;
- multiple source images in one window;
- a batch queue;
- persistent `.slice` project files;
- a layer/sidebar inspector;
- arbitrary polygon or freehand slices;
- rotation or perspective correction;
- image editing inside a slice;
- annotations;
- crop presets or complex aspect-ratio UI;
- cloud sync;
- account/login;
- subscription or credits.

If automatic detection becomes useful later, it should remain an optional accelerator that produces normal editable rectangles. Manual slicing must stay the complete core workflow.

## Test coverage

Unit tests should cover:

- normalized-to-pixel rectangle conversion;
- orientation-correct geometry;
- clamping at every source edge;
- integer pixel rounding behavior;
- deterministic slice ordering;
- output filename generation;
- collision avoidance;
- alpha preservation for PNG;
- source-format fallback behavior;
- partial export failure without aborting later slices.

UI tests should cover at least:

1. open an image;
2. create two slices;
3. move and resize one slice;
4. delete a slice;
5. save the remaining slices to a temporary folder;
6. verify the expected number of output files exists.

## First-release acceptance criteria

ImageKid Slicer is ready for its first usable release when:

- a user can open or drop a normal image without onboarding;
- drawing on the image creates a slice rectangle;
- slices can be selected, moved, resized, and deleted;
- zooming/resizing the window never changes source-relative slice geometry;
- Save asks for a folder and creates one output file per valid slice;
- exported crops match the selected source regions at original resolution;
- source files are never modified;
- output collisions never overwrite files silently;
- the complete core workflow works with networking disabled;
- there is no visible complexity unrelated to slicing.

## Later possibilities

Only consider these after the minimal version is proven:

- optional slice renaming if not included initially;
- arrow-key nudge and numeric pixel dimensions/position;
- temporary guides or snapping;
- equal-size duplication/grid helpers;
- format selection in the Save panel;
- automatic whitespace/object-based slice suggestions;
- reusable project/session files;
- copy selected slice to clipboard;
- drag an individual slice directly to Finder.

These are enhancements, not requirements. The defining product experience remains:

> Open image → define slices → Save → get all slices.
