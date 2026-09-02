"""Turn a photographic reconstruction into flat-shaded cartoon shapes.

The engine reconstructs colour per vertex, sampled from the source image, so a
model comes back with thousands of slightly different shades — soft gradients,
baked-in lighting, and JPEG-ish mottling. That reads as a photograph draped over
a mesh, which is at odds with the stylised, flat-coloured assets these images
usually start as.

Quantising the colour to a small palette and painting whole faces rather than
blending across them gives back what the source looked like: a handful of solid
regions with crisp boundaries — a muzzle, a horn, a belly patch — that read as
assembled shapes rather than one photographed lump.

This is a finishing pass, not reconstruction. It never moves the surface — it
does split shared vertices so that colour boundaries survive export, which
changes the vertex indexing but not a single position.
"""

from __future__ import annotations

import numpy as np
import trimesh

#: Below this the palette starts merging things that read as separate parts —
#: a yak's horns fold into its face.
MINIMUM_PALETTE = 2

#: Above this the flat look breaks down and it is just the original gradient
#: again, more expensively.
MAXIMUM_PALETTE = 64


def _vertex_rgb(mesh: trimesh.Trimesh) -> "np.ndarray | None":
    visual = getattr(mesh, "visual", None)
    if isinstance(visual, trimesh.visual.TextureVisuals):
        try:
            visual = visual.to_color()
        except Exception:
            return None
    if not isinstance(visual, trimesh.visual.ColorVisuals):
        return None
    colours = visual.vertex_colors
    if colours is None or len(colours) != len(mesh.vertices):
        return None
    return np.asarray(colours)[:, :3].astype(np.float64)


def build_palette(colours: np.ndarray, count: int, seed: int = 0) -> np.ndarray:
    """Choose ``count`` representative colours by k-means in RGB.

    Weighted toward what the eye notices: clustering happens in plain RGB
    because the palette only has to look like the source's own flat colours,
    which are already far apart.
    """

    from scipy.cluster.vq import kmeans2

    unique = np.unique(colours, axis=0)
    if len(unique) <= count:
        return unique

    # `++` seeding rather than random: with a handful of clusters a bad start
    # visibly merges two real colours, and this is deterministic given the seed.
    centroids, _ = kmeans2(unique, count, minit="++", seed=seed, iter=25)

    # kmeans2 can return an empty cluster as an all-zero centroid, which would
    # paint part of the model black.
    live = centroids[~np.all(centroids == 0, axis=1)]
    return live if len(live) else unique[:count]


def flatten_colour(mesh: trimesh.Trimesh, palette_size: int, seed: int = 0) -> bool:
    """Repaint ``mesh`` with a small palette, one flat colour per face.

    Face colours rather than vertex colours: blending three corner colours
    across a triangle is exactly the soft gradient this is meant to remove, and
    painting whole faces puts a crisp boundary where two regions meet.

    Returns whether anything was repainted.
    """

    if palette_size < MINIMUM_PALETTE or len(mesh.faces) == 0:
        return False
    palette_size = min(palette_size, MAXIMUM_PALETTE)

    colours = _vertex_rgb(mesh)
    if colours is None:
        return False

    palette = build_palette(colours, palette_size, seed=seed)

    # Split shared vertices so every face owns its three corners.
    #
    # glTF has no per-face colour: it stores colour per vertex. A vertex shared
    # by two differently coloured faces can only hold one value, so the exporter
    # averages them — and the crisp boundary this pass exists to create comes
    # back as a gradient. Measured on a six-colour model: 114 distinct colours
    # after a GLB round-trip. Unmerging costs vertices (three per face) and buys
    # boundaries that survive the file format.
    mesh.unmerge_vertices()
    colours = _vertex_rgb(mesh)
    if colours is None:
        return False

    # Each face takes the palette entry nearest its own average colour. Deciding
    # per face rather than per vertex means a face never straddles two entries
    # and needs a gradient to express it.
    face_colours = colours[mesh.faces].mean(axis=1)
    distances = np.linalg.norm(
        face_colours[:, None, :] - palette[None, :, :], axis=2
    )
    chosen = palette[np.argmin(distances, axis=1)]

    rgba = np.empty((len(mesh.faces), 4), dtype=np.uint8)
    rgba[:, :3] = np.clip(chosen, 0, 255).astype(np.uint8)
    rgba[:, 3] = 255
    mesh.visual = trimesh.visual.ColorVisuals(mesh=mesh, face_colors=rgba)
    return True
