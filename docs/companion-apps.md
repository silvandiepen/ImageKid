# Companion apps

## Current status

ImageKid currently has implemented macOS targets for three companion apps:

- `ImageKidUpscale` / display name `ImageKid Upscale` / bundle id `com.hakobs.imagekid.upscale` — implemented.
- `ImageKidCutout` / display name `ImageKid Cutout` / bundle id `com.hakobs.imagekid.cutout` — implemented.
- `ImageKidSlicer` / display name `ImageKid Slicer` / bundle id `com.hakobs.imagekid.slicer` — first implementation; see [ImageKid Slicer](slicer.md).

Upscale and Cutout currently share lightweight batch UI and file I/O helpers under `apps/native-macos/Sources/CompanionSupport`. They can open or accept dropped image files, show a queue with thumbnails and per-file status, process files serially on device, and write outputs to a sibling folder or a user-chosen folder. Upscale supports the always-available Core Image path and a Best Quality Core ML path. Cutout supports Apple Vision background removal and a Best Quality Core ML path. The companion apps include model install controls and reuse ImageKid's shared App Group model cache when signed with `group.com.hakobs.imagekid`. Richer output controls, retry/reveal actions, and release packaging are still planned work.

ImageKid remains the full editor and the product where the complete toolset keeps growing. Companion apps are deliberately smaller, cheaper, single-purpose utilities built from the same local-processing foundation:

- **ImageKid Upscale**: batch upscale images.
- **ImageKid Cutout**: batch remove image backgrounds.
- **ImageKid Slicer**: open one composite image, manually define rectangular regions, and save every region as a separate image.

They are separate app targets, not feature modes inside the main ImageKid window. Their job is to make one repeated or focused operation fast and obvious for users who do not need the full editor in that moment.

## Product strategy

These apps exist because many users have one recurring or narrowly defined job: upscale a folder of images, remove backgrounds from a batch of product shots, icons, portraits, or generated assets, or split a generated/reference sheet into individual images. Hosted tools often add subscriptions, credits, uploads, or excessive UI to jobs that can run locally on the user's own machine.

The companion-app promise is:

> Pay once, do the focused job locally, keep using it.

Positioning:

- **ImageKid** is the flagship app: complete editor, inspection, manual correction, multiple tools, export control, Magic, and future workflows.
- **ImageKid Upscale** is a focused batch upscaler: cheaper, simpler, fast to understand, made for repeated local upscaling.
- **ImageKid Cutout** is a focused batch background remover: cheaper, simpler, made for repeated local transparent cutouts.
- **ImageKid Slicer** is a focused sheet splitter: open one image, draw the regions to extract, then save all slices in one action.

The companion apps should be lower-priced one-time purchases. They should not require accounts, subscriptions, credits, hosted processing, telemetry, or lock-in. Exact pricing is a release/business decision, but the UX and copy should make the value clear: local processing without paying a service every time.

## Companion app shapes

Not every companion app must use the same interface. The shared rule is **one obvious job**, not **one identical UI**.

### Batch companions

ImageKid Upscale and ImageKid Cutout open to a queue. Users can drop one or more image files, choose processing settings, choose output behavior, then click **Generate**. The app processes the queue one item at a time, shows progress per file and overall progress, and writes deterministic output files.

Batch companions should feel simpler than ImageKid:

- no annotation tools;
- no magic prompt editing;
- no multi-tool toolbar;
- no canvas editing;
- no project/session concept;
- no video support in the first release.

### Canvas companion

ImageKid Slicer is different because the operation requires direct spatial input. It opens one image and uses the image itself as the canvas. Users draw, move, resize, and delete rectangular slice overlays, then click **Save** to choose a folder and create all slices.

Slicer must not inherit the batch queue simply for consistency. It should have:

- one image per window;
- no permanent sidebar or inspector;
- no project/import flow;
- direct rectangle manipulation;
- source-resolution export from the original image;
- no AI or automatic detection in the first release;
- no persistent project file in the first release.

See [ImageKid Slicer](slicer.md) for the full product and technical definition.

## Shared principles

All companion apps follow these rules:

