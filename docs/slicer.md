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

There is no project setup, layer system, batch queue, AI detection, account, cloud processing, or general-purpose image editing. The image, the slice rectangles, and the cutting guides are the interface.

Beyond drawing rectangles by hand, slices can also be produced by **cutting guides** dragged across the image, by a **grid**, or by a **template** — all of which are still manual layouts the user chooses, not detection.

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

### Several images, one window

Opening or dropping images adds them to a filmstrip below the canvas; opening never replaces what is already open, so nothing drawn is ever lost by opening something else. Each image keeps its own slices, guides, crop, selection, and view transform, and switching between them disturbs none of it.

The filmstrip appears only once a second image is open, so cutting one sheet stays exactly as small as it always was. This supersedes the original "one image per window" position and the `docs/decisions.md` D-015 non-goal on multiple sources — see **Multiple images** below.

### Media-first

Slicer runs dark, always: judging a crop against light chrome is harder, and the app has no appearance setting to honour. The chrome — the top bar, the tool bar, the slices list — is translucent dark glass over a window vibrancy layer, washed with a dark scrim so it does not take its colour from whatever happens to be behind the window. The canvas deliberately is **not** translucent: a slicing tool is colour-critical, and letting the desktop tint the source image would be a bad trade for a nicer screenshot.

The source image occupies almost the entire window. A floating tool bar sits over the canvas — the same shape as ImageKid's and Fekthor's — and everything else is on demand: the grid and template controls live in popovers, and the slices list is a sidebar that is closed until asked for. There is no layer list, thumbnail browser, or settings panel.

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

The window chrome is a real unified toolbar at the compact native height — not a bar drawn into the content — so it stays out of the traffic lights' way on its own and drags the window. It carries only:

- **Open**;
- the source's name and pixel size, and the slice count (or the crop size while the Crop tool is active);
- the **export options** button, labelled with what will be written (`PNG · 200% · q80`);
- the export summary and **Reveal** after a save;
- **Save** / **Crop & Save…**, which appears only when there is something to write.

Everything else is a native menu command, the floating tool bar, or a popover that appears only while relevant.

## Empty state

When no source image is loaded:

- show a simple centered **Open Image** action;
- accept Finder drag and drop anywhere in the window, at any time — not only while empty;
- accept an image dragged onto the Dock icon: the bundle declares `public.image` as an Editor document type at Alternate rank (which keeps Preview the system default), and the app delegate's `open(urls:)` loads it;
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
- **Option-drag** pulls out a copy at the same size instead: the original stays where it is, and the drag moves the new slice. The copy starts exactly on top of the original, so it does not jump out from under the pointer, and it is never born locked or named.

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

A slice can be renamed in its inspector or in the slices list (**View ▸ Show Slices List**, `⌥⌘S`), which is closed by default. Clearing the name field restores the automatic `Slice n` name. A custom name replaces `slice-01` in the exported filename and still gets collision protection.

## Tool bar

A floating tool bar sits over the bottom of the canvas, in the same idiom as ImageKid's and Fekthor's: a material capsule of square buttons.

- **Slice** (`S`) — draw, select, move, and resize rectangles.
- **Suggest Guides** — find the gutters between tiles and drop a guide down the middle of each.
- **Detect Elements** — one slice around each separate thing in the image.
- **Guides** (`G`) — drag cutting lines across the image.
- **Crop** (`C`) — one region, saved straight out as a single file.
- **Snapping** — toggle edge snapping.
- **Grid** — a popover with the grid toggle, columns/rows, the centre-line snapping toggle, and "save this grid as a template".
- **Templates** — a popover listing the built-in layouts and the user's own.
- **Auto Slice** — one slice per cell between the current cutting lines.
- **Clear Guides** — remove every guide.
- **Lock** — lock the selected slice.
- **Slices list** — show or hide the sidebar.

Every one of these is also a menu command, so the whole app is reachable from the keyboard.

Every icon carries a tooltip, and so does every menu command.

The icons do not rely on SwiftUI's `.help()`, which drew nothing on the floating tool bar. Setting `NSView.toolTip` on the annotation's own view did not work either: dumping the real hierarchy showed SwiftUI hosting a `.background` representable *behind* the control and sometimes laid out beyond its parent's bounds — hosts at x=161 inside 41-point-wide parents at x=47 — so the view carrying the tooltip was clipped and never consulted.

