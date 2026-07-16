# Build validation

Local validation performed before publishing this scaffold:

- `swift package dump-package` succeeds;
- every Swift source file passes `swiftc -parse` with Swift 6.2 on Linux.

A complete type-check and build requires the macOS SDK because the app imports SwiftUI, AppKit, AVFoundation, and AVKit. The pull-request workflow runs `swift build` and `swift test` on `macos-15` and is the authoritative build result.