- Processing is on-device.
- Pricing is one-time purchase, not subscription or credit based.
- The apps should be useful immediately without an account.
- Source files are never overwritten implicitly.
- Output naming must avoid collisions unless an explicit overwrite mode exists.
- Heavy image decoding, processing, encoding, and file writes must not block the main actor.
- Errors should be reported without losing successful work.
- Native macOS file panels, menus, shortcuts, drag and drop, accessibility, and sandbox behavior are first-class requirements.
- Apple frameworks are preferred before third-party dependencies.
- A companion app must complete its own core promise without requiring the full ImageKid app.

Batch-specific principles for Upscale and Cutout:

- Multiple files can be dropped or added through an Open panel.
- The queue supports remove, clear completed, retry failed, and reveal output.
- Files process serially by default to keep memory and thermal pressure predictable.
- Users can cancel the active item and stop the remaining queue.
- Errors are shown per file without aborting the full queue unless the user stops it.
- Optional Best Quality models are stored under the shared ImageKid App Group when available, so ImageKid, ImageKid Upscale, and ImageKid Cutout do not each download their own copy.

## ImageKid Upscale

### Core workflow

1. Drop images into the queue.
2. Choose scale: `2x`, `4x`, `8x`, or custom percentage.
3. Choose quality engine:
   - **Standard**: always available, fast, deterministic Core Image path.
   - **Best Quality**: Core ML upscaler when installed in the shared model cache.
4. Choose content mode:
   - Automatic.
   - Photos/artwork.
   - Screenshots/UI.
5. Choose output destination.
6. Click **Generate**.

### Queue row

Each row should show:

- thumbnail;
- filename;
- original dimensions;
- target dimensions;
- output path;
- status: waiting, processing, done, failed, cancelled;
- progress indicator;
- remove/retry/reveal controls.

### Output options

Default behavior should be safe:

- Output folder defaults to a sibling folder named `ImageKid Upscaled`.
- Output filename defaults to `{name}-upscaled-{scale}.{ext}`.
- Original format is preserved when practical.
- PNG transparency is preserved.
- JPEG/HEIC quality defaults should avoid unexpected huge files.

Advanced output options:

- Choose destination folder.
- Save next to originals.
- Overwrite originals, behind confirmation.
- Format: original, PNG, JPEG, HEIC.
- Quality slider for lossy formats.
- Metadata policy: keep or strip.

### Processing implementation

Use `packages/ImageKidInference` as the shared engine boundary:

- `CoreImageUpscaler` for Standard.
- `CoreMLUpscaler` for Best Quality.
- `TilePlanner` for large images.

The queue runner must capture immutable inputs before processing starts: source URL, output URL, scale, engine, content mode, format, and quality. Results should only write to that captured output target.

## ImageKid Cutout

### Core workflow

1. Drop images into the queue.
2. Choose background removal quality:
   - **Built-in**: Apple Vision, always available.
   - **Best Quality**: Core ML cutout model when installed in the shared model cache.
3. Choose edge treatment:
   - Clean.
   - Soft edge.
   - Preserve fine hair/detail.
4. Choose output destination.
5. Click **Generate**.

### Queue row

Each row should show:

- thumbnail;
- filename;
- original dimensions;
- output format;
- output path;
- status and progress;
- quick before/after preview where cheap enough;
- remove/retry/reveal controls.

### Output options

Default behavior should make transparency obvious and safe:

- Output folder defaults to a sibling folder named `ImageKid Cutouts`.
- Output filename defaults to `{name}-cutout.png`.
- PNG is the default because it preserves alpha.
- If overwrite is enabled and the source is JPEG/HEIC, warn that transparency requires PNG or a background fill.

Advanced output options:

- Choose destination folder.
- Save next to originals.
- Overwrite originals, only when the selected format can represent the result safely.
- Format: PNG, TIFF, WebP if supported later.
- Optional background fill color for JPEG/HEIC exports.
- Metadata policy: keep or strip.

### Processing implementation

Use `packages/ImageKidInference` as the shared engine boundary:

- `VisionBackgroundRemover` for Built-in.
- `CoreMLBackgroundRemover` for Best Quality.

The first version should not include manual mask refinement. If refinement is needed, open the file in full ImageKid.