What works is registering a tooltip **rect** on an ancestor that is correctly framed and on top, which is what `addToolTip(_:owner:userData:)` is for. Each annotation measures itself in the root view's coordinates, registers there, and re-registers whenever it moves. `.help()` is applied alongside, since that is what carries the text into the accessibility tree.

The tests assert geometry rather than text: two earlier attempts set the right string on the wrong view, which no text-only assertion could tell apart from working. macOS menu items support `NSMenuItem.toolTip` but SwiftUI's `Commands` cannot set one, so the live menu is annotated as it opens — as it opens rather than once at launch, because SwiftUI rebuilds the items as state changes and titles like Lock/Unlock flip with it. The text lives in one table in `SlicerHelp`, and a test reads `SlicerCommands.swift` and fails if a command is added without one.

## Cutting guides

Guides are lines across the whole image. They are not exported and they are not slices — they are what **Auto Slice** cuts along, and what other slices snap to.

- With the Guides tool, a mostly-sideways drag lays down a horizontal cut; a mostly-upright drag lays down a vertical one.
- Dragging an existing guide moves it; guides snap to the same lines slices do.
- A selected guide is deleted with `Delete`/`Backspace`, or from its context menu.
- **Clear Guides** removes them all without touching the slices they produced.

**Auto Slice** (`⇧⌘A`) turns every cell between the cut lines — the guides, plus the grid when it is shown — into one slice, numbered in reading order. Cells thinner than the minimum slice size are dropped rather than exported as slivers.

## Detecting elements

Two different jobs, deliberately kept apart:

- **Suggest Guides** (`⇧⌘G`) projects the whole image onto each axis and finds the runs that are background all the way across. It produces *guides*, and can only ever describe a **grid** — which is exactly right for a sheet of tiles laid out in rows and columns.
- **Detect Elements** (`⇧⌘D`) walks the pixels and groups the ones that touch. It produces *slices*, one around each separate thing, wherever it sits. A collage of three boxes that share no full-width gutter becomes three slices; projection would give four cells matching nothing.

Element detection is eight-connected, so a diagonal touch counts as the same thing. Boxes within a few pixels of each other are merged first — a thing is rarely one component, since an outline, its fill and its shadow all touch nothing — and anything smaller than roughly 1% of the image on either side is dropped as dust. The results come back in reading order, so the slices are numbered the way the sheet is read.

Both run on the same downsampled copy, off the main actor, and both stay accelerators: what they produce is ordinary guides and ordinary slices, editable and deletable like any other.

Each hands back the tool that edits what it just made: Detect Elements, Auto Slice and templates leave you on the **Slice** tool, Suggest Guides leaves you on **Guides**. Without that, running a detection from the Guides tool means the next click lays a guide across the new work instead of selecting it.

## Suggested guides

**Suggest Guides** (`⇧⌘G`) looks for the runs of uninterrupted background separating one tile from the next, and drops a guide down the middle of each. The background is taken as the median of the border pixels, so a tile running to the edge does not throw it off, and runs touching an edge are skipped — those are the sheet's own margin, and a cut there would only carve off a blank strip.

What it produces is ordinary guides: draggable, deletable, ignorable. Auto Slice then cuts along them exactly as if they had been dragged out by hand. Detection stays an accelerator, never a mode, and manual slicing remains the complete workflow.

The scan runs on a downsampled copy — a gutter is a large-scale feature, and a 12000px scan does not need 12000 columns of work.

## Snapping

While snapping is on, a dragged slice latches onto:

- the image edges;
- the image centre lines, and other slices' centre lines (togglable);
- other slices' edges;
- guides;
- the grid;
- **the edges of the content itself** (togglable) — where the tiles on a sheet actually start and stop, so pulling an edge near a square lands exactly on that square instead of a pixel or two off.

Content edges come from the same column/row projection Suggest Guides uses, scanned once when the image loads so dragging never pays for it. Where a gutter guide sits down the *middle* of a gap, a content edge sits on the tile's own border — the two describe different lines, and a sheet offers both.

A move snaps the whole rectangle by whichever of its leading edge, centre, or trailing edge is closest, so a move never resizes. A draw or resize only snaps the edges the pointer is actually moving, so the anchored edge stays put. Holding `Shift` (the square constraint) suspends snapping. The line a drag has latched onto is drawn while the drag is live.

