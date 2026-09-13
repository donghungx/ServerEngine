from __future__ import annotations

from dataclasses import replace
import json
import logging
import os
import re
import shutil
import subprocess
import time
from pathlib import Path

from PySide6.QtCore import QObject, Signal, Slot

from server_engine.bootstrap import AppContainer


LOGGER = logging.getLogger("server_engine.gui.workers")


class MetricsWorker(QObject):
    metricsReady = Signal("QVariantList", "QVariantMap")

    @Slot()
    def refresh(self) -> None:
        load_one, load_five, load_fifteen = os.getloadavg()
        cpu_count = self._logical_cpu_count()
        load_percent = min(max((load_one / cpu_count) * 100, 0), 100)
        cpu_usage = self._cpu_usage_percent()
        total_memory_mb, used_memory_mb, memory_percent = self._memory_snapshot()

        hero_metrics = [
            {
                "id": "load",
                "title": "Load average",
                "value": f"{load_percent:.1f}%",
                "percent": load_percent,
                "detail": f"{load_one:.2f} / {load_five:.2f} / {load_fifteen:.2f}",
                "caption": "Normalized by CPU cores",
            },
            {
                "id": "cpu",
                "title": f"{cpu_count} Core(s)",
                "value": f"{cpu_usage:.1f}%",
                "percent": cpu_usage,
                "detail": "Current CPU usage",
                "caption": "Machine snapshot",
            },
            {
                "id": "ram",
                "title": "RAM usage",
                "value": f"{memory_percent:.1f}%",
                "percent": memory_percent,
                "detail": f"{used_memory_mb:.0f} / {total_memory_mb:.0f} MB",
                "caption": "Memory footprint",
            },
        ]

        usage = shutil.disk_usage("/")
        used_gb = usage.used / (1024 ** 3)
        total_gb = usage.total / (1024 ** 3)
        free_gb = usage.free / (1024 ** 3)
        disk_percent = (usage.used / usage.total) * 100 if usage.total else 0
        disk_metric = {
            "title": "Disk",
            "mount": "/",
            "value": f"{disk_percent:.0f}%",
            "percent": disk_percent,
            "detail": f"{used_gb:.2f} / {total_gb:.2f} GB",
            "free": f"{free_gb:.2f} GB free",
            "total": f"{total_gb:.2f} GB total",
        }

        self.metricsReady.emit(hero_metrics, disk_metric)

    def _logical_cpu_count(self) -> int:
        try:
            result = subprocess.run(
                ["sysctl", "-n", "hw.logicalcpu"],
                capture_output=True,
                text=True,
                check=True,
            )
            value = int(result.stdout.strip())
            if value > 0:
                return value
        except Exception:
            pass
        return max(os.cpu_count() or 1, 1)

    def _cpu_usage_percent(self) -> float:
        try:
            result = subprocess.run(
                ["top", "-l", "1", "-n", "0"],
                capture_output=True,
                text=True,
                check=True,
            )
            match = re.search(r"CPU usage:\s+([0-9.]+)% user,\s+([0-9.]+)% sys,\s+([0-9.]+)% idle", result.stdout)
            if match:
                user = float(match.group(1))
                system = float(match.group(2))
                return min(max(user + system, 0.0), 100.0)
        except Exception:
            pass
        return 0.0

    def _memory_snapshot(self) -> tuple[float, float, float]:
        try:
            total_memory = int(
                subprocess.run(
                    ["sysctl", "-n", "hw.memsize"],
                    capture_output=True,
                    text=True,
                    check=True,
                ).stdout.strip()
            )
            vm_stat_output = subprocess.run(
                ["vm_stat"],
                capture_output=True,
                text=True,
                check=True,
            ).stdout
            page_size_match = re.search(r"page size of (\d+) bytes", vm_stat_output)
            page_size = int(page_size_match.group(1)) if page_size_match else 4096
            values: dict[str, int] = {}
            for line in vm_stat_output.splitlines():
                match = re.match(r"([^:]+):\s+(\d+)\.", line.strip())
                if match:
                    values[match.group(1)] = int(match.group(2))

            free_pages = values.get("Pages free", 0) + values.get("Pages speculative", 0)
            used_bytes = max(total_memory - free_pages * page_size, 0)
            total_mb = total_memory / (1024 ** 2)
            used_mb = used_bytes / (1024 ** 2)
            percent = (used_bytes / total_memory) * 100 if total_memory else 0
            return total_mb, used_mb, percent
        except Exception:
            return 0.0, 0.0, 0.0


