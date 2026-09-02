"""Fusing several single-image reconstructions into one model.

The engine reconstructs from one image, so everything facing away from that
camera is invented rather than observed. A profile photograph of an animal
produces a model with one eye, because nothing in the input says there is a
second one.

Given several views, each reconstruction knows something the others do not.
Fusing them means keeping what each view contributes while letting the others
correct what it guessed.

Two rules, and the second is what makes this work:

*Every view adds.* A point is solid if any view reconstructed it solid. A view
looking straight down the length of a subject cannot tell how long it is, so it
must not be able to veto the view that could.

*Every outline vetoes.* A point is removed if it falls outside any view's
outline. An outline is measured — it is the input image's own silhouette — while
depth is inferred, so the outlines are the part worth trusting absolutely.

The result is re-extracted from one volume rather than stitched from surfaces:
joining meshes leaves seams and holes exactly where they meet, which is the
visible middle of the object, while one surface out of one volume is watertight
by construction.

This builds a model out of what was seen. It does not make the engine
multi-view: a network trained to consume several images at once would agree
with itself across views instead of being made to agree afterwards, and the
engine boundary is where that would go.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import trimesh

#: Edge length of the cubic blend grid. High enough to keep the detail that
#: survives smoothing and decimation, low enough that voxelising a handful of
#: meshes stays a couple of seconds.
GRID = 160

#: Points sampled to rasterise a view's outline. Generous: a sparse sampling
#: leaves pinholes, and since the outline is a veto, a hole in it deletes real
#: geometry.
SILHOUETTE_SAMPLES = 200_000

#: Fraction of the object's size left clear around the grid, so the surface is
#: never clipped by the edge of the volume.
PADDING = 0.06

#: Where the camera stands in the frame the engine reconstructs into.
#:
#: Not a convention anyone declares — measured. Silhouettes of real TripoSR
#: reconstructions were projected from each axis and compared against the
#: prepared input image; +X matched every time and by a wide margin (0.85, 0.89
#: and 0.79 IoU against 0.55, 0.68 and 0.36 for its opposite). Get this wrong
#: and fusion is worse than useless: every view's outline lands on the side it
#: invented rather than the side it saw.
CAMERA_AXIS = np.array([1.0, 0.0, 0.0])


@dataclass(frozen=True)
class View:
    """One reconstruction, and where its camera was.

    ``yaw`` is degrees turned around the upright axis: 0 is whatever the first
    view saw, 90 a quarter turn, 180 the far side.

    ``pitch`` lifts the camera off the horizon: 90 is directly overhead, -90
    directly underneath. A turnaround sheet's top and bottom panels are these,
    and they are not reachable by any yaw — which is why treating a six-view
    sheet as six quarter turns destroys it.

    For a top or bottom view the yaw no longer moves the camera; it rolls the
    picture instead, and still matters, because it says which way round the
    object was lying in the frame.
    """

    mesh: trimesh.Trimesh
    yaw: float
    pitch: float = 0.0

    @property
    def orientation(self) -> np.ndarray:
        """Rotation carrying this reconstruction back into the world frame."""

        return turn(self.yaw) @ tilt(self.pitch)

    @property
    def direction(self) -> np.ndarray:
        """Unit vector from the object toward this view's camera."""

        return self.orientation[:3, :3] @ CAMERA_AXIS


def turn(yaw: float) -> np.ndarray:
    """Rotation about the upright axis by ``yaw`` degrees."""

    return trimesh.transformations.rotation_matrix(np.radians(yaw), [0, 1, 0])


def tilt(pitch: float) -> np.ndarray:
    """Rotation lifting the camera off the horizon by ``pitch`` degrees.

    About the axis perpendicular to both the camera axis and upright, which for
    a camera on +X and up on +Y is Z.
    """

    return trimesh.transformations.rotation_matrix(np.radians(pitch), [0, 0, 1])


def camera_direction(yaw: float, pitch: float = 0.0) -> np.ndarray:
    """Unit vector from the object toward the camera of a view at this angle."""

    return (turn(yaw) @ tilt(pitch))[:3, :3] @ CAMERA_AXIS


#: The six views a turnaround sheet names, as (yaw, pitch).
#:
#: Fixed by two conventions. The object faces its front camera, so its forward
#: direction is where that camera stands; its right-hand side is then a quarter
#: turn from there, the way anyone facing forward has a right hand.
#:
#: Top and bottom need one more thing settled — which way round the object lies
#: in the frame — and there the convention is the common one, that the overhead
#: panel is the side view tipped back, so the subject faces the same way in both.
#: A sheet that does it differently will come out rotated in plan, which is
#: exactly why the assignment is shown for checking rather than trusted.
NAMED_VIEWS: dict[str, tuple[float, float]] = {
    "front": (0.0, 0.0),
    "right": (270.0, 0.0),
    "back": (180.0, 0.0),
    "left": (90.0, 0.0),
    "top": (90.0, 90.0),
    "bottom": (90.0, -90.0),
}