One on-screen tolerance becomes two normalised tolerances, because the source is rarely square.

## Grid

An optional regular grid of columns and rows, drawn over the image. It is a snapping and auto-slice aid only: it is never exported and never edits a slice by itself. Its current column × row setting can be saved as a template.

## Templates

A template is a named column × row layout that fills the whole image with slices in one click. Built-ins cover halves, thirds, quarters, 3 × 3, 4 × 4, and a 5 × 4 contact sheet; the user's own templates are saved in preferences (Slicer still has no document format) and can be deleted from the same popover.

Applying a template makes its grid the visible grid and its cells the slices. Because there is no undo, it asks first when there are unsaved slices to lose.

## Locking

A locked slice is inert to the pointer: it cannot be selected, moved, resized, or deleted, and a drag that starts on top of it draws a **new** slice rather than picking the locked one up. It still exports, still acts as a snap target, and survives Auto Slice and templates — locking is how the user says "not this one".

Lock from the tool bar, `⌘L`, or a slice's context menu; `⇧⌘L` unlocks everything. A locked slice draws with a muted dashed outline and a lock badge, so the difference is visible before the user tries to drag it.

## Slices list

An optional sidebar (`⌥⌘S`), closed by default. Each row shows a thumbnail of the slice's own region, its editable name, its exact pixel size, a lock toggle, and a delete button. Selecting a row selects the slice on the canvas.

## Slice inspector

Double-clicking a slice — or `⌘E` with one selected — opens its inspector as a popover anchored on the slice itself. It holds everything about that one slice:

- a **preview** of the region it will export, at the slice's own aspect ratio, and the filename it will be written as;
- its **name**, with the automatic `Slice n` as the placeholder; clearing the field restores it;
- an **anchor grid** — the nine points, one of which stays put while the size changes;
- exact **width and height** in source pixels, with steppers and an optional locked ratio;
- exact **X and Y** in source pixels;
- **lock**, **duplicate**, and **delete**.

The anchor is what makes typed sizes predictable: 512 × 512 with the top-left anchor leaves the top-left corner where it is, while the same numbers on the centre anchor grow the slice outwards in every direction. Every value is in source pixels and is clamped to the image, so a size larger than the source trims rather than overflows.

A locked slice still opens its inspector — that is where the lock is undone — but its size and position fields are disabled.

## Crop

The Crop tool is the one-in-one-out path: no slices, no folder, just a region and a file. Choosing it dims everything outside the region, and the slice overlays and guides step aside so there is a single thing on screen to adjust.

- Entering Crop starts from the whole image, so trimming an edge is one handle drag.
- Dragging inside a full-image crop draws a fresh region; once the region is smaller than the image, dragging inside moves it and the handles resize it.
- `Shift` constrains to a square, snapping works exactly as it does for slices, and the region carries rule-of-thirds guides and a live pixel readout.
- `Escape` resets the region to the whole image.
- **Crop & Save…** (`⌘S` while the Crop tool is active) opens a normal save panel, suggesting `{source-name}-crop.{ext}`, and writes one file at source resolution — the same atomic, source-safe write the slice export uses.

The crop region is independent of the slices: it survives Auto Slice and templates, and switching back to the Slice tool leaves both untouched.

## Zoom and navigation

Enough navigation to work at the pixel, not just to place a rectangle:

- fit image to window by default;
- pinch, `Command`-scroll, or `Command-+` / `Command--` to zoom, up to 32×;
- `Command-0` to fit/reset;
- two-finger scroll to pan when zoomed in;
- slice geometry remains attached to source-image coordinates at every zoom level.

**Zoom is anchored to the pointer**, not to the middle of the canvas. Zooming about the centre is fine for taking in a whole sheet and useless for inspecting a corner — the thing being looked at slides away exactly when it gets big enough to see.

Once the image is drawn larger than its own pixels the canvas switches from smooth interpolation to exact: blurring is the wrong answer when the point is to see pixels. Panning is clamped to keep a corner of the image on screen, so a stray gesture cannot fling it somewhere it has to be hunted for.

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

## Multiple images