class AppSettingsSaveWorker(QObject):
    completed = Signal(bool, str)

    def __init__(self, container: AppContainer) -> None:
        super().__init__()
        self._container = container
        self._kind = ""
        self._payload: dict[str, object] = {}

    @Slot(str, "QVariantMap")
    def runSave(self, kind: str, payload: dict[str, object]) -> None:
        self._kind = str(kind or "").strip().lower()
        self._payload = dict(payload)
        self.run()

    def _copy_common_settings(self, current):
        from server_engine.core.models import AppSettings

        return AppSettings(
            app_name=current.app_name,
            default_php_version=current.default_php_version,
            default_mysql_version=current.default_mysql_version,
            default_mariadb_version=current.default_mariadb_version,
            default_redis_version=current.default_redis_version,
            default_memcached_version=current.default_memcached_version,
            default_mailpit_version=current.default_mailpit_version,
            default_apache_version=current.default_apache_version,
            default_nginx_version=current.default_nginx_version,
            php_runtime_log_to_file=current.php_runtime_log_to_file,
            php_runtime_log_to_screen=current.php_runtime_log_to_screen,
            php_runtime_log_dir=current.php_runtime_log_dir,
            default_server_type=current.default_server_type,
            active_web_server=current.active_web_server,
            active_apache_version=current.active_apache_version,
            active_nginx_version=current.active_nginx_version,
            apache_port=current.apache_port,
            apache_enabled_modules=current.apache_enabled_modules,
            apache_error_log_path=current.apache_error_log_path,
            preferred_database_engine=current.preferred_database_engine,
            active_database_version=current.active_database_version,
            database_port=current.database_port,
            database_root_password=current.database_root_password,
            database_runtime_passwords=current.database_runtime_passwords,
            database_optimization=current.database_optimization,
            active_redis_version=current.active_redis_version,
            cache_driver=current.cache_driver,
            active_memcached_version=current.active_memcached_version,
            active_mailpit_version=current.active_mailpit_version,
            active_mongodb_version=current.active_mongodb_version,
            active_postgresql_version=current.active_postgresql_version,
            redis_port=current.redis_port,
            redis_password=current.redis_password,
            redis_runtime_passwords=current.redis_runtime_passwords,
            mailpit_smtp_port=current.mailpit_smtp_port,
            mailpit_http_port=current.mailpit_http_port,
            appearance_theme=current.appearance_theme,
            appearance_accent_color=current.appearance_accent_color,
            appearance_language=current.appearance_language,
            home_global_services=current.home_global_services,
            bottom_terminal_panel_height=current.bottom_terminal_panel_height,
            nginx_worker_processes=current.nginx_worker_processes,
            nginx_worker_connections=current.nginx_worker_connections,
            nginx_keepalive_timeout=current.nginx_keepalive_timeout,
            nginx_client_max_body_size=current.nginx_client_max_body_size,
            nginx_sendfile=current.nginx_sendfile,
            nginx_gzip=current.nginx_gzip,
            nginx_server_tokens=current.nginx_server_tokens,
            nginx_error_log_path=current.nginx_error_log_path,
            active_node_version=current.active_node_version,
            active_phpmyadmin_version=current.active_phpmyadmin_version,
            phpmyadmin_php_version=current.phpmyadmin_php_version,
            phpmyadmin_hosts_registered=current.phpmyadmin_hosts_registered,
            auto_start_stack=current.auto_start_stack,
            auto_update_hosts=current.auto_update_hosts,
            environment_root=current.environment_root,
            enable_simulated_processes=current.enable_simulated_processes,
            default_project_folder=current.default_project_folder,
        )

    def _build_general_settings(self):
        current = self._container.settings_service.get_settings()
        cleaned_root = str(self._payload.get("environment_root", "")).strip()
        resolved_root = str(Path(cleaned_root).expanduser()) if cleaned_root else current.environment_root
        cleaned_folder = str(self._payload.get("default_project_folder", "")).strip() or "~/ServerEngine"
        settings = self._copy_common_settings(current)
        settings.auto_start_stack = bool(self._payload.get("auto_start_stack", current.auto_start_stack))
        settings.auto_update_hosts = bool(self._payload.get("auto_update_hosts", current.auto_update_hosts))
        settings.enable_simulated_processes = bool(
            self._payload.get("enable_simulated_processes", current.enable_simulated_processes)
        )
        settings.environment_root = resolved_root
        settings.default_project_folder = cleaned_folder
        return settings

    def _build_appearance_settings(self):
        current = self._container.settings_service.get_settings()
        settings = self._copy_common_settings(current)
        theme_mode = str(self._payload.get("theme_mode", "")).strip().lower()
        accent_color = str(self._payload.get("accent_color", "")).strip().lower()
        language = str(self._payload.get("language", "")).strip().lower()
        if theme_mode in {"system", "light", "dark"}:
            settings.appearance_theme = theme_mode
        if re.fullmatch(r"#[0-9a-f]{6}", accent_color):
            settings.appearance_accent_color = accent_color
        if language in {"en", "de", "vi", "zh-hans", "zh-hant"}:
            settings.appearance_language = language
        return settings

    @Slot()
    def run(self) -> None:
        try:
            if self._kind == "general":
                self._container.settings_service.save_settings(self._build_general_settings())
                self.completed.emit(True, "General settings saved.")
                return
            if self._kind == "appearance":
                self._container.settings_service.save_settings(self._build_appearance_settings())
                self.completed.emit(True, "Appearance settings saved.")
                return
            self.completed.emit(False, f"Unsupported app settings save kind: {self._kind}")
        except Exception as exc:
            self.completed.emit(False, str(exc))


class DatabaseBackupWorker(QObject):
    progressChanged = Signal(int, str)
    completed = Signal(bool, str, bool)

    def __init__(self, service, mode: str, value: str) -> None:
        super().__init__()
        self._service = service
        self._mode = mode
        self._value = value
        self._cancel_requested = False

    @Slot()
    def cancel(self) -> None:
        self._cancel_requested = True

    @Slot()
    def run(self) -> None:
        if self._mode == "restore":
            result = self._service.restore_backup(self._value, self._emit_progress, self._is_cancel_requested)
        elif self._mode == "import":
            parts = self._value.split("\n", 2)
            database_name = parts[0]
            import_path = parts[1] if len(parts) > 1 else ""
            clear_existing = len(parts) > 2 and parts[2].strip() == "1"
            result = self._service.import_dump_with_progress(
                database_name,
                import_path,
                self._emit_progress,
                clear_existing,
            )
        else:
            result = self._service.create_backup(self._value, self._emit_progress, self._is_cancel_requested)
        canceled = self._cancel_requested or "cancel" in str(result.message or "").lower()
        self.completed.emit(result.success, result.message, canceled)

    def _emit_progress(self, value: int, message: str) -> None:
        self.progressChanged.emit(value, message)

    def _is_cancel_requested(self) -> bool:
        return self._cancel_requested


class DatabaseBackupItemsWorker(QObject):
    completed = Signal(str, object, bool, str)

    def __init__(self, service, database_name: str) -> None:
        super().__init__()
        self._service = service
        self._database_name = str(database_name or "").strip()

    @Slot()
    def run(self) -> None:
        database_name = self._database_name
        start = time.perf_counter()
        LOGGER.debug("DatabaseBackupItemsWorker.run: start database=%s", database_name)
        try:
            result = self._service.list_backups(database_name)
            items: list[dict[str, object]] = []
            if result.success:
                items = list(result.payload.get("items", []))
            LOGGER.debug(
                "DatabaseBackupItemsWorker.run: done database=%s success=%s items=%d message=%s took=%.1fms",
                database_name,
                bool(result.success),
                len(items),
                str(result.message or ""),
                (time.perf_counter() - start) * 1000.0,
            )
            self.completed.emit(database_name, items, bool(result.success), str(result.message or ""))
        except Exception as exc:
            LOGGER.debug(
                "DatabaseBackupItemsWorker.run: exception database=%s error=%s took=%.1fms",
                database_name,
                exc,
                (time.perf_counter() - start) * 1000.0,
            )
            self.completed.emit(database_name, [], False, str(exc))


