"""Fusing several reconstructions into one model.

Two claims carry the design, and most of these check one or the other:

* a view adds what only it could see, and no other view can veto it;
* a view's *outline* does veto, because an outline is measured where depth is
  inferred.

Both were arrived at by measuring against a known object rather than by
argument — the alternatives are recorded in ``multiview.align``.
"""

from __future__ import annotations

import numpy as np
import pytest
import trimesh

from sculptor_engine import multiview


pytest.importorskip("torchmcubes", reason="fusion needs a surface extractor")


def sphere() -> trimesh.Trimesh:
    return trimesh.creation.icosphere(subdivisions=3, radius=1.0)


def bump_at(offset) -> trimesh.Trimesh:
    """A lump on the surface, big enough to survive a 160-cell grid."""

    box = trimesh.creation.box(extents=(0.6, 0.6, 0.6))
    box.apply_translation(offset)
    return box


def as_seen_from(mesh: trimesh.Trimesh, yaw: float) -> trimesh.Trimesh:
    """The same object expressed in the camera's frame.

    A reconstruction always comes back facing its own camera, so this is what
    the engine would hand us for a camera at ``yaw``.
    """

    turned = mesh.copy()
    turned.apply_transform(multiview.turn(-yaw))
    return turned


def as_seen_overhead(mesh: trimesh.Trimesh, yaw: float = 0.0) -> trimesh.Trimesh:
    """What the engine would return for a camera directly above."""

    turned = mesh.copy()
    turned.apply_transform(
        np.linalg.inv(multiview.turn(yaw) @ multiview.tilt(90.0))
    )
    return turned


def facing(yaw: float, distance: float = 1.0) -> np.ndarray:
    """A point out in front of the camera at ``yaw``.

    Written in terms of the module's own camera geometry rather than a literal
    axis, so these tests keep meaning what they say if the measured camera axis
    is ever revised.
    """

    return multiview.camera_direction(yaw) * distance


def occupied(mesh: trimesh.Trimesh, point) -> bool:
    """Whether a point falls inside a mesh.

    Voxelised rather than ``mesh.contains``, which wants an r-tree the runtime
    does not ship.
    """

    solid = mesh.voxelized(pitch=0.04).fill()
    return bool(solid.is_filled(np.array([point]))[0])


def long_subject() -> trimesh.Trimesh:
    """A body extended along the first view's line of sight.

    Symmetric about the centre, so the reconciliation in ``align`` has nothing
    to shift and the test can name absolute positions.
    """

    return trimesh.util.concatenate(
        [sphere(), bump_at(facing(0.0, 1.2)), bump_at(facing(0.0, -1.2))]
    )


class TestEveryViewAdds:
    def test_a_view_that_could_not_see_the_length_does_not_shorten_it(self):
        """The whole point. A subject photographed end-on tells you nothing
        about how long it is: the engine returns a blob, because its outline
        genuinely is round. The view that could see the length has to win."""

        end_on = sphere()

        fused = multiview.fuse([
            multiview.View(mesh=end_on, yaw=0.0),
            multiview.View(mesh=as_seen_from(long_subject(), 90.0), yaw=90.0),
        ])

        assert occupied(fused, facing(0.0, 1.2)), "the measured length was lost"
        assert occupied(fused, facing(0.0, -1.2))
        assert not occupied(end_on, facing(0.0, 1.2)), "the end-on view never had it"

    def test_a_majority_of_uninformative_views_cannot_veto_one_that_saw(self):
        # Two views agreeing on nothing useful must not outvote the one view
        # with the evidence. Averaging occupancy would let them.
        fused = multiview.fuse([
            multiview.View(mesh=sphere(), yaw=0.0),
            multiview.View(mesh=as_seen_from(long_subject(), 90.0), yaw=90.0),
            multiview.View(mesh=as_seen_from(sphere(), 180.0), yaw=180.0),
        ])

        assert occupied(fused, facing(0.0, 1.2))

    def test_the_shared_body_is_kept(self):
        # Both views agree about the sphere itself, so it must come through at
        # roughly the right size rather than eroded by the blend.
        fused = multiview.fuse([
            multiview.View(mesh=sphere(), yaw=0.0),
            multiview.View(mesh=sphere(), yaw=90.0),
        ])
        assert occupied(fused, (0, 0, 0))
        assert fused.extents == pytest.approx(np.full(3, 2.0), abs=0.15)