- **Open** and drag-and-drop both accept any number of images at once, as does the Dock icon.
- The **filmstrip** shows each open image with a thumbnail, its name, its slice count, and an orange dot while it has unsaved slices. Clicking switches to it; its context menu closes it.
- **Apply Layout to All Images** (`⌥⌘A`) copies the current image's slices and guides onto every other open image. Because all geometry is normalised against the source, one layout lands correctly on sheets of different pixel sizes. Locked slices on the receiving images survive — locking means "not this one", on every image.
- **Export All Images…** (`⇧⌘S`) runs every image that has slices in one go, into one subfolder per image inside the folder picked, so eight sheets do not land as seventy-two loose files. Images with no slices are skipped.
- **Close Image** (`⇧⌘W`) confirms first if that image has unsaved slices; quitting counts unsaved work across every open image, not just the one on screen.

## Sessions

A session file (`.slicer`) records which images were open and everything drawn on each of them — slices, names, locks, guides, the crop — plus the grid, snapping, and export options. **File ▸ Save Session…** (`⌥⌘S`) writes one; **Open Session…** (`⇧⌘O`) or double-clicking the file restores it.

It is plain JSON describing *layout*, not pixels: reopening re-reads the original sources, so a session stays tiny and never becomes a second copy of the user's images. Each image is recorded with a security-scoped bookmark (so a sandboxed relaunch can still reach it) and its path as a fallback. Images that can no longer be found are named in a warning rather than dropped silently — a session that quietly loses half its sheets is worse than one that says so.

Slicer owns the type outright: it is declared in `UTExportedTypeDeclarations` and claimed at `Owner` rank, unlike images which it handles at `Alternate` rank so Preview stays the system default.

## Export options

The export options popover — the toolbar button, labelled with the current settings — decides what Save actually writes. They apply to both the slice export and Crop & Save, and persist between launches.

- **Format**: same as source, PNG, JPEG, HEIC, or TIFF. "Same as source" keeps the source's encoding where Image I/O can write it and falls back to PNG otherwise.
- **Quality**: shown only when the resulting format is lossy — which, for "same as source", depends on the source.
- **Scale**: presets from 25% to 400% plus an exact percentage, with a live "1200×800 → 600×400" readout against a real region. An unscaled export skips resampling entirely.
- **Filename prefix**: sanitised and hyphenated, leading both automatic and custom names.
- A live preview of the first filename, so none of the above is a guess.

Scaling resamples the cropped region at high interpolation quality; the crop itself is still taken from the original-resolution source.

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

Slicer keeps a single window. `WindowGroup` opens a fresh one for every Finder or Dock open request, but the session lives in one model, so a second window would only ever be a duplicate view of the first — each new window checks in with `SlicerWindowCoordinator` and closes itself if one is already up. (`Window` would be the tidier scene type, but it never became visible to XCUITest.)

## App target

The target exists in `apps/native-macos/project.yml`:

- Target: `ImageKidSlicer`
- Display name: `ImageKid Slicer`
- Bundle identifier: `com.hakobs.imagekid.slicer`
- Info.plist: hand-written (XcodeGen-generated, gitignored) because `CFBundleDocumentTypes` is an array and `INFOPLIST_KEY_*` build settings only carry scalars.
- Icon: `SlicerAppIcon` in ImageKid's shared asset catalog, matching the other apps' geometry — an 824 body inset 100 on every side of a 1024 canvas, continuous corners, soft drop shadow.
- Category: Graphics & Design
- Minimum macOS target: macOS 14, the repository's deployment target.
- Sandbox: enabled.
- File entitlement: user-selected read/write.
- Network entitlement: none.

Source shape:

```text
apps/native-macos/Sources/ImageKidSlicer/
├── ImageKidSlicerApp.swift     app + delegate (Finder open, quit protection)
├── SlicerWindow.swift          window chrome, empty state, export summary
├── SlicerFilmstrip.swift       the strip of open images
├── SlicerWindowCoordinator.swift  keeps Slicer to a single window
├── SlicerChrome.swift          the dark-glass surfaces and canvas backdrop
├── SlicerHelp.swift            tooltip text, and annotating the live menu
├── ToolTip.swift               AppKit tooltips on SwiftUI controls
├── SlicerToolbar.swift         the floating tool bar, grid and template popovers
├── SlicerCanvas.swift          pointer, guides, grid and snap rendering
├── SliceOverlay.swift          one slice rectangle and its handles
├── CropOverlay.swift           the Crop tool's dimming, thirds and handles
├── SliceListSidebar.swift      the opt-in slices list
├── SliceInspector.swift        the per-slice popover: preview, name, size, anchor
├── SliceThumbnail.swift        a slice's own region, cropped from the preview
├── SlicerDocumentModel.swift   the session: source, slices, guides, grid
├── SliceGeometry.swift         normalised geometry + canvas mapping
├── SliceGuides.swift           guides, grid, auto layout
├── SliceSnapping.swift         snap targets and edge snapping
├── SliceTemplates.swift        built-in and saved templates
├── SliceDetection.swift        gutters, content edges and element detection
├── SlicerSession.swift         the .slicer session document
├── ExportOptions.swift         format, scale, quality, naming + their store
├── ExportOptionsView.swift     the export options popover
├── SliceImageIO.swift          decode, orientation, encode, atomic write
├── SliceExporter.swift         naming, collisions, the export run
└── UITestSupport.swift         the deterministic XCUITest launch arguments
```