## ImageKid Slicer

### Core workflow

1. Open, paste, or drop one image containing multiple desired regions.
2. Drag on the image to create a rectangular slice.
3. Create as many slices as needed.
4. Move or resize slices directly on the image.
5. Click **Save**.
6. Choose a destination folder.
7. Create one source-resolution image file per valid slice.

There is no separate export/settings screen in the first release. `Command-S` performs the same Save action.

### Slice behavior

- New slices receive deterministic names such as `Slice 1`, `Slice 2`, and `Slice 3`.
- The selected slice shows resize handles.
- Drag inside a selected slice to move it.
- Drag handles to resize it.
- `Delete` / `Backspace` removes it.
- `Shift` while creating or resizing constrains to a square.
- Slice geometry remains tied to source-image coordinates regardless of fit/zoom/window size.
- Export resolves geometry against the original orientation-correct source pixels, not the screen preview.

### Output behavior

- Source files are never modified.
- Default naming is `{source-name}-slice-01.{ext}`, `{source-name}-slice-02.{ext}`, and so on.
- Preserve the source format when Image I/O can safely encode it; otherwise fall back to PNG.
- Existing files are never overwritten silently; generate a collision-safe numbered filename.
- Export slices serially and atomically.
- If one slice fails, continue creating the remaining valid slices and report the failure at completion.

### Explicit first-release exclusions

Slicer does not initially include automatic object detection, AI slice detection, whitespace/grid detection, multiple source images, batch queues, persistent `.slice` projects, polygon slices, editing/annotation tools, sprite metadata, or export-setting panels.

See [ImageKid Slicer](slicer.md) for detailed interaction, coordinate, implementation, accessibility, testing, safety, and acceptance criteria.

## App targets

Current implemented native macOS companion targets:

- `ImageKidUpscale`
  - Display name: `ImageKid Upscale`
  - Bundle id: `com.hakobs.imagekid.upscale`
  - Category: Graphics & Design

- `ImageKidCutout`
  - Display name: `ImageKid Cutout`
  - Bundle id: `com.hakobs.imagekid.cutout`
  - Category: Graphics & Design

Planned native macOS companion target:

- `ImageKidSlicer`
  - Display name: `ImageKid Slicer`
  - Proposed bundle id: `com.hakobs.imagekid.slicer`
  - Category: Graphics & Design
  - No network entitlement.

Upscale and Cutout should continue using shared batch-processing support rather than importing UI code from the main app. Slicer should reuse clean image I/O and coordinate helpers where appropriate, but should not depend on the batch queue because its core interaction is canvas-based.

Suggested batch shared code:

```text
packages/
├── ImageKidInference/
└── ImageKidBatch/
    ├── BatchItem.swift
    ├── BatchQueue.swift
    ├── OutputPlanner.swift
    ├── ImageLoader.swift
    ├── ImageWriter.swift
    └── BatchProgress.swift
```

Potential Slicer-specific source should remain under `apps/native-macos/Sources/ImageKidSlicer` unless a helper is genuinely reusable by multiple apps.

## UI architecture

### Upscale and Cutout

Use the same high-level batch layout:

- title/header with short current action;
- large drop zone when the queue is empty;
- compact settings bar above the queue when files exist;
- queue list;
- sticky bottom bar with destination, overwrite mode, total count, and **Generate**;
- progress overlay only for queue-level work, never blocking row-level status.

On macOS, support:

- drag and drop;
- Open panel;
- paste image files from Finder;
- `Command-O` to add files;
- `Command-Delete` to remove selected queue rows;
- `Command-R` to retry failed rows;
- `Command-Period` / `Escape` to cancel processing.

### Slicer

Use a media-first canvas:

- large open/drop affordance only while empty;
- source image fitted to the available window;
- minimal **Open** and **Save** controls;
- rectangular overlays directly on the image;
- contextual resize handles only for the selected slice;
- no permanent sidebar, settings bar, queue, or inspector;
- native menus for keyboard-discoverable actions.

Primary shortcuts:

