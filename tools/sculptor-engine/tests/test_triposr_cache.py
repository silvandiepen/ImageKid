"""The Hugging Face cache the engine uses.

TripoSR's image tokenizer builds its ViT from ``facebook/dino-vitb16``'s config,
which ``transformers`` resolves through the Hugging Face cache in the user's
home. A sandboxed app cannot read there, and the failure is late and ugly:

    could not load TripoSR: [Errno 1] Operation not permitted:
    '~/.cache/huggingface/hub/models--facebook--dino-vitb16/refs/main'

These pin the redirection that avoids it.
"""

from __future__ import annotations

import os

import pytest

from sculptor_engine.engines import triposr


@pytest.fixture(autouse=True)
def clean_environment(monkeypatch):
    for key in ("SCULPTOR_HF_HOME", "HF_HOME", "HF_HUB_OFFLINE", "TRANSFORMERS_OFFLINE"):
        monkeypatch.delenv(key, raising=False)


class TestBundledCache:
    def test_points_at_an_explicit_cache_and_goes_offline(self, tmp_path, monkeypatch):
        cache = tmp_path / "hf-cache"
        cache.mkdir()
        monkeypatch.setenv("SCULPTOR_HF_HOME", str(cache))

        triposr._use_bundled_hugging_face_cache()

        assert os.environ["HF_HOME"] == str(cache)
        # Offline matters as much as the path: a lookup that escaped to the
        # network would fail under the sandbox anyway, and slowly.
        assert os.environ["HF_HUB_OFFLINE"] == "1"
        assert os.environ["TRANSFORMERS_OFFLINE"] == "1"

    def test_does_nothing_when_there_is_no_bundled_cache(self, tmp_path, monkeypatch):
        # A development checkout should keep using the user's own cache.
        monkeypatch.setenv("SCULPTOR_HF_HOME", str(tmp_path / "absent"))

        triposr._use_bundled_hugging_face_cache()

        assert "HF_HOME" not in os.environ
        assert "HF_HUB_OFFLINE" not in os.environ

    def test_respects_a_cache_the_caller_already_chose(self, tmp_path, monkeypatch):
        cache = tmp_path / "hf-cache"
        cache.mkdir()
        monkeypatch.setenv("SCULPTOR_HF_HOME", str(cache))
        monkeypatch.setenv("HF_HOME", "/somewhere/deliberate")

        triposr._use_bundled_hugging_face_cache()

        assert os.environ["HF_HOME"] == "/somewhere/deliberate"

    def test_looks_beside_the_package_by_default(self, monkeypatch):
        # This is where bundle_runtime.sh puts it: <runtime>/hf-cache, a sibling
        # of the sculptor_engine package.
        root = triposr._package_root()
        assert (root / "sculptor_engine").is_dir(), (
            f"_package_root() should hold the package; got {root}"
        )
