"""End-to-end worker behaviour.

The reconstruction engine is substituted with a deterministic one that returns
real ``trimesh`` geometry. That keeps these tests about the worker — staging,
error classification, cancellation, protocol hygiene — rather than about SPAR3D,
which needs multi-gigabyte weights and is covered by the Phase 0 spike instead.
"""

from __future__ import annotations

import json
import subprocess
import sys
import textwrap
from pathlib import Path

import numpy as np
import pytest
import trimesh
from PIL import Image

from sculptor_engine.engines.base import (
    Cancelled,
    EngineUnavailable,
    InferenceFailed,
    OutOfMemory,
    ReconstructionEngine,
)
from sculptor_engine.protocol import (
    AnalyseRequest,
    GenerateOptions,
    GenerateRequest,
    Stage,
)
from sculptor_engine.worker import Emitter, Worker

ROOT = Path(__file__).resolve().parent.parent


class RecordingEmitter(Emitter):
    """Captures messages instead of writing them to a stream."""

    def __init__(self) -> None:
        self.messages: list[dict] = []

    def send(self, message: dict) -> None:
        # Prove every message is serialisable, as the real emitter requires.
        self.messages.append(json.loads(json.dumps(message)))

    def of_type(self, kind: str) -> list[dict]:
        return [m for m in self.messages if m["type"] == kind]


class BoxEngine(ReconstructionEngine):
    """Returns a unit box, optionally raising instead."""

    name = "box"

    def __init__(self, raises: Exception | None = None, available: bool = True) -> None:
        self._raises = raises
        self._available = available
        self.received: Path | None = None

    @property
    def is_available(self) -> bool:
        return self._available

    @property
    def unavailable_reason(self) -> str | None:
        return None if self._available else "test engine marked unavailable"

    def reconstruct(self, prepared_image, progress, should_cancel):
        self.received = prepared_image
        if self._raises is not None:
            raise self._raises
        progress(0.25)
        if should_cancel():
            raise Cancelled("cancelled during inference")
        progress(0.75)
        return trimesh.creation.box(extents=(2.0, 3.0, 1.0))


@pytest.fixture
def source_image(tmp_path) -> Path:
    """A clean cutout: opaque block on a transparent field."""

    path = tmp_path / "source.png"
    image = Image.new("RGBA", (300, 300), (0, 0, 0, 0))
    image.paste(Image.new("RGBA", (140, 160), (200, 80, 40, 255)), (80, 70))
    image.save(path)
    return path


def make_request(source: Path, workspace: Path, **options) -> GenerateRequest:
    return GenerateRequest(
        jobId="job-1",
        sourcePath=str(source),
        workspace=str(workspace),
        options=GenerateOptions(**options),
    )


