from __future__ import annotations

import sqlite3
from pathlib import Path
from typing import Any


class SQLiteDatabase:
    def __init__(self, path: Path) -> None:
        self.path = path

    def connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.path)
        connection.row_factory = sqlite3.Row
        return connection

    def initialize(self) -> None:
        with self.connect() as connection:
            connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS sites (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    local_domain TEXT NOT NULL UNIQUE,
                    project_path TEXT NOT NULL,
                    web_root TEXT NOT NULL,
                    domain_aliases_json TEXT NOT NULL DEFAULT '[]',
                    php_version TEXT NOT NULL,
                    framework_preset TEXT NOT NULL,
                    server_type TEXT NOT NULL,
                    ssl_enabled INTEGER NOT NULL,
                    ssl_enforce_tls INTEGER NOT NULL DEFAULT 0,
                    ssl_allow_http INTEGER NOT NULL DEFAULT 1,
                    database_enabled INTEGER NOT NULL,
                    database_name TEXT,
                    database_user TEXT,
                    notes TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    status TEXT NOT NULL,
                    tags_json TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS settings (
                    key TEXT PRIMARY KEY,
                    value_json TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS node_projects (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    local_domain TEXT NOT NULL UNIQUE,
                    project_path TEXT NOT NULL,
                    document_root TEXT NOT NULL,
                    node_version TEXT NOT NULL,
                    run_script_name TEXT NOT NULL,
                    run_script_command TEXT NOT NULL,
                    port INTEGER NOT NULL,
                    notes TEXT NOT NULL,
                    ssl_enabled INTEGER NOT NULL,
                    ssl_enforce_tls INTEGER NOT NULL DEFAULT 0,
                    ssl_allow_http INTEGER NOT NULL DEFAULT 1,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    status TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS proxies (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    local_domain TEXT NOT NULL UNIQUE,
                    target TEXT NOT NULL,
                    notes TEXT NOT NULL,
                    ssl_enabled INTEGER NOT NULL DEFAULT 0,
                    ssl_enforce_tls INTEGER NOT NULL DEFAULT 0,
                    ssl_allow_http INTEGER NOT NULL DEFAULT 1,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                    
                CREATE TABLE IF NOT EXISTS app_cache (
                    key TEXT PRIMARY KEY,
                    value_json TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                """
            )
            columns = {row["name"] for row in connection.execute("PRAGMA table_info(sites)").fetchall()}
            if "domain_aliases_json" not in columns:
                connection.execute("ALTER TABLE sites ADD COLUMN domain_aliases_json TEXT NOT NULL DEFAULT '[]'")
            if "ssl_enforce_tls" not in columns:
                connection.execute("ALTER TABLE sites ADD COLUMN ssl_enforce_tls INTEGER NOT NULL DEFAULT 0")
            if "ssl_allow_http" not in columns:
                connection.execute("ALTER TABLE sites ADD COLUMN ssl_allow_http INTEGER NOT NULL DEFAULT 1")
            node_columns = {row["name"] for row in connection.execute("PRAGMA table_info(node_projects)").fetchall()}
            if "ssl_enforce_tls" not in node_columns:
                connection.execute("ALTER TABLE node_projects ADD COLUMN ssl_enforce_tls INTEGER NOT NULL DEFAULT 0")
            if "ssl_allow_http" not in node_columns:
                connection.execute("ALTER TABLE node_projects ADD COLUMN ssl_allow_http INTEGER NOT NULL DEFAULT 1")
            proxy_columns = {row["name"] for row in connection.execute("PRAGMA table_info(proxies)").fetchall()}
            if "ssl_enabled" not in proxy_columns:
                connection.execute("ALTER TABLE proxies ADD COLUMN ssl_enabled INTEGER NOT NULL DEFAULT 0")
            if "ssl_enforce_tls" not in proxy_columns:
                connection.execute("ALTER TABLE proxies ADD COLUMN ssl_enforce_tls INTEGER NOT NULL DEFAULT 0")
            if "ssl_allow_http" not in proxy_columns:
                connection.execute("ALTER TABLE proxies ADD COLUMN ssl_allow_http INTEGER NOT NULL DEFAULT 1")
            connection.execute(
                """
                UPDATE sites
                SET
                    domain_aliases_json = '[]',
                    php_version = framework_preset,
                    framework_preset = domain_aliases_json
                WHERE domain_aliases_json IN ('generic_php', 'laravel', 'wordpress', 'custom', 'symfony', 'codeigniter')
                  AND framework_preset NOT IN ('generic_php', 'laravel', 'wordpress', 'custom', 'symfony', 'codeigniter')
                """
            )
            connection.execute(
                """
                UPDATE sites
                SET domain_aliases_json = '[]'
                WHERE TRIM(COALESCE(domain_aliases_json, '')) = ''
                """
            )
            connection.commit()

    def fetch_all(self, query: str, params: tuple[Any, ...] = ()) -> list[sqlite3.Row]:
        with self.connect() as connection:
            return list(connection.execute(query, params).fetchall())

    def fetch_one(self, query: str, params: tuple[Any, ...] = ()) -> sqlite3.Row | None:
        with self.connect() as connection:
            return connection.execute(query, params).fetchone()

    def execute(self, query: str, params: tuple[Any, ...] = ()) -> None:
        with self.connect() as connection:
            connection.execute(query, params)
            connection.commit()