#: What a sheet is likely to have written under each panel.
VIEW_SYNONYMS: dict[str, str] = {
    "front": "front",
    "front view": "front",
    "back": "back",
    "rear": "back",
    "behind": "back",
    "right": "right",
    "right side": "right",
    "side": "right",
    "left": "left",
    "left side": "left",
    "top": "top",
    "above": "top",
    "plan": "top",
    "bottom": "bottom",
    "below": "bottom",
    "underside": "bottom",
}


def named_view(label: str) -> tuple[float, float] | None:
    """Angles for a panel label, or ``None`` if it names no view we know."""

    cleaned = " ".join(label.lower().split()).strip(".:-–—")
    name = VIEW_SYNONYMS.get(cleaned)
    return NAMED_VIEWS[name] if name else None


#: How a sheet's panels are most often ordered, read left to right and top to
#: bottom. Not a guess to be trusted — a shortlist to be measured. Each is tried
#: and scored against the panels' own pictures, and the reading that explains
#: them best is the one used.
LAYOUTS: dict[int, tuple[tuple[str, ...], ...]] = {
    2: (("front", "right"), ("front", "back")),
    3: (("front", "right", "back"), ("front", "left", "back")),
    4: (
        ("front", "right", "back", "left"),
        ("front", "left", "back", "right"),
    ),
    5: (("front", "right", "back", "left", "top"),),
    6: (
        ("front", "right", "back", "left", "top", "bottom"),
        ("front", "back", "left", "right", "top", "bottom"),
        ("front", "right", "back", "left", "bottom", "top"),
    ),
}


def candidate_layouts(count: int) -> tuple[tuple[tuple[float, float], ...], ...]:
    """Readings of a ``count``-panel sheet worth trying, as angles.

    A sheet does not say which panel is which, and it cannot be worked out from
    the geometry — two attempts at that failed, and both are recorded in the
    documentation. What can be done is to try the handful of orders sheets are
    actually laid out in and let the pictures decide.

    Raises ``UnknownAngles`` when there is no plausible reading, rather than
    inventing one: a panel placed wrongly does not merely fail to help, it
    carves away what the correctly-placed panels got right.
    """

    readings = LAYOUTS.get(count)
    if not readings:
        raise UnknownAngles(
            f"no known way to read a sheet of {count} panels; "
            f"expected {', '.join(str(n) for n in sorted(LAYOUTS))}"
        )
    return tuple(
        tuple(NAMED_VIEWS[name] for name in reading) for reading in readings
    )


class UnknownAngles(ValueError):
    """Nobody said where the cameras were, and it cannot be guessed.

    Distinct from a caller stating the wrong number of angles, which is a
    mistake worth reporting. This one means the caller said nothing and there
    was nothing to infer — a case to fall back from, not to fail on.
    """


def as_mesh(geometry: object) -> trimesh.Trimesh:
    """One mesh from whatever the engine returned.

    Fusion works on a single surface, and an engine is free to hand back a
    scene. Parts are concatenated rather than picked between, so nothing is
    silently dropped before the blend.
    """

    if isinstance(geometry, trimesh.Trimesh):
        return geometry
    if isinstance(geometry, trimesh.Scene):
        parts = [
            part
            for part in geometry.geometry.values()
            if isinstance(part, trimesh.Trimesh) and len(part.faces)
        ]
        if not parts:
            raise ValueError("view has no mesh geometry to fuse")
        return parts[0] if len(parts) == 1 else trimesh.util.concatenate(parts)
    raise ValueError(f"cannot fuse geometry of type {type(geometry).__name__}")


