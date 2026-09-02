# ImageKid

ImageKid is a native macOS utility for opening, viewing, inspecting, resizing, cropping, annotating, and exporting local images. It also provides basic local video playback. The repository includes the static product website at [imagekid.hakobs.com](https://imagekid.hakobs.com).

The app is offline by design: no account, cloud processing, analytics, ads, paid API, remote activation, or runtime download.

## Monorepo

- `apps/native-macos` — Swift Package Manager executable, native app source, companion app targets, and tests.
- `apps/website` — Vue 3, Vite, and strict TypeScript product site and public docs.
- `packages` — reserved for code shared by apps; apps never depend on one another.
- `docs` — product, requirements, architecture, implementation, release, companion-app, and contributor documentation.

Node 22 or newer is required for workspace commands. Native development requires macOS 14+, Xcode 16+, and Swift 5.10+.

## Current native capabilities

- File panel, drag and drop, URL paste, and image paste.
- Fitted image viewing, mouse and trackpad pan, pinch zoom, and reset.
- Pixel colour sampling, saved colour values, copy formats, and palette file export.
- Crop handles, guides, free crop, ratios, and editable dimensions.
- Exact and percentage resize controls.
- Editable rectangle, ellipse, line, arrow, freehand, and text annotations.
- Full-resolution PNG, JPEG, HEIC, TIFF, BMP, and GIF image export.
- Basic local video loading and playback through AVFoundation.
- Separate initial macOS companion targets for ImageKid Upscale, ImageKid Cutout, and ImageKid Slicer.

The colour picker does not yet have a pixel-grid loupe or dominant-palette extraction. Undo, close protection, blur/pixelation, metadata preservation, and production packaging remain incomplete. Video editing and export are not implemented.

A third focused macOS companion, **ImageKid Slicer**, has a first implementation: open one composite image, define regions — by hand, by cutting guides, by a grid, or from a template — then Save to a folder to create every slice as a separate local image. It is not packaged, signed, or notarised. See [docs/slicer.md](docs/slicer.md).

The planned focused range also includes **ImageKid Convert**, **ImageKid
AppIcons**, **ImageKid Sheet**, **ImageKid Compress**, and the Fekthor Effects,
Trace, Cleanup, View, and Edit tools. These are separate, single-purpose products
built from shared local engines, not reduced modes of the flagship editors. See
the [focused app family](docs/focused-apps.md),
[ImageKid Convert](docs/imagekid-convert.md), and
[Fekthor focused apps](docs/fekthor/FOCUSED-APPS.md).

ImageKid AppIcons, ImageKid Sheet, and ImageKid Compress also include command-line
tools backed by the same processing engines as their graphical apps. See the
[focused CLI contract](docs/focused-cli.md).

## Development

Install the website workspace from the repository root:

```bash
npm install
npm run site:dev
```

Run all website checks:

```bash
npm run check
```

Native commands from the root:

```bash
npm run native:build
npm run native:test
npm run native:run
```

Or work directly in `apps/native-macos`:

```bash
cd apps/native-macos
swift build
swift test
swift run ImageKid
```

Open `apps/native-macos/Package.swift` in Xcode to run the `ImageKid` scheme on My Mac. Swift build and test require macOS frameworks and cannot run on Linux.

## Website deployment

The website builds to `apps/website/dist` as a static SPA. Cloudflare Pages uses `imagekid-dev` for the `development` branch and `imagekid` for `main`. Pull requests run the website check workflow; branch deployments run only through the deploy workflow and repository secrets.

See [docs/website.md](docs/website.md) for routes, domains, content ownership, and deployment details.

## Release status

The repository is a development foundation. A successful Swift package build is not a signed, sandboxed, notarised, or App Store-ready application. There is currently no packaged download. See [docs/release-boundary.md](docs/release-boundary.md).

## Documentation

Start with the [documentation index](docs/README.md), [product definition](docs/product.md), [implementation status](docs/implementation.md), [requirements](docs/requirements.md), [architecture](docs/architecture.md), and [companion app strategy](docs/companion-apps.md). Focused-product documentation includes the [focused app family](docs/focused-apps.md), [ImageKid Convert](docs/imagekid-convert.md), [Fekthor focused apps](docs/fekthor/FOCUSED-APPS.md), and the implemented [ImageKid Slicer](docs/slicer.md). [ImageKid Sculptor](docs/sculptor.md), the local single-image-to-3D workflow, is planned and not implemented.

## Licence

No open-source licence has been selected. Source availability is not permission to copy, modify, redistribute, or reuse the code or assets.
