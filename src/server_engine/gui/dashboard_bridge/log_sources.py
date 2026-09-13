from ._shared import *


class LogSourcesMixin(DashboardBridgeSignals):
    def _log_service_label(self, service: str, group: str) -> str:
        service_labels = {
            "apache": "Apache",
            "database": "Database",
            "mailpit": "Mailpit",
            "memcached": "Memcached",
            "mongodb": "MongoDB",
            "nginx": "Nginx",
            "node-projects": "Node",
            "php": "PHP",
            "postgresql": "PostgreSQL",
            "redis": "Redis",
        }
        label = service_labels.get(service, service.title())
        cleaned_group = group.strip()
        if not cleaned_group:
            return label
        if cleaned_group.lower().startswith(f"{service}-"):
            cleaned_group = cleaned_group[len(service) + 1 :]
        return f"{label} ({cleaned_group})"

    def _log_source_group(self, source_name: str, source_category: str) -> str:
        rel = Path(source_name)
        parts = [part for part in rel.parts if part not in {"", "."}]
        if len(parts) >= 3:
            return self._log_service_label(parts[0].lower(), parts[1])
        if source_category in {"php", "mailpit", "memcached", "mongodb", "postgresql", "redis", "database", "apache", "nginx", "node-projects"}:
            return self._log_service_label(source_category, Path(source_name).parent.name or source_category)
        return source_category.title() if source_category else "Logs"

    def _log_source_display_name(self, source_path: str) -> str:
        leaf = Path(source_path).name.strip()
        return leaf or source_path

    def _runtime_log_payload(
        self,
        source_id: str,
        source_name: str,
        source_path: Path,
        category: str,
        group_label: str,
    ) -> dict[str, str]:
        return {
            "id": source_id,
            "name": source_name,
            "path": str(source_path),
            "category": category,
            "groupLabel": group_label,
            "size": str(source_path.stat().st_size if source_path.exists() else 0),
            "modified": int(source_path.stat().st_mtime) if source_path.exists() else 0,
        }

    def _has_group_item(self, items: list[dict[str, str]], category: str, group_label: str) -> bool:
        for item in items:
            if str(item.get("category", "")).lower() != category.lower():
                continue
            if str(item.get("groupLabel", "")) == group_label:
                return True
        return False

    @Property("QVariantList", notify=dataChanged)
    def logSourceItems(self) -> list[dict[str, str]]:
        items: list[dict[str, str]] = []
        seen_ids: set[str] = set()
        seen_paths: set[str] = set()
        try:
            for source in self._container.log_service.list_sources():
                try:
                    source_id = str(source.id)
                    source_name = str(source.name)
                    source_path = str(source.path)
                    normalized_path = str(Path(source_path).resolve()) if source_path else source_path
                    source_category = str(source.category)
                    path = Path(source_path)
                    display_name = self._log_source_display_name(source_path)
                    group_label = self._log_source_group(source_name, source_category)
                    size = path.stat().st_size if path.exists() else 0
                    modified = int(path.stat().st_mtime) if path.exists() else 0
                    seen_ids.add(source_id)
                    seen_paths.add(normalized_path)
                    items.append(
                        {
                            "id": source_id,
                            "name": display_name,
                            "path": source_path,
                            "category": source_category,
                            "groupLabel": group_label,
                            "size": str(size),
                            "modified": modified,
                        }
                    )
                except Exception:
                    continue

            for runtime in self._container.php_runtime_service.list_runtimes():
                try:
                    version = str(runtime.version)
                    source_id = f"php-runtime-{version.replace('.', '_')}"
                    if source_id in seen_ids:
                        continue
                    path = self._php_runtime_specific_log_path(version)
                    if not path.exists() or not path.is_file():
                        continue
                    normalized_path = str(path.resolve())
                    if normalized_path in seen_paths:
                        continue
                    seen_paths.add(normalized_path)
                    group_label = self._log_service_label("php", version)
                    if self._has_group_item(items, "php", group_label):
                        continue
                    items.append(self._runtime_log_payload(source_id, path.name, path, "php", group_label))
                except Exception:
                    continue

            for runtime in self._container.database_runtime_service.list_runtimes():
                try:
                    if runtime.engine not in {"mongodb", "postgresql"}:
                        continue
                    source_id = f"{runtime.engine}-runtime-{runtime.id}"
                    if source_id in seen_ids:
                        continue
                    service = self._container.mongodb_service if runtime.engine == "mongodb" else self._container.postgresql_service
                    path = service.log_path(runtime)
                    normalized_path = str(path.resolve())
                    if normalized_path in seen_paths:
                        continue
                    group_label = self._log_service_label(runtime.engine, runtime.version)
                    if self._has_group_item(items, runtime.engine, group_label):
                        continue
                    seen_paths.add(normalized_path)
                    items.append(self._runtime_log_payload(source_id, path.name, path, runtime.engine, group_label))
                except Exception:
                    continue

            for project in self._container.node_project_service.list_projects():
                try:
                    source_id = f"node-project-log-{project.id}"
                    if source_id in seen_ids:
                        continue
                    path = self._container.node_project_runtime_service.log_path(project.id)
                    normalized_path = str(path.resolve())
                    if normalized_path in seen_paths:
                        continue
                    label = project.name.strip() or project.local_domain.strip() or project.id
                    group_label = self._log_service_label("node-projects", label)
                    if self._has_group_item(items, "node-projects", group_label):
                        continue
                    seen_paths.add(normalized_path)
                    items.append(self._runtime_log_payload(source_id, path.name, path, "node-projects", group_label))
                except Exception:
                    continue
        except Exception:
            return []
        items.sort(
            key=lambda item: (
                -int(item.get("modified", 0) or 0),
                str(item.get("category", "")).lower(),
                str(item.get("name", "")).lower(),
            )
        )
        return items

    @Slot(str, int, result=str)
    def readLogTail(self, source_id: str, lines: int) -> str:
        try:
            amount = lines if lines > 0 else 200
            virtual_path = self._virtual_log_source_path(source_id.strip())
            if virtual_path is not None:
                if not virtual_path.exists():
                    return f"Log file has not been created yet: {virtual_path}"
                content = virtual_path.read_text(encoding="utf-8", errors="replace")
                return "\n".join(content.splitlines()[-amount:])
            return self._container.log_service.read_tail(source_id.strip(), amount)
        except Exception as exc:
            return str(exc)

    @Slot(str, result=str)
    def readLogFile(self, source_id: str) -> str:
        try:
            virtual_path = self._virtual_log_source_path(source_id.strip())
            if virtual_path is not None:
                if not virtual_path.exists():
                    return f"Log file has not been created yet: {virtual_path}"
                return virtual_path.read_text(encoding="utf-8", errors="replace")
            return self._container.log_service.read_file(source_id.strip())
        except Exception as exc:
            return str(exc)
