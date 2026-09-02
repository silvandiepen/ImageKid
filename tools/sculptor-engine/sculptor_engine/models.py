"""Where reconstruction weights live, and whether they are installed.

The worker never downloads weights. The Sculptor app downloads them into the
shared App Group the same way ImageKid already installs the Best Cutout and Best
Upscale Core ML models (see ``CompanionCoreMLModels.swift``), and this module
only answers "are they there, and where?".

Layout, matching the "Model storage" section of ``docs/sculptor.md``::

    group.com.hakobs.imagekid/
    └── Models/
        └── Sculptor/
            └── SPAR3D/<version>/
                ├── config.yaml
                └── model.safetensors

``SCULPTOR_MODELS_DIR`` overrides the search root. The app should set it to the
sandbox-authorised container path it already holds rather than making the worker
guess; the fallbacks exist for command-line use and the test suite.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

APP_GROUP_IDENTIFIER = "group.com.hakobs.imagekid"

#: Weight version this worker expects. Bump together with the app's download
#: manifest so an old install is treated as missing rather than loaded blindly.
SPAR3D_VERSION = "v1"

#: Files that must all be present for a model directory to count as installed.
SPAR3D_REQUIRED_FILES = ("config.yaml", "model.safetensors")

TRIPOSR_VERSION = "v1"

TRIPOSR_REQUIRED_FILES = ("config.yaml", "model.ckpt")


def models_root() -> Path:
    """Root directory holding every Sculptor model version."""

    override = os.environ.get("SCULPTOR_MODELS_DIR")
    if override:
        return Path(override).expanduser()

    group_container = (
        Path.home() / "Library" / "Group Containers" / APP_GROUP_IDENTIFIER
    )
    if group_container.is_dir():
        return group_container / "Models" / "Sculptor"

    return (
        Path.home()
        / "Library"
        / "Application Support"
        / "ImageKid"
        / "Models"
        / "Sculptor"
    )


@dataclass(frozen=True)
class ModelInstallation:
    """Resolved location and installation state of one model version."""

    name: str
    version: str
    directory: Path
    missing_files: tuple[str, ...]

    @property
    def is_installed(self) -> bool:
        return not self.missing_files

    def describe_missing(self) -> str:
        """Message for a ``modelNotInstalled`` error the app can surface."""

        if self.is_installed:
            return ""
        return (
            f"{self.name} {self.version} is not installed. "
            f"Expected {', '.join(self.missing_files)} in {self.directory}. "
            "Install the model from Sculptor before generating."
        )


def _installation(
    name: str, version: str, required: tuple, root: Path | None = None
) -> ModelInstallation:
    directory = (root or models_root()) / name / version
    missing = tuple(f for f in required if not (directory / f).is_file())
    return ModelInstallation(
        name=name, version=version, directory=directory, missing_files=missing
    )


def spar3d_installation(root: Path | None = None) -> ModelInstallation:
    """Locate the SPAR3D weights and report which required files are absent."""

    return _installation("SPAR3D", SPAR3D_VERSION, SPAR3D_REQUIRED_FILES, root)


def triposr_installation(root: Path | None = None) -> ModelInstallation:
    """Locate the TripoSR weights and report which required files are absent."""

    return _installation("TripoSR", TRIPOSR_VERSION, TRIPOSR_REQUIRED_FILES, root)
