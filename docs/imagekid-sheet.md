# ImageKid Sheet

## Product definition

ImageKid Sheet combines multiple images into a contact sheet, labelled reference
sheet, or sprite sheet. It is the inverse companion to ImageKid Slicer.

It ships as a native macOS app and the `imagekid-sheet` CLI.

## Core promise

> Drop images. Arrange them. Export one clean sheet.

## Output modes

### Contact sheet

Create a printable or shareable grid with optional filenames, labels,
dimensions, and page headers.

### Reference sheet

Create a presentation-oriented board with controlled spacing, background,
labels, and title. Layout remains grid or flow based and deterministic.

### Sprite sheet

Pack images into a transparent atlas and export machine-readable frame data.
The initial metadata formats are JSON and CSS.

## Core workflow

1. Drop files, folders, or paste images.
2. Choose Contact, Reference, or Sprite mode.
3. Reorder images or choose a deterministic sort.
4. Choose grid, spacing, labels, background, and output size.
5. Preview the complete sheet.
6. Export the image or PDF and optional metadata.

## Inputs

- PNG
- JPEG
- HEIC/HEIF
- TIFF
- GIF with an explicit selected or first frame
- WebP where the system codec is available and tested
- PDF page
- SVG rendered safely at a chosen size

Folders are recursive only with an explicit option. Hidden files and package
contents are ignored by default.

## Layout controls

Shared:

- Manual, filename, date, dimension, or file-size ordering.
- Rows, columns, fixed cell size, or automatic fit.
- Horizontal and vertical gap.
- Outer padding.
- Background colour or transparency.
- Fit, fill, stretch, or original-size placement.
- Per-image alignment.
- Sheet dimensions, paper size, or maximum dimension.

Contact/reference:

- Filename, custom label, dimensions, file size, or no caption.
- Caption position and text style.
- Header/title and optional footer.
- Page margins.
- Single sheet or paginated PDF.

Sprite:

- Trim transparent bounds.
- Extrude edge pixels.
- Frame padding.
- Power-of-two canvas.
- Maximum atlas dimensions.
- Preserve input order or optimise packing.
- Top-left or bottom-left coordinate origin.
- Optional frame rotation recorded in metadata.
- Split into numbered atlases when the maximum is exceeded.

## Manual adjustments

- Drag or use keyboard actions to reorder.
- Remove an item without deleting its source.
- Replace an item while preserving its position and label.
- Change an individual image's fit and focal position.
- Edit a custom caption.

There is no arbitrary freeform placement, vector drawing, or layer system in the
first release.

## Output

Contact/reference:

- PNG
- JPEG
- HEIC/HEIF
- TIFF
- Single or multi-page PDF

Sprite:

- PNG atlas
- JSON frame metadata
- CSS background classes

An optional manifest records source checksums, resolved order, layout
configuration, frame rectangles, output dimensions, and tool version.

## CLI

```sh
imagekid-sheet Frames/*.png \
  --mode sprite \
  --output Character.png \
  --metadata Character.json

imagekid-sheet Photos \
  --mode contact \
  --columns 4 \
  --labels filename \
  --output ContactSheet.pdf

imagekid-sheet References/*.png \
  --mode reference \
  --width 2400 \
  --gap 24 \
  --background '#f4f1eb' \
  --output Reference.png
```

Initial options:

```text
--mode <contact|reference|sprite>
--output <path>
--metadata <path>
--metadata-format <json|css>
--recursive
--sort <input|filename|created|dimensions|size>
--rows <count>
--columns <count>
--cell <width>x<height>
--width <pixels>
--height <pixels>
--gap <pixels>
--padding <pixels>
--background <transparent|colour>
--fit <contain|cover|stretch|original>
--labels <none|filename|dimensions|size>
--title <text>
--trim
--extrude <pixels>
--power-of-two
--max-size <width>x<height>
--origin <top-left|bottom-left>
--overwrite
--dry-run
--json
```

Shell glob expansion is performed by the shell. A directory adds its supported
direct children unless `--recursive` is used. Input order remains stable unless
sorting or packing optimisation changes it.

JSON output reports the sheet/atlas and metadata paths, dimensions, format,
input count, page/atlas count, resolved order, frame rectangles, rotation flags,
byte sizes, checksums, and skipped inputs.

See [Focused app command-line tools](focused-cli.md) for shared behaviour.

## Accessibility

- Reordering has keyboard actions.
- Every preview item exposes its filename, position, and caption.
- Layout controls expose exact values.
- Errors identify affected sources and whether they were skipped.

## First-release exclusions

- Freeform mood-board placement.
- Image editing or annotation.
- AI layout.
- Video contact sheets.
- Animated sprite export.
- Game-engine texture compression.
- Publishing or uploading.

## Shared implementation

```text
packages/ImageKidSheet/
├── SheetRequest.swift
├── SheetItem.swift
├── GridLayout.swift
├── FlowLayout.swift
├── SpritePacker.swift
├── SheetRenderer.swift
├── CaptionRenderer.swift
├── FrameMetadata.swift
├── SheetManifest.swift
└── SheetValidator.swift
```

The app and CLI both depend on this package.

## Release gates

- App and CLI produce equivalent deterministic layouts.
- Sprite coordinates decode back to the correct source pixels.
- Trim, extrusion, rotation, and origin are represented correctly in metadata.
- Multi-atlas output is deterministic.
- PDF pagination does not clip content.
- Large sets do not retain every full-resolution decode in memory.
- Missing files do not silently reorder successful input.
- Output and manifest writes are atomic.

## Proposed identity

- App target: `ImageKidSheet`
- CLI target: `imagekid-sheet`
- Display name: `ImageKid Sheet`
- Proposed bundle id: `com.hakobs.imagekid.sheet`
- Category: Graphics & Design
- Network entitlement: none
