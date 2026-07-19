# Decisions

## D-001 — Native macOS application

ImageKid is implemented in Swift using SwiftUI and Apple media frameworks. Native file handling, menus, keyboard commands, colour management, video playback, accessibility, and distribution behaviour are core product requirements.

## D-002 — Media-first window

The image or video occupies the window. There is no permanent sidebar, inspector, layer panel, or multitrack timeline. A floating action bar and native menus expose tools progressively.

## D-003 — One media item per window

A window owns one image or one video session. Multiple files open in multiple windows rather than becoming tabs, a browser, or a project library.

## D-004 — Non-destructive session state

The source remains immutable. Crop, output size, annotations, timing, and other edits are stored as intent and applied during preview or export. The app never overwrites the source implicitly.

## D-005 — Normalised media coordinates

Crop and annotation geometry are stored relative to orientation-correct media, not window pixels. A shared coordinate mapper is used by interaction, preview, sampling, and export.

## D-006 — Offline without exceptions

Core behaviour must work with networking disabled. The app has no account, activation, analytics, paid SDK, or implicit cloud processing. Prompted image edits are the explicit exception: they use a user-supplied provider credential and only run after the user starts that action.

## D-007 — Apple frameworks first

Use AppKit, SwiftUI, Core Graphics, Core Image, Image I/O, AVFoundation, AVKit, VideoToolbox, and Uniform Type Identifiers before introducing third-party dependencies. A dependency requires a concrete capability or maintenance advantage.

## D-008 — Swift package for the foundation

The initial repository is a Swift Package Manager executable. This provides a small buildable source tree, Xcode support, command-line build and test, and straightforward CI.

A signed application target is added during release packaging, when bundle identifiers, entitlements, assets, archives, and notarisation become necessary.

## D-009 — Standard scaling always available (superseded in part by D-013)

The active product uses deterministic high-quality standard interpolation as the always-available default. This decision originally also deferred AI upscaling and removed it from the code and dependency graph; that part is superseded by D-013, which records the shipped Best Quality add-ons.

## D-010 — Images before processed video

Image editing establishes coordinate mapping, non-destructive state, annotation rendering, colour handling, and export first. Video reuses those domain concepts through a bounded AVFoundation frame pipeline afterward.

## D-011 — No full video timeline

Video has playback, a scrubber, and optional annotation start/end ranges. Multiple clips, tracks, transitions, keyframes, and audio editing are not introduced.

## D-012 — Buildability is distinct from distribution readiness

The repository must build and test now. App Sandbox entitlements, signing, notarisation, App Store metadata, and a production `.app` archive are separate release tasks and must not be implied by a successful SwiftPM build.

## D-013 — Optional Best Quality add-ons as downloaded local runtimes

ImageKid ships two opt-in Best Quality add-ons alongside the built-in engines: AI upscaling via a downloaded Real-ESRGAN `ncnn-vulkan` runtime, and AI background removal via a downloaded ONNX model plus a locally built `rembg` Python runtime. Both download on demand from Settings, store to Application Support, and run on-device as subprocesses. They remain fully offline at inference time and use no accounts, cloud processing, or paid APIs.

This supersedes the D-009 position that AI upscaling was removed from the code and dependency graph, and it narrows the earlier "no runtime downloads" stance to "no cloud, accounts, or paid APIs." The built-in tiers (Core Image / Lanczos upscaling; Apple Vision background removal) remain the always-available defaults.

## D-014 — Core ML as the cross-platform inference direction

The downloaded-runtime mechanism in D-013 is macOS-specific and cannot move to iOS: iOS has no subprocesses, App Store review prohibits downloading executable code, there is no system Python, and there is no Vulkan. The intended direction is to convert the same models (Real-ESRGAN, ISNet) to Core ML and run inference in-process on both platforms, delivering weights as data rather than as an executable runtime. Adopting Core ML on macOS as well would let both apps share one engine and retire the binary download, Vulkan dependency, and Python runtime. See `ios-feasibility.md`.