class DatabaseSizeWorker(QObject):
    completed = Signal(bool, "QVariantMap", str)

    def __init__(self, container: AppContainer) -> None:
        super().__init__()
        self._container = container

    @Slot()
    def run(self) -> None:
        try:
            result = self._container.database_service.list_database_sizes()
            payload = result.payload if result.success else {}
            sizes = payload.get("sizes", {}) if isinstance(payload, dict) else {}
            normalized = sizes if isinstance(sizes, dict) else {}
            self.completed.emit(bool(result.success), normalized, str(result.message or ""))
        except Exception as exc:
            self.completed.emit(False, {}, str(exc))


class PhpInfoWorker(QObject):
    completed = Signal(str, bool, str, str)

    def __init__(self, container: AppContainer, version: str) -> None:
        super().__init__()
        self._container = container
        self._version = version.strip()

    @Slot()
    def run(self) -> None:
        version = self._version
        try:
            runtime = self._container.php_runtime_service.require_runtime(version)
            result = subprocess.run(
                [runtime.php_path, "-d", "html_errors=0", "-r", "phpinfo();"],
                capture_output=True,
                text=True,
                check=False,
                timeout=10,
            )
            output = (result.stdout or "").strip()
            if result.returncode != 0:
                details = (result.stderr or result.stdout or "").strip()
                self.completed.emit(version, False, details or f"phpinfo() failed for PHP {version}", "")
                return
            if not output:
                self.completed.emit(version, False, "phpinfo() returned no output.", "")
                return
            self.completed.emit(version, True, f"Loaded phpinfo() from PHP {version}", output)
        except Exception as exc:
            self.completed.emit(version, False, str(exc), "")


class HomeServiceWorker(QObject):
    completed = Signal(str, bool, str, "QVariantMap")

    def __init__(self, container: AppContainer, service_id: str, running: bool) -> None:
        super().__init__()
        self._container = container
        self._service_id = service_id
        self._running = running

    @Slot()
    def run(self) -> None:
        try:
            LOGGER.debug(
                "HomeServiceWorker.run: service_id=%s running=%s",
                self._service_id,
                self._running,
            )
            if self._service_id == "web":
                settings = self._container.settings_service.get_settings()
                stack_service = self._container.stack_service
                web_service_id = "nginx" if settings.active_web_server == settings.active_web_server.NGINX else "apache"
                LOGGER.debug(
                    "HomeServiceWorker.run: web mapped_service_id=%s action=%s",
                    web_service_id,
                    "start" if self._running else "stop",
                )
                if self._running:
                    result = stack_service.start_service(web_service_id)
                else:
                    result = stack_service.stop_service(web_service_id)
                ok = result.state.value != "error"
                message = result.message or ""
                payload = self._payload_from_status(stack_service.status(), target_service_id=web_service_id)
                LOGGER.debug(
                    "HomeServiceWorker.run: complete service_id=%s ok=%s message=%s running=%s status=%s",
                    self._service_id,
                    ok,
                    message,
                    payload.get("running"),
                    payload.get("status"),
                )
                self.completed.emit(self._service_id, ok, message, payload)
                return

            if self._service_id == "database":
                service = self._container.database_service
                LOGGER.debug("HomeServiceWorker.run: database action=%s", "start" if self._running else "stop")
                result = service.start_runtime() if self._running else service.stop_runtime()
                payload = self._payload_from_status(service.status(), log_tail=service.read_log_tail())
                LOGGER.debug(
                    "HomeServiceWorker.run: complete service_id=%s success=%s message=%s running=%s status=%s",
                    self._service_id,
                    bool(result.success),
                    result.message,
                    payload.get("running"),
                    payload.get("status"),
                )
                self.completed.emit(self._service_id, bool(result.success), result.message, payload)
                return

            if self._service_id == "redis":
                service = self._container.redis_service
                LOGGER.debug("HomeServiceWorker.run: redis action=%s", "start" if self._running else "stop")
                result = service.start_runtime() if self._running else service.stop_runtime()
                payload = self._payload_from_status(service.status(), log_tail=service.read_log_tail())
                LOGGER.debug(
                    "HomeServiceWorker.run: complete service_id=%s success=%s message=%s running=%s status=%s",
                    self._service_id,
                    bool(result.success),
                    result.message,
                    payload.get("running"),
                    payload.get("status"),
                )
                self.completed.emit(self._service_id, bool(result.success), result.message, payload)
                return

            if self._service_id == "memcached":
                service = self._container.memcached_service
                LOGGER.debug("HomeServiceWorker.run: memcached action=%s", "start" if self._running else "stop")
                result = service.start_runtime() if self._running else service.stop_runtime()
                payload = self._payload_from_status(service.status(), log_tail=service.read_log_tail())
                LOGGER.debug(
                    "HomeServiceWorker.run: complete service_id=%s success=%s message=%s running=%s status=%s",
                    self._service_id,
                    bool(result.success),
                    result.message,
                    payload.get("running"),
                    payload.get("status"),
                )
                self.completed.emit(self._service_id, bool(result.success), result.message, payload)
                return

            if self._service_id == "mailpit":
                service = self._container.mailpit_service
                LOGGER.debug("HomeServiceWorker.run: mailpit action=%s", "start" if self._running else "stop")
                result = service.start_runtime() if self._running else service.stop_runtime()
                payload = self._payload_from_status(service.status(), log_tail=service.read_log_tail())
                LOGGER.debug(
                    "HomeServiceWorker.run: complete service_id=%s success=%s message=%s running=%s status=%s",
                    self._service_id,
                    bool(result.success),
                    result.message,
                    payload.get("running"),
                    payload.get("status"),
                )
                self.completed.emit(self._service_id, bool(result.success), result.message, payload)
                return

            if self._service_id == "mongodb":
                service = self._container.mongodb_service
                LOGGER.debug("HomeServiceWorker.run: mongodb action=%s", "start" if self._running else "stop")
                result = service.start_runtime() if self._running else service.stop_runtime()
                payload = self._payload_from_status(service.status(), log_tail=service.read_log_tail())
                LOGGER.debug(
                    "HomeServiceWorker.run: complete service_id=%s success=%s message=%s running=%s status=%s",
                    self._service_id,
                    bool(result.success),
                    result.message,
                    payload.get("running"),
                    payload.get("status"),
                )
                self.completed.emit(self._service_id, bool(result.success), result.message, payload)
                return

            if self._service_id == "postgresql":
                service = self._container.postgresql_service
                LOGGER.debug("HomeServiceWorker.run: postgresql action=%s", "start" if self._running else "stop")
                result = service.start_runtime() if self._running else service.stop_runtime()
                payload = self._payload_from_status(service.status(), log_tail=service.read_log_tail())
                LOGGER.debug(
                    "HomeServiceWorker.run: complete service_id=%s success=%s message=%s running=%s status=%s",
                    self._service_id,
                    bool(result.success),
                    result.message,
                    payload.get("running"),
                    payload.get("status"),
                )
                self.completed.emit(self._service_id, bool(result.success), result.message, payload)
                return

            LOGGER.debug("HomeServiceWorker.run: unknown service_id=%s", self._service_id)
            self.completed.emit(self._service_id, False, "Unknown service.", {})
        except Exception as exc:
            LOGGER.exception("HomeServiceWorker.run: failed service_id=%s", self._service_id)
            self.completed.emit(self._service_id, False, str(exc), {})

    def _payload_from_status(self, status, target_service_id: str | None = None, log_tail: str = "") -> dict[str, object]:
        target = target_service_id or self._service_id
        services = getattr(status, "services", None)
        if services is not None:
            item = next((service for service in services if service.service_id == target), None)
        else:
            item = status
        state = getattr(item, "state", None)
        state_value = getattr(state, "value", "stopped")
        return {
            "running": state_value == "running",
            "status": str(state_value).title(),
            "message": str(getattr(item, "message", "") or ""),
            "log_tail": log_tail,
        }


