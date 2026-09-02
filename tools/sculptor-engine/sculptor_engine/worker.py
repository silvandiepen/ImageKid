"""The long-lived worker process: read requests, run jobs, emit messages.

The app keeps one worker alive while Sculptor is open, because loading model
weights is far more expensive than running a generation.

Two details matter more than they look:

*Protocol isolation.* PyTorch and its dependencies print to ``stdout`` on
import. A single stray line corrupts the protocol stream, so :func:`serve` takes
a private duplicate of the real stdout for protocol traffic and points file
descriptor 1 at stderr. Everything a library prints becomes a diagnostic.

*Cancellation.* Requests are read on a background thread so a ``cancel`` that
arrives mid-generation is acted on immediately rather than queueing behind the
job it is trying to stop.
"""

from __future__ import annotations

import json
import os
import queue
import sys
import threading
import time
import traceback
from pathlib import Path
from typing import Callable, TextIO

from . import elements, imageprep, meshnorm, multiview, views, workspace
from .engines import (
    DEFAULT_ENGINE,
    Cancelled,
    EngineUnavailable,
    InferenceFailed,
    OutOfMemory,
    ReconstructionEngine,
    create_engine,
)
from .protocol import (
    AnalyseRequest,
    CancelRequest,
    ErrorCode,
    GenerateOptions,
    GenerateRequest,
    ProtocolError,
    ResultArtifacts,
    ShutdownRequest,
    Stage,
    analysis_message,
    decode_request,
    error_message,
    progress_message,
    ready_message,
    result_message,
)

#: Both supported engines predict visible surface and hidden geometry in one
#: forward pass. The two user-facing stages split that pass at this point so the
#: progress copy stays truthful about what the user is waiting for.
HIDDEN_SIDE_SPLIT = 0.5


class Emitter:
    """Writes protocol messages, one JSON object per line."""

    def __init__(self, stream: TextIO) -> None:
        self._stream = stream
        self._lock = threading.Lock()

    def send(self, message: dict) -> None:
        line = json.dumps(message, separators=(",", ":"), ensure_ascii=False)
        with self._lock:
            self._stream.write(line + "\n")
            self._stream.flush()


def log(message: str) -> None:
    """Diagnostics. Never goes to the protocol stream."""

    print(f"[sculptor-engine] {message}", file=sys.stderr, flush=True)


def _describe(yaw: float, pitch: float) -> str:
    """A camera position in words, for the log."""

    for name, angles in multiview.NAMED_VIEWS.items():
        if angles == (yaw, pitch):
            return name
    return f"{yaw:g}°" if not pitch else f"{yaw:g}°/{pitch:g}°"