class TestSuccessfulJob:
    def test_emits_a_result_with_a_readable_glb(self, source_image, tmp_path):
        emitter = RecordingEmitter()
        Worker(BoxEngine(), emitter).run(
            make_request(source_image, tmp_path / "work", inputSize=128)
        )

        results = emitter.of_type("result")
        assert emitter.of_type("error") == []
        assert len(results) == 1

        result = results[0]
        glb = Path(result["glbPath"])
        assert glb.is_file()
        reopened = trimesh.load(str(glb), file_type="glb", force="scene")
        assert len(reopened.geometry) == 1

    def test_visits_every_stage_in_order(self, source_image, tmp_path):
        emitter = RecordingEmitter()
        Worker(BoxEngine(), emitter).run(make_request(source_image, tmp_path / "w"))

        seen = []
        for message in emitter.of_type("progress"):
            if message["stage"] not in seen:
                seen.append(message["stage"])
        assert seen == [stage.value for stage in Stage]

    def test_overall_progress_never_goes_backwards(self, source_image, tmp_path):
        emitter = RecordingEmitter()
        Worker(BoxEngine(), emitter).run(make_request(source_image, tmp_path / "w"))
        fractions = [m["fraction"] for m in emitter.of_type("progress")]
        assert fractions == sorted(fractions)

    def test_result_metadata_matches_the_normalised_asset(self, source_image, tmp_path):
        emitter = RecordingEmitter()
        # Smoothing and simplification off, so the geometry reaching
        # normalisation is exactly the box the engine returned and the scale is
        # predictable. Their own effects are covered in test_meshnorm.
        Worker(BoxEngine(), emitter).run(
            make_request(
                source_image,
                tmp_path / "w",
                smoothingIterations=0,
                targetTriangles=0,
            )
        )
        result = emitter.of_type("result")[0]

        assert result["triangleCount"] == 12
        assert result["upAxis"] == "+Y"
        assert result["originConvention"] == "bottomCentre"
        # The box's longest edge is 3.0, so normalisation scales by 1/3.
        assert result["appliedScale"] == pytest.approx(1 / 3.0)
        assert result["durationSeconds"] >= 0

    def test_hands_the_engine_the_prepared_square_not_the_source(
        self, source_image, tmp_path
    ):
        engine = BoxEngine()
        Worker(engine, RecordingEmitter()).run(
            make_request(source_image, tmp_path / "w", inputSize=192)
        )
        assert engine.received != source_image
        with Image.open(engine.received) as prepared:
            assert prepared.size == (192, 192)

    def test_leaves_the_source_image_untouched(self, source_image, tmp_path):
        before = source_image.read_bytes()
        Worker(BoxEngine(), RecordingEmitter()).run(
            make_request(source_image, tmp_path / "w")
        )
        assert source_image.read_bytes() == before


class TestErrorClassification:
    @pytest.mark.parametrize(
        "raised, expected_code, recoverable",
        [
            (EngineUnavailable("no weights"), "modelNotInstalled", True),
            (OutOfMemory("mps out of memory"), "insufficientMemory", True),
            (InferenceFailed("bad forward pass"), "inferenceFailed", True),
            (Cancelled("stopped"), "cancelled", True),
        ],
    )
    def test_maps_engine_failures_to_protocol_codes(
        self, source_image, tmp_path, raised, expected_code, recoverable
    ):
        emitter = RecordingEmitter()
        Worker(BoxEngine(raises=raised), emitter).run(
            make_request(source_image, tmp_path / "w")
        )

        errors = emitter.of_type("error")
        assert len(errors) == 1
        assert errors[0]["code"] == expected_code
        assert errors[0]["recoverable"] is recoverable
        assert emitter.of_type("result") == []

    def test_reports_a_corrupt_source_image(self, tmp_path):
        broken = tmp_path / "broken.png"
        broken.write_bytes(b"nope")
        emitter = RecordingEmitter()
        Worker(BoxEngine(), emitter).run(make_request(broken, tmp_path / "w"))
        assert emitter.of_type("error")[0]["code"] == "corruptImage"

    def test_reports_a_missing_mask(self, source_image, tmp_path):
        emitter = RecordingEmitter()
        Worker(BoxEngine(), emitter).run(
            GenerateRequest(
                jobId="job-1",
                sourcePath=str(source_image),
                workspace=str(tmp_path / "w"),
                maskPath=str(tmp_path / "absent.png"),
            )
        )
        assert emitter.of_type("error")[0]["code"] == "noForegroundFound"

    def test_an_unexpected_exception_becomes_an_internal_error(
        self, source_image, tmp_path
    ):
        emitter = RecordingEmitter()
        Worker(BoxEngine(raises=ValueError("surprise")), emitter).run(
            make_request(source_image, tmp_path / "w")
        )
        error = emitter.of_type("error")[0]
        assert error["code"] == "internalError"
        assert error["recoverable"] is False

    def test_writes_no_glb_when_the_job_fails(self, source_image, tmp_path):
        workspace = tmp_path / "w"
        Worker(BoxEngine(raises=InferenceFailed("boom")), RecordingEmitter()).run(
            make_request(source_image, workspace)
        )
        assert not (workspace / "output" / "model.glb").exists()


