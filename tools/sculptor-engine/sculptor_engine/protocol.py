"""Wire protocol between the Sculptor app and the local reconstruction worker.

One JSON object per line, UTF-8, newline terminated, in both directions.

Design rules that this module exists to enforce:

* No image or model bytes ever travel through a message. Messages carry
  sandbox-authorised local paths to files inside the job workspace.
* ``stdout`` carries protocol traffic and nothing else. Diagnostics go to
  ``stderr``. See ``sculptor_engine.worker`` for how third-party libraries are
  kept off the protocol stream.
* Keys are camelCase so the Swift side can decode them with a default
  ``JSONDecoder`` and no key strategy.
"""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from enum import Enum
from typing import Any, Union

PROTOCOL_VERSION = 1


class Stage(str, Enum):
    """User-facing progress stages, in the order the doc presents them."""

    PREPARING_IMAGE = "preparingImage"
    ISOLATING_OBJECT = "isolatingObject"
    RECONSTRUCTING = "reconstructing"
    BUILDING_HIDDEN_SIDES = "buildingHiddenSides"
    CLEANING_MODEL = "cleaningModel"
    PREPARING_PREVIEW = "preparingPreview"


#: Nominal share of a generation each stage occupies, used to turn per-stage
#: progress into an overall fraction. Derived from stage ordering only; the
#: Phase 0 spike should replace these with measured timings.
STAGE_WEIGHTS: dict[Stage, float] = {
    Stage.PREPARING_IMAGE: 0.04,
    Stage.ISOLATING_OBJECT: 0.06,
    Stage.RECONSTRUCTING: 0.55,
    Stage.BUILDING_HIDDEN_SIDES: 0.20,
    Stage.CLEANING_MODEL: 0.10,
    Stage.PREPARING_PREVIEW: 0.05,
}


class ErrorCode(str, Enum):
    """Failures the app is expected to render.

    Mirrors the "Failure handling" list in ``docs/sculptor.md``. The app owns the
    copy; the worker only classifies.
    """

    UNSUPPORTED_IMAGE = "unsupportedImage"
    CORRUPT_IMAGE = "corruptImage"
    NO_FOREGROUND_FOUND = "noForegroundFound"
    MODEL_NOT_INSTALLED = "modelNotInstalled"
    INSUFFICIENT_DISK_SPACE = "insufficientDiskSpace"
    INSUFFICIENT_MEMORY = "insufficientMemory"
    INFERENCE_FAILED = "inferenceFailed"
    INVALID_MESH = "invalidMesh"
    EXPORT_FAILED = "exportFailed"
    CANCELLED = "cancelled"
    MALFORMED_REQUEST = "malformedRequest"
    INTERNAL_ERROR = "internalError"


#: Failures the user can retry from without re-importing the source image.
RECOVERABLE_CODES = frozenset(
    {
        ErrorCode.NO_FOREGROUND_FOUND,
        ErrorCode.MODEL_NOT_INSTALLED,
        ErrorCode.INSUFFICIENT_DISK_SPACE,
        ErrorCode.INSUFFICIENT_MEMORY,
        ErrorCode.INFERENCE_FAILED,
        ErrorCode.INVALID_MESH,
        ErrorCode.EXPORT_FAILED,
        ErrorCode.CANCELLED,
    }
)


class ProtocolError(Exception):
    """A message could not be parsed into a request."""


