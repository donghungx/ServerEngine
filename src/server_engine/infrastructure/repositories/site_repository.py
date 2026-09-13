from __future__ import annotations

import json

from server_engine.core.models import FrameworkPreset, ServerType, Site, SiteStatus
from server_engine.infrastructure.sqlite import SQLiteDatabase


class SiteRepository:
    def __init__(self, database: SQLiteDatabase) -> None:
        self.database = database

    def list_all(self) -> list[Site]:
        rows = self.database.fetch_all("SELECT * FROM sites ORDER BY name COLLATE NOCASE")
        return [self._row_to_site(row) for row in rows]

    def get(self, site_id: str) -> Site | None:
        row = self.database.fetch_one("SELECT * FROM sites WHERE id = ?", (site_id,))
        return self._row_to_site(row) if row else None

    def get_by_domain(self, local_domain: str) -> Site | None:
        target = local_domain.strip().lower()
        for site in self.list_all():
            if target in site.all_domains():
                return site
        return None

    def save(self, site: Site) -> Site:
        self.database.execute(
            """
            INSERT INTO sites (
                id, name, local_domain, project_path, web_root, php_version, framework_preset,
                domain_aliases_json, server_type, ssl_enabled, ssl_enforce_tls, ssl_allow_http, database_enabled, database_name, database_user,
                notes, created_at, updated_at, status, tags_json
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                local_domain = excluded.local_domain,
                project_path = excluded.project_path,
                web_root = excluded.web_root,
                domain_aliases_json = excluded.domain_aliases_json,
                php_version = excluded.php_version,
                framework_preset = excluded.framework_preset,
                server_type = excluded.server_type,
                ssl_enabled = excluded.ssl_enabled,
                ssl_enforce_tls = excluded.ssl_enforce_tls,
                ssl_allow_http = excluded.ssl_allow_http,
                database_enabled = excluded.database_enabled,
                database_name = excluded.database_name,
                database_user = excluded.database_user,
                notes = excluded.notes,
                updated_at = excluded.updated_at,
                status = excluded.status,
                tags_json = excluded.tags_json
            """,
            (
                site.id,
                site.name,
                site.local_domain,
                site.project_path,
                site.web_root,
                site.php_version,
                site.framework_preset.value,
                json.dumps(site.domain_aliases),
                site.server_type.value,
                int(site.ssl_enabled),
                int(site.ssl_enforce_tls),
                int(site.ssl_allow_http),
                int(site.database_enabled),
                site.database_name,
                site.database_user,
                site.notes,
                site.created_at,
                site.updated_at,
                site.status.value,
                json.dumps(site.tags),
            ),
        )
        return site

    def delete(self, site_id: str) -> bool:
        existing = self.get(site_id)
        if not existing:
            return False
        self.database.execute("DELETE FROM sites WHERE id = ?", (site_id,))
        return True

    def _row_to_site(self, row: object) -> Site:
        raw_aliases = row["domain_aliases_json"]
        raw_php_version = row["php_version"]
        raw_framework = row["framework_preset"]
        framework_values = {item.value for item in FrameworkPreset}

        # Compatibility repair for rows saved during the domain-alias schema
        # transition where domain_aliases_json/php_version/framework_preset were
        # written in the wrong order.
        if str(raw_framework) not in framework_values and str(raw_aliases) in framework_values:
            raw_aliases, raw_php_version, raw_framework = "[]", raw_framework, raw_aliases

        try:
            parsed_aliases = json.loads(raw_aliases) if raw_aliases else []
        except (TypeError, json.JSONDecodeError):
            parsed_aliases = []
        if not isinstance(parsed_aliases, list):
            parsed_aliases = []
        return Site(
            id=row["id"],
            name=row["name"],
            local_domain=row["local_domain"],
            project_path=row["project_path"],
            web_root=row["web_root"],
            domain_aliases=parsed_aliases,
            php_version=raw_php_version,
            framework_preset=FrameworkPreset(raw_framework),
            server_type=ServerType(row["server_type"]),
            ssl_enabled=bool(row["ssl_enabled"]),
            ssl_enforce_tls=bool(row["ssl_enforce_tls"]) if "ssl_enforce_tls" in row.keys() else False,
            ssl_allow_http=bool(row["ssl_allow_http"]) if "ssl_allow_http" in row.keys() else True,
            database_enabled=bool(row["database_enabled"]),
            database_name=row["database_name"],
            database_user=row["database_user"],
            notes=row["notes"],
            created_at=row["created_at"],
            updated_at=row["updated_at"],
            status=SiteStatus(row["status"]),
            tags=json.loads(row["tags_json"]),
        )
