from __future__ import annotations

import logging
import os
import re
import shutil
import socket
import subprocess
import time
from pathlib import Path

from server_engine.core.models import DatabaseRuntime, OperationResult, RuntimePaths, ServiceDefinition, ServiceKind, ServiceState, ServiceStatus
from server_engine.infrastructure.process_manager import ProcessManager
from server_engine.services.database_runtime_service import DatabaseRuntimeService
from server_engine.services.settings_service import SettingsService


LOGGER = logging.getLogger("server_engine.mongodb")


class MongodbService:
    def __init__(
        self,
        runtime_paths: RuntimePaths,
        settings_service: SettingsService,
        runtime_service: DatabaseRuntimeService,
        process_manager: ProcessManager,
    ) -> None:
        self.runtime_paths = runtime_paths
        self.settings_service = settings_service
        self.runtime_service = runtime_service
        self.process_manager = process_manager
        self.port = 27017

    def active_runtime(self) -> DatabaseRuntime | None:
        settings = self.settings_service.get_settings()
        runtime = self.runtime_service.resolve(runtime_id=settings.active_mongodb_version)
        if runtime is not None and runtime.engine == "mongodb":
            return runtime
        return self.runtime_service.resolve(preferred_engine="mongodb")

    def _runtime_key(self, runtime: DatabaseRuntime | None = None) -> str:
        active = runtime or self.active_runtime()
        return active.id if active else "mongodb"

    def _runtime_log_key(self, runtime: DatabaseRuntime | None = None) -> str:
        active = runtime or self.active_runtime()
        if active is None:
            return "mongodb"
        return active.version.strip() or active.id

    def config_path(self, runtime: DatabaseRuntime | None = None) -> Path:
        path = self.runtime_paths.config_dir / "mongodb" / f"{self._runtime_key(runtime)}.conf"
        path.parent.mkdir(parents=True, exist_ok=True)
        return path

    def data_dir(self, runtime: DatabaseRuntime | None = None, create: bool = True) -> Path:
        path = self.runtime_paths.data_dir / "mongodb" / self._runtime_key(runtime)
        if create:
            path.mkdir(parents=True, exist_ok=True)
        return path

    def log_path(self, runtime: DatabaseRuntime | None = None) -> Path:
        path = self.runtime_paths.logs_dir / "mongodb" / self._runtime_log_key(runtime) / "mongodb.log"
        path.parent.mkdir(parents=True, exist_ok=True)
        return path

    def backup_root(self, runtime: DatabaseRuntime | None = None) -> Path:
        path = self.runtime_paths.backups_dir / "mongodb" / self._runtime_key(runtime)
        path.mkdir(parents=True, exist_ok=True)
        return path

    def _clear_quarantine_tree(self, path: Path) -> None:
        if os.uname().sysname != "Darwin":
            return
        subprocess.run(["xattr", "-dr", "com.apple.quarantine", str(path)], capture_output=True, text=True, check=False)

    def _runtime_binary(self, runtime: DatabaseRuntime, name: str) -> Path:
        return Path(runtime.home) / "bin" / name

    def _has_runtime_binary(self, runtime: DatabaseRuntime, name: str) -> bool:
        return self._runtime_binary(runtime, name).is_file() and os.access(self._runtime_binary(runtime, name), os.X_OK)

    def _run_tool(self, args: list[str], cwd: Path | None = None, timeout: int = 300) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            args,
            cwd=str(cwd) if cwd else None,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )

    def generate_config(self) -> str:
        runtime = self.active_runtime()
        data_dir = self.data_dir(runtime)
        log_path = self.log_path(runtime)
        config = (
            "systemLog:\n"
            "  destination: file\n"
            f"  path: {log_path}\n"
            "  logAppend: true\n"
            "storage:\n"
            f"  dbPath: {data_dir}\n"
            "net:\n"
            "  bindIp: 127.0.0.1\n"
            f"  port: {self.port}\n"
        )
        path = self.config_path(runtime)
        path.write_text(config, encoding="utf-8")
        return str(path)

    def service_definition(self, write_config: bool = True) -> ServiceDefinition | None:
        runtime = self.active_runtime()
        if runtime is None:
            return None
        self._clear_quarantine_tree(Path(runtime.home))
        config_path = self.generate_config() if write_config else str(self.config_path(runtime))
        return ServiceDefinition(
            id="mongodb",
            name="MongoDB",
            kind=ServiceKind.DATABASE,
            executable_name=Path(runtime.server_path).name,
            default_port=self.port,
            executable_path=runtime.server_path,
            arguments=["--config", config_path],
            working_directory=str(self.runtime_paths.runtime_dir),
            log_path=str(self.log_path(runtime)),
        )

    def status(self) -> ServiceStatus:
        definition = self.service_definition(write_config=False)
        if definition is None:
            return ServiceStatus(service_id="mongodb", state=ServiceState.STOPPED, port=self.port, message="No MongoDB runtime installed.")
        status = self.process_manager.status(definition)
        if status.port:
            self.port = status.port
        return status

    def start_runtime(self) -> OperationResult:
        current = self.status()
        if current.state == ServiceState.RUNNING:
            self.port = current.port or self.port
            LOGGER.info("MongoDB start skipped; already running: %s", current.message)
            return OperationResult(True, current.message, {"state": current.to_dict()})
        if self._port_in_use(self.port):
            fallback_port = self._next_available_port(self.port + 1)
            if fallback_port is None:
                LOGGER.error("MongoDB cannot start because ports %s-27027 are already in use.", self.port)
                return OperationResult(False, f"MongoDB cannot start because ports {self.port}-27027 are already in use.", {"port": self.port})
            self.port = fallback_port
        definition = self.service_definition(write_config=True)
        if definition is None:
            LOGGER.error("MongoDB start failed: no runtime installed.")
            return OperationResult(False, "No MongoDB runtime installed.")
        status = self.process_manager.start(definition)
        if status.port:
            self.port = status.port
        if status.state == ServiceState.ERROR:
            LOGGER.error("MongoDB start failed: %s", status.message)
        else:
            LOGGER.info("MongoDB start completed: %s", status.message)
        return OperationResult(status.state != ServiceState.ERROR, status.message, {"state": status.to_dict()})

    def stop_runtime(self) -> OperationResult:
        status = self.process_manager.stop("mongodb")
        if status.state != ServiceState.ERROR:
            LOGGER.info("MongoDB stop completed: %s", status.message)
            return OperationResult(True, status.message, {"state": status.to_dict()})
        for _ in range(8):
            current = self.status()
            if current.state == ServiceState.STOPPED:
                LOGGER.info("MongoDB stop completed after status refresh: %s", current.message)
                return OperationResult(True, "MongoDB stopped.", {"state": current.to_dict()})
            time.sleep(0.1)
        LOGGER.error("MongoDB stop failed: %s", status.message)
        return OperationResult(False, status.message, {"state": status.to_dict()})

    def restart_runtime(self) -> OperationResult:
        self.process_manager.stop("mongodb")
        result = self.start_runtime()
        if result.success:
            LOGGER.info("MongoDB restart completed: %s", result.message)
        else:
            LOGGER.error("MongoDB restart failed: %s", result.message)
        return result

    def _port_in_use(self, port: int) -> bool:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.1)
            return sock.connect_ex(("127.0.0.1", port)) == 0

    def _next_available_port(self, start: int) -> int | None:
        for port in range(start, 27028):
            if not self._port_in_use(port):
                return port
        return None

    def read_log_tail(self, lines: int = 120) -> str:
        path = self.log_path()
        if not path.exists():
            return ""
        return "\n".join(path.read_text(encoding="utf-8", errors="replace").splitlines()[-lines:])

    def _client_unavailable(self) -> OperationResult:
        return OperationResult(False, "MongoDB client backend is not available because pymongo is not installed.")

    def _client(self):
        status = self.status()
        if status.state == ServiceState.RUNNING and status.port:
            self.port = status.port
        try:
            from pymongo import MongoClient

            return MongoClient(f"mongodb://127.0.0.1:{self.port}", serverSelectionTimeoutMS=2500)
        except Exception:
            return None

    def list_databases(self) -> OperationResult:
        runtime = self.active_runtime()
        if runtime is None:
            return OperationResult(False, "No MongoDB runtime installed.")
        client = self._client()
        if client is None:
            return self._client_unavailable()
        try:
            names = [name for name in client.list_database_names() if name not in {"admin", "config", "local"}]
            return OperationResult(True, "Loaded MongoDB databases.", {"databases": [{"name": name} for name in names], "runtime": runtime.to_dict(), "port": self.port})
        except Exception as exc:
            return OperationResult(False, f"Could not query MongoDB databases: {exc}")
        finally:
            client.close()

    def list_backups(self, database_name: str) -> OperationResult:
        runtime = self.active_runtime()
        if runtime is None:
            return OperationResult(False, "No MongoDB runtime installed.")
        cleaned = database_name.strip()
        root = self.backup_root(runtime) / cleaned
        if not root.exists():
            return OperationResult(True, "No MongoDB backups found.", {"items": []})
        items = []
        for path in sorted(root.iterdir(), key=lambda candidate: candidate.stat().st_mtime, reverse=True):
            if not path.is_file():
                continue
            stat = path.stat()
            items.append(
                {
                    "name": path.name,
                    "path": str(path),
                    "size": stat.st_size,
                    "modified": int(stat.st_mtime),
                }
            )
        return OperationResult(True, "Loaded MongoDB backups.", {"items": items})

    def create_database(self, name: str) -> OperationResult:
        cleaned = name.strip()
        if not re.match(r"^[A-Za-z_][A-Za-z0-9_-]*$", cleaned):
            return OperationResult(False, "Database name must start with a letter or underscore and use only letters, numbers, underscores, and hyphens.")
        client = self._client()
        if client is None:
            return self._client_unavailable()
        try:
            client[cleaned]["server_engine_init"].insert_one({"createdBy": "Server Engine"})
            return OperationResult(True, f"Created MongoDB database: {cleaned}", {"database": cleaned})
        except Exception as exc:
            return OperationResult(False, f"Create MongoDB database failed: {exc}")
        finally:
            client.close()

    def drop_database(self, name: str) -> OperationResult:
        cleaned = name.strip()
        if cleaned in {"admin", "config", "local"}:
            return OperationResult(False, f"Refusing to drop protected MongoDB database: {cleaned}")
        client = self._client()
        if client is None:
            return self._client_unavailable()
        try:
            client.drop_database(cleaned)
            return OperationResult(True, f"Dropped MongoDB database: {cleaned}", {"database": cleaned})
        except Exception as exc:
            return OperationResult(False, f"Drop MongoDB database failed: {exc}")
        finally:
            client.close()

    def create_backup(self, database_name: str) -> OperationResult:
        runtime = self.active_runtime()
        if runtime is None:
            return OperationResult(False, "No MongoDB runtime installed.")
        cleaned = database_name.strip()
        if not cleaned:
            return OperationResult(False, "Database name is required.")
        if cleaned in {"admin", "config", "local"}:
            return OperationResult(False, f"Refusing to back up protected MongoDB database: {cleaned}")
        if not self._has_runtime_binary(runtime, "mongodump"):
            return OperationResult(False, "MongoDB backup requires mongodump, which is not included in this runtime.")
        status = self.status()
        if status.state == ServiceState.RUNNING and status.port:
            self.port = status.port
        timestamp = time.strftime("%Y%m%d-%H%M%S")
        root = self.backup_root(runtime) / cleaned
        root.mkdir(parents=True, exist_ok=True)
        archive = root / f"{cleaned}-{timestamp}.archive.gz"
        binary = self._runtime_binary(runtime, "mongodump")
        result = self._run_tool(
            [
                str(binary),
                "--host",
                "127.0.0.1",
                "--port",
                str(self.port),
                "--db",
                cleaned,
                "--archive=" + str(archive),
                "--gzip",
            ],
            timeout=600,
        )
        if result.returncode != 0:
            message = result.stderr.strip() or result.stdout.strip() or "mongodump failed."
            return OperationResult(False, f"MongoDB backup failed: {message}")
        stat = archive.stat()
        return OperationResult(
            True,
            f"Created MongoDB backup: {archive.name}",
            {
                "name": archive.name,
                "path": str(archive),
                "size": stat.st_size,
                "modified": int(stat.st_mtime),
                "database": cleaned,
            },
        )

    def restore_backup(self, archive_path: str) -> OperationResult:
        runtime = self.active_runtime()
        if runtime is None:
            return OperationResult(False, "No MongoDB runtime installed.")
        if not self._has_runtime_binary(runtime, "mongorestore"):
            return OperationResult(False, "MongoDB restore requires mongorestore, which is not included in this runtime.")
        target = Path(archive_path.strip())
        try:
            backup_root = self.backup_root(runtime).resolve()
            target_resolved = target.resolve()
            if backup_root not in target_resolved.parents:
                return OperationResult(False, "Backup path is outside managed MongoDB backup folder.")
            if not target_resolved.is_file():
                return OperationResult(False, "Backup file not found.")
        except Exception as exc:
            return OperationResult(False, f"Invalid backup path: {exc}")
        status = self.status()
        if status.state == ServiceState.RUNNING and status.port:
            self.port = status.port
        binary = self._runtime_binary(runtime, "mongorestore")
        result = self._run_tool(
            [
                str(binary),
                "--host",
                "127.0.0.1",
                "--port",
                str(self.port),
                "--archive=" + str(target_resolved),
                "--gzip",
                "--drop",
            ],
            timeout=600,
        )
        if result.returncode != 0:
            message = result.stderr.strip() or result.stdout.strip() or "mongorestore failed."
            return OperationResult(False, f"MongoDB restore failed: {message}")
        return OperationResult(True, f"Restored MongoDB backup: {target_resolved.name}", {"path": str(target_resolved)})

    def delete_backup(self, archive_path: str) -> OperationResult:
        runtime = self.active_runtime()
        if runtime is None:
            return OperationResult(False, "No MongoDB runtime installed.")
        target = Path(archive_path.strip())
        try:
            backup_root = self.backup_root(runtime).resolve()
            target_resolved = target.resolve()
            if backup_root not in target_resolved.parents:
                return OperationResult(False, "Backup path is outside managed MongoDB backup folder.")
            target_resolved.unlink()
            return OperationResult(True, f"Deleted backup: {target.name}")
        except Exception as exc:
            return OperationResult(False, f"Delete MongoDB backup failed: {exc}")

    def import_dump(self, database_name: str, import_path: str) -> OperationResult:
        runtime = self.active_runtime()
        if runtime is None:
            return OperationResult(False, "No MongoDB runtime installed.")
        cleaned = database_name.strip()
        if not cleaned:
            return OperationResult(False, "Database name is required.")
        target = Path(import_path.strip())
        if not target.is_file():
            return OperationResult(False, "Import file not found.")
        status = self.status()
        if status.state == ServiceState.RUNNING and status.port:
            self.port = status.port
        suffix = target.suffix.lower()
        if suffix in {".json", ".csv", ".tsv"}:
            if not self._has_runtime_binary(runtime, "mongoimport"):
                return OperationResult(False, "MongoDB import requires mongoimport, which is not included in this runtime.")
            binary = self._runtime_binary(runtime, "mongoimport")
            collection = target.stem
            args = [
                str(binary),
                "--host",
                "127.0.0.1",
                "--port",
                str(self.port),
                "--db",
                cleaned,
                "--collection",
                collection,
                "--file",
                str(target),
            ]
            if suffix == ".json":
                args.append("--jsonArray")
            elif suffix == ".csv":
                args.extend(["--type", "csv", "--headerline"])
            elif suffix == ".tsv":
                args.extend(["--type", "tsv", "--headerline"])
            result = self._run_tool(args, timeout=600)
            if result.returncode != 0:
                message = result.stderr.strip() or result.stdout.strip() or "mongoimport failed."
                return OperationResult(False, f"MongoDB import failed: {message}")
            return OperationResult(True, f"Imported MongoDB data into {cleaned}.{collection}", {"database": cleaned, "collection": collection, "path": str(target)})
        if suffix == ".gz" or target.name.endswith(".archive") or target.name.endswith(".archive.gz"):
            if not self._has_runtime_binary(runtime, "mongorestore"):
                return OperationResult(False, "MongoDB restore requires mongorestore, which is not included in this runtime.")
            binary = self._runtime_binary(runtime, "mongorestore")
            args = [
                str(binary),
                "--host",
                "127.0.0.1",
                "--port",
                str(self.port),
                "--archive=" + str(target),
            ]
            if target.name.endswith(".gz"):
                args.append("--gzip")
            result = self._run_tool(args, timeout=600)
            if result.returncode != 0:
                message = result.stderr.strip() or result.stdout.strip() or "mongorestore failed."
                return OperationResult(False, f"MongoDB restore import failed: {message}")
            return OperationResult(True, f"Imported MongoDB archive: {target.name}", {"database": cleaned, "path": str(target)})
        return OperationResult(False, "Unsupported MongoDB import file. Use .json, .csv, .tsv, .archive, or .archive.gz.")
