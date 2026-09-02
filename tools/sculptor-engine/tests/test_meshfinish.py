"""Smoothing, simplification and the extra export formats.

Colour preservation is checked by *value* throughout, not by presence. An
earlier version of this suite only asserted that a colour array existed and the
right length, which passed while decimation was silently replacing every colour
with trimesh's default grey — the models came out correct-shaped and colourless.
"""

from __future__ import annotations

import numpy as np
import pytest
import trimesh

from sculptor_engine import meshnorm


def coloured_sphere(subdivisions: int = 4) -> trimesh.Trimesh:
    """A sphere with a position-dependent colour per vertex.

    Varying colour matters: a uniformly coloured mesh cannot tell "colour was
    carried across" apart from "colour was replaced by a constant".
    """

    mesh = trimesh.creation.icosphere(subdivisions=subdivisions, radius=1.0)
    points = np.asarray(mesh.vertices)
    normalised = (points - points.min(axis=0)) / np.ptp(points, axis=0)
    colours = np.hstack(
        [(normalised * 255).astype(np.uint8), np.full((len(points), 1), 255, np.uint8)]
    )
    mesh.visual.vertex_colors = colours
    return mesh


def unique_colours(mesh: trimesh.Trimesh) -> int:
    visual = mesh.visual
    if not isinstance(visual, trimesh.visual.ColorVisuals):
        return 0
    return len(np.unique(np.asarray(visual.vertex_colors)[:, :3], axis=0))


class TestSmoothing:
    def test_relaxes_a_jagged_surface(self):
        mesh = trimesh.creation.icosphere(subdivisions=3, radius=1.0)
        rng = np.random.default_rng(0)
        mesh.vertices += rng.normal(scale=0.05, size=mesh.vertices.shape)

        def roughness(m):
            # Spread of vertex distance from centre: a sphere with noise on it
            # has a wide spread, a smooth one a narrow spread.
            return float(np.std(np.linalg.norm(m.vertices - m.vertices.mean(axis=0), axis=1)))

        before = roughness(mesh)
        meshnorm.smooth(mesh, iterations=10)
        assert roughness(mesh) < before * 0.6

    def test_holds_its_volume(self):
        # Taubin rather than Laplacian precisely so a smooth model is not also
        # a visibly shrunken one.
        mesh = trimesh.creation.icosphere(subdivisions=4, radius=1.0)
        before = mesh.volume
        meshnorm.smooth(mesh, iterations=12)
        assert mesh.volume == pytest.approx(before, rel=0.08)

    def test_zero_iterations_changes_nothing(self):
        mesh = trimesh.creation.icosphere(subdivisions=2)
        before = mesh.vertices.copy()
        meshnorm.smooth(mesh, iterations=0)
        assert np.allclose(mesh.vertices, before)

    def test_keeps_vertex_colour(self):
        # Smoothing moves vertices but keeps topology, so colour must survive
        # untouched rather than merely still exist.
        mesh = coloured_sphere()
        before = np.asarray(mesh.visual.vertex_colors).copy()
        meshnorm.smooth(mesh, iterations=6)
        assert np.array_equal(np.asarray(mesh.visual.vertex_colors), before)


