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
        "--view",
        dest="views",
        action="append",
        type=Path,
        metavar="IMAGE",
        help="another view of the same object, reconstructed and fused with "
        "--image; repeatable, in camera order",
    )
    parser.add_argument(
        "--view-yaw",
        dest="view_yaws",
        action="append",
        type=float,
        metavar="DEGREES",
        help="camera angle for each view including --image; repeatable. "
        "Defaults to quarter turns: 0, 90, 180, 270",
    )
    parser.add_argument(
        "--view-name",
        dest="view_names",
        action="append",
        choices=["front", "right", "back", "left", "top", "bottom"],
        help="which view each panel is, including --image; repeatable. The "
        "clearest way to describe a sheet, and the only way to describe one "
        "with top or bottom panels",
    )
    parser.add_argument(
        "--view-pitch",
        dest="view_pitches",
        action="append",
        type=float,
        metavar="DEGREES",
        help="camera elevation for each view: 90 is overhead, -90 underneath",
    )
    parser.add_argument(
        "--blocks",
        type=int,
        default=None,
        metavar="N",
        help="build the model out of blocks on a grid N cells across, e.g. 28",
    )
    parser.add_argument(
        "--cartoon",
        action="store_true",
        help="build the model from the panels' own flat-coloured shapes instead "
        "of reconstructing a surface. Needs several views; never runs the "
        "reconstruction engine",
    )
    parser.add_argument(
        "--fuse-views",
        action="store_true",
        help="blend the views into one surface instead of choosing the best of "
        "them. Off by default: fusing rebuilds the surface from a voxel grid "
        "and loses the detail the engine produced",
    )
    parser.add_argument(
        "--no-split-sheet",
        dest="split_sheet",
        action="store_false",
        help="feed a turnaround sheet in whole instead of recognising the "
        "views laid out inside it",
    )
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
        help="Taubin smoothing passes (default 30; 0 keeps the raw isosurface)",
    )
    parser.add_argument(
        "--triangles",
        type=int,
        default=None,
        metavar="N",
        help="decimate to about N triangles (default 20000; 0 keeps them all)",
    )
    parser.add_argument(
        "--palette",
        type=int,
        default=None,
        metavar="N",
        help="flatten colour to N tones for a cartoon look "
        "(default 12; 0 keeps the sampled colour)",
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
    if args.palette is not None:
        overrides["paletteColours"] = args.palette
    if args.formats:
        overrides["exportFormats"] = tuple(dict.fromkeys(args.formats))
    if not args.split_sheet:
        overrides["splitSheet"] = False
    if args.fuse_views:
        overrides["fuseViews"] = True
    if args.cartoon:
        overrides["cartoon"] = True
    if args.blocks is not None:
        overrides["blocks"] = args.blocks
    # Only checkable here when the views were named on the command line; a
    # sheet's view count is not known until the image is opened, and the worker
    # checks it then.
    expected = len(args.views or []) + 1
    for flag, given, key in (
        ("--view-yaw", args.view_yaws, "viewYaws"),
        ("--view-pitch", args.view_pitches, "viewPitches"),
        ("--view-name", args.view_names, "viewNames"),
    ):
        if not given:
            continue
        if args.views and len(given) != expected:
            parser.error(
                f"{flag} given {len(given)} times for {expected} views"
            )
        overrides[key] = tuple(given)

    return run_once(
        source=args.image,
        output=args.output,
        mask=args.mask,
        extra_views=args.views,
        work_dir=args.work_dir,
        engine_name=engine_name,
        options=GenerateOptions(**overrides),
        quiet=args.json,
        **engine_kwargs,
    )


if __name__ == "__main__":
    sys.exit(main())