def align(views: list[View]) -> list[trimesh.Trimesh]:
    """Put every reconstruction into the first view's frame, at one size.

    Two steps, both necessary.

    The declared yaw turns each mesh back to where its camera was; a
    reconstruction always comes back facing its own camera, so a back view
    arrives facing forward.

    Then the sizes are reconciled. Each reconstruction is normalised to fill its
    own box, so a long subject seen end-on comes back the same size as the same
    subject seen side-on, and in a shared frame they disagree about how big the
    object is. Height is the one dimension every view of an upright object
    shares, so height is what they are reconciled by. Measured on a known
    object, this is the difference between fusion beating the best single view
    (0.69 against 0.66 IoU) and losing badly to it (0.42).

    Deliberately no ICP. Refining the fit numerically sounds strictly better and
    is not: it fits every view onto whichever view happens to be first, and when
    that one is the least informative — the head-on view that came back a
    blob — it drags the good views down to it. Measured, it cost the best view
    a third of its accuracy (0.66 to 0.46).
    """

    if not views:
        return []

    reference = views[0].mesh.copy()
    reference.apply_transform(views[0].orientation)
    aligned = [reference]
    centre = reference.bounds.mean(axis=0)

    for view in views[1:]:
        mesh = view.mesh.copy()
        mesh.apply_transform(view.orientation)

        axis = _shared_axis(view.direction, views[0].direction)
        theirs = _extent_along(reference, axis)
        ours = _extent_along(mesh, axis)
        if ours > 1e-9 and theirs > 1e-9:
            mesh.apply_scale(theirs / ours)
        mesh.apply_translation(centre - mesh.bounds.mean(axis=0))

        aligned.append(mesh)

    return aligned


def _shared_axis(direction: np.ndarray, reference: np.ndarray) -> np.ndarray:
    """A world axis both cameras measured rather than inferred.

    A camera measures the two axes across its picture and infers the one along
    its line of sight. The axis perpendicular to both cameras is therefore
    across both pictures, and is the only one they can be compared on.

    For two views around the horizon that is the upright axis — the shared
    height. For a side view and a view from overhead it is neither camera's
    obvious choice, and using height there would scale by the very depth the
    overhead view had to invent.

    Cameras facing each other share a whole plane rather than one axis; upright
    is the natural pick, and it is what two opposite views of a standing object
    agree on best.
    """

    axis = np.cross(direction, reference)
    length = np.linalg.norm(axis)
    if length < 1e-6:
        return np.array([0.0, 1.0, 0.0])
    return axis / length


def _extent_along(mesh: trimesh.Trimesh, axis: np.ndarray) -> float:
    """How far a mesh reaches along an arbitrary direction."""

    projected = np.asarray(mesh.vertices) @ axis
    return float(projected.max() - projected.min())


def _grid_bounds(meshes: list[trimesh.Trimesh]) -> np.ndarray:
    """A padded cube containing every mesh.

    Cubic so one pitch serves all three axes, which is what voxelising wants.
    """

    corners = np.array([mesh.bounds for mesh in meshes]).reshape(-1, 3)
    low, high = corners.min(axis=0), corners.max(axis=0)
    centre = (low + high) / 2.0
    half = (high - low).max() / 2.0 * (1.0 + PADDING)
    return np.array([centre - half, centre + half])


def _occupancy(mesh: trimesh.Trimesh, bounds: np.ndarray, grid: int) -> np.ndarray:
    """Sample a mesh into a solid occupancy grid over ``bounds``.

    Surface voxelisation plus a hole fill, rather than testing whether each of
    four million grid points falls inside the mesh: the same answer in seconds
    instead of minutes.
    """

    pitch = float((bounds[1][0] - bounds[0][0]) / (grid - 1))
    volume = np.zeros((grid, grid, grid), dtype=bool)

    try:
        voxels = mesh.voxelized(pitch=pitch).fill()
    except Exception:
        return volume

    matrix = np.asarray(voxels.matrix, dtype=bool)
    origin = np.asarray(voxels.transform)[:3, 3]
    offset = np.rint((origin - bounds[0]) / pitch).astype(int)

    # Clip rather than assume it fits: a rescaled view can reach slightly past
    # the bounds the grid was sized from.
    source = [slice(None)] * 3
    target = [slice(None)] * 3
    for axis in range(3):
        start = int(offset[axis])
        low_cut = max(-start, 0)
        high_cut = max(start + matrix.shape[axis] - grid, 0)
        length = matrix.shape[axis] - low_cut - high_cut
        if length <= 0:
            return volume
        source[axis] = slice(low_cut, low_cut + length)
        target[axis] = slice(start + low_cut, start + low_cut + length)

    volume[tuple(target)] = matrix[tuple(source)]
    return volume


