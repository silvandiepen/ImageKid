# Third-party notices

This file is a release checklist and future attribution location. It is not yet a declaration that any candidate model or dependency is included.

Before a distributable build is produced, every bundled model, source component, binary, font, icon set outside Apple system assets, and converted artifact must be listed with:

- component or model name;
- exact version, tag, commit, or checkpoint;
- upstream project and source location;
- copyright holder;
- code licence;
- model-weight or asset licence;
- redistribution and commercial-use status;
- required attribution text;
- local modifications;
- source and converted SHA-256 checksums;
- conversion script and toolchain version.

## Current candidates

### Real-ESRGAN family

**Status:** Candidate only; not bundled.

Intended use: general image upscaling and frame-based video upscaling.

Required before inclusion:

- pin the exact upstream repository commit;
- pin the exact checkpoint;
- retain the BSD 3-Clause source-code notice;
- verify explicit redistribution terms for the chosen pretrained weights;
- document Core ML conversion and checksums;
- complete quality and Apple Silicon performance review.

### RealESRGAN illustration/anime checkpoint

**Status:** Candidate only; not bundled.

Intended use: illustrations, animation, icons, and line art.

Required before inclusion: the same checks as the general model, with particular attention to checkpoint redistribution terms.

### BasicVSR++ or another temporal video model

**Status:** Research candidate only; not bundled.

Intended use: future temporally consistent video super-resolution.

Required before inclusion:

- exact code and weight licensing;
- native runtime or Core ML conversion;
- operator and memory validation;
- window-boundary and scene-cut testing;
- complete attribution and provenance.

## Apple frameworks

SwiftUI, AppKit, Core Graphics, Core Image, Core ML, AVFoundation, VideoToolbox, Image I/O, and Uniform Type Identifiers are system frameworks and are not redistributed as third-party packages by this repository.

## Release rule

An item must not ship while its source, licence, model-weight rights, attribution, or provenance is ambiguous. Technical availability is not sufficient permission to redistribute it.