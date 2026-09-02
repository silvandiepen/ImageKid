"""Mesh normalisation and GLB export."""

from __future__ import annotations

import numpy as np
import pytest
import trimesh

from sculptor_engine import meshnorm
from sculptor_engine.meshnorm import ExportFailed, InvalidMesh


def box_at(centre, extents=(1.0, 1.0, 1.0)) -> trimesh.Trimesh:
    mesh = trimesh.creation.box(extents=extents)
    mesh.apply_translation(np.asarray(centre, dtype=float))
    return mesh


class TestNormalise:
    def test_rejects_geometry_with_no_meshes(self):
        with pytest.raises(InvalidMesh):
            meshnorm.normalise(trimesh.Scene())

    def test_rejects_an_unexpected_type(self):
        with pytest.raises(InvalidMesh):
            meshnorm.normalise("not geometry")

    def test_places_the_asset_on_the_ground_plane(self):
        scene, _ = meshnorm.normalise(box_at((5.0, 9.0, -3.0), (2.0, 2.0, 2.0)))
        bounds = scene.bounds
        assert bounds[0][1] == pytest.approx(0.0, abs=1e-6)

    def test_centres_the_asset_on_x_and_z(self):
        scene, _ = meshnorm.normalise(box_at((5.0, 9.0, -3.0), (2.0, 4.0, 2.0)))
        bounds = scene.bounds
        centre_x = (bounds[0][0] + bounds[1][0]) / 2
        centre_z = (bounds[0][2] + bounds[1][2]) / 2
        assert centre_x == pytest.approx(0.0, abs=1e-6)
        assert centre_z == pytest.approx(0.0, abs=1e-6)

    def test_normalises_the_longest_edge_to_one_unit(self):
        scene, asset = meshnorm.normalise(box_at((0, 0, 0), (4.0, 8.0, 2.0)))
        extents = scene.bounds[1] - scene.bounds[0]
        assert float(extents.max()) == pytest.approx(1.0, abs=1e-6)
        assert asset.applied_scale == pytest.approx(1 / 8.0)
        assert asset.bounding_box_longest_edge == pytest.approx(1.0)

    def test_can_preserve_original_scale(self):
        _, asset = meshnorm.normalise(
            box_at((0, 0, 0), (4.0, 8.0, 2.0)), normalise_scale=False
        )
        assert asset.applied_scale == pytest.approx(1.0)
        assert asset.bounding_box_longest_edge == pytest.approx(8.0)

    def test_reports_the_asset_convention(self):
        _, asset = meshnorm.normalise(box_at((0, 0, 0)))
        assert asset.up_axis == "+Y"
        assert asset.origin_convention == "bottomCentre"

    def test_counts_triangles_and_vertices(self):
        _, asset = meshnorm.normalise(box_at((0, 0, 0)))
        assert asset.triangle_count == 12
        assert asset.vertex_count > 0


class TestFragmentRemoval:
    def test_removes_a_tiny_disconnected_speck(self):
        body = box_at((0, 0, 0), (10.0, 10.0, 10.0))
        speck = box_at((40.0, 0, 0), (0.2, 0.2, 0.2))
        combined = trimesh.util.concatenate([body, speck])

        _, asset = meshnorm.normalise(combined, fragment_threshold=0.02)

        assert asset.removed_fragments == 1
        # Only the main body remains, so the bounds are no longer stretched by
        # the speck sitting 40 units away.
        assert asset.triangle_count == 12

    def test_keeps_comparable_components(self):
        # Two halves of a real object must both survive.
        left = box_at((-6.0, 0, 0), (5.0, 5.0, 5.0))
        right = box_at((6.0, 0, 0), (5.0, 5.0, 5.0))
        combined = trimesh.util.concatenate([left, right])

        _, asset = meshnorm.normalise(combined, fragment_threshold=0.02)

        assert asset.removed_fragments == 0
        assert asset.triangle_count == 24

    def test_threshold_of_zero_disables_removal(self):
        body = box_at((0, 0, 0), (10.0, 10.0, 10.0))
        speck = box_at((40.0, 0, 0), (0.1, 0.1, 0.1))
        combined = trimesh.util.concatenate([body, speck])

        _, asset = meshnorm.normalise(combined, fragment_threshold=0.0)

        assert asset.removed_fragments == 0
        assert asset.triangle_count == 24


