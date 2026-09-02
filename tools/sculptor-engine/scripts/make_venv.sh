#!/usr/bin/env bash
#
# Create .venv from the same relocatable CPython the app bundles.
#
#   ./scripts/make_venv.sh            # core deps only, no PyTorch
#   ./scripts/make_venv.sh --engine   # plus the reconstruction backend
#
# Deliberately not the system Python. macOS ships 3.9, the bundle ships 3.11,
# and developing against a different interpreter than you ship is how the
# transformers 5.x incompatibility reached a build: the 3.9 venv resolved a
# working version, the fresh 3.11 runtime resolved a broken one. Same
# interpreter, same resolutions, same bugs found early.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_VERSION="${PYTHON_VERSION:-3.11.9}"
release="20240415"

with_engine=0
[ "${1:-}" = "--engine" ] && with_engine=1

arch="$(uname -m)"
case "$arch" in
  arm64) triple="aarch64-apple-darwin" ;;
  x86_64) triple="x86_64-apple-darwin" ;;
  *) echo "unsupported architecture: $arch" >&2; exit 1 ;;
esac

runtime="$here/.python"
if [ ! -x "$runtime/bin/python3" ]; then
  echo "Fetching CPython ${PYTHON_VERSION}…"
  staging="$(mktemp -d)"
  trap 'rm -rf "$staging"' EXIT
  url="https://github.com/indygreg/python-build-standalone/releases/download/${release}/cpython-${PYTHON_VERSION}+${release}-${triple}-install_only.tar.gz"
  curl -fsSL "$url" -o "$staging/python.tar.gz"
  mkdir -p "$staging/out"
  tar -xzf "$staging/python.tar.gz" -C "$staging/out" --strip-components=1
  rm -rf "$runtime"
  mv "$staging/out" "$runtime"
fi

echo "Creating .venv from $("$runtime/bin/python3" -V)…"
rm -rf "$here/.venv"
"$runtime/bin/python3" -m venv "$here/.venv"
"$here/.venv/bin/python" -m pip install --upgrade pip >/dev/null

echo "Installing core dependencies…"
"$here/.venv/bin/python" -m pip install -r "$here/requirements.txt" pytest

if [ "$with_engine" = "1" ]; then
  # Same two-phase dance as bundle_runtime.sh: torchmcubes builds against an
  # already-installed PyTorch and needs its backend present.
  torchmcubes_url="$(grep -E '^git\+.*torchmcubes' "$here/requirements-triposr.txt" || true)"
  staged="$(mktemp)"
  grep -vE '^git\+.*torchmcubes' "$here/requirements-triposr.txt" > "$staged"
  sed -i '' "s|^-r requirements.txt|-r $here/requirements.txt|" "$staged"

  echo "Installing the reconstruction backend (pulls PyTorch)…"
  "$here/.venv/bin/python" -m pip install -r "$staged"
  rm -f "$staged"

  if [ -n "$torchmcubes_url" ]; then
    "$here/.venv/bin/python" -m pip install scikit-build-core cmake ninja pybind11 >/dev/null
    "$here/.venv/bin/python" -m pip install --no-build-isolation "$torchmcubes_url"
  fi

  if [ ! -d "$here/vendor/TripoSR" ]; then
    echo "Fetching the TripoSR runtime…"
    "$here/scripts/install_triposr.sh"
  fi
fi

echo
echo "Done: $("$here/.venv/bin/python" -V)"
echo "  python -m pytest tests/ -q"
