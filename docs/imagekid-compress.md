# ImageKid Compress

## Product definition

ImageKid Compress reduces image file size while showing the visible cost of the
chosen compression. It supports one file or a batch and can optimise for a
quality setting, maximum file size, or total batch size.

It ships as a native macOS app and the `imagekid-compress` CLI.

## Core promise

> Make images smaller. See what changes before saving.

## Core workflow

1. Drop files or folders.
2. Choose smaller, balanced, high quality, exact quality, or target size.
3. Compare original and compressed previews.
4. Review projected savings and metadata policy.
5. Compress to a new folder or explicitly replace sources.

The app shows the resolved codec, dimensions, quality, metadata policy, original
size, output size, and percentage saved.

## Initial formats

Input:

- PNG
- JPEG
- HEIC/HEIF
- TIFF
- WebP where system decoding is available and tested

Output:

- PNG
- JPEG
- HEIC/HEIF
- WebP where encoding is available and tested

GIF animation, PDF, SVG, and video are excluded initially. Compress must not
quietly turn a document or animation into a static image.

## Compression modes

- **Preserve format** optimises within the source format.
- **Choose format** applies one explicit output format to compatible input.
- **Automatic format** chooses the smallest tested result satisfying the quality
  threshold and required capabilities, reporting the choice per file.
- **Target size** searches for the highest tested quality below a byte limit.
- **Target dimensions** resizes explicitly before compression.

## Comparison

Comparison is a Compress capability rather than a separate product:

- split view;
- draggable wipe;
- overlay;
- blink;
- pixel difference;
- matched zoom and pan;
- actual size;
- matched pixel inspection;
- light, dark, and transparent backgrounds.

Batch review prioritises files with the largest savings, largest difference,
failed target, transparency change, or metadata warning.

## Quality information

Show original/output size, savings, dimensions, formats, quality setting, colour
profile, transparency, metadata removed, target result, and clearly labelled
comparison metrics where implemented.

## Metadata

Metadata is part of Compress, not a separate app:

- **Preserve** retains supported EXIF, dates, copyright, camera, colour, and GPS.
- **Remove private** removes GPS, device identifiers, serial numbers, thumbnails,
  and selected private fields while retaining rendering requirements.
- **Strip** removes non-essential metadata.

The inspector shows metadata categories and approximate size. It warns that
removal can also delete authorship, copyright, capture date, and descriptions.
Orientation is baked or represented correctly before its tag is removed.

## Batch controls

- Format mode.
- Quality or target file size.
- Optional dimensions.
- Transparency background.
- Colour-profile policy.
- Metadata policy.
- Destination and naming.
- Explicit source replacement.
- Skip output larger than source, or keep with warning.

## CLI

```sh
imagekid-compress Photos/*.jpg \
  --preset balanced \
  --output Compressed

imagekid-compress Hero.png \
  --format webp \
  --max-size 500KB \
  --output Hero.webp

imagekid-compress Uploads \
  --recursive \
  --metadata remove-private \
  --max-width 2400 \
  --output UploadsCompressed
```

Initial options:

```text
--output <file-or-directory>
--recursive
--preset <smaller|balanced|high-quality|web|email>
--format <preserve|automatic|png|jpeg|heic|webp>
--quality <0...100>
--max-size <bytes|KB|MB>
--max-width <pixels>
--max-height <pixels>
--resize <percent|widthxheight>
--metadata <preserve|remove-private|strip>
--colour-profile <preserve|srgb|strip>
--background <colour>
--keep-larger
--replace-source
--overwrite
--dry-run
--json
```

`--replace-source` allows a validated result to replace its source.
`--overwrite` allows an existing planned destination to be replaced. Both are
off by default.

JSON output reports paths, formats, dimensions, sizes, savings, resolved quality,
target result, metadata changes, colour policy, checksums, and warnings.

See [Focused app command-line tools](focused-cli.md) for shared behaviour.

## Output safety

- Default output is a sibling `ImageKid Compressed` folder.
- Same-directory output uses `{name}-compressed.{extension}`.
- Larger output is skipped by default.
- Source replacement stages and validates before atomic replacement.
- Failure or cancellation leaves the original unchanged.
- Batch totals never count skipped or failed output as saved bytes.

## Accessibility

- Comparison modes have keyboard controls and text summaries.
- Original/output panes expose which side is active.
- Warnings state exact consequences.
- Savings are not communicated by colour alone.
- Reduced motion disables automatic blinking.

## First-release exclusions

- Video/audio compression.
- Animated image preservation.
- PDF optimisation.
- SVG minification, which belongs to Fekthor Cleanup.
- Cloud codecs or AI reconstruction.
- Watch folders.
- A separate metadata editor.

## Shared implementation

```text
packages/ImageKidCompression/
├── CompressionRequest.swift
├── FormatCapabilities.swift
├── CompressionPlanner.swift
├── QualitySearch.swift
├── TargetSizeSearch.swift
├── MetadataPolicy.swift
├── ImageComparator.swift
├── CompressionResult.swift
└── CompressionValidator.swift
```

The app and CLI both depend on this package. `ImageComparator` may also be used
by the flagship ImageKid editor.

## Release gates

- App and CLI produce equivalent output.
- Target-size mode finds the highest tested quality satisfying the limit.
- Alpha, orientation, metadata, and colour remain correct.
- Removing orientation metadata never changes visible orientation.
- Private-metadata removal has GPS and device-identifier fixtures.
- Source replacement is atomic.
- Large batches stay within a documented memory boundary.
- Savings totals match actual files.
- Comparison uses the decoded output that will be written.

## Proposed identity

- App target: `ImageKidCompress`
- CLI target: `imagekid-compress`
- Display name: `ImageKid Compress`
- Proposed bundle id: `com.hakobs.imagekid.compress`
- Category: Graphics & Design
- Network entitlement: none
