# Third-party notices

## Bundled components

### Figtree

- **Component**: Figtree (variable font, `Figtree[wght].ttf`)
- **Version**: 2.002
- **Upstream source**: https://github.com/google/fonts/tree/main/ofl/figtree (upstream project: https://github.com/erikdkennedy/figtree)
- **Copyright holder**: Copyright 2022 The Figtree Project Authors
- **Licence**: SIL Open Font License, Version 1.1 — see `licenses/Figtree-OFL.txt`
- **Required attribution**: none in-product; the OFL text ships with the repository. The About window credits "Typeset in Figtree".
- **Redistribution / commercial use**: permitted, including bundling inside an application, under the OFL. The font is not sold on its own and is not renamed.
- **Local modifications**: none — the upstream binary is vendored byte-for-byte.
- **Checksum**: `sha256:26ad3db9b31ff7dde67a91ff515d022d2f495cd506590699cf264f0bfe6fb714` (62,712 bytes)
- **Bundled at**: `packages/ImageKidKit/Sources/ImageKidKit/Resources/Figtree.ttf`, registered at runtime via `CTFontManagerRegisterFontsForURL`.

Apart from the above, the apps bundle no third-party runtime libraries, models, or external icon sets.

The app uses Apple system frameworks including SwiftUI, AppKit, Core Graphics, Core Image, Image I/O, AVFoundation, AVKit, VideoToolbox, and Uniform Type Identifiers. These are provided by macOS and are not redistributed as repository dependencies.

Before any external source component, binary, asset, font, icon set, or model is included, record:

- component name and exact version or commit;
- upstream source;
- copyright holder;
- licence and required attribution;
- redistribution and commercial-use status;
- local modifications;
- checksums for bundled binary assets where relevant.

An item must not ship while its source, licence, attribution, or redistribution terms are ambiguous.