class Worker:
    """Owns the engine and runs one job at a time."""

    def __init__(self, engine: ReconstructionEngine, emitter: Emitter) -> None:
        self._engine = engine
        self._emit = emitter
        self._cancelled: set[str] = set()
        self._cancel_lock = threading.Lock()
        self._active_job: str | None = None

    # -- cancellation -------------------------------------------------------

    def cancel(self, job_id: str) -> None:
        with self._cancel_lock:
            self._cancelled.add(job_id)

    def _is_cancelled(self, job_id: str) -> bool:
        with self._cancel_lock:
            return job_id in self._cancelled

    def _clear_cancel(self, job_id: str) -> None:
        with self._cancel_lock:
            self._cancelled.discard(job_id)

    # -- job ----------------------------------------------------------------

    def run(self, request: GenerateRequest) -> None:
        """Execute one generation, emitting progress then a result or an error."""

        job_id = request.jobId
        self._active_job = job_id
        started = time.monotonic()

        def progress(stage: Stage, fraction: float = 0.0) -> None:
            self._emit.send(progress_message(job_id, stage, fraction))

        def check_cancel() -> None:
            if self._is_cancelled(job_id):
                raise Cancelled("cancelled by request")

        try:
            options = request.options

            # 1. Preparing image ------------------------------------------------
            progress(Stage.PREPARING_IMAGE)
            space = workspace.prepare(request.workspace)
            check_cancel()
            image = imageprep.load_source(request.sourcePath)
            sources, from_sheet = self._gather_views(job_id, image, request)
            progress(Stage.PREPARING_IMAGE, 1.0)

            # 2. Isolating object -----------------------------------------------
            progress(Stage.ISOLATING_OBJECT)
            prepared_views = []
            for index, source_image in enumerate(sources):
                check_cancel()
                prepared_views.append(
                    imageprep.isolate_subject(
                        source_image,
                        space.prepared_view_path(index),
                        # A supplied mask describes the source file, so it only
                        # applies when the source file is the whole subject.
                        mask_path=request.maskPath if len(sources) == 1 else None,
                        padding=options.cropPadding,
                        size=options.inputSize,
                        # A view cut out of a sheet was framed here, not by
                        # whoever made the picture.
                        framed_by_us=from_sheet,
                    )
                )
                progress(Stage.ISOLATING_OBJECT, (index + 1) / len(sources))
            prepared = prepared_views[0]
            for note in prepared.notes:
                log(f"{job_id}: {note}")
            log(f"{job_id}: suitability={prepared.suitability.value}")

            # 3-4. Reconstructing / building hidden sides -----------------------
            progress(Stage.RECONSTRUCTING)
            check_cancel()
            count = len(prepared_views)

            def report(fraction: float) -> None:
                if fraction <= HIDDEN_SIDE_SPLIT:
                    progress(Stage.RECONSTRUCTING, fraction / HIDDEN_SIDE_SPLIT)
                else:
                    progress(
                        Stage.BUILDING_HIDDEN_SIDES,
                        (fraction - HIDDEN_SIDE_SPLIT) / (1 - HIDDEN_SIDE_SPLIT),
                    )

            if options.blocks and count > 1:
                # Carved from the panels' outlines: no reconstruction at all.
                geometry, view_count = self._carve(
                    job_id, prepared_views, report, blocks=options.blocks
                )
            elif options.cartoon and count > 1:
                # Carved from the panels' own shapes. The reconstruction engine
                # is never asked, which is most of why this path is quick.
                geometry, view_count = self._carve(job_id, prepared_views, report)
            else:
                reconstructed = []
                for index, view in enumerate(prepared_views):
                    check_cancel()
                    reconstructed.append(
                        self._engine.reconstruct(
                            view.path,
                            # Each view is one slice of the same progress bar,
                            # so a three-view job advances a third as fast
                            # rather than snapping back to zero twice.
                            progress=lambda fraction, index=index: report(
                                (index + fraction) / count
                            ),
                            should_cancel=lambda: self._is_cancelled(job_id),
                        )
                    )

                if count > 1:
                    # The silhouettes the engine was actually shown: the
                    # evidence every candidate model is checked against.
                    import numpy as np
                    from PIL import Image as _Image

                    pictures = [
                        np.asarray(_Image.open(view.path).convert("RGBA"))[:, :, 3] > 8
                        for view in prepared_views
                    ]
                    geometry, view_count = self._fuse(
                        job_id, reconstructed, options, pictures
                    )
                else:
                    geometry, view_count = reconstructed[0], 1

                if options.blocks:
                    # One picture, so there are no other outlines to carve
                    # against. Blocks cannot make a wrong shape right, but they
                    # make it a deliberate object rather than a lumpy one.
                    from . import shapes

                    geometry = shapes.blockify(
                        multiview.as_mesh(geometry), size=options.blocks
                    )
                    log(
                        f"{job_id}: rebuilt as blocks on a {options.blocks}-cell "
                        f"grid, {len(geometry.faces)} triangles"
                    )

            progress(Stage.BUILDING_HIDDEN_SIDES, 1.0)

            # 5. Cleaning model -------------------------------------------------
            progress(Stage.CLEANING_MODEL)
            check_cancel()
            # Blocks are finished the moment they are built, and the usual
            # finishing pass destroys them. Smoothing assumes one connected
            # surface; a pile of separate cubes shares no edges, so each cube
            # collapses toward its own centre and the model renders as a cloud
            # of specks. Their colours are already flat, so there is nothing to
            # quantise either, and their triangle count is already low.
            finishing = (
                dict(smoothing_iterations=0, target_triangles=0, palette_colours=0)
                if options.blocks
                else dict(
                    smoothing_iterations=options.smoothingIterations,
                    target_triangles=options.targetTriangles,
                    palette_colours=options.paletteColours,
                )
            )
            scene, asset = meshnorm.normalise(
                geometry,
                fragment_threshold=0.0 if options.blocks else options.fragmentThreshold,
                normalise_scale=options.normaliseScale,
                pitch_correction=options.pitchCorrection,
                align_ground=options.alignGround,
                **finishing,
            )
            if asset.removed_fragments:
                log(f"{job_id}: removed {asset.removed_fragments} stray fragment(s)")
            if asset.simplified_from:
                log(
                    f"{job_id}: simplified {asset.simplified_from} -> "
                    f"{asset.triangle_count} triangles"
                )
            progress(Stage.CLEANING_MODEL, 1.0)

            # 6. Preparing preview ----------------------------------------------
            progress(Stage.PREPARING_PREVIEW)
            check_cancel()
            glb = meshnorm.export_glb(
                scene,
                temporary=space.temp_dir / "model.glb.part",
                destination=space.glb_path,
            )
            preview = meshnorm.export_preview_obj(scene, space.preview_path)

            # Extra formats alongside the canonical GLB, for callers that need
            # to hand the asset to something else.
            exports: dict[str, str] = {}
            for file_format in options.exportFormats:
                if file_format == "glb":
                    exports["glb"] = str(glb)
                    continue
                extra = meshnorm.export_mesh(
                    scene,
                    space.output_dir / f"model{meshnorm.EXPORT_FORMATS[file_format]}",
                    file_format,
                )
                exports[file_format] = str(extra)
            progress(Stage.PREPARING_PREVIEW, 1.0)

            self._emit.send(
                result_message(
                    job_id,
                    ResultArtifacts(
                        glbPath=str(glb),
                        previewPath=str(preview),
                        exports=exports,
                        preparedImagePath=str(prepared.path),
                        viewCount=view_count,
                        triangleCount=asset.triangle_count,
                        vertexCount=asset.vertex_count,
                        hasTexture=asset.has_texture,
                        appliedScale=asset.applied_scale,
                        boundingBoxLongestEdge=asset.bounding_box_longest_edge,
                        upAxis=asset.up_axis,
                        originConvention=asset.origin_convention,
                        durationSeconds=round(time.monotonic() - started, 3),
                    ),
                )
            )
        except Cancelled as exc:
            self._fail(job_id, ErrorCode.CANCELLED, str(exc))
        except EngineUnavailable as exc:
            self._fail(job_id, ErrorCode.MODEL_NOT_INSTALLED, str(exc))
        except OutOfMemory as exc:
            self._fail(job_id, ErrorCode.INSUFFICIENT_MEMORY, str(exc))
        except InferenceFailed as exc:
            self._fail(job_id, ErrorCode.INFERENCE_FAILED, str(exc))
        except workspace.InsufficientDiskSpace as exc:
            self._fail(job_id, ErrorCode.INSUFFICIENT_DISK_SPACE, str(exc))
        except imageprep.UnsupportedImage as exc:
            self._fail(job_id, ErrorCode.UNSUPPORTED_IMAGE, str(exc))
        except imageprep.CorruptImage as exc:
            self._fail(job_id, ErrorCode.CORRUPT_IMAGE, str(exc))
        except imageprep.NoForegroundFound as exc:
            self._fail(job_id, ErrorCode.NO_FOREGROUND_FOUND, str(exc))
        except meshnorm.InvalidMesh as exc:
            self._fail(job_id, ErrorCode.INVALID_MESH, str(exc))
        except meshnorm.ExportFailed as exc:
            self._fail(job_id, ErrorCode.EXPORT_FAILED, str(exc))
        except (workspace.WorkspaceError, OSError) as exc:
            self._fail(job_id, ErrorCode.INTERNAL_ERROR, str(exc))
        except Exception as exc:  # never let one job kill the worker
            log(traceback.format_exc())
            self._fail(job_id, ErrorCode.INTERNAL_ERROR, f"{type(exc).__name__}: {exc}")
        finally:
            self._clear_cancel(job_id)
            self._active_job = None

    # -- views --------------------------------------------------------------

    def _gather_views(
        self, job_id: str, image, request: GenerateRequest
    ) -> tuple[list, bool]:
        """Every image this job should reconstruct from, in camera order.

        Three cases, in the order they take precedence: views the caller
        supplied outright; several views found laid out inside one image; or
        the ordinary single image.

        Also reports whether the views were cut out of a sheet, because their
        framing is then ours rather than the picture's.
        """

        if request.viewPaths:
            extra = [imageprep.load_source(path) for path in request.viewPaths]
            log(f"{job_id}: {len(extra) + 1} views supplied")
            return [image] + extra, False

        if not request.options.splitSheet:
            return [image], False

        cells = views.find_cells(image)
        if len(cells) < 2:
            return [image], False

        log(
            f"{job_id}: found {len(cells)} views laid out in the source image; "
            "reconstructing each"
        )
        return [cell.image for cell in cells], True

    def _carve(
        self, job_id: str, prepared_views: list, report, blocks: int = 0
    ) -> tuple:
        """Build the model from the panels' own flat-coloured shapes.

        The panels are already cut out and squared up, so all that remains is to
        read the shapes out of each and carve. Nothing is reconstructed, which
        is why this takes seconds where the engine takes minutes.
        """

        import numpy as np
        from PIL import Image as _Image

        panels = []
        for index, view in enumerate(prepared_views):
            picture = _Image.open(view.path).convert("RGBA")
            subject = np.asarray(picture)[:, :, 3] > 8
            found = elements.find(picture)
            log(f"{job_id}: panel {index}: {len(found)} shapes")
            panels.append(
                (
                    elements.Panel(
                        subject=subject,
                        direction=multiview.camera_direction(
                            *multiview.NAMED_VIEWS["front"]
                        ),
                    ),
                    found,
                )
            )
            report((index + 1) / len(prepared_views) * HIDDEN_SIDE_SPLIT)

        # Place each panel's camera. Cartoon mode needs the same reading of the
        # sheet as everything else does.
        readings = self._view_angles(len(panels), GenerateOptions())
        reading = readings[0]
        panels = [
            (
                elements.Panel(
                    subject=panel.subject,
                    direction=multiview.camera_direction(*angles),
                ),
                found,
            )
            for (panel, found), angles in zip(panels, reading)
        ]

        # Only the level panels: an overhead one cannot yet be placed the right
        # way round, and a wrongly rolled panel carves the model to a sliver.
        level = [
            (panel, found)
            for (panel, found), angles in zip(panels, reading)
            if angles[1] == 0.0
        ]
        if len(level) < 2:
            raise ValueError("cartoon mode needs at least two level views")

        if blocks:
            model, pieces = elements.blocks(level, size=blocks)
            log(
                f"{job_id}: built {pieces} materials as blocks on a {blocks}-cell "
                f"grid from {len(level)} panels, {len(model.faces)} triangles"
            )
        else:
            model, pieces = elements.build(level)
            log(
                f"{job_id}: carved {pieces} shapes from {len(level)} panels, "
                f"{len(model.faces)} triangles"
            )
        return model, len(level)

    def _fuse(
        self,
        job_id: str,
        reconstructed: list,
        options: GenerateOptions,
        pictures: list,
    ) -> tuple:
        """Choose the model that best explains the panels' own pictures.

        By default the candidates are the reconstructions themselves — one per
        panel, each turned to face where its camera stood. Several views of an
        object do not have to be blended to be useful: they let the best of them
        be *identified*, which one picture alone cannot do. A subject
        photographed end-on comes back flat and says nothing about it; the panel
        that saw the length disagrees, and the pictures settle it.

        Blending is opt-in, and that is a retreat from where this started.
        Rebuilding the surface out of an occupancy grid fixes the outline and
        ruins the model: measured on a real six-panel sheet it flattened the
        horns, softened the ears and smeared the muzzle across the face, and the
        outline score went *up* while it did so. A silhouette metric cannot see
        any of that, which is exactly how it happened.

        Returns the geometry and how many views went into it, so the result
        never claims views it did not use.
        """

        count = len(reconstructed)
        try:
            readings = self._view_angles(count, options)
        except multiview.UnknownAngles as exc:
            # A caller who stated the wrong number of angles gets an error
            # instead: that is a mistake worth hearing about.
            log(f"{job_id}: {exc}; using the first view alone")
            return reconstructed[0], 1

        meshes = [multiview.as_mesh(geometry) for geometry in reconstructed]
        best: tuple[float, str, object, int] | None = None

        for reading in readings:
            views = [
                multiview.View(mesh=mesh, yaw=yaw, pitch=pitch)
                for mesh, (yaw, pitch) in zip(meshes, reading)
            ]
            named = " ".join(_describe(*angles) for angles in reading)

            # Each panel's own reconstruction, turned to face where its camera
            # stood. Scale and placement do not enter into the scoring, so the
            # orientation is all that is needed.
            attempts: list[tuple[str, object, int]] = []
            for index, view in enumerate(views):
                placed = view.mesh.copy()
                placed.apply_transform(view.orientation)
                attempts.append((f"the {_describe(*reading[index])} view", placed, 1))

            if options.fuseViews:
                level = [view for view in views if view.pitch == 0.0]
                subsets = [("all views fused", views)]
                if 2 <= len(level) < len(views):
                    subsets.append(("the level views fused", level))
                for how, subset in subsets:
                    if len(subset) < 2:
                        continue
                    try:
                        attempts.append((how, multiview.fuse(subset), len(subset)))
                    except Exception as exc:
                        log(
                            f"{job_id}: could not fuse {how} of [{named}] "
                            f"({type(exc).__name__}: {exc})"
                        )

            for how, mesh, used in attempts:
                scores = multiview.agreement(mesh, views, pictures)
                mean = sum(scores) / len(scores)
                log(
                    f"{job_id}: [{named}] {how} scores {mean:.3f} ("
                    + ", ".join(f"{score:.2f}" for score in scores)
                    + ")"
                )
                if best is None or mean > best[0]:
                    best = (mean, f"{how} of [{named}]", mesh, used)

        assert best is not None
        score, label, mesh, used = best
        log(
            f"{job_id}: using {label} — {score:.3f} against the "
            f"{count} pictures"
        )
        return mesh, used

    @staticmethod
    def _view_angles(count: int, options: GenerateOptions) -> list[list[tuple]]:
        """Readings of the sheet worth trying, each a list of (yaw, pitch).

        A caller who says which panel is which gets exactly that, and one who
        gives angles gets those. With nothing declared there is more than one
        plausible reading, so all of them are returned and the pictures decide
        between them.
        """

        if options.viewNames:
            if len(options.viewNames) != count:
                raise ValueError(
                    f"{len(options.viewNames)} view names given for {count} views"
                )
            return [[multiview.NAMED_VIEWS[name] for name in options.viewNames]]

        if options.viewYaws:
            if len(options.viewYaws) != count:
                raise ValueError(
                    f"{len(options.viewYaws)} view angles given for {count} views"
                )
            pitches = options.viewPitches or (0.0,) * count
            if len(pitches) != count:
                raise ValueError(
                    f"{len(pitches)} view elevations given for {count} views"
                )
            return [list(zip(options.viewYaws, pitches))]

        return [list(reading) for reading in multiview.candidate_layouts(count)]

    def _fail(self, job_id: str, code: ErrorCode, message: str) -> None:
        log(f"{job_id}: {code.value}: {message}")
        self._emit.send(error_message(job_id, code, message))

    # -- analysis -----------------------------------------------------------

    def analyse(self, request: AnalyseRequest) -> None:
        """Rate a source image without reconstructing it.

        Runs on the reader thread rather than the job queue: it never touches
        the engine and takes milliseconds, so it must not wait behind a
        generation the user is still watching.
        """

        try:
            image = imageprep.load_source(request.sourcePath)
            # Rate what will actually be reconstructed. A turnaround sheet
            # judged whole reads as a badly framed subject; judged by its first
            # view it reads as what it is.
            cells = views.find_cells(image)
            view_count = max(len(cells), 1)
            subject = cells[0].image if cells else image
            mask = imageprep.resolve_mask(subject, request.maskPath if not cells else None)
            box = imageprep.subject_box(subject, mask)
            verdict, notes, coverage, touches_edge = imageprep.assess(
                subject, mask, box, framed_by_us=bool(cells)
            )
            if view_count > 1:
                notes = (
                    f"{view_count} views of one object found in this image; "
                    "all of them will be used.",
                ) + tuple(notes)
        except imageprep.UnsupportedImage as exc:
            self._emit.send(
                error_message(None, ErrorCode.UNSUPPORTED_IMAGE, str(exc))
            )
            return
        except (imageprep.CorruptImage, imageprep.NoForegroundFound) as exc:
            code = (
                ErrorCode.CORRUPT_IMAGE
                if isinstance(exc, imageprep.CorruptImage)
                else ErrorCode.NO_FOREGROUND_FOUND
            )
            self._emit.send(error_message(None, code, str(exc)))
            return
        except Exception as exc:
            log(f"analyse {request.requestId}: {type(exc).__name__}: {exc}")
            self._emit.send(
                error_message(None, ErrorCode.INTERNAL_ERROR, str(exc))
            )
            return

        self._emit.send(
            analysis_message(
                request.requestId,
                verdict.value,
                notes,
                mask is not None,
                coverage,
                touches_edge,
                view_count,
            )
        )


