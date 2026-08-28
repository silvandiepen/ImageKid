"""Run a folder of images through the worker and record timing and quality.

This is the Phase 0 spike harness from ``docs/sculptor.md``: run a corpus of
representative single-object images, verify front/side/back quality, and record
generation time and peak memory so the stage weights and the stated system
requirements come from measurement rather than upstream marketing.

    python scripts/run_corpus.py ~/tiko --output out/corpus

Writes one GLB and one contact sheet per image, plus ``summary.json``.
"""

from __future__ import annotations

import argparse
import json
import resource
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sculptor_engine import imageprep, meshnorm  # noqa: E402
from sculptor_engine.engines import create_engine  # noqa: E402
from sculptor_engine.engines.base import EngineError  # noqa: E402

IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp"}


def peak_memory_mb() -> float:
    """Peak resident set size. macOS reports bytes, Linux kilobytes."""

    peak = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    return peak / (1024 * 1024) if sys.platform == "darwin" else peak / 1024


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("corpus", type=Path, help="folder of source images")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--engine", default=None)
    parser.add_argument("--device", default=None)
    parser.add_argument("--mc-resolution", type=int, default=None)
    parser.add_argument("--input-size", type=int, default=512)
    parser.add_argument("--padding", type=float, default=0.08)
    parser.add_argument(
        "--pitch",
        type=float,
        default=0.0,
        help="degrees of pitch to undo the source camera elevation "
        "(-60 for the isometric Tiko Media renders)",
    )
    parser.add_argument("--render", action="store_true", help="write contact sheets")
    args = parser.parse_args()

    sources = sorted(
        p for p in args.corpus.iterdir() if p.suffix.lower() in IMAGE_SUFFIXES
    )
    if not sources:
        raise SystemExit(f"no images in {args.corpus}")

    kwargs = {}
    if args.device:
        kwargs["device"] = args.device
    if args.mc_resolution:
        kwargs["marching_cubes_resolution"] = args.mc_resolution

    from sculptor_engine.engines import DEFAULT_ENGINE

    engine = create_engine(args.engine or DEFAULT_ENGINE, **kwargs)
    if not engine.is_available:
        raise SystemExit(f"engine unavailable: {engine.unavailable_reason}")

    args.output.mkdir(parents=True, exist_ok=True)
    records = []

    for source in sources:
        stem = source.stem
        print(f"--- {stem}", flush=True)
        record = {"name": stem}
        started = time.monotonic()
        try:
            prepared_path = args.output / f"{stem}-prepared.png"
            image = imageprep.load_source(source)
            prepared = imageprep.isolate_subject(
                image, prepared_path, padding=args.padding, size=args.input_size
            )
            record["suitability"] = prepared.suitability.value
            record["hadMask"] = prepared.had_mask
            record["notes"] = list(prepared.notes)

            inference_started = time.monotonic()
            geometry = engine.reconstruct(
                prepared.path, progress=lambda _f: None, should_cancel=lambda: False
            )
            record["inferenceSeconds"] = round(time.monotonic() - inference_started, 2)

            scene, asset = meshnorm.normalise(
                geometry, pitch_correction=args.pitch
            )
            glb = meshnorm.export_glb(
                scene,
                temporary=args.output / f"{stem}.glb.part",
                destination=args.output / f"{stem}.glb",
            )
            record.update(
                {
                    "ok": True,
                    "triangles": asset.triangle_count,
                    "vertices": asset.vertex_count,
                    "hasTexture": asset.has_texture,
                    "removedFragments": asset.removed_fragments,
                    # False means no dominant base plane was found and the mesh
                    # kept the engine's camera-frame orientation.
                    "groundAligned": asset.ground_aligned,
                    "glb": str(glb),
                }
            )

            if args.render:
                from render_views import as_single_mesh, render, BACKGROUND, VIEWS
                from PIL import Image

                mesh = as_single_mesh(glb)
                size = 288
                sheet = Image.new(
                    "RGB", (size * len(VIEWS), size), tuple(BACKGROUND)
                )
                for index, (_, yaw) in enumerate(VIEWS):
                    sheet.paste(render(mesh, yaw, size), (index * size, 0))
                sheet_path = args.output / f"{stem}-views.png"
                sheet.save(sheet_path)
                record["views"] = str(sheet_path)
        except (EngineError, imageprep.ImagePrepError, meshnorm.MeshError) as exc:
            record.update({"ok": False, "error": f"{type(exc).__name__}: {exc}"})
            print(f"    FAILED {exc}", flush=True)

        record["totalSeconds"] = round(time.monotonic() - started, 2)
        record["peakMemoryMb"] = round(peak_memory_mb(), 1)
        records.append(record)
        if record.get("ok"):
            print(
                f"    {record['triangles']} tris  "
                f"{record['inferenceSeconds']}s inference  "
                f"{record['peakMemoryMb']} MB peak",
                flush=True,
            )

    summary = {
        "engine": engine.name,
        "device": getattr(engine, "_device", None),
        "inputSize": args.input_size,
        "padding": args.padding,
        "pitchCorrection": args.pitch,
        "marchingCubesResolution": args.mc_resolution,
        "results": records,
    }
    (args.output / "summary.json").write_text(json.dumps(summary, indent=2))

    ok = [r for r in records if r.get("ok")]
    print(f"\n{len(ok)}/{len(records)} succeeded")
    if ok:
        times = [r["inferenceSeconds"] for r in ok]
        print(
            f"inference: min {min(times)}s  median "
            f"{sorted(times)[len(times) // 2]}s  max {max(times)}s"
        )
        print(f"peak memory: {max(r['peakMemoryMb'] for r in ok)} MB")
    return 0 if len(ok) == len(records) else 1


if __name__ == "__main__":
    raise SystemExit(main())
