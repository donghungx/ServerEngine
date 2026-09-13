from __future__ import annotations

import json

from server_engine.core.models import AppSettings, ServerType
from server_engine.infrastructure.sqlite import SQLiteDatabase


class SettingsRepository:
    SETTINGS_KEY = "app_settings"

    def __init__(self, database: SQLiteDatabase) -> None:
        self.database = database

    def load(self) -> AppSettings:
        row = self.database.fetch_one("SELECT value_json FROM settings WHERE key = ?", (self.SETTINGS_KEY,))
        if not row:
            return AppSettings()
        payload = json.loads(row["value_json"])
        defaults = AppSettings()
        return AppSettings(
            app_name=payload["app_name"],
            default_php_version=payload["default_php_version"],
            default_mysql_version=str(payload.get("default_mysql_version", defaults.default_mysql_version) or defaults.default_mysql_version),
            default_mariadb_version=str(payload.get("default_mariadb_version", defaults.default_mariadb_version) or defaults.default_mariadb_version),
            default_redis_version=str(payload.get("default_redis_version", defaults.default_redis_version) or defaults.default_redis_version),
            default_memcached_version=str(payload.get("default_memcached_version", defaults.default_memcached_version) or defaults.default_memcached_version),
            default_mailpit_version=str(payload.get("default_mailpit_version", defaults.default_mailpit_version) or defaults.default_mailpit_version),
            default_apache_version=str(payload.get("default_apache_version", defaults.default_apache_version) or defaults.default_apache_version),
            default_nginx_version=str(payload.get("default_nginx_version", defaults.default_nginx_version) or defaults.default_nginx_version),
            php_runtime_log_to_file=bool(payload.get("php_runtime_log_to_file", True)),
            php_runtime_log_to_screen=bool(payload.get("php_runtime_log_to_screen", False)),
            php_runtime_log_dir=str(payload.get("php_runtime_log_dir", "") or ""),
            default_server_type=ServerType(payload["default_server_type"]),
            active_web_server=ServerType(payload.get("active_web_server", payload.get("default_server_type", ServerType.APACHE.value))),
            active_apache_version=payload.get("active_apache_version"),
            active_nginx_version=payload.get("active_nginx_version"),
            apache_port=int(payload.get("apache_port", 8080)),
            apache_enabled_modules=payload.get("apache_enabled_modules", []),
            apache_error_log_path=str(payload.get("apache_error_log_path", "") or ""),
            preferred_database_engine=payload["preferred_database_engine"],
            active_database_version=payload.get("active_database_version"),
            database_port=int(payload.get("database_port", 3306)),
            database_root_password=payload.get("database_root_password", ""),
            database_runtime_passwords=payload.get("database_runtime_passwords", {}),
            database_optimization=payload.get("database_optimization", {}),
            active_redis_version=payload.get("active_redis_version"),
            cache_driver=str(payload.get("cache_driver", "redis") or "redis"),
            active_memcached_version=payload.get("active_memcached_version"),
            active_mailpit_version=payload.get("active_mailpit_version"),
            active_mongodb_version=payload.get("active_mongodb_version"),
            active_postgresql_version=payload.get("active_postgresql_version"),
            redis_port=int(payload.get("redis_port", 6379)),
            redis_password=payload.get("redis_password", ""),
            redis_runtime_passwords=payload.get("redis_runtime_passwords", {}),
            mailpit_smtp_port=int(payload.get("mailpit_smtp_port", 1025)),
            mailpit_http_port=int(payload.get("mailpit_http_port", 8025)),
            appearance_theme=str(payload.get("appearance_theme", "system") or "system"),
            appearance_accent_color=str(payload.get("appearance_accent_color", "#007bff") or "#007bff"),
            appearance_language=str(payload.get("appearance_language", "en") or "en"),
            home_global_services=payload.get("home_global_services", {
                "web": True,
                "database": True,
                "redis": True,
                "mailpit": True,
            }),
            bottom_terminal_panel_height=int(payload.get("bottom_terminal_panel_height") or defaults.bottom_terminal_panel_height),
            nginx_worker_processes=str(payload.get("nginx_worker_processes", "1") or "1"),
            nginx_worker_connections=int(payload.get("nginx_worker_connections", 1024)),
            nginx_keepalive_timeout=int(payload.get("nginx_keepalive_timeout", 65)),
            nginx_client_max_body_size=str(payload.get("nginx_client_max_body_size", "64m") or "64m"),
            nginx_sendfile=bool(payload.get("nginx_sendfile", True)),
            nginx_gzip=bool(payload.get("nginx_gzip", True)),
            nginx_server_tokens=bool(payload.get("nginx_server_tokens", False)),
            nginx_error_log_path=str(payload.get("nginx_error_log_path", "") or ""),
            active_node_version=payload.get("active_node_version"),
            active_phpmyadmin_version=payload.get("active_phpmyadmin_version", "5.2.3"),
            phpmyadmin_php_version=payload.get("phpmyadmin_php_version", defaults.phpmyadmin_php_version),
            phpmyadmin_hosts_registered=bool(payload.get("phpmyadmin_hosts_registered", False)),
            auto_start_stack=bool(payload.get("auto_start_stack", False)),
            auto_update_hosts=bool(payload.get("auto_update_hosts", True)),
            environment_root=payload.get("environment_root"),
            enable_simulated_processes=bool(payload.get("enable_simulated_processes", True)),
            default_project_folder=str(payload.get("default_project_folder", "~/ServerEngine") or "~/ServerEngine"),
        )

    def save(self, settings: AppSettings) -> AppSettings:
        self.database.execute(
            """
            INSERT INTO settings (key, value_json)
            VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value_json = excluded.value_json
            """,
            (self.SETTINGS_KEY, json.dumps(settings.to_dict())),
        )
        return settings
