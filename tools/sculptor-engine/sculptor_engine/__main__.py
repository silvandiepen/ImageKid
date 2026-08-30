"""Command-line entry point.

Two modes, both speaking the same protocol:

``--serve``
    Long-lived worker reading requests on stdin. This is how the Sculptor app
    drives the engine.

``--image``/``--output``
    One-shot generation, for the Phase 0 spike and for scripting a corpus run.

Examples::

    python -m sculptor_engine --image temple.png --output temple-3d.glb
    python -m sculptor_engine --serve
    python -m sculptor_engine --check
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="sculptor-engine",
        description="Local single-image to 3D reconstruction worker for ImageKid Sculptor.",
    )
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument(
        "--serve",
        action="store_true",
        help="run as a long-lived worker, reading JSON-lines requests on stdin",
    )
    mode.add_argument(
        "--image",
        type=Path,
        help="source image for a one-shot generation",
    )
    mode.add_argument(
        "--check",
        action="store_true",
        help="report engine and model installation status, then exit",
    )

    parser.add_argument("--output", type=Path, help="destination .glb (with --image)")
    parser.add_argument("--mask", type=Path, help="optional foreground mask PNG")
    parser.add_argument(
        "--pitch",
        type=float,
        default=0.0,
        help="degrees of pitch to undo the source camera elevation; 0 suits an "
        "eye-level photo, 30 an isometric render",
    )
    parser.add_argument(
        "--format",
        dest="formats",
        action="append",
        choices=["glb", "obj", "stl", "ply"],
        help="extra format to write beside the GLB; repeatable",
    )
    parser.add_argument(
        "--smoothing",
        type=int,
        default=None,
        metavar="N",
        help="Taubin smoothing passes (default 8; 0 keeps the raw isosurface)",
    )
    parser.add_argument(
        "--triangles",
        type=int,
        default=None,
        metavar="N",
        help="decimate to about N triangles (default 60000; 0 keeps them all)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="print one JSON object describing the result, and nothing else",
    )
    parser.add_argument(
        "--work-dir",
        type=Path,
        help="job workspace to keep (defaults to a temporary directory)",
    )
    parser.add_argument(
        "--engine",
        default=None,
        help="reconstruction engine name (triposr or spar3d; default triposr)",
    )
    parser.add_argument("--device", help="force a torch device, e.g. mps or cpu")
    parser.add_argument(
        "--low-memory",
        action="store_true",
        help="trade speed and some surface detail for lower peak memory",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    from .engines import DEFAULT_ENGINE

    engine_name = args.engine or DEFAULT_ENGINE
    engine_kwargs = {}
    if args.device:
        engine_kwargs["device"] = args.device
    if args.low_memory:
        engine_kwargs["low_memory"] = True

    if args.check:
        from .engines import create_engine

        engine = create_engine(engine_name, **engine_kwargs)
        print(
            json.dumps(
                {
                    "engine": engine.name,
                    "available": engine.is_available,
                    "detail": engine.unavailable_reason,
                },
                indent=2,
            )
        )
        return 0 if engine.is_available else 1

    from .protocol import GenerateOptions
    from .worker import run_once, serve

    if args.serve:
        return serve(engine_name, **engine_kwargs)

    if not args.output:
        parser.error("--output is required with --image")

    overrides = {"pitchCorrection": args.pitch}
    if args.smoothing is not None:
        overrides["smoothingIterations"] = args.smoothing
    if args.triangles is not None:
        overrides["targetTriangles"] = args.triangles
    if args.formats:
        overrides["exportFormats"] = tuple(dict.fromkeys(args.formats))

    return run_once(
        source=args.image,
        output=args.output,
        mask=args.mask,
        work_dir=args.work_dir,
        engine_name=engine_name,
        options=GenerateOptions(**overrides),
        quiet=args.json,
        **engine_kwargs,
    )


if __name__ == "__main__":
    sys.exit(main())