def _reader(
    stream: TextIO,
    jobs: "queue.Queue[GenerateRequest | ShutdownRequest]",
    on_cancel: Callable[[str], None],
    on_analyse: Callable[[AnalyseRequest], None],
    emitter: Emitter,
) -> None:
    """Read requests off stdin.

    ``cancel`` is handled here rather than queued, so it reaches a running job
    immediately. Everything else is handed to the main thread in order.
    """

    try:
        for line in stream:
            line = line.strip()
            if not line:
                continue
            try:
                request = decode_request(line)
            except ProtocolError as exc:
                emitter.send(
                    error_message(None, ErrorCode.MALFORMED_REQUEST, str(exc))
                )
                continue
            if isinstance(request, CancelRequest):
                on_cancel(request.jobId)
            elif isinstance(request, AnalyseRequest):
                # Cheap and engine-free, so it is answered here rather than
                # queued behind a generation in progress.
                on_analyse(request)
            else:
                jobs.put(request)
                if isinstance(request, ShutdownRequest):
                    return
    finally:
        jobs.put(ShutdownRequest())


def serve(engine_name: str = DEFAULT_ENGINE, **engine_kwargs) -> int:
    """Run the request loop until stdin closes or a shutdown arrives."""

    # Take a private handle on the real stdout before anything can write to it,
    # then point fd 1 at stderr so library chatter cannot corrupt the protocol.
    protocol_fd = os.dup(1)
    os.dup2(2, 1)
    sys.stdout = os.fdopen(2, "w", closefd=False)
    protocol_stream = os.fdopen(protocol_fd, "w", encoding="utf-8", closefd=True)

    emitter = Emitter(protocol_stream)

    try:
        engine = create_engine(engine_name, **engine_kwargs)
    except Exception as exc:
        emitter.send(
            error_message(None, ErrorCode.INTERNAL_ERROR, f"could not create engine: {exc}")
        )
        return 1

    emitter.send(
        ready_message(engine.name, engine.is_available, engine.unavailable_reason)
    )

    worker = Worker(engine, emitter)
    jobs: "queue.Queue[GenerateRequest | ShutdownRequest]" = queue.Queue()
    reader = threading.Thread(
        target=_reader,
        args=(sys.stdin, jobs, worker.cancel, worker.analyse, emitter),
        daemon=True,
        name="sculptor-reader",
    )
    reader.start()

    while True:
        request = jobs.get()
        if isinstance(request, ShutdownRequest):
            break
        worker.run(request)

    protocol_stream.flush()
    return 0