class RuntimeInstallWorker(QObject):
    progressChanged = Signal(int, str)
    completed = Signal(bool, str)

    def __init__(self, bridge, item: dict[str, object], overwrite: bool) -> None:
        super().__init__()
        self._bridge = bridge
        self._item = item
        self._overwrite = overwrite

    @Slot()
    def run(self) -> None:
        try:
            self._bridge._install_runtime_package(self._item, self._overwrite, self._emit_progress)
            label = str(self._item.get("label") or self._item.get("id") or "runtime")
            self.completed.emit(True, f"Installed {label}.")
        except Exception as exc:
            self.completed.emit(False, str(exc))

    def _emit_progress(self, value: int, message: str) -> None:
        self.progressChanged.emit(value, message)


class RuntimeManifestWorker(QObject):
    completed = Signal(bool, str, str, "QVariantList")

    def __init__(self, bridge, service_id: str) -> None:
        super().__init__()
        self._bridge = bridge
        self._service_id = service_id

    @Slot()
    def run(self) -> None:
        try:
            result = self._bridge._load_runtime_server_items(self._service_id)
            self.completed.emit(True, self._service_id, "", result)
        except Exception as exc:
            self.completed.emit(False, self._service_id, str(exc), [])


class RequiredRuntimeBootstrapWorker(QObject):
    progressChanged = Signal(int, str)
    completed = Signal(bool, str)

    def __init__(self, bridge) -> None:
        super().__init__()
        self._bridge = bridge

    @Slot()
    def run(self) -> None:
        try:
            self._bridge._run_required_runtime_bootstrap(self._emit_progress)
            self.completed.emit(True, "Required runtimes are ready.")
        except Exception as exc:
            self.completed.emit(False, str(exc))

    def _emit_progress(self, value: int, message: str) -> None:
        self.progressChanged.emit(value, message)