class TestGroundAlignment:
    """Single-image reconstruction happens in the input camera's frame, so a
    subject rendered from above comes out tilted. These cover recovering "up"
    from the object's own flat base."""

    @staticmethod
    def plated_object(tilt_degrees: float) -> trimesh.Trimesh:
        """A wide flat base plate with a smaller block on top, then tilted.

        This is the shape of every isometric Tiko Media asset: a diorama.
        """

        plate = trimesh.creation.box(extents=(10.0, 0.6, 10.0))
        tower = trimesh.creation.box(extents=(3.0, 4.0, 3.0))
        tower.apply_translation([0.0, 2.3, 0.0])
        mesh = trimesh.util.concatenate([plate, tower])
        if tilt_degrees:
            angle = np.radians(tilt_degrees)
            rotation = trimesh.transformations.rotation_matrix(angle, [1, 0, 0])
            mesh.apply_transform(rotation)
        return mesh

    def test_recovers_up_from_a_tilted_base_plate(self):
        mesh = self.plated_object(tilt_degrees=55.0)
        up = meshnorm.find_up_axis(mesh)
        assert up is not None
        # The plate's normal was +Y before the tilt; find it again.
        expected = trimesh.transformations.rotation_matrix(
            np.radians(55.0), [1, 0, 0]
        )[:3, :3] @ np.array([0.0, 1.0, 0.0])
        assert float(np.dot(up, expected)) > 0.98

    def test_up_points_away_from_the_base_not_into_it(self):
        # The block sits on top, so "up" must be the side the mass is on.
        mesh = self.plated_object(tilt_degrees=0.0)
        up = meshnorm.find_up_axis(mesh)
        assert up is not None
        assert up[1] > 0.9

    def test_normalise_stands_a_tilted_diorama_upright(self):
        scene, asset = meshnorm.normalise(
            self.plated_object(tilt_degrees=55.0), align_ground=True
        )
        assert asset.ground_aligned is True

        # Upright means the plate is horizontal: the object is far wider than
        # it is tall, and its base sits on Y=0.
        extents = scene.bounds[1] - scene.bounds[0]
        assert extents[1] < extents[0] * 0.6
        assert scene.bounds[0][1] == pytest.approx(0.0, abs=1e-6)

    def test_declines_to_rotate_a_shape_with_no_dominant_plane(self):
        # A sphere has no base to align to; guessing would be worse than
        # leaving the engine's orientation alone.
        sphere = trimesh.creation.icosphere(subdivisions=3, radius=1.0)
        assert meshnorm.find_up_axis(sphere) is None
        _, asset = meshnorm.normalise(sphere, align_ground=True)
        assert asset.ground_aligned is False

    def test_ground_alignment_is_off_by_default(self):
        # It is a guess that proved unreliable on real reconstructions, where
        # the largest flat region is often the invented back face.
        _, asset = meshnorm.normalise(self.plated_object(tilt_degrees=55.0))
        assert asset.ground_aligned is False


class TestPitchCorrection:
    """The reliable orientation fix when the source camera angle is known."""

    @staticmethod
    def tilted_tower(tilt_degrees: float) -> trimesh.Trimesh:
        """A tall block tipped back, as a raised camera would reconstruct it."""

        mesh = trimesh.creation.box(extents=(2.0, 8.0, 2.0))
        rotation = trimesh.transformations.rotation_matrix(
            np.radians(tilt_degrees), [1, 0, 0]
        )
        mesh.apply_transform(rotation)
        return mesh

    def test_undoes_a_known_camera_elevation(self):
        scene, _ = meshnorm.normalise(
            self.tilted_tower(60.0), pitch_correction=-60.0, normalise_scale=False
        )
        extents = scene.bounds[1] - scene.bounds[0]
        # Upright again: the 8-unit axis is vertical, the 2-unit ones are not.
        assert extents[1] == pytest.approx(8.0, abs=1e-4)
        assert extents[0] == pytest.approx(2.0, abs=1e-4)

    def test_zero_is_a_no_op(self):
        upright = trimesh.creation.box(extents=(2.0, 8.0, 2.0))
        without, _ = meshnorm.normalise(upright.copy(), normalise_scale=False)
        with_zero, _ = meshnorm.normalise(
            upright.copy(), pitch_correction=0.0, normalise_scale=False
        )
        assert np.allclose(without.bounds, with_zero.bounds)

    def test_still_lands_on_the_ground_plane_after_correction(self):
        scene, _ = meshnorm.normalise(
            self.tilted_tower(60.0), pitch_correction=-60.0
        )
        assert scene.bounds[0][1] == pytest.approx(0.0, abs=1e-6)