class TestEveryOutlineVetoes:
    def test_depth_one_view_invented_is_carved_away_by_another(self):
        """The failure mode a single image cannot avoid: made-up depth.

        A lump pointing straight at its own camera is invisible in that view's
        outline — it is exactly the thing that view had to guess. A second
        camera looking from the side sees no such lump in its outline, and that
        outline removes it.
        """

        lump = facing(0.0, 1.4)
        hallucinated = trimesh.util.concatenate([sphere(), bump_at(lump)])

        fused = multiview.fuse([
            multiview.View(mesh=hallucinated, yaw=0.0),
            multiview.View(mesh=as_seen_from(sphere(), 90.0), yaw=90.0),
        ])

        assert not occupied(fused, lump)
        assert occupied(fused, (0, 0, 0)), "the body itself must survive"

    def test_an_outline_is_taken_from_the_direction_the_camera_looked(self):
        # A tall fin is inside the outline seen end-on and outside it seen from
        # the side, so which direction the outline is taken from decides
        # whether it survives at all.
        bounds = np.array([[-1.5, -1.5, -1.5], [1.5, 1.5, 1.5]])
        flat = trimesh.creation.box(extents=(2.4, 2.4, 0.3))

        head_on = multiview._silhouette(flat, np.array([0.0, 0.0, 1.0]), bounds, 48)
        edge_on = multiview._silhouette(flat, np.array([1.0, 0.0, 0.0]), bounds, 48)

        assert head_on.mean() > edge_on.mean() * 2


class TestAlignment:
    def test_a_view_is_turned_back_to_where_its_camera_was(self):
        """The sign of the rotation, which is easy to get backwards.

        A lump on the object's right is seen by the 90° camera as a lump
        straight ahead. Aligned, it must return to the right — not the left.
        """

        lump = facing(90.0)
        truth = trimesh.util.concatenate([sphere(), bump_at(lump)])
        aligned = multiview.align([
            multiview.View(mesh=sphere(), yaw=0.0),
            multiview.View(mesh=as_seen_from(truth, 90.0), yaw=90.0),
        ])

        # Measured from the mesh's own middle, since aligning also recentres:
        # the lump is the part furthest from it, and it must lie the way the
        # 90° camera was looking.
        points = np.asarray(aligned[1].vertices)
        middle = points.mean(axis=0)
        furthest = points[np.linalg.norm(points - middle, axis=1).argmax()]
        assert (furthest - middle) @ multiview.camera_direction(90.0) > 0.5

    def test_views_are_brought_to_a_common_size(self):
        """Each reconstruction fills its own box, so the views disagree on size.

        Height is the one dimension every view of an upright object shares, and
        reconciling by it is what makes the outlines line up at all.
        """

        small = sphere()
        small.apply_scale(0.4)

        aligned = multiview.align([
            multiview.View(mesh=sphere(), yaw=0.0),
            multiview.View(mesh=small, yaw=90.0),
        ])

        assert aligned[1].extents[1] == pytest.approx(aligned[0].extents[1], rel=0.02)

    def test_views_are_brought_to_a_common_place(self):
        adrift = sphere()
        adrift.apply_translation([0.7, -0.4, 0.2])

        aligned = multiview.align([
            multiview.View(mesh=sphere(), yaw=0.0),
            multiview.View(mesh=adrift, yaw=90.0),
        ])

        assert aligned[1].bounds.mean(axis=0) == pytest.approx(
            aligned[0].bounds.mean(axis=0), abs=1e-6
        )

    def test_the_first_view_defines_the_frame(self):
        # It is placed by its own angle and then left alone: nothing rescales
        # or recentres it, because everything else is measured against it.
        first = sphere()
        first.apply_scale([1.0, 1.7, 1.0])
        aligned = multiview.align([
            multiview.View(mesh=first, yaw=0.0),
            multiview.View(mesh=sphere(), yaw=90.0),
        ])
        assert aligned[0].extents == pytest.approx(first.extents)
        assert aligned[0].bounds == pytest.approx(first.bounds)

    def test_the_camera_direction_turns_with_the_view(self):
        # Quarter turns land on axes, and half a turn is the opposite side.
        assert multiview.camera_direction(0.0) == pytest.approx(multiview.CAMERA_AXIS)
        assert multiview.camera_direction(180.0) == pytest.approx(-multiview.CAMERA_AXIS)
        assert multiview.camera_direction(90.0) @ multiview.CAMERA_AXIS == pytest.approx(
            0.0, abs=1e-9
        )


