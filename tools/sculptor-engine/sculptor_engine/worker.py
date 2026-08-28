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

from . import imageprep, meshnorm, workspace
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
            progress(Stage.PREPARING_IMAGE, 1.0)

            # 2. Isolating object -----------------------------------------------
            progress(Stage.ISOLATING_OBJECT)
            check_cancel()
            prepared = imageprep.isolate_subject(
                image,
                space.prepared_image_path,
                mask_path=request.maskPath,
                padding=options.cropPadding,
                size=options.inputSize,
            )
            for note in prepared.notes:
                log(f"{job_id}: {note}")
            log(f"{job_id}: suitability={prepared.suitability.value}")
            progress(Stage.ISOLATING_OBJECT, 1.0)

            # 3-4. Reconstructing / building hidden sides -----------------------
            progress(Stage.RECONSTRUCTING)
            check_cancel()

            def on_engine_progress(fraction: float) -> None:
                if fraction <= HIDDEN_SIDE_SPLIT:
                    progress(Stage.RECONSTRUCTING, fraction / HIDDEN_SIDE_SPLIT)
                else:
                    progress(
                        Stage.BUILDING_HIDDEN_SIDES,
                        (fraction - HIDDEN_SIDE_SPLIT) / (1 - HIDDEN_SIDE_SPLIT),
                    )

            geometry = self._engine.reconstruct(
                prepared.path,
                progress=on_engine_progress,
                should_cancel=lambda: self._is_cancelled(job_id),
            )
            progress(Stage.BUILDING_HIDDEN_SIDES, 1.0)

            # 5. Cleaning model -------------------------------------------------
            progress(Stage.CLEANING_MODEL)
            check_cancel()
            scene, asset = meshnorm.normalise(
                geometry,
                fragment_threshold=options.fragmentThreshold,
                normalise_scale=options.normaliseScale,
                pitch_correction=options.pitchCorrection,
                align_ground=options.alignGround,
            )
            if asset.removed_fragments:
                log(f"{job_id}: removed {asset.removed_fragments} stray fragment(s)")
            progress(Stage.CLEANING_MODEL, 1.0)

            # 6. Preparing preview ----------------------------------------------
            progress(Stage.PREPARING_PREVIEW)
            check_cancel()
            glb = meshnorm.export_glb(
                scene,
                temporary=space.temp_dir / "model.glb.part",
                destination=space.glb_path,
            )
            preview = meshnorm.export_preview(scene, space.preview_path)
            progress(Stage.PREPARING_PREVIEW, 1.0)

            self._emit.send(
                result_message(
                    job_id,
                    ResultArtifacts(
                        glbPath=str(glb),
                        previewPath=str(preview),
                        preparedImagePath=str(prepared.path),
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
            mask = imageprep.resolve_mask(image, request.maskPath)
            box = imageprep.subject_box(image, mask)
            verdict, notes, coverage, touches_edge = imageprep.assess(image, mask, box)
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
    work_dir: Path | None = None,
    engine_name: str = DEFAULT_ENGINE,
    options: GenerateOptions | None = None,
    **engine_kwargs,
) -> int:
    """One-shot command-line generation, for the spike and for scripting.

    Emits the same protocol messages on stdout as :func:`serve`, so the CLI and
    the app observe identical behaviour.
    """

    import tempfile
    import uuid

    emitter = Emitter(sys.stdout)
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
                options=options or GenerateOptions(),
            )
        )
        produced = workspace.JobWorkspace(root).glb_path
        if not produced.is_file():
            return 1
        output.parent.mkdir(parents=True, exist_ok=True)
        # shutil.move, not os.replace: the workspace may sit on a different
        # filesystem from the destination when it defaults to a temp directory.
        import shutil

        shutil.move(str(produced), str(output))
    return 0
