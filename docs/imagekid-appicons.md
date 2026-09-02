# ImageKid AppIcons

## Product definition

ImageKid AppIcons turns one source artwork file into complete, validated icon
packages for apps and websites. It combines visual preparation, platform-safe
preview, deterministic resizing, naming, and package generation.

It ships as a native macOS app and the `imagekid-appicons` CLI.

## Core promise

> Add one source. Export every icon size correctly.

It is not a general image editor. It prepares existing artwork for specific icon
destinations.

## Supported sources

- SVG
- PDF with vector rendering retained until output
- PNG
- JPEG
- HEIC/HEIF
- TIFF

Raster sources must be large enough for the largest requested output. The app
warns when upscaling is required. SVG input uses the secure local renderer:
scripts and event handlers are disabled, remote resources are blocked, and
unresolved linked assets are reported.

## Core workflow

1. Drop or open one source file.
2. Choose a destination preset.
3. Position and scale the artwork inside the icon canvas.
4. Choose padding, background, and appearance variants.
5. Inspect platform previews and validation warnings.
6. Export the complete package.

## Initial presets

### Apple App Icon

- iOS and iPadOS AppIcon asset catalog.
- macOS AppIcon asset catalog.
- Required filenames, scales, and `Contents.json`.
- Current Apple icon-mask and safe-area preview.
- Light, dark, and tinted slots where supported.

Preset definitions are versioned and updated through app releases. The app does
not fetch requirements at runtime.

### Web and favicon

- ICO when reliable local encoding is implemented.
- Named PNG favicons.
- Apple touch icon.
- Web app manifest icons.
- Optional `site.webmanifest` output.

### Generic icon set

- User-defined square sizes.
- Filename template.
- PNG, JPEG, or WebP where supported.
- Optional one-file PDF export.

## Preparation controls

- Transparent or solid canvas background.
- Artwork position and scale.
- Exact or percentage padding.
- Fit or fill.
- Background extension for non-square sources.
- Light, dark, and tinted variants.
- Per-variant replacement source.
- Corner-radius preview.
- Colour-profile policy.
- Metadata preserve or strip policy for generic output.

The app does not bake rounded corners into Apple app icons by default because
the operating system applies its own mask.

## Preview and validation

Preview the icon at representative launcher, Dock, settings-list, browser-tab,
and bookmark sizes on light and dark surfaces.

Validation covers missing sizes, insufficient raster resolution, safe-area
issues, rejected transparency, colour space, dimensions, filename collisions,
malformed SVG/PDF input, and package-manifest consistency.

## Output

- Export creates a new package directory by default.
- Existing asset catalogs are never replaced without confirmation.
- Output is staged and validated before destination replacement.
- A generated manifest records the tool and preset version, resolved settings,
  source checksum, and generated files.
- The manifest contains no source pixels or private metadata.

## CLI

```sh
imagekid-appicons Logo.svg --preset ios --output AppIcon.appiconset

imagekid-appicons Logo.svg \
  --preset web \
  --background '#ffffff' \
  --output PublicIcons

imagekid-appicons Logo.svg \
  --sizes 16,32,64,128,256,512,1024 \
  --padding 8% \
  --output GenericIcons
```

Initial options:

```text
--preset <ios|macos|web|generic>
--output <directory>
--sizes <comma-separated pixels>
--padding <pixels|percent>
--fit <contain|cover>
--background <transparent|colour>
--dark-source <path>
--tinted-source <path>
--metadata <strip|preserve>
--manifest <on|off>
--overwrite
--dry-run
--json
```

The CLI accepts one primary source. Appearance variants are explicit options so
file ordering cannot assign the wrong artwork to a slot.

JSON output reports each relative path, dimensions, format, appearance role,
byte size, checksum, and validation status.

See [Focused app command-line tools](focused-cli.md) for shared behaviour.

## First-release exclusions

- Drawing or path editing.
- AI icon generation.
- Cloud requirement updates.
- Android adaptive icons until their foreground/background workflow is fully
  documented and tested.
- Windows packages until ICO packaging is reliable.
- Uploading to App Store Connect.

## Shared implementation

```text
packages/ImageKidAppIcons/
├── AppIconRequest.swift
├── DestinationPreset.swift
├── ArtworkPlacement.swift
├── IconRenderer.swift
├── AssetCatalogWriter.swift
├── WebIconWriter.swift
├── PackageManifest.swift
└── AppIconValidator.swift
```

The app and CLI both depend on this package.

## Release gates

- Apple catalogs import into current Xcode without warnings.
- Web output passes manifest and dimension fixtures.
- SVG/PDF and raster input produce consistent placement.
- Preview masks are never baked accidentally into unmasked output.
- Appearance variants cannot be swapped silently.
- Small raster sources produce an explicit warning.
- App and CLI produce equivalent packages.
- Package writes are atomic and conflict-safe.

## Proposed identity

- App target: `ImageKidAppIcons`
- CLI target: `imagekid-appicons`
- Display name: `ImageKid AppIcons`
- Proposed bundle id: `com.hakobs.imagekid.appicons`
- Category: Graphics & Design
- Network entitlement: none
