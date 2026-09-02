# ImageKid Convert

## Product definition

ImageKid Convert is a focused native macOS app for converting one image or a
batch of images into another format. It should make format, size, transparency,
quality, colour, and metadata consequences visible before files are written.

It is not an image editor and it is not a vectorizer.

## Core promise

> Drop files, choose the output, convert them locally.

No upload, account, credits, or subscription. The app completes every supported
conversion on the Mac.

## Core workflow

1. Drop files or folders, paste files, or use the Open panel.
2. Choose an output preset or format.
3. Review output dimensions, transparency, estimated size where available, and
   any format warnings.
4. Choose the destination and naming rule.
5. Click **Convert**.
6. Reveal, copy, or open the generated files.

The empty window is the drop target. Once files are present, the interface is a
queue with a compact settings area and a persistent Convert action. There is no
canvas editor, layer panel, annotation toolbar, or project format.

## Initial format scope

The first release should support the formats that can be decoded and encoded
reliably on the minimum supported macOS version. The exact matrix must be backed
by codec tests rather than marketing claims.

Planned input coverage:

- PNG
- JPEG
- HEIC/HEIF
- TIFF
- GIF, with explicit static versus animated handling
- BMP
- WebP when the system codec is available and tested
- PDF, with page selection
- SVG, rendered safely as vector input

Planned output coverage:

- PNG
- JPEG
- HEIC/HEIF
- TIFF
- WebP when reliable encoding is available
- PDF

SVG is an input for raster or PDF rendering in ImageKid Convert. The first
release does not promise arbitrary raster-to-SVG conversion, PDF-to-editable-SVG
reconstruction, or SVG source editing. Those jobs belong to Fekthor Trace,
Cleanup, View, and Edit.

## SVG handling

SVG input must retain vector sharpness until the final render. Users choose an
exact pixel size, scale, or PDF page size before output.

The preview and renderer must:

- disable scripts;
- block remote network resources;
- never execute event handlers;
- report missing linked assets;
- preserve transparency where the destination format supports it;
- warn before flattening transparency into JPEG or another opaque format;
- use an explicit background colour when opaque output is selected;
- respect the SVG viewBox and provide a clear fallback when width or height is
  missing.

Animations are not exported to static PNG, JPEG, TIFF, HEIC, or PDF. The preview
may show the source animation, but the user must choose which rendered state or
frame is used. Animated SVG editing belongs to Fekthor Effects.

## PDF handling

- Show every page with its page number and dimensions.
- Allow all pages, a range, or selected pages.
- Export pages as separate files by default.
- Let the user select pixel dimensions, DPI, or a named scale.
- Preserve PDF as PDF only for operations that do not require rasterisation.
- Never claim that a rendered PDF page remains editable vector artwork.

## Batch controls

- Output format.
- Original size, percentage, exact dimensions, or maximum width/height.
- Aspect-ratio lock for exact dimensions.
- Scale mode for mismatched dimensions: fit, fill, stretch, or no resize.
- Lossy quality where the chosen codec supports it.
- Transparency or background fill.
- Colour-profile policy: preserve, convert to sRGB, or remove where safe.
- Metadata policy: preserve, remove private fields, or strip.
- Animation policy for GIF input: preserve when supported, first frame, or a
  selected frame.
- Destination: sibling folder, chosen folder, or next to source.
- Collision-safe filename template.

Per-file overrides can exist, but the common batch settings remain primary. A
mixed queue should clearly mark files that cannot use the chosen option.

## Presets

The first useful presets should express outcomes instead of codec terminology:

- Web image
- Transparent PNG
- High-quality photo
- Smaller photo
- Social image
- PDF page to image
- SVG to PNG
- Strip metadata

Presets are editable values, not opaque processing modes. Selecting one should
show the actual format, dimensions, quality, colour, and metadata settings it
will use.

Convert provides straightforward quality controls for lossy output. Advanced
target-size search, before/after visual comparison, and detailed savings reports
belong to ImageKid Compress.

### Metadata

