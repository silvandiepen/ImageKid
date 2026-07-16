# Build and run

Requirements: macOS 14+, Xcode 16+, and Swift 5.10+.

Open `apps/native-macos/Package.swift` in Xcode, select the `ImageKid` scheme, and run on My Mac.

From the repository root:

```bash
npm run native:build
npm run native:test
npm run native:run
```

Or from the native package:

```bash
cd apps/native-macos
make build
make test
make run
```

Website development requires Node 22+:

```bash
npm install
npm run site:dev
npm run check
```

The Swift package is a development foundation. Signing, sandbox entitlements, an asset catalogue, archive settings, and notarisation are separate distribution tasks.
