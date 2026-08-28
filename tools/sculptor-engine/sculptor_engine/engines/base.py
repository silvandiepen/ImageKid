"""The engine boundary.

An engine turns one prepared square image into geometry. It does not download
weights, write user-facing files, or know about the protocol; the worker owns
all three.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from pathlib import Path
from typing import Callable

#: Called with a 0..1 fraction of the reconstruction stage.
ProgressCallback = Callable[[float], None]

#: Polled between phases; returning ``True`` asks the engine to stop.
CancelCheck = Callable[[], bool]


class EngineError(Exception):
    """Base class for reconstruction failures."""


class EngineUnavailable(EngineError):
    """The engine cannot run — most often because weights are not installed.

    This is recoverable: the app downloads the model, then the user retries.
    """


class InferenceFailed(EngineError):
    """The engine ran and failed."""


class OutOfMemory(EngineError):
    """The device ran out of memory during reconstruction."""


class Cancelled(EngineError):
    """The job was cancelled."""


class ReconstructionEngine(ABC):
    """Single-image to complete-3D-object reconstruction.

    Implementations must produce a *complete* object with inferred hidden sides,
    not a depth surface. That is a product requirement, not an optimisation:
    see "Reconstruction principle" in ``docs/sculptor.md``.
    """

    #: Stable identifier reported in the ``ready`` message.
    name: str = "unknown"

    @property
    @abstractmethod
    def is_available(self) -> bool:
        """Whether the engine could run right now. Cheap; must not load weights."""

    @property
    @abstractmethod
    def unavailable_reason(self) -> str | None:
        """Why :attr:`is_available` is ``False``, or ``None`` when it is ``True``."""

    @abstractmethod
    def reconstruct(
        self,
        prepared_image: Path,
        progress: ProgressCallback,
        should_cancel: CancelCheck,
    ):
        """Reconstruct ``prepared_image`` and return a ``trimesh`` scene or mesh.

        Raises :class:`EngineUnavailable`, :class:`InferenceFailed`,
        :class:`OutOfMemory`, or :class:`Cancelled`.
        """
