"""Reconstruction engines behind a single boundary.

SPAR3D is the V1 choice, not a permanent dependency. Everything above this
package talks to :class:`~sculptor_engine.engines.base.ReconstructionEngine`, so
a later native/Core ML engine can replace it without touching the worker, the
protocol, or the app.
"""

from .base import (
    Cancelled,
    EngineError,
    EngineUnavailable,
    InferenceFailed,
    OutOfMemory,
    ReconstructionEngine,
)

__all__ = [
    "Cancelled",
    "EngineError",
    "EngineUnavailable",
    "InferenceFailed",
    "OutOfMemory",
    "ReconstructionEngine",
    "create_engine",
]


#: Default engine. TripoSR rather than SPAR3D because its weights are ungated
#: and MIT licensed, so a build can be verified end to end without an account or
#: a licence acceptance. See ``docs/sculptor.md`` and ``triposr.py``.
DEFAULT_ENGINE = "triposr"


def create_engine(name: str = DEFAULT_ENGINE, **kwargs) -> ReconstructionEngine:
    """Instantiate an engine by name.

    Importing lazily keeps ``--help``, protocol tests, and the image/mesh layers
    usable on a machine with no PyTorch installed.
    """

    if name == "triposr":
        from .triposr import TripoSREngine

        return TripoSREngine(**kwargs)
    if name == "spar3d":
        from .spar3d import SPAR3DEngine

        return SPAR3DEngine(**kwargs)
    raise ValueError(f"unknown engine: {name!r}")
