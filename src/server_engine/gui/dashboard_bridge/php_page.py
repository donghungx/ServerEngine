from ._shared import *


class PhpPageMixin(DashboardBridgeSignals):
    def _cleanup_phpinfo_job(self) -> None:
        if self._phpinfo_thread is not None:
            self._phpinfo_thread.deleteLater()
        self._phpinfo_thread = None
        self._phpinfo_worker = None

    @Slot(str)
    def requestPhpRuntimePhpInfo(self, version: str) -> None:
        cleaned = (version or "").strip()
        if not cleaned:
            self.phpInfoReady.emit("", False, "PHP runtime version is missing.", "")
            return

        self._phpinfo_pending_version = cleaned
        if self._phpinfo_thread is not None and self._phpinfo_thread.isRunning():
            return

        thread = QThread(self)
        worker = PhpInfoWorker(self._container, cleaned)
        worker.moveToThread(thread)
        thread.started.connect(worker.run)
        worker.completed.connect(self._handle_phpinfo_ready)
        worker.completed.connect(thread.quit)
        worker.completed.connect(worker.deleteLater)
        thread.finished.connect(self._cleanup_phpinfo_job)

        self._phpinfo_thread = thread
        self._phpinfo_worker = worker
        thread.start()

    @Slot(str, bool, str, str)
    def _handle_phpinfo_ready(self, version: str, ok: bool, message: str, content: str) -> None:
        self.phpInfoReady.emit(version, ok, message, content)
        pending = self._phpinfo_pending_version.strip()
        self._phpinfo_pending_version = ""
        if pending and pending != version.strip():
            QTimer.singleShot(0, lambda v=pending: self.requestPhpRuntimePhpInfo(v))

    @Property("QVariantList", notify=dataChanged)
    def phpVersions(self) -> list[str]:
        versions = self._container.php_runtime_service.list_versions()
        return versions or [self._container.settings_service.get_settings().default_php_version]

    @Property("QVariantList", notify=dataChanged)
    def wordpressVersions(self) -> list[str]:
        return self._wordpress_versions()

    @Property("QVariantList", notify=dataChanged)
    def laravelVersions(self) -> list[str]:
        return self._laravel_versions()

    def _laravel_versions(self) -> list[str]:
        payload = self._laravel_versions_payload()
        versions = [str(item.get("version", "")).strip() for item in payload if str(item.get("version", "")).strip()]
        if versions:
            return versions
        return ["12.0.0", "11.0.0", "10.0.0"]

    def _laravel_versions_payload(self) -> list[dict[str, str]]:
        cache_path = self._container.runtime_paths.temp_dir / "laravel_versions.json"
        max_cache_age = 24 * 60 * 60
        try:
            if cache_path.exists() and time.time() - cache_path.stat().st_mtime < max_cache_age:
                cached = json.loads(cache_path.read_text(encoding="utf-8"))
                versions = cached.get("versions", []) if isinstance(cached, dict) else []
                if isinstance(versions, list) and versions:
                    cleaned: list[dict[str, str]] = []
                    for item in versions:
                        if isinstance(item, dict):
                            version = str(item.get("version", "")).strip()
                            require_php = str(item.get("require_php", "")).strip()
                            if version:
                                cleaned.append({"version": version, "require_php": require_php})
                    if cleaned:
                        return cleaned
            request = urllib.request.Request(
                "https://repo.packagist.org/p2/laravel/laravel.json",
                headers=self._request_headers({"User-Agent": "ServerEngine/1.0"}),
            )
            with urllib.request.urlopen(request, timeout=15, context=default_ssl_context(request.full_url)) as response:
                data = json.loads(response.read().decode("utf-8", errors="replace"))
            packages = data.get("packages", {}).get("laravel/laravel", [])
            rows: list[dict[str, str]] = []
            for entry in packages:
                if not isinstance(entry, dict):
                    continue
                version = str(entry.get("version", "")).strip()
                lowered = version.lower()
                if not version or any(tag in lowered for tag in ("dev", "alpha", "beta", "rc")):
                    continue
                normalized = version.lstrip("v")
                require_php = str((entry.get("require") or {}).get("php", "")).strip()
                rows.append({"version": normalized, "require_php": require_php})
            dedup: dict[str, dict[str, str]] = {}
            for row in rows:
                ver = row["version"]
                if ver not in dedup:
                    dedup[ver] = row
            sorted_rows = sorted(dedup.values(), key=lambda item: self._semver_key(item["version"]), reverse=True)
            by_major: dict[int, dict[str, str]] = {}
            for item in sorted_rows:
                major = self._semver_key(item["version"])[0]
                if major <= 0:
                    continue
                if major not in by_major:
                    by_major[major] = item
            result = [by_major[key] for key in sorted(by_major.keys(), reverse=True)][:8]
            cache_path.parent.mkdir(parents=True, exist_ok=True)
            cache_path.write_text(json.dumps({"versions": result}, ensure_ascii=True), encoding="utf-8")
            return result
        except Exception:
            if cache_path.exists():
                try:
                    cached = json.loads(cache_path.read_text(encoding="utf-8"))
                    versions = cached.get("versions", []) if isinstance(cached, dict) else []
                    if isinstance(versions, list):
                        return [
                            {"version": str(item.get("version", "")).strip(), "require_php": str(item.get("require_php", "")).strip()}
                            for item in versions
                            if isinstance(item, dict) and str(item.get("version", "")).strip()
                        ]
                except Exception:
                    pass
            return [{"version": "12.0.0", "require_php": ""}, {"version": "11.0.0", "require_php": ""}, {"version": "10.0.0", "require_php": ""}]

    def _php_constraint_matches(self, php_version: str, constraint: str) -> bool:
        version = self._semver_key(php_version)
        raw = (constraint or "").strip()
        if not raw:
            return True
        ors = [part.strip() for part in re.split(r"\|\|?", raw) if part.strip()]
        if not ors:
            return True
        for part in ors:
            if self._php_constraint_and_matches(version, part):
                return True
        return False

    def _php_constraint_and_matches(self, version: tuple[int, int, int], expression: str) -> bool:
        tokens = [token.strip() for token in re.split(r"[,\s]+", expression.strip()) if token.strip()]
        if not tokens:
            return True
        for token in tokens:
            if not self._php_constraint_token_matches(version, token):
                return False
        return True

    def _php_constraint_token_matches(self, version: tuple[int, int, int], token: str) -> bool:
        cleaned = token.split("@", 1)[0].strip()
        if not cleaned or cleaned == "*":
            return True
        if cleaned.startswith("^"):
            base = self._semver_key(cleaned[1:])
            if version < base:
                return False
            upper = (base[0] + 1, 0, 0) if base[0] > 0 else (0, base[1] + 1, 0)
            return version < upper
        if cleaned.startswith("~"):
            base = self._semver_key(cleaned[1:])
            if version < base:
                return False
            upper = (base[0], base[1] + 1, 0)
            return version < upper
        if "*" in cleaned or "x" in cleaned.lower():
            wildcard = cleaned.lower().replace("x", "*")
            parts = [part for part in wildcard.split(".")]
            major = int(parts[0]) if parts and parts[0].isdigit() else 0
            minor = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 0
            if len(parts) <= 1 or parts[1] == "*":
                return (major, 0, 0) <= version < (major + 1, 0, 0)
            return (major, minor, 0) <= version < (major, minor + 1, 0)
        for op in (">=", "<=", ">", "<", "!=", "==", "="):
            if cleaned.startswith(op):
                target = self._semver_key(cleaned[len(op):])
                if op == ">=":
                    return version >= target
                if op == "<=":
                    return version <= target
                if op == ">":
                    return version > target
                if op == "<":
                    return version < target
                if op == "!=":
                    return version != target
                return version == target
        target = self._semver_key(cleaned)
        if cleaned.count(".") <= 1:
            return (target[0], target[1], 0) <= version < (target[0], target[1] + 1, 0)
        return version == target

    @Slot(str, str, result="QVariantMap")
    def laravelVersionCompatibility(self, laravel_version: str, current_php_version: str) -> dict[str, object]:
        selected = str(laravel_version or "").strip()
        if not selected:
            selected = self._laravel_versions()[0] if self._laravel_versions() else ""
        payload = self._laravel_versions_payload()
        require_php = ""
        for item in payload:
            if str(item.get("version", "")).strip() == selected:
                require_php = str(item.get("require_php", "")).strip()
                break
        installed = [str(version).strip() for version in self._container.php_runtime_service.list_versions() if str(version).strip()]
        installed.sort(key=self._semver_key)
        compatible = [version for version in installed if self._php_constraint_matches(version, require_php)]
        recommended = compatible[-1] if compatible else ""
        current = str(current_php_version or "").strip()
        current_ok = bool(current and self._php_constraint_matches(current, require_php))
        message = ""
        if not compatible:
            constraint_label = require_php or "unknown"
            message = f"No installed PHP version matches Laravel {selected} requirement ({constraint_label})."
        elif current and not current_ok:
            message = f"Laravel {selected} works best with PHP {recommended}."
        return {
            "compatible": bool(compatible) and (current_ok or not current),
            "recommended_php": recommended,
            "require_php": require_php,
            "message": message,
        }

    def _wordpress_versions(self) -> list[str]:
        fallback = ["Latest"]
        cache_path = self._container.runtime_paths.temp_dir / "wordpress_versions.json"
        max_cache_age = 24 * 60 * 60
        stale_versions: list[str] = []

        try:
            if cache_path.exists() and time.time() - cache_path.stat().st_mtime < max_cache_age:
                cached = json.loads(cache_path.read_text(encoding="utf-8"))
                versions = cached.get("versions", []) if isinstance(cached, dict) else []
                cleaned = [str(version).strip() for version in versions if str(version).strip()]
                if cleaned:
                    return cleaned
            if cache_path.exists():
                cached = json.loads(cache_path.read_text(encoding="utf-8"))
                versions = cached.get("versions", []) if isinstance(cached, dict) else []
                stale_versions = [str(version).strip() for version in versions if str(version).strip()]
        except Exception:
            pass

        try:
            request = urllib.request.Request(
                "https://api.wordpress.org/core/version-check/1.7/",
                headers=self._request_headers({"User-Agent": "ServerEngine/1.0"}),
            )
            with urllib.request.urlopen(request, timeout=3, context=default_ssl_context(request.full_url)) as response:
                payload = json.loads(response.read().decode("utf-8"))
            versions: list[str] = []
            for offer in payload.get("offers", []):
                version = str(offer.get("current") or offer.get("version") or "").strip()
                if version and version not in versions:
                    versions.append(version)
            if versions:
                values = versions
                cache_path.parent.mkdir(parents=True, exist_ok=True)
                cache_path.write_text(json.dumps({"versions": values, "cached_at": time.time()}), encoding="utf-8")
                return values
        except Exception:
            pass

        return stale_versions or fallback

    @Property("QVariantList", notify=dataChanged)
    def phpRuntimeItems(self) -> list[dict[str, str]]:
        runtimes = self._container.php_runtime_service.list_runtimes()
        items: list[dict[str, str]] = []
        for runtime in runtimes:
            items.append(
                {
                    "version": runtime.version,
                    "label": runtime.label,
                    "php_path": runtime.php_path,
                    "php_cgi_path": runtime.php_cgi_path,
                    "ini_dir": runtime.ini_dir,
                    "home": runtime.home,
                    "status": "Detected",
                }
            )
        return items

    @Property(bool, notify=phpExtensionsChanged)
    def phpExtensionActionBusy(self) -> bool:
        return self._php_extension_action_busy

    @Property(str, notify=phpExtensionsChanged)
    def phpExtensionActionTarget(self) -> str:
        return self._php_extension_action_target

    @Slot(str, result="QVariantList")
    def phpExtensionItems(self, version: str) -> list[dict[str, object]]:
        try:
            runtime = self._container.php_runtime_service.require_runtime(version)
            enabled = self._php_enabled_extensions(version)
            ext_dir = self._php_extension_dir(runtime)
            items: list[dict[str, object]] = []
            catalog = [
                ("redis", "Cache", "Redis client extension"),
                ("memcached", "Cache", "Memcached client extension"),
                ("apcu", "Cache", "In-process user cache"),
                ("opcache", "Performance", "Bytecode cache"),
                ("imagick", "Media", "ImageMagick bindings"),
                ("intl", "Core", "Internationalization support"),
                ("xdebug", "Debug", "Debugging and profiling"),
            ]
            for name, category, desc in catalog:
                so_name = f"{name}.so"
                if name == "opcache":
                    so_name = "opcache.so"
                installed = (ext_dir / so_name).exists()
                is_enabled = name in enabled
                items.append(
                    {
                        "name": name,
                        "category": category,
                        "description": desc,
                        "installed": installed,
                        "enabled": is_enabled,
                        "status": "Enabled" if is_enabled else ("Installed" if installed else "Not installed"),
                        "actionLabel": "Disable" if is_enabled else ("Enable" if installed else "Install"),
                    }
                )
            return items
        except Exception:
            return []

    @Slot(str, str, bool, result=bool)
    def setPhpExtensionEnabled(self, version: str, extension_name: str, enabled: bool) -> bool:
        key = f"{version}:{extension_name}"
        if self._php_extension_action_busy:
            self._last_operation_message = "Another extension action is in progress. Please wait."
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False
        self._php_extension_action_busy = True
        self._php_extension_action_target = key
        self.phpExtensionsChanged.emit()
        try:
            runtime = self._container.php_runtime_service.require_runtime(version)
            name = extension_name.strip().lower()
            if not name:
                raise ValueError("Extension name is required.")
            ext_dir = self._php_extension_dir(runtime)
            so_path = ext_dir / f"{name}.so"
            if not so_path.exists():
                raise ValueError(
                    f"{name}.so is not bundled in this PHP runtime. "
                    "This app uses prebundled extensions only. Rebuild/package PHP runtime with this extension included."
                )
            ini_path = self._php_ini_path(version)
            ini_path.parent.mkdir(parents=True, exist_ok=True)
            self._ensure_php_ini_default_backup(version, ini_path)
            self._create_php_ini_snapshot(version, ini_path)
            cache_exclusive = {"redis", "memcached", "apcu", "opcache"}
            if enabled and name in cache_exclusive:
                # Keep only one cache extension active at a time for safer defaults.
                for other in cache_exclusive:
                    if other != name:
                        self._set_php_extension_state(ini_path, other, False)
            self._set_php_extension_state(ini_path, name, enabled)
            state_label = "enabled" if enabled else "disabled"
            self._last_operation_message = f"{name} {state_label} for PHP {version}. Restart web server to apply."
            self._last_operation_error = False
            self.operationFeedbackChanged.emit()
            self.phpExtensionsChanged.emit()
            return True
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            self.phpExtensionsChanged.emit()
            return False
        finally:
            self._php_extension_action_busy = False
            self._php_extension_action_target = ""
            self.phpExtensionsChanged.emit()

    @Property("QVariantList", notify=dataChanged)
    def phpTimezoneItems(self) -> list[dict[str, str]]:
        try:
            data_path = self._container.binary_locator.project_root / "src" / "server_engine" / "gui" / "qml" / "data" / "timezones.json"
            if not data_path.exists():
                return [{"label": "(UTC+00:00) UTC", "value": "UTC"}]
            payload = json.loads(data_path.read_text(encoding="utf-8"))
            items: list[dict[str, str]] = []
            if isinstance(payload, list):
                for entry in payload:
                    if isinstance(entry, str):
                        value = entry.strip()
                        if value:
                            items.append({"label": value, "value": value})
                        continue
                    if not isinstance(entry, dict):
                        continue
                    label = str(entry.get("text", "")).strip()
                    utc_values = entry.get("utc", [])
                    value = ""
                    if isinstance(utc_values, list) and len(utc_values) > 0:
                        value = str(utc_values[0] or "").strip()
                    if not value:
                        value = str(entry.get("value", "")).strip()
                    if not label:
                        label = value
                    if label and value:
                        items.append({"label": label, "value": value})
            elif isinstance(payload, dict):
                raw = payload.get("timezones", [])
                if isinstance(raw, list):
                    for entry in raw:
                        if isinstance(entry, str):
                            value = entry.strip()
                            if value:
                                items.append({"label": value, "value": value})
                            continue
                        if not isinstance(entry, dict):
                            continue
                        label = str(entry.get("text", "")).strip()
                        utc_values = entry.get("utc", [])
                        value = ""
                        if isinstance(utc_values, list) and len(utc_values) > 0:
                            value = str(utc_values[0] or "").strip()
                        if not value:
                            value = str(entry.get("value", "")).strip()
                        if not label:
                            label = value
                        if label and value:
                            items.append({"label": label, "value": value})
            deduped: list[dict[str, str]] = []
            seen: set[str] = set()
            # Always include canonical UTC option first.
            deduped.append({"label": "(UTC+00:00) UTC", "value": "UTC"})
            seen.add("UTC")
            for item in items:
                value = str(item.get("value", "")).strip()
                label = str(item.get("label", "")).strip()
                if not value or not label or value in seen:
                    continue
                seen.add(value)
                deduped.append({"label": label, "value": value})
            return deduped
        except Exception:
            return [{"label": "(UTC+00:00) UTC", "value": "UTC"}]

    @Property(bool, notify=actionStateChanged)
    def phpRuntimeServiceActionBusy(self) -> bool:
        return self._php_runtime_service_action_busy

    @Property(str, notify=operationFeedbackChanged)
    def phpRuntimeServiceMessage(self) -> str:
        return self._php_runtime_service_message

    @Property(bool, notify=operationFeedbackChanged)
    def phpRuntimeServiceError(self) -> bool:
        return self._php_runtime_service_error

    def _php_runtime_service_id(self, version: str) -> str:
        return "php-cgi-" + version.strip().replace(".", "_")

    @Slot(str, result="QVariantMap")
    def phpRuntimeServiceState(self, version: str) -> dict:
        try:
            cleaned = version.strip()
            if not cleaned:
                return {
                    "state": "Stopped",
                    "pid": "-",
                    "cpu": "-",
                    "ram": "-",
                    "port": "",
                    "message": "",
                    "running": False,
                    "started_at": "-",
                    "pool": "www",
                    "process_mode": "Dynamic",
                    "accepted_connections": "-",
                    "listen_queue": "0",
                    "max_listen_queue": "0",
                    "listen_queue_len": "0",
                    "idle_processes": "0",
                    "active_processes": "0",
                    "total_processes": "0",
                    "max_active_processes": "0",
                    "max_children_reached": "0",
                    "slow_requests": "0",
                }
            settings = self._container.settings_service.get_settings()
            if settings.active_web_server != settings.active_web_server.NGINX:
                return {
                    "state": "Unavailable",
                    "pid": "-",
                    "cpu": "-",
                    "ram": "-",
                    "port": "",
                    "message": "Service controls are available only when Nginx is active.",
                    "running": False,
                    "started_at": "-",
                    "pool": "www",
                    "process_mode": "Dynamic",
                    "accepted_connections": "-",
                    "listen_queue": "0",
                    "max_listen_queue": "0",
                    "listen_queue_len": "0",
                    "idle_processes": "0",
                    "active_processes": "0",
                    "total_processes": "0",
                    "max_active_processes": "0",
                    "max_children_reached": "0",
                    "slow_requests": "0",
                }
            service_id = self._php_runtime_service_id(cleaned)
            status = self._container.stack_service.status()
            service = next((item for item in status.services if item.service_id == service_id), None)
            if service is None:
                return {
                    "state": "Unavailable",
                    "pid": "-",
                    "cpu": "-",
                    "ram": "-",
                    "port": "",
                    "message": f"PHP runtime service not found for version {cleaned}.",
                    "running": False,
                    "started_at": "-",
                    "pool": "www",
                    "process_mode": "Dynamic",
                    "accepted_connections": "-",
                    "listen_queue": "0",
                    "max_listen_queue": "0",
                    "listen_queue_len": "0",
                    "idle_processes": "0",
                    "active_processes": "0",
                    "total_processes": "0",
                    "max_active_processes": "0",
                    "max_children_reached": "0",
                    "slow_requests": "0",
                }
            cpu, ram = self._process_usage(service.pid)
            running = service.state.value == "running"
            runtime_message = service.message or ""
            if running and not runtime_message:
                runtime_message = "php-cgi runtime is running. Detailed pool counters are unavailable for this backend."
            return {
                "state": service.state.value.title(),
                "pid": str(service.pid) if service.pid else "-",
                "cpu": cpu,
                "ram": ram,
                "port": str(service.port or ""),
                "message": runtime_message,
                "running": running,
                "started_at": str(service.started_at or "-"),
                "pool": "www",
                "process_mode": "Dynamic",
                "accepted_connections": "-" if running else "0",
                "listen_queue": "0",
                "max_listen_queue": "0",
                "listen_queue_len": "0",
                "idle_processes": "0" if not running else "1",
                "active_processes": "1" if running else "0",
                "total_processes": "1" if running else "0",
                "max_active_processes": "1" if running else "0",
                "max_children_reached": "0",
                "slow_requests": "0",
            }
        except Exception as exc:
            return {
                "state": "Error",
                "pid": "-",
                "cpu": "-",
                "ram": "-",
                "port": "",
                "message": str(exc),
                "running": False,
                "started_at": "-",
                "pool": "www",
                "process_mode": "Dynamic",
                "accepted_connections": "-",
                "listen_queue": "0",
                "max_listen_queue": "0",
                "listen_queue_len": "0",
                "idle_processes": "0",
                "active_processes": "0",
                "total_processes": "0",
                "max_active_processes": "0",
                "max_children_reached": "0",
                "slow_requests": "0",
            }

    def _start_php_runtime_service_action(self, action: str, version: str) -> bool:
        if self._php_runtime_service_action_busy:
            self._php_runtime_service_message = "PHP runtime service action already running."
            self._php_runtime_service_error = True
            self._last_operation_message = self._php_runtime_service_message
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False
        cleaned = version.strip()
        if not cleaned:
            self._php_runtime_service_message = "PHP version is required."
            self._php_runtime_service_error = True
            self._last_operation_message = self._php_runtime_service_message
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False
        self._php_runtime_service_action_busy = True
        self.actionStateChanged.emit()
        thread = QThread(self)
        worker = PhpRuntimeServiceActionWorker(self._container, action, cleaned)
        worker.moveToThread(thread)
        worker.completed.connect(self._on_php_runtime_service_action_completed)
        worker.completed.connect(thread.quit)
        thread.started.connect(worker.run)
        thread.finished.connect(worker.deleteLater)
        thread.finished.connect(thread.deleteLater)
        self._php_runtime_service_action_thread = thread
        self._php_runtime_service_action_worker = worker
        thread.start()
        return True

    @Slot(bool, str)
    def _on_php_runtime_service_action_completed(self, success: bool, message: str) -> None:
        self._php_runtime_service_action_busy = False
        self._php_runtime_service_message = message
        self._php_runtime_service_error = not success
        self._last_operation_message = message
        self._last_operation_error = not success
        self._php_runtime_service_action_thread = None
        self._php_runtime_service_action_worker = None
        self.dataChanged.emit()
        self.operationFeedbackChanged.emit()
        self.actionStateChanged.emit()

    @Slot(str, result=bool)
    def startPhpRuntimeServiceAsync(self, version: str) -> bool:
        return self._start_php_runtime_service_action("start", version)

    @Slot(str, result=bool)
    def stopPhpRuntimeServiceAsync(self, version: str) -> bool:
        return self._start_php_runtime_service_action("stop", version)

    @Slot(str, result=bool)
    def restartPhpRuntimeServiceAsync(self, version: str) -> bool:
        return self._start_php_runtime_service_action("restart", version)

    @Slot(str, result=bool)
    def reloadPhpRuntimeServiceAsync(self, version: str) -> bool:
        return self._start_php_runtime_service_action("reload", version)

    @Slot(str, result=str)
    def phpIniContent(self, version: str) -> str:
        try:
            ini_path = self._php_ini_path(version)
            if not ini_path.exists():
                return ""
            return ini_path.read_text(encoding="utf-8")
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return ""

    @Slot(str, result=str)
    def phpRuntimeLogPath(self, version: str) -> str:
        return str(self._php_runtime_log_path(version))

    @Slot(str, int, result=str)
    def phpRuntimeLogTail(self, version: str, lines: int) -> str:
        try:
            amount = lines if lines > 0 else 250
            path = self._php_runtime_log_path(version)
            if not path.exists():
                return ""
            content = path.read_text(encoding="utf-8", errors="replace")
            rows = content.splitlines()
            return "\n".join(rows[-amount:])
        except Exception:
            return ""

    @Slot(str, int, result="QVariantMap")
    def phpRuntimeRelatedLog(self, version: str, lines: int) -> dict:
        amount = lines if lines > 0 else 250
        cleaned = version.strip().lower()
        token_dash = cleaned.replace(".", "-")
        token_under = cleaned.replace(".", "_")
        candidates: list[tuple[int, Path]] = []
        try:
            for source in self._container.log_service.list_sources():
                source_path = Path(source.path)
                if not source_path.exists() or not source_path.is_file():
                    continue
                name = source_path.name.lower()
                rel_name = str(source.name).lower()
                score = -1
                if name == f"php-{token_dash}.log":
                    score = 100
                elif name == f"php_{token_under}.log":
                    score = 95
                elif cleaned in name or cleaned in rel_name:
                    score = 85
                elif source.category == "php" and name == "php.log":
                    score = 80
                elif source.category == "php":
                    score = 70
                elif source.category in {"apache", "nginx"} and "error" in name:
                    score = 50
                if score >= 0:
                    candidates.append((score, source_path))
            candidates.sort(key=lambda item: (item[0], item[1].stat().st_mtime), reverse=True)
            for _, path in candidates:
                content = path.read_text(encoding="utf-8", errors="replace")
                tail = "\n".join(content.splitlines()[-amount:])
                if tail.strip():
                    return {
                        "path": str(path),
                        "content": tail,
                        "message": "",
                    }
            # Return best path even if empty so UI shows where it looked.
            if candidates:
                return {
                    "path": str(candidates[0][1]),
                    "content": "",
                    "message": "Log file found but no entries yet.",
                }
            return {
                "path": str(self._php_runtime_log_path(version)),
                "content": "",
                "message": "No related runtime log file found.",
            }
        except Exception as exc:
            return {
                "path": str(self._php_runtime_log_path(version)),
                "content": "",
                "message": str(exc),
            }

    @Slot(str, result="QVariantMap")
    def phpRuntimePhpInfo(self, version: str) -> dict:
        try:
            if not self._active_web_server_running():
                return {
                    "ok": False,
                    "message": "Start Apache/Nginx first, then reload phpinfo.",
                    "html": "",
                }
            runtime = self._container.php_runtime_service.require_runtime(version)
            result = subprocess.run(
                [runtime.php_path, "-d", "html_errors=1", "-r", "phpinfo();"],
                capture_output=True,
                text=True,
                check=False,
                timeout=15,
            )
            html = (result.stdout or "").strip()
            if result.returncode != 0:
                details = (result.stderr or result.stdout or "").strip()
                return {
                    "ok": False,
                    "message": details or f"phpinfo() failed for PHP {version}",
                    "html": "",
                }
            if not html:
                return {
                    "ok": False,
                    "message": "phpinfo() returned no output.",
                    "html": "",
                }
            return {
                "ok": True,
                "message": f"Loaded phpinfo() from PHP {version}",
                "html": html,
            }
        except Exception as exc:
            return {
                "ok": False,
                "message": str(exc),
                "html": "",
            }

    @Slot(str, str, result=bool)
    def savePhpIni(self, version: str, content: str) -> bool:
        try:
            ini_path = self._php_ini_path(version)
            ini_path.parent.mkdir(parents=True, exist_ok=True)
            self._ensure_php_ini_default_backup(version, ini_path)
            self._create_php_ini_snapshot(version, ini_path)
            ini_path.write_text(content, encoding="utf-8")
            self._last_operation_message = f"Saved php.ini for PHP {version}"
            self._last_operation_error = False
            self.operationFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False

    @Slot(str, "QVariantList", result="QVariantMap")
    def phpIniDirectiveMap(self, version: str, keys: list) -> dict:
        try:
            ini_path = self._php_ini_path(version)
            directives = self._read_php_ini_directives(ini_path)
            result: dict[str, str] = {}
            for key in keys:
                key_name = str(key).strip()
                if not key_name:
                    continue
                result[key_name] = directives.get(key_name, "")
            return result
        except Exception:
            return {}

    @Slot(str, "QVariantList", result="QVariantMap")
    def phpIniDefaultDirectiveMap(self, version: str, keys: list) -> dict:
        try:
            ini_path = self._php_ini_path(version)
            self._ensure_php_ini_default_backup(version, ini_path)
            backup_path = self._php_ini_default_backup_path(version)
            directives = self._read_php_ini_directives(backup_path)
            result: dict[str, str] = {}
            for key in keys:
                key_name = str(key).strip()
                if not key_name:
                    continue
                result[key_name] = directives.get(key_name, "")
            return result
        except Exception:
            return {}

    @Slot(str, "QVariantList", result="QVariantMap")
    def phpIniManagedDirectiveMap(self, version: str, keys: list) -> dict:
        """Return normalized directive values for UI-managed PHP settings.

        Uses current php.ini values when valid, otherwise falls back to the
        default-backup value, then a safe hardcoded fallback.
        """
        try:
            ini_path = self._php_ini_path(version)
            self._ensure_php_ini_default_backup(version, ini_path)
            current = self._read_php_ini_directives(ini_path)
            defaults = self._read_php_ini_directives(self._php_ini_default_backup_path(version))
            bool_keys = {"file_uploads", "short_open_tag", "display_errors", "cgi.fix_pathinfo"}
            error_reporting_allowed = {
                "E_ALL",
                "E_ALL & ~E_DEPRECATED",
                "E_ALL & ~E_STRICT",
                "E_ALL & ~E_DEPRECATED & ~E_STRICT",
                "E_ALL & ~E_NOTICE",
                "E_ALL & ~E_NOTICE & ~E_DEPRECATED & ~E_STRICT",
                "E_ALL & ~E_WARNING",
                "E_ALL & ~E_WARNING & ~E_NOTICE",
                "E_ERROR",
                "E_ERROR | E_WARNING",
                "E_ERROR | E_PARSE",
                "E_ERROR | E_WARNING | E_PARSE",
                "E_ERROR | E_WARNING | E_PARSE | E_NOTICE",
                "0",
            }
            result: dict[str, str] = {}
            for key in keys:
                key_name = str(key).strip()
                if not key_name:
                    continue
                raw = str(current.get(key_name, "")).strip()
                default_raw = str(defaults.get(key_name, "")).strip()
                if key_name in bool_keys:
                    lowered = raw.lower()
                    if lowered in {"1", "on", "true", "yes"}:
                        result[key_name] = "On"
                    elif lowered in {"0", "off", "false", "no"}:
                        result[key_name] = "Off"
                    else:
                        fallback = default_raw.lower()
                        result[key_name] = "On" if fallback in {"1", "on", "true", "yes"} else "Off"
                    continue
                if key_name == "error_reporting":
                    if raw in error_reporting_allowed:
                        result[key_name] = raw
                    elif default_raw in error_reporting_allowed:
                        result[key_name] = default_raw
                    else:
                        result[key_name] = "E_ALL & ~E_DEPRECATED & ~E_STRICT"
                    continue
                if key_name == "date.timezone":
                    invalid = {"", "on", "off", "1", "0", "true", "false", "yes", "no"}
                    if raw.lower() not in invalid:
                        result[key_name] = raw
                    elif default_raw.lower() not in invalid:
                        result[key_name] = default_raw
                    else:
                        result[key_name] = "UTC"
                    continue
                result[key_name] = raw if raw else default_raw
            return result
        except Exception:
            return {}

    @Slot(str, "QVariantMap", result=bool)
    def savePhpIniDirectiveMap(self, version: str, values: dict) -> bool:
        try:
            ini_path = self._php_ini_path(version)
            ini_path.parent.mkdir(parents=True, exist_ok=True)
            self._ensure_php_ini_default_backup(version, ini_path)
            self._create_php_ini_snapshot(version, ini_path)
            default_directives = self._read_php_ini_directives(self._php_ini_default_backup_path(version))
            normalized: dict[str, str] = {}
            bool_keys = {"file_uploads", "short_open_tag", "display_errors", "cgi.fix_pathinfo"}
            error_reporting_allowed = {
                "E_ALL",
                "E_ALL & ~E_DEPRECATED",
                "E_ALL & ~E_STRICT",
                "E_ALL & ~E_DEPRECATED & ~E_STRICT",
                "E_ALL & ~E_NOTICE",
                "E_ALL & ~E_NOTICE & ~E_DEPRECATED & ~E_STRICT",
                "E_ALL & ~E_WARNING",
                "E_ALL & ~E_WARNING & ~E_NOTICE",
                "E_ERROR",
                "E_ERROR | E_WARNING",
                "E_ERROR | E_PARSE",
                "E_ERROR | E_WARNING | E_PARSE",
                "E_ERROR | E_WARNING | E_PARSE | E_NOTICE",
                "0",
            }
            for key, value in dict(values).items():
                key_name = str(key).strip()
                if not key_name:
                    continue
                raw_value = str(value).strip()
                if key_name in bool_keys:
                    lowered = raw_value.lower()
                    if lowered in {"1", "on", "true", "yes"}:
                        normalized[key_name] = "On"
                    elif lowered in {"0", "off", "false", "no"}:
                        normalized[key_name] = "Off"
                    else:
                        normalized[key_name] = default_directives.get(key_name, "Off")
                    continue
                if key_name == "error_reporting":
                    normalized[key_name] = (
                        raw_value
                        if raw_value in error_reporting_allowed
                        else default_directives.get(key_name, "E_ALL & ~E_DEPRECATED & ~E_STRICT")
                    )
                    continue
                if key_name == "date.timezone":
                    if not raw_value or raw_value.lower() in {"on", "off", "1", "0", "true", "false"}:
                        normalized[key_name] = default_directives.get(key_name, "UTC") or "UTC"
                    else:
                        normalized[key_name] = raw_value
                    continue
                normalized[key_name] = raw_value
            self._write_php_ini_directives(ini_path, normalized)
            self._last_operation_message = (
                f"Saved PHP configuration for {version}. Restart web server to apply changes."
            )
            self._last_operation_error = False
            self.operationFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False

    @Slot(str, result=bool)
    def restorePhpIniDefault(self, version: str) -> bool:
        try:
            ini_path = self._php_ini_path(version)
            backup_path = self._php_ini_default_backup_path(version)
            if not backup_path.exists():
                raise ValueError(f"No default php.ini backup found for PHP {version}")
            ini_path.parent.mkdir(parents=True, exist_ok=True)
            self._create_php_ini_snapshot(version, ini_path)
            ini_path.write_text(backup_path.read_text(encoding="utf-8"), encoding="utf-8")
            self._last_operation_message = f"Restored default php.ini for PHP {version}"
            self._last_operation_error = False
            self.operationFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False

    @Slot(str, result=str)
    def phpIniDefaultBackupPath(self, version: str) -> str:
        return str(self._php_ini_default_backup_path(version))

    @Slot(str, result=bool)
    def ensurePhpIniDefaultBackup(self, version: str) -> bool:
        try:
            ini_path = self._php_ini_path(version)
            self._ensure_php_ini_default_backup(version, ini_path)
            return self._php_ini_default_backup_path(version).exists()
        except Exception:
            return False

    @Slot(str, result=str)
    def phpIniDefaultContent(self, version: str) -> str:
        try:
            ini_path = self._php_ini_path(version)
            self._ensure_php_ini_default_backup(version, ini_path)
            backup_path = self._php_ini_default_backup_path(version)
            if not backup_path.exists():
                return ""
            return backup_path.read_text(encoding="utf-8")
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return ""

    def _php_extension_dir(self, runtime) -> Path:
        # Prefer runtime-local extension directories (dist/deployed runtime truth).
        candidates = [
            Path(runtime.home) / "lib" / "php" / "extensions",
            Path(runtime.home) / "lib" / "php" / "modules",
            Path(runtime.home) / "modules",
        ]
        for base in candidates:
            if not base.exists():
                continue
            if any(child.is_file() and child.suffix == ".so" for child in base.glob("*.so")):
                return base
            subdirs = [child for child in base.iterdir() if child.is_dir()]
            for child in subdirs:
                if any(item.is_file() and item.suffix == ".so" for item in child.glob("*.so")):
                    return child
        # Fall back to php-config/php-reported extension dir for this runtime binary.
        php_config = Path(runtime.home) / "bin" / "php-config"
        try:
            if php_config.exists():
                result = subprocess.run(
                    [str(php_config), "--extension-dir"],
                    capture_output=True,
                    text=True,
                    timeout=8,
                    check=True,
                )
                ext_dir = Path(result.stdout.strip())
                if str(ext_dir).strip() and ext_dir.exists():
                    return ext_dir
        except Exception:
            pass
        try:
            result = subprocess.run(
                [runtime.php_path, "-i"],
                capture_output=True,
                text=True,
                timeout=8,
                check=True,
            )
            for line in result.stdout.splitlines():
                if "extension_dir =>" in line:
                    parts = [part.strip() for part in line.split("=>")]
                    if len(parts) >= 2 and parts[1]:
                        ext_dir = Path(parts[1])
                        if ext_dir.exists():
                            return ext_dir
        except Exception:
            pass
        return candidates[0]

    def _php_enabled_extensions(self, version: str) -> set[str]:
        ini_path = self._php_ini_path(version)
        if not ini_path.exists():
            return set()
        enabled: set[str] = set()
        for raw_line in ini_path.read_text(encoding="utf-8", errors="replace").splitlines():
            line = raw_line.strip()
            if not line or line.startswith(";") or line.startswith("#"):
                continue
            lowered = line.lower()
            if lowered.startswith("extension="):
                value = self._strip_ini_inline_comment(line.split("=", 1)[1].strip())
                value = value.strip('"').strip("'")
                if value.endswith(".so"):
                    value = value[:-3]
                enabled.add(value.lower())
            elif lowered.startswith("zend_extension="):
                value = self._strip_ini_inline_comment(line.split("=", 1)[1].strip())
                value = value.strip('"').strip("'")
                base = Path(value).name
                if base.endswith(".so"):
                    base = base[:-3]
                enabled.add(base.lower())
        return enabled

    def _set_php_extension_state(self, ini_path: Path, extension_name: str, enabled: bool) -> None:
        original_lines = ini_path.read_text(encoding="utf-8", errors="replace").splitlines() if ini_path.exists() else []
        target = extension_name.lower()
        found = False
        output_lines: list[str] = []

        def normalize_ext(value: str) -> str:
            raw = value.strip().strip('"').strip("'")
            raw = Path(raw).name
            if raw.endswith(".so"):
                raw = raw[:-3]
            return raw.lower()

        for raw_line in original_lines:
            stripped = raw_line.strip()
            if not stripped:
                output_lines.append(raw_line)
                continue
            uncommented = stripped.lstrip(";#").strip()
            lower_uncommented = uncommented.lower()
            if "=" in uncommented and (lower_uncommented.startswith("extension=") or lower_uncommented.startswith("zend_extension=")):
                key, value = uncommented.split("=", 1)
                key = key.strip().lower()
                if normalize_ext(value) == target:
                    found = True
                    if enabled:
                        if target == "opcache":
                            output_lines.append("zend_extension=opcache.so")
                        else:
                            output_lines.append(f"extension={target}.so")
                    else:
                        if target == "opcache":
                            output_lines.append("; zend_extension=opcache.so")
                        else:
                            output_lines.append(f"; extension={target}.so")
                    continue
            output_lines.append(raw_line)

        if enabled and not found:
            output_lines.append("")
            output_lines.append("; Added by Server Engine")
            if target == "opcache":
                output_lines.append("zend_extension=opcache.so")
            else:
                output_lines.append(f"extension={target}.so")

        ini_path.write_text("\n".join(output_lines).rstrip() + "\n", encoding="utf-8")

    def _php_ini_path(self, version: str) -> Path:
        runtime = self._container.php_runtime_service.require_runtime(version)
        return Path(runtime.ini_dir) / "php.ini"

    def _php_runtime_log_path(self, version: str) -> Path:
        runtime_specific = self._php_runtime_specific_log_path(version)
        if runtime_specific.exists():
            return runtime_specific
        settings = self._container.settings_service.get_settings()
        configured = (settings.php_runtime_log_dir or "").strip()
        if configured:
            configured_path = Path(configured).expanduser()
        else:
            configured_path = self._container.runtime_paths.logs_dir / "php.log"

        if configured_path.suffix:
            log_dir = configured_path.parent
        elif configured_path.name == "php.log":
            log_dir = configured_path.parent
        else:
            log_dir = configured_path

        cleaned = version.strip().replace("/", "-").replace("\\", "-")
        runtime_specific = log_dir / f"php-{cleaned}.log"
        if runtime_specific.exists():
            return runtime_specific
        return log_dir / "php.log"

    def _php_runtime_specific_log_path(self, version: str) -> Path:
        return self._container.config_service.php_runtime_log_path(version)

    def _php_ini_backup_dir(self, version: str) -> Path:
        sanitized = version.replace("/", "_").replace("\\", "_").strip() or "unknown"
        return self._container.runtime_paths.config_dir / "php-ini-backups" / sanitized

    def _php_ini_default_backup_path(self, version: str) -> Path:
        return self._php_ini_backup_dir(version) / "php.ini.default.bak"

    def _ensure_php_ini_default_backup(self, version: str, ini_path: Path) -> None:
        backup_path = self._php_ini_default_backup_path(version)
        if backup_path.exists() or not ini_path.exists():
            return
        backup_path.parent.mkdir(parents=True, exist_ok=True)
        backup_path.write_text(ini_path.read_text(encoding="utf-8"), encoding="utf-8")

    def _create_php_ini_snapshot(self, version: str, ini_path: Path) -> None:
        if not ini_path.exists():
            return
        snapshot_dir = self._php_ini_backup_dir(version) / "snapshots"
        snapshot_dir.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        snapshot_path = snapshot_dir / f"php.ini.{timestamp}.bak"
        snapshot_path.write_text(ini_path.read_text(encoding="utf-8"), encoding="utf-8")

    def _read_php_ini_directives(self, ini_path: Path) -> dict[str, str]:
        if not ini_path.exists():
            return {}
        directives: dict[str, str] = {}
        for raw_line in ini_path.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith(";") or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            directives[key.strip()] = self._strip_ini_inline_comment(value.strip())
        return directives

    def _strip_ini_inline_comment(self, raw: str) -> str:
        if not raw:
            return ""
        in_single = False
        in_double = False
        for index, char in enumerate(raw):
            if char == "'" and not in_double:
                in_single = not in_single
                continue
            if char == '"' and not in_single:
                in_double = not in_double
                continue
            if (char == ";" or char == "#") and not in_single and not in_double:
                return raw[:index].strip()
        return raw.strip()

    def _write_php_ini_directives(self, ini_path: Path, updates: dict[str, str]) -> None:
        existing_lines = ini_path.read_text(encoding="utf-8").splitlines() if ini_path.exists() else []
        managed = {key: value for key, value in updates.items() if key}
        written: set[str] = set()
        output_lines: list[str] = []
        for raw_line in existing_lines:
            stripped = raw_line.strip()
            if stripped.startswith(";") or stripped.startswith("#") or "=" not in stripped:
                output_lines.append(raw_line)
                continue
            key, _ = stripped.split("=", 1)
            key_name = key.strip()
            if key_name in managed:
                if key_name in written:
                    # Drop duplicate definitions for managed directives so PHP
                    # won't override earlier values with stale trailing lines.
                    continue
                output_lines.append(f"{key_name} = {managed[key_name]}")
                written.add(key_name)
            else:
                output_lines.append(raw_line)
        remaining_keys = [key for key in managed.keys() if key not in written]
        if remaining_keys:
            output_lines.append("")
            output_lines.append("; Added by Server Engine")
            for key in remaining_keys:
                output_lines.append(f"{key} = {managed[key]}")
        ini_path.write_text("\n".join(output_lines).rstrip() + "\n", encoding="utf-8")