class TestCancellation:
    def test_a_cancel_before_the_job_stops_it(self, source_image, tmp_path):
        emitter = RecordingEmitter()
        worker = Worker(BoxEngine(), emitter)
        worker.cancel("job-1")
        worker.run(make_request(source_image, tmp_path / "w"))

        assert emitter.of_type("error")[0]["code"] == "cancelled"
        assert emitter.of_type("result") == []

    def test_cancel_state_does_not_leak_into_the_next_job(self, source_image, tmp_path):
        emitter = RecordingEmitter()
        worker = Worker(BoxEngine(), emitter)
        worker.cancel("job-1")
        worker.run(make_request(source_image, tmp_path / "w1"))
        worker.run(make_request(source_image, tmp_path / "w2"))

        assert len(emitter.of_type("result")) == 1


class TestAnalysis:
    """Rating a source image without reconstructing it.

    The point is that a user learns a flag or a cropped subject is a poor
    candidate on import, rather than after waiting out a generation.
    """

    def test_rates_a_clean_cutout_as_good(self, source_image, tmp_path):
        emitter = RecordingEmitter()
        Worker(BoxEngine(), emitter).analyse(
            AnalyseRequest(requestId="a1", sourcePath=str(source_image))
        )

        messages = emitter.of_type("analysis")
        assert len(messages) == 1
        assert messages[0]["requestId"] == "a1"
        assert messages[0]["suitability"] == "good"
        assert messages[0]["hadMask"] is True
        assert messages[0]["notes"] == []

    def test_rates_an_image_without_a_subject_as_poor(self, tmp_path):
        # A flag: opaque everywhere, nothing to isolate. This is the case the
        # badge exists for, since it cannot reconstruct usefully.
        flat = tmp_path / "flag.png"
        Image.new("RGBA", (400, 400), (180, 30, 40, 255)).save(flat)

        emitter = RecordingEmitter()
        Worker(BoxEngine(), emitter).analyse(
            AnalyseRequest(requestId="a2", sourcePath=str(flat))
        )

        message = emitter.of_type("analysis")[0]
        assert message["suitability"] == "poor"
        assert message["hadMask"] is False
        assert message["notes"], "a poor rating must explain itself"

    def test_flags_a_subject_touching_the_frame_edge(self, tmp_path):
        cropped = tmp_path / "cropped.png"
        image = Image.new("RGBA", (400, 400), (0, 0, 0, 0))
        image.paste(Image.new("RGBA", (200, 200), (10, 200, 90, 255)), (0, 100))
        image.save(cropped)

        emitter = RecordingEmitter()
        Worker(BoxEngine(), emitter).analyse(
            AnalyseRequest(requestId="a3", sourcePath=str(cropped))
        )

        message = emitter.of_type("analysis")[0]
        assert message["touchesEdge"] is True
        assert message["suitability"] != "good"

    def test_reports_a_corrupt_image_rather_than_a_rating(self, tmp_path):
        broken = tmp_path / "broken.png"
        broken.write_bytes(b"not an image")

        emitter = RecordingEmitter()
        Worker(BoxEngine(), emitter).analyse(
            AnalyseRequest(requestId="a4", sourcePath=str(broken))
        )

        assert emitter.of_type("analysis") == []
        assert emitter.of_type("error")[0]["code"] == "corruptImage"

    def test_analysis_never_runs_the_engine(self, source_image):
        # It must stay cheap; touching the engine would make it slow and could
        # fail with modelNotInstalled for what is only a rating.
        engine = BoxEngine(raises=AssertionError("engine must not be used"))
        emitter = RecordingEmitter()
        Worker(engine, emitter).analyse(
            AnalyseRequest(requestId="a5", sourcePath=str(source_image))
        )
        assert engine.received is None
        assert emitter.of_type("analysis")


