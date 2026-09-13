from __future__ import annotations

import logging
from pathlib import Path
import socket
import time

from server_engine.core.models import MailpitRuntime, OperationResult, ServiceDefinition, ServiceKind, ServiceState, ServiceStatus
from server_engine.infrastructure.binary_locator import BinaryLocator
from server_engine.infrastructure.process_manager import ProcessManager
from server_engine.services.settings_service import SettingsService


LOGGER = logging.getLogger("server_engine.mailpit")


class MailpitService:
    def __init__(self, settings_service: SettingsService, binary_locator: BinaryLocator, process_manager: ProcessManager) -> None:
        self.settings_service = settings_service
        self.binary_locator = binary_locator
        self.process_manager = process_manager

    def active_runtime(self) -> MailpitRuntime | None:
        return self.binary_locator.mailpit_runtime()

    def _runtime_key(self, runtime: MailpitRuntime | None = None) -> str:
        active = runtime or self.active_runtime()
        if active is None:
            return "mailpit"
        return (active.version or active.id or "mailpit").strip() or "mailpit"

    def log_path(self, runtime: MailpitRuntime | None = None) -> Path:
        active = runtime or self.active_runtime()
        if active is None:
            path = self.binary_locator.runtime_paths.logs_dir / "mailpit" / "mailpit.log"
        else:
            path = self.binary_locator.runtime_paths.logs_dir / "mailpit" / self._runtime_key(active) / "mailpit.log"
        path.parent.mkdir(parents=True, exist_ok=True)
        return path

    def service_definition(self) -> ServiceDefinition:
        settings = self.settings_service.get_settings()
        runtime = self.active_runtime()
        binary = self.binary_locator.mailpit_binary()
        return ServiceDefinition(
            id="mailpit",
            name="Mailpit",
            kind=ServiceKind.MAILPIT,
            executable_name="mailpit",
            default_port=settings.mailpit_http_port,
            executable_path=str(binary),
            arguments=[
                "--smtp",
                f"127.0.0.1:{settings.mailpit_smtp_port}",
                "--listen",
                f"127.0.0.1:{settings.mailpit_http_port}",
            ],
            working_directory=str(self.binary_locator.runtime_paths.runtime_dir),
            log_path=str(self.log_path(runtime)),
        )

    def status(self) -> ServiceStatus:
        return self.process_manager.status(self.service_definition())

    def start_runtime(self) -> OperationResult:
        definition = self.service_definition()
        settings = self.settings_service.get_settings()

        if self._port_in_use(settings.mailpit_smtp_port):
            LOGGER.error("Mailpit cannot start because SMTP port %s is already in use.", settings.mailpit_smtp_port)
            return OperationResult(False, f"Mailpit SMTP port {settings.mailpit_smtp_port} is already in use.")

        if self._port_in_use(settings.mailpit_http_port):
            LOGGER.error("Mailpit cannot start because web port %s is already in use.", settings.mailpit_http_port)
            return OperationResult(False, f"Mailpit web port {settings.mailpit_http_port} is already in use.")

        status = self.process_manager.start(definition)
        if status.state == ServiceState.ERROR:
            LOGGER.error("Mailpit start failed: %s", status.message)
        return OperationResult(status.state != ServiceState.ERROR, status.message)

    def stop_runtime(self) -> OperationResult:
        status = self.process_manager.stop("mailpit")
        if status.state != ServiceState.ERROR:
            return OperationResult(True, status.message)
        # Process termination can race with status bookkeeping; verify actual state before failing.
        for _ in range(6):
            current = self.status()
            if current.state == ServiceState.STOPPED:
                return OperationResult(True, "Mailpit stopped.")
            time.sleep(0.1)
        LOGGER.error("Mailpit stop failed: %s", status.message)
        return OperationResult(False, status.message)

    def restart_runtime(self) -> OperationResult:
        self.process_manager.stop("mailpit")
        result = self.start_runtime()
        if not result.success:
            LOGGER.error("Mailpit restart failed: %s", result.message)
        return result

    def web_url(self) -> str:
        settings = self.settings_service.get_settings()
        return f"http://127.0.0.1:{settings.mailpit_http_port}"

    def read_log_tail(self, lines: int = 120) -> str:
        path = self.log_path()
        if not path.exists():
            return ""
        return "\n".join(path.read_text(encoding="utf-8", errors="replace").splitlines()[-lines:])

    def _port_in_use(self, port: int) -> bool:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.1)
            return sock.connect_ex(("127.0.0.1", port)) == 0
