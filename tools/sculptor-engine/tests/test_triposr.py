"""TripoSR's output convention.

The module imports torch lazily, so everything here runs without it.
"""

from __future__ import annotations

import numpy as np
import pytest
import trimesh

from sculptor_engine.engines import triposr


class TestUpAxisCorrection:
    """TripoSR does not emit a Y-up mesh; the engine fixes its own convention.

    This was the single largest defect found on the corpus: without it an
    eye-level animal reconstructs lying on its back, and every downstream
    assumption about "up" is wrong.
    """

    def test_correction_is_a_quarter_turn(self):
        assert triposr.UP_AXIS_CORRECTION_DEGREES == -90.0

    def test_stands_up_a_subject_whose_vertical_axis_is_z(self):
        # A "tall" subject as TripoSR emits it: the long axis along Z.
        mesh = trimesh.creation.box(extents=(2.0, 2.0, 9.0))

        triposr._to_y_up(mesh)

        extents = mesh.bounds[1] - mesh.bounds[0]
        assert extents[1] == pytest.approx(9.0, abs=1e-6), "long axis should be Y"
        assert extents[2] == pytest.approx(2.0, abs=1e-6)

    def test_leaves_the_left_right_axis_alone(self):
        # A pitch about X must not mirror or swap the subject's width.
        mesh = trimesh.creation.box(extents=(7.0, 1.0, 3.0))
        triposr._to_y_up(mesh)
        assert (mesh.bounds[1] - mesh.bounds[0])[0] == pytest.approx(7.0, abs=1e-6)

    def test_is_a_rigid_motion(self):
        # Volume and face count must survive; this is a rotation, not a remesh.
        mesh = trimesh.creation.icosphere(subdivisions=2, radius=1.5)
        before_volume = mesh.volume
        before_faces = len(mesh.faces)

        triposr._to_y_up(mesh)

        assert mesh.volume == pytest.approx(before_volume, rel=1e-9)
        assert len(mesh.faces) == before_faces

    def test_composes_with_the_camera_elevation(self):
        """Engine convention and camera angle are separate corrections.

        A steep isometric render needed -60 degrees overall, which is this
        -90 plus roughly +30 of camera elevation. Applying them in sequence
        must reproduce that, or the two controls are fighting each other.
        """

        from sculptor_engine import meshnorm

        engine_frame = trimesh.creation.box(extents=(2.0, 2.0, 9.0))
        combined = engine_frame.copy()
        triposr._to_y_up(combined)
        combined.apply_transform(meshnorm.pitch_transform(30.0))

        direct = engine_frame.copy()
        direct.apply_transform(meshnorm.pitch_transform(-60.0))

        assert np.allclose(combined.bounds, direct.bounds, atol=1e-6)