class TestServeProtocolHygiene:
    """The protocol stream must carry protocol messages and nothing else."""

    #: ``__BODY__`` is replaced after dedenting, so the substituted lines keep
    #: the indentation they need instead of confusing ``textwrap.dedent``.
    SERVE_TEMPLATE = textwrap.dedent(
        """
        import sys
        sys.path.insert(0, __ROOT__)

        import trimesh
        from sculptor_engine import worker
        from sculptor_engine.engines.base import ReconstructionEngine

        class TestEngine(ReconstructionEngine):
            name = "test"

            @property
            def is_available(self):
                return True

            @property
            def unavailable_reason(self):
                return None

            def reconstruct(self, prepared_image, progress, should_cancel):
        __BODY__

        worker.create_engine = lambda *a, **k: TestEngine()
        sys.exit(worker.serve())
        """
    )

    def _run_serve(self, tmp_path: Path, stdin: str, engine_body: str) -> subprocess.CompletedProcess:
        body = textwrap.indent(textwrap.dedent(engine_body).strip("\n"), " " * 8)
        source = self.SERVE_TEMPLATE.replace("__ROOT__", repr(str(ROOT))).replace(
            "__BODY__", body
        )
        script = tmp_path / "run_serve.py"
        script.write_text(source)
        return subprocess.run(
            [sys.executable, str(script)],
            input=stdin,
            capture_output=True,
            text=True,
            timeout=180,
        )

    def test_library_chatter_never_reaches_the_protocol_stream(self, tmp_path):
        # An engine that prints to stdout, exactly as torch and friends do on
        # import. Every stdout line must still parse as a protocol message.
        source = tmp_path / "s.png"
        image = Image.new("RGBA", (200, 200), (0, 0, 0, 0))
        image.paste(Image.new("RGBA", (100, 100), (10, 200, 90, 255)), (50, 50))
        image.save(source)

        request = json.dumps(
            {
                "type": "generate",
                "jobId": "j1",
                "sourcePath": str(source),
                "workspace": str(tmp_path / "work"),
                "options": {"inputSize": 96},
            }
        )
        completed = self._run_serve(
            tmp_path,
            stdin=request + "\n" + json.dumps({"type": "shutdown"}) + "\n",
            engine_body=(
                'print("noisy library banner on stdout")\n'
                'sys.stdout.write("more chatter\\n")\n'
                "return trimesh.creation.box(extents=(1.0, 2.0, 1.0))\n"
            ),
        )

        assert completed.returncode == 0, completed.stderr
        lines = [line for line in completed.stdout.splitlines() if line.strip()]
        assert lines, completed.stderr
        messages = [json.loads(line) for line in lines]  # raises if chatter leaked

        assert messages[0]["type"] == "ready"
        assert [m for m in messages if m["type"] == "result"]
        # The chatter went somewhere — stderr.
        assert "noisy library banner" in completed.stderr

    def test_malformed_input_is_reported_without_killing_the_worker(self, tmp_path):
        completed = self._run_serve(
            tmp_path,
            stdin='{"type":"bogus"}\nnot json at all\n{"type":"shutdown"}\n',
            engine_body="return trimesh.creation.box()\n",
        )

        assert completed.returncode == 0, completed.stderr
        messages = [
            json.loads(line) for line in completed.stdout.splitlines() if line.strip()
        ]
        errors = [m for m in messages if m["type"] == "error"]
        assert len(errors) == 2
        assert all(e["code"] == "malformedRequest" for e in errors)

    def test_closing_stdin_shuts_the_worker_down(self, tmp_path):
        completed = self._run_serve(
            tmp_path, stdin="", engine_body="return trimesh.creation.box()\n"
        )
        assert completed.returncode == 0, completed.stderr
        messages = [
            json.loads(line) for line in completed.stdout.splitlines() if line.strip()
        ]
        assert messages[0]["type"] == "ready"


