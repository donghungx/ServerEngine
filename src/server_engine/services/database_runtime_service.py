from __future__ import annotations

from server_engine.core.models import DatabaseRuntime
from server_engine.infrastructure.binary_locator import BinaryLocator


class DatabaseRuntimeService:
    def __init__(self, binary_locator: BinaryLocator) -> None:
        self.binary_locator = binary_locator

    def list_runtimes(self) -> list[DatabaseRuntime]:
        return self.binary_locator.available_database_runtimes()

    def list_ids(self) -> list[str]:
        return [runtime.id for runtime in self.list_runtimes()]

    def resolve(self, runtime_id: str | None = None, preferred_engine: str | None = None) -> DatabaseRuntime | None:
        return self.binary_locator.database_runtime(runtime_id=runtime_id, preferred_engine=preferred_engine)

    def require(self, runtime_id: str | None = None, preferred_engine: str | None = None) -> DatabaseRuntime:
        runtime = self.resolve(runtime_id=runtime_id, preferred_engine=preferred_engine)
        if runtime is None:
            available = ", ".join(self.list_ids()) or "none"
            raise ValueError(f"Database runtime not available. Available versions: {available}")
        return runtime
