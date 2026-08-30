"""Input preparation: orientation, masking, cropping and the square render."""

from __future__ import annotations

import pytest
from PIL import Image

from sculptor_engine import imageprep
from sculptor_engine.imageprep import (
    CorruptImage,
    NoForegroundFound,
    Suitability,
)


def write_rgba(path, size, subject_box=None, colour=(200, 60, 40, 255)):
    """An RGBA image with an opaque rectangle on a transparent field."""

    image = Image.new("RGBA", size, (0, 0, 0, 0))
    if subject_box is not None:
        block = Image.new("RGBA", (
            subject_box[2] - subject_box[0],
            subject_box[3] - subject_box[1],
        ), colour)
        image.paste(block, subject_box[:2])
    image.save(path, format="PNG")
    return image


class TestLoadSource:
    def test_rejects_a_missing_file(self, tmp_path):
        with pytest.raises(CorruptImage):
            imageprep.load_source(tmp_path / "nope.png")

    def test_rejects_a_file_that_is_not_an_image(self, tmp_path):
        broken = tmp_path / "broken.png"
        broken.write_bytes(b"this is not a PNG")
        with pytest.raises(CorruptImage):
            imageprep.load_source(broken)

    def test_always_returns_rgba(self, tmp_path):
        path = tmp_path / "rgb.jpg"
        Image.new("RGB", (32, 32), (10, 20, 30)).save(path)
        assert imageprep.load_source(path).mode == "RGBA"

    def test_does_not_modify_the_source_file(self, tmp_path):
        path = tmp_path / "source.png"
        write_rgba(path, (40, 40), (10, 10, 30, 30))
        before = path.read_bytes()
        imageprep.load_source(path)
        assert path.read_bytes() == before


class TestMaskResolution:
    def test_uses_alpha_when_it_is_a_real_cutout(self, tmp_path):
        path = tmp_path / "cutout.png"
        write_rgba(path, (100, 100), (20, 20, 60, 60))
        image = imageprep.load_source(path)
        assert imageprep.resolve_mask(image, None) is not None

    def test_ignores_a_fully_opaque_alpha_channel(self, tmp_path):
        # A JPEG converted to RGBA is opaque everywhere; that carries no
        # subject information and must not be mistaken for a cutout.
        path = tmp_path / "opaque.png"
        Image.new("RGBA", (64, 64), (120, 120, 120, 255)).save(path)
        image = imageprep.load_source(path)
        assert imageprep.resolve_mask(image, None) is None

    def test_supplied_mask_wins_over_alpha(self, tmp_path):
        source = tmp_path / "s.png"
        write_rgba(source, (100, 100), (0, 0, 100, 100))
        mask_path = tmp_path / "m.png"
        mask = Image.new("L", (100, 100), 0)
        mask.paste(Image.new("L", (10, 10), 255), (45, 45))
        mask.save(mask_path)

        image = imageprep.load_source(source)
        resolved = imageprep.resolve_mask(image, mask_path)
        assert imageprep.subject_box(image, resolved) == (45, 45, 55, 55)

    def test_mask_is_resized_to_the_source(self, tmp_path):
        source = tmp_path / "s.png"
        write_rgba(source, (100, 100), (0, 0, 100, 100))
        mask_path = tmp_path / "m.png"
        Image.new("L", (50, 50), 255).save(mask_path)
        image = imageprep.load_source(source)
        assert imageprep.resolve_mask(image, mask_path).size == (100, 100)

    def test_empty_mask_is_an_error(self, tmp_path):
        source = tmp_path / "s.png"
        write_rgba(source, (50, 50), (0, 0, 50, 50))
        mask_path = tmp_path / "m.png"
        Image.new("L", (50, 50), 0).save(mask_path)
        with pytest.raises(NoForegroundFound):
            imageprep.resolve_mask(imageprep.load_source(source), mask_path)

    def test_missing_mask_file_is_an_error(self, tmp_path):
        source = tmp_path / "s.png"
        write_rgba(source, (50, 50), (0, 0, 50, 50))
        with pytest.raises(NoForegroundFound):
            imageprep.resolve_mask(imageprep.load_source(source), tmp_path / "gone.png")


class TestSubjectBox:
    def test_finds_the_opaque_region(self, tmp_path):
        path = tmp_path / "s.png"
        write_rgba(path, (200, 120), (30, 10, 70, 90))
        image = imageprep.load_source(path)
        mask = imageprep.resolve_mask(image, None)
        assert imageprep.subject_box(image, mask) == (30, 10, 70, 90)

    def test_falls_back_to_the_whole_frame_without_a_mask(self, tmp_path):
        path = tmp_path / "s.png"
        Image.new("RGBA", (80, 40), (5, 5, 5, 255)).save(path)
        image = imageprep.load_source(path)
        assert imageprep.subject_box(image, None) == (0, 0, 80, 40)


