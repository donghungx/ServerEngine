from __future__ import annotations

import logging
import os
from pathlib import Path
from typing import Callable, Any

from server_engine.core.models import (
    DatabaseRuntime,
    PhpRuntime,
    RedisRuntime,
    MemcachedRuntime,
    MailpitRuntime,
    RuntimePaths,
)
from server_engine.services.app_cache_service import AppCacheService

LOGGER = logging.getLogger("server_engine.runtime_inventory")


class BinaryLocator:
    def __init__(self, runtime_paths: RuntimePaths, app_cache: AppCacheService) -> None:
        self.runtime_paths = runtime_paths
        self.app_cache = app_cache
        self.project_root = Path(__file__).resolve().parents[3]
        self._settings_provider: Callable[[], Any] | None = None

    def set_settings_provider(self, provider: Callable[[], Any]) -> None:
        self._settings_provider = provider

    def _dev_runtime_inventory_logging_enabled(self) -> bool:
        env_value = os.environ.get("SERVER_ENGINE_RUNTIME_INVENTORY_LOG", "").strip().lower()
        return env_value in {"1", "true", "yes", "on"}

    def _log_runtime_inventory_load(self, kind: str, source: str, count: int) -> None:
        if self._dev_runtime_inventory_logging_enabled():
            LOGGER.info("Runtime inventory loaded kind=%s source=%s count=%d", kind, source, count)

    def _runtime_kind_for_server_prefix(self, prefix: str) -> str:
        return "apache" if prefix.startswith("apache") else "nginx"

    def _cached_path_items(self, kind: str) -> list[Path]:
        paths: list[Path] = []
        for item in self.app_cache.get_runtime_inventory(kind):
            if not isinstance(item, dict):
                continue
            home = str(item.get("home") or "").strip()
            if home:
                paths.append(Path(home))
        return paths

    def _cache_path_items(self, kind: str, paths: list[Path], prefix: str = "") -> None:
        self.app_cache.set_runtime_inventory(
            kind,
            [
                {
                    "id": path.name,
                    "version": path.name.removeprefix(prefix).removeprefix(prefix.rstrip("-")).lstrip("-"),
                    "label": path.name,
                    "home": str(path),
                }
                for path in paths
            ],
        )

    def project_dist_apache_root(self) -> Path:
        return self.deployed_apache_root()

    def deployed_apache_root(self) -> Path:
        return self.runtime_paths.bin_dir / "server"

    def project_dist_php_root(self) -> Path:
        return self.runtime_paths.bin_dir / "php"

    def project_dist_database_root(self) -> Path:
        return self.runtime_paths.bin_dir / "database"

    def project_dist_redis_root(self) -> Path:
        return self.runtime_paths.bin_dir / "redis"

    def project_dist_mailpit_root(self) -> Path:
        return self.runtime_paths.bin_dir / "mailpit"

    def project_dist_memcached_root(self) -> Path:
        return self.runtime_paths.bin_dir / "memcached"

    def project_dist_tools_root(self) -> Path:
        return self.deployed_tools_root()

    def deployed_tools_root(self) -> Path:
        return self.runtime_paths.bin_dir / "tools"

    def latest_composer_phar(self) -> Path | None:
        return self._latest_versioned_tool_phar("composer", "composer-", "composer.phar")

    def latest_wp_cli_phar(self) -> Path | None:
        return self._latest_versioned_tool_phar("wp-cli", "wp-cli-", "wp-cli.phar")

    def _latest_versioned_tool_phar(self, tool_dir_name: str, runtime_prefix: str, phar_name: str) -> Path | None:
        tool_root = self.deployed_tools_root() / tool_dir_name
        if not tool_root.exists():
            return None
        candidates: list[tuple[tuple[int, ...], Path]] = []
        for child in tool_root.iterdir():
            if not child.is_dir() or not child.name.startswith(runtime_prefix):
                continue
            version_text = child.name.removeprefix(runtime_prefix)
            parts: list[int] = []
            for token in version_text.split("."):
                if token.isdigit():
                    parts.append(int(token))
                else:
                    break
            if not parts:
                continue
            phar_path = child / phar_name
            if phar_path.exists():
                candidates.append((tuple(parts), phar_path))
        if not candidates:
            return None
        candidates.sort(key=lambda item: item[0])
        return candidates[-1][1]

    def project_dist_node_root(self) -> Path:
        return self.deployed_node_root()

    def deployed_node_root(self) -> Path:
        return self.runtime_paths.bin_dir / "node"

    def _prefer_project_dist_runtime(self) -> bool:
        return False

    def apache_home(self) -> Path:
        override = os.environ.get("SERVER_ENGINE_APACHE_HOME")
        if override:
            return Path(override).expanduser()
        selected = self._active_runtime_id("apache")
        if selected:
            home = self.apache_runtime_home(selected)
            if home is not None:
                return home
        deployed_root = self.deployed_apache_root()
        if deployed_root.exists():
            runtimes = sorted(
                [child for child in deployed_root.iterdir() if child.is_dir() and child.name.startswith("apache-")],
                key=lambda item: item.name,
            )
            if runtimes:
                return runtimes[-1]
        legacy_runtime = self.runtime_paths.bin_dir / "apache" / "current"
        if legacy_runtime.exists():
            return legacy_runtime
        return deployed_root / "apache-current"

    def apache_httpd(self) -> Path:
        return self.apache_home() / "bin" / "httpd"

    def apachectl(self) -> Path:
        return self.apache_home() / "bin" / "apachectl"

    def nginx_home(self) -> Path:
        override = os.environ.get("SERVER_ENGINE_NGINX_HOME")
        if override:
            return Path(override).expanduser()
        selected = self._active_runtime_id("nginx")
        if selected:
            home = self.nginx_runtime_home(selected)
            if home is not None:
                return home
        deployed_root = self.deployed_apache_root()
        if deployed_root.exists():
            runtimes = sorted(
                [child for child in deployed_root.iterdir() if child.is_dir() and child.name.startswith("nginx-")],
                key=lambda item: item.name,
            )
            if runtimes:
                return runtimes[-1]
        legacy_runtime = self.runtime_paths.bin_dir / "nginx" / "current"
        if legacy_runtime.exists():
            return legacy_runtime
        return deployed_root / "nginx-current"

    def nginx_binary(self) -> Path:
        home = self.nginx_home()
        candidate = home / "bin" / "nginx"
        if candidate.exists():
            return candidate
        return home / "sbin" / "nginx"

    def available_apache_runtimes(self) -> list[Path]:
        return self._available_server_runtimes("apache-")

    def available_nginx_runtimes(self) -> list[Path]:
        return self._available_server_runtimes("nginx-")

    def apache_runtime_home(self, runtime_id: str) -> Path | None:
        return self._server_runtime_home("apache-", runtime_id)

    def nginx_runtime_home(self, runtime_id: str) -> Path | None:
        return self._server_runtime_home("nginx-", runtime_id)

    def _active_runtime_id(self, service: str) -> str | None:
        if self._settings_provider is None:
            return None
        try:
            settings = self._settings_provider()
            value = getattr(settings, f"active_{service}_version", None)
            return str(value).strip() or None
        except Exception:
            return None

    def _server_runtime_roots(self) -> list[Path]:
        return [self.deployed_apache_root()]

    def _available_server_runtimes(self, prefix: str) -> list[Path]:
        kind = self._runtime_kind_for_server_prefix(prefix)
        if self.app_cache.has_runtime_inventory(kind):
            cached = self._cached_path_items(kind)
            runtimes = sorted(cached, key=lambda item: item.name)
            self._log_runtime_inventory_load(kind, "cache", len(runtimes))
            return runtimes
        by_name: dict[str, Path] = {}
        for root in self._server_runtime_roots():
            if not root.exists():
                continue
            for child in sorted(root.iterdir(), key=lambda item: item.name):
                if child.is_dir() and child.name.startswith(prefix) and child.name not in by_name:
                    by_name[child.name] = child
        runtimes = sorted(by_name.values(), key=lambda item: item.name)
        self._cache_path_items(kind, runtimes, prefix)
        self._log_runtime_inventory_load(kind, "scan", len(runtimes))
        return runtimes

    def _server_runtime_home(self, prefix: str, runtime_id: str) -> Path | None:
        requested = runtime_id.strip()
        normalized = requested.removeprefix(prefix).lstrip("-")
        for runtime in self._available_server_runtimes(prefix):
            version = runtime.name.removeprefix(prefix).lstrip("-")
            if runtime.name == requested or version == normalized:
                return runtime
        matches = [
            runtime for runtime in self._available_server_runtimes(prefix)
            if runtime.name.startswith(requested) or runtime.name.removeprefix(prefix).lstrip("-").startswith(normalized)
        ]
        return matches[-1] if matches else None

    def nginx_paths(self) -> dict[str, str]:
        return {
            "project_dist_server_root": str(self.project_dist_apache_root()),
            "nginx_home": str(self.nginx_home()),
            "nginx": str(self.nginx_binary()),
        }

    def phpmyadmin_root(self, requested_version: str | None = None) -> Path:
        target_version = (requested_version or "").strip()
        project_dist = self.project_dist_tools_root() / "phpmyadmin"
        deployed = self.deployed_tools_root() / "phpmyadmin"
        search_roots = [deployed]
        for root in search_roots:
            if not root.exists():
                continue
            runtimes = sorted([child for child in root.iterdir() if child.is_dir() and (child / "index.php").exists()], key=lambda item: item.name)
            if target_version:
                for child in runtimes:
                    if child.name == target_version:
                        return child
            if runtimes:
                return runtimes[-1]
        fallback_root = deployed if deployed.exists() else project_dist
        return fallback_root / (target_version or "current")

    def available_phpmyadmin_versions(self) -> list[str]:
        if self.app_cache.has_runtime_inventory("phpmyadmin"):
            cached = self.app_cache.get_runtime_inventory("phpmyadmin")
            cached_versions = [
                str(item.get("version") or item.get("id") or "").strip()
                for item in cached
                if isinstance(item, dict)
            ]
            versions = [version for version in cached_versions if version]
            self._log_runtime_inventory_load("phpmyadmin", "cache", len(versions))
            return versions
        versions: list[str] = []
        roots = [self.deployed_tools_root() / "phpmyadmin"]
        for root in roots:
            if not root.exists():
                continue
            for child in sorted(root.iterdir(), key=lambda item: item.name):
                if child.is_dir() and (child / "index.php").exists() and child.name not in versions:
                    versions.append(child.name)
        self.app_cache.set_runtime_inventory(
            "phpmyadmin",
            [{"id": version, "version": version, "label": version} for version in versions],
        )
        self._log_runtime_inventory_load("phpmyadmin", "scan", len(versions))
        return versions

    def apache_modules_dir(self) -> Path:
        home = self.apache_home()
        dist_style = home / "lib" / "httpd" / "modules"
        if dist_style.exists():
            return dist_style
        return home / "modules"

    def available_apache_modules(self) -> list[str]:
        modules_dir = self.apache_modules_dir()
        if not modules_dir.exists():
            return []
        return sorted(
            child.name
            for child in modules_dir.iterdir()
            if child.is_file() and child.suffix == ".so" and child.name.startswith("mod_")
        )

    def apache_paths(self) -> dict[str, str]:
        return {
            "project_dist_apache_root": str(self.project_dist_apache_root()),
            "deployed_apache_root": str(self.deployed_apache_root()),
            "apache_home": str(self.apache_home()),
            "apache_runtime_key": self.apache_home().name,
            "httpd": str(self.apache_httpd()),
            "apachectl": str(self.apachectl()),
            "modules_dir": str(self.apache_modules_dir()),
            "config_dir": str(self.runtime_paths.config_dir / self.apache_home().name),
            "sites_dir": str(self.runtime_paths.sites_config_dir),
            "logs_dir": str(self.runtime_paths.logs_dir / "apache"),
            "runtime_dir": str(self.runtime_paths.runtime_dir / "apache"),
        }

    def php_root(self) -> Path:
        override = os.environ.get("SERVER_ENGINE_PHP_ROOT")
        if override:
            return Path(override).expanduser()
        deployed = self.runtime_paths.bin_dir / "php"
        if deployed.exists():
            return deployed
        return deployed

    def _php_runtime_roots(self) -> list[Path]:
        override = os.environ.get("SERVER_ENGINE_PHP_ROOT")
        if override:
            return [Path(override).expanduser()]
        deployed = self.runtime_paths.bin_dir / "php"
        roots = [deployed]
        deduped: list[Path] = []
        for root in roots:
            if root not in deduped:
                deduped.append(root)
        return deduped

    def available_php_runtimes(self) -> list[PhpRuntime]:
        if self.app_cache.has_runtime_inventory("php"):
            cached = self.app_cache.get_runtime_inventory("php")
            runtimes: list[PhpRuntime] = []

            for item in cached:
                if not isinstance(item, dict):
                    continue

                runtime = PhpRuntime(
                    version=str(item.get("version", "")),
                    label=str(item.get("label", "")),
                    home=str(item.get("home", "")),
                    php_path=str(item.get("php_path", "")),
                    php_cgi_path=str(item.get("php_cgi_path", "")),
                    ini_dir=str(item.get("ini_dir", "")),
                )

                if not runtime.version or not runtime.php_path or not runtime.php_cgi_path:
                    continue

                runtimes.append(runtime)

            self._log_runtime_inventory_load("php", "cache", len(runtimes))
            return runtimes

        by_version: dict[str, PhpRuntime] = {}

        for root in self._php_runtime_roots():
            if not root.exists():
                continue

            for child in sorted(root.iterdir(), key=lambda item: item.name):
                if not child.is_dir():
                    continue

                php_path = child / "bin" / "php"
                php_cgi_path = child / "bin" / "php-cgi"
                ini_dir = child / "conf"

                if not php_path.exists() or not php_cgi_path.exists():
                    continue

                version = child.name.removeprefix("php")

                if version in by_version:
                    continue

                by_version[version] = PhpRuntime(
                    version=version,
                    label=child.name,
                    home=str(child),
                    php_path=str(php_path),
                    php_cgi_path=str(php_cgi_path),
                    ini_dir=str(ini_dir),
                )

        runtimes = [by_version[key] for key in sorted(by_version)]

        self.app_cache.set_runtime_inventory(
            "php",
            [runtime.to_dict() for runtime in runtimes],
        )

        self._log_runtime_inventory_load("php", "scan", len(runtimes))
        return runtimes

    def php_runtime(self, requested_version: str) -> PhpRuntime | None:
        normalized = requested_version.strip().removeprefix("php")
        runtimes = self.available_php_runtimes()
        for runtime in runtimes:
            if runtime.version == normalized:
                return runtime
        prefix_matches = [runtime for runtime in runtimes if runtime.version.startswith(normalized + ".") or runtime.version.startswith(normalized)]
        if prefix_matches:
            return sorted(prefix_matches, key=lambda item: item.version)[-1]
        return None

    def php_paths(self) -> dict[str, object]:
        return {
            "project_dist_php_root": str(self.project_dist_php_root()),
            "php_root": str(self.php_root()),
            "versions": [runtime.to_dict() for runtime in self.available_php_runtimes()],
        }

    def available_node_versions(self) -> list[str]:
        versions: list[str] = []

        for item in self.available_node_runtimes():
            version = str(item.get("version", ""))

            if version and version not in versions:
                versions.append(version)

        return sorted(versions)

    def available_node_runtimes(self) -> list[dict[str, str | bool]]:
        items = self._scan_node_runtimes()
        self._log_runtime_inventory_load("node", "scan", len(items))
        return items

    def _scan_node_runtimes(self) -> list[dict[str, str | bool]]:
        by_version: dict[str, dict[str, str | bool]] = {}

        roots: list[tuple[str, Path, bool]] = [
            ("installed", self.deployed_node_root(), True),
        ]

        for source, root, removable in roots:
            if not root.exists():
                continue

            for child in sorted(root.iterdir(), key=lambda item: item.name):
                if not child.is_dir():
                    continue

                node_binary = child / "bin" / "node"

                if not node_binary.exists():
                    continue

                version = child.name.removeprefix("node")
                existing = by_version.get(version)

                if existing is not None and str(existing.get("source", "")) == "installed":
                    continue

                by_version[version] = {
                    "version": version,
                    "label": child.name,
                    "home": str(child),
                    "source": source,
                    "removable": removable,
                }

        items = list(by_version.values())
        items.sort(key=lambda item: str(item["version"]))

        self.app_cache.set_runtime_inventory("node", items)
        return items

    def node_runtime_home(self, requested_version: str) -> Path | None:
        version = requested_version.strip().removeprefix("node")
        candidates = [self.deployed_node_root()]
        for root in candidates:
            if not root.exists():
                continue
            exact = root / f"node{version}"
            if (exact / "bin" / "node").exists():
                return exact
            matches = sorted(
                [
                    child for child in root.iterdir()
                    if child.is_dir()
                    and child.name.startswith(f"node{version}.")
                    and (child / "bin" / "node").exists()
                ],
                key=lambda item: item.name,
            )
            if matches:
                return matches[-1]
        return None

    def node_binary_paths(self, requested_version: str) -> dict[str, Path] | None:
        home = self.node_runtime_home(requested_version)
        if home is None:
            return None
        bin_dir = home / "bin"
        node = bin_dir / "node"
        npm = bin_dir / "npm"
        npx = bin_dir / "npx"
        if not node.exists() or not npm.exists():
            return None
        return {
            "home": home,
            "bin_dir": bin_dir,
            "node": node,
            "npm": npm,
            "npx": npx,
        }

    def database_root(self) -> Path:
        override = os.environ.get("SERVER_ENGINE_DATABASE_ROOT")
        if override:
            return Path(override).expanduser()
        deployed = self.runtime_paths.bin_dir / "database"
        if deployed.exists():
            return deployed
        return deployed

    def available_database_runtimes(self) -> list[DatabaseRuntime]:
        if self.app_cache.has_runtime_inventory("database"):
            cached = self.app_cache.get_runtime_inventory("database")
            cached_runtimes: list[DatabaseRuntime] = []
            for item in cached:
                if not isinstance(item, dict):
                    continue
                runtime = DatabaseRuntime(
                    id=str(item.get("id", "")),
                    engine=str(item.get("engine", "")),
                    version=str(item.get("version", "")),
                    label=str(item.get("label", "")),
                    home=str(item.get("home", "")),
                    server_path=str(item.get("server_path", "")),
                    client_path=str(item.get("client_path", "")) or None,
                    config_template_path=str(item.get("config_template_path", "")) or None,
                )
                if runtime.id and runtime.engine and runtime.version and runtime.server_path:
                    cached_runtimes.append(runtime)
            self._log_runtime_inventory_load("database", "cache", len(cached_runtimes))
            return cached_runtimes
        root = self.database_root()
        if not root.exists():
            return []
        runtimes: list[DatabaseRuntime] = []
        for child in sorted(root.iterdir(), key=lambda item: item.name):
            if not child.is_dir():
                continue
            engine, version = self._parse_database_runtime_name(child.name)
            if engine == "mariadb":
                server_path = child / "bin" / "mariadbd"
                alt_server_path = child / "bin" / "mysqld"
                client_path = child / "bin" / "mysql"
                config_template_path = child / "conf" / "my.cnf"
            elif engine == "mysql":
                server_path = child / "bin" / "mysqld"
                alt_server_path = child / "bin" / "mysqld"
                client_path = child / "bin" / "mysql"
                config_template_path = child / "conf" / "my.cnf"
            elif engine == "mongodb":
                server_path = child / "bin" / "mongod"
                alt_server_path = child / "bin" / "mongod"
                client_path = child / "bin" / "mongosh"
                config_template_path = child / "conf" / "mongod.conf"
            elif engine == "postgresql":
                server_path = child / "bin" / "postgres"
                alt_server_path = child / "bin" / "pg_ctl"
                client_path = child / "bin" / "psql"
                config_template_path = child / "conf" / "postgresql.conf"
            else:
                continue
            if not server_path.exists() and alt_server_path.exists():
                server_path = alt_server_path
            if not server_path.exists():
                continue
            runtimes.append(
                DatabaseRuntime(
                    id=child.name,
                    engine=engine,
                    version=version,
                    label=child.name,
                    home=str(child),
                    server_path=str(server_path),
                    client_path=str(client_path) if client_path.exists() else None,
                    config_template_path=str(config_template_path) if config_template_path.exists() else None,
                )
            )
        self.app_cache.set_runtime_inventory("database", [runtime.to_dict() for runtime in runtimes])
        self._log_runtime_inventory_load("database", "scan", len(runtimes))
        return runtimes

    def database_runtime(self, runtime_id: str | None = None, preferred_engine: str | None = None) -> DatabaseRuntime | None:
        runtimes = self.available_database_runtimes()
        if runtime_id:
            for runtime in runtimes:
                if runtime.id == runtime_id or runtime.version == runtime_id:
                    return runtime
        if preferred_engine:
            engine_matches = [runtime for runtime in runtimes if runtime.engine == preferred_engine]
            if engine_matches:
                return sorted(engine_matches, key=lambda item: item.version)[-1]
        if runtimes:
            return runtimes[-1]
        return None

    def database_paths(self) -> dict[str, object]:
        return {
            "project_dist_database_root": str(self.project_dist_database_root()),
            "database_root": str(self.database_root()),
            "versions": [runtime.to_dict() for runtime in self.available_database_runtimes()],
        }

    def redis_root(self) -> Path:
        override = os.environ.get("SERVER_ENGINE_REDIS_ROOT")
        if override:
            return Path(override).expanduser()
        deployed = self.runtime_paths.bin_dir / "redis"
        if deployed.exists():
            return deployed
        return deployed

    def available_redis_runtimes(self) -> list[RedisRuntime]:
        if self.app_cache.has_runtime_inventory("redis"):
            cached = self.app_cache.get_runtime_inventory("redis")
            cached_runtimes: list[RedisRuntime] = []
            for item in cached:
                if not isinstance(item, dict):
                    continue
                runtime = RedisRuntime(
                    id=str(item.get("id", "")),
                    version=str(item.get("version", "")),
                    label=str(item.get("label", "")),
                    home=str(item.get("home", "")),
                    server_path=str(item.get("server_path", "")),
                    client_path=str(item.get("client_path", "")) or None,
                    config_template_path=str(item.get("config_template_path", "")) or None,
                )
                if runtime.id and runtime.version and runtime.server_path:
                    cached_runtimes.append(runtime)
            self._log_runtime_inventory_load("redis", "cache", len(cached_runtimes))
            return cached_runtimes
        root = self.redis_root()
        if not root.exists():
            return []
        runtimes: list[RedisRuntime] = []
        for child in sorted(root.iterdir(), key=lambda item: item.name):
            if not child.is_dir():
                continue
            server_path = child / "bin" / "redis-server"
            client_path = child / "bin" / "redis-cli"
            if not server_path.exists():
                continue
            config_path = child / "conf" / "redis.conf"
            if not config_path.exists():
                bottle_config = child / ".bottle" / "etc" / "redis.conf"
                if bottle_config.exists():
                    config_path = bottle_config
            runtimes.append(
                RedisRuntime(
                    id=child.name,
                    version=child.name.removeprefix("redis-").removeprefix("redis"),
                    label=child.name,
                    home=str(child),
                    server_path=str(server_path),
                    client_path=str(client_path) if client_path.exists() else None,
                    config_template_path=str(config_path) if config_path.exists() else None,
                )
            )
        self.app_cache.set_runtime_inventory("redis", [runtime.to_dict() for runtime in runtimes])
        self._log_runtime_inventory_load("redis", "scan", len(runtimes))
        return runtimes

    def redis_runtime(self, runtime_id: str | None = None) -> RedisRuntime | None:
        runtimes = self.available_redis_runtimes()
        if runtime_id:
            normalized = runtime_id.strip().removeprefix("redis-").removeprefix("redis")
            for runtime in runtimes:
                if runtime.id == runtime_id or runtime.version == normalized:
                    return runtime
            prefix_matches = [runtime for runtime in runtimes if runtime.version.startswith(normalized)]
            if prefix_matches:
                return sorted(prefix_matches, key=lambda item: item.version)[-1]
        if runtimes:
            return runtimes[-1]
        return None

    def redis_paths(self) -> dict[str, object]:
        return {
            "project_dist_redis_root": str(self.project_dist_redis_root()),
            "redis_root": str(self.redis_root()),
            "versions": [runtime.to_dict() for runtime in self.available_redis_runtimes()],
        }

    def memcached_root(self) -> Path:
        override = os.environ.get("SERVER_ENGINE_MEMCACHED_ROOT")
        if override:
            return Path(override).expanduser()
        deployed = self.runtime_paths.bin_dir / "memcached"
        if deployed.exists():
            return deployed
        return deployed

    def available_memcached_runtimes(self) -> list[MemcachedRuntime]:
        if self.app_cache.has_runtime_inventory("memcached"):
            cached = self.app_cache.get_runtime_inventory("memcached")
            cached_runtimes: list[MemcachedRuntime] = []
            for item in cached:
                if not isinstance(item, dict):
                    continue
                runtime = MemcachedRuntime(
                    id=str(item.get("id", "")),
                    version=str(item.get("version", "")),
                    label=str(item.get("label", "")),
                    home=str(item.get("home", "")),
                    server_path=str(item.get("server_path", "")),
                    tool_path=str(item.get("tool_path", "")) or None,
                )
                if runtime.id and runtime.version and runtime.server_path:
                    cached_runtimes.append(runtime)
            self._log_runtime_inventory_load("memcached", "cache", len(cached_runtimes))
            return cached_runtimes
        root = self.memcached_root()
        if not root.exists():
            return []
        runtimes: list[MemcachedRuntime] = []
        for child in sorted(root.iterdir(), key=lambda item: item.name):
            if not child.is_dir():
                continue
            server_path = child / "bin" / "memcached"
            tool_path = child / "bin" / "memcached-tool"
            if not server_path.exists():
                continue
            runtimes.append(
                MemcachedRuntime(
                    id=child.name,
                    version=child.name.removeprefix("memcached-").removeprefix("memcached"),
                    label=child.name,
                    home=str(child),
                    server_path=str(server_path),
                    tool_path=str(tool_path) if tool_path.exists() else None,
                )
            )
        self.app_cache.set_runtime_inventory("memcached", [runtime.to_dict() for runtime in runtimes])
        self._log_runtime_inventory_load("memcached", "scan", len(runtimes))
        return runtimes

    def memcached_runtime(self, runtime_id: str | None = None) -> MemcachedRuntime | None:
        runtimes = self.available_memcached_runtimes()
        if runtime_id:
            normalized = runtime_id.strip().removeprefix("memcached-").removeprefix("memcached")
            for runtime in runtimes:
                if runtime.id == runtime_id or runtime.version == normalized:
                    return runtime
            prefix_matches = [runtime for runtime in runtimes if runtime.version.startswith(normalized)]
            if prefix_matches:
                return sorted(prefix_matches, key=lambda item: item.version)[-1]
        if runtimes:
            return runtimes[-1]
        return None

    def _parse_database_runtime_name(self, name: str) -> tuple[str, str]:
        lowered = name.lower()
        if lowered.startswith("mariadb-"):
            return "mariadb", name.split("-", 1)[1]
        if lowered.startswith("mysql-"):
            return "mysql", name.split("-", 1)[1]
        if lowered.startswith("mongodb-"):
            return "mongodb", name.split("-", 1)[1]
        if lowered.startswith("postgresql-"):
            return "postgresql", name.split("-", 1)[1]
        if lowered.startswith("mariadb"):
            return "mariadb", name.removeprefix("mariadb").lstrip("-")
        if lowered.startswith("mysql"):
            return "mysql", name.removeprefix("mysql").lstrip("-")
        if lowered.startswith("mongodb"):
            return "mongodb", name.removeprefix("mongodb").lstrip("-")
        if lowered.startswith("postgresql"):
            return "postgresql", name.removeprefix("postgresql").lstrip("-")
        return "", name

    def mailpit_root(self) -> Path:
        override = os.environ.get("SERVER_ENGINE_MAILPIT_ROOT")
        if override:
            return Path(override).expanduser()
        deployed = self.runtime_paths.bin_dir / "mailpit"
        if deployed.exists():
            return deployed
        return deployed

    def available_mailpit_runtimes(self) -> list[MailpitRuntime]:
        if self.app_cache.has_runtime_inventory("mailpit"):
            cached = self.app_cache.get_runtime_inventory("mailpit")
            cached_runtimes: list[MailpitRuntime] = []
            for item in cached:
                if not isinstance(item, dict):
                    continue
                runtime = MailpitRuntime(
                    id=str(item.get("id", "")),
                    version=str(item.get("version", "")),
                    label=str(item.get("label", "")),
                    home=str(item.get("home", "")),
                    server_path=str(item.get("server_path", "")),
                )
                if runtime.id and runtime.version and runtime.server_path:
                    cached_runtimes.append(runtime)
            self._log_runtime_inventory_load("mailpit", "cache", len(cached_runtimes))
            return cached_runtimes
        root = self.mailpit_root()
        if not root.exists():
            return []
        runtimes: list[MailpitRuntime] = []
        for child in sorted(root.iterdir(), key=lambda item: item.name):
            if not child.is_dir():
                continue
            server_path = child / "bin" / "mailpit"
            if not server_path.exists():
                continue
            runtimes.append(
                MailpitRuntime(
                    id=child.name,
                    version=child.name.removeprefix("mailpit-").removeprefix("mailpit"),
                    label=child.name,
                    home=str(child),
                    server_path=str(server_path),
                )
            )
        self.app_cache.set_runtime_inventory("mailpit", [runtime.to_dict() for runtime in runtimes])
        self._log_runtime_inventory_load("mailpit", "scan", len(runtimes))
        return runtimes

    def mailpit_runtime(self, runtime_id: str | None = None) -> MailpitRuntime | None:
        runtimes = self.available_mailpit_runtimes()
        selected = runtime_id or self._active_runtime_id("mailpit")
        if selected:
            normalized = str(selected).strip().removeprefix("mailpit-").removeprefix("mailpit")
            for runtime in runtimes:
                if runtime.id == selected or runtime.version == normalized:
                    return runtime
            prefix_matches = [runtime for runtime in runtimes if runtime.version.startswith(normalized)]
            if prefix_matches:
                return sorted(prefix_matches, key=lambda item: item.version)[-1]
        if runtimes:
            return runtimes[-1]
        return None

    def mailpit_paths(self) -> dict[str, object]:
        return {
            "project_dist_mailpit_root": str(self.project_dist_mailpit_root()),
            "mailpit_root": str(self.mailpit_root()),
            "versions": [runtime.to_dict() for runtime in self.available_mailpit_runtimes()],
        }

    def mailpit_home(self) -> Path:
        runtime = self.mailpit_runtime()
        if runtime is None:
            return self.mailpit_root() / "mailpit-current"
        return Path(runtime.home)

    def mailpit_binary(self) -> Path:
        runtime = self.mailpit_runtime()
        if runtime is None:
            return self.mailpit_root() / "mailpit-current" / "bin" / "mailpit"
        return Path(runtime.server_path)
