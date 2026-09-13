from __future__ import annotations

import logging
from pathlib import Path
import socket
import time

from server_engine.core.models import MemcachedRuntime, OperationResult, RuntimePaths, ServiceDefinition, ServiceKind, ServiceState, ServiceStatus
from server_engine.infrastructure.process_manager import ProcessManager
from server_engine.services.memcached_runtime_service import MemcachedRuntimeService
from server_engine.services.settings_service import SettingsService


LOGGER = logging.getLogger("server_engine.memcached")


class MemcachedService:
    DEFAULT_PORT = 11211
    DEFAULT_HOST = "127.0.0.1"

    def __init__(
        self,
        runtime_paths: RuntimePaths,
        settings_service: SettingsService,
        runtime_service: MemcachedRuntimeService,
        process_manager: ProcessManager,
    ) -> None:
        self.runtime_paths = runtime_paths
        self.settings_service = settings_service
        self.runtime_service = runtime_service
        self.process_manager = process_manager

    def active_runtime(self) -> MemcachedRuntime | None:
        settings = self.settings_service.get_settings()
        return self.runtime_service.resolve(runtime_id=settings.active_memcached_version)

    def _runtime_key(self, runtime: MemcachedRuntime | None = None) -> str:
        active = runtime or self.active_runtime()
        return active.id if active else "memcached"

    def _runtime_log_key(self, runtime: MemcachedRuntime | None = None) -> str:
        active = runtime or self.active_runtime()
        if active is None:
            return "memcached"
        return active.version.strip() or active.id

    def port(self) -> int:
        return int(self.read_config_settings().get("port", self.DEFAULT_PORT))

    def host(self) -> str:
        return str(self.read_config_settings().get("host", self.DEFAULT_HOST))

    def config_path(self, runtime: MemcachedRuntime | None = None) -> Path:
        path = self.runtime_paths.config_dir / "memcached" / f"{self._runtime_key(runtime)}.conf"
        path.parent.mkdir(parents=True, exist_ok=True)
        return path

    def log_path(self, runtime: MemcachedRuntime | None = None) -> Path:
        path = self.runtime_paths.logs_dir / "memcached" / self._runtime_log_key(runtime) / "memcached.log"
        path.parent.mkdir(parents=True, exist_ok=True)
        return path

    def pid_path(self, runtime: MemcachedRuntime | None = None) -> Path:
        path = self.runtime_paths.runtime_dir / "memcached" / f"{self._runtime_key(runtime)}.pid"
        path.parent.mkdir(parents=True, exist_ok=True)
        return path

    def data_dir(self, runtime: MemcachedRuntime | None = None, create: bool = True) -> Path:
        path = self.runtime_paths.data_dir / "memcached" / self._runtime_key(runtime)
        if create:
            path.mkdir(parents=True, exist_ok=True)
        return path

    def generate_config(self) -> str:
        runtime = self.active_runtime()
        if runtime is None:
            raise ValueError("No active Memcached runtime selected.")
        pid_path = self.pid_path(runtime)
        log_path = self.log_path(runtime)
        data_dir = self.data_dir(runtime)
        config = (
            f"-l {self.DEFAULT_HOST}\n"
            f"-p {self.DEFAULT_PORT}\n"
            f"-P {pid_path}\n"
            f"-v\n"
            f"# log: {log_path}\n"
            f"# data: {data_dir}\n"
        )
        path = self.config_path(runtime)
        path.write_text(config, encoding="utf-8")
        return str(path)

    def service_definition(self) -> ServiceDefinition | None:
        runtime = self.active_runtime()
        if runtime is None:
            return None
        log_path = self.log_path(runtime)
        config = self.read_config_settings(runtime)
        host = str(config.get("host", self.DEFAULT_HOST))
        port = int(config.get("port", self.DEFAULT_PORT))
        return ServiceDefinition(
            id="memcached",
            name="Memcached",
            kind=ServiceKind.REDIS,
            executable_name=Path(runtime.server_path).name,
            default_port=port,
            executable_path=runtime.server_path,
            arguments=[
                "-l", host,
                "-p", str(port),
                "-P", str(self.pid_path(runtime)),
                "-v",
            ],
            working_directory=str(self.runtime_paths.runtime_dir / "memcached"),
            log_path=str(log_path),
        )

    def status(self) -> ServiceStatus:
        definition = self.service_definition()
        if definition is None:
            return ServiceStatus(service_id="memcached", state=ServiceState.STOPPED, message="No active Memcached runtime selected.")
        return self.process_manager.status(definition)

    def start_runtime(self) -> OperationResult:
        definition = self.service_definition()
        if definition is None:
            LOGGER.error("Memcached start failed: no active Memcached runtime selected.")
            return OperationResult(False, "No active Memcached runtime selected.")
        # Ensure config exists at least once.
        if not self.config_path(self.active_runtime()).exists():
            self.generate_config()
        if self._port_in_use(definition.default_port):
            LOGGER.error(
                "Memcached cannot start because port %s is already in use.",
                definition.default_port,
            )
            return OperationResult(
                False,
                f"Memcached cannot start because port {definition.default_port} is already in use.",
                {"port": definition.default_port},
            )
        status = self.process_manager.start(definition)
        if status.state == ServiceState.ERROR:
            LOGGER.error("Memcached start failed: %s", status.message)
        return OperationResult(status.state != ServiceState.ERROR, status.message, {"state": status.to_dict()})

    def stop_runtime(self) -> OperationResult:
        status = self.process_manager.stop("memcached")
        if status.state != ServiceState.ERROR:
            return OperationResult(True, status.message, {"state": status.to_dict()})
        for _ in range(8):
            current = self.status()
            if current.state == ServiceState.STOPPED:
                return OperationResult(True, "Memcached stopped.", {"state": current.to_dict()})
            time.sleep(0.1)
        LOGGER.error("Memcached stop failed: %s", status.message)
        return OperationResult(False, status.message, {"state": status.to_dict()})

    def restart_runtime(self) -> OperationResult:
        self.process_manager.stop("memcached")
        result = self.start_runtime()
        if not result.success:
            LOGGER.error("Memcached restart failed: %s", result.message)
        return result

    def read_log_tail(self, lines: int = 120) -> str:
        path = self.log_path()
        if not path.exists():
            return ""
        content = path.read_text(encoding="utf-8", errors="replace").splitlines()
        return "\n".join(content[-lines:])

    def _port_in_use(self, port: int) -> bool:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.1)
            return sock.connect_ex(("127.0.0.1", port)) == 0

    def read_config_settings(self, runtime: MemcachedRuntime | None = None) -> dict[str, str | int]:
        active = runtime or self.active_runtime()
        if active is None:
            return {"host": self.DEFAULT_HOST, "port": self.DEFAULT_PORT}
        path = self.config_path(runtime)
        if not path.exists():
            self.generate_config()
        host = self.DEFAULT_HOST
        port = self.DEFAULT_PORT
        try:
            for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
                line = raw.strip()
                if not line or line.startswith("#"):
                    continue
                if line.startswith("-l "):
                    candidate = line[3:].strip()
                    if candidate:
                        host = candidate
                elif line.startswith("-p "):
                    candidate = line[3:].strip()
                    if candidate.isdigit():
                        port = int(candidate)
        except Exception:
            pass
        return {"host": host, "port": port}

    def save_config_settings(self, host: str, port: int, runtime: MemcachedRuntime | None = None) -> OperationResult:
        cleaned_host = host.strip()
        if not cleaned_host:
            return OperationResult(False, "Host is required.")
        if port <= 0 or port > 65535:
            return OperationResult(False, "Port must be between 1 and 65535.")
        active = runtime or self.active_runtime()
        if active is None:
            return OperationResult(False, "No active Memcached runtime selected.")
        pid_path = self.pid_path(active)
        log_path = self.log_path(active)
        data_dir = self.data_dir(active)
        config = (
            f"-l {cleaned_host}\n"
            f"-p {port}\n"
            f"-P {pid_path}\n"
            f"-v\n"
            f"# log: {log_path}\n"
            f"# data: {data_dir}\n"
        )
        path = self.config_path(active)
        path.write_text(config, encoding="utf-8")
        return OperationResult(True, "Memcached config saved.", {"path": str(path)})
