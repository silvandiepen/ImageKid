"""Per-job working directories.

Every generation is a job with an isolated workspace. The app owns the parent
directory (it holds the sandbox authorisation); the worker only creates the
subdirectories it needs inside it.

The export rule from ``docs/sculptor.md`` is enforced here: artifacts are written
to a temporary name inside the workspace and moved into place atomically, so a
failed generation can never leave a half-written GLB behind.
"""

from __future__ import annotations

import os
import shutil
from dataclasses import dataclass
from pathlib import Path

#: Refuse to start a job with less headroom than this. SPAR3D intermediates plus
#: a textured GLB comfortably fit; the check exists to fail early and clearly
#: rather than partway through inference.
MINIMUM_FREE_BYTES = 2 * 1024 * 1024 * 1024


class WorkspaceError(Exception):
    """The job workspace could not be prepared."""


class InsufficientDiskSpace(WorkspaceError):
    """Not enough free space on the volume holding the workspace."""


@dataclass(frozen=True)
class JobWorkspace:
    """Directories for one generation."""

    root: Path

    @property
    def input_dir(self) -> Path:
        return self.root / "input"

    @property
    def temp_dir(self) -> Path:
        return self.root / "temp"

    @property
    def output_dir(self) -> Path:
        return self.root / "output"

    @property
    def prepared_image_path(self) -> Path:
        """Square, subject-cropped image handed to the reconstruction engine."""

        return self.input_dir / "prepared.png"

    @property
    def glb_path(self) -> Path:
        """Canonical generated asset."""

        return self.output_dir / "model.glb"

    @property
    def preview_path(self) -> Path:
        """Viewer-compatible copy for the app's 3D preview."""

        return self.output_dir / "preview.ply"

    def free_bytes(self) -> int:
        return shutil.disk_usage(self.root).free

    def commit(self, temporary: Path, destination: Path) -> Path:
        """Move a finished artifact into place atomically.

        ``os.replace`` is atomic within a filesystem, and both paths live inside
        the workspace, so a crash mid-write leaves the temporary file rather
        than a truncated destination.
        """

        destination.parent.mkdir(parents=True, exist_ok=True)
        os.replace(temporary, destination)
        return destination


def prepare(root: str | Path) -> JobWorkspace:
    """Create the job directory structure and check for room to work."""

    workspace = JobWorkspace(Path(root).expanduser())
    try:
        for directory in (
            workspace.root,
            workspace.input_dir,
            workspace.temp_dir,
            workspace.output_dir,
        ):
            directory.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        raise WorkspaceError(f"could not create job workspace: {exc}") from exc

    free = workspace.free_bytes()
    if free < MINIMUM_FREE_BYTES:
        raise InsufficientDiskSpace(
            f"{free // (1024 * 1024)} MB free where "
            f"{MINIMUM_FREE_BYTES // (1024 * 1024)} MB is required"
        )
    return workspace