# ---------------------------------------------------------------------------
# Requests (app -> worker)
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class GenerateOptions:
    """Per-job knobs. All optional; the defaults are the product defaults.

    None of these are exposed in the normal Sculptor UI. They exist so the
    engine spike and the test suite can drive the worker deterministically.
    """

    #: Fraction of the subject's longest side added as padding on each side
    #: before the square render.
    cropPadding: float = 0.08
    #: Square edge length handed to the reconstruction engine.
    inputSize: int = 512
    #: Drop disconnected mesh components smaller than this fraction of the
    #: largest component's surface area. ``0`` disables fragment removal.
    fragmentThreshold: float = 0.02
    #: Normalise the asset to a one-unit longest edge and record the applied
    #: scale in the result metadata.
    normaliseScale: bool = True
    #: Degrees of pitch to undo the source camera's elevation. Reconstruction
    #: happens in the camera's frame, so a subject rendered from above comes out
    #: tilted. 0 suits an eye-level photo; -60 stands up the isometric renders
    #: in the Tiko Media catalogue.
    pitchCorrection: float = 0.0
    #: Taubin smoothing passes over the surface. Marching cubes terraces every
    #: curved surface into concentric steps — most visible on the smooth,
    #: stylised subjects this product targets, where a rabbit's paws come out
    #: looking contoured. It takes a lot of passes to remove that, not a few.
    #: 0 keeps the raw isosurface.
    smoothingIterations: int = 30
    #: Decimate to about this many triangles. A 256 isosurface emits a couple
    #: of hundred thousand for shapes that are genuinely simple; once the
    #: terracing is smoothed away, the honest triangle count is far lower.
    #: 0 keeps every triangle.
    targetTriangles: int = 20000
    #: Extra formats to write beside the canonical GLB: obj, stl, ply.
    exportFormats: tuple = ()
    #: Recover the upright axis from the object's largest flat surface instead
    #: of a fixed pitch. Off by default: on real reconstructions the biggest
    #: planar region is often the smooth invented back face rather than the
    #: base, so this is a guess that can land the object on its side.
    alignGround: bool = False
    #: Seed for engines that sample. ``None`` means "engine default".
    seed: int | None = None
    #: Force a torch device ("mps", "cpu"). ``None`` means "auto-select".
    device: str | None = None
    #: Trade speed for peak memory in the reconstruction backend.
    lowMemory: bool = False

    @staticmethod
    def from_dict(raw: dict[str, Any] | None) -> "GenerateOptions":
        if raw is None:
            return GenerateOptions()
        if not isinstance(raw, dict):
            raise ProtocolError("options must be an object")
        unknown = set(raw) - set(GenerateOptions.__dataclass_fields__)
        if unknown:
            raise ProtocolError(f"unknown options: {', '.join(sorted(unknown))}")

        values = dict(raw)
        if "exportFormats" in values:
            formats = values["exportFormats"]
            if not isinstance(formats, (list, tuple)):
                raise ProtocolError("exportFormats must be an array")
            # Validated here rather than at export time, so a typo fails before
            # the user waits out a whole generation.
            from .meshnorm import EXPORT_FORMATS

            cleaned = []
            for name in formats:
                if not isinstance(name, str) or name.lower() not in EXPORT_FORMATS:
                    raise ProtocolError(
                        f"unsupported export format {name!r}; expected any of "
                        f"{', '.join(sorted(EXPORT_FORMATS))}"
                    )
                cleaned.append(name.lower())
            values["exportFormats"] = tuple(cleaned)

        try:
            return GenerateOptions(**values)
        except TypeError as exc:
            raise ProtocolError(str(exc)) from exc


@dataclass(frozen=True)
class GenerateRequest:
    """Reconstruct one image into one GLB inside one job workspace."""

    jobId: str
    sourcePath: str
    workspace: str
    #: Optional app-produced foreground mask. The app owns Vision segmentation;
    #: the worker just honours the result when one is supplied.
    maskPath: str | None = None
    options: GenerateOptions = field(default_factory=GenerateOptions)


@dataclass(frozen=True)
class AnalyseRequest:
    """Rate a source image without reconstructing it.

    Cheap — decode, mask, bounding box — so the app can show a suitability
    badge the moment an image is imported, rather than after the user has
    waited out a generation to discover the subject was never usable.
    """

    requestId: str
    sourcePath: str
    maskPath: str | None = None
    cropPadding: float = 0.08


@dataclass(frozen=True)
class CancelRequest:
    jobId: str


@dataclass(frozen=True)
class ShutdownRequest:
    pass


# typing.Union rather than PEP 604: this alias is evaluated at runtime, and the
# protocol/prep/mesh layers are kept importable on stock macOS Python (3.9) so
# the suite runs without provisioning a newer interpreter. The SPAR3D backend
# itself needs 3.11+; see the README.
Request = Union[GenerateRequest, AnalyseRequest, CancelRequest, ShutdownRequest]


