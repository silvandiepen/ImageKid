# Focused app family

## Decision

ImageKid and Fekthor can produce focused macOS apps that each finish one clear
job. These are separate products, not reduced editions of the flagship editors.

The family is split by the kind of source material being changed:

- **ImageKid** handles raster images, image files, conversion, and pixel output.
- **Fekthor** handles SVG structure, vector geometry, presentation attributes,
  interactive states, and SVG animation.

Every focused app must be useful without owning ImageKid or Fekthor. Code can be
shared through packages, but apps never import from another app.

## Product principles

- One obvious job per app.
- Native macOS interaction and file handling.
- Local processing by default.
- No account, subscription, credits, telemetry, ads, or hosted processing.
- One-time purchase.
- Never overwrite source files implicitly.
- Show the result before export whenever the operation changes appearance.
- Preserve unsupported SVG content instead of silently deleting it.
- Be honest about format changes. Rendering an SVG to PNG is conversion;
  tracing a PNG into paths is vectorization.

The product promise is:

> Buy the tool once. Use your own Mac. Keep your files local.

## Agreed range

| App | Core job | Initial state |
| --- | --- | --- |
| ImageKid Convert | Convert and batch-export image files, including rendering SVG and PDF input | Planned |
| [ImageKid AppIcons](imagekid-appicons.md) | Turn one source into complete app icon and favicon packages | Planned with CLI |
| [ImageKid Sheet](imagekid-sheet.md) | Combine images into contact sheets, sprite sheets, or reference sheets | Planned with CLI |
| [ImageKid Compress](imagekid-compress.md) | Reduce image file sizes with direct visual quality comparison | Planned with CLI |
| Fekthor Effects | Add CSS-based states and motion to SVG elements | Planned from existing animation engine |
| Fekthor Trace | Turn raster artwork into editable SVG paths | Planned focused product; quality gate remains |
| Fekthor Cleanup | Repair, normalise, and reduce SVG files without changing their appearance | Planned |
| Fekthor View | View SVGs and their animations, with an optional inspector | Planned |
| Fekthor Edit | Make basic visual and structural corrections to an SVG | Planned |

See [ImageKid Convert](imagekid-convert.md) and the
[Fekthor focused apps](fekthor/FOCUSED-APPS.md) for the product definitions.

## Relationship to the flagship apps

ImageKid and Fekthor remain broader editors. The focused products exist because
many people do not need a full creative workspace for a small, repeated job.

- Use **ImageKid Convert** to turn one or many files into another image format.
- Use **Fekthor Effects** to define hover, focus, active, and automatic motion.
- Use **Fekthor Trace** to convert pixels into paths when the trace is good enough
  to remain editable.
- Use **Fekthor Cleanup** to repair or simplify SVG source.
- Use **Fekthor View** to open and understand an SVG without editing it by
  default.
- Use **Fekthor Edit** to crop the canvas, edit paths, recolour artwork, or change
  strokes without opening the complete Fekthor workspace.
- Use the flagship apps when work crosses several of these workflows or needs
  deeper creative tools.

Cross-promotion may exist, but it must be quiet. A focused app cannot make its
core action depend on installing or buying another product.

## Shared implementation direction

Focused products should reuse engines, models, codecs, and controls through
packages:

- `ImageKidCore` and Image I/O for raster decoding, colour, metadata, and export.
- `ImageKidKit` for shared native controls and file presentation.
- `ImageKidInference` only where a product explicitly needs an on-device model.
- `FekthorKit` for SVG parsing, scene structure, geometry, tracing, animation,
  cleanup, deterministic serialization, and validation.

The current `FekthorTrace` source target contains the broad Fekthor editor. Its
name must not be treated as proof that the focused Fekthor Trace product is
already complete. Before separate products ship, the flagship target should be
named unambiguously and each focused app should receive its own target and
bundle identity.

## Recommended release order

1. **ImageKid Convert**. It has a clear job, deterministic output, broad search
   intent, and no quality dependency on an ML model.
2. **Fekthor View**. It is a small surface that validates secure SVG loading,
   animation playback, inspection, and the shared renderer.
3. **Fekthor Cleanup**. It builds on parsing and serialization while producing a
   measurable before and after result.
4. **Fekthor Edit**. It adds controlled mutation once viewing, parsing, saving,
   and round-trip preservation are trusted.
5. **Fekthor Effects**. Much of the underlying animation model exists, but the
   focused state editor and web export workflow still need a smaller interface.
6. **Fekthor Trace**. Release only after representative artwork passes the
   quality and editability gate. The name promises a good vector result, so a
   technically working trace is not enough.

This is an implementation order, not a commercial ranking. Effects may be more
distinctive commercially than View or Cleanup once it is ready.

## Further ImageKid candidates

Three additional focused ImageKid products are planned. Their workflows are
clearer than adding more modes to Convert. Each ships with a command-line tool;
see the shared [focused CLI contract](focused-cli.md).

### ImageKid AppIcons

Prepare one source image or SVG as app icons, favicons, and named PNG sizes. It
would manage padding, background, safe-area preview, light/dark variants, and
asset-catalog export. The result is concrete and the workflow is more than
generic conversion. See [ImageKid AppIcons](imagekid-appicons.md).

### ImageKid Sheet

Combine a folder of images into a contact sheet, sprite sheet, or labelled
reference sheet. It is the inverse companion to ImageKid Slicer and has a clear
input-to-output demonstration. See [ImageKid Sheet](imagekid-sheet.md).

### ImageKid Compare

Open two images and compare them with split, overlay, blink, difference, and
pixel-dimension views. This is useful for generated assets, compression checks,
design revisions, and before/after work, but it is not currently strong enough
as a standalone product. The comparison controls should become shared UI used
by ImageKid Compress and the flagship ImageKid editor.

### ImageKid Metadata

Inspect, copy, and remove EXIF, GPS, colour-profile, and other image metadata in
one file or a batch. This is not a separate product. Metadata inspection and
preserve/strip controls belong in ImageKid Convert, ImageKid Compress, and the
flagship ImageKid inspector where relevant.

### ImageKid Compress

Compare file size and visible quality, then batch-compress images to a target
format, quality, or maximum size. The first Convert version still has basic
lossy quality controls. Compress is a separate product because it adds live
before/after comparison, target-size search, and batch size-saving reports. See
[ImageKid Compress](imagekid-compress.md).

## Ideas deliberately kept out

- A generic ImageKid or Fekthor Lite app. The scope would be unclear and would
  repeat the flagship problem.
- A separate SVG converter. ImageKid Convert already renders SVG to raster/PDF;
  Fekthor owns SVG-aware changes.
- A separate Fekthor Inspector. Inspection belongs inside Fekthor View.
- A separate ImageKid Compare. Comparison is shared by Compress and ImageKid.
- A separate ImageKid Metadata. Metadata controls belong to Convert, Compress,
  and ImageKid.
- A separate vector crop tool. Canvas and viewBox cropping belongs inside
  Fekthor Edit, with automatic bounds repair also available in Cleanup.
- Cloud image generation or token-based processing. It conflicts with the local,
  one-time-purchase purpose of the focused range.