# ---------------------------------------------------------------------------
# Several views of one object
# ---------------------------------------------------------------------------


class SphereEngine(ReconstructionEngine):
    """Returns a sphere, and records the image it was handed each time.

    A sphere rather than a box because fusion voxelises and re-extracts, and a
    box's flat faces make "did the shape survive" a question about marching
    cubes rather than about the worker.
    """

    name = "sphere"

    def __init__(self) -> None:
        self.received: list[Path] = []

    @property
    def is_available(self) -> bool:
        return True

    @property
    def unavailable_reason(self) -> str | None:
        return None

    def reconstruct(self, prepared_image, progress, should_cancel):
        self.received.append(prepared_image)
        progress(0.5)
        return trimesh.creation.icosphere(subdivisions=3, radius=1.0)


class WrongDepthEngine(ReconstructionEngine):
    """Returns the same shape for every view, however it was photographed.

    Fusing identical views cannot improve on one of them, so the single-view
    candidate has to be allowed to win.
    """

    name = "wrong-depth"

    @property
    def is_available(self) -> bool:
        return True

    @property
    def unavailable_reason(self) -> str | None:
        return None

    def reconstruct(self, prepared_image, progress, should_cancel):
        progress(0.5)
        return trimesh.creation.icosphere(subdivisions=3, radius=1.0)


@pytest.fixture
def sheet_image(tmp_path) -> Path:
    """Three views of one object laid out in a row, as a turnaround render."""

    path = tmp_path / "turnaround.png"
    image = Image.new("RGBA", (900, 300), (0, 0, 0, 0))
    for index in range(3):
        left = index * 300 + 60
        image.paste(Image.new("RGBA", (150, 180), (200, 80, 40, 255)), (left, 60))
    image.save(path)
    return path