The target is also declared in `apps/native-macos/Package.swift`, so `swift build` and `swift test` — and therefore CI — compile it and run its unit tests.

If image I/O or coordinate helpers are already reusable, keep them in existing shared packages rather than copying them into the Slicer target.

## Keyboard commands

First-release commands:

- `Command-O` — open image.
- `Command-S` — save/create all slices.
- `Command-0` — fit image to window.
- `Command-+` / `Command--` — zoom.
- `Delete` / `Backspace` — delete selected slice.
- `Escape` — cancel the current drag/resize operation or clear selection when idle.
- `Command-D` — duplicate the selected slice.
- `Command-E` — open the selected slice's inspector (or double-click the slice).
- `Command-L` / `Shift-Command-L` — lock the selected slice / unlock every slice.
- `Shift-Command-A` — Auto Slice from the current cutting lines.
- `Control-Command-S` — show or hide the slices list.
- `Option-Command-S` — save the session; `Shift-Command-O` — open one.
- `Shift-Command-G` — suggest guides from the sheet's gutters.
- `Shift-Command-D` — detect elements, one slice around each.
- `Command-C` — copy the selected slice as an image.
- Arrow keys — nudge the selection by one source pixel, ten with `Shift`.
- `Shift-Command-S` — export every open image's slices in one run.
- `Option-Command-A` — apply this image's layout to every open image.
- `Shift-Command-W` — close the current image.
- `S` / `G` / `C` — the Slice, Guides, and Crop tools.

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
- a batch queue;
- persistent `.slice` project files;
- a layer inspector;
- an always-visible sidebar (the slices list is opt-in and closed by default);
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

`ImageKidSlicerTests` (SwiftPM, so CI runs it) covers:

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

It also covers guide clamping, auto layout ordering and sliver rejection, grid lines, snap-target collection, move/resize/draw snapping, anchored resizing to a typed pixel size, moving to a typed pixel origin, export format/scale/quality/prefix resolution, template layouts, the crop region and its single-file export, locking, and that every SF Symbol the tool bar names actually resolves on the deployment target.

`ImageKidSlicerUITests` (an XCUITest target on the `ImageKidSlicer` scheme) drives the real app through:

1. open an image, create two slices, resize and move one, delete one, save, and confirm one file per remaining slice;
2. the empty state offering Open and hiding Save;
3. guides feeding Auto Slice, and `Backspace` deleting a selected guide;
4. a template laying out the whole image and exporting;
5. renaming a slice in the sidebar, locking it, and proving a drag that starts on the locked slice draws a new one instead of moving it;
6. double-clicking a slice to open its inspector, renaming it there, and typing an exact size that holds the top-left anchor still;
7. the Crop tool: starting from the whole image, dragging a smaller region, saving it as one file, and switching back to Slice.

Under XCUITest the app and the runner have separate sandbox containers: the app may read the runner's fixtures but not write into them. `--uitest-open <path>` therefore takes a path, while `--uitest-save <name>` takes a folder *name* that the app creates inside its own container, and the save is verified through what the app reports it wrote.

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

Guides, snapping, the grid, templates, renaming, locking, arrow-key nudge, copy to clipboard, drag-out to the Finder, gutter-based suggestions, and session files have all shipped. Still open:

- notarisation and release packaging. Slicer signs with a real identity and archives, but a
  Developer ID Application identity is not installed on the build machine, so a directly
  distributable notarised build cannot be produced yet.

These are enhancements, not requirements. The defining product experience remains:

> Open image → define slices → Save → get all slices.