class TestViewsFromAboveAndBelow:
    """A turnaround sheet's top and bottom panels.

    No yaw reaches them, which is why treating a six-view sheet as six quarter
    turns destroys it: two views end up placed where they never were, and since
    outlines veto, they carve away what the others got right.
    """

    def test_overhead_is_not_reachable_by_turning(self):
        overhead = multiview.camera_direction(0.0, 90.0)
        assert overhead == pytest.approx([0.0, 1.0, 0.0], abs=1e-9)
        for yaw in (0.0, 90.0, 180.0, 270.0):
            assert multiview.camera_direction(yaw)[1] == pytest.approx(0.0, abs=1e-9)

    def test_underneath_is_the_opposite_of_overhead(self):
        assert multiview.camera_direction(0.0, -90.0) == pytest.approx(
            -multiview.camera_direction(0.0, 90.0), abs=1e-9
        )

    def test_yaw_rolls_an_overhead_view_rather_than_moving_it(self):
        # Still overhead, but the object lies a different way round in frame.
        for yaw in (0.0, 90.0, 180.0):
            assert multiview.camera_direction(yaw, 90.0) == pytest.approx(
                [0.0, 1.0, 0.0], abs=1e-9
            )

    def test_an_overhead_view_measures_the_plan_and_contributes_it(self):
        """The reason a top view is worth having.

        Seen from the front, an object's length is guesswork. Seen from above it
        is measured. The overhead view has to be able to hand that over.
        """

        long_one = long_subject()
        fused = multiview.fuse([
            multiview.View(mesh=sphere(), yaw=0.0),
            multiview.View(
                mesh=as_seen_overhead(long_one), yaw=0.0, pitch=90.0
            ),
        ])

        assert occupied(fused, facing(0.0, 1.2))

    def test_an_overhead_view_is_not_scaled_by_the_depth_it_invented(self):
        """Height is the wrong thing to reconcile an overhead view by.

        Turned upright, an overhead reconstruction's vertical extent is the one
        axis its camera could not see. Scaling by it would size the whole view
        from a guess.
        """

        squashed = sphere()
        # Deep in the direction its camera looked, which after turning upright
        # becomes the vertical: exactly the axis that must be ignored.
        squashed.apply_scale([3.0, 1.0, 1.0])

        aligned = multiview.align([
            multiview.View(mesh=sphere(), yaw=0.0),
            multiview.View(mesh=squashed, yaw=0.0, pitch=90.0),
        ])

        # Sized on an axis both cameras saw across their pictures, so the two
        # agree there however wrong the invented depth was.
        axis = np.array([0.0, 0.0, 1.0])
        assert multiview._extent_along(aligned[1], axis) == pytest.approx(
            multiview._extent_along(aligned[0], axis), rel=0.02
        )