class GlobalStackWorker(QObject):
    completed = Signal(str, "QVariantList")

    def __init__(self, container: AppContainer, action: str, service_ids: list[str]) -> None:
        super().__init__()
        self._container = container
        self._action = action
        self._service_ids = service_ids

    @Slot()
    def run(self) -> None:
        LOGGER.debug("GlobalStackWorker.run: action=%s service_ids=%s", self._action, self._service_ids)
        results: list[dict[str, object]] = []
        for service_id in self._service_ids:
            try:
                LOGGER.debug("GlobalStackWorker.run: begin service_id=%s action=%s", service_id, self._action)
                if service_id == "web":
                    settings = self._container.settings_service.get_settings()
                    web_service_id = "nginx" if settings.active_web_server == settings.active_web_server.NGINX else "apache"
                    stack_status = self._container.stack_service.status()
                    web_status = next((s for s in stack_status.services if s.service_id == web_service_id), None)
                    is_running = bool(web_status and web_status.state.value == "running")
                    LOGGER.debug(
                        "GlobalStackWorker.run: web mapped_service_id=%s running=%s",
                        web_service_id,
                        is_running,
                    )
                    if self._action == "start" and is_running:
                        results.append({"service_id": service_id, "success": True, "message": "Already running.", "running": True, "log_tail": ""})
                        continue
                    if self._action == "stop" and not is_running:
                        results.append({"service_id": service_id, "success": True, "message": "Already stopped.", "running": False, "log_tail": ""})
                        continue
                    if self._action == "start":
                        result = self._container.stack_service.start_service(web_service_id)
                    elif self._action == "stop":
                        result = self._container.stack_service.stop_service(web_service_id)
                    else:
                        self._container.stack_service.stop_service(web_service_id)
                        result = self._container.stack_service.start_service(web_service_id)
                    ok = result.state.value != "error"
                    final_status = self._container.stack_service.status()
                    web_state = next((s for s in final_status.services if s.service_id == web_service_id), None)
                    final_running = bool(web_state and web_state.state.value == "running")
                    LOGGER.debug(
                        "GlobalStackWorker.run: web complete ok=%s running=%s message=%s",
                        ok,
                        final_running,
                        result.message or "",
                    )
                    results.append({"service_id": service_id, "success": ok, "message": result.message or "", "running": final_running, "log_tail": ""})
                    continue
                if service_id == "database":
                    db_status = self._container.database_service.status()
                    is_running = db_status.state.value == "running"
                    LOGGER.debug("GlobalStackWorker.run: database running=%s", is_running)
                    if self._action == "start" and is_running:
                        results.append({"service_id": service_id, "success": True, "message": "Already running.", "running": True, "log_tail": self._container.database_service.read_log_tail()})
                        continue
                    if self._action == "stop" and not is_running:
                        results.append({"service_id": service_id, "success": True, "message": "Already stopped.", "running": False, "log_tail": self._container.database_service.read_log_tail()})
                        continue
                    if self._action == "start":
                        result = self._container.database_service.start_runtime()
                    elif self._action == "stop":
                        result = self._container.database_service.stop_runtime()
                    else:
                        self._container.database_service.stop_runtime()
                        result = self._container.database_service.start_runtime()
                    final_running = self._container.database_service.status().state.value == "running"
                    LOGGER.debug(
                        "GlobalStackWorker.run: database complete ok=%s running=%s message=%s",
                        bool(result.success),
                        final_running,
                        result.message or "",
                    )
                    results.append({
                        "service_id": service_id,
                        "success": bool(result.success),
                        "message": result.message,
                        "running": final_running,
                        "log_tail": self._container.database_service.read_log_tail(),
                    })
                    continue
                if service_id == "redis":
                    cache_service = self._container.redis_service
                    is_running = cache_service.status().state.value == "running"
                    LOGGER.debug("GlobalStackWorker.run: redis running=%s", is_running)
                    if self._action == "start" and is_running:
                        results.append({"service_id": service_id, "success": True, "message": "Already running.", "running": True, "log_tail": cache_service.read_log_tail()})
                        continue
                    if self._action == "stop" and not is_running:
                        results.append({"service_id": service_id, "success": True, "message": "Already stopped.", "running": False, "log_tail": cache_service.read_log_tail()})
                        continue
                    if self._action == "start":
                        result = cache_service.start_runtime()
                    elif self._action == "stop":
                        result = cache_service.stop_runtime()
                    else:
                        cache_service.stop_runtime()
                        result = cache_service.start_runtime()
                    final_running = cache_service.status().state.value == "running"
                    LOGGER.debug(
                        "GlobalStackWorker.run: redis complete ok=%s running=%s message=%s",
                        bool(result.success),
                        final_running,
                        result.message or "",
                    )
                    results.append({
                        "service_id": service_id,
                        "success": bool(result.success),
                        "message": result.message,
                        "running": final_running,
                        "log_tail": cache_service.read_log_tail(),
                    })
                    continue
                if service_id == "memcached":
                    cache_service = self._container.memcached_service
                    is_running = cache_service.status().state.value == "running"
                    LOGGER.debug("GlobalStackWorker.run: memcached running=%s", is_running)
                    if self._action == "start" and is_running:
                        results.append({"service_id": service_id, "success": True, "message": "Already running.", "running": True, "log_tail": cache_service.read_log_tail()})
                        continue
                    if self._action == "stop" and not is_running:
                        results.append({"service_id": service_id, "success": True, "message": "Already stopped.", "running": False, "log_tail": cache_service.read_log_tail()})
                        continue
                    if self._action == "start":
                        result = cache_service.start_runtime()
                    elif self._action == "stop":
                        result = cache_service.stop_runtime()
                    else:
                        cache_service.stop_runtime()
                        result = cache_service.start_runtime()
                    final_running = cache_service.status().state.value == "running"
                    LOGGER.debug(
                        "GlobalStackWorker.run: memcached complete ok=%s running=%s message=%s",
                        bool(result.success),
                        final_running,
                        result.message or "",
                    )
                    results.append({
                        "service_id": service_id,
                        "success": bool(result.success),
                        "message": result.message,
                        "running": final_running,
                        "log_tail": cache_service.read_log_tail(),
                    })
                    continue
                if service_id == "mailpit":
                    is_running = self._container.mailpit_service.status().state.value == "running"
                    LOGGER.debug("GlobalStackWorker.run: mailpit running=%s", is_running)
                    if self._action == "start" and is_running:
                        results.append({"service_id": service_id, "success": True, "message": "Already running."})
                        continue
                    if self._action == "stop" and not is_running:
                        results.append({"service_id": service_id, "success": True, "message": "Already stopped."})
                        continue
                    if self._action == "start":
                        result = self._container.mailpit_service.start_runtime()
                    elif self._action == "stop":
                        result = self._container.mailpit_service.stop_runtime()
                    else:
                        self._container.mailpit_service.stop_runtime()
                        result = self._container.mailpit_service.start_runtime()
                    LOGGER.debug(
                        "GlobalStackWorker.run: mailpit complete success=%s message=%s",
                        bool(result.success),
                        result.message or "",
                    )
                    results.append({
                        "service_id": service_id,
                        "success": bool(result.success),
                        "message": result.message,
                        "log_tail": self._container.mailpit_service.read_log_tail(),
                    })
                    continue
                if service_id == "mongodb":
                    cache_service = self._container.mongodb_service
                    is_running = cache_service.status().state.value == "running"
                    LOGGER.debug("GlobalStackWorker.run: mongodb running=%s", is_running)
                    if self._action == "start" and is_running:
                        results.append({"service_id": service_id, "success": True, "message": "Already running.", "running": True, "log_tail": cache_service.read_log_tail()})
                        continue
                    if self._action == "stop" and not is_running:
                        results.append({"service_id": service_id, "success": True, "message": "Already stopped.", "running": False, "log_tail": cache_service.read_log_tail()})
                        continue
                    if self._action == "start":
                        result = cache_service.start_runtime()
                    elif self._action == "stop":
                        result = cache_service.stop_runtime()
                    else:
                        cache_service.stop_runtime()
                        result = cache_service.start_runtime()
                    final_running = cache_service.status().state.value == "running"
                    LOGGER.debug(
                        "GlobalStackWorker.run: mongodb complete ok=%s running=%s message=%s",
                        bool(result.success),
                        final_running,
                        result.message or "",
                    )
                    results.append({
                        "service_id": service_id,
                        "success": bool(result.success),
                        "message": result.message,
                        "running": final_running,
                        "log_tail": cache_service.read_log_tail(),
                    })
                    continue
                if service_id == "postgresql":
                    cache_service = self._container.postgresql_service
                    is_running = cache_service.status().state.value == "running"
                    LOGGER.debug("GlobalStackWorker.run: postgresql running=%s", is_running)
                    if self._action == "start" and is_running:
                        results.append({"service_id": service_id, "success": True, "message": "Already running.", "running": True, "log_tail": cache_service.read_log_tail()})
                        continue
                    if self._action == "stop" and not is_running:
                        results.append({"service_id": service_id, "success": True, "message": "Already stopped.", "running": False, "log_tail": cache_service.read_log_tail()})
                        continue
                    if self._action == "start":
                        result = cache_service.start_runtime()
                    elif self._action == "stop":
                        result = cache_service.stop_runtime()
                    else:
                        cache_service.stop_runtime()
                        result = cache_service.start_runtime()
                    final_running = cache_service.status().state.value == "running"
                    LOGGER.debug(
                        "GlobalStackWorker.run: postgresql complete ok=%s running=%s message=%s",
                        bool(result.success),
                        final_running,
                        result.message or "",
                    )
                    results.append({
                        "service_id": service_id,
                        "success": bool(result.success),
                        "message": result.message,
                        "running": final_running,
                        "log_tail": cache_service.read_log_tail(),
                    })
                    continue
                LOGGER.debug("GlobalStackWorker.run: unsupported service_id=%s", service_id)
                results.append({"service_id": service_id, "success": False, "message": "Unknown service."})
            except Exception as exc:
                LOGGER.exception("GlobalStackWorker.run: failed service_id=%s action=%s", service_id, self._action)
                results.append({"service_id": service_id, "success": False, "message": str(exc)})
        self.completed.emit(self._action, results)


