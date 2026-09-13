from __future__ import annotations

from typing import Any, Callable

from server_engine.infrastructure.binary_locator import BinaryLocator
from server_engine.services.app_cache_service import AppCacheService


class RuntimeInventoryService:
    RUNTIME_LABELS: dict[str, str] = {
        "php": "PHP",
        "apache": "Apache",
        "nginx": "Nginx",
        "mysql": "MySQL",
        "mariadb": "MariaDB",
        "database": "Database",
        "mongodb": "MongoDB",
        "postgresql": "PostgreSQL",
        "redis": "Redis",
        "memcached": "Memcached",
        "mailpit": "Mailpit",
        "node": "Node",
        "phpmyadmin": "phpMyAdmin",
    }

    RUNTIME_KINDS: tuple[str, ...] = (
        "php",
        "apache",
        "nginx",
        "database",
        "redis",
        "memcached",
        "mailpit",
        "node",
        "phpmyadmin",
    )

    def __init__(self, binary_locator: BinaryLocator, cache_service: AppCacheService) -> None:
        self.binary_locator = binary_locator
        self.cache_service = cache_service
        self._rebuilders: dict[str, Callable[[], list[dict[str, Any]]]] = {
            "php": self.rebuild_php,
            "apache": self.rebuild_apache,
            "nginx": self.rebuild_nginx,
            "database": self.rebuild_database,
            "redis": self.rebuild_redis,
            "memcached": self.rebuild_memcached,
            "mailpit": self.rebuild_mailpit,
            "node": self.rebuild_node,
            "phpmyadmin": self.rebuild_phpmyadmin,
        }

    def label_for(self, kind: str) -> str:
        return self.RUNTIME_LABELS.get(kind, kind.title())

    def runtimes(self, kind: str) -> list[dict[str, Any]]:
        return self.cache_service.get_runtime_inventory(kind)

    def php_runtimes(self) -> list[dict[str, Any]]:
        return self.runtimes("php")

    def apache_runtimes(self) -> list[dict[str, Any]]:
        return self.runtimes("apache")

    def nginx_runtimes(self) -> list[dict[str, Any]]:
        return self.runtimes("nginx")

    def database_runtimes(self) -> list[dict[str, Any]]:
        return self.runtimes("database")

    def redis_runtimes(self) -> list[dict[str, Any]]:
        return self.runtimes("redis")

    def memcached_runtimes(self) -> list[dict[str, Any]]:
        return self.runtimes("memcached")

    def mailpit_runtimes(self) -> list[dict[str, Any]]:
        return self.runtimes("mailpit")

    def node_runtimes(self) -> list[dict[str, Any]]:
        return self.runtimes("node")

    def phpmyadmin_versions(self) -> list[dict[str, Any]]:
        return self.runtimes("phpmyadmin")

    def rebuild(self, kind: str) -> list[dict[str, Any]]:
        rebuilder = self._rebuilders.get(kind)
        if rebuilder is None:
            return []
        return rebuilder()

    def rebuild_php(self) -> list[dict[str, Any]]:
        self.cache_service.clear_runtime_inventory("php")
        items = [runtime.to_dict() for runtime in self.binary_locator.available_php_runtimes()]
        self.cache_service.set_runtime_inventory("php", items)
        return items

    def rebuild_apache(self) -> list[dict[str, Any]]:
        self.cache_service.clear_runtime_inventory("apache")
        items = [
            {
                "id": runtime.name,
                "version": runtime.name.removeprefix("apache-").removeprefix("apache"),
                "label": runtime.name,
                "home": str(runtime),
            }
            for runtime in self.binary_locator.available_apache_runtimes()
        ]
        self.cache_service.set_runtime_inventory("apache", items)
        return items

    def rebuild_nginx(self) -> list[dict[str, Any]]:
        self.cache_service.clear_runtime_inventory("nginx")
        items = [
            {
                "id": runtime.name,
                "version": runtime.name.removeprefix("nginx-").removeprefix("nginx"),
                "label": runtime.name,
                "home": str(runtime),
            }
            for runtime in self.binary_locator.available_nginx_runtimes()
        ]
        self.cache_service.set_runtime_inventory("nginx", items)
        return items

    def rebuild_database(self) -> list[dict[str, Any]]:
        self.cache_service.clear_runtime_inventory("database")
        items = [runtime.to_dict() for runtime in self.binary_locator.available_database_runtimes()]
        self.cache_service.set_runtime_inventory("database", items)
        return items

    def rebuild_redis(self) -> list[dict[str, Any]]:
        self.cache_service.clear_runtime_inventory("redis")
        items = [runtime.to_dict() for runtime in self.binary_locator.available_redis_runtimes()]
        self.cache_service.set_runtime_inventory("redis", items)
        return items

    def rebuild_memcached(self) -> list[dict[str, Any]]:
        self.cache_service.clear_runtime_inventory("memcached")
        items = [runtime.to_dict() for runtime in self.binary_locator.available_memcached_runtimes()]
        self.cache_service.set_runtime_inventory("memcached", items)
        return items

    def rebuild_mailpit(self) -> list[dict[str, Any]]:
        self.cache_service.clear_runtime_inventory("mailpit")
        items = [runtime.to_dict() for runtime in self.binary_locator.available_mailpit_runtimes()]
        self.cache_service.set_runtime_inventory("mailpit", items)
        return items

    def rebuild_node(self) -> list[dict[str, Any]]:
        self.cache_service.clear_runtime_inventory("node")
        items = self.binary_locator.available_node_runtimes()
        self.cache_service.set_runtime_inventory("node", items)
        return items

    def rebuild_phpmyadmin(self) -> list[dict[str, Any]]:
        self.cache_service.clear_runtime_inventory("phpmyadmin")
        items = [
            {
                "id": version,
                "version": version,
                "label": version,
            }
            for version in self.binary_locator.available_phpmyadmin_versions()
        ]
        self.cache_service.set_runtime_inventory("phpmyadmin", items)
        return items

    def rebuild_all(self) -> None:
        for kind in self.RUNTIME_KINDS:
            self.rebuild(kind)

    def ensure_seeded(self) -> None:
        for kind in self.RUNTIME_KINDS:
            if not self.cache_service.has_runtime_inventory(kind):
                self.rebuild(kind)

    def clear(self, kind: str) -> None:
        self.cache_service.clear_runtime_inventory(kind)

    def clear_all(self) -> None:
        for kind in self.RUNTIME_KINDS:
            self.clear(kind)

    def clear_and_rebuild(self, kind: str) -> list[dict[str, Any]]:
        self.clear(kind)
        return self.rebuild(kind)

    def clear_and_rebuild_all(self) -> None:
        self.clear_all()
        self.rebuild_all()
