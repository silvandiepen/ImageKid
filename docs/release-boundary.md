# Release boundary

A successful Swift package build proves that the source compiles and tests against the macOS SDK. It does not by itself prove that an application archive is signed, sandboxed, notarised, or accepted by App Store Connect.

Distribution readiness requires a macOS app target, bundle metadata, entitlements, assets, signing, archive configuration, and release validation.

## Companion App Store boundary

ImageKid Upscale, ImageKid Cutout, and ImageKid Slicer each have a registered bundle identifier, provisioning profile, editable macOS version, listing metadata, privacy declaration, age rating, review information, price schedule, and valid attached build in App Store Connect. Upscale and Cutout use build 4; Slicer uses build 3. None has been submitted for review or released.

The attached builds are signed and sandboxed Mac App Store packages. They are not direct-download Developer ID builds and are not notarised for distribution outside the App Store. Final production icons, App Store screenshots, and a human release test pass remain release inputs.

Sculptor has only a dormant draft identity. Its implementation, price, model-distribution decision, validation, and release setup remain deliberately out of this boundary.