def _screen_axes(direction: np.ndarray) -> np.ndarray:
    """The two axes a camera looking from ``direction`` projects onto.

    Upright is the natural reference for "which way is up in the picture", and
    it fails for exactly the cameras that matter most here: one looking straight
    down has no upright component to cross against, and the result is a zero
    vector and a picture of stripes. Those cameras take their reference from the
    forward axis instead, which is the convention a plan view is drawn with —
    the front of the object toward the top of the page.
    """

    forward = np.asarray(direction, dtype=float)
    forward = forward / np.linalg.norm(forward)

    up = np.array([0.0, 1.0, 0.0])
    if abs(float(forward @ up)) > 0.999:
        up = np.array([0.0, 0.0, 1.0])

    right = np.cross(up, forward)
    right /= np.linalg.norm(right)
    # Re-square the pair, since the reference up is only approximately
    # perpendicular to the view once it has been swapped.
    return np.stack([right, np.cross(forward, right)])


def _silhouette(
    mesh: trimesh.Trimesh, direction: np.ndarray, bounds: np.ndarray, grid: int
) -> np.ndarray:
    """Which grid points fall inside this view's outline.

    A reconstruction's outline is the part of it that was measured: it is the
    input image's own silhouette, which the engine matched closely. Its depth,
    by contrast, is inferred — a subject photographed end-on comes back a blob
    because nothing in that picture says how long it is.

    So the outline constrains and the depth does not. Intersecting the outlines
    of several views gives a visual hull, and that is what lets a side view cut
    a front view's blob down to the right length.
    """

    from scipy.ndimage import binary_closing, binary_fill_holes

    axes = _screen_axes(direction)
    low, high = bounds[0], bounds[1]
    span = float((high - low).max())
    origin = axes @ (low + high) / 2.0

    def to_pixels(points: np.ndarray) -> np.ndarray:
        return np.rint((points - origin) / span * grid + grid / 2.0).astype(int)

    projected = to_pixels(np.asarray(mesh.sample(SILHOUETTE_SAMPLES)) @ axes.T)
    inside = ((projected >= 0) & (projected < grid)).all(axis=1)

    outline = np.zeros((grid, grid), dtype=bool)
    outline[projected[inside, 0], projected[inside, 1]] = True
    # Sampling leaves pinholes; closing and filling turn a dotted scatter into
    # the solid region it stands for.
    outline = binary_fill_holes(binary_closing(outline, np.ones((3, 3))))

    axis = [np.linspace(low[i], high[i], grid) for i in range(3)]
    coordinates = np.stack(np.meshgrid(*axis, indexing="ij"), axis=-1)
    cells = np.clip(to_pixels(coordinates @ axes.T), 0, grid - 1)
    return outline[cells[..., 0], cells[..., 1]]


#: Resolution at which an outline is compared with a picture. Small on purpose:
#: this is a question about shape, not detail, and a coarse grid is forgiving of
#: the pixel or two of slop in fitting one to the other.
OUTLINE_SIZE = 128