class TestPreviewExport:
    """Apple's Model I/O cannot read GLB, so the app previews a PLY copy."""

    def test_writes_a_ply_that_reopens_with_the_same_triangles(self, tmp_path):
        scene, asset = meshnorm.normalise(box_at((0, 0, 0)))
        preview = meshnorm.export_preview(scene, tmp_path / "preview.ply")

        assert preview.stat().st_size > 0
        reopened = trimesh.load(str(preview), file_type="ply")
        assert len(reopened.faces) == asset.triangle_count

    def test_preserves_vertex_colour(self, tmp_path):
        mesh = box_at((0, 0, 0))
        mesh.visual.vertex_colors = np.tile(
            np.array([[200, 40, 60, 255]], dtype=np.uint8), (len(mesh.vertices), 1)
        )
        scene, _ = meshnorm.normalise(mesh)

        preview = meshnorm.export_preview(scene, tmp_path / "preview.ply")
        reopened = trimesh.load(str(preview), file_type="ply")

        colours = np.asarray(reopened.visual.vertex_colors)[:, :3]
        assert (colours == np.array([200, 40, 60])).all()

    def test_leaves_the_canonical_glb_untouched(self, tmp_path):
        scene, _ = meshnorm.normalise(box_at((0, 0, 0)))
        glb = tmp_path / "model.glb"
        meshnorm.export_glb(scene, tmp_path / "t.part", glb)
        before = glb.read_bytes()

        meshnorm.export_preview(scene, tmp_path / "preview.ply")

        assert glb.read_bytes() == before


class TestExport:
    def test_writes_a_glb_that_reopens_with_geometry(self, tmp_path):
        scene, _ = meshnorm.normalise(box_at((1.0, 2.0, 3.0)))
        destination = tmp_path / "out" / "model.glb"

        written = meshnorm.export_glb(
            scene, temporary=tmp_path / "model.glb.part", destination=destination
        )

        assert written == destination
        assert destination.stat().st_size > 0
        reopened = trimesh.load(str(destination), file_type="glb", force="scene")
        assert len(reopened.geometry) == 1

    def test_export_preserves_the_ground_plane_convention(self, tmp_path):
        scene, _ = meshnorm.normalise(box_at((5.0, 5.0, 5.0), (3.0, 1.0, 2.0)))
        destination = tmp_path / "model.glb"
        meshnorm.export_glb(scene, tmp_path / "t.part", destination)

        reopened = trimesh.load(str(destination), file_type="glb", force="scene")
        assert reopened.bounds[0][1] == pytest.approx(0.0, abs=1e-5)

    def test_leaves_no_destination_file_when_export_fails(self, tmp_path):
        destination = tmp_path / "model.glb"
        # A directory where the temporary file must go: writing fails, and the
        # "no half-written destination" guarantee must still hold.
        temporary = tmp_path / "blocked"
        temporary.mkdir()

        scene, _ = meshnorm.normalise(box_at((0, 0, 0)))
        with pytest.raises(ExportFailed):
            meshnorm.export_glb(scene, temporary=temporary, destination=destination)

        assert not destination.exists()

    def test_temporary_file_is_removed_from_its_staging_name(self, tmp_path):
        scene, _ = meshnorm.normalise(box_at((0, 0, 0)))
        temporary = tmp_path / "model.glb.part"
        destination = tmp_path / "model.glb"

        meshnorm.export_glb(scene, temporary=temporary, destination=destination)

        assert not temporary.exists()
        assert destination.exists()
