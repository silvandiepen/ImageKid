"""TripoSR reconstruction backend.

TripoSR (Stability AI + Tripo AI) reconstructs a complete 3D object from a
single image via a triplane NeRF, then extracts a mesh with marching cubes. It
predicts geometry for sides the source image never shows, which is the product
requirement Sculptor is built around.

Chosen as the first *verifiable* engine because it is **MIT licensed and not
gated**: weights download without an account or a licence acceptance, and the
licence carries none of the revenue thresholds the Stability Community License
puts on SPAR3D. SPAR3D remains available in ``spar3d.py`` for anyone who accepts
its terms and supplies a token.

This module never downloads weights; the app installs them. See
``sculptor_engine.models``.

Upstream: https://github.com/VAST-AI-Research/TripoSR (MIT)
Weights:  https://huggingface.co/stabilityai/TripoSR (MIT)
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

from ..models import ModelInstallation, triposr_installation
from .base import (
    Cancelled,
    CancelCheck,
    EngineUnavailable,
    InferenceFailed,
    OutOfMemory,
    ProgressCallback,
    ReconstructionEngine,
)

#: TripoSR composites the subject over mid grey rather than using an alpha
#: channel. This is its expected input convention, not a stylistic choice.
BACKGROUND_GREY = 0.5


def triposr_source_path() -> Path:
    """Where the vendored TripoSR source lives.

    Fetched by ``scripts/install_triposr.sh`` rather than committed, matching how
    ``tools/coreml-conversion`` treats its third-party dependencies.
    """

    override = os.environ.get("SCULPTOR_TRIPOSR_PATH")
    if override:
        return Path(override).expanduser()
    return Path(__file__).resolve().parent.parent.parent / "vendor" / "TripoSR"


class TripoSREngine(ReconstructionEngine):
    """Runs TripoSR locally, keeping the loaded model alive between jobs."""

    name = "triposr"

    def __init__(
        self,
        installation: ModelInstallation | None = None,
        device: str | None = None,
        low_memory: bool = False,
        marching_cubes_resolution: int = 256,
        #: Density level for the isosurface. TripoSR's own default.
        threshold: float = 25.0,
        #: Triplane query batch. Lower trades speed for peak memory.
        chunk_size: int = 8192,
    ) -> None:
        self._installation = installation or triposr_installation()
        self._requested_device = device
        self._low_memory = low_memory
        self._resolution = marching_cubes_resolution
        self._threshold = threshold
        self._chunk_size = 4096 if low_memory else chunk_size
        self._model = None
        self._device: str | None = None

    # -- availability -------------------------------------------------------

    @property
    def is_available(self) -> bool:
        return self.unavailable_reason is None

    @property
    def unavailable_reason(self) -> str | None:
        if not self._installation.is_installed:
            return self._installation.describe_missing()
        source = triposr_source_path()
        if not (source / "tsr" / "system.py").is_file():
            return (
                f"TripoSR source is not present at {source}. "
                "Run scripts/install_triposr.sh."
            )
        import importlib.util

        for module in ("torch", "omegaconf", "einops", "torchmcubes"):
            if importlib.util.find_spec(module) is None:
                return (
                    f"{module} is not installed in the worker environment. "
                    "Install requirements-triposr.txt."
                )
        return None

    # -- device -------------------------------------------------------------

    def _select_device(self) -> str:
        import torch

        if self._requested_device:
            return self._requested_device
        if torch.backends.mps.is_available() and torch.backends.mps.is_built():
            return "mps"
        return "cpu"

    # -- model --------------------------------------------------------------

    def _load_model(self):
        if self._model is not None:
            return self._model

        reason = self.unavailable_reason
        if reason is not None:
            raise EngineUnavailable(reason)

        source = str(triposr_source_path())
        if source not in sys.path:
            sys.path.insert(0, source)

        try:
            from tsr.system import TSR
        except ImportError as exc:
            raise EngineUnavailable(
                f"could not import the TripoSR runtime from {source}: {exc}"
            ) from exc

        self._device = self._select_device()
        try:
            model = TSR.from_pretrained(
                str(self._installation.directory),
                config_name="config.yaml",
                weight_name="model.ckpt",
            )
            model.renderer.set_chunk_size(self._chunk_size)
            model.to(self._device)
        except (RuntimeError, OSError, ValueError) as exc:
            if _is_out_of_memory(exc):
                raise OutOfMemory(
                    f"not enough memory to load TripoSR on {self._device}: {exc}"
                ) from exc
            raise InferenceFailed(f"could not load TripoSR: {exc}") from exc

        self._model = model
        return model

    def unload(self) -> None:
        """Drop the model and release device memory."""

        self._model = None
        try:
            import torch

            if self._device == "mps":
                torch.mps.empty_cache()
        except (ImportError, AttributeError):
            pass

    # -- reconstruction -----------------------------------------------------

    def _to_engine_input(self, prepared_image: Path):
        """Convert the prepared RGBA square into TripoSR's expected input.

        The worker's prepared image is engine-neutral: a subject on transparency.
        TripoSR wants the subject composited over mid grey with no alpha, so the
        conversion belongs here rather than in shared preparation.
        """

        import numpy as np
        from PIL import Image

        with Image.open(prepared_image) as opened:
            opened.load()
            rgba = opened.convert("RGBA")

        data = np.asarray(rgba).astype(np.float32) / 255.0
        rgb, alpha = data[:, :, :3], data[:, :, 3:4]
        composited = rgb * alpha + (1.0 - alpha) * BACKGROUND_GREY
        return Image.fromarray((composited * 255.0).astype(np.uint8))

    def reconstruct(
        self,
        prepared_image: Path,
        progress: ProgressCallback,
        should_cancel: CancelCheck,
    ):
        """Reconstruct one prepared square image into a coloured mesh.

        Cancellation is cooperative and lands either side of the forward pass and
        the isosurface extraction; neither is interruptible internally. For an
        immediate stop the app terminates the worker, which also frees device
        memory.
        """

        import torch

        model = self._load_model()
        if should_cancel():
            raise Cancelled("cancelled before inference")

        progress(0.05)
        image = self._to_engine_input(prepared_image)

        try:
            progress(0.15)
            with torch.no_grad():
                # Triplane scene code: this is where hidden-side geometry is
                # predicted, so it is the bulk of the reconstruction stage.
                scene_codes = model([image], device=self._device)
            progress(0.55)

            if should_cancel():
                raise Cancelled("cancelled after inference")

            # Marching cubes runs through a CPU extension, so the density grid
            # is pulled off the GPU here regardless of the inference device.
            meshes = model.extract_mesh(
                scene_codes,
                True,  # has_vertex_color
                resolution=self._resolution,
                threshold=self._threshold,
            )
            progress(0.95)
        except Cancelled:
            raise
        except (RuntimeError, MemoryError) as exc:
            if _is_out_of_memory(exc):
                raise OutOfMemory(
                    f"ran out of memory on {self._device} during reconstruction: {exc}"
                ) from exc
            raise InferenceFailed(f"TripoSR inference failed: {exc}") from exc
        except Exception as exc:
            raise InferenceFailed(f"TripoSR inference failed: {exc}") from exc

        if not meshes:
            raise InferenceFailed("TripoSR returned no geometry")

        mesh = meshes[0]
        if mesh is None or len(getattr(mesh, "faces", ())) == 0:
            raise InferenceFailed(
                "TripoSR produced an empty mesh; the subject may not have been "
                "separated from its background"
            )

        progress(1.0)
        return mesh


def _is_out_of_memory(exc: BaseException) -> bool:
    text = str(exc).lower()
    return (
        "out of memory" in text
        or "can't allocate" in text
        or "mps_malloc" in text
        or "cannot allocate" in text
    )
