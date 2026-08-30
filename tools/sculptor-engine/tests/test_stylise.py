"""Flattening sampled colour into a small painted palette."""

from __future__ import annotations

import numpy as np
import pytest
import trimesh

from sculptor_engine import meshnorm, stylise


def photographic_sphere(subdivisions: int = 4) -> trimesh.Trimesh:
    """A mesh coloured like a reconstruction: two regions, plus noise.

    The noise is the point. A real model's colour is sampled from a photograph,
    so nominally flat regions arrive as thousands of near-identical shades.
    """

    mesh = trimesh.creation.icosphere(subdivisions=subdivisions, radius=1.0)
    points = np.asarray(mesh.vertices)
    rng = np.random.default_rng(0)

    base = np.where(
        (points[:, 1] > 0)[:, None],
        np.array([220.0, 60.0, 50.0]),
        np.array([40.0, 70.0, 200.0]),
    )
    noisy = np.clip(base + rng.normal(scale=6.0, size=base.shape), 0, 255)
    mesh.visual.vertex_colors = np.hstack(
        [noisy.astype(np.uint8), np.full((len(points), 1), 255, np.uint8)]
    )
    return mesh


def face_colour_count(mesh: trimesh.Trimesh) -> int:
    colours = getattr(mesh.visual, "face_colors", None)
    if colours is None:
        return 0
    return len(np.unique(np.asarray(colours)[:, :3], axis=0))


class TestPalette:
    def test_collapses_thousands_of_shades_to_the_requested_few(self):
        mesh = photographic_sphere()
        assert stylise.flatten_colour(mesh, palette_size=6)
        assert face_colour_count(mesh) <= 6

    def test_keeps_regions_that_are_genuinely_different(self):
        # Two clearly separate colours must not merge into one average.
        mesh = photographic_sphere()
        stylise.flatten_colour(mesh, palette_size=4)

        colours = np.unique(np.asarray(mesh.visual.face_colors)[:, :3], axis=0)
        reddish = [c for c in colours if c[0] > c[2]]
        bluish = [c for c in colours if c[2] > c[0]]
        assert reddish and bluish, f"palette lost a region: {colours}"

    def test_is_deterministic(self):
        first, second = photographic_sphere(), photographic_sphere()
        stylise.flatten_colour(first, palette_size=6)
        stylise.flatten_colour(second, palette_size=6)
        assert np.array_equal(
            np.asarray(first.visual.face_colors), np.asarray(second.visual.face_colors)
        )

    def test_paints_faces_not_vertices(self):
        # Per-vertex colour is interpolated across a triangle, which is the
        # gradient this exists to remove.
        mesh = photographic_sphere()
        stylise.flatten_colour(mesh, palette_size=5)
        assert getattr(mesh.visual, "face_colors", None) is not None
        assert len(mesh.visual.face_colors) == len(mesh.faces)

    def test_never_moves_the_surface(self):
        """Colour changes; shape does not.

        Splitting shared vertices re-indexes the mesh — the vertex array grows
        to three per face — so this checks the surface itself is unchanged
        rather than comparing arrays that are legitimately different.
        """

        mesh = photographic_sphere()
        before_faces = len(mesh.faces)
        before_bounds = np.asarray(mesh.bounds).copy()
        before_volume = mesh.volume
        before_positions = {tuple(p) for p in np.round(mesh.vertices, 9)}

        stylise.flatten_colour(mesh, palette_size=6)

        assert len(mesh.faces) == before_faces
        assert np.allclose(mesh.bounds, before_bounds)
        assert mesh.volume == pytest.approx(before_volume, rel=1e-9)
        after_positions = {tuple(p) for p in np.round(mesh.vertices, 9)}
        assert after_positions == before_positions, "a vertex position changed"

    @pytest.mark.parametrize("size", [0, 1, -3])
    def test_declines_a_palette_too_small_to_mean_anything(self, size):
        mesh = photographic_sphere()
        assert stylise.flatten_colour(mesh, palette_size=size) is False

    def test_a_uniformly_coloured_mesh_stays_uniform(self):
        # trimesh gives an uncoloured mesh a single default colour, so this is
        # a no-op in effect. What matters is that it neither crashes nor
        # invents variety that was not there.
        mesh = trimesh.creation.box()
        stylise.flatten_colour(mesh, palette_size=6)
        assert face_colour_count(mesh) <= 1

    def test_handles_geometry_with_no_faces(self):
        empty = trimesh.Trimesh(vertices=np.zeros((3, 3)), faces=np.zeros((0, 3), int))
        assert stylise.flatten_colour(empty, palette_size=6) is False

    def test_never_paints_a_region_black_from_an_empty_cluster(self):
        # k-means can return an all-zero centroid for a cluster nothing landed
        # in; using it would paint part of the model black.
        mesh = photographic_sphere()
        stylise.flatten_colour(mesh, palette_size=32)
        colours = np.asarray(mesh.visual.face_colors)[:, :3]
        assert colours.sum(axis=1).min() > 0


class TestThroughNormalise:
    def test_flattens_as_part_of_the_pass(self):
        _, asset = meshnorm.normalise(photographic_sphere(), palette_colours=8)
        assert asset.palette_flattened is True

    def test_off_by_request(self):
        _, asset = meshnorm.normalise(photographic_sphere(), palette_colours=0)
        assert asset.palette_flattened is False

    def test_survives_export_and_reload(self, tmp_path):
        scene, _ = meshnorm.normalise(photographic_sphere(), palette_colours=6)
        written = meshnorm.export_mesh(scene, tmp_path / "m.glb", "glb")

        reopened = trimesh.load(str(written), file_type="glb", force="mesh")
        colours = reopened.visual.vertex_colors
        # GLB stores colour per vertex, so a flat-painted mesh comes back with
        # more entries than palette slots — but still only a handful of values.
        assert len(np.unique(np.asarray(colours)[:, :3], axis=0)) <= 12
