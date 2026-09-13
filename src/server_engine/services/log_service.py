from __future__ import annotations

from pathlib import Path
import re

from server_engine.core.models import LogSource, RuntimePaths


class LogService:
    def __init__(self, runtime_paths: RuntimePaths) -> None:
        self.runtime_paths = runtime_paths

    def list_sources(self) -> list[LogSource]:
        self.runtime_paths.logs_dir.mkdir(parents=True, exist_ok=True)
        sources: list[LogSource] = []
        for path in sorted(self.runtime_paths.logs_dir.rglob("*")):
            if not path.is_file():
                continue
            if path.name.startswith("."):
                continue
            if path.suffix.lower() not in {".log", ".txt"}:
                continue
            rel = path.relative_to(self.runtime_paths.logs_dir)
            source_id = self._source_id_from_relative(rel)
            sources.append(
                LogSource(
                    id=source_id,
                    name=str(rel),
                    path=str(path),
                    category=self._category_for_relative(rel),
                )
            )
        return sources

    def read_tail(self, source_id: str, lines: int = 100) -> str:
        source = next((item for item in self.list_sources() if item.id == source_id), None)
        if source is None:
            raise ValueError(f"Unknown log source: {source_id}")
        content = Path(source.path).read_text(encoding="utf-8", errors="replace")
        return "\n".join(content.splitlines()[-lines:])

    def read_file(self, source_id: str) -> str:
        source = next((item for item in self.list_sources() if item.id == source_id), None)
        if source is None:
            raise ValueError(f"Unknown log source: {source_id}")
        return Path(source.path).read_text(encoding="utf-8", errors="replace")

    def _source_id_from_relative(self, relative_path: Path) -> str:
        return re.sub(r"[^a-z0-9_\\-]+", "_", str(relative_path).lower())

    def _category_for_relative(self, relative_path: Path) -> str:
        if len(relative_path.parts) > 1:
            top = relative_path.parts[0].lower()
            if top == "app":
                return "general"
            if top.startswith("apache"):
                return "apache"
            if top.startswith("nginx"):
                return "nginx"
            if top.startswith("mailpit"):
                return "mailpit"
            if top.startswith("node"):
                return "node-projects"
            if top.startswith("database"):
                return "database"
            if top.startswith("memcached") or top.startswith("memcache"):
                return "memcached"
            return top
        name = relative_path.name.lower()
        if "apache" in name:
            return "apache"
        if "nginx" in name:
            return "nginx"
        if "php" in name:
            return "php"
        if "redis" in name:
            return "redis"
        if "memcached" in name or "memcache" in name:
            return "memcached"
        if "maria" in name or "mysql" in name or "database" in name:
            return "database"
        if "mailpit" in name:
            return "mailpit"
        if "node" in name:
            return "node"
        return "general"
