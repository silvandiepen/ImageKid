"""Finding an object's parts in the picture rather than in the mesh.

A stylised subject is drawn as a few flat-coloured shapes: a black body, a tan
muzzle with two nostril holes in it, orange inside each ear. That structure is
right there in the image, crisp and unambiguous, and it is the structure a
cartoon model wants to be built from.

It is not recoverable from the reconstruction. A reconstructed surface is one
continuous lumpy thing with no seams in it, and every attempt to find "the
head" in that surface — clustering the skin, clustering the solid, following
thickness — carves the blob a different way and none of them find a head. The
mesh does not know it has parts. The picture does.

So the parts come from here: quantise the panel to a small palette, take each
connected region of one colour, and that is an element. Holes come free, and
they matter — a nostril is a hole in the muzzle, not a separate object, and
region-finding gives it as one.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from PIL import Image

#: Colours to reduce a panel to before looking for regions. Enough for a body,
#: a muzzle, ear insides, hooves and a couple of shading bands; few enough that
#: a soft gradient across a flank stays one colour instead of becoming stripes.
PALETTE = 6

#: A region smaller than this share of the subject is a speck of anti-aliasing
#: or a stray highlight, not an element of the object.
SMALLEST_ELEMENT = 0.004

#: A hole smaller than this share of the region it sits in is noise. A nostril
#: is well above it; a compression artefact is not.
SMALLEST_HOLE = 0.02


@dataclass(frozen=True)
class Element:
    """One flat-coloured piece of a subject, as seen in one panel."""

    #: Boolean mask over the panel: true where this element is.
    mask: np.ndarray
    #: The flat colour it is drawn in, RGB.
    colour: np.ndarray
    #: Share of the subject's area this element covers.
    weight: float
    #: Holes inside it — a nostril, an eye — as their own masks.
    holes: tuple

    @property
    def area(self) -> int:
        return int(self.mask.sum())


#: How much brightness counts against colour when deciding what is one element.
#:
#: A black flank runs from near-black in shadow to mid-grey in the light, and in
#: plain RGB those are as far apart as black is from tan — so clustering splits
#: one body into three shading bands and calls them different parts. They are
#: the same material under different light. Colour barely moves; brightness
#: does. Weighting brightness down lets the muzzle separate from the body while
#: the body stays one thing.
BRIGHTNESS_WEIGHT = 0.25

#: How different two groups' colours must be to stay separate, with brightness
#: excluded entirely. A black flank and a lit black flank sit almost on top of
#: each other here; a tan muzzle is eighty units away. Anything between is a
#: judgement call, and this is set nearer the muzzle than the flank so that
#: genuine markings survive.
MATERIAL_TOLERANCE = 40.0


def _material(pixels: np.ndarray) -> np.ndarray:
    """Colour in a form where lighting matters less than material.

    Brightness on one axis, the two colour oppositions on the others — roughly
    how vision separates them, and enough to tell a lit flank from a tan muzzle
    without a colour-science dependency.
    """

    red, green, blue = pixels[:, 0], pixels[:, 1], pixels[:, 2]
    brightness = 0.299 * red + 0.587 * green + 0.114 * blue
    return np.stack(
        [
            brightness * BRIGHTNESS_WEIGHT,
            red - green,
            (red + green) / 2.0 - blue,
        ],
        axis=1,
    )


def quantise(image: Image.Image, palette: int = PALETTE, seed: int = 0):
    """Reduce a panel to a few flat colours, ignoring the background.

    Returns the palette and a label per pixel, with -1 outside the subject.
    """

    from scipy.cluster.vq import kmeans2

    rgba = np.asarray(image.convert("RGBA"))
    inside = rgba[:, :, 3] > 8
    pixels = rgba[:, :, :3][inside].astype(np.float64)
    if not len(pixels):
        raise ValueError("the panel has no subject in it")

    unique = np.unique(pixels, axis=0)
    count = min(palette, len(unique))
    if count < 2:
        labels = np.full(rgba.shape[:2], -1, dtype=int)
        labels[inside] = 0
        return np.clip(unique[:1], 0, 255).astype(np.uint8), labels

    _, assignment = kmeans2(
        _material(pixels), count, minit="++", seed=seed, missing="warn"
    )
    assignment = _merge_shades(pixels, assignment, count)

    # The palette is the average of what each group actually looked like, not
    # the cluster centre, which lives in a space with no colour in it.
    kept = np.unique(assignment)
    centres = np.stack([pixels[assignment == index].mean(axis=0) for index in kept])
    renumber = {old: new for new, old in enumerate(kept)}
    assignment = np.array([renumber[value] for value in assignment])

    labels = np.full(rgba.shape[:2], -1, dtype=int)
    labels[inside] = assignment
    return np.clip(centres, 0, 255).astype(np.uint8), labels


def _merge_shades(
    pixels: np.ndarray, assignment: np.ndarray, count: int
) -> np.ndarray:
    """Fold together groups that differ only in how brightly they are lit.

    Weighting brightness down is not enough on its own. A subject that is nearly
    all one material — a black cow — has almost no colour differences for the
    clustering to find, so it spends every group it is given on shading anyway
    and reports a body in three parts. Merging afterwards on colour alone, with
    brightness left out entirely, puts the flank back together while leaving the
    muzzle where it is.
    """

    present = [index for index in range(count) if (assignment == index).any()]
    colour = {
        index: np.array(
            [
                pixels[assignment == index][:, 0].mean()
                - pixels[assignment == index][:, 1].mean(),
                pixels[assignment == index][:, :2].mean()
                - pixels[assignment == index][:, 2].mean(),
            ]
        )
        for index in present
    }

    merged = dict.fromkeys(present)
    for index in present:
        merged[index] = index

    def root(index: int) -> int:
        while merged[index] != index:
            index = merged[index]
        return index

    for first in present:
        for second in present:
            if second <= first:
                continue
            if np.linalg.norm(colour[first] - colour[second]) < MATERIAL_TOLERANCE:
                merged[root(second)] = root(first)

    return np.array([root(value) for value in assignment])


def _holes_in(mask: np.ndarray) -> list[np.ndarray]:
    """Enclosed gaps in a region, each as its own mask.

    A nostril is a hole in the muzzle, and saying so is the difference between
    a shape you can edit and two shapes that happen to overlap.
    """

    from scipy.ndimage import binary_fill_holes, label

    solid = binary_fill_holes(mask)
    gaps = solid & ~mask
    if not gaps.any():
        return []

    pieces, count = label(gaps)
    found = []
    for index in range(1, count + 1):
        hole = pieces == index
        if hole.sum() >= mask.sum() * SMALLEST_HOLE:
            found.append(hole)
    return found


def find(image: Image.Image, palette: int = PALETTE, seed: int = 0) -> list[Element]:
    """The elements a panel is drawn from, largest first."""

    from scipy.ndimage import label

    centres, labels = quantise(image, palette, seed=seed)
    subject = float((labels >= 0).sum())
    if subject == 0:
        return []

    elements: list[Element] = []
    for index, colour in enumerate(centres):
        region = labels == index
        if not region.any():
            continue
        # One colour can appear in several places — two ears, four hooves — and
        # each is its own element.
        pieces, count = label(region)
        for piece in range(1, count + 1):
            mask = pieces == piece
            if mask.sum() < subject * SMALLEST_ELEMENT:
                continue
            elements.append(
                Element(
                    mask=mask,
                    colour=np.asarray(colour),
                    weight=float(mask.sum()) / subject,
                    holes=tuple(_holes_in(mask)),
                )
            )

    elements.sort(key=lambda element: -element.weight)
    return elements


# ---------------------------------------------------------------------------
# From flat regions to solids
# ---------------------------------------------------------------------------

#: Cells across the model when carving. The silhouettes are crisp, so this is
#: what decides how crisp the result is — unlike a reconstruction, there is no
#: noise here for a coarse grid to be hiding.
CARVE_STEPS = 192

#: Two elements are the same material if their colours are this close. Panels
#: are lit differently, so the same muzzle photographs a little warmer from one
#: side than another.
SAME_MATERIAL = 60.0


@dataclass(frozen=True)
class Piece:
    """One material, as a solid, with the colour it is drawn in."""

    mesh: object
    colour: np.ndarray
    #: Panels this material was visible in.
    seen_in: int


def _grid(size: int, extent: float = 1.0):
    """Sample points filling a cube ``extent`` units across, centred on nothing.

    The world is scaled so the subject stands one unit tall, but an animal is
    usually longer than it is tall, so a one-unit cube saws its nose off — which
    is exactly what happened: the muzzle carved to nothing because it lay
    outside the box. The cube has to be as wide as the widest panel is.
    """

    half = extent / 2.0
    axis = np.linspace(-half, half, size)
    return np.stack(np.meshgrid(axis, axis, axis, indexing="ij"), axis=-1)


def build(panels: list, size: int = CARVE_STEPS, seed: int = 0):
    """Assemble a model from panels, as a few flat-coloured solids.

    ``panels`` are ``(Panel, [Element])`` pairs, one per view. Elements are
    grouped across panels by colour into materials, each material is carved from
    the panels that saw it, and each separate lump of a material becomes its own
    solid — so two ear linings of one colour come out as two things.

    Nothing here reconstructs. The shape is the intersection of outlines that
    were drawn, which is why the horns survive.
    """

    import trimesh

    frames = [panel for panel, _ in panels]
    scales = reconcile(frames)
    extent = needed_extent(frames)
    points = _grid(size, extent)

    materials: list[list] = []
    for (panel, found), scale in zip(panels, scales):
        for element in found:
            for group in materials:
                if (
                    np.linalg.norm(
                        group[0][0].colour.astype(float)
                        - element.colour.astype(float)
                    )
                    < SAME_MATERIAL
                ):
                    group.append((element, panel, scale))
                    break
            else:
                materials.append([(element, panel, scale)])

    pieces = []
    for group in materials:
        colour = np.mean([e.colour.astype(float) for e, _, _ in group], axis=0)

        # Within one panel, regions of one colour are different places the same
        # material appears — a muzzle and two ear linings. Union them: asking
        # for a point inside all three at once is asking for nowhere, and it
        # carved the muzzle away to nothing.
        combined: dict = {}
        for element, panel, scale in group:
            key = id(panel)
            if key not in combined:
                combined[key] = [panel, np.zeros_like(element.mask), scale]
            combined[key][1] |= element.mask

        field = np.ones((size, size, size), dtype=np.float32)
        for panel, mask, scale in combined.values():
            field = carve(mask, panel, points, field, scale)
        if field.max() < 0.5:
            continue

        whole = _surface(field, size, extent)
        if whole is None:
            continue
        for lump in whole.split(only_watertight=False):
            if len(lump.faces) < len(whole.faces) * 0.02:
                continue
            lump.visual = trimesh.visual.ColorVisuals(
                mesh=lump,
                vertex_colors=np.tile(
                    np.append(colour.astype(np.uint8), 255), (len(lump.vertices), 1)
                ),
            )
            pieces.append(lump)

    if not pieces:
        raise ValueError("nothing could be carved from these panels")
    return trimesh.util.concatenate(pieces), len(pieces)


def blocks(panels: list, size: int = 34, seed: int = 0):
    """Assemble a model as coloured blocks on a grid.

    The carve already works on a grid, so this is what it produces before
    anything is smoothed over: the cells that are inside the object, each kept
    as a cube. Deliberately blocky rather than accidentally lumpy — a low
    resolution reads as a choice, where a smoothed reconstruction at the same
    fidelity reads as a failure.

    Only cells with an exposed face are emitted. The inside of a solid is never
    seen, and leaving it out is the difference between a few thousand triangles
    and a few hundred thousand.
    """

    import trimesh

    frames = [panel for panel, _ in panels]
    scales = reconcile(frames)
    extent = needed_extent(frames)
    points = _grid(size, extent)
    step = extent / (size - 1)

    claimed = np.zeros((size, size, size), dtype=bool)
    pieces = []

    # Smallest elements first: a muzzle should win its cells from the body it
    # sits in, rather than the body swallowing it.
    for panel_group, colour in sorted(
        _by_material(panels, scales), key=lambda item: item[0][0][1].sum()
    ):
        field = np.ones((size, size, size), dtype=np.float32)
        for panel, mask, scale in panel_group:
            field = carve(mask, panel, points, field, scale)

        solid = (field >= 0.5) & ~claimed
        if not solid.any():
            continue
        claimed |= solid

        cubes = _blocks_of(solid, points, step, colour)
        if cubes is not None:
            pieces.append(cubes)

    if not pieces:
        raise ValueError("nothing could be built from these panels")
    return trimesh.util.concatenate(pieces), len(pieces)


def _by_material(panels: list, scales: list) -> list:
    """Group each panel's elements by colour, unioning them within a panel."""

    materials: list[list] = []
    colours: list[np.ndarray] = []
    for (panel, found), scale in zip(panels, scales):
        for element in found:
            for index, group in enumerate(materials):
                if (
                    np.linalg.norm(colours[index] - element.colour.astype(float))
                    < SAME_MATERIAL
                ):
                    for entry in group:
                        if entry[0] is panel:
                            entry[1] |= element.mask
                            break
                    else:
                        group.append([panel, element.mask.copy(), scale])
                    break
            else:
                materials.append([[panel, element.mask.copy(), scale]])
                colours.append(element.colour.astype(float))

    return list(zip(materials, colours))


