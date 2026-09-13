from __future__ import annotations

import logging
from pathlib import Path
import socket
import time

from server_engine.core.models import OperationResult, RedisRuntime, RuntimePaths, ServiceDefinition, ServiceKind, ServiceState, ServiceStatus
from server_engine.infrastructure.process_manager import ProcessManager
from server_engine.services.redis_runtime_service import RedisRuntimeService
from server_engine.services.settings_service import SettingsService


LOGGER = logging.getLogger("server_engine.redis")


class RedisService:
    def __init__(
        self,
        runtime_paths: RuntimePaths,
        settings_service: SettingsService,
        runtime_service: RedisRuntimeService,
        process_manager: ProcessManager,
    ) -> None:
        self.runtime_paths = runtime_paths
        self.settings_service = settings_service
        self.runtime_service = runtime_service
        self.process_manager = process_manager

    def active_runtime(self) -> RedisRuntime | None:
        settings = self.settings_service.get_settings()
        return self.runtime_service.resolve(runtime_id=settings.active_redis_version)

    def runtime_metadata(self) -> dict[str, object]:
        settings = self.settings_service.get_settings()
        runtime = self.active_runtime()
        return {
            "active_runtime": runtime.to_dict() if runtime else None,
            "available_runtimes": [item.to_dict() for item in self.runtime_service.list_runtimes()],
            "config_path": str(self.config_path(runtime)),
            "data_dir": str(self.data_dir(runtime, create=False)),
            "port": settings.redis_port,
        }

    def _runtime_key(self, runtime: RedisRuntime | None = None) -> str:
        active = runtime or self.active_runtime()
        return active.id if active else "redis"

    def _runtime_log_key(self, runtime: RedisRuntime | None = None) -> str:
        active = runtime or self.active_runtime()
        if active is None:
            return "redis"
        return active.version.strip() or active.id

    def _password_for_runtime(self, runtime: RedisRuntime | None = None) -> str:
        settings = self.settings_service.get_settings()
        runtime_key = self._runtime_key(runtime)
        runtime_passwords = settings.redis_runtime_passwords or {}
        if runtime_key in runtime_passwords:
            return runtime_passwords.get(runtime_key, "")
        return settings.redis_password

    def config_path(self, runtime: RedisRuntime | None = None) -> Path:
        path = self.runtime_paths.redis_config_dir / f"{self._runtime_key(runtime)}.conf"
        path.parent.mkdir(parents=True, exist_ok=True)
        return path

    def log_path(self, runtime: RedisRuntime | None = None) -> Path:
        path = self.runtime_paths.logs_dir / "redis" / self._runtime_log_key(runtime) / "redis.log"
        path.parent.mkdir(parents=True, exist_ok=True)
        return path

    def pid_path(self, runtime: RedisRuntime | None = None) -> Path:
        path = self.runtime_paths.runtime_dir / "redis" / f"{self._runtime_key(runtime)}.pid"
        path.parent.mkdir(parents=True, exist_ok=True)
        return path

    def data_dir(self, runtime: RedisRuntime | None = None, create: bool = True) -> Path:
        path = self.runtime_paths.data_dir / "redis" / self._runtime_key(runtime)
        if create:
            path.mkdir(parents=True, exist_ok=True)
        return path

    def generate_config(self) -> str:
        settings = self.settings_service.get_settings()
        runtime = self.active_runtime()
        if runtime is None:
            raise ValueError("No active Redis runtime selected.")
        data_dir = self.data_dir(runtime)
        log_path = self.log_path(runtime)
        pid_path = self.pid_path(runtime)
        config = (
            "bind 127.0.0.1\n"
            "protected-mode yes\n"
            f"port {settings.redis_port}\n"
            "daemonize no\n"
            "supervised no\n"
            f"pidfile {self._quote_config_path(pid_path)}\n"
            f"dir {self._quote_config_path(data_dir)}\n"
            "dbfilename dump.rdb\n"
            "appendonly no\n"
            f"logfile {self._quote_config_path(log_path)}\n"
        )
        password = self._password_for_runtime(runtime)
        if password:
            config += f"requirepass {password}\n"
        path = self.config_path(runtime)
        path.write_text(config, encoding="utf-8")
        return str(path)

    def _quote_config_path(self, path: Path) -> str:
        value = str(path).replace("\\", "\\\\").replace('"', '\\"')
        return f'"{value}"'

    def service_definition(self) -> ServiceDefinition | None:
        runtime = self.active_runtime()
        if runtime is None:
            return None
        settings = self.settings_service.get_settings()
        return ServiceDefinition(
            id="redis",
            name="Redis",
            kind=ServiceKind.REDIS,
            executable_name=Path(runtime.server_path).name,
            default_port=settings.redis_port,
            executable_path=runtime.server_path,
            arguments=[self.generate_config()],
            working_directory=str(self.runtime_paths.runtime_dir / "redis"),
            log_path=str(self.log_path(runtime)),
        )

    def status(self) -> ServiceStatus:
        definition = self.service_definition()
        if definition is None:
            return ServiceStatus(service_id="redis", state=ServiceState.STOPPED, message="No active Redis runtime selected.")
        return self.process_manager.status(definition)

    def start_runtime(self) -> OperationResult:
        definition = self.service_definition()
        if definition is None:
            LOGGER.error("Redis start failed: no active Redis runtime selected.")
            return OperationResult(False, "No active Redis runtime selected.")
        if self._port_in_use(definition.default_port):
            LOGGER.error(
                "Redis cannot start because port %s is already in use.",
                definition.default_port,
            )
            return OperationResult(
                False,
                f"Redis cannot start because port {definition.default_port} is already in use. Stop the existing service or change the Redis port.",
                {"port": definition.default_port},
            )
        status = self.process_manager.start(definition)
        if status.state == ServiceState.ERROR:
            LOGGER.error("Redis start failed: %s", status.message)
        return OperationResult(status.state != ServiceState.ERROR, status.message, {"state": status.to_dict()})

    def stop_runtime(self) -> OperationResult:
        status = self.process_manager.stop("redis")
        if status.state != ServiceState.ERROR:
            return OperationResult(True, status.message, {"state": status.to_dict()})
        for _ in range(8):
            current = self.status()
            if current.state == ServiceState.STOPPED:
                return OperationResult(True, "Redis stopped.", {"state": current.to_dict()})
            time.sleep(0.1)
        LOGGER.error("Redis stop failed: %s", status.message)
        return OperationResult(False, status.message, {"state": status.to_dict()})

    def restart_runtime(self) -> OperationResult:
        self.process_manager.stop("redis")
        result = self.start_runtime()
        if not result.success:
            LOGGER.error("Redis restart failed: %s", result.message)
        return result

    def read_log_tail(self, lines: int = 120) -> str:
        path = self.log_path()
        if not path.exists():
            return ""
        content = path.read_text(encoding="utf-8", errors="replace").splitlines()
        return "\n".join(content[-lines:])

    def password(self) -> str:
        return self._password_for_runtime()

    def update_password(self, new_password: str) -> OperationResult:
        runtime = self.active_runtime()
        if runtime is None:
            return OperationResult(False, "No active Redis runtime selected.")
        value = new_password.strip()
        settings = self.settings_service.get_settings()
        settings.redis_password = value
        runtime_passwords = dict(settings.redis_runtime_passwords or {})
        runtime_passwords[self._runtime_key(runtime)] = value
        settings.redis_runtime_passwords = runtime_passwords
        self.settings_service.save_settings(settings)
        self.generate_config()
        if value:
            return OperationResult(True, "Updated Redis password. Restart Redis to apply the new password.")
        return OperationResult(True, "Cleared Redis password. Restart Redis to apply the change.")

    def _port_in_use(self, port: int) -> bool:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.1)
            return sock.connect_ex(("127.0.0.1", port)) == 0