class MailpitActionWorker(QObject):
    completed = Signal(str, bool, str)

    def __init__(self, container: AppContainer, action: str) -> None:
        super().__init__()
        self._container = container
        self._action = action

    @Slot()
    def run(self) -> None:
        try:
            if self._action == "start":
                result = self._container.mailpit_service.start_runtime()
            elif self._action == "stop":
                result = self._container.mailpit_service.stop_runtime()
            else:
                result = self._container.mailpit_service.restart_runtime()
            self.completed.emit(self._action, bool(result.success), result.message)
        except Exception as exc:
            self.completed.emit(self._action, False, str(exc))


class RedisRestartWorker(QObject):
    completed = Signal(bool, str)

    def __init__(self, container: AppContainer) -> None:
        super().__init__()
        self._container = container

    @Slot()
    def run(self) -> None:
        try:
            result = self._container.redis_service.restart_runtime()
            self.completed.emit(bool(result.success), result.message)
        except Exception as exc:
            self.completed.emit(False, str(exc))


class MemcachedRestartWorker(QObject):
    completed = Signal(bool, str)

    def __init__(self, container: AppContainer) -> None:
        super().__init__()
        self._container = container

    @Slot()
    def run(self) -> None:
        try:
            result = self._container.memcached_service.restart_runtime()
            self.completed.emit(bool(result.success), result.message)
        except Exception as exc:
            self.completed.emit(False, str(exc))


class MongodbItemsWorker(QObject):
    completed = Signal("QVariantList")

    def __init__(self, container: AppContainer) -> None:
        super().__init__()
        self._container = container

    @Slot()
    def run(self) -> None:
        items: list[dict[str, str]] = []
        try:
            result = self._container.mongodb_service.list_databases()
            if result.success:
                runtime = result.payload.get("runtime") or {}
                port = str(result.payload.get("port", "27017"))
                for entry in result.payload.get("databases", []):
                    name = str(entry.get("name", "")).strip()
                    if not name:
                        continue
                    items.append(
                        {
                            "name": name,
                            "engine": "MONGODB",
                            "runtime": str(runtime.get("version", "")),
                            "host": "127.0.0.1",
                            "port": port,
                            "status": "Ready",
                        }
                    )
        except Exception:
            items = []
        self.completed.emit(items)


class MongodbActionWorker(QObject):
    completed = Signal(str, bool, str, str)

    def __init__(self, container: AppContainer, action: str) -> None:
        super().__init__()
        self._container = container
        self._action = action

    @Slot()
    def run(self) -> None:
        try:
            if self._action == "start":
                result = self._container.mongodb_service.start_runtime()
            elif self._action == "stop":
                result = self._container.mongodb_service.stop_runtime()
            else:
                result = self._container.mongodb_service.restart_runtime()
            log_tail = self._container.mongodb_service.read_log_tail()
            self.completed.emit(self._action, bool(result.success), result.message, log_tail)
        except Exception as exc:
            self.completed.emit(self._action, False, str(exc), "")


class PhpMyAdminWorker(QObject):
    completed = Signal(bool, str)

    def __init__(self, container: AppContainer) -> None:
        super().__init__()
        self._container = container

    @Slot()
    def run(self) -> None:
        try:
            settings = self._container.settings_service.get_settings()
            runtime_root = self._container.config_service.phpmyadmin_root()
            if not runtime_root.exists() or not (runtime_root / "index.php").exists():
                self.completed.emit(False, f"phpMyAdmin runtime is incomplete. Missing: {runtime_root / 'index.php'}")
                return
            if settings.auto_update_hosts:
                self._container.hosts_gateway.ensure_mapping(self._container.config_service.phpmyadmin_domain())
                self._container.settings_service.save_settings(
                    replace(settings, phpmyadmin_hosts_registered=True)
                )
            self._container.config_service.write_phpmyadmin_config()
            self._container.config_service.write_phpmyadmin_php_cgi_wrapper()
            url = self._container.config_service.phpmyadmin_url()
            subprocess.Popen(["open", url])
            self.completed.emit(True, f"Opened phpMyAdmin at {url}")
        except Exception as exc:
            self.completed.emit(False, str(exc))


class DatabaseRestartWorker(QObject):
    completed = Signal(bool, str)

    def __init__(self, container: AppContainer) -> None:
        super().__init__()
        self._container = container

    @Slot()
    def run(self) -> None:
        try:
            result = self._container.database_service.restart_runtime()
            self.completed.emit(bool(result.success), result.message)
        except Exception as exc:
            self.completed.emit(False, str(exc))


class WebRouteReloadWorker(QObject):
    completed = Signal(bool, str)

    def __init__(self, container: AppContainer) -> None:
        super().__init__()
        self._container = container

    @Slot()
    def run(self) -> None:
        try:
            settings = self._container.settings_service.get_settings()
            web_id = "nginx" if settings.active_web_server == settings.active_web_server.NGINX else "apache"
            status = self._container.stack_service.status()
            web_status = next((item for item in status.services if item.service_id == web_id), None)
            if web_status is None or web_status.state.value != "running":
                self.completed.emit(True, "")
                return
            self._container.stack_service.stop_service(web_id)
            result = self._container.stack_service.start_service(web_id)
            ok = result.state.value != "error"
            self.completed.emit(ok, result.message or "")
        except Exception as exc:
            self.completed.emit(False, str(exc))


class WebRestartWorker(QObject):
    completed = Signal(bool, str)

    def __init__(self, container: AppContainer) -> None:
        super().__init__()
        self._container = container

    @Slot()
    def run(self) -> None:
        try:
            settings = self._container.settings_service.get_settings()
            web_id = "nginx" if settings.active_web_server == settings.active_web_server.NGINX else "apache"
            self._container.stack_service.stop_service(web_id)
            result = self._container.stack_service.start_service(web_id)
            ok = result.state.value != "error"
            self.completed.emit(ok, result.message or "")
        except Exception as exc:
            self.completed.emit(False, str(exc))


