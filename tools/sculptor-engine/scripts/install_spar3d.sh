#!/usr/bin/env bash
#
# Fetch the SPAR3D reconstruction runtime into vendor/SPAR3D.
#
# Not committed, matching how TripoSR and tools/coreml-conversion treat their
# third-party dependencies. The upstream project ships no setup.py or
# pyproject.toml, so it cannot be pip-installed — it is meant to be cloned and
# put on the path, which is what this does and what the engine expects.
#
# The Stability AI Community License travels with the clone. It permits
# commercial use, needs registration at stability.ai/community-license, and
# requires a separate enterprise licence above USD 1,000,000 annual revenue.
# Unlike some alternatives it carries no territorial restriction.
#
# Model weights are a separate concern and are gated: accept the licence on
# Hugging Face, then scripts/fetch_weights.py --engine spar3d.

set -euo pipefail

REPO="https://github.com/Stability-AI/stable-point-aware-3d.git"
# Pin so a measurement stays reproducible. Update deliberately.
REF="${SPAR3D_REF:-main}"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="$here/vendor/SPAR3D"

if [ -f "$target/spar3d/system.py" ]; then
  echo "SPAR3D already present at $target"
else
  mkdir -p "$here/vendor"
  git clone --depth 1 --branch "$REF" "$REPO" "$target"
fi

# Upstream imports a background remover at module scope in spar3d/utils.py but
# only uses it inside remove_background(). Sculptor never calls that — the app
# supplies a Vision mask, or the worker uses the source alpha — so the import
# would pull a whole segmentation stack into the worker for nothing, and its
# absence stops the engine loading at all. Make it lazy.
utils="$target/spar3d/utils.py"
if grep -q '^from transparent_background import Remover$' "$utils"; then
  python3 - "$utils" <<'PATCH'
import sys

path = sys.argv[1]
source = open(path, encoding="utf-8").read()

source = source.replace(
    "from transparent_background import Remover\n",
    "# Patched by ImageKid Sculptor: imported lazily in remove_background() so\n"
    "# the unused background remover is not required to load the engine.\n"
    "# See scripts/install_spar3d.sh.\n",
    1,
)

# The signature names the type, which would be evaluated at import time.
old_signature = "    bg_remover: Remover = None,"
new_signature = '    bg_remover: "Remover" = None,'
if old_signature not in source:
    raise SystemExit(f"unexpected upstream signature in {path}; patch not applied")
source = source.replace(old_signature, new_signature, 1)

old = "    if do_remove:\n        image = bg_remover.process("
new = (
    "    if do_remove:\n"
    "        from transparent_background import Remover  # noqa: F401\n\n"
    "        image = bg_remover.process("
)
if old not in source:
    raise SystemExit(f"unexpected upstream content in {path}; patch not applied")
source = source.replace(old, new, 1)

open(path, "w", encoding="utf-8").write(source)
print(f"patched {path}")
PATCH
else
  echo "transparent_background import already patched or upstream changed; check $utils"
fi

# Upstream's requirements also pull in two compiled extensions of its own — a
# texture baker and a UV unwrapper — which exist to paint the mesh. Sculptor
# asks only for geometry, and those are the parts least likely to build on
# macOS, so they are left out unless something needs them.
echo
echo "SPAR3D source ready at $target"
echo
echo "Next:"
echo "  1. Accept the licence: https://huggingface.co/stabilityai/stable-point-aware-3d"
echo "  2. Authenticate:       .venv/bin/hf auth login"
echo "  3. Fetch the weights:  .venv/bin/python scripts/fetch_weights.py --engine spar3d"