Metadata is a conversion option and inspector, not a separate product. Convert
shows available EXIF, GPS, camera/device, date, copyright, description, colour,
and orientation categories before processing.

- **Preserve** keeps supported metadata where the destination format permits it.
- **Remove private** removes GPS, device identifiers, serial numbers, embedded
  thumbnails, and other selected private fields.
- **Strip** removes non-essential metadata while retaining information required
  for correct rendering.

The app warns when a format cannot carry selected metadata. Orientation must be
baked or represented correctly before an orientation tag is removed. Metadata
changes are included in the per-file conversion result and JSON output when the
conversion engine is used from a future CLI.

## Queue and progress

Each row shows:

- thumbnail or format icon;
- source filename and format;
- source dimensions and file size;
- planned output filename, format, dimensions, and estimated size when known;
- warning state;
- waiting, processing, done, failed, or cancelled status;
- retry and reveal actions.

Files process serially by default to keep memory and thermal pressure
predictable. A failed file does not stop the remaining queue. The active item
and remaining queue are cancellable.

## Output safety

- Source files are never overwritten by default.
- Default folder name is `ImageKid Converted` beside the source where possible.
- Default filename is `{name}.{output-extension}` when the extension changes,
  otherwise `{name}-converted.{output-extension}`.
- Collisions generate a numbered filename unless explicit overwrite mode is
  enabled.
- Overwrite mode requires confirmation and must never allow source destruction
  when conversion has not completed successfully.
- Write to a temporary file in the destination folder, validate it, then move it
  atomically into place.
- Orientation must be normalised consistently so preview dimensions and output
  pixels agree.

## Finder integration

Planned native integrations:

- Open With support for declared image, PDF, and SVG types.
- Finder Quick Actions for saved presets.
- Services menu support for selected files.
- Drag generated files directly from completed queue rows.

Finder actions must use the same validated conversion pipeline as the main app.
They must not create a second, less safe implementation.

## Accessibility

- The entire queue and settings flow is keyboard accessible.
- Warnings name the file and the consequence, not only a colour or icon.
- Progress is exposed through accessibility values without announcing every
  minor percentage change.
- Format icons are supplementary to text labels.
- Reduced motion is respected.

## Explicit first-release exclusions

- Image editing or annotation.
- Background removal and AI upscaling.
- Raster-to-vector tracing.
- SVG path or style editing.
- Video transcoding.
- OCR.
- Cloud codecs or upload fallback.
- Watch folders and scheduled conversions.
- A proprietary project format.

## Reuse and implementation

Convert should reuse shared decoding, output planning, queue, metadata, colour,
and file-writing code. It may be the point where the initial
`CompanionSupport` queue is promoted into a reusable package.

Suggested boundaries:

```text
packages/
├── ImageKidCore/
├── ImageKidBatch/
│   ├── BatchItem.swift
│   ├── BatchQueue.swift
│   ├── OutputPlanner.swift
│   └── BatchProgress.swift
└── ImageKidConversion/
    ├── ConversionRequest.swift
    ├── FormatCapabilities.swift
    ├── RasterConverter.swift
    ├── PDFRenderer.swift
    ├── SVGRenderer.swift
    └── ConversionValidator.swift
```

Do not extract a package until at least two app targets genuinely use its API.

## Release gates

ImageKid Convert is ready to release only when:

- every advertised input/output pair has fixtures and round-trip or pixel-level
  validation where applicable;
- alpha, orientation, colour profile, page size, and animation-loss warnings are
  correct;
- SVG and PDF rendering cannot access the network or execute scripts;
- cancellation leaves no partial destination file;
- a queue can continue after malformed or unsupported input;
- large-image work does not block the main actor;
- Finder and sandbox permission flows recover cleanly;
- the app is signed, sandboxed, packaged, and tested outside Xcode.

## Proposed app identity

- Target: `ImageKidConvert`
- Display name: `ImageKid Convert`
- Proposed bundle id: `com.hakobs.imagekid.convert`
- Category: Graphics & Design
- Network entitlement: none
