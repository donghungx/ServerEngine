from __future__ import annotations

from server_engine.core.models import Proxy
from server_engine.infrastructure.sqlite import SQLiteDatabase


class ProxyRepository:
    def __init__(self, database: SQLiteDatabase) -> None:
        self.database = database

    def list_all(self) -> list[Proxy]:
        rows = self.database.fetch_all("SELECT * FROM proxies ORDER BY name COLLATE NOCASE")
        return [self._row_to_proxy(row) for row in rows]

    def get(self, proxy_id: str) -> Proxy | None:
        row = self.database.fetch_one("SELECT * FROM proxies WHERE id = ?", (proxy_id,))
        return self._row_to_proxy(row) if row else None

    def get_by_domain(self, domain: str) -> Proxy | None:
        row = self.database.fetch_one("SELECT * FROM proxies WHERE LOWER(local_domain) = ?", (domain.strip().lower(),))
        return self._row_to_proxy(row) if row else None

    def save(self, proxy: Proxy) -> Proxy:
        self.database.execute(
            """INSERT INTO proxies (id, name, local_domain, target, notes, ssl_enabled, ssl_enforce_tls, ssl_allow_http, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET name=excluded.name, local_domain=excluded.local_domain,
            target=excluded.target, notes=excluded.notes, ssl_enabled=excluded.ssl_enabled,
            ssl_enforce_tls=excluded.ssl_enforce_tls, ssl_allow_http=excluded.ssl_allow_http, updated_at=excluded.updated_at""",
            (proxy.id, proxy.name, proxy.local_domain, proxy.target, proxy.notes, int(proxy.ssl_enabled), int(proxy.ssl_enforce_tls), int(proxy.ssl_allow_http), proxy.created_at, proxy.updated_at),
        )
        return proxy

    def delete(self, proxy_id: str) -> bool:
        if self.get(proxy_id) is None:
            return False
        self.database.execute("DELETE FROM proxies WHERE id = ?", (proxy_id,))
        return True

    @staticmethod
    def _row_to_proxy(row: object) -> Proxy:
        return Proxy(id=row["id"], name=row["name"], local_domain=row["local_domain"], target=row["target"], notes=row["notes"], ssl_enabled=bool(row["ssl_enabled"]), ssl_enforce_tls=bool(row["ssl_enforce_tls"]), ssl_allow_http=bool(row["ssl_allow_http"]), created_at=row["created_at"], updated_at=row["updated_at"])
