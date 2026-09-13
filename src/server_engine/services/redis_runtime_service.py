from __future__ import annotations

from server_engine.core.models import RedisRuntime
from server_engine.infrastructure.binary_locator import BinaryLocator


class RedisRuntimeService:
    def __init__(self, binary_locator: BinaryLocator) -> None:
        self.binary_locator = binary_locator

    def list_runtimes(self) -> list[RedisRuntime]:
        return self.binary_locator.available_redis_runtimes()

    def list_ids(self) -> list[str]:
        return [runtime.id for runtime in self.list_runtimes()]

    def resolve(self, runtime_id: str | None = None) -> RedisRuntime | None:
        return self.binary_locator.redis_runtime(runtime_id=runtime_id)

    def require(self, runtime_id: str | None = None) -> RedisRuntime:
        runtime = self.resolve(runtime_id=runtime_id)
        if runtime is None:
            available = ", ".join(self.list_ids()) or "none"
            raise ValueError(f"Redis runtime not available. Available versions: {available}")
        return runtime
