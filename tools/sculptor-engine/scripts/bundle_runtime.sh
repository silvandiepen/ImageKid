#!/usr/bin/env bash
#
# Package a self-contained Python runtime and the worker into the app bundle,
# at Contents/Resources/sculptor-engine/ where WorkerLaunchConfiguration looks
# for it.
#
# This is what the App Sandbox requires: a sandboxed process may only execute
# binaries inside its own bundle, so the Sculptor target stays unsandboxed until
# this has run. See apps/native-macos/project.yml.
#
#   ./scripts/bundle_runtime.sh "/path/to/ImageKid Sculptor.app"
#
# Be aware of what this costs before wiring it into a release: PyTorch alone is
# roughly 2.5 GB, and every .so inside the runtime has to be signed
# individually for notarisation. A Core ML port of the engine would remove the
# Python dependency altogether and is the better long-term answer; this script
# exists so the sandboxed path can be tested now rather than blocked.

set -euo pipefail

APP="${1:?path to the built .app}"
PYTHON_VERSION="${PYTHON_VERSION:-3.11.9}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ ! -d "$APP" ]; then
  echo "no such app bundle: $APP" >&2
  exit 1
fi

resources="$APP/Contents/Resources"
target="$resources/sculptor-engine"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

arch="$(uname -m)"
case "$arch" in
  arm64) triple="aarch64-apple-darwin" ;;
  x86_64) triple="x86_64-apple-darwin" ;;
  *) echo "unsupported architecture: $arch" >&2; exit 1 ;;
esac

# python-build-standalone: a relocatable CPython, which the system Python is
# not — /usr/bin/python3 cannot be copied into a bundle and still work.
release="20240415"
url="https://github.com/indygreg/python-build-standalone/releases/download/${release}/cpython-${PYTHON_VERSION}+${release}-${triple}-install_only.tar.gz"

echo "Fetching CPython ${PYTHON_VERSION} for ${triple}…"
curl -fsSL "$url" -o "$staging/python.tar.gz"
mkdir -p "$staging/runtime"
tar -xzf "$staging/python.tar.gz" -C "$staging/runtime" --strip-components=1

runtime_python="$staging/runtime/bin/python3"
"$runtime_python" -m pip install --upgrade pip >/dev/null

# torchmcubes is a CMake extension that calls find_package(Torch) while
# building, so PyTorch has to already be importable *and* build isolation has to
# be off. Installing the requirements in one pass fails with
# "Could not find a package configuration file provided by Torch".
torchmcubes_url="$(grep -E '^git\+.*torchmcubes' "$here/requirements-triposr.txt" || true)"

echo "Installing worker dependencies (this pulls PyTorch; expect gigabytes)…"
# Not named requirements.txt: the file begins with `-r requirements.txt`, and a
# copy under that name would include itself.
staged="$staging/worker-requirements.txt"
grep -vE '^git\+.*torchmcubes' "$here/requirements-triposr.txt" > "$staged"
# That `-r` is relative to the original file's directory, which the copy is not
# in any more; point it at the real one.
sed -i '' "s|^-r requirements.txt|-r $here/requirements.txt|" "$staged"
"$runtime_python" -m pip install -r "$staged"

if [ -n "$torchmcubes_url" ]; then
  # Without build isolation pip will not fetch the build backend either, so it
  # has to be present in the environment first.
  echo "Installing the build backend torchmcubes needs…"
  "$runtime_python" -m pip install scikit-build-core cmake ninja pybind11

  echo "Building torchmcubes against the installed PyTorch…"
  "$runtime_python" -m pip install --no-build-isolation "$torchmcubes_url"
fi

# TripoSR's image tokenizer builds its ViT from facebook/dino-vitb16's config.
# transformers resolves that through the Hugging Face cache in the user's home,
# which a sandboxed app cannot read — the generation fails with "Operation not
# permitted: ~/.cache/huggingface/...". Only the config is needed; the weights
# come from TripoSR's own checkpoint. Pre-populate a cache that travels with the
# app so nothing is looked up at runtime.
echo "Pre-populating the Hugging Face cache with the ViT config…"
HF_HOME="$staging/runtime/hf-cache" "$runtime_python" - <<'PY'
from huggingface_hub import snapshot_download

path = snapshot_download(
    "facebook/dino-vitb16",
    allow_patterns=["config.json", "preprocessor_config.json"],
)
print(f"  cached {path}")
PY

echo "Copying the worker…"
cp -R "$here/sculptor_engine" "$staging/runtime/"
if [ -d "$here/vendor/TripoSR/tsr" ]; then
  cp -R "$here/vendor/TripoSR/tsr" "$staging/runtime/"
  cp "$here/vendor/TripoSR/LICENSE" "$staging/runtime/TripoSR-LICENSE"
else
  echo "warning: vendor/TripoSR missing; run scripts/install_triposr.sh first" >&2
fi

# Trim what cannot run from a bundle or is dead weight there.
find "$staging/runtime" -name "__pycache__" -type d -prune -exec rm -rf {} + 2>/dev/null || true
find "$staging/runtime" -name "*.pyc" -delete 2>/dev/null || true
rm -rf "$staging/runtime/lib/python"*/test 2>/dev/null || true

rm -rf "$target"
mkdir -p "$resources"
cp -R "$staging/runtime" "$target"

size="$(du -sh "$target" | cut -f1)"
echo "Bundled runtime at $target ($size)"
echo
echo "Next, and not optional for distribution:"
echo "  1. Sign every native binary inside it:"
echo "     find '$target' \\( -name '*.so' -o -name '*.dylib' \\) -exec \\"
echo "       codesign --force --timestamp --options runtime -s <identity> {} +"
echo "  2. Sign the app itself, then notarise."
echo "  3. Re-enable the sandbox in project.yml and the entitlements, and"
echo "     confirm the worker still launches — that is the whole point."
