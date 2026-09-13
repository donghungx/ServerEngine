from __future__ import annotations

import os
from pathlib import Path

from server_engine.core.models import RuntimePaths


class PathProvider:
    def __init__(self, runtime_root: Path | None = None) -> None:
        self._runtime_root = runtime_root

    def resolve_root(self) -> Path:
        if self._runtime_root is not None:
            return self._runtime_root
        override = os.environ.get("SERVER_ENGINE_HOME")
        if override:
            return Path(override).expanduser()
        return Path.home() / "Library" / "Application Support" / "Server Engine"

    def build(self) -> RuntimePaths:
        root = self.resolve_root()
        config_dir = root / "config"
        return RuntimePaths(
            root=root,
            bin_dir=root / "bin",
            config_dir=config_dir,
            nginx_config_dir=config_dir / "nginx",
            php_config_dir=config_dir / "php",
            database_config_dir=config_dir / "database",
            redis_config_dir=config_dir / "redis",
            sites_config_dir=config_dir / "sites",
            logs_dir=root / "logs",
            data_dir=root / "data",
            backups_dir=root / "backups",
            runtime_dir=root / "runtime",
            temp_dir=root / "temp",
            db_path=root / "server_engine.db",
        )

    def ensure(self) -> RuntimePaths:
        runtime_paths = self.build()
        try:
            self._ensure_paths(runtime_paths)
            return runtime_paths
        except PermissionError:
            if self._runtime_root is not None or os.environ.get("SERVER_ENGINE_HOME"):
                raise
            fallback = Path.cwd() / ".server-engine-runtime"
            runtime_paths = PathProvider(runtime_root=fallback).build()
            self._ensure_paths(runtime_paths)
            return runtime_paths

    def _ensure_paths(self, runtime_paths: RuntimePaths) -> None:
        for path in runtime_paths.to_dict().values():
            candidate = Path(path)
            if candidate.suffix:
                candidate.parent.mkdir(parents=True, exist_ok=True)
            else:
                candidate.mkdir(parents=True, exist_ok=True)