class TestSimplification:
    def test_reduces_towards_the_target(self):
        mesh = coloured_sphere(subdivisions=5)
        reduced = meshnorm.simplify(mesh, target_triangles=2000)
        assert len(reduced.faces) < len(mesh.faces)
        assert len(reduced.faces) <= 2600, "should land near the requested count"

    def test_leaves_a_mesh_that_is_already_small_enough(self):
        mesh = trimesh.creation.box()
        assert meshnorm.simplify(mesh, target_triangles=10_000) is mesh

    def test_zero_target_disables_it(self):
        mesh = coloured_sphere(subdivisions=4)
        assert meshnorm.simplify(mesh, target_triangles=0) is mesh

    def test_carries_vertex_colour_across(self):
        """The bug this whole module exists for.

        trimesh's decimation returns geometry only, handing back default grey.
        Checking that *a* colour array exists is not enough — it does, and it
        is wrong. Check the colours are still varied and still resemble the
        original at the same location.
        """

        mesh = coloured_sphere(subdivisions=5)
        reduced = meshnorm.simplify(mesh, target_triangles=2000)

        # Compare against what the *reduced* mesh could hold: colour is
        # position-dependent, so a faithful carry gives nearly one distinct
        # colour per surviving vertex. Collapsing to grey gives one.
        assert unique_colours(reduced) > len(reduced.vertices) * 0.5, (
            "decimation collapsed the colours to near-uniform"
        )

        # Colour is position-dependent, so a surviving vertex should carry
        # roughly the colour its position had before.
        from scipy.spatial import cKDTree

        _, index = cKDTree(np.asarray(mesh.vertices)).query(
            np.asarray(reduced.vertices), k=1
        )
        expected = np.asarray(mesh.visual.vertex_colors)[index][:, :3].astype(int)
        actual = np.asarray(reduced.visual.vertex_colors)[:, :3].astype(int)
        assert np.abs(expected - actual).mean() < 3

    def test_survives_a_backend_that_is_unavailable(self, monkeypatch):
        # A coarser model is worth having; failing the generation is not.
        mesh = coloured_sphere(subdivisions=4)

        def explode(*args, **kwargs):
            raise RuntimeError("no decimation backend")

        monkeypatch.setattr(
            type(mesh), "simplify_quadric_decimation", explode, raising=False
        )
        assert meshnorm.simplify(mesh, target_triangles=100) is mesh


class TestNormaliseIntegration:
    def test_smooths_and_simplifies_through_normalise(self):
        mesh = coloured_sphere(subdivisions=5)
        before = len(mesh.faces)

        scene, asset = meshnorm.normalise(
            mesh, smoothing_iterations=5, target_triangles=1500
        )

        assert asset.triangle_count < before
        assert asset.simplified_from == before
        assert asset.has_texture, "colour must survive the whole pass"

    def test_reports_nothing_simplified_when_it_was_not(self):
        _, asset = meshnorm.normalise(trimesh.creation.box(), target_triangles=0)
        assert asset.simplified_from == 0


class TestExportFormats:
    @pytest.mark.parametrize("file_format", sorted(meshnorm.EXPORT_FORMATS))
    def test_writes_and_reopens_every_supported_format(self, file_format, tmp_path):
        scene, _ = meshnorm.normalise(coloured_sphere(subdivisions=3))
        destination = tmp_path / f"model{meshnorm.EXPORT_FORMATS[file_format]}"

        written = meshnorm.export_mesh(scene, destination, file_format)

        assert written.is_file() and written.stat().st_size > 0
        reopened = trimesh.load(str(written), force="mesh")
        assert len(reopened.faces) > 0

    def test_obj_and_ply_keep_colour(self, tmp_path):
        # STL has no colour by design; GLB, PLY and OBJ all carry it.
        scene, _ = meshnorm.normalise(coloured_sphere(subdivisions=3))
        for file_format in ("ply", "obj"):
            written = meshnorm.export_mesh(
                scene, tmp_path / f"m{meshnorm.EXPORT_FORMATS[file_format]}", file_format
            )
            reopened = trimesh.load(str(written), force="mesh")
            assert unique_colours(reopened) > 10, f"{file_format} lost its colour"

    def test_rejects_an_unknown_format(self, tmp_path):
        scene, _ = meshnorm.normalise(trimesh.creation.box())
        with pytest.raises(meshnorm.ExportFailed, match="unsupported export format"):
            meshnorm.export_mesh(scene, tmp_path / "m.xyz", "xyz")

    def test_leaves_no_partial_file_behind(self, tmp_path):
        scene, _ = meshnorm.normalise(trimesh.creation.box())
        blocked = tmp_path / "model.obj"
        blocked.mkdir()  # a directory where the file must go

        with pytest.raises(meshnorm.ExportFailed):
            meshnorm.export_mesh(scene, blocked, "obj")

        assert not (tmp_path / "model.obj.part").exists()
