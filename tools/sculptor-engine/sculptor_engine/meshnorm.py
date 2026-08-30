"""Deterministic mesh normalisation and GLB export.

Implements the "Mesh and asset normalisation" pass from ``docs/sculptor.md``:
validate, drop stray fragments, repair normals, put the asset on a stable origin,
and export a GLB that reopens.

The asset convention produced here is the one the doc specifies:

* up axis ``+Y``;
* origin at bottom-centre (ground contact);
* normalised to a one-unit longest edge by default, with the applied scale
  reported so the engine's original dimensions stay recoverable;
* canonical export GLB, with generated UVs and textures preserved.

Work happens on a ``trimesh.Scene`` rather than a single concatenated mesh
because concatenation collapses per-geometry materials, which would silently
destroy the texturing the product depends on.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import trimesh


class MeshError(Exception):
    """Base class for normalisation failures."""


class InvalidMesh(MeshError):
    """The engine produced nothing usable."""


class ExportFailed(MeshError):
    """The normalised asset could not be written or could not be reopened."""


@dataclass(frozen=True)
class NormalisedAsset:
    """Statistics describing the exported asset."""

    triangle_count: int
    vertex_count: int
    has_texture: bool
    applied_scale: float
    bounding_box_longest_edge: float
    removed_fragments: int
    #: Triangle count before decimation, or 0 if none was applied.
    simplified_from: int = 0
    #: Whether a dominant ground plane was found and used to stand the object
    #: upright. False means the mesh kept the engine's camera-frame orientation.
    ground_aligned: bool = False
    up_axis: str = "+Y"
    origin_convention: str = "bottomCentre"


def _as_scene(loaded: object) -> trimesh.Scene:
    if isinstance(loaded, trimesh.Scene):
        return loaded
    if isinstance(loaded, trimesh.Trimesh):
        return trimesh.Scene(loaded)
    raise InvalidMesh(f"unexpected geometry type from engine: {type(loaded).__name__}")


def _mesh_geometries(scene: trimesh.Scene) -> list[trimesh.Trimesh]:
    return [g for g in scene.geometry.values() if isinstance(g, trimesh.Trimesh)]


def _drop_small_fragments(mesh: trimesh.Trimesh, threshold: float) -> int:
    """Remove disconnected components far smaller than the main body.

    Faces are masked rather than the mesh being re-split, because
    ``update_faces``/``remove_unreferenced_vertices`` carry UVs and material
    assignments along with them, while re-splitting can drop them.

    Returns the number of components removed.
    """

    if threshold <= 0 or len(mesh.faces) == 0:
        return 0

    components = trimesh.graph.connected_components(
        mesh.face_adjacency, nodes=np.arange(len(mesh.faces))
    )
    if len(components) <= 1:
        return 0

    areas = mesh.area_faces
    component_areas = np.array([float(areas[c].sum()) for c in components])
    largest = component_areas.max()
    if largest <= 0:
        return 0

    keep = component_areas >= largest * threshold
    if keep.all():
        return 0

    keep_faces = np.zeros(len(mesh.faces), dtype=bool)
    for component, keeping in zip(components, keep):
        if keeping:
            keep_faces[component] = True

    if not keep_faces.any():
        return 0

    mesh.update_faces(keep_faces)
    mesh.remove_unreferenced_vertices()
    return int((~keep).sum())


#: A normal cluster must hold at least this share of total surface area before
#: it is trusted as the ground plane. Below it, the object has no obviously flat
#: base and rotating it would be guesswork.
GROUND_PLANE_AREA_SHARE = 0.15

#: Half-angle, in degrees, for grouping face normals into one planar cluster.
#: Wide because marching cubes stair-steps even a perfectly flat surface, which
#: scatters its normals: at 12 degrees a real base plate clusters only 3% of the
#: area, while the recovered axis is already stable. Widening recovers the area
#: without moving the axis.
GROUND_PLANE_TOLERANCE_DEGREES = 30.0


def find_up_axis(mesh: trimesh.Trimesh) -> "np.ndarray | None":
    """Estimate which way is up from the object's flattest, largest surface.

    Single-image reconstruction happens in the *input camera's* frame, so a
    subject photographed or rendered from above — every isometric Tiko Media
    asset, for one — comes out tilted by the camera's elevation. Nothing in the
    mesh is axis-aligned by construction, so "up" has to be recovered.

    Objects in this product's domain rest on something flat: a base plate, a
    plinth, the ground. That surface is normally the single largest planar
    region, which makes its normal a good estimate of the vertical axis.

    Returns a unit vector, or ``None`` when no plane is dominant enough to
    trust — a sphere or a cube, where rotating would be arbitrary.
    """

    if len(mesh.faces) == 0:
        return None

    normals = np.asarray(mesh.face_normals, dtype=np.float64)
    areas = np.asarray(mesh.area_faces, dtype=np.float64)
    total_area = float(areas.sum())
    if total_area <= 0 or not np.isfinite(normals).all():
        return None

    # Fold opposing normals together: the top and bottom of a base plate lie on
    # the same axis and should reinforce each other rather than compete.
    threshold = float(np.cos(np.radians(GROUND_PLANE_TOLERANCE_DEGREES)))

    # Test only the normals of the largest faces as candidate axes; the ground
    # plane is by definition made of large faces, so this finds it without an
    # expensive full clustering pass.
    candidate_count = min(len(areas), 400)
    candidates = np.argsort(areas)[::-1][:candidate_count]

    best_axis = None
    best_share = 0.0
    for index in candidates:
        axis = normals[index]
        alignment = np.abs(normals @ axis)
        share = float(areas[alignment >= threshold].sum()) / total_area
        if share > best_share:
            best_share = share
            best_axis = axis

    if best_axis is None or best_share < GROUND_PLANE_AREA_SHARE:
        return None

    # Refine: the wide tolerance that recovers the cluster also makes the seed
    # normal a coarse estimate. Re-fit from the cluster's area-weighted mean,
    # flipping members onto one side first so opposing faces of the same plate
    # reinforce rather than cancel.
    for _ in range(2):
        axis = best_axis / np.linalg.norm(best_axis)
        alignment = normals @ axis
        members = np.abs(alignment) >= threshold
        if not members.any():
            break
        signs = np.sign(alignment[members])
        signs[signs == 0] = 1.0
        weighted = (normals[members] * signs[:, None] * areas[members, None]).sum(axis=0)
        if np.linalg.norm(weighted) < 1e-9:
            break
        best_axis = weighted

    axis = best_axis / np.linalg.norm(best_axis)

    # Orient the axis so it points away from the base. The ground plane lies
    # below the object's centre of mass, so compare where the flat cluster sits
    # against where the surface as a whole sits, both along the axis and
    # weighted by area.
    centroids = np.asarray(mesh.triangles_center, dtype=np.float64) @ axis
    members = np.abs(normals @ axis) >= threshold
    plane_position = float(
        np.average(centroids[members], weights=areas[members])
    )
    object_position = float(np.average(centroids, weights=areas))
    if plane_position > object_position:
        axis = -axis
    return axis


def _rotation_bringing_to_y(axis: "np.ndarray") -> "np.ndarray":
    """4x4 rotation taking ``axis`` onto +Y by the shortest arc."""

    target = np.array([0.0, 1.0, 0.0])
    axis = axis / np.linalg.norm(axis)
    cross = np.cross(axis, target)
    dot = float(np.dot(axis, target))
    norm = float(np.linalg.norm(cross))

    transform = np.eye(4)
    if norm < 1e-9:
        if dot > 0:
            return transform
        # Already antiparallel: a half turn about any perpendicular axis.
        transform[:3, :3] = np.diag([1.0, -1.0, -1.0])
        return transform

    axis_of_rotation = cross / norm
    angle = float(np.arctan2(norm, dot))
    x, y, z = axis_of_rotation
    c, s = np.cos(angle), np.sin(angle)
    transform[:3, :3] = np.array(
        [
            [c + x * x * (1 - c), x * y * (1 - c) - z * s, x * z * (1 - c) + y * s],
            [y * x * (1 - c) + z * s, c + y * y * (1 - c), y * z * (1 - c) - x * s],
            [z * x * (1 - c) - y * s, z * y * (1 - c) + x * s, c + z * z * (1 - c)],
        ]
    )
    return transform


def smooth(mesh: trimesh.Trimesh, iterations: int) -> None:
    """Relax marching-cubes stair-stepping, in place.

    Taubin rather than plain Laplacian: Laplacian smoothing shrinks a mesh a
    little more with every pass, so a subject smooth enough to look good would
    also be visibly smaller and rounder than the image. Taubin alternates a
    positive and a negative pass, which removes the same high-frequency noise
    while holding the volume.

    Vertices move; the mesh keeps its topology, so per-vertex colour is
    untouched.
    """

    if iterations <= 0 or len(mesh.faces) == 0:
        return
    trimesh.smoothing.filter_taubin(mesh, iterations=iterations)


def simplify(mesh: trimesh.Trimesh, target_triangles: int) -> trimesh.Trimesh:
    """Reduce triangle count with quadric decimation.

    A 256-resolution isosurface produces a few hundred thousand triangles for
    what is often a simple shape — far more than a game engine or a map wants,
    and more than the detail actually justifies. Quadric decimation collapses
    edges cheapest-error-first, so flat regions lose density and silhouettes
    keep it.

    Returns the mesh unchanged when it is already at or below the target, or
    when the decimation backend is unavailable — a coarser model is worth
    having, but not at the cost of failing the generation.
    """

    if target_triangles <= 0 or len(mesh.faces) <= target_triangles:
        return mesh
    try:
        reduced = mesh.simplify_quadric_decimation(face_count=target_triangles)
    except Exception:
        return mesh
    if reduced is None or len(reduced.faces) == 0:
        return mesh

    _carry_vertex_colour(mesh, reduced)
    return reduced


def _carry_vertex_colour(source: trimesh.Trimesh, reduced: trimesh.Trimesh) -> None:
    """Copy per-vertex colour from ``source`` onto the decimated ``reduced``.

    Decimation returns geometry only — trimesh hands back a mesh with default
    grey, silently discarding the colour the engine worked out. Since decimation
    collapses edges, every surviving vertex sits on or very near an original
    one, so nearest-neighbour lookup restores the appearance faithfully.
    """

    visual = getattr(source, "visual", None)
    if not isinstance(visual, trimesh.visual.ColorVisuals):
        return
    colours = visual.vertex_colors
    if colours is None or len(colours) != len(source.vertices):
        return

    try:
        from scipy.spatial import cKDTree

        _, index = cKDTree(np.asarray(source.vertices)).query(
            np.asarray(reduced.vertices), k=1
        )
    except Exception:
        return

    reduced.visual = trimesh.visual.ColorVisuals(
        mesh=reduced, vertex_colors=np.asarray(colours)[index]
    )


def _has_texture(mesh: trimesh.Trimesh) -> bool:
    visual = getattr(mesh, "visual", None)
    if visual is None:
        return False
    if isinstance(visual, trimesh.visual.TextureVisuals):
        material = getattr(visual, "material", None)
        if material is None:
            return False
        if getattr(material, "image", None) is not None:
            return True
        return getattr(material, "baseColorTexture", None) is not None
    if isinstance(visual, trimesh.visual.ColorVisuals):
        return bool(getattr(visual, "vertex_colors", None) is not None)
    return False


def pitch_transform(degrees: float) -> "np.ndarray":
    """Rotation about +X that undoes a raised camera.

    Reconstruction happens in the input camera's frame, so a subject rendered
    from above comes out tilted back by the camera's elevation. Rotating by the
    negative of that elevation stands it up.
    """

    angle = np.radians(degrees)
    transform = np.eye(4)
    transform[:3, :3] = np.array(
        [
            [1.0, 0.0, 0.0],
            [0.0, np.cos(angle), -np.sin(angle)],
            [0.0, np.sin(angle), np.cos(angle)],
        ]
    )
    return transform


def normalise(
    scene_or_mesh: object,
    fragment_threshold: float = 0.02,
    normalise_scale: bool = True,
    pitch_correction: float = 0.0,
    align_ground: bool = False,
    smoothing_iterations: int = 0,
    target_triangles: int = 0,
) -> tuple[trimesh.Scene, NormalisedAsset]:
    """Clean and re-place the generated geometry.

    ``pitch_correction`` is the reliable way to fix orientation when the source
    camera's elevation is known: measured across the Tiko Media corpus, -60
    degrees stands those isometric renders upright.

    ``align_ground`` tries to recover the same thing from geometry alone, by
    finding the object's largest flat surface. It is **off by default** because
    it is not trustworthy: on this corpus the largest planar region is often the
    smooth back face the engine invents, not the base, so it corrected one asset
    and laid two others on their side. Prefer ``pitch_correction``.

    Returns the scene ready for export together with its statistics.
    """

    scene = _as_scene(scene_or_mesh)
    meshes = _mesh_geometries(scene)
    if not meshes:
        raise InvalidMesh("engine produced a scene with no mesh geometry")

    removed = 0
    simplified_from = 0
    for name, mesh in list(scene.geometry.items()):
        if not isinstance(mesh, trimesh.Trimesh) or len(mesh.faces) == 0:
            continue
        removed += _drop_small_fragments(mesh, fragment_threshold)

        # Decimate first, then smooth. It is tempting to argue the reverse —
        # that quadric decimation will treat marching-cubes terracing as real
        # geometry and preserve it — but measured on a real reconstruction the
        # two orders are visually identical, and this one comes out marginally
        # smoother (7.2 vs 7.9 degrees mean angle between adjacent faces) while
        # doing far less work, because smoothing then runs over 20k vertices
        # instead of 90k.
        #
        # What actually removes the terracing is the number of smoothing passes,
        # not the ordering.
        if target_triangles:
            before = len(mesh.faces)
            reduced = simplify(mesh, target_triangles)
            if reduced is not mesh:
                simplified_from += before
                scene.geometry[name] = reduced
                mesh = reduced

        smooth(mesh, smoothing_iterations)

        # Repairs winding order and recomputes normals; invalid normals are the
        # common cause of a model that renders inside-out in the preview.
        mesh.fix_normals()

    meshes = [m for m in _mesh_geometries(scene) if len(m.faces) > 0]
    if not meshes:
        raise InvalidMesh("no geometry left after fragment removal")

    total_triangles = sum(len(m.faces) for m in meshes)
    total_vertices = sum(len(m.vertices) for m in meshes)
    if total_triangles == 0:
        raise InvalidMesh("mesh contains no triangles")

    # Stand the object upright before measuring bounds, so the ground-plane and
    # bottom-centre placement below are computed in final orientation.
    if pitch_correction:
        scene.apply_transform(pitch_transform(pitch_correction))

    ground_aligned = False
    if align_ground:
        largest = max(meshes, key=lambda m: float(m.area_faces.sum()))
        up = find_up_axis(largest)
        if up is not None:
            scene.apply_transform(_rotation_bringing_to_y(up))
            ground_aligned = True

    bounds = scene.bounds
    if bounds is None or not np.isfinite(bounds).all():
        raise InvalidMesh("mesh has no finite bounding box")

    extents = bounds[1] - bounds[0]
    longest = float(extents.max())
    if longest <= 0:
        raise InvalidMesh("mesh bounding box is degenerate")

    scale = 1.0 / longest if normalise_scale else 1.0

    # Bottom-centre origin: centre X and Z on the bounding box, drop the lowest
    # point onto Y=0. Scale first so the translation lands in final units.
    centre = (bounds[0] + bounds[1]) / 2.0
    transform = np.eye(4)
    transform[0, 0] = transform[1, 1] = transform[2, 2] = scale
    transform[0, 3] = -centre[0] * scale
    transform[1, 3] = -bounds[0][1] * scale
    transform[2, 3] = -centre[2] * scale
    scene.apply_transform(transform)

    return scene, NormalisedAsset(
        triangle_count=total_triangles,
        vertex_count=total_vertices,
        has_texture=any(_has_texture(m) for m in meshes),
        applied_scale=scale,
        bounding_box_longest_edge=longest * scale,
        removed_fragments=removed,
        simplified_from=simplified_from,
        ground_aligned=ground_aligned,
    )


def export_glb(scene: trimesh.Scene, temporary: Path, destination: Path) -> Path:
    """Write the GLB to ``temporary``, verify it reopens, then commit it.

    Verifying before the move is what keeps the "no half-written destination"
    guarantee meaningful: a GLB that cannot be reloaded never reaches the
    user's chosen path.
    """

    temporary.parent.mkdir(parents=True, exist_ok=True)
    try:
        scene.export(file_obj=str(temporary), file_type="glb")
    except Exception as exc:  # trimesh raises a range of export errors
        raise ExportFailed(f"could not write GLB: {exc}") from exc

    if not temporary.is_file() or temporary.stat().st_size == 0:
        raise ExportFailed("GLB export produced an empty file")

    try:
        reopened = trimesh.load(str(temporary), file_type="glb", force="scene")
    except Exception as exc:
        raise ExportFailed(f"exported GLB could not be reopened: {exc}") from exc

    if not _mesh_geometries(_as_scene(reopened)):
        raise ExportFailed("exported GLB reopened with no mesh geometry")

    destination.parent.mkdir(parents=True, exist_ok=True)
    os.replace(temporary, destination)
    return destination


#: Formats the worker can write, mapped to the extension each one uses.
#:
#: GLB stays the canonical export. The rest exist because a generated asset
#: usually has somewhere else to go: OBJ for the widest tool compatibility,
#: STL for printing, PLY for anything reading raw per-vertex colour.
EXPORT_FORMATS = {
    "glb": ".glb",
    "obj": ".obj",
    "stl": ".stl",
    "ply": ".ply",
}

#: Formats that carry the per-vertex colour the engine produces.
#:
#: OBJ's own spec has no vertex colour; trimesh writes the widely-read
#: `v x y z r g b` extension, which Blender and MeshLab accept and some other
#: tools quietly ignore. STL has no colour at all, by design — it is geometry
#: for printing.
COLOUR_BEARING_FORMATS = frozenset({"glb", "ply", "obj"})


def export_mesh(
    scene: trimesh.Scene, destination: Path, file_format: str = "glb"
) -> Path:
    """Write the asset in ``file_format``, verifying it reopens.

    Same guarantee as :func:`export_glb`: written to a temporary name beside
    the destination, reopened to prove it is valid, then moved into place, so a
    failure cannot leave a half-written file where the user asked for an asset.
    """

    file_format = file_format.lower()
    if file_format not in EXPORT_FORMATS:
        raise ExportFailed(
            f"unsupported export format {file_format!r}; "
            f"expected one of {', '.join(sorted(EXPORT_FORMATS))}"
        )

    if file_format == "glb":
        return export_glb(
            scene,
            temporary=destination.with_suffix(destination.suffix + ".part"),
            destination=destination,
        )

    meshes = _mesh_geometries(scene)
    if not meshes:
        raise ExportFailed("no mesh geometry to export")
    # These formats hold a single mesh, so a multi-geometry scene is flattened.
    combined = meshes[0] if len(meshes) == 1 else trimesh.util.concatenate(meshes)

    temporary = destination.with_suffix(destination.suffix + ".part")
    temporary.parent.mkdir(parents=True, exist_ok=True)
    try:
        combined.export(file_obj=str(temporary), file_type=file_format)
    except Exception as exc:
        raise ExportFailed(f"could not write {file_format.upper()}: {exc}") from exc

    if not temporary.is_file() or temporary.stat().st_size == 0:
        raise ExportFailed(f"{file_format.upper()} export produced an empty file")

    try:
        reopened = trimesh.load(str(temporary), file_type=file_format)
    except Exception as exc:
        raise ExportFailed(
            f"exported {file_format.upper()} could not be reopened: {exc}"
        ) from exc
    if not len(getattr(reopened, "faces", ())):
        raise ExportFailed(
            f"exported {file_format.upper()} reopened with no geometry"
        )

    destination.parent.mkdir(parents=True, exist_ok=True)
    try:
        os.replace(temporary, destination)
    except OSError as exc:
        # The destination can be unwritable — occupied by a directory, on a
        # full or read-only volume. Clean up rather than leaving a stray
        # `.part` beside whatever the user was pointing at.
        temporary.unlink(missing_ok=True)
        raise ExportFailed(f"could not write {destination.name}: {exc}") from exc
    return destination


def export_preview(scene: trimesh.Scene, destination: Path) -> Path:
    """Write a viewer-compatible copy of the asset for the app's 3D preview.

    Apple's Model I/O — and therefore SceneKit and RealityKit's asset loading —
    does not read GLB. Rather than compromise the canonical export to suit the
    viewer, this is the preview adapter ``docs/sculptor.md`` asks for: the same
    geometry written as binary PLY, which Model I/O does read, with per-vertex
    colour preserved.

    The GLB remains the asset the user exports; this file is disposable.
    """

    meshes = _mesh_geometries(scene)
    if not meshes:
        raise ExportFailed("no mesh geometry to preview")

    # PLY holds a single mesh, so multi-geometry scenes are flattened. Vertex
    # colour survives concatenation; only material assignments are lost, and the
    # preview does not use them.
    combined = meshes[0] if len(meshes) == 1 else trimesh.util.concatenate(meshes)

    visual = getattr(combined, "visual", None)
    if visual is not None and not isinstance(visual, trimesh.visual.ColorVisuals):
        try:
            combined.visual = visual.to_color()
        except Exception:
            # Colour is a nicety here; geometry is the point.
            pass

    destination.parent.mkdir(parents=True, exist_ok=True)
    try:
        combined.export(file_obj=str(destination), file_type="ply")
    except Exception as exc:
        raise ExportFailed(f"could not write preview PLY: {exc}") from exc
    return destination
