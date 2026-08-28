"""Model location and installation state.

The worker must never download weights; it only reports whether the app has
installed them. These tests pin that boundary.
"""

from __future__ import annotations

from sculptor_engine import models


class TestModelsRoot:
    def test_environment_override_wins(self, tmp_path, monkeypatch):
        monkeypatch.setenv("SCULPTOR_MODELS_DIR", str(tmp_path / "custom"))
        assert models.models_root() == tmp_path / "custom"

    def test_falls_back_to_application_support_without_an_app_group(
        self, tmp_path, monkeypatch
    ):
        monkeypatch.delenv("SCULPTOR_MODELS_DIR", raising=False)
        monkeypatch.setattr(models.Path, "home", staticmethod(lambda: tmp_path))
        root = models.models_root()
        assert root == tmp_path / "Library" / "Application Support" / "ImageKid" / "Models" / "Sculptor"

    def test_prefers_the_app_group_container_when_it_exists(self, tmp_path, monkeypatch):
        monkeypatch.delenv("SCULPTOR_MODELS_DIR", raising=False)
        container = tmp_path / "Library" / "Group Containers" / models.APP_GROUP_IDENTIFIER
        container.mkdir(parents=True)
        monkeypatch.setattr(models.Path, "home", staticmethod(lambda: tmp_path))
        assert models.models_root() == container / "Models" / "Sculptor"


class TestSPAR3DInstallation:
    def test_reports_every_missing_file(self, tmp_path):
        installation = models.spar3d_installation(tmp_path)
        assert installation.is_installed is False
        assert set(installation.missing_files) == set(models.SPAR3D_REQUIRED_FILES)

    def test_partial_install_is_not_installed(self, tmp_path):
        directory = tmp_path / "SPAR3D" / models.SPAR3D_VERSION
        directory.mkdir(parents=True)
        (directory / "config.yaml").write_text("{}")
        installation = models.spar3d_installation(tmp_path)
        assert installation.is_installed is False
        assert installation.missing_files == ("model.safetensors",)

    def test_complete_install_is_installed(self, tmp_path):
        directory = tmp_path / "SPAR3D" / models.SPAR3D_VERSION
        directory.mkdir(parents=True)
        for name in models.SPAR3D_REQUIRED_FILES:
            (directory / name).write_text("x")
        installation = models.spar3d_installation(tmp_path)
        assert installation.is_installed is True
        assert installation.describe_missing() == ""

    def test_missing_message_names_the_directory_and_files(self, tmp_path):
        message = models.spar3d_installation(tmp_path).describe_missing()
        assert "SPAR3D" in message
        assert "model.safetensors" in message
        assert str(tmp_path) in message

    def test_version_is_part_of_the_path(self, tmp_path):
        installation = models.spar3d_installation(tmp_path)
        assert installation.directory.name == models.SPAR3D_VERSION
