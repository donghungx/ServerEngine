from __future__ import annotations

from pathlib import Path
import re

from server_engine.core.models import AppSettings, RuntimePaths
from server_engine.infrastructure.repositories.settings_repository import SettingsRepository


class SettingsService:
    def __init__(self, repository: SettingsRepository, runtime_paths: RuntimePaths) -> None:
        self.repository = repository
        self.runtime_paths = runtime_paths

    def _single_available_apache_runtime(self) -> str | None:
        runtime_root = self.runtime_paths.bin_dir / "server"
        if not runtime_root.exists():
            return None
        runtimes = sorted(
            child.name
            for child in runtime_root.iterdir()
            if child.is_dir() and child.name.startswith("apache-")
        )
        if len(runtimes) != 1:
            return None
        return runtimes[0]

    def get_settings(self) -> AppSettings:
        settings = self.repository.load()
        if settings.environment_root is None:
            settings.environment_root = str(self.runtime_paths.root)
        settings.default_php_version = (settings.default_php_version or "8.3.30").strip() or "8.3.30"
        settings.default_mysql_version = (settings.default_mysql_version or "mysql-8.4.9").strip() or "mysql-8.4.9"
        settings.default_mariadb_version = (settings.default_mariadb_version or "mariadb-12.2.2").strip() or "mariadb-12.2.2"
        settings.default_redis_version = (settings.default_redis_version or "redis-8.6.3").strip() or "redis-8.6.3"
        settings.default_memcached_version = (settings.default_memcached_version or "memcached-1.6.41").strip() or "memcached-1.6.41"
        settings.default_mailpit_version = (settings.default_mailpit_version or "mailpit-1.29.7").strip() or "mailpit-1.29.7"
        settings.default_apache_version = (settings.default_apache_version or "apache-2.4.67").strip() or "apache-2.4.67"
        settings.default_nginx_version = (settings.default_nginx_version or "nginx-1.31.0").strip() or "nginx-1.31.0"
        settings.php_runtime_log_to_file = bool(settings.php_runtime_log_to_file)
        settings.php_runtime_log_to_screen = bool(settings.php_runtime_log_to_screen)
        if not settings.php_runtime_log_to_file and not settings.php_runtime_log_to_screen:
            settings.php_runtime_log_to_file = True
        raw_log_path = (settings.php_runtime_log_dir or "").strip()
        if raw_log_path:
            expanded = Path(raw_log_path).expanduser()
            if expanded.suffix:
                expanded = expanded.parent
            elif expanded.name == "php.log":
                expanded = expanded.parent
            settings.php_runtime_log_dir = str(expanded)
        else:
            settings.php_runtime_log_dir = str(self.runtime_paths.logs_dir / "php")
        if settings.apache_port <= 0:
            settings.apache_port = 8080
        settings.active_apache_version = (settings.active_apache_version or "").strip() or None
        if settings.active_apache_version is None:
            single_apache_runtime = self._single_available_apache_runtime()
            if single_apache_runtime is not None:
                settings.active_apache_version = single_apache_runtime
                self.repository.save(settings)
        settings.active_nginx_version = (settings.active_nginx_version or "").strip() or None
        settings.apache_error_log_path = (settings.apache_error_log_path or "").strip()
        settings.nginx_worker_processes = (settings.nginx_worker_processes or "1").strip() or "1"
        if settings.nginx_worker_connections <= 0:
            settings.nginx_worker_connections = 1024
        if settings.nginx_keepalive_timeout <= 0:
            settings.nginx_keepalive_timeout = 65
        settings.nginx_client_max_body_size = (settings.nginx_client_max_body_size or "64m").strip() or "64m"
        settings.nginx_error_log_path = (settings.nginx_error_log_path or "").strip()
        settings.active_node_version = (settings.active_node_version or "").strip() or None
        if settings.database_port <= 0:
            settings.database_port = 3306
        default_db_opt = AppSettings().database_optimization
        merged_db_opt: dict[str, int] = {}
        for key, default_value in default_db_opt.items():
            try:
                merged_db_opt[key] = int((settings.database_optimization or {}).get(key, default_value))
            except Exception:
                merged_db_opt[key] = int(default_value)
        settings.database_optimization = merged_db_opt
        settings.cache_driver = (settings.cache_driver or "redis").strip().lower()
        if settings.cache_driver not in {"redis", "memcached", "apcu", "file"}:
            settings.cache_driver = "redis"
        settings.active_memcached_version = (settings.active_memcached_version or "").strip() or None
        settings.active_mailpit_version = (settings.active_mailpit_version or "").strip() or None
        settings.active_mongodb_version = (settings.active_mongodb_version or "").strip() or None
        settings.active_postgresql_version = (settings.active_postgresql_version or "").strip() or None
        if settings.redis_port <= 0:
            settings.redis_port = 6379
        if settings.mailpit_smtp_port <= 0:
            settings.mailpit_smtp_port = 1025
        if settings.mailpit_http_port <= 0:
            settings.mailpit_http_port = 8025
        settings.appearance_theme = (settings.appearance_theme or "system").strip().lower()
        if settings.appearance_theme not in {"system", "light", "dark"}:
            settings.appearance_theme = "system"
        settings.appearance_accent_color = (settings.appearance_accent_color or "#007bff").strip().lower()
        if not re.fullmatch(r"#[0-9a-f]{6}", settings.appearance_accent_color):
            settings.appearance_accent_color = "#007bff"
        settings.appearance_language = (settings.appearance_language or "en").strip().lower()
        if settings.appearance_language in {"zh_cn", "zh-sg"}:
            settings.appearance_language = "zh-hans"
        elif settings.appearance_language in {"zh_tw", "zh_hk", "zh-mo"}:
            settings.appearance_language = "zh-hant"
        if settings.appearance_language not in {"en", "vi", "zh-hans", "zh-hant"}:
            settings.appearance_language = "en"
        defaults = {"web": True, "database": True, "redis": False, "memcached": False, "mailpit": False}
        normalized_global = {}
        for key, default_value in defaults.items():
            normalized_global[key] = bool((settings.home_global_services or {}).get(key, default_value))
        settings.home_global_services = normalized_global
        if settings.bottom_terminal_panel_height < 80:
            settings.bottom_terminal_panel_height = 80
        return settings

    def save_settings(self, settings: AppSettings) -> AppSettings:
        return self.repository.save(settings)
