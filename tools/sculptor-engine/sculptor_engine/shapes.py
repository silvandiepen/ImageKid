"""Rebuilding a solid as a handful of spheres and cubes.

A stylised subject is an assembly. Whoever modelled the cow started from a
barrel, a ball, four cylinders and two cones, and the look comes from that:
every part is a clean solid and the joins are the only complicated thing about
it.

Smoothing a surface cannot arrive there from the other side. It treats the
model as one continuous thing, so it rounds a horn and a flank by the same
rule, and the harder it works the more of the horn it removes.

The way in is the largest thing that fits inside. The biggest sphere that fits
in a cow is its barrel; take that away and the biggest that fits in what is
left is its head; then its legs, its ears, its muzzle. Each is placed where the
solid is deepest, which is the middle of a part, and sized by how deep it is
there, which is the part's thickness. Nothing has to recognise a leg for this
to put a sphere in one.

Cubes come from the same idea measured differently — the largest cube that fits
is found by counting steps to the outside along the axes instead of straight
through — and at each place the two compete on how much of the object they
account for.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import trimesh

#: Cells across the object's longest side. The parts have to be several cells
#: thick to be found at all, and the cost is cubic, so this is the dial between
#: "a leg is a shape" and "a leg is a rounding error".
STEPS = 128

#: Stop once the shapes account for this much of the object. Past it the
#: additions are slivers filling the creases between parts, which is detail the
#: whole exercise is trying to be rid of.
ENOUGH = 0.93

#: Never place a shape smaller than this share of the first one. A cow is a
#: barrel and some limbs; anything a twentieth of the barrel is a wrinkle.
SMALLEST = 0.055

#: How square a part must measure before it is called a cube. The two depths
#: are equal at the centre of a cube and about 0.58 apart at the centre of a
#: sphere, so anything above this is squarer than it is round. Set high: a
#: stylised animal is mostly balls, and a cube where a ball belongs is far more
#: noticeable than the reverse.
BOXY = 0.86

#: Subdivision for the spheres. Two reads as round and keeps a dozen of them
#: to a few thousand triangles.
DETAIL = 2


@dataclass(frozen=True)
class Shape:
    """One primitive standing for one part of the object."""

    mesh: trimesh.Trimesh
    kind: str
    #: Share of the object this shape accounts for.
    weight: float


def blockify(mesh: trimesh.Trimesh, size: int = 28) -> trimesh.Trimesh:
    """Rebuild any mesh as coloured blocks on a grid.

    For the case a carve cannot serve: one picture, so there are no other
    outlines to carve against and all there is to work with is whatever the
    reconstruction produced. Blocks will not make a wrong shape right — nothing
    can, from one photograph — but they make it a deliberate object rather than
    a lumpy one, and the silhouette the camera actually saw survives.

    Only cells with an exposed face become cubes; the inside of a solid is never
    seen.
    """

    from scipy.spatial import cKDTree

    pitch = float(mesh.extents.max()) / size
    voxels = mesh.voxelized(pitch=pitch).fill()
    solid = np.asarray(voxels.matrix, dtype=bool)
    if not solid.any():
        raise ValueError("nothing to build blocks from")

    padded = np.pad(solid, 1)
    exposed = solid & ~(
        padded[:-2, 1:-1, 1:-1]
        & padded[2:, 1:-1, 1:-1]
        & padded[1:-1, :-2, 1:-1]
        & padded[1:-1, 2:, 1:-1]
        & padded[1:-1, 1:-1, :-2]
        & padded[1:-1, 1:-1, 2:]
    )
    cells = np.argwhere(exposed)
    origin = np.asarray(voxels.transform)[:3, 3]
    centres = origin + cells * pitch

    # Each block takes the colour of the surface nearest it, so a tan muzzle
    # stays tan rather than averaging into the body around it.
    source = getattr(mesh.visual, "vertex_colors", None)
    if source is not None and len(source) == len(mesh.vertices):
        _, nearest = cKDTree(np.asarray(mesh.vertices)).query(centres, k=1)
        colours = np.asarray(source)[nearest]
    else:
        colours = np.tile(np.array([200, 200, 200, 255], np.uint8), (len(cells), 1))

    cube = trimesh.creation.box(extents=(pitch, pitch, pitch))
    template = np.asarray(cube.vertices)
    faces = np.asarray(cube.faces)

    vertices = (template[None, :, :] + centres[:, None, :]).reshape(-1, 3)
    offsets = (np.arange(len(cells)) * len(template)).reshape(-1, 1, 1)
    indices = (faces[None, :, :] + offsets).reshape(-1, 3)

    blocks = trimesh.Trimesh(vertices=vertices, faces=indices, process=False)
    blocks.visual = trimesh.visual.ColorVisuals(
        mesh=blocks,
        vertex_colors=np.repeat(colours, len(template), axis=0),
    )
    return blocks


def _solid(mesh: trimesh.Trimesh, steps: int) -> tuple[np.ndarray, np.ndarray, float]:
    """The object as a filled grid, with where it sits and how coarse it is."""

    pitch = float(mesh.extents.max()) / steps
    filled = mesh.voxelized(pitch=pitch).fill()
    matrix = np.asarray(filled.matrix, dtype=bool)
    origin = np.asarray(filled.transform)[:3, 3]
    return matrix, origin, pitch


def _covers(shape: np.ndarray, centre: np.ndarray, reach: float, kind: str) -> np.ndarray:
    """Which cells a primitive of this size at this place would contain."""

    grids = np.indices(shape)
    offsets = grids - centre.reshape(3, 1, 1, 1)
    if kind == "sphere":
        return (offsets**2).sum(axis=0) <= reach**2
    return (np.abs(offsets) <= reach).all(axis=0)


def _axes_of(points: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """The directions a part extends along, and how far along each.

    A leg is long and thin, a terminal building is long and low, a head is
    round. Fitting the same shape to all three describes none of them, so each
    part is measured along its own axes — which is the whole difference between
    a body that is one shape and a body that is four beads in a row.
    """

    centre = points.mean(axis=0)
    centred = points - centre
    _, _, axes = np.linalg.svd(centred, full_matrices=False)
    reach = np.quantile(np.abs(centred @ axes.T), REACH, axis=0)
    return axes, np.maximum(reach, 0.5)


def _stretched(kind: str, axes: np.ndarray, reach: np.ndarray) -> trimesh.Trimesh:
    """A box or ellipsoid on a part's own axes, with three independent sizes."""

    if kind == "ellipsoid":
        shape = trimesh.creation.icosphere(subdivisions=DETAIL, radius=1.0)
        shape.apply_scale(reach)
    else:
        shape = trimesh.creation.box(extents=reach * 2.0)

    placement = np.eye(4)
    placement[:3, :3] = axes.T
    shape.apply_transform(placement)
    return shape


