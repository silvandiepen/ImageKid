# Build validation

Local validation performed before publishing this scaffold:

- `swift package dump-package` succeeds;
- every Swift source file passes `swiftc -parse` with Swift 6.2 on Linux.

A complete type-check and build requires the macOS SDK because the app in `apps/native-macos` imports SwiftUI, AppKit, AVFoundation, and AVKit. The pull-request workflow runs `swift build` and `swift test` with `apps/native-macos` as its working directory on `macos-15` and is the authoritative native build result. Website validation runs with `npm run check` from the repository root.
