# Companion apps

## Current status

ImageKid now has initial macOS targets for the two companion apps:

- `ImageKidUpscale` / display name `ImageKid Upscale` / bundle id `com.hakobs.imagekid.upscale`.
- `ImageKidCutout` / display name `ImageKid Cutout` / bundle id `com.hakobs.imagekid.cutout`.

Both apps currently share lightweight batch UI and file I/O helpers under `apps/native-macos/Sources/CompanionSupport`. They can open or accept dropped image files, show a queue with thumbnails and per-file status, process files serially on device, and write outputs to a sibling folder or a user-chosen folder. Upscale uses the always-available Core Image path. Cutout uses Apple Vision background removal. Best Quality model install/download UI, richer output controls, retry/reveal actions, and release packaging are still planned work.

ImageKid remains the full editor and the product where the complete toolset keeps growing. The companion apps are deliberately smaller, cheaper, single-purpose batch utilities built from the same local processing foundation:

- **ImageKid Upscale**: batch upscale images.
- **ImageKid Cutout**: batch remove image backgrounds.

They are separate app targets, not separate feature modes inside the main ImageKid window. Their job is to make one repeated operation fast and obvious for users who do not need the full editor in that moment.

## Product strategy

These apps exist because many users have one recurring job: upscale a folder of images, or remove backgrounds from a batch of product shots, icons, portraits, or generated assets. Hosted services often charge subscriptions, credits, or high per-batch prices for work that can run locally on the user's own machine.

The companion-app promise is:

> Pay once, drop in a batch, run it locally, keep using it.

Positioning:

- **ImageKid** is the flagship app: complete editor, inspection, manual correction, multiple tools, export control, Magic, and future workflows.
- **ImageKid Upscale** is a focused batch upscaler: cheaper, simpler, fast to understand, made for repeated local upscaling.
- **ImageKid Cutout** is a focused batch background remover: cheaper, simpler, made for repeated local transparent cutouts.

The companion apps should be lower-priced one-time purchases. They should not require accounts, subscriptions, credits, hosted processing, telemetry, or lock-in. Exact pricing is a release/business decision, but the UX and copy should make the value clear: local batch processing without paying a service every time.

## Product shape

Each app opens to a queue. Users can drop one or more image files, choose processing settings, choose output behavior, then click **Generate**. The app processes the queue one item at a time, shows progress per file and overall progress, and writes deterministic output files.

The apps should feel simpler than ImageKid:

- no annotation tools;
- no magic prompt editing;
- no multi-tool toolbar;
- no canvas editing;
- no project/session concept;
- no video support in the first release.

## Shared principles

- Processing is on-device.
- Pricing is one-time purchase, not subscription or credit based.
- The apps should be useful immediately without an account.
- Multiple files can be dropped or added through an Open panel.
- The queue supports remove, clear completed, retry failed, and reveal output.
- Files process serially by default to keep memory and thermal pressure predictable.
- Users can cancel the active item and stop the remaining queue.
- Source files are never overwritten unless the user explicitly chooses overwrite mode.
- Output naming must avoid collisions unless overwrite mode is active.
- Errors are shown per file without aborting the full queue unless the user stops it.

## ImageKid Upscale

### Core workflow

1. Drop images into the queue.
2. Choose scale: `2x`, `4x`, `8x`, or custom percentage.
3. Choose quality engine:
   - **Standard**: always available, fast, deterministic Core Image path.
   - **Best Quality**: Core ML upscaler when bundled or installed.
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
   - **Best Quality**: Core ML cutout model when bundled or installed.
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

## App targets

Add two native macOS targets in `apps/native-macos/project.yml` or split into dedicated folders if the code grows:

- `ImageKidUpscale`
  - Display name: `ImageKid Upscale`
  - Proposed bundle id: `com.hakobs.imagekid.upscale`
  - Category: Graphics & Design

- `ImageKidCutout`
  - Display name: `ImageKid Cutout`
  - Proposed bundle id: `com.hakobs.imagekid.cutout`
  - Category: Graphics & Design

Both targets should depend on a shared batch-processing package/module rather than importing UI code from the main app.

Suggested shared code:

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

## UI architecture

Use the same high-level layout for both apps:

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
- Command-O to add files;
- Command-Delete to remove selected queue rows;
- Command-R to retry failed rows;
- Command-Period/Escape to cancel processing.

## Safety rules

- Do not overwrite by default.
- Overwrite mode requires an explicit confirmation when enabled.
- If an output already exists, generate a numbered filename unless overwrite is active.
- Write to a temporary file in the destination folder, then atomically move into place.
- Failed outputs should be removed unless they are a previous successful file.
- Queue processing must not run on the main actor.
- Large image decoding, model inference, encoding, and file writes must be cancellable between steps.

## Relationship to ImageKid

ImageKid should remain the place for inspection, editing, manual correction, and creative workflows. It keeps all features and remains the app that receives the most complete product investment. The companion apps are narrower batch tools:

- Use **ImageKid Upscale** when every file needs the same scale/quality treatment.
- Use **ImageKid Cutout** when every file needs a transparent cutout.
- Use **ImageKid** when a file needs review, cropping, text, selection work, mask refinement, export tuning, or magic edits.

The companion apps should never force users into ImageKid for their core promise. Upscale must complete batch upscaling on its own. Cutout must complete batch background removal on its own. Cross-promotion can exist, but it should be quiet and useful: for example, "Open in ImageKid" for manual refinement after a failed or imperfect output.

## Release sequence

1. Add shared batch/image I/O helpers for the companion app targets. Done for the initial macOS implementation under `apps/native-macos/Sources/CompanionSupport`; promote to `ImageKidBatch` if/when more targets need it.
2. Build `ImageKid Upscale` with Standard upscaling only. Done for the initial macOS implementation.
3. Build `ImageKid Cutout` with Built-in Vision removal only. Done for the initial macOS implementation.
4. Add Best Quality Core ML upscaling and model availability UI.
5. Add Best Quality Core ML background removal and model availability UI.
6. Add shared queue tests for output planning, overwrite behavior, cancellation, and per-file error handling.
7. Add signed archive/export configuration for all three macOS apps.
8. Decide whether the companion apps ship as separate App Store apps, separate direct-download apps, or a bundle.
9. Define one-time purchase pricing, bundle pricing with ImageKid, and upgrade/cross-sell copy.

## Open decisions

- Final naming: `ImageKid Cutout` vs `ImageKid Background Remove`.
- Exact one-time purchase price for each companion app.
- Whether ImageKid owners get the companion apps bundled, discounted, or independent.
- Whether the companion apps should be macOS-only first or also iOS/iPadOS.
- Whether Best Quality models are bundled by default or installed on demand.
- Whether output settings should be global per queue only, or overridable per row.
- Whether the apps share a visual identity with ImageKid or use simpler utility branding.