def decode_request(line: str) -> Request:
    """Parse one inbound protocol line.

    Raises ``ProtocolError`` with a human-readable reason; the worker turns that
    into a ``malformedRequest`` message rather than dying.
    """

    try:
        raw = json.loads(line)
    except json.JSONDecodeError as exc:
        raise ProtocolError(f"invalid JSON: {exc.msg}") from exc
    if not isinstance(raw, dict):
        raise ProtocolError("message must be a JSON object")

    kind = raw.get("type")
    if kind == "generate":
        for key in ("jobId", "sourcePath", "workspace"):
            if not isinstance(raw.get(key), str) or not raw[key]:
                raise ProtocolError(f"generate requires a non-empty string '{key}'")
        mask = raw.get("maskPath")
        if mask is not None and not isinstance(mask, str):
            raise ProtocolError("maskPath must be a string when present")
        return GenerateRequest(
            jobId=raw["jobId"],
            sourcePath=raw["sourcePath"],
            workspace=raw["workspace"],
            maskPath=mask,
            options=GenerateOptions.from_dict(raw.get("options")),
        )
    if kind == "analyse":
        for key in ("requestId", "sourcePath"):
            if not isinstance(raw.get(key), str) or not raw[key]:
                raise ProtocolError(f"analyse requires a non-empty string '{key}'")
        mask = raw.get("maskPath")
        if mask is not None and not isinstance(mask, str):
            raise ProtocolError("maskPath must be a string when present")
        padding = raw.get("cropPadding", 0.08)
        if not isinstance(padding, (int, float)):
            raise ProtocolError("cropPadding must be a number")
        return AnalyseRequest(
            requestId=raw["requestId"],
            sourcePath=raw["sourcePath"],
            maskPath=mask,
            cropPadding=float(padding),
        )
    if kind == "cancel":
        if not isinstance(raw.get("jobId"), str) or not raw["jobId"]:
            raise ProtocolError("cancel requires a non-empty string 'jobId'")
        return CancelRequest(jobId=raw["jobId"])
    if kind == "shutdown":
        return ShutdownRequest()
    raise ProtocolError(f"unknown message type: {kind!r}")


# ---------------------------------------------------------------------------
# Responses (worker -> app)
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class ResultArtifacts:
    """Paths and metadata for one finished generation.

    ``glbPath`` is the canonical asset. Everything else is either an input the
    app may want to show or metadata describing what normalisation did.
    """

    glbPath: str
    #: Viewer-compatible copy for the app's 3D preview. Apple's Model I/O does
    #: not read GLB, so the preview loads this instead. Disposable.
    previewPath: str
    #: Any extra formats that were requested, keyed by format name.
    exports: dict
    preparedImagePath: str
    triangleCount: int
    vertexCount: int
    hasTexture: bool
    #: Uniform scale applied during normalisation, so a caller can recover the
    #: engine's original dimensions.
    appliedScale: float
    #: Longest edge of the asset's bounding box after normalisation.
    boundingBoxLongestEdge: float
    upAxis: str
    originConvention: str
    durationSeconds: float


def ready_message(engine: str, engine_available: bool, detail: str | None = None) -> dict:
    """First line the worker emits, so the app can stop waiting on startup."""

    return {
        "type": "ready",
        "protocolVersion": PROTOCOL_VERSION,
        "engine": engine,
        "engineAvailable": engine_available,
        "detail": detail,
    }


def progress_message(job_id: str, stage: Stage, stage_fraction: float = 0.0) -> dict:
    """Progress within ``stage``, plus the overall fraction derived from it."""

    stage_fraction = min(max(stage_fraction, 0.0), 1.0)
    completed = 0.0
    for candidate, weight in STAGE_WEIGHTS.items():
        if candidate is stage:
            break
        completed += weight
    overall = completed + STAGE_WEIGHTS[stage] * stage_fraction
    return {
        "type": "progress",
        "jobId": job_id,
        "stage": stage.value,
        "stageFraction": round(stage_fraction, 4),
        "fraction": round(min(overall, 1.0), 4),
    }


def result_message(job_id: str, artifacts: ResultArtifacts) -> dict:
    return {"type": "result", "jobId": job_id, **asdict(artifacts)}


def analysis_message(
    request_id: str,
    suitability: str,
    notes: tuple,
    had_mask: bool,
    subject_coverage: float,
    touches_edge: bool,
) -> dict:
    """How well a source image suits single-image reconstruction."""

    return {
        "type": "analysis",
        "requestId": request_id,
        "suitability": suitability,
        "notes": list(notes),
        "hadMask": had_mask,
        "subjectCoverage": round(subject_coverage, 4),
        "touchesEdge": touches_edge,
    }


def error_message(job_id: str | None, code: ErrorCode, message: str) -> dict:
    return {
        "type": "error",
        "jobId": job_id,
        "code": code.value,
        "message": message,
        "recoverable": code in RECOVERABLE_CODES,
    }
