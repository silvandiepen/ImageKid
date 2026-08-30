"""Render orthographic views of a generated GLB for visual QA.

The product promise is that a user can rotate behind a generated model and judge
the inferred hidden geometry. That is not something a triangle count can prove,
so this renders front/right/back/left/top views into a contact sheet.

Deliberately a self-contained numpy rasteriser: it needs no GL context, so it
runs the same way in a terminal, over SSH, and in CI. It is a QA tool, not the
product's preview path — the app uses a native 3D view.

    python scripts/render_views.py model.glb --output sheet.png
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path

import numpy as np
import trimesh
from PIL import Image

#: Yaw angles, in degrees, for the standard inspection views.
VIEWS = [("front", 0), ("right", 90), ("back", 180), ("left", 270), ("top", None)]

BACKGROUND = np.array([28, 28, 32], dtype=np.uint8)


def as_single_mesh(path: Path) -> trimesh.Trimesh:
    """Flatten a GLB into one mesh with per-vertex colour."""

    loaded = trimesh.load(str(path), file_type="glb", force="scene")
    meshes = []
    for name, geometry in loaded.geometry.items():
        if not isinstance(geometry, trimesh.Trimesh):
            continue
        transform = loaded.graph.get(name)[0] if name in loaded.graph.nodes else None
        mesh = geometry.copy()
        if transform is not None:
            mesh.apply_transform(transform)
        meshes.append(mesh)
    if not meshes:
        raise SystemExit(f"no mesh geometry in {path}")
    return trimesh.util.concatenate(meshes)


#: Used only when a mesh genuinely carries no colour.
NEUTRAL = np.array([200, 200, 200], dtype=np.uint8)


def vertex_colours(mesh: trimesh.Trimesh) -> np.ndarray:
    """Per-vertex RGB, falling back to neutral grey only if there is none.

    Reads ``ColorVisuals.vertex_colors`` directly rather than going through
    ``to_color()``: on a mesh that already has colour, that round-trip hands
    back trimesh's default grey and silently discards the real thing.
    """

    visual = getattr(mesh, "visual", None)
    colours = None

    if isinstance(visual, trimesh.visual.ColorVisuals):
        stored = visual.vertex_colors
        if stored is not None and len(stored) == len(mesh.vertices):
            colours = np.asarray(stored)
    elif isinstance(visual, trimesh.visual.TextureVisuals):
        # Sample the texture through the UVs.
        try:
            converted = visual.to_color().vertex_colors
            if converted is not None and len(converted) == len(mesh.vertices):
                colours = np.asarray(converted)
        except Exception:
            colours = None

    if colours is None:
        return np.tile(NEUTRAL, (len(mesh.vertices), 1))
    return colours[:, :3].astype(np.uint8)


def rotate(vertices: np.ndarray, yaw_degrees: float | None) -> np.ndarray:
    """Rotate about +Y for a yaw view, or tip forward for the top view."""

    if yaw_degrees is None:
        angle = math.radians(90.0)
        matrix = np.array(
            [
                [1, 0, 0],
                [0, math.cos(angle), -math.sin(angle)],
                [0, math.sin(angle), math.cos(angle)],
            ]
        )
    else:
        angle = math.radians(yaw_degrees)
        matrix = np.array(
            [
                [math.cos(angle), 0, math.sin(angle)],
                [0, 1, 0],
                [-math.sin(angle), 0, math.cos(angle)],
            ]
        )
    return vertices @ matrix.T


def render(mesh: trimesh.Trimesh, yaw: float | None, size: int) -> Image.Image:
    """Orthographic z-buffered render with flat per-face shading."""

    vertices = rotate(np.asarray(mesh.vertices, dtype=np.float64), yaw)
    colours = vertex_colours(mesh)

    # Fit the model into the frame with a small margin.
    low, high = vertices.min(axis=0), vertices.max(axis=0)
    centre = (low + high) / 2.0
    extent = float((high - low)[:2].max()) or 1.0
    scale = (size * 0.88) / extent

    screen_x = (vertices[:, 0] - centre[0]) * scale + size / 2.0
    screen_y = size / 2.0 - (vertices[:, 1] - centre[1]) * scale
    depth = vertices[:, 2]

    frame = np.zeros((size, size, 3), dtype=np.uint8)
    frame[:, :] = BACKGROUND
    zbuffer = np.full((size, size), -np.inf, dtype=np.float64)

    faces = np.asarray(mesh.faces)
    # Painter-friendly ordering is not enough for interpenetrating geometry, so
    # a real z-buffer decides every pixel.
    normals = np.asarray(mesh.face_normals)
    rotated_normals = rotate(normals, yaw)
    # Simple headlight shading, clamped so back faces stay visible rather than black.
    shade = np.clip(np.abs(rotated_normals[:, 2]) * 0.75 + 0.25, 0.0, 1.0)

    for index, face in enumerate(faces):
        xs = screen_x[face]
        ys = screen_y[face]
        zs = depth[face]

        min_x = max(int(np.floor(xs.min())), 0)
        max_x = min(int(np.ceil(xs.max())), size - 1)
        min_y = max(int(np.floor(ys.min())), 0)
        max_y = min(int(np.ceil(ys.max())), size - 1)
        if min_x > max_x or min_y > max_y:
            continue

        area = (xs[1] - xs[0]) * (ys[2] - ys[0]) - (xs[2] - xs[0]) * (ys[1] - ys[0])
        if abs(area) < 1e-9:
            continue

        grid_y, grid_x = np.mgrid[min_y : max_y + 1, min_x : max_x + 1]
        px = grid_x + 0.5
        py = grid_y + 0.5

        w0 = ((xs[1] - px) * (ys[2] - py) - (xs[2] - px) * (ys[1] - py)) / area
        w1 = ((xs[2] - px) * (ys[0] - py) - (xs[0] - px) * (ys[2] - py)) / area
        w2 = 1.0 - w0 - w1

        inside = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
        if not inside.any():
            continue

        z = w0 * zs[0] + w1 * zs[1] + w2 * zs[2]
        target_z = zbuffer[min_y : max_y + 1, min_x : max_x + 1]
        visible = inside & (z > target_z)
        if not visible.any():
            continue

        face_colour = colours[face].mean(axis=0) * shade[index]
        target_z[visible] = z[visible]
        patch = frame[min_y : max_y + 1, min_x : max_x + 1]
        patch[visible] = face_colour.astype(np.uint8)

    return Image.fromarray(frame)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("glb", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--size", type=int, default=320)
    args = parser.parse_args()

    mesh = as_single_mesh(args.glb)
    tiles = [(label, render(mesh, yaw, args.size)) for label, yaw in VIEWS]

    sheet = Image.new("RGB", (args.size * len(tiles), args.size), tuple(BACKGROUND))
    for index, (_, tile) in enumerate(tiles):
        sheet.paste(tile, (index * args.size, 0))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(args.output)
    print(f"{args.glb.name}: {' '.join(label for label, _ in tiles)} -> {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