def _blocks_of(solid: np.ndarray, points: np.ndarray, step: float, colour):
    """One cube per exposed cell, as a single mesh."""

    import trimesh

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
    if not len(cells):
        return None

    cube = trimesh.creation.box(extents=(step, step, step))
    template = np.asarray(cube.vertices)
    faces = np.asarray(cube.faces)

    centres = points[tuple(cells.T)]
    vertices = (template[None, :, :] + centres[:, None, :]).reshape(-1, 3)
    offsets = (np.arange(len(cells)) * len(template)).reshape(-1, 1, 1)
    indices = (faces[None, :, :] + offsets).reshape(-1, 3)

    mesh = trimesh.Trimesh(vertices=vertices, faces=indices, process=False)
    mesh.visual = trimesh.visual.ColorVisuals(
        mesh=mesh,
        vertex_colors=np.tile(
            np.append(np.asarray(colour, dtype=np.uint8), 255), (len(vertices), 1)
        ),
    )
    return mesh


def _surface(field: np.ndarray, size: int, extent: float):
    """The surface of a carved field, in the object's own coordinates."""

    import torch
    import trimesh
    from torchmcubes import marching_cubes

    vertices, faces = marching_cubes(
        torch.from_numpy(np.ascontiguousarray(field)), 0.5
    )
    if not len(faces):
        return None
    points = (vertices.numpy()[:, ::-1] / (size - 1.0) - 0.5) * extent
    mesh = trimesh.Trimesh(vertices=points, faces=faces.numpy(), process=True)
    mesh.fix_normals()
    return mesh