class TestNamedViews:
    """The six panels a turnaround sheet labels."""

    def test_the_six_views_look_in_six_different_directions(self):
        directions = [
            tuple(np.round(multiview.camera_direction(*angles), 6))
            for angles in multiview.NAMED_VIEWS.values()
        ]
        assert len(set(directions)) == 6

    @pytest.mark.parametrize(
        "one,other", [("front", "back"), ("left", "right"), ("top", "bottom")]
    )
    def test_opposing_views_face_each_other(self, one, other):
        assert multiview.camera_direction(
            *multiview.NAMED_VIEWS[one]
        ) == pytest.approx(
            -multiview.camera_direction(*multiview.NAMED_VIEWS[other]), abs=1e-9
        )

    def test_the_object_faces_its_front_camera(self):
        # Everything else is defined relative to this, so it is worth pinning.
        assert multiview.camera_direction(
            *multiview.NAMED_VIEWS["front"]
        ) == pytest.approx(multiview.CAMERA_AXIS)

    def test_the_sides_are_level_and_the_top_is_not(self):
        for name in ("front", "back", "left", "right"):
            assert multiview.camera_direction(*multiview.NAMED_VIEWS[name])[
                1
            ] == pytest.approx(0.0, abs=1e-9)
        assert multiview.camera_direction(*multiview.NAMED_VIEWS["top"])[1] > 0.99

    @pytest.mark.parametrize(
        "label,expected",
        [
            ("FRONT", "front"),
            ("Right Side", "right"),
            ("  back  ", "back"),
            ("LEFT SIDE", "left"),
            ("TOP", "top"),
            ("Bottom:", "bottom"),
            ("underside", "bottom"),
        ],
    )
    def test_reads_the_labels_a_sheet_prints(self, label, expected):
        assert multiview.named_view(label) == multiview.NAMED_VIEWS[expected]

    @pytest.mark.parametrize("label", ["", "cow", "figure 2", "3/4 view"])
    def test_a_label_naming_no_view_is_declined(self, label):
        assert multiview.named_view(label) is None


class TestAgreementWithThePictures:
    """Checking a model against the images it was built from.

    The only check available that is not circular, and the one the whole
    multi-view path leans on: which candidate model best explains the pictures.
    """

    def picture_of(self, mesh, direction) -> np.ndarray:
        """A stand-in for a prepared input image: what that camera saw."""

        return multiview.projected_outline(mesh, direction)

    def test_a_model_matches_the_pictures_it_came_from(self):
        truth = long_subject()
        views = [multiview.View(mesh=truth, yaw=yaw) for yaw in (0.0, 90.0, 180.0)]
        pictures = [self.picture_of(truth, view.direction) for view in views]

        assert min(multiview.agreement(truth, views, pictures)) > 0.95

    def test_a_flattened_model_fails_the_views_that_could_see_its_length(self):
        """The failure a single image cannot avoid, caught by the check.

        Squashed along one camera's line of sight, a model still satisfies that
        camera perfectly and fails the ones looking from the side. That
        asymmetry is exactly what tells fusion apart from not fusing.
        """

        truth = long_subject()
        views = [multiview.View(mesh=truth, yaw=yaw) for yaw in (0.0, 90.0)]
        pictures = [self.picture_of(truth, view.direction) for view in views]

        squashed = truth.copy()
        squashed.apply_transform(multiview.turn(0.0))
        squashed.apply_scale(
            1.0 - 0.7 * np.abs(multiview.camera_direction(0.0))
        )

        scores = multiview.agreement(squashed, views, pictures)
        assert scores[0] > scores[1], "its own camera is still satisfied"
        assert scores[1] < 0.75, "the side view should not accept it"

    def test_an_outline_and_a_picture_are_fitted_the_same_way(self):
        """The bug that made a good model look broken.

        An early version projected the outline with its axes transposed against
        the picture, and scored a reconstruction 0.43 against the very image it
        was built from. Both sides must go through the same normalisation.
        """

        mesh = trimesh.creation.box(extents=(2.0, 1.0, 0.5))
        direction = multiview.camera_direction(0.0)

        outline = multiview.projected_outline(mesh, direction)
        # The same silhouette arriving as a picture instead.
        picture = multiview.picture_outline(outline)

        union = (outline | picture).sum()
        assert (outline & picture).sum() / union > 0.98

    def test_a_wildly_different_shape_scores_badly(self):
        # Judged from the side, where the difference is visible. Head-on the
        # long subject and a sphere have the same outline, and the check
        # correctly says so — which is the whole reason one view is not enough.
        truth = long_subject()
        views = [multiview.View(mesh=truth, yaw=90.0)]
        pictures = [self.picture_of(truth, views[0].direction)]

        assert multiview.agreement(sphere(), views, pictures)[0] < 0.85

    def test_scale_and_position_do_not_count(self):
        # Both sides are cropped to their content and scaled to fit, so a model
        # is judged on its shape rather than on where it happens to sit.
        truth = long_subject()
        views = [multiview.View(mesh=truth, yaw=90.0)]
        pictures = [self.picture_of(truth, views[0].direction)]

        moved = truth.copy()
        moved.apply_scale(0.4)
        moved.apply_translation([3.0, -2.0, 1.5])

        assert multiview.agreement(moved, views, pictures)[0] > 0.95

    def test_an_empty_picture_scores_zero_rather_than_dividing_by_nothing(self):
        views = [multiview.View(mesh=sphere(), yaw=0.0)]
        blank = np.zeros((64, 64), dtype=bool)
        assert multiview.agreement(sphere(), views, [blank])[0] == 0.0


