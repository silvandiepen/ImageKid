"""Protocol encoding/decoding. This is the contract the Swift side depends on."""

from __future__ import annotations

import json
from dataclasses import asdict

import pytest

from sculptor_engine.protocol import (
    STAGE_WEIGHTS,
    CancelRequest,
    ErrorCode,
    GenerateOptions,
    GenerateRequest,
    ProtocolError,
    ResultArtifacts,
    ShutdownRequest,
    Stage,
    decode_request,
    error_message,
    progress_message,
    ready_message,
    result_message,
)


class TestDecodeRequest:
    def test_decodes_a_minimal_generate(self):
        request = decode_request(
            json.dumps(
                {
                    "type": "generate",
                    "jobId": "job-1",
                    "sourcePath": "/tmp/a.png",
                    "workspace": "/tmp/work",
                }
            )
        )
        assert isinstance(request, GenerateRequest)
        assert request.jobId == "job-1"
        assert request.maskPath is None
        assert request.options == GenerateOptions()

    def test_decodes_options_and_mask(self):
        request = decode_request(
            json.dumps(
                {
                    "type": "generate",
                    "jobId": "job-2",
                    "sourcePath": "/tmp/a.png",
                    "workspace": "/tmp/work",
                    "maskPath": "/tmp/mask.png",
                    "options": {"inputSize": 256, "lowMemory": True},
                }
            )
        )
        assert request.maskPath == "/tmp/mask.png"
        assert request.options.inputSize == 256
        assert request.options.lowMemory is True
        # Untouched options keep their defaults.
        assert request.options.cropPadding == GenerateOptions().cropPadding

    def test_decodes_cancel_and_shutdown(self):
        assert decode_request('{"type":"cancel","jobId":"j"}') == CancelRequest("j")
        assert isinstance(decode_request('{"type":"shutdown"}'), ShutdownRequest)

    @pytest.mark.parametrize(
        "line",
        [
            "not json",
            "[1,2,3]",
            '{"type":"nope"}',
            '{"type":"generate","jobId":"j"}',
            '{"type":"generate","jobId":"","sourcePath":"a","workspace":"b"}',
            '{"type":"generate","jobId":"j","sourcePath":"a","workspace":"b","maskPath":7}',
            '{"type":"cancel"}',
        ],
    )
    def test_rejects_malformed_input(self, line):
        with pytest.raises(ProtocolError):
            decode_request(line)

    def test_rejects_unknown_options_rather_than_ignoring_them(self):
        # A typo'd option must not silently do nothing.
        with pytest.raises(ProtocolError, match="unknown options: bakeResolution"):
            decode_request(
                '{"type":"generate","jobId":"j","sourcePath":"a","workspace":"b",'
                '"options":{"bakeResolution":512}}'
            )


class TestProgress:
    def test_stage_weights_sum_to_one(self):
        assert sum(STAGE_WEIGHTS.values()) == pytest.approx(1.0)

    def test_overall_fraction_increases_across_stages(self):
        fractions = [
            progress_message("j", stage, 0.0)["fraction"] for stage in Stage
        ]
        assert fractions == sorted(fractions)
        assert fractions[0] == 0.0

    def test_final_stage_completes_at_one(self):
        message = progress_message("j", Stage.PREPARING_PREVIEW, 1.0)
        assert message["fraction"] == pytest.approx(1.0)

    def test_stage_fraction_is_clamped(self):
        assert progress_message("j", Stage.RECONSTRUCTING, -3)["stageFraction"] == 0.0
        assert progress_message("j", Stage.RECONSTRUCTING, 9)["stageFraction"] == 1.0


class TestMessages:
    def test_ready_reports_engine_availability(self):
        message = ready_message("spar3d", False, "weights missing")
        assert message["type"] == "ready"
        assert message["engineAvailable"] is False
        assert message["detail"] == "weights missing"

    def test_model_not_installed_is_recoverable(self):
        message = error_message("j", ErrorCode.MODEL_NOT_INSTALLED, "no weights")
        assert message["recoverable"] is True
        assert message["code"] == "modelNotInstalled"

    def test_internal_error_is_not_recoverable(self):
        assert error_message("j", ErrorCode.INTERNAL_ERROR, "boom")["recoverable"] is False

    def test_result_keys_are_camel_case_for_swift_decoding(self):
        artifacts = ResultArtifacts(
            glbPath="/tmp/model.glb",
            previewPath="/tmp/preview.ply",
            exports={"obj": "/tmp/model.obj"},
            preparedImagePath="/tmp/prepared.png",
            viewCount=1,
            triangleCount=12,
            vertexCount=8,
            hasTexture=True,
            appliedScale=0.5,
            boundingBoxLongestEdge=1.0,
            upAxis="+Y",
            originConvention="bottomCentre",
            durationSeconds=1.25,
        )
        message = result_message("job-9", artifacts)
        assert message["type"] == "result"
        assert message["jobId"] == "job-9"
        for key in asdict(artifacts):
            assert key in message
            assert "_" not in key

    def test_every_message_survives_a_json_round_trip(self):
        messages = [
            ready_message("spar3d", True, None),
            progress_message("j", Stage.CLEANING_MODEL, 0.5),
            error_message("j", ErrorCode.CANCELLED, "stopped"),
        ]
        for message in messages:
            assert json.loads(json.dumps(message)) == message


class TestSeveralViews:
    def test_decodes_extra_view_paths(self):
        request = decode_request(
            json.dumps(
                {
                    "type": "generate",
                    "jobId": "job-3",
                    "sourcePath": "/w/front.png",
                    "workspace": "/w",
                    "viewPaths": ["/w/side.png", "/w/back.png"],
                }
            )
        )
        assert request.viewPaths == ("/w/side.png", "/w/back.png")

    def test_a_generate_without_views_is_a_single_image_job(self):
        request = decode_request(
            json.dumps(
                {
                    "type": "generate",
                    "jobId": "job-3",
                    "sourcePath": "/w/a.png",
                    "workspace": "/w",
                }
            )
        )
        assert request.viewPaths == ()
        assert request.options.splitSheet is True

    def test_an_empty_view_path_is_refused(self):
        with pytest.raises(ProtocolError):
            decode_request(
                json.dumps(
                    {
                        "type": "generate",
                        "jobId": "job-3",
                        "sourcePath": "/w/a.png",
                        "workspace": "/w",
                        "viewPaths": [""],
                    }
                )
            )

    def test_decodes_declared_camera_angles(self):
        options = GenerateOptions.from_dict({"viewYaws": [0, 90, 180]})
        assert options.viewYaws == (0.0, 90.0, 180.0)

    def test_camera_angles_must_be_numbers(self):
        with pytest.raises(ProtocolError):
            GenerateOptions.from_dict({"viewYaws": ["front"]})

    def test_sheet_splitting_can_be_turned_off(self):
        assert GenerateOptions.from_dict({"splitSheet": False}).splitSheet is False

    def test_decodes_named_views(self):
        options = GenerateOptions.from_dict(
            {"viewNames": ["front", "RIGHT", "back", "left", "top", "bottom"]}
        )
        assert options.viewNames == (
            "front", "right", "back", "left", "top", "bottom",
        )

    def test_an_unknown_view_name_is_refused_before_any_work_is_done(self):
        # A typo must fail here, not after a reconstruction per view.
        with pytest.raises(ProtocolError, match="unknown view name"):
            GenerateOptions.from_dict({"viewNames": ["fromt"]})

    def test_decodes_camera_elevations(self):
        options = GenerateOptions.from_dict({"viewPitches": [0, 90, -90]})
        assert options.viewPitches == (0.0, 90.0, -90.0)