class TestColourBleed:
    """Growing subject colour into transparent pixels before compositing.

    The engine flattens the cutout onto a solid background. A cutout's RGB is
    undefined where alpha is zero — usually black — so without this the
    silhouette blends into that undefined colour and leaves a halo, which
    reconstructs as a thin shell of geometry around the object.
    """

    @staticmethod
    def cutout() -> Image.Image:
        image = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        image.paste(Image.new("RGBA", (24, 24), (230, 80, 40, 255)), (20, 20))
        return image

    def test_fills_transparent_pixels_with_neighbouring_colour(self):
        import numpy as np

        before = np.asarray(self.cutout())
        after = np.asarray(imageprep.bleed_colour_outward(self.cutout()))

        assert tuple(before[19, 32, :3]) == (0, 0, 0), "fixture should start black"
        assert tuple(after[19, 32, :3]) == (230, 80, 40)

    def test_leaves_alpha_alone(self):
        import numpy as np

        before = np.asarray(self.cutout())
        after = np.asarray(imageprep.bleed_colour_outward(self.cutout()))
        # The silhouette must not move; only colour under it changes.
        assert np.array_equal(before[:, :, 3], after[:, :, 3])

    def test_leaves_the_subject_untouched(self):
        import numpy as np

        before = np.asarray(self.cutout())
        after = np.asarray(imageprep.bleed_colour_outward(self.cutout()))
        assert np.array_equal(before[20:44, 20:44, :3], after[20:44, 20:44, :3])

    def test_zero_passes_is_a_no_op(self):
        import numpy as np

        image = self.cutout()
        assert np.array_equal(
            np.asarray(image), np.asarray(imageprep.bleed_colour_outward(image, passes=0))
        )

    def test_prepare_applies_it_to_a_masked_subject(self, tmp_path):
        import numpy as np

        source = tmp_path / "s.png"
        write_rgba(source, (200, 200), (60, 60, 140, 140))
        out = tmp_path / "prepared.png"

        imageprep.prepare(source, out, padding=0.4, size=128)

        with Image.open(out) as prepared:
            data = np.asarray(prepared.convert("RGBA"))
        # Just outside the subject the pixels are still transparent, but their
        # colour should now be the subject's rather than undefined black.
        transparent = data[:, :, 3] < 8
        assert transparent.any()
        assert data[transparent][:, :3].max() > 0, (
            "transparent pixels kept undefined black; the bleed did not run"
        )


class TestPrepare:
    def test_writes_a_square_png_of_the_requested_size(self, tmp_path):
        source = tmp_path / "s.png"
        write_rgba(source, (300, 200), (100, 50, 180, 150))
        out = tmp_path / "out" / "prepared.png"

        prepared = imageprep.prepare(source, out, size=256)

        assert prepared.path == out
        with Image.open(out) as written:
            assert written.size == (256, 256)
            assert written.mode == "RGBA"

    def test_centres_the_subject_in_the_square(self, tmp_path):
        # An off-centre subject must end up centred, so the engine sees a
        # consistently framed object regardless of where it sat in the source.
        source = tmp_path / "s.png"
        write_rgba(source, (400, 400), (300, 300, 340, 340))
        out = tmp_path / "prepared.png"

        imageprep.prepare(source, out, padding=0.0, size=64)

        with Image.open(out) as written:
            alpha = written.convert("RGBA").getchannel("A")
        box = alpha.getbbox()
        left_gap, top_gap = box[0], box[1]
        right_gap, bottom_gap = 64 - box[2], 64 - box[3]
        assert abs(left_gap - right_gap) <= 1
        assert abs(top_gap - bottom_gap) <= 1

    def test_padding_shrinks_the_subject_within_the_square(self, tmp_path):
        source = tmp_path / "s.png"
        write_rgba(source, (200, 200), (50, 50, 150, 150))

        tight = tmp_path / "tight.png"
        padded = tmp_path / "padded.png"
        imageprep.prepare(source, tight, padding=0.0, size=100)
        imageprep.prepare(source, padded, padding=0.25, size=100)

        def coverage(path):
            with Image.open(path) as image:
                box = image.convert("RGBA").getchannel("A").getbbox()
            return (box[2] - box[0]) * (box[3] - box[1])

        assert coverage(padded) < coverage(tight)

    def test_honours_exif_orientation(self, tmp_path):
        # Orientation 6 means "rotate 90 CW on display". A tall subject in
        # stored pixels must come out wide, and vice versa.
        from PIL import TiffImagePlugin

        source = tmp_path / "rotated.jpg"
        image = Image.new("RGB", (100, 50), (0, 0, 0))
        exif = Image.Exif()
        exif[0x0112] = 6
        image.save(source, exif=exif)

        loaded = imageprep.load_source(source)
        assert loaded.size == (50, 100)

    def test_reports_poor_suitability_without_a_mask(self, tmp_path):
        source = tmp_path / "s.png"
        Image.new("RGBA", (500, 500), (90, 90, 90, 255)).save(source)
        prepared = imageprep.prepare(source, tmp_path / "p.png")
        assert prepared.had_mask is False
        assert prepared.suitability is Suitability.POOR
        assert prepared.notes

    def test_reports_good_suitability_for_a_clean_cutout(self, tmp_path):
        source = tmp_path / "s.png"
        write_rgba(source, (600, 600), (150, 150, 450, 450))
        prepared = imageprep.prepare(source, tmp_path / "p.png")
        assert prepared.had_mask is True
        assert prepared.suitability is Suitability.GOOD
        assert prepared.notes == ()

    def test_flags_a_subject_that_touches_the_frame_edge(self, tmp_path):
        source = tmp_path / "s.png"
        write_rgba(source, (400, 400), (0, 100, 200, 300))
        prepared = imageprep.prepare(source, tmp_path / "p.png")
        assert prepared.touches_edge is True
        assert prepared.suitability is not Suitability.GOOD
