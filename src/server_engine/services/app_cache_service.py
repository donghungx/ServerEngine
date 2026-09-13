from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any

from server_engine.infrastructure.sqlite import SQLiteDatabase


class AppCacheService:
    def __init__(self, database: SQLiteDatabase) -> None:
        self.database = database

    def get_json(self, key: str, default: Any = None) -> Any:
        row = self.database.fetch_one(
            "SELECT value_json FROM app_cache WHERE key = ?",
            (key,),
        )
        if row is None:
            return default
        try:
            return json.loads(str(row["value_json"]))
        except Exception:
            return default

    def set_json(self, key: str, value: Any) -> None:
        self.database.execute(
            """
            INSERT INTO app_cache (key, value_json, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET
                value_json = excluded.value_json,
                updated_at = excluded.updated_at
            """,
            (key, json.dumps(value), datetime.now(timezone.utc).isoformat()),
        )

    def delete(self, key: str) -> None:
        self.database.execute("DELETE FROM app_cache WHERE key = ?", (key,))

    def has_key(self, key: str) -> bool:
        row = self.database.fetch_one(
            "SELECT 1 FROM app_cache WHERE key = ?",
            (key,),
        )
        return row is not None

    def clear(self) -> None:
        self.database.execute("DELETE FROM app_cache")

    def get_runtime_inventory(self, kind: str) -> list[dict[str, Any]]:
        value = self.get_json(f"runtime_inventory.{kind}", [])
        return value if isinstance(value, list) else []

    def has_runtime_inventory(self, kind: str) -> bool:
        return self.has_key(f"runtime_inventory.{kind}")

    def set_runtime_inventory(self, kind: str, items: list[dict[str, Any]]) -> None:
        self.set_json(f"runtime_inventory.{kind}", items)

    def clear_runtime_inventory(self, kind: str) -> None:
        self.delete(f"runtime_inventory.{kind}")