def needed_extent(panels: list) -> float:
    """How wide a cube has to be to hold the subject, in subject heights."""

    widest = 1.0
    for panel in panels:
        rows, columns = np.where(panel.subject)
        height = float(rows.max() - rows.min() + 1)
        width = float(columns.max() - columns.min() + 1)
        widest = max(widest, width / height)
    return widest * 1.12


@dataclass(frozen=True)
class Panel:
    """One picture of the subject, and where it was taken from.

    ``subject`` is the whole subject's mask, not one element's. Every panel is
    an independent render, fitted to its own frame, so the panels have to be
    reconciled before anything can be carved from them — and the subject's own
    outline is what they are reconciled by.
    """

    subject: np.ndarray
    direction: np.ndarray


def _frame(subject: np.ndarray) -> tuple[float, float, float]:
    """Where the subject sits in its panel: centre column, centre row, height."""

    rows, columns = np.where(subject)
    top, bottom = rows.min(), rows.max()
    left, right = columns.min(), columns.max()
    return (left + right) / 2.0, (top + bottom) / 2.0, float(bottom - top + 1)


def _spread(panel: Panel, world_axis: np.ndarray) -> float:
    """How many pixels the subject covers along a world direction, in one panel.

    A panel only measures the two directions across its picture, and this is how
    far the subject reaches along one of them.
    """

    from .multiview import _screen_axes

    axes = _screen_axes(np.asarray(panel.direction, dtype=float))
    screen = np.array([world_axis @ axes[0], world_axis @ axes[1]])
    length = np.linalg.norm(screen)
    if length < 1e-9:
        return 0.0
    screen /= length

    centre_x, centre_y, _ = _frame(panel.subject)
    rows, columns = np.where(panel.subject)
    along = (columns - centre_x) * screen[0] - (rows - centre_y) * screen[1]
    return float(along.max() - along.min())