class TestColour:
    def test_colour_comes_from_the_view_that_faced_it(self):
        red, blue = sphere(), sphere()
        red.visual.vertex_colors = np.tile([220, 30, 30, 255], (len(red.vertices), 1))
        blue.visual.vertex_colors = np.tile([30, 30, 220, 255], (len(blue.vertices), 1))

        fused = multiview.fuse([
            multiview.View(mesh=red, yaw=0.0),
            multiview.View(mesh=as_seen_from(blue, 180.0), yaw=180.0),
        ])

        points = np.asarray(fused.vertices)
        colours = np.asarray(fused.visual.vertex_colors)
        towards_front = points @ multiview.camera_direction(0.0)
        # Front half red, back half blue: the seam itself is not asserted on,
        # only that each side took the colour of the camera that faced it.
        assert colours[towards_front > 0.8][:, 0].mean() > 150
        assert colours[towards_front < -0.8][:, 2].mean() > 150


class TestOccupancy:
    def test_a_solid_is_solid_in_the_middle_and_empty_at_the_corners(self):
        mesh = sphere()
        bounds = multiview._grid_bounds([mesh])
        volume = multiview._occupancy(mesh, bounds, 32)
        assert volume[16, 16, 16]
        assert not volume[0, 0, 0]
        # A sphere fills about half its bounding cube; well away from either
        # extreme is the assertion that a hollow shell would fail.
        assert 0.25 < volume.mean() < 0.6


class TestRefusesTooLittle:
    @pytest.mark.parametrize("count", [0, 1])
    def test_fusing_needs_two_views(self, count):
        views = [multiview.View(mesh=sphere(), yaw=0.0)] * count
        with pytest.raises(ValueError):
            multiview.fuse(views)


class TestReadingASheet:
    def test_a_turnaround_is_read_as_going_round_the_object(self):
        readings = multiview.candidate_layouts(4)
        assert any(
            reading == tuple(multiview.NAMED_VIEWS[name] for name in
                             ("front", "right", "back", "left"))
            for reading in readings
        )

    def test_both_ways_round_are_offered(self):
        # Which side of a sheet is "right" is a convention nobody agrees on, so
        # both are tried and the pictures decide.
        readings = multiview.candidate_layouts(3)
        assert len(readings) >= 2
        assert len(set(readings)) == len(readings)

    def test_a_six_panel_sheet_is_read_as_four_sides_plus_top_and_bottom(self):
        for reading in multiview.candidate_layouts(6):
            pitches = sorted(pitch for _, pitch in reading)
            assert pitches == [-90.0, 0.0, 0.0, 0.0, 0.0, 90.0]

    def test_every_reading_names_each_panel_once(self):
        for count in multiview.LAYOUTS:
            for reading in multiview.candidate_layouts(count):
                assert len(set(reading)) == count

    @pytest.mark.parametrize("count", [1, 7, 12])
    def test_an_unreadable_sheet_is_refused_rather_than_guessed(self, count):
        with pytest.raises(multiview.UnknownAngles):
            multiview.candidate_layouts(count)
