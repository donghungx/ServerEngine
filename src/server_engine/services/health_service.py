from __future__ import annotations

import socket

from server_engine.core.models import OperationResult
from server_engine.services.stack_service import StackService


class HealthService:
    def __init__(self, stack_service: StackService) -> None:
        self.stack_service = stack_service

    def stack_summary(self) -> OperationResult:
        status = self.stack_service.status()
        return OperationResult(True, "Stack status collected.", status.to_dict())

    def port_conflicts(self) -> list[int]:
        conflicts: list[int] = []
        for definition in self.stack_service.definitions():
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
                sock.settimeout(0.1)
                if sock.connect_ex(("127.0.0.1", definition.default_port)) == 0:
                    conflicts.append(definition.default_port)
        return conflicts