class PhpRuntimeServiceActionWorker(QObject):
    completed = Signal(bool, str)

    def __init__(self, container: AppContainer, action: str, version: str) -> None:
        super().__init__()
        self._container = container
        self._action = action.strip().lower()
        self._version = version.strip()

    @Slot()
    def run(self) -> None:
        try:
            settings = self._container.settings_service.get_settings()
            if settings.active_web_server != settings.active_web_server.NGINX:
                self.completed.emit(False, "PHP runtime service controls are available only when Nginx is active.")
                return

            service_id = "php-cgi-" + self._version.replace(".", "_")
            definitions = self._container.stack_service.definitions()
            definition = next((item for item in definitions if item.id == service_id), None)
            if definition is None:
                self.completed.emit(False, f"PHP runtime service not found for version {self._version}.")
                return

            if self._action == "start":
                result = self._container.stack_service.start_service(service_id)
                self.completed.emit(result.state.value != "error", str(result.message or ""))
                return

            if self._action == "stop":
                result = self._container.stack_service.stop_service(service_id)
                self.completed.emit(result.state.value != "error", str(result.message or ""))
                return

            if self._action in {"restart", "reload"}:
                self._container.stack_service.stop_service(service_id)
                result = self._container.stack_service.start_service(service_id)
                self.completed.emit(result.state.value != "error", str(result.message or ""))
                return

            self.completed.emit(False, f"Unsupported action: {self._action}")
        except Exception as exc:
            self.completed.emit(False, str(exc))


class NodeProjectRuntimeActionWorker(QObject):
    completed = Signal(bool, str)

    def __init__(self, container: AppContainer, action: str, project_id: str) -> None:
        super().__init__()
        self._container = container
        self._action = action.strip().lower()
        self._project_id = project_id.strip()

    @Slot()
    def run(self) -> None:
        try:
            service = self._container.node_project_runtime_service
            if self._action == "start":
                result = service.start(self._project_id)
            elif self._action == "stop":
                result = service.stop(self._project_id)
            elif self._action == "restart":
                result = service.restart(self._project_id)
            else:
                self.completed.emit(False, f"Unsupported action: {self._action}")
                return
            self.completed.emit(bool(result.success), str(result.message or ""))
        except Exception as exc:
            self.completed.emit(False, str(exc))


class NodeProjectSaveWorker(QObject):
    progress = Signal(int, str)
    completed = Signal(bool, str)

    def __init__(self, container: AppContainer, payload: dict) -> None:
        super().__init__()
        self._container = container
        self._payload = dict(payload)
        self._cancel_requested = False

    def request_cancel(self) -> None:
        self._cancel_requested = True

    def _step(self, percent: int, message: str) -> None:
        if self._cancel_requested:
            raise RuntimeError("Node project creation cancelled.")
        self.progress.emit(percent, message)

    def _template_command(self, template_id: str, project_path: Path) -> list[str] | None:
        name = project_path.name
        commands = {
            "react": ["npm", "create", "vite@latest", name, "--", "--template", "react"],
            "vue": ["npm", "create", "vite@latest", name, "--", "--template", "vue"],
            "svelte": ["npm", "create", "vite@latest", name, "--", "--template", "svelte"],
            "next": ["npx", "create-next-app@latest", name, "--yes", "--use-npm"],
            "remix": ["npx", "create-remix@latest", name, "--no-install"],
            "nuxt": ["npx", "nuxi@latest", "init", name, "--no-install"],
            "sveltekit": ["npx", "sv", "create", name, "--template", "minimal", "--types", "js", "--no-add-ons", "--no-install"],
            "express": ["npm", "init", "-y"],
            "fastify": ["npm", "init", "-y"],
            "nest": ["npx", "@nestjs/cli", "new", name, "--package-manager", "npm", "--skip-git", "--strict"],
        }
        command = commands.get(template_id)
        if command is None:
            return None
        return command

    def _run_node_command(self, command: list[str], cwd: Path, bin_dir: Path, log_path: Path) -> None:
        env = os.environ.copy()
        env["PATH"] = f"{bin_dir}:{env.get('PATH', '')}"
        env.setdefault("CI", "1")
        with log_path.open("a", encoding="utf-8") as handle:
            handle.write("$ " + " ".join(command) + "\n")
            result = subprocess.run(command, cwd=str(cwd), env=env, stdout=handle, stderr=subprocess.STDOUT, text=True, check=False)
        if result.returncode != 0:
            raise RuntimeError(f"Node setup command failed ({result.returncode}). See {log_path}.")

    @Slot()
    def run(self) -> None:
        try:
            payload = self._payload
            project_id = str(payload.get("id", "")).strip()
            local_domain = str(payload.get("local_domain", "")).strip().lower()
            project_path = str(payload.get("project_path", "")).strip()
            node_version = str(payload.get("node_version", "")).strip()
            run_script_name = str(payload.get("run_script_name", "")).strip()
            run_script_command = str(payload.get("run_script_command", "")).strip()
            notes = str(payload.get("notes", "")).strip()
            ssl_enabled = bool(payload.get("ssl_enabled", False))
            ssl_enforce_tls = bool(payload.get("ssl_enforce_tls", False))
            ssl_allow_http = bool(payload.get("ssl_allow_http", True))
            port = int(str(payload.get("port", "0")).strip() or "0")
            if not local_domain:
                raise ValueError("Domain is required.")
            if not project_path:
                raise ValueError("Project path is required.")
            if not node_version:
                raise ValueError("Node version is required.")
            if not run_script_name or not run_script_command:
                raise ValueError("Run option is required.")
            if port < 1 or port > 65535:
                raise ValueError("Port must be between 1 and 65535.")

            template_id = str(payload.get("template_id", "existing")).strip().lower() or "existing"
            project_root = Path(project_path).expanduser().resolve()
            self._step(5, "Validating project data...")
            if not project_id and template_id != "existing":
                if project_root.exists() and any(project_root.iterdir()):
                    raise ValueError("New Node projects can only be created in an empty folder.")
                project_root.mkdir(parents=True, exist_ok=True)
                binaries = self._container.binary_locator.node_binary_paths(node_version)
                if binaries is None:
                    raise ValueError(f"Node runtime {node_version} was not found.")
                bin_dir = Path(binaries["bin_dir"])
                log_path = self._container.binary_locator.runtime_paths.logs_dir / "node-project-setup.log"
                log_path.parent.mkdir(parents=True, exist_ok=True)
                command = self._template_command(template_id, project_root)
                if command is None:
                    raise ValueError(f"Unsupported Node template: {template_id}")
                self._step(20, "Creating project files...")
                if template_id in {"express", "fastify"}:
                    self._run_node_command(command, project_root, bin_dir, log_path)
                    package = json.loads((project_root / "package.json").read_text(encoding="utf-8"))
                    dependency = "express" if template_id == "express" else "fastify"
                    package.setdefault("dependencies", {})[dependency] = "latest"
                    (project_root / "package.json").write_text(json.dumps(package, indent=2) + "\n", encoding="utf-8")
                else:
                    self._run_node_command(command, project_root.parent, bin_dir, log_path)
                self._step(55, "Installing node_modules...")
                self._run_node_command(["npm", "install"], project_root, bin_dir, log_path)

            name = str(payload.get("name", "")).strip() or local_domain.split(".")[0]
            node_project_service = self._container.node_project_service
            self._step(70, "Saving project mapping...")
            if project_id:
                node_project_service.update_project(
                    project_id,
                    name=name,
                    local_domain=local_domain,
                    project_path=project_path,
                    document_root=project_path,
                    node_version=node_version,
                    run_script_name=run_script_name,
                    run_script_command=run_script_command,
                    port=port,
                    notes=notes,
                    ssl_enabled=ssl_enabled,
                    ssl_enforce_tls=ssl_enforce_tls,
                    ssl_allow_http=ssl_allow_http,
                )
                message = f"Updated Node project: {local_domain}"
            else:
                node_project_service.create_project(
                    name=name,
                    local_domain=local_domain,
                    project_path=project_path,
                    document_root=project_path,
                    node_version=node_version,
                    run_script_name=run_script_name,
                    run_script_command=run_script_command,
                    port=port,
                    notes=notes,
                    ssl_enabled=ssl_enabled,
                    ssl_enforce_tls=ssl_enforce_tls,
                    ssl_allow_http=ssl_allow_http,
                )
                message = f"Created Node project: {local_domain}"

            settings = self._container.settings_service.get_settings()
            web_id = "nginx" if settings.active_web_server == settings.active_web_server.NGINX else "apache"
            status = self._container.stack_service.status()
            web_status = next((item for item in status.services if item.service_id == web_id), None)
            if web_status is not None and web_status.state.value == "running":
                self._step(85, "Reloading web server routes...")
                self._container.stack_service.stop_service(web_id)
                self._container.stack_service.start_service(web_id)

            self._step(100, "Project ready to run.")
            self.completed.emit(True, message)
        except Exception as exc:
            self.completed.emit(False, str(exc))


