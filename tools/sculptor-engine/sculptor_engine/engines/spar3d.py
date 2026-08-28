"""SPAR3D reconstruction backend.

Stability AI's Stable Point-Aware Reconstruction of 3D Objects from Single
Images. Chosen for V1 because it predicts a complete mesh with inferred hidden
geometry rather than a visible-surface depth map, and because its reference
implementation exports GLB and has experimental Apple Silicon MPS support.

This module never downloads weights. The Sculptor app installs them into the
shared App Group; here they are only located and loaded. See
``sculptor_engine.models``.

Upstream references:
* https://github.com/Stability-AI/stable-point-aware-3d
* https://huggingface.co/stabilityai/stable-point-aware-3d

The exact upstream call signature must be confirmed against the pinned commit
during the Phase 0 spike; see ``docs/sculptor.md`` and this tool's README.
"""

from __future__ import annotations

from pathlib import Path

from ..models import ModelInstallation, spar3d_installation
from .base import (
    Cancelled,
    CancelCheck,
    EngineUnavailable,
    InferenceFailed,
    OutOfMemory,
    ProgressCallback,
    ReconstructionEngine,
)


class SPAR3DEngine(ReconstructionEngine):
    """Runs SPAR3D locally, keeping the loaded model alive between jobs."""

    name = "spar3d"

    def __init__(
        self,
        installation: ModelInstallation | None = None,
        device: str | None = None,
        low_memory: bool = False,
        bake_resolution: int = 1024,
        remesh: str = "none",
    ) -> None:
        self._installation = installation or spar3d_installation()
        self._requested_device = device
        self._low_memory = low_memory
        self._bake_resolution = bake_resolution
        self._remesh = remesh
        self._model = None
        self._device: str | None = None

    # -- availability -------------------------------------------------------

    @property
    def is_available(self) -> bool:
        return self._installation.is_installed and _torch_is_importable()

    @property
    def unavailable_reason(self) -> str | None:
        if not self._installation.is_installed:
            return self._installation.describe_missing()
        if not _torch_is_importable():
            return (
                "PyTorch is not installed in the worker environment. "
                "Install requirements-spar3d.txt."
            )
        return None

    # -- device -------------------------------------------------------------

    def _select_device(self) -> str:
        """Pick the torch device.

        MPS is preferred on Apple Silicon. The upstream project describes that
        path as experimental and more memory-hungry than CUDA, so CPU remains a
        working fallback — slow, but correct.
        """

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

        try:
            import torch
            from spar3d.system import SPAR3D
        except ImportError as exc:
            raise EngineUnavailable(
                f"SPAR3D runtime is not installed in the worker environment: {exc}"
            ) from exc

        self._device = self._select_device()
        try:
            model = SPAR3D.from_pretrained(
                str(self._installation.directory),
                config_name="config.yaml",
                weight_name="model.safetensors",
            )
            model.eval()
            model.to(self._device)
            if self._device != "cpu":
                # Half precision roughly halves peak memory on MPS. Only used in
                # low-memory mode because it can cost fine surface detail.
                if self._low_memory:
                    model.to(torch.float16)
        except (RuntimeError, OSError) as exc:
            if _is_out_of_memory(exc):
                raise OutOfMemory(
                    f"not enough memory to load SPAR3D on {self._device}: {exc}"
                ) from exc
            raise InferenceFailed(f"could not load SPAR3D: {exc}") from exc

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

    def reconstruct(
        self,
        prepared_image: Path,
        progress: ProgressCallback,
        should_cancel: CancelCheck,
    ):
        """Reconstruct one prepared square image into a textured mesh.

        Cancellation is cooperative and lands at the boundaries either side of
        the forward pass; the pass itself is not interruptible. For an immediate
        cancel the app terminates the worker, which also reclaims device memory.
        """

        from PIL import Image

        model = self._load_model()
        if should_cancel():
            raise Cancelled("cancelled before inference")

        progress(0.05)
        with Image.open(prepared_image) as opened:
            opened.load()
            image = opened.convert("RGBA")

        try:
            import torch

            progress(0.15)
            with torch.no_grad():
                mesh, _ = model.run_image(
                    image,
                    bake_resolution=self._bake_resolution,
                    remesh=self._remesh,
                )
            progress(0.95)
        except RuntimeError as exc:
            if _is_out_of_memory(exc):
                raise OutOfMemory(
                    f"ran out of memory on {self._device} during reconstruction: {exc}"
                ) from exc
            raise InferenceFailed(f"SPAR3D inference failed: {exc}") from exc
        except Exception as exc:
            raise InferenceFailed(f"SPAR3D inference failed: {exc}") from exc

        if should_cancel():
            raise Cancelled("cancelled after inference")

        if mesh is None:
            raise InferenceFailed("SPAR3D returned no geometry")

        progress(1.0)
        return mesh


def _torch_is_importable() -> bool:
    """Whether PyTorch is present, without paying the cost of importing it."""

    import importlib.util

    return importlib.util.find_spec("torch") is not None


def _is_out_of_memory(exc: BaseException) -> bool:
    text = str(exc).lower()
    return "out of memory" in text or "can't allocate" in text or "mps_malloc" in text