- `Command-O` — open image;
- `Command-S` — create/save all slices;
- `Command-0` — fit image;
- `Command-+` / `Command--` — zoom;
- `Delete` / `Backspace` — delete selected slice;
- `Escape` — cancel active interaction or clear selection.

## Safety rules

Shared:

- Do not overwrite source files by default.
- If an output already exists, generate a numbered filename unless an explicit overwrite mode is active.
- Write to a temporary file in the destination folder, then atomically move into place.
- Failed outputs should be removed unless they are a previous successful file.
- Large image decoding, processing, encoding, and file writes must not run synchronously on the main actor.

Batch apps:

- Overwrite mode requires explicit confirmation when enabled.
- Processing must be cancellable between expensive steps.
- One failed queue item does not abort later queue items.

Slicer:

- Never modify the source.
- Clamp every slice to source bounds.
- Reject zero-sized or invalid crop rectangles.
- Resolve export geometry from the original orientation-correct image.
- One failed slice should not prevent remaining valid slices from exporting.

## Relationship to ImageKid

ImageKid remains the place for inspection, editing, manual correction, and creative workflows. Companion apps are narrower tools:

- Use **ImageKid Upscale** when every file needs the same scale/quality treatment.
- Use **ImageKid Cutout** when every file needs a transparent cutout.
- Use **ImageKid Slicer** when one image contains several assets or views that need to become separate files.
- Use **ImageKid** when a file needs review, cropping, text, selection work, mask refinement, export tuning, annotations, or magic edits.

The companion apps should never force users into ImageKid for their core promise. Upscale must complete batch upscaling on its own. Cutout must complete batch background removal on its own. Slicer must complete manual multi-region extraction on its own. Cross-promotion can exist, but it should be quiet and useful.

## Release sequence

Upscale/Cutout progress:

1. Add shared batch/image I/O helpers for companion app targets. Done for the initial macOS implementation under `apps/native-macos/Sources/CompanionSupport`; promote to `ImageKidBatch` if/when more targets need it.
2. Build `ImageKid Upscale` with Standard upscaling only. Done for the initial macOS implementation.
3. Build `ImageKid Cutout` with Built-in Vision removal only. Done for the initial macOS implementation.
4. Add Best Quality Core ML upscaling and model availability UI. Done for the initial macOS implementation.
5. Add Best Quality Core ML background removal and model availability UI. Done for the initial macOS implementation.
6. Add shared queue tests for output planning, overwrite behavior, cancellation, and per-file error handling.
7. Add signed archive/export configuration for the macOS apps.
8. Decide whether companion apps ship as separate App Store apps, separate direct-download apps, or a bundle.
9. Define one-time purchase pricing, bundle pricing with ImageKid, and upgrade/cross-sell copy.

Slicer implementation sequence:

1. Add `ImageKidSlicer` macOS target with sandboxed user-selected file access and no network entitlement.
2. Reuse or extract orientation-correct image loading and coordinate mapping from existing shared code.
3. Build one-image fit/zoom/pan canvas.
4. Add create/select/move/resize/delete rectangle interactions.
5. Add normalized-to-source-pixel geometry conversion and tests.
6. Add Save-to-folder export with deterministic naming, collision protection, and atomic writes.
7. Add close/replace-source protection for unsaved slice definitions.
8. Add accessibility and UI smoke coverage.
9. Add signing, icon, product copy, and release packaging.

## Open decisions

Suite-level:

- Final naming: `ImageKid Cutout` vs `ImageKid Background Remove`.
- Exact one-time purchase price for each companion app.
- Whether ImageKid owners get companion apps bundled, discounted, or independent.
- Whether companion apps should remain macOS-first or also move to iOS/iPadOS where their workflows make sense.
- Whether companion apps share a visual identity with ImageKid or use simpler utility branding.

Upscale/Cutout:

- Whether Best Quality models are bundled by default or installed on demand.
- Whether output settings should be global per queue only, or overridable per row.

Slicer:

- Whether slice renaming belongs in the first release or remains automatic numbering only.
- Whether `Command-D` duplicate ships immediately.
- Whether output should preserve source encoding automatically or use PNG as the universal first-release output.
- Whether arrow-key nudging/numeric geometry belongs in the first release or a later precision update.