def reconcile(panels: list) -> list:
    """How many pixels one world unit is worth in each panel.

    Every panel is its own render, fitted to its own frame, so a side view and a
    view from overhead disagree about how big the subject is. They are put on a
    common footing the same way the reconstructions were: by an axis both
    cameras measured.

    For two views around the horizon that axis is height. For a side view and an
    overhead one it is neither camera's obvious choice — and using height there
    would be meaningless, since a camera looking straight down cannot see it.
    """

    from .multiview import _shared_axis

    reference = panels[0]
    _, _, reference_height = _frame(reference.subject)

    scales = []
    for panel in panels:
        axis = _shared_axis(
            np.asarray(panel.direction, dtype=float),
            np.asarray(reference.direction, dtype=float),
        )
        theirs = _spread(reference, axis)
        ours = _spread(panel, axis)
        if theirs < 1e-6 or ours < 1e-6:
            scales.append(reference_height)
            continue
        # The reference defines the world: it stands one unit tall.
        world = theirs / reference_height
        scales.append(ours / world)
    return scales


def carve(
    mask: np.ndarray,
    panel: Panel,
    points: np.ndarray,
    field: np.ndarray,
    scale: float | None = None,
) -> np.ndarray:
    """Cut from ``field`` everything this panel's region does not cover.

    Panels are reconciled by the subject's height in each, which is the one
    measurement they all share — the same problem as reconciling reconstructions,
    but on outlines that were drawn rather than inferred, and correspondingly
    easier. The world is scaled so the subject stands one unit tall, centred.

    The region is read with interpolation and kept as a fraction rather than a
    yes or no. Rounding to the nearest pixel steps the cut in and out by a whole
    pixel as the sampling drifts across the grid, and those steps come out of
    the extractor as ridges banding the whole model — the surface is smooth, the
    sampling of it was not.
    """

    from scipy.ndimage import map_coordinates

    from .multiview import _screen_axes

    axes = _screen_axes(np.asarray(panel.direction, dtype=float))
    centre_x, centre_y, height = _frame(panel.subject)
    if scale is None:
        scale = height

    screen = points.reshape(-1, 3) @ axes.T
    column = centre_x + screen[:, 0] * scale
    row = centre_y - screen[:, 1] * scale

    covered = map_coordinates(
        mask.astype(np.float32),
        np.stack([row, column]),
        order=1,
        mode="constant",
        cval=0.0,
    )
    return np.minimum(field, covered.reshape(field.shape))
