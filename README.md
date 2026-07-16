# ImageKid

ImageKid is a small, native macOS utility for opening, viewing, inspecting, resizing, cropping, and annotating images and basic video.

The media is the interface. Drop, paste, or open a local file and it appears immediately in a quiet Preview-like window. Moving the pointer reveals a compact action bar; the same commands are available from the macOS menu bar and keyboard.

ImageKid is offline by design. It has no account, cloud processing, analytics, paid API, or runtime download.

## Current foundation build

The repository now contains a buildable Swift package and native macOS application entry point.

Implemented in the current scaffold:

- native SwiftUI application and window lifecycle;
- drag and drop, File > Open, Command-O, and pasteboard input;
- image and common AVFoundation video loading;
- fitted image viewing, panning, pinch zoom, and reset;
- native video playback through `AVPlayer`;
- click-to-sample image colours and copy HEX values;
- session colour strip;
- non-destructive crop selection state;
- exact or percentage resize state;
- rectangle and text annotation foundations;
- full-resolution PNG, JPEG, and TIFF image export;
- geometry unit tests;
- macOS GitHub Actions build and test workflow.

Still to implement before a first useful release:

- colour loupe and palette extraction;
- crop handles and ratio presets;
- editable annotation selection, arrows, drawing, blur, and pixelation;
- undo and dirty-close protection;
- video colour sampling, crop, annotations, and export;
- richer metadata and colour-profile handling;
- accessibility and performance hardening.

AI upscaling is deliberately deferred. It is not part of the current build, architecture, release scope, or dependency graph.

## Build

Requirements:

- macOS 14 or newer;
- Xcode 16 or newer with the macOS SDK;
- Swift 5.10 or newer.

Open `Package.swift` in Xcode, select the `ImageKid` scheme, and run it on My Mac.

From Terminal:

```bash
swift build
swift test
swift run ImageKid
```

The current package is intended for development and validation. Before App Store or notarised distribution, create or generate a signed macOS application target with the correct bundle identifier, sandbox entitlements, assets, and archive settings.

## Product principles

- Media-first rather than editor-first.
- No permanent sidebar or layer panel.
- Tools appear only when needed.
- One image or video per window.
- Source files are never overwritten implicitly.
- Every feature works without an internet connection.
- Native menus, keyboard commands, drag and drop, pasteboard, and file panels.

## Documentation

- [Documentation index](docs/README.md)
- [Product definition](docs/product.md)
- [Requirements](docs/requirements.md)
- [User experience](docs/ux.md)
- [Architecture](docs/architecture.md)
- [Implementation status](docs/implementation.md)
- [Decisions](docs/decisions.md)
- [Testing](docs/testing.md)
- [Roadmap](docs/roadmap.md)

## Licence

No project licence has been selected yet. Add a licence before accepting outside contributions or distributing source under open-source terms.