def _fit(mask: np.ndarray, size: int) -> np.ndarray:
    """Crop a silhouette to its content, scale it, and centre it.

    Both sides of the comparison go through this, which is the only way the
    comparison means anything. Fitting them differently is not a subtle error:
    an early version had the projection transposed against the picture and
    scored a reconstruction 0.43 against the very image it was built from,
    where the true figure was 0.96 — a broken measurement that looked like a
    broken model.
    """

    rows, columns = np.where(mask)
    if not len(rows):
        return np.zeros((size, size), dtype=bool)

    cropped = mask[rows.min() : rows.max() + 1, columns.min() : columns.max() + 1]
    from PIL import Image as _Image

    picture = _Image.fromarray(cropped.astype(np.uint8) * 255)
    scale = (size * 0.9) / max(picture.size)
    resized = picture.resize(
        (max(int(picture.width * scale), 1), max(int(picture.height * scale), 1)),
        _Image.Resampling.NEAREST,
    )
    canvas = _Image.new("L", (size, size), 0)
    canvas.paste(resized, ((size - resized.width) // 2, (size - resized.height) // 2))
    return np.asarray(canvas) > 127


def projected_outline(
    mesh: trimesh.Trimesh, direction: np.ndarray, size: int = OUTLINE_SIZE
) -> np.ndarray:
    """The mesh's outline as a camera looking from ``direction`` would see it."""

    from scipy.ndimage import binary_closing, binary_fill_holes

    axes = _screen_axes(np.asarray(direction, dtype=float))
    points = np.asarray(mesh.sample(SILHOUETTE_SAMPLES)) @ axes.T

    low, high = points.min(axis=0), points.max(axis=0)
    span = float((high - low).max()) or 1.0
    scale = (size * 0.9) / span
    centre = (low + high) / 2.0

    across = np.rint((points[:, 0] - centre[0]) * scale + size / 2.0)
    # Screen up becomes a row index counted downward.
    down = np.rint(size / 2.0 - (points[:, 1] - centre[1]) * scale)
    across = np.clip(across, 0, size - 1).astype(int)
    down = np.clip(down, 0, size - 1).astype(int)

    grid = np.zeros((size, size), dtype=bool)
    grid[down, across] = True
    return _fit(binary_fill_holes(binary_closing(grid, np.ones((3, 3)))), size)


def picture_outline(alpha: np.ndarray, size: int = OUTLINE_SIZE) -> np.ndarray:
    """A prepared input image's own silhouette, fitted the same way."""

    return _fit(np.asarray(alpha, dtype=bool), size)


def agreement(
    mesh: trimesh.Trimesh, views: list[View], pictures: list[np.ndarray]
) -> list[float]:
    """How far a model's outline matches each view's own picture.

    The only check available that is not circular. Asking the views whether they
    agree with each other cannot work — a view placed at the wrong angle
    corrupts the shape its neighbours are judged against, so the damage lands on
    them rather than on the culprit, and measured on a real subject the correct
    placement scored *worse* than every wrong one. The input pictures are
    outside that argument. They are what was actually photographed.
    """

    scores = []
    for view, picture in zip(views, pictures):
        outline = projected_outline(mesh, view.direction)
        expected = picture_outline(picture)
        union = (outline | expected).sum()
        scores.append(float((outline & expected).sum() / union) if union else 0.0)
    return scores


def blend(
    views: list[View], grid: int = GRID
) -> tuple[np.ndarray, np.ndarray, list[trimesh.Trimesh]]:
    """Occupancy over a shared grid, with the aligned meshes.

    Every view adds what it reconstructed; every view's outline takes away what
    falls outside it. Kept separate from :func:`fuse` so the volume can be
    inspected and tested without a surface extractor.
    """

    if len(views) < 2:
        raise ValueError("fusing needs at least two views")

    meshes = align(views)
    bounds = _grid_bounds(meshes)

    solid = np.zeros((grid, grid, grid), dtype=bool)
    hull = np.ones((grid, grid, grid), dtype=bool)

    for mesh, view in zip(meshes, views):
        solid |= _occupancy(mesh, bounds, grid)
        hull &= _silhouette(mesh, view.direction, bounds, grid)

    return (solid & hull).astype(np.float32), bounds, meshes


def fuse(views: list[View], grid: int = GRID) -> trimesh.Trimesh:
    """Blend several reconstructions into one surface.

    Raises ``ValueError`` if there are not two views to fuse, or if the blend
    leaves nothing solid.
    """

    blended, bounds, meshes = blend(views, grid=grid)

    import torch
    from torchmcubes import marching_cubes

    vertices, faces = marching_cubes(
        torch.from_numpy(np.ascontiguousarray(blended)), 0.5
    )
    faces = faces.numpy()
    if not len(faces):
        raise ValueError("fusion produced no surface")

    # torchmcubes reports vertices with the array axes reversed.
    vertices = vertices.numpy()[:, ::-1]

    # Grid indices back into the object's own coordinates.
    span = bounds[1] - bounds[0]
    vertices = bounds[0] + vertices / (grid - 1.0) * span

    fused = trimesh.Trimesh(vertices=vertices, faces=faces, process=True)
    fused.fix_normals()
    _paint(fused, meshes, views)
    return fused


def _paint(
    fused: trimesh.Trimesh, meshes: list[trimesh.Trimesh], views: list[View]
) -> None:
    """Colour the fused surface from whichever view faced each part.

    Geometry is decided by all the views together; colour is not, because a
    view's guess at the colour of the side it could not see is not worth
    averaging in.
    """

    from scipy.spatial import cKDTree

    points = np.asarray(fused.vertices)
    if not len(points):
        return

    offsets = points - points.mean(axis=0)
    lengths = np.linalg.norm(offsets, axis=1, keepdims=True)
    lengths[lengths == 0] = 1.0
    directions = offsets / lengths

    best = np.full(len(points), -np.inf)
    colours = np.zeros((len(points), 4), dtype=np.uint8)
    painted = False

    for mesh, view in zip(meshes, views):
        source = getattr(mesh.visual, "vertex_colors", None)
        if source is None or len(source) != len(mesh.vertices):
            continue
        score = directions @ view.direction
        chosen = score > best
        if not chosen.any():
            continue
        _, index = cKDTree(np.asarray(mesh.vertices)).query(points[chosen], k=1)
        colours[chosen] = np.asarray(source)[index]
        best[chosen] = score[chosen]
        painted = True

    if painted:
        fused.visual = trimesh.visual.ColorVisuals(mesh=fused, vertex_colors=colours)
