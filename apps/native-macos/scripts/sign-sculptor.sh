#!/usr/bin/env bash
#
# Sign ImageKid Sculptor, including the ~190 native binaries inside its bundled
# Python runtime.
#
#   ./scripts/sign-sculptor.sh "/path/to/ImageKid Sculptor.app"                 # ad-hoc
#   ./scripts/sign-sculptor.sh "/path/to/ImageKid Sculptor.app" "Developer ID Application: …"
#
# Not `codesign --deep`: it is deprecated, and Apple's guidance is explicit that
# it must not be relied on for nested code. Signing runs inside-out — every
# .so and .dylib first, then the app — because signing the bundle seals the
# contents, and anything signed afterwards invalidates that seal.
#
# List available identities with:
#   security find-identity -v -p codesigning
#
# Notarising is deliberately not done here. It uploads the app to Apple under
# your account, which is a decision for a person, not a build script:
#
#   xcrun notarytool submit "<app>.zip" --keychain-profile <profile> --wait
#   xcrun stapler staple "<app>"

set -euo pipefail

APP="${1:?path to the .app}"
IDENTITY="${2:--}"                      # default: ad-hoc
ENTITLEMENTS="${ENTITLEMENTS:-}"

if [ ! -d "$APP" ]; then
  echo "no such app bundle: $APP" >&2
  exit 1
fi

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -z "$ENTITLEMENTS" ]; then
  ENTITLEMENTS="$here/Sources/ImageKidSculptor/ImageKidSculptor.entitlements"
fi
if [ ! -f "$ENTITLEMENTS" ]; then
  echo "no entitlements at $ENTITLEMENTS" >&2
  exit 1
fi

if [ "$IDENTITY" = "-" ]; then
  echo "Signing ad-hoc. Good for running locally; not for distribution."
else
  echo "Signing as: $IDENTITY"
fi

runtime="$APP/Contents/Resources/sculptor-engine"
if [ -d "$runtime" ]; then
  count="$(find "$runtime" \( -name '*.so' -o -name '*.dylib' \) | wc -l | tr -d ' ')"
  echo "Signing $count native binaries in the bundled runtime…"
  # -exec … + batches them, which matters at this count.
  find "$runtime" \( -name '*.so' -o -name '*.dylib' \) -exec \
    codesign --force --timestamp --options runtime -s "$IDENTITY" {} + \
    >/dev/null 2>&1

  # The interpreter runs as its own process, so it needs its own entitlements.
  # Without disable-library-validation *here*, dyld refuses to map the runtime's
  # dylibs into it — "mapping process and mapped file have different Team IDs" —
  # because the app holding that entitlement does not help a different process.
  worker_entitlements="$here/Sources/ImageKidSculptor/SculptorWorker.entitlements"
  if [ ! -f "$worker_entitlements" ]; then
    echo "missing $worker_entitlements" >&2
    exit 1
  fi
  echo "Signing the interpreter with the worker entitlements…"
  for executable in "$runtime/bin/"*; do
    [ -f "$executable" ] && [ -x "$executable" ] || continue
    codesign --force --timestamp --options runtime \
      --entitlements "$worker_entitlements" -s "$IDENTITY" "$executable" \
      >/dev/null 2>&1 || true
  done
else
  echo "warning: no bundled runtime; run tools/sculptor-engine/scripts/bundle_runtime.sh" >&2
fi

echo "Signing the app…"
codesign --force --timestamp --options runtime \
  --entitlements "$ENTITLEMENTS" -s "$IDENTITY" "$APP"

echo
echo "Verifying…"
codesign --verify --verbose=2 "$APP" 2>&1 | tail -3
echo
codesign -d --entitlements - "$APP" 2>&1 |
  grep -oE "app-sandbox|network.client|disable-library-validation|application-groups" |
  sort -u | sed 's/^/  entitlement: /'

if [ "$IDENTITY" != "-" ]; then
  echo
  echo "Next: notarise, which uploads to Apple under your account —"
  echo "  ditto -c -k --keepParent '$APP' Sculptor.zip"
  echo "  xcrun notarytool submit Sculptor.zip --keychain-profile <profile> --wait"
  echo "  xcrun stapler staple '$APP'"
fi
