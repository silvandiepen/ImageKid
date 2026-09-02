"""Finding several views inside one image.

The failure that matters is a false positive: splitting a single subject into
pieces produces confident nonsense, where declining to split produces the
behaviour the user already had. Most of these check it says no.
"""

from __future__ import annotations

import pytest
from PIL import Image, ImageDraw

from sculptor_engine import views


def blank(size, transparent: bool = True) -> Image.Image:
    return Image.new("RGBA", size, (0, 0, 0, 0) if transparent else (255, 255, 255, 255))


def blob(image: Image.Image, box, colour=(200, 80, 40, 255)) -> None:
    """Paint a solid rectangle, as a subject on a background."""

    left, top, right, bottom = box
    image.paste(Image.new("RGBA", (right - left, bottom - top), colour), (left, top))


def sheet_of(count: int, opaque: bool = False, size=(900, 300)) -> Image.Image:
    """A row of evenly spaced subjects, like a turnaround render."""

    image = blank(size, transparent=not opaque)
    cell = size[0] // count
    for index in range(count):
        left = index * cell + cell // 5
        blob(image, (left, 60, left + cell // 2, size[1] - 60))
    return image


class TestDetectsSheets:
    @pytest.mark.parametrize("count", [2, 3, 4])
    def test_finds_a_row_of_views(self, count):
        cells = views.find_cells(sheet_of(count))
        assert len(cells) == count

    def test_works_without_alpha(self):
        # A render on a flat white backdrop, which is how most sheets arrive.
        cells = views.find_cells(sheet_of(3, opaque=True))
        assert len(cells) == 3

    def test_finds_a_grid(self):
        image = blank((600, 600))
        for x in (60, 340):
            for y in (60, 340):
                blob(image, (x, y, x + 180, y + 180))
        assert len(views.find_cells(image)) == 4

    def test_handles_a_grid_with_an_empty_slot(self):
        # Three views laid out 2x2.
        image = blank((600, 600))
        for x, y in ((60, 60), (340, 60), (60, 340)):
            blob(image, (x, y, x + 180, y + 180))
        assert len(views.find_cells(image)) == 3

    def test_returns_cells_in_reading_order(self):
        cells = views.find_cells(sheet_of(3))
        lefts = [cell.box[0] for cell in cells]
        assert lefts == sorted(lefts)

    def test_each_cell_is_cropped_tight_to_its_subject(self):
        """The box hugs the subject, not the grid slot.

        Checked against the sheet's own mask rather than by re-examining the
        crop: a tight crop of an opaque subject has the subject in all four
        corners, so corner-sampled background detection would call the whole
        thing background and find nothing.
        """

        sheet = sheet_of(3)
        mask = views.content_mask(sheet)

        for cell in views.find_cells(sheet):
            left, top, right, bottom = cell.box
            region = mask[top:bottom, left:right]
            # Every edge of the box touches content, so nothing was left over.
            assert region[0].any() and region[-1].any()
            assert region[:, 0].any() and region[:, -1].any()


class TestCellsCarryTheirCutout:
    """The split knows what is background; the crop has to keep that.

    Handed a subject on white, the reconstruction engine has nothing to say
    where the object ends and builds the picture as a flat card.
    """

    def test_a_cell_from_a_flat_backdrop_comes_out_cut_out(self):
        # Round subjects, so a tight crop still has backdrop in its corners.
        image = blank((900, 300), transparent=False)
        drawing = ImageDraw.Draw(image)
        for index in range(3):
            left = index * 300 + 60
            drawing.ellipse((left, 60, left + 150, 240), fill=(200, 80, 40, 255))

        for cell in views.find_cells(image):
            alpha = cell.image.getchannel("A")
            assert alpha.getextrema()[0] == 0, "background should be transparent"
            assert alpha.getextrema()[1] == 255, "subject should be opaque"

    def test_a_pale_patch_inside_the_subject_stays_opaque(self):
        # The mask comes from colour distance, and a white marking on an animal
        # is the same colour as the backdrop behind it.
        image = blank((900, 300), transparent=False)
        for index in range(3):
            left = index * 300 + 60
            blob(image, (left, 60, left + 150, 240))
            blob(image, (left + 50, 110, left + 100, 160), colour=(255, 255, 255, 255))

        for cell in views.find_cells(image):
            width, height = cell.image.size
            assert cell.image.getchannel("A").getpixel((width // 2, height // 2)) == 255

    def test_a_sheet_that_already_has_alpha_keeps_its_own(self):
        # Soft edges are real information; re-deriving the mask would harden
        # them into a jagged silhouette.
        sheet = blank((900, 300))
        for index in range(3):
            left = index * 300 + 60
            blob(image=sheet, box=(left, 60, left + 150, 240), colour=(200, 80, 40, 128))

        for cell in views.find_cells(sheet):
            assert cell.image.getchannel("A").getextrema()[1] == 128


class TestDeclinesOtherwise:
    def test_a_single_subject_is_not_a_sheet(self):
        image = blank((600, 600))
        blob(image, (150, 150, 450, 450))
        assert views.find_cells(image) == []
        assert views.looks_like_a_sheet(image) is False

    def test_a_subject_with_internal_gaps_is_not_a_sheet(self):
        # An animal's legs leave vertical gaps; those must not read as gutters.
        image = blank((600, 400))
        blob(image, (150, 80, 450, 260))          # body
        for x in (180, 260, 340, 400):            # legs
            blob(image, (x, 260, x + 30, 340))
        assert views.find_cells(image) == []

    def test_an_empty_image_is_not_a_sheet(self):
        assert views.find_cells(blank((300, 300))) == []

    def test_a_sprite_sheet_is_refused(self):
        # Many small cells is a catalogue, not a turnaround of one object.
        image = blank((800, 800))
        for row in range(5):
            for column in range(5):
                blob(image, (
                    column * 160 + 30, row * 160 + 30,
                    column * 160 + 130, row * 160 + 130,
                ))
        assert views.find_cells(image) == []

    def test_wildly_uneven_cells_are_refused(self):
        # One large subject beside something small is likelier to be a subject
        # and a caption than two views of the same thing.
        image = blank((900, 400))
        blob(image, (40, 40, 400, 360))
        blob(image, (600, 180, 660, 220))
        assert views.find_cells(image) == []

    def test_one_subject_that_comes_apart_is_not_a_sheet(self):
        """The failure that made a ferry into four viewpoints.

        A pale ship on a pale background breaks into a hull and some cabins, and
        connected regions will happily call those four panels. A sheet tiles —
        its panels sit in rows and columns and never overlap when projected onto
        an axis — while the parts of one subject sit on top of each other.
        """

        image = blank((700, 400), transparent=False)
        blob(image, (60, 180, 640, 300))          # hull
        blob(image, (150, 90, 260, 175))          # a cabin above it
        blob(image, (330, 90, 440, 175))          # another
        blob(image, (500, 90, 610, 175))          # and another

        assert views.find_cells(image) == []

    def test_pieces_stacked_in_a_column_are_not_a_sheet(self):
        # Overlapping horizontally rather than vertically: same argument.
        image = blank((400, 700), transparent=False)
        blob(image, (150, 60, 260, 640))
        blob(image, (60, 150, 145, 260))
        blob(image, (60, 330, 145, 440))

        assert views.find_cells(image) == []

    def test_a_proper_grid_still_reads_as_a_sheet(self):
        # The guard must not cost us the layouts that do tile.
        image = blank((900, 600))
        for x in (60, 340, 620):
            for y in (60, 340):
                blob(image, (x, y, x + 200, y + 200))
        assert len(views.find_cells(image)) == 6

    def test_debris_is_dropped_rather_than_counted(self):
        # A speck should not turn two views into three.
        image = sheet_of(2)
        blob(image, (860, 10, 868, 18))
        cells = views.find_cells(image)
        assert len(cells) == 2
