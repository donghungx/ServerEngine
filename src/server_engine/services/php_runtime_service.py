from __future__ import annotations

from server_engine.core.models import PhpRuntime
from server_engine.infrastructure.binary_locator import BinaryLocator


class PhpRuntimeService:
    def __init__(self, binary_locator: BinaryLocator) -> None:
        self.binary_locator = binary_locator

    def list_runtimes(self) -> list[PhpRuntime]:
        return self.binary_locator.available_php_runtimes()

    def list_versions(self) -> list[str]:
        return [runtime.version for runtime in self.list_runtimes()]

    def get_runtime(self, requested_version: str) -> PhpRuntime | None:
        return self.binary_locator.php_runtime(requested_version)

    def require_runtime(self, requested_version: str) -> PhpRuntime:
        runtime = self.get_runtime(requested_version)
        if runtime is None:
            versions = ", ".join(self.list_versions()) or "none"
            raise ValueError(f"PHP runtime not available for version '{requested_version}'. Available versions: {versions}")
        return runtime