def _holds(kind: str, local: np.ndarray, reach: np.ndarray) -> np.ndarray:
    """Whether points, in the part's own frame, fall inside the primitive."""

    if kind == "ellipsoid":
        return np.linalg.norm(local / reach, axis=1) <= 1.0
    return (np.abs(local) <= reach).all(axis=1)


def _volume_of(kind: str, reach: np.ndarray) -> float:
    if kind == "ellipsoid":
        return float(4.0 / 3.0 * np.pi * np.prod(reach))
    return float(8.0 * np.prod(reach))


def fit(mesh: trimesh.Trimesh, most: int = 14, steps: int = STEPS) -> list[Shape]:
    """Account for a solid with spheres and cubes, biggest first.

    Stops when the shapes cover enough of the object, or when the next one
    would be a sliver, whichever comes first — so a simple object gets few
    shapes and a complicated one gets more, without being told which it is.
    """

    from scipy.ndimage import (
        distance_transform_cdt,
        distance_transform_edt,
        maximum_filter,
    )

    solid, origin, pitch = _solid(mesh, steps)
    total = float(solid.sum())
    if total == 0:
        return []

    # Measured once, on the whole object. Recomputing it on what is left after
    # each shape is taken away does not work: removing a ball from the middle of
    # a body leaves a shell, the deepest point of a shell is barely inside it,
    # and every shape after the first comes out small and stuck to the surface.
    # The result was a cow-shaped scatter of loose beads.
    through = distance_transform_edt(solid)
    along = distance_transform_cdt(solid, metric="chessboard").astype(float)

    # The ridge running down the middle of the object — its skeleton. Every
    # part has a peak on it, sized by that part's own thickness.
    ridge = (through >= maximum_filter(through, size=3)) & (through > 1.0)
    seeds = np.argwhere(ridge)
    order = np.argsort(-through[tuple(seeds.T)])

    covered = np.zeros_like(solid)
    shapes: list[Shape] = []
    first: float | None = None

    for position in seeds[order]:
        if len(shapes) >= most:
            break
        if covered.sum() >= total * ENOUGH:
            break

        index = tuple(position)
        if covered[index]:
            continue

        # Which primitive this part is, from how the two depths compare. They
        # are equal at the centre of a cube and about 0.58 apart at the centre of
        # a sphere, because the biggest cube inside a ball spans its diameter
        # cornerwise. Comparing volumes instead is no use — an inscribed cube
        # always holds more than an inscribed sphere, so everything came out
        # cubes.
        if along[index] >= through[index] * BOXY:
            kind, reach = "cube", float(along[index])
        else:
            kind, reach = "sphere", float(through[index])

        inside = _covers(solid.shape, position, reach, kind)
        gained = float((inside & solid & ~covered).sum()) / total

        if first is None:
            first = gained
        elif gained < first * SMALLEST:
            # Ordered by size, so once the additions are slivers they stay
            # slivers.
            break

        shapes.append(
            Shape(
                mesh=_build(kind, origin + position * pitch, reach * pitch),
                kind=kind,
                weight=gained,
            )
        )
        covered |= inside

    return shapes


def _build(kind: str, centre: np.ndarray, reach: float) -> trimesh.Trimesh:
    if kind == "sphere":
        shape = trimesh.creation.icosphere(subdivisions=DETAIL, radius=reach)
    else:
        shape = trimesh.creation.box(extents=(reach * 2,) * 3)
    shape.apply_translation(centre)
    return shape


def rebuild(
    mesh: trimesh.Trimesh, colour: np.ndarray, most: int = 14, steps: int = STEPS
) -> tuple[trimesh.Trimesh | None, list[Shape]]:
    """One element, remade as the shapes that fit inside it."""

    shapes = fit(mesh, most=most, steps=steps)
    if not shapes:
        return None, []

    pieces = []
    for shape in shapes:
        piece = shape.mesh
        piece.visual = trimesh.visual.ColorVisuals(
            mesh=piece,
            vertex_colors=np.tile(
                np.append(np.asarray(colour, dtype=np.uint8), 255),
                (len(piece.vertices), 1),
            ),
        )
        pieces.append(piece)

    return trimesh.util.concatenate(pieces), shapes