class NodeProjectModulesWorker(QObject):
    completed = Signal(bool, str, "QVariantList", bool)

    def __init__(self, container: AppContainer, project_id: str) -> None:
        super().__init__()
        self._container = container
        self._project_id = project_id.strip()

    @Slot()
    def run(self) -> None:
        try:
            project = self._container.node_project_service.repository.get(self._project_id)
            if project is None:
                self.completed.emit(False, "Node project not found.", [], False)
                return
            project_root = Path(project.project_path).expanduser()
            package_json = project_root / "package.json"
            direct_dependencies = self._load_direct_dependencies(package_json)
            node_modules_root = project_root / "node_modules"
            if not node_modules_root.exists():
                self.completed.emit(True, "node_modules folder not found.", [], False)
                return
            items: list[dict[str, str]] = []
            for package_dir in self._iter_package_dirs(node_modules_root):
                package_json = package_dir / "package.json"
                if not package_json.exists():
                    continue
                try:
                    data = json.loads(package_json.read_text(encoding="utf-8"))
                except Exception:
                    continue
                name = str(data.get("name") or package_dir.name or "").strip()
                if direct_dependencies and name not in direct_dependencies:
                    continue
                version = str(data.get("version") or "").strip()
                description = str(data.get("description") or "").strip()
                items.append(
                    {
                        "name": name,
                        "version": version,
                        "description": description,
                        "path": str(package_dir),
                    }
                )
            items.sort(key=lambda item: (str(item.get("name", "")).lower(), str(item.get("version", "")).lower()))
            self.completed.emit(True, f"Loaded {len(items)} package(s).", items, True)
        except Exception as exc:
            self.completed.emit(False, str(exc), [], False)

    def _load_direct_dependencies(self, package_json: Path) -> set[str]:
        if not package_json.exists():
            return set()
        try:
            data = json.loads(package_json.read_text(encoding="utf-8"))
        except Exception:
            return set()
        deps = data.get("dependencies") or {}
        if isinstance(deps, dict):
            return {str(name).strip() for name in deps.keys() if str(name).strip()}
        return set()

    def _iter_package_dirs(self, node_modules_root: Path):
        for child in sorted(node_modules_root.iterdir(), key=lambda path: path.name.lower()):
            if not child.is_dir() or child.name.startswith("."):
                continue
            if child.name.startswith("@"):
                for scoped in sorted(child.iterdir(), key=lambda path: path.name.lower()):
                    if scoped.is_dir() and not scoped.name.startswith("."):
                        yield scoped
                continue
            yield child


class NodeProjectInstallDependenciesWorker(QObject):
    completed = Signal(bool, str)

    def __init__(self, container: AppContainer, project_id: str) -> None:
        super().__init__()
        self._container = container
        self._project_id = project_id.strip()

    @Slot()
    def run(self) -> None:
        try:
            result = self._container.node_project_runtime_service.install_dependencies(self._project_id)
            self.completed.emit(bool(result.success), str(result.message or ""))
        except Exception as exc:
            self.completed.emit(False, str(exc))


class SiteCreationWorker(QObject):
    progressChanged = Signal(int, str)
    completed = Signal(bool, str)

    def __init__(self, bridge, payload: dict[str, object]) -> None:
        super().__init__()
        self._bridge = bridge
        self._payload = payload

    @Slot()
    def run(self) -> None:
        try:
            message = self._bridge._create_site_internal(self._payload, self._emit_progress)
            self.completed.emit(True, message)
        except Exception as exc:
            LOGGER.exception("site_creation worker failed")
            self.completed.emit(False, str(exc))

    def _emit_progress(self, value: int, message: str) -> None:
        if getattr(self._bridge, "_site_creation_cancel_requested", False):
            raise RuntimeError("Site creation cancelled.")
        self.progressChanged.emit(value, message)
