from __future__ import annotations

from server_engine.core.models import NodeProject, NodeProjectStatus
from server_engine.infrastructure.sqlite import SQLiteDatabase


class NodeProjectRepository:
    def __init__(self, database: SQLiteDatabase) -> None:
        self.database = database

    def list_all(self) -> list[NodeProject]:
        rows = self.database.fetch_all("SELECT * FROM node_projects ORDER BY name COLLATE NOCASE")
        return [self._row_to_project(row) for row in rows]

    def get(self, project_id: str) -> NodeProject | None:
        row = self.database.fetch_one("SELECT * FROM node_projects WHERE id = ?", (project_id,))
        return self._row_to_project(row) if row else None

    def get_by_domain(self, local_domain: str) -> NodeProject | None:
        row = self.database.fetch_one(
            "SELECT * FROM node_projects WHERE LOWER(local_domain) = ?",
            (local_domain.strip().lower(),),
        )
        return self._row_to_project(row) if row else None

    def save(self, project: NodeProject) -> NodeProject:
        self.database.execute(
            """
            INSERT INTO node_projects (
                id, name, local_domain, project_path, document_root, node_version,
                run_script_name, run_script_command, port, notes, ssl_enabled,
                ssl_enforce_tls, ssl_allow_http,
                created_at, updated_at, status
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                local_domain = excluded.local_domain,
                project_path = excluded.project_path,
                document_root = excluded.document_root,
                node_version = excluded.node_version,
                run_script_name = excluded.run_script_name,
                run_script_command = excluded.run_script_command,
                port = excluded.port,
                notes = excluded.notes,
                ssl_enabled = excluded.ssl_enabled,
                ssl_enforce_tls = excluded.ssl_enforce_tls,
                ssl_allow_http = excluded.ssl_allow_http,
                updated_at = excluded.updated_at,
                status = excluded.status
            """,
            (
                project.id,
                project.name,
                project.local_domain,
                project.project_path,
                project.document_root,
                project.node_version,
                project.run_script_name,
                project.run_script_command,
                int(project.port),
                project.notes,
                int(project.ssl_enabled),
                int(project.ssl_enforce_tls),
                int(project.ssl_allow_http),
                project.created_at,
                project.updated_at,
                project.status.value,
            ),
        )
        return project

    def delete(self, project_id: str) -> bool:
        existing = self.get(project_id)
        if existing is None:
            return False
        self.database.execute("DELETE FROM node_projects WHERE id = ?", (project_id,))
        return True

    def _row_to_project(self, row: object) -> NodeProject:
        return NodeProject(
            id=row["id"],
            name=row["name"],
            local_domain=row["local_domain"],
            project_path=row["project_path"],
            document_root=row["document_root"],
            node_version=row["node_version"],
            run_script_name=row["run_script_name"],
            run_script_command=row["run_script_command"],
            port=int(row["port"]),
            notes=row["notes"],
            ssl_enabled=bool(row["ssl_enabled"]),
            ssl_enforce_tls=bool(row["ssl_enforce_tls"]) if "ssl_enforce_tls" in row.keys() else False,
            ssl_allow_http=bool(row["ssl_allow_http"]) if "ssl_allow_http" in row.keys() else True,
            created_at=row["created_at"],
            updated_at=row["updated_at"],
            status=NodeProjectStatus(row["status"]),
        )