class TestSeveralViews:
    def test_a_turnaround_sheet_is_reconstructed_view_by_view(
        self, sheet_image, tmp_path
    ):
        pytest.importorskip("torchmcubes", reason="fusion needs a surface extractor")
        engine = SphereEngine()
        emitter = RecordingEmitter()

        Worker(engine, emitter).run(
            make_request(sheet_image, tmp_path / "job")
        )

        assert len(engine.received) == 3, "each view should be reconstructed"
        # Distinct prepared images, not the same file handed over three times.
        assert len({path.name for path in engine.received}) == 3
        # One of them is chosen. Several views earn their keep by letting the
        # best be identified, which one picture cannot do — not by being blended
        # into a surface that no camera saw.
        assert emitter.of_type("result")[0]["viewCount"] == 1

    def test_a_sheet_can_be_taken_at_face_value(self, sheet_image, tmp_path):
        engine = SphereEngine()
        emitter = RecordingEmitter()

        Worker(engine, emitter).run(
            make_request(sheet_image, tmp_path / "job", splitSheet=False)
        )

        assert len(engine.received) == 1
        assert emitter.of_type("result")[0]["viewCount"] == 1

    def test_an_ordinary_image_is_still_one_view(self, source_image, tmp_path):
        engine = SphereEngine()
        emitter = RecordingEmitter()

        Worker(engine, emitter).run(make_request(source_image, tmp_path / "job"))

        assert len(engine.received) == 1
        assert emitter.of_type("result")[0]["viewCount"] == 1

    def test_views_can_be_supplied_as_separate_files(self, source_image, tmp_path):
        pytest.importorskip("torchmcubes", reason="fusion needs a surface extractor")
        engine = SphereEngine()
        emitter = RecordingEmitter()

        Worker(engine, emitter).run(
            GenerateRequest(
                jobId="job-1",
                sourcePath=str(source_image),
                workspace=str(tmp_path / "job"),
                viewPaths=(str(source_image),),
            )
        )

        assert len(engine.received) == 2
        # Every view is reconstructed; which one is used is then decided by the
        # pictures, and by default that is one of them rather than a blend.
        assert emitter.of_type("result")[0]["viewCount"] == 1

    def test_supplied_views_win_over_splitting_a_sheet(self, sheet_image, tmp_path):
        # An explicit list of views is a statement about the input; it must not
        # then be second-guessed by the sheet detector.
        pytest.importorskip("torchmcubes", reason="fusion needs a surface extractor")
        engine = SphereEngine()
        emitter = RecordingEmitter()

        Worker(engine, emitter).run(
            GenerateRequest(
                jobId="job-1",
                sourcePath=str(sheet_image),
                workspace=str(tmp_path / "job"),
                viewPaths=(str(sheet_image),),
            )
        )

        assert len(engine.received) == 2

    def test_progress_climbs_once_across_every_view(self, sheet_image, tmp_path):
        pytest.importorskip("torchmcubes", reason="fusion needs a surface extractor")
        emitter = RecordingEmitter()
        Worker(SphereEngine(), emitter).run(
            make_request(sheet_image, tmp_path / "job")
        )

        fractions = [m["fraction"] for m in emitter.of_type("progress")]
        assert fractions == sorted(fractions), "progress must never go backwards"

    def test_a_mismatched_set_of_angles_is_refused(self, sheet_image, tmp_path):
        emitter = RecordingEmitter()
        Worker(SphereEngine(), emitter).run(
            make_request(sheet_image, tmp_path / "job", viewYaws=(0.0, 90.0))
        )

        errors = emitter.of_type("error")
        assert errors and "3 views" in errors[0]["message"]

    def test_the_choice_is_reported_honestly(self, sheet_image, tmp_path):
        """Whatever model wins, the count must describe it.

        Every candidate — including the plain single-view model — is scored
        against the panels' own pictures, so which one wins depends on the
        subject. What must never vary is that the result says how many views
        actually went into what it returned. ``multiview.agreement`` is where
        the scoring itself is pinned down.
        """

        pytest.importorskip("torchmcubes", reason="fusion needs a surface extractor")
        emitter = RecordingEmitter()

        Worker(WrongDepthEngine(), emitter).run(
            make_request(
                sheet_image,
                tmp_path / "job",
                viewNames=("front", "right", "back"),
            )
        )

        result = emitter.of_type("result")[0]
        assert 1 <= result["viewCount"] <= 3
        assert emitter.of_type("error") == []

    def test_blending_is_available_but_not_the_default(self, sheet_image, tmp_path):
        """Fusing rebuilds the surface out of a voxel grid.

        On a real six-panel sheet that fixed the outline and flattened the
        horns, softened the ears and smeared the muzzle — six views producing a
        worse model than one. It stays reachable, and it stays off.
        """

        pytest.importorskip("torchmcubes", reason="fusion needs a surface extractor")
        emitter = RecordingEmitter()

        Worker(SphereEngine(), emitter).run(
            make_request(sheet_image, tmp_path / "job", fuseViews=True)
        )

        assert emitter.of_type("result")[0]["viewCount"] > 1

    def test_analysis_reports_the_views_it_found(self, sheet_image):
        emitter = RecordingEmitter()
        Worker(SphereEngine(), emitter).analyse(
            AnalyseRequest(requestId="a1", sourcePath=str(sheet_image))
        )

        analysis = emitter.of_type("analysis")[0]
        assert analysis["viewCount"] == 3
        assert any("3 views" in note for note in analysis["notes"])

    def test_analysis_of_one_subject_reports_one_view(self, source_image):
        emitter = RecordingEmitter()
        Worker(SphereEngine(), emitter).analyse(
            AnalyseRequest(requestId="a1", sourcePath=str(source_image))
        )
        assert emitter.of_type("analysis")[0]["viewCount"] == 1
