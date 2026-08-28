"""Install reconstruction weights for development.

In the product the **app** downloads weights into the App Group, the same way
ImageKid installs its Core ML models. This script does the equivalent from the
command line so the worker and the corpus harness can be exercised without
running the app.

    python scripts/fetch_weights.py
    python scripts/fetch_weights.py --engine spar3d   # needs a Hugging Face token

TripoSR is MIT licensed and ungated. SPAR3D is gated behind an account and an
acceptance of the Stability AI Community License; `huggingface-cli login` first,
and read the licence before shipping anything built on it.
"""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sculptor_engine import models  # noqa: E402

REPOSITORIES = {
    "triposr": ("stabilityai/TripoSR", models.TRIPOSR_REQUIRED_FILES),
    "spar3d": ("stabilityai/stable-point-aware-3d", models.SPAR3D_REQUIRED_FILES),
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", default="triposr", choices=sorted(REPOSITORIES))
    parser.add_argument(
        "--root",
        type=Path,
        default=None,
        help="model root (defaults to the App Group location the worker reads)",
    )
    args = parser.parse_args()

    try:
        from huggingface_hub import hf_hub_download
    except ImportError:
        print(
            "huggingface_hub is not installed; pip install -r requirements-triposr.txt",
            file=sys.stderr,
        )
        return 1

    repository, required = REPOSITORIES[args.engine]
    installation = (
        models.triposr_installation(args.root)
        if args.engine == "triposr"
        else models.spar3d_installation(args.root)
    )
    directory = installation.directory
    directory.mkdir(parents=True, exist_ok=True)

    for name in required:
        destination = directory / name
        if destination.is_file():
            print(f"{name}: already installed")
            continue
        print(f"{name}: downloading from {repository}…", flush=True)
        try:
            cached = hf_hub_download(repository, name)
        except Exception as exc:
            print(f"{name}: FAILED {exc}", file=sys.stderr)
            if args.engine == "spar3d":
                print(
                    "SPAR3D is gated: accept its licence on Hugging Face and run "
                    "`huggingface-cli login` first.",
                    file=sys.stderr,
                )
            return 1
        # Copy rather than symlink: the app group directory must stand alone if
        # the Hugging Face cache is later cleared.
        shutil.copy(cached, destination)
        print(f"{name}: {destination.stat().st_size / (1024 ** 2):.0f} MB")

    print(f"\ninstalled to {directory}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
