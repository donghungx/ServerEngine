from __future__ import annotations

import logging
import gzip
import json
import os
import re
import shutil
import socket
import subprocess
import tarfile
import tempfile
import time
import zipfile
from pathlib import Path

from server_engine.core.models import DatabaseRuntime, OperationResult, RuntimePaths, ServiceDefinition, ServiceKind, ServiceState, ServiceStatus
from server_engine.infrastructure.process_manager import ProcessManager
from server_engine.services.database_runtime_service import DatabaseRuntimeService
from server_engine.services.settings_service import SettingsService


LOGGER = logging.getLogger("server_engine.postgresql")


class PostgresqlService:
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
        self.port = 5432

    def active_runtime(self) -> DatabaseRuntime | None:
        settings = self.settings_service.get_settings()
        runtime = self.runtime_service.resolve(runtime_id=settings.active_postgresql_version)
        if runtime is not None and runtime.engine == "postgresql":
            return runtime
        return self.runtime_service.resolve(preferred_engine="postgresql")

    def _runtime_key(self, runtime: DatabaseRuntime | None = None) -> str:
        active = runtime or self.active_runtime()
        return active.id if active else "postgresql"

    def _runtime_log_key(self, runtime: DatabaseRuntime | None = None) -> str:
        active = runtime or self.active_runtime()
        if active is None:
            return "postgresql"
        return active.version.strip() or active.id

    def config_path(self, runtime: DatabaseRuntime | None = None) -> Path:
        path = self.runtime_paths.config_dir / "postgresql" / f"{self._runtime_key(runtime)}.conf"
        path.parent.mkdir(parents=True, exist_ok=True)
        return path

    def data_dir(self, runtime: DatabaseRuntime | None = None, create: bool = True) -> Path:
        path = self.runtime_paths.data_dir / "postgresql" / self._runtime_key(runtime)
        if create:
            path.mkdir(parents=True, exist_ok=True)
        return path

    def log_path(self, runtime: DatabaseRuntime | None = None) -> Path:
        path = self.runtime_paths.logs_dir / "postgresql" / self._runtime_log_key(runtime) / "postgresql.log"
        path.parent.mkdir(parents=True, exist_ok=True)
        return path

    def backup_root(self, runtime: DatabaseRuntime | None = None) -> Path:
        path = self.runtime_paths.backups_dir / "postgresql" / self._runtime_key(runtime)
        path.mkdir(parents=True, exist_ok=True)
        return path

    def _runtime_bin(self, runtime: DatabaseRuntime, name: str) -> Path:
        return Path(runtime.home) / "bin" / name

    def _postgresql_share_dir(self, runtime: DatabaseRuntime) -> Path | None:
        share_root = Path(runtime.home) / "share"
        candidates = [
            share_root / "postgresql",
            share_root / f"postgresql@{str(runtime.version).split('.', 1)[0]}",
            share_root,
        ]
        candidates.extend(sorted(share_root.glob("postgresql*")) if share_root.exists() else [])
        return next((path for path in candidates if (path / "postgres.bki").exists()), None)

    def _process_env(self) -> dict[str, str]:
        env = os.environ.copy()
        env["LANG"] = "C"
        env["LC_ALL"] = "C"
        env["TZ"] = "UTC"
        return env

    def _clear_quarantine_tree(self, path: Path) -> None:
        if os.uname().sysname != "Darwin":
            return
        subprocess.run(["xattr", "-dr", "com.apple.quarantine", str(path)], capture_output=True, text=True, check=False)

    def _repair_runtime_libraries(self, runtime: DatabaseRuntime) -> None:
        runtime_lib = Path(runtime.home) / "lib"
        missing_icu_data = runtime_lib / "libicudata.78.dylib"
        if missing_icu_data.exists():
            return
        candidates = [
            Path("/opt/homebrew/Cellar/icu4c@78/78.3/lib/libicudata.78.dylib"),
            Path("/usr/local/Cellar/icu4c@78/78.3/lib/libicudata.78.dylib"),
        ]
        source = next((path for path in candidates if path.exists()), None)
        if source is None:
            return
        runtime_lib.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, missing_icu_data)

    def generate_config(self) -> str:
        runtime = self.active_runtime()
        data_dir = self.data_dir(runtime)
        log_path = self.log_path(runtime)
        escaped_data_dir = str(data_dir).replace("'", "''")
        escaped_log_dir = str(log_path.parent).replace("'", "''")
        config = (
            "listen_addresses = '127.0.0.1'\n"
            f"port = {self.port}\n"
            "unix_socket_directories = '/tmp'\n"
            f"data_directory = '{escaped_data_dir}'\n"
            f"log_directory = '{escaped_log_dir}'\n"
            f"log_filename = '{log_path.name}'\n"
            "logging_collector = off\n"
            "timezone = 'UTC'\n"
            "log_timezone = 'UTC'\n"
        )
        path = self.config_path(runtime)
        path.write_text(config, encoding="utf-8")
        return str(path)

    def initialize_runtime(self) -> OperationResult:
        runtime = self.active_runtime()
        if runtime is None:
            return OperationResult(False, "No PostgreSQL runtime installed.")
        self._clear_quarantine_tree(Path(runtime.home))
        self._repair_runtime_libraries(runtime)
        data_dir = self.data_dir(runtime)
        if (data_dir / "PG_VERSION").exists():
            self._write_pg_hba(data_dir)
            return OperationResult(True, "PostgreSQL data directory already initialized.", {"initialized_now": False})
        initdb = self._runtime_bin(runtime, "initdb")
        if not initdb.exists():
            return OperationResult(False, "PostgreSQL initdb binary not found.")
        share_dir = self._postgresql_share_dir(runtime)
        if share_dir is None:
            return OperationResult(False, f"PostgreSQL share directory is missing postgres.bki under {Path(runtime.home) / 'share'}.")
        data_dir.mkdir(parents=True, exist_ok=True)
        command = [str(initdb), "-D", str(data_dir), "-L", str(share_dir), "-U", "postgres", "-A", "trust", "-E", "UTF8", "--locale=C"]
        try:
            result = subprocess.run(command, capture_output=True, text=True, check=True, env=self._process_env())
            output = "\n".join(part for part in [result.stdout.strip(), result.stderr.strip()] if part)
            if output:
                self.log_path(runtime).write_text(output + "\n", encoding="utf-8")
                LOGGER.info("PostgreSQL initdb output for %s:\n%s", runtime.id, output)
            self._write_pg_hba(data_dir)
            return OperationResult(True, "Initialized PostgreSQL data directory.", {"initialized_now": True})
        except subprocess.CalledProcessError as exc:
            details = "\n".join(part for part in [exc.stdout.strip(), exc.stderr.strip()] if part).strip()
            if details:
                LOGGER.error("PostgreSQL initdb failed for %s:\n%s", runtime.id, details)
            else:
                LOGGER.error("PostgreSQL initdb failed for %s with exit code %s", runtime.id, exc.returncode)
            return OperationResult(False, f"PostgreSQL init failed: {details or exc.returncode}")

    def _write_pg_hba(self, data_dir: Path) -> None:
        hba_path = data_dir / "pg_hba.conf"
        hba_path.write_text(
            "local all all trust\n"
            "host all all 127.0.0.1/32 trust\n"
            "host all all ::1/128 trust\n",
            encoding="utf-8",
        )

    def service_definition(self) -> ServiceDefinition | None:
        runtime = self.active_runtime()
        if runtime is None:
            return None
        data_dir = self.data_dir(runtime)
        config_path = self.generate_config()
        return ServiceDefinition(
            id="postgresql",
            name="PostgreSQL",
            kind=ServiceKind.DATABASE,
            executable_name=Path(runtime.server_path).name,
            default_port=self.port,
            executable_path=runtime.server_path,
            arguments=["-D", str(data_dir), "-c", f"config_file={config_path}"],
            working_directory=str(self.runtime_paths.runtime_dir),
            log_path=str(self.log_path(runtime)),
        )

    def status(self) -> ServiceStatus:
        definition = self.service_definition()
        if definition is None:
            return ServiceStatus(service_id="postgresql", state=ServiceState.STOPPED, port=self.port, message="No PostgreSQL runtime installed.")
        return self.process_manager.status(definition)

    def start_runtime(self) -> OperationResult:
        if self._port_in_use(self.port):
            return OperationResult(False, f"PostgreSQL cannot start because port {self.port} is already in use.", {"port": self.port})
        init_result = self.initialize_runtime()
        if not init_result.success:
            LOGGER.error("PostgreSQL start aborted during initialization: %s", init_result.message)
            return init_result
        definition = self.service_definition()
        if definition is None:
            return OperationResult(False, "No PostgreSQL runtime installed.")
        status = self.process_manager.start(definition)
        if status.state == ServiceState.ERROR or not status.message.strip():
            LOGGER.error("PostgreSQL start failed: %s", status.message)
        else:
            LOGGER.info("PostgreSQL start completed: %s", status.message)
        payload = {"state": status.to_dict(), **dict(init_result.payload or {})}
        return OperationResult(status.state != ServiceState.ERROR, status.message, payload)

    def stop_runtime(self) -> OperationResult:
        status = self.process_manager.stop("postgresql")
        if status.state != ServiceState.ERROR:
            return OperationResult(True, status.message, {"state": status.to_dict()})
        for _ in range(8):
            current = self.status()
            if current.state == ServiceState.STOPPED:
                return OperationResult(True, "PostgreSQL stopped.", {"state": current.to_dict()})
            time.sleep(0.1)
        return OperationResult(False, status.message, {"state": status.to_dict()})

    def restart_runtime(self) -> OperationResult:
        self.process_manager.stop("postgresql")
        return self.start_runtime()

    def _port_in_use(self, port: int) -> bool:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.1)
            return sock.connect_ex(("127.0.0.1", port)) == 0

    def read_log_tail(self, lines: int = 120) -> str:
        path = self.log_path()
        if not path.exists():
            return ""
        return "\n".join(path.read_text(encoding="utf-8", errors="replace").splitlines()[-lines:])

    def _psql_command(self) -> tuple[list[str], DatabaseRuntime] | None:
        runtime = self.active_runtime()
        if runtime is None:
            return None
        psql = Path(runtime.client_path) if runtime.client_path else self._runtime_bin(runtime, "psql")
        if not psql.exists():
            return None
        return [str(psql), "-h", "127.0.0.1", "-p", str(self.port), "-U", "postgres"], runtime

    def _run_psql(self, args: list[str], *, input_text: str | None = None, database: str = "postgres") -> subprocess.CompletedProcess[str]:
        command_info = self._psql_command()
        if command_info is None:
            raise ValueError("PostgreSQL psql binary not found.")
        prefix, _ = command_info
        return subprocess.run(
            [*prefix, "-d", database, *args],
            input=input_text,
            capture_output=True,
            text=True,
            check=True,
            env=self._process_env() | {"PGPASSWORD": ""},
        )

    def list_databases(self) -> OperationResult:
        runtime = self.active_runtime()
        if runtime is None:
            return OperationResult(False, "No PostgreSQL runtime installed.")
        try:
            result = self._run_psql(["-At", "-c", "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname;"])
            names = [line.strip() for line in result.stdout.splitlines() if line.strip() and line.strip() != "postgres"]
            return OperationResult(
                True,
                "Loaded PostgreSQL databases.",
                {"databases": [{"name": name} for name in names], "runtime": runtime.to_dict(), "port": self.port},
            )
        except Exception as exc:
            return OperationResult(False, f"Could not query PostgreSQL databases: {exc}")

    def create_database(self, name: str, encoding: str = "UTF8") -> OperationResult:
        cleaned = name.strip()
        if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", cleaned):
            return OperationResult(False, "Database name must start with a letter or underscore and use only letters, numbers, and underscores.")
        cleaned_encoding = (encoding.strip() or "UTF8").upper()
        if cleaned_encoding not in {"UTF8", "LATIN1", "SQL_ASCII"}:
            return OperationResult(False, "Unsupported PostgreSQL encoding selected.")
        try:
            self._run_psql(["-c", f'CREATE DATABASE "{cleaned}" ENCODING \'{cleaned_encoding}\';'])
            return OperationResult(True, f"Created PostgreSQL database: {cleaned}", {"database": cleaned})
        except subprocess.CalledProcessError as exc:
            return OperationResult(False, f"Create PostgreSQL database failed: {(exc.stderr or exc.stdout or '').strip()}")
        except Exception as exc:
            return OperationResult(False, f"Create PostgreSQL database failed: {exc}")

    def drop_database(self, name: str) -> OperationResult:
        cleaned = name.strip()
        if cleaned in {"postgres", "template0", "template1"}:
            return OperationResult(False, f"Refusing to drop protected PostgreSQL database: {cleaned}")
        if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", cleaned):
            return OperationResult(False, "Database name must start with a letter or underscore and use only letters, numbers, and underscores.")
        try:
            self._run_psql(["-c", f'DROP DATABASE "{cleaned}";'])
            return OperationResult(True, f"Dropped PostgreSQL database: {cleaned}", {"database": cleaned})
        except subprocess.CalledProcessError as exc:
            return OperationResult(False, f"Drop PostgreSQL database failed: {(exc.stderr or exc.stdout or '').strip()}")
        except Exception as exc:
            return OperationResult(False, f"Drop PostgreSQL database failed: {exc}")

    def update_password(self, new_password: str) -> OperationResult:
        value = new_password.strip()
        if not value:
            return OperationResult(False, "Password is required.")
        escaped = value.replace("'", "''")
        try:
            self._run_psql(["-c", f"ALTER USER postgres WITH PASSWORD '{escaped}';"])
            return OperationResult(True, "Updated PostgreSQL postgres user password.")
        except Exception as exc:
            return OperationResult(False, f"PostgreSQL password update failed: {exc}")

    def list_backups(self, database_name: str | None = None) -> OperationResult:
        runtime = self.active_runtime()
        if runtime is None:
            return OperationResult(False, "No PostgreSQL runtime installed.")
        target_name = database_name.strip() if database_name else ""
        items: list[dict[str, object]] = []
        for archive_path in sorted(self.backup_root(runtime).glob("*.zip"), reverse=True):
            parts = archive_path.stem.split("__", 1)
            stored_database = parts[1] if len(parts) == 2 else ""
            if target_name and stored_database != target_name:
                continue
            items.append({
                "name": archive_path.name,
                "database": stored_database,
                "path": str(archive_path),
                "size": archive_path.stat().st_size,
                "created_at": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(archive_path.stat().st_mtime)),
            })
        return OperationResult(True, "Loaded PostgreSQL backups.", {"items": items})

    def create_backup(self, database_name: str) -> OperationResult:
        runtime = self.active_runtime()
        if runtime is None:
            return OperationResult(False, "No PostgreSQL runtime installed.")
        cleaned = database_name.strip()
        pg_dump = self._runtime_bin(runtime, "pg_dump")
        if not pg_dump.exists():
            return OperationResult(False, "PostgreSQL pg_dump binary not found.")
        timestamp = time.strftime("%Y%m%d-%H%M%S")
        archive_path = self.backup_root(runtime) / f"{timestamp}__{cleaned}.zip"
        try:
            with tempfile.TemporaryDirectory(prefix="server-engine-pg-backup-") as temp_dir:
                temp_root = Path(temp_dir)
                dump_path = temp_root / f"{cleaned}.sql"
                command = [str(pg_dump), "-h", "127.0.0.1", "-p", str(self.port), "-U", "postgres", "-d", cleaned, "-f", str(dump_path)]
                subprocess.run(command, capture_output=True, text=True, check=True, env=self._process_env() | {"PGPASSWORD": ""})
                (temp_root / "metadata.json").write_text(json.dumps({"database": cleaned, "engine": "postgresql", "runtime": runtime.version}, indent=2), encoding="utf-8")
                with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
                    archive.write(dump_path, dump_path.name)
                    archive.write(temp_root / "metadata.json", "metadata.json")
            return OperationResult(True, f"Created PostgreSQL backup: {archive_path.name}", {"archive_path": str(archive_path)})
        except subprocess.CalledProcessError as exc:
            return OperationResult(False, f"PostgreSQL backup failed: {(exc.stderr or exc.stdout or '').strip()}")
        except Exception as exc:
            return OperationResult(False, f"PostgreSQL backup failed: {exc}")

    def restore_backup(self, archive_path: str) -> OperationResult:
        runtime = self.active_runtime()
        if runtime is None:
            return OperationResult(False, "No PostgreSQL runtime installed.")
        archive_file = Path(archive_path.strip())
        if not archive_file.exists():
            return OperationResult(False, "Backup archive not found.")
        try:
            with tempfile.TemporaryDirectory(prefix="server-engine-pg-restore-") as temp_dir:
                temp_root = Path(temp_dir)
                with zipfile.ZipFile(archive_file, "r") as archive:
                    archive.extractall(temp_root)
                metadata_path = temp_root / "metadata.json"
                metadata: dict[str, object] = {}
                if metadata_path.exists():
                    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
                database_name = str(metadata.get("database", "")).strip()
                sql_files = sorted(temp_root.glob("*.sql"))
                if not database_name and sql_files:
                    database_name = sql_files[0].stem
                if not database_name or not sql_files:
                    return OperationResult(False, "Backup archive does not contain a PostgreSQL SQL dump.")
                self.create_database(database_name, "UTF8")
                sql = sql_files[0].read_text(encoding="utf-8", errors="replace")
                self._run_psql([], input_text=sql, database=database_name)
            return OperationResult(True, f"Restored PostgreSQL backup into database: {database_name}", {"database": database_name})
        except subprocess.CalledProcessError as exc:
            return OperationResult(False, f"PostgreSQL restore failed: {(exc.stderr or exc.stdout or '').strip()}")
        except Exception as exc:
            return OperationResult(False, f"PostgreSQL restore failed: {exc}")

    def delete_backup(self, archive_path: str) -> OperationResult:
        runtime = self.active_runtime()
        if runtime is None:
            return OperationResult(False, "No PostgreSQL runtime installed.")
        target = Path(archive_path.strip())
        try:
            backup_root = self.backup_root(runtime).resolve()
            target_resolved = target.resolve()
            if backup_root not in target_resolved.parents:
                return OperationResult(False, "Backup path is outside managed PostgreSQL backup folder.")
            target_resolved.unlink()
            return OperationResult(True, f"Deleted backup: {target.name}")
        except Exception as exc:
            return OperationResult(False, f"Delete PostgreSQL backup failed: {exc}")

    def _extract_import_source(self, source_path: Path, working_dir: Path) -> Path:
        if source_path.suffix.lower() == ".sql":
            return source_path
        destination_sql = working_dir / (source_path.stem + ".sql")
        suffixes = [part.lower() for part in source_path.suffixes]
        if source_path.suffix.lower() == ".zip":
            with zipfile.ZipFile(source_path, "r") as archive:
                sql_entries = [info for info in archive.infolist() if not info.is_dir() and info.filename.lower().endswith(".sql")]
                if not sql_entries:
                    raise ValueError("ZIP archive does not contain a .sql file.")
                with archive.open(sql_entries[0], "r") as source, destination_sql.open("wb") as dest:
                    shutil.copyfileobj(source, dest)
            return destination_sql
        if suffixes[-2:] == [".tar", ".gz"] or source_path.suffix.lower() == ".tgz":
            with tarfile.open(source_path, "r:gz") as archive:
                members = [member for member in archive.getmembers() if member.isfile() and member.name.lower().endswith(".sql")]
                if not members:
                    raise ValueError("Archive does not contain a .sql file.")
                source = archive.extractfile(members[0])
                if source is None:
                    raise ValueError("Could not read SQL file from archive.")
                with source, destination_sql.open("wb") as dest:
                    shutil.copyfileobj(source, dest)
            return destination_sql
        if source_path.suffix.lower() == ".gz":
            with gzip.open(source_path, "rb") as source, destination_sql.open("wb") as dest:
                shutil.copyfileobj(source, dest)
            return destination_sql
        raise ValueError("Unsupported import file. Use .sql, .zip, .tar.gz, .tgz, or .gz.")

    def import_dump(self, database_name: str, import_path: str) -> OperationResult:
        cleaned = database_name.strip()
        source_path = Path(import_path.strip())
        if not cleaned:
            return OperationResult(False, "Database name is required.")
        if not source_path.exists():
            return OperationResult(False, "Import file not found.")
        try:
            with tempfile.TemporaryDirectory(prefix="server-engine-pg-import-") as temp_dir:
                sql_path = self._extract_import_source(source_path, Path(temp_dir))
                self.create_database(cleaned, "UTF8")
                sql = sql_path.read_text(encoding="utf-8", errors="replace")
                self._run_psql([], input_text=sql, database=cleaned)
            return OperationResult(True, f"Imported PostgreSQL dump into {cleaned}.")
        except subprocess.CalledProcessError as exc:
            return OperationResult(False, f"PostgreSQL import failed: {(exc.stderr or exc.stdout or '').strip()}")
        except Exception as exc:
            return OperationResult(False, f"PostgreSQL import failed: {exc}")
