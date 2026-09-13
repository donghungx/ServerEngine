from __future__ import annotations

import logging

from server_engine.core.models import RuntimePaths
from server_engine.gui import app as gui_app


def _runtime_paths(root):
    return RuntimePaths(
        root=root,
        bin_dir=root / "bin",
        config_dir=root / "config",
        nginx_config_dir=root / "config" / "nginx",
        php_config_dir=root / "config" / "php",
        database_config_dir=root / "config" / "database",
        redis_config_dir=root / "config" / "redis",
        sites_config_dir=root / "config" / "sites",
        logs_dir=root / "logs",
        data_dir=root / "data",
        backups_dir=root / "backups",
        runtime_dir=root / "runtime",
        temp_dir=root / "temp",
        db_path=root / "server_engine.db",
    )


def test_seed_bundled_runtime_populates_existing_empty_directories(tmp_path, monkeypatch):
    source_root = tmp_path / "app" / "Contents" / "Resources" / "runtime"
    source_payload = source_root / "tools" / "composer"
    source_payload.mkdir(parents=True, exist_ok=True)
    (source_payload / "composer.phar").write_text("phar", encoding="utf-8")

    runtime_root = tmp_path / "Library" / "Application Support" / "Server Engine"
    (runtime_root / "bin" / "tools").mkdir(parents=True, exist_ok=True)
    old_php_runtime = runtime_root / "bin" / "php" / "php7.4.33"
    old_php_runtime.mkdir(parents=True, exist_ok=True)
    (old_php_runtime / "keep.txt").write_text("keep", encoding="utf-8")
    existing_composer = runtime_root / "bin" / "tools" / "composer"
    existing_composer.mkdir(parents=True, exist_ok=True)
    (existing_composer / "composer.phar").write_text("old", encoding="utf-8")

    monkeypatch.setattr(gui_app, "_bundled_runtime_root", lambda: source_root)
    monkeypatch.setattr(gui_app.PathProvider, "ensure", lambda self: _runtime_paths(runtime_root))
    monkeypatch.setattr(gui_app, "_bundled_app_version", lambda: "1.0.2")

    gui_app._seed_bundled_runtime_if_needed(logging.getLogger("test"))

    assert (runtime_root / "bin" / "tools" / "composer" / "composer.phar").read_text(encoding="utf-8") == "phar"
    assert (old_php_runtime / "keep.txt").read_text(encoding="utf-8") == "keep"
    marker = runtime_root / ".bundled_runtime_seed_1.0.2"
    assert marker.exists()
