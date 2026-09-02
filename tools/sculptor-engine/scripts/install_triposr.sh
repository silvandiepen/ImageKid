#!/usr/bin/env bash
#
# Fetch the TripoSR reconstruction runtime into vendor/TripoSR.
#
# The source is not committed, matching how tools/coreml-conversion treats its
# third-party dependencies. TripoSR is MIT licensed; its LICENSE travels with
# the clone.
#
# Model weights are a separate concern: the Sculptor app downloads those into
# the App Group. See scripts/fetch_weights.py for a development-time equivalent.

set -euo pipefail

REPO="https://github.com/VAST-AI-Research/TripoSR.git"
# Pin so a Phase 0 measurement stays reproducible. Update deliberately.
REF="${TRIPOSR_REF:-main}"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="$here/vendor/TripoSR"

if [ -f "$target/tsr/system.py" ]; then
  echo "TripoSR already present at $target"
else
  mkdir -p "$here/vendor"
  git clone --depth 1 --branch "$REF" "$REPO" "$target"
fi

# TripoSR imports rembg at module scope in tsr/utils.py, but only uses it inside
# remove_background(). Sculptor never calls that — the app supplies a Vision
# mask, or the worker uses the source alpha — so the import would pull
# onnxruntime into the bundle for nothing. Make it lazy.
utils="$target/tsr/utils.py"
if grep -q '^import rembg$' "$utils"; then
  python3 - "$utils" <<'PATCH'
import sys

path = sys.argv[1]
source = open(path, encoding="utf-8").read()

source = source.replace(
    "import rembg\n",
    "# Patched by ImageKid Sculptor: imported lazily in remove_background()\n"
    "# so the unused background remover does not pull onnxruntime into the\n"
    "# worker environment. See scripts/install_triposr.sh.\n",
    1,
)
# Match the full indented statement, so the lazy import lands inside the
# `if do_remove:` block rather than de-indenting the call out of it.
old = "        image = rembg.remove(image, session=rembg_session, **rembg_kwargs)"
new = (
    "        import rembg\n\n"
    "        image = rembg.remove(image, session=rembg_session, **rembg_kwargs)"
)
if old not in source:
    raise SystemExit(f"unexpected upstream content in {path}; patch not applied")
source = source.replace(old, new, 1)

open(path, "w", encoding="utf-8").write(source)
print(f"patched {path}")
PATCH
else
  echo "rembg import already patched or upstream changed; check $utils"
fi

# torchmcubes accepts CPU tensors only. On Apple Silicon the density grid lives
# on MPS, and upstream only falls back to the CPU on AttributeError, so the run
# dies with "vol must be a CPU tensor". Always cross to the CPU for marching
# cubes; the vertices are moved back to the caller's device immediately after.
iso="$target/tsr/models/isosurface.py"
if grep -q 'except AttributeError:' "$iso"; then
  python3 - "$iso" <<'PATCH'
import sys

path = sys.argv[1]
source = open(path, encoding="utf-8").read()

old = """        try:
            v_pos, t_pos_idx = self.mc_func(level.detach(), 0.0)
        except AttributeError:
            print("torchmcubes was not compiled with CUDA support, use CPU version instead.")
            v_pos, t_pos_idx = self.mc_func(level.detach().cpu(), 0.0)"""
new = """        # Patched by ImageKid Sculptor: torchmcubes accepts CPU tensors only
        # and raises "vol must be a CPU tensor" for MPS input, which upstream's
        # AttributeError fallback does not catch.
        v_pos, t_pos_idx = self.mc_func(level.detach().cpu(), 0.0)"""

if old not in source:
    raise SystemExit(f"unexpected upstream content in {path}; patch not applied")

open(path, "w", encoding="utf-8").write(source.replace(old, new, 1))
print(f"patched {path}")
PATCH
else
  echo "isosurface already patched or upstream changed; check $iso"
fi

echo "TripoSR ready at $target"