def run_once(
    source: Path,
    output: Path,
    mask: Path | None = None,
    extra_views: list | None = None,
    work_dir: Path | None = None,
    engine_name: str = DEFAULT_ENGINE,
    options: GenerateOptions | None = None,
    quiet: bool = False,
    **engine_kwargs,
) -> int:
    """One-shot command-line generation, for scripting and for agents.

    Emits the same protocol messages on stdout as :func:`serve`, so the CLI and
    the app observe identical behaviour.

    With ``quiet``, progress is suppressed and a single JSON object describing
    the outcome is printed instead — one parse, one result, for a caller that
    wants an answer rather than a stream.
    """

    import tempfile
    import uuid

    collected: list[dict] = []

    class _Collector(Emitter):
        def __init__(self) -> None:
            self._stream = sys.stdout
            self._lock = threading.Lock()

        def send(self, message: dict) -> None:
            collected.append(message)
            if not quiet:
                super().send(message)

    emitter = _Collector()
    try:
        engine = create_engine(engine_name, **engine_kwargs)
    except Exception as exc:
        emitter.send(
            error_message(None, ErrorCode.INTERNAL_ERROR, f"could not create engine: {exc}")
        )
        return 1

    emitter.send(
        ready_message(engine.name, engine.is_available, engine.unavailable_reason)
    )

    job_id = uuid.uuid4().hex[:12]
    with tempfile.TemporaryDirectory(prefix="sculptor-") as fallback:
        root = Path(work_dir) if work_dir else Path(fallback) / job_id
        worker = Worker(engine, emitter)
        worker.run(
            GenerateRequest(
                jobId=job_id,
                sourcePath=str(source),
                workspace=str(root),
                maskPath=str(mask) if mask else None,
                viewPaths=tuple(str(path) for path in (extra_views or ())),
                options=options or GenerateOptions(),
            )
        )
        produced = workspace.JobWorkspace(root).glb_path
        if not produced.is_file():
            if quiet:
                failure = next(
                    (m for m in collected if m.get("type") == "error"), None
                )
                print(json.dumps({
                    "ok": False,
                    "error": (failure or {}).get("message", "generation failed"),
                    "code": (failure or {}).get("code", "internalError"),
                }))
            return 1
        output.parent.mkdir(parents=True, exist_ok=True)
        # shutil.move, not os.replace: the workspace may sit on a different
        # filesystem from the destination when it defaults to a temp directory.
        import shutil

        shutil.move(str(produced), str(output))

        result = next((m for m in collected if m.get("type") == "result"), {})

        # Extra formats land beside the GLB, named after it, so a caller gets
        # `model.obj` next to `model.glb` rather than a path inside a temporary
        # workspace that is about to be deleted.
        exports = {"glb": str(output)}
        for file_format, path in (result.get("exports") or {}).items():
            if file_format == "glb":
                continue
            source_path = Path(path)
            if not source_path.is_file():
                continue
            beside = output.with_suffix(meshnorm.EXPORT_FORMATS[file_format])
            shutil.move(str(source_path), str(beside))
            exports[file_format] = str(beside)

        if quiet:
            print(
                json.dumps(
                    {
                        "ok": True,
                        "output": str(output),
                        "exports": exports,
                        "views": result.get("viewCount"),
                        "triangles": result.get("triangleCount"),
                        "vertices": result.get("vertexCount"),
                        "hasColour": result.get("hasTexture"),
                        "upAxis": result.get("upAxis"),
                        "originConvention": result.get("originConvention"),
                        "seconds": result.get("durationSeconds"),
                    }
                )
            )
    return 0
