from __future__ import annotations

import logging
import getpass
import gzip
import json
import os
import re
import socket
from pathlib import Path
import shutil
import signal
import subprocess
import tarfile
import tempfile
import time
import zipfile

from server_engine.core.models import DatabaseConfig, DatabaseRuntime, OperationResult, RuntimePaths, ServiceDefinition, ServiceKind, ServiceState, ServiceStatus
from server_engine.services.database_runtime_service import DatabaseRuntimeService
from server_engine.infrastructure.process_manager import ProcessManager
from server_engine.services.settings_service import SettingsService


LOGGER = logging.getLogger("server_engine.database")


class DatabaseService:
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

    def default_config(self) -> DatabaseConfig:
        settings = self.settings_service.get_settings()
        return DatabaseConfig(
            engine=settings.preferred_database_engine,
            port=settings.database_port,
            password=self.root_password(),
        )

    def active_runtime(self) -> DatabaseRuntime | None:
        settings = self.settings_service.get_settings()
        return self.runtime_service.resolve(
            runtime_id=settings.active_database_version,
            preferred_engine=settings.preferred_database_engine,
        )

    def runtime_metadata(self) -> dict[str, object]:
        settings = self.settings_service.get_settings()
        runtime = self.active_runtime()
        return {
            "active_runtime": runtime.to_dict() if runtime else None,
            "available_runtimes": [item.to_dict() for item in self.runtime_service.list_runtimes()],
            "config_path": str(self.config_path()),
            "data_dir": str(self.data_dir(runtime, create=False)),
            "port": settings.database_port,
        }

    def _runtime_key(self, runtime: DatabaseRuntime | None = None) -> str:
        active = runtime or self.active_runtime()
        return active.id if active else "database"

    def _runtime_log_key(self, runtime: DatabaseRuntime | None = None) -> str:
        active = runtime or self.active_runtime()
        if active is None:
            return "database"
        return active.version.strip() or active.id

    def _password_for_runtime(self, runtime: DatabaseRuntime | None = None) -> str:
        settings = self.settings_service.get_settings()
        runtime_key = self._runtime_key(runtime)
        runtime_passwords = settings.database_runtime_passwords or {}
        if runtime_key in runtime_passwords:
            return runtime_passwords.get(runtime_key, "")
        return settings.database_root_password

    def _safe_runtime_root(self, runtime: DatabaseRuntime | None = None) -> Path:
        return Path(tempfile.gettempdir()) / "server-engine-db" / self._runtime_key(runtime)

    def _safe_link(self, link_path: Path, target_path: Path) -> Path:
        link_path.parent.mkdir(parents=True, exist_ok=True)
        target_path.parent.mkdir(parents=True, exist_ok=True)
        if not target_path.exists():
            if target_path.suffix:
                target_path.touch()
            else:
                target_path.mkdir(parents=True, exist_ok=True)
        if link_path.is_symlink():
            current = os.readlink(link_path)
            if Path(current) == target_path:
                return link_path
            link_path.unlink()
        elif link_path.exists():
            if link_path.is_dir():
                for child in link_path.iterdir():
                    if child.is_file() or child.is_symlink():
                        child.unlink()
            else:
                link_path.unlink()
        os.symlink(target_path, link_path)
        return link_path

    def safe_data_dir(self, runtime: DatabaseRuntime | None = None) -> Path:
        runtime = runtime or self.active_runtime()
        real_path = self.data_dir(runtime)
        return self._safe_link(self._safe_runtime_root(runtime) / "data", real_path)

    def safe_runtime_home(self, runtime: DatabaseRuntime | None = None) -> Path:
        runtime = runtime or self.active_runtime()
        if runtime is None:
            return self._safe_runtime_root(runtime) / "runtime-home"
        return self._safe_link(self._safe_runtime_root(runtime) / "runtime-home", Path(runtime.home))

    def safe_log_path(self, runtime: DatabaseRuntime | None = None) -> Path:
        runtime = runtime or self.active_runtime()
        real_path = self.log_path(runtime)
        return self._safe_link(self._safe_runtime_root(runtime) / "runtime.log", real_path)

    def safe_socket_path(self, runtime: DatabaseRuntime | None = None) -> Path:
        # Use the conventional local socket so app frameworks can connect with
        # DB_HOST=localhost without additional socket configuration.
        return Path("/tmp/mysql.sock")

    def safe_pid_path(self, runtime: DatabaseRuntime | None = None) -> Path:
        path = self._safe_runtime_root(runtime) / "runtime.pid"
        path.parent.mkdir(parents=True, exist_ok=True)
        return path

    def safe_config_path(self, runtime: DatabaseRuntime | None = None) -> Path:
        path = self._safe_runtime_root(runtime) / "my.cnf"
        path.parent.mkdir(parents=True, exist_ok=True)
        return path

    def config_path(self, runtime: DatabaseRuntime | None = None) -> Path:
        path = self.runtime_paths.database_config_dir / f"{self._runtime_key(runtime)}.cnf"
        path.parent.mkdir(parents=True, exist_ok=True)
        return path

    def log_path(self, runtime: DatabaseRuntime | None = None) -> Path:
        path = self.runtime_paths.logs_dir / "database" / self._runtime_log_key(runtime) / "database.log"
        path.parent.mkdir(parents=True, exist_ok=True)
        return path

    def socket_path(self, runtime: DatabaseRuntime | None = None) -> Path:
        return self.safe_socket_path(runtime)

    def pid_path(self, runtime: DatabaseRuntime | None = None) -> Path:
        return self.runtime_paths.runtime_dir / "database" / f"{self._runtime_key(runtime)}.pid"

    def data_dir(self, runtime: DatabaseRuntime | None = None, create: bool = True) -> Path:
        path = self.runtime_paths.data_dir / "database" / self._runtime_key(runtime)
        if create:
            path.mkdir(parents=True, exist_ok=True)
        return path

    def backup_root(self, runtime: DatabaseRuntime | None = None) -> Path:
        path = self.runtime_paths.backups_dir / "database" / self._runtime_key(runtime)
        path.mkdir(parents=True, exist_ok=True)
        return path

    def backup_log_path(self, runtime: DatabaseRuntime | None = None) -> Path:
        path = self.runtime_paths.logs_dir / "database" / f"{self._runtime_key(runtime)}-backup.log"
        path.parent.mkdir(parents=True, exist_ok=True)
        return path

    def import_log_path(self, runtime: DatabaseRuntime | None = None) -> Path:
        path = self.runtime_paths.logs_dir / "database" / f"{self._runtime_key(runtime)}-import.log"
        path.parent.mkdir(parents=True, exist_ok=True)
        return path

    def _report_progress(self, callback, value: int, message: str) -> None:
        if callback is None:
            return
        try:
            callback(int(max(0, min(100, value))), message)
        except Exception:
            pass

    def _append_import_log(self, runtime: DatabaseRuntime | None, message: str) -> None:
        with open(self.import_log_path(runtime), "a", encoding="utf-8") as log_handle:
            log_handle.write(message.rstrip() + "\n")

    def generate_config(self) -> str:
        settings = self.settings_service.get_settings()
        runtime = self.active_runtime()
        config_path = self.config_path(runtime)
        (self.runtime_paths.runtime_dir / "database").mkdir(parents=True, exist_ok=True)
        if config_path.exists():
            config = config_path.read_text(encoding="utf-8", errors="replace")
            if not config.strip():
                config = self._default_runtime_config(settings, runtime)
        else:
            config = self._default_runtime_config(settings, runtime)

        # MySQL 8+ no longer supports query_cache_size.
        if self._is_mysql8_or_newer(runtime):
            config = "\n".join(
                line for line in config.splitlines()
                if not line.strip().lower().startswith("query_cache_size=")
            ).rstrip() + "\n"

        self._atomic_write_text(config_path, config)
        safe_config_path = self.safe_config_path(runtime)
        self._atomic_write_text(safe_config_path, config)
        return str(safe_config_path)

    def _default_runtime_config(self, settings, runtime: DatabaseRuntime | None) -> str:
        config = (
            "[mysqld]\n"
            f"port={settings.database_port}\n"
            f"datadir={self.safe_data_dir(runtime)}\n"
            f"socket={self.safe_socket_path(runtime)}\n"
            f"pid-file={self.safe_pid_path(runtime)}\n"
            f"log-error={self.safe_log_path(runtime)}\n"
            "bind-address=127.0.0.1\n"
        )
        opt = settings.database_optimization or {}
        config += (
            f"key_buffer_size={int(opt.get('key_buffer_size_mb', 16))}M\n"
            f"tmp_table_size={int(opt.get('tmp_table_size_mb', 128))}M\n"
            f"innodb_buffer_pool_size={int(opt.get('innodb_buffer_pool_size_mb', 1024))}M\n"
            f"innodb_log_buffer_size={int(opt.get('innodb_log_buffer_size_mb', 128))}M\n"
            f"sort_buffer_size={int(opt.get('sort_buffer_size_kb', 256))}K\n"
            f"read_buffer_size={int(opt.get('read_buffer_size_kb', 256))}K\n"
            f"read_rnd_buffer_size={int(opt.get('read_rnd_buffer_size_kb', 256))}K\n"
            f"join_buffer_size={int(opt.get('join_buffer_size_kb', 256))}K\n"
            f"thread_stack={int(opt.get('thread_stack_kb', 256))}K\n"
            f"binlog_cache_size={int(opt.get('binlog_cache_size_kb', 64))}K\n"
            f"thread_cache_size={int(opt.get('thread_cache_size', 96))}\n"
            f"table_open_cache={int(opt.get('table_open_cache', 1400))}\n"
            f"max_connections={int(opt.get('max_connections', 160))}\n"
        )
        if not self._is_mysql8_or_newer(runtime):
            config += f"query_cache_size={int(opt.get('query_cache_size_mb', 64))}M\n"
        return config

    def _atomic_write_text(self, path: Path, content: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as handle:
            handle.write(content)
            temp_path = Path(handle.name)
        temp_path.replace(path)

    def _is_mysql8_or_newer(self, runtime: DatabaseRuntime | None) -> bool:
        if runtime is None:
            return False
        if (runtime.engine or "").strip().lower() != "mysql":
            return False
        try:
            major = int(str(runtime.version).split(".", 1)[0])
            return major >= 8
        except Exception:
            return False

    def _clear_quarantine_tree(self, path: Path) -> None:
        if os.uname().sysname != "Darwin":
            return
        try:
            subprocess.run(
                ["xattr", "-dr", "com.apple.quarantine", str(path)],
                capture_output=True,
                text=True,
                check=False,
            )
        except Exception:
            return

    def service_definition(self) -> ServiceDefinition | None:
        runtime = self.active_runtime()
        if runtime is None:
            return None
        settings = self.settings_service.get_settings()
        return ServiceDefinition(
            id="database",
            name=f"{runtime.engine.upper()} Database",
            kind=ServiceKind.DATABASE,
            executable_name=Path(runtime.server_path).name,
            default_port=settings.database_port,
            executable_path=runtime.server_path,
            arguments=[f"--defaults-file={self.generate_config()}"],
            working_directory=str(self.runtime_paths.runtime_dir / "database"),
            log_path=str(self.safe_log_path(runtime)),
        )

    def _terminate_temp_process(self, process: subprocess.Popen[bytes] | subprocess.Popen[str]) -> None:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except Exception:
            try:
                process.terminate()
            except Exception:
                return
        for _ in range(30):
            if process.poll() is not None:
                return
            time.sleep(0.1)
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except Exception:
            try:
                process.kill()
            except Exception:
                return

    def _client_candidates(self, runtime: DatabaseRuntime) -> list[Path]:
        candidates: list[Path] = []
        engine = str(runtime.engine or "").strip().lower()
        if runtime.client_path:
            candidates.append(Path(runtime.client_path))
        if engine == "mariadb":
            candidates.append(Path(runtime.home) / "bin" / "mariadb")
            candidates.append(Path(runtime.home) / "bin" / "mysql")
        else:
            candidates.append(Path(runtime.home) / "bin" / "mysql")
            candidates.append(Path(runtime.home) / "bin" / "mariadb")
        return candidates

    def _dump_candidates(self, runtime: DatabaseRuntime) -> list[Path]:
        engine = str(runtime.engine or "").strip().lower()
        if engine == "mariadb":
            return [
                Path(runtime.home) / "bin" / "mariadb-dump",
                Path(runtime.home) / "bin" / "mysqldump",
            ]
        return [
            Path(runtime.home) / "bin" / "mysqldump",
            Path(runtime.home) / "bin" / "mariadb-dump",
        ]

    def _verify_runtime_password(self, runtime: DatabaseRuntime, password: str, timeout_seconds: float = 12.0) -> bool:
        client_path = next((candidate for candidate in self._client_candidates(runtime) if candidate.exists()), None)
        if client_path is None:
            return False
        env = os.environ.copy()
        if password:
            env["MYSQL_PWD"] = password
        elif "MYSQL_PWD" in env:
            env.pop("MYSQL_PWD")
        command = [str(client_path), "-u", "root", f"--socket={self.safe_socket_path(runtime)}", "-e", "SELECT 1"]
        deadline = time.time() + timeout_seconds
        while time.time() < deadline:
            try:
                subprocess.run(command, capture_output=True, text=True, check=True, env=env)
                return True
            except Exception:
                time.sleep(0.3)
        return False

    def _force_reset_root_password(self, runtime: DatabaseRuntime, new_value: str) -> OperationResult:
        previous_status = self.status()
        if previous_status.state == ServiceState.RUNNING:
            self.process_manager.stop("database")

        escaped_password = new_value.replace("\\", "\\\\").replace("'", "''")
        init_sql_path = self._safe_runtime_root(runtime) / "reset-root-password.sql"
        init_sql_path.parent.mkdir(parents=True, exist_ok=True)
        init_sql_path.write_text(
            "ALTER USER IF EXISTS 'root'@'localhost' IDENTIFIED BY '" + escaped_password + "';\n"
            "ALTER USER IF EXISTS 'root'@'127.0.0.1' IDENTIFIED BY '" + escaped_password + "';\n"
            "FLUSH PRIVILEGES;\n",
            encoding="utf-8",
        )

        safe_config = self.generate_config()
        command = [
            runtime.server_path,
            f"--defaults-file={safe_config}",
            f"--init-file={init_sql_path}",
        ]
        log_path = self.log_path(runtime)
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with open(log_path, "a", encoding="utf-8") as log_handle:
            log_handle.write("$ " + " ".join(command[:-1] + ["--init-file=<hidden>"]) + "\n")
            process = subprocess.Popen(
                command,
                cwd=str(self.runtime_paths.runtime_dir / "database"),
                stdout=log_handle,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
        try:
            if not self._verify_runtime_password(runtime, new_value):
                return OperationResult(False, "Forced root password reset did not complete successfully.")

            settings = self.settings_service.get_settings()
            settings.database_root_password = new_value
            runtime_passwords = dict(settings.database_runtime_passwords or {})
            runtime_passwords[self._runtime_key(runtime)] = new_value
            settings.database_runtime_passwords = runtime_passwords
            self.settings_service.save_settings(settings)
            return OperationResult(True, "Updated root password.")
        finally:
            self._terminate_temp_process(process)
            try:
                init_sql_path.unlink(missing_ok=True)
            except Exception:
                pass
            if previous_status.state == ServiceState.RUNNING:
                self.start_runtime()

    def status(self) -> ServiceStatus:
        definition = self.service_definition()
        if definition is None:
            return ServiceStatus(service_id="database", state=ServiceState.STOPPED, message="No active database runtime selected.")

        return self.process_manager.status(definition)

    def initialize_runtime(self) -> OperationResult:
        runtime = self.active_runtime()
        if runtime is None:
            return OperationResult(False, "No active database runtime selected.")
        self._clear_quarantine_tree(Path(runtime.home))

        data_dir = self.data_dir(runtime)
        safe_data_dir = self.safe_data_dir(runtime)
        safe_runtime_home = self.safe_runtime_home(runtime)
        (self.runtime_paths.runtime_dir / "database").mkdir(parents=True, exist_ok=True)
        system_markers = [
            data_dir / "mysql",
            data_dir / "performance_schema",
            data_dir / "aria_log_control",
            data_dir / "ibdata1",
        ]
        if any(marker.exists() for marker in system_markers):
            return OperationResult(
                True,
                "Database data directory already initialized.",
                {
                    "data_dir": str(data_dir),
                    "initialized_now": False,
                    "already_initialized": True,
                },
            )

        if runtime.engine == "mariadb":
            candidates = [
                safe_runtime_home / "scripts" / "mariadb-install-db",
                safe_runtime_home / "bin" / "mariadb-install-db",
                safe_runtime_home / "scripts" / "mysql_install_db",
                safe_runtime_home / "bin" / "mysql_install_db",
            ]
            install_path = next((candidate for candidate in candidates if candidate.exists()), None)
            if install_path is None:
                return OperationResult(False, "MariaDB install-db script not found.")
            command = [
                str(install_path),
                "--no-defaults",
                f"--basedir={safe_runtime_home}",
                f"--datadir={safe_data_dir}",
                f"--user={getpass.getuser()}",
                "--skip-test-db",
                "--auth-root-authentication-method=normal",
            ]
        else:
            server_path = safe_runtime_home / "bin" / Path(runtime.server_path).name
            if not server_path.exists():
                server_path = Path(runtime.server_path)
            command = [
                str(server_path),
                "--no-defaults",
                "--initialize-insecure",
                f"--basedir={safe_runtime_home}",
                f"--datadir={safe_data_dir}",
                f"--user={getpass.getuser()}",
            ]
        try:
            result = subprocess.run(command, capture_output=True, text=True, check=True)
            output = "\n".join(part for part in [result.stdout.strip(), result.stderr.strip()] if part)
            if output:
                self.log_path(runtime).write_text(output + "\n", encoding="utf-8")
            return OperationResult(
                True,
                "Initialized database data directory.",
                {
                    "data_dir": str(data_dir),
                    "initialized_now": True,
                    "already_initialized": False,
                },
            )
        except subprocess.CalledProcessError as exc:
            details = "\n".join(
                part for part in [
                    str(exc.stdout or "").strip(),
                    str(exc.stderr or "").strip(),
                ] if part
            ).strip()
            if details:
                try:
                    self.log_path(runtime).write_text(details + "\n", encoding="utf-8")
                except Exception:
                    pass
                LOGGER.error("Database init failed for %s:\n%s", runtime.id, details)
                return OperationResult(False, f"Database init failed: {details}")
            LOGGER.error("Database init failed for %s with exit code %s", runtime.id, exc.returncode)
            return OperationResult(False, f"Database init failed with exit code {exc.returncode}.")
        except Exception as exc:
            LOGGER.exception("Database init failed for %s", runtime.id)
            return OperationResult(False, f"Database init failed: {exc}")

    def start_runtime(self) -> OperationResult:
        settings = self.settings_service.get_settings()
        if self._port_in_use(settings.database_port):
            LOGGER.error("Database cannot start because port %s is already in use.", settings.database_port)
            return OperationResult(
                False,
                f"Database cannot start because port {settings.database_port} is already in use. Stop the existing database server or change the Database port.",
                {"port": settings.database_port},
            )
        init_result = self.initialize_runtime()
        if not init_result.success:
            LOGGER.error("Database start aborted during initialization: %s", init_result.message)
            return init_result
        definition = self.service_definition()
        if definition is None:
            LOGGER.error("Database start failed: no active database runtime selected.")
            return OperationResult(False, "No active database runtime selected.")
        status = self.process_manager.start(definition)
        payload = {"state": status.to_dict(), **dict(init_result.payload or {})}
        if status.state.value == "error":
            LOGGER.error("Database start failed: %s", status.message)
            return OperationResult(False, status.message, payload)
        if bool(payload.get("initialized_now")):
            LOGGER.info("Database started after initial initialization: %s", status.message)
            return OperationResult(
                True,
                "Database initialized (first run) and started successfully.",
                payload,
            )
        LOGGER.info("Database start completed: %s", status.message)
        return OperationResult(True, status.message, payload)

    def stop_runtime(self) -> OperationResult:
        status = self.process_manager.stop("database")
        if status.state.value != "error":
            return OperationResult(True, status.message, {"state": status.to_dict()})
        for _ in range(8):
            current = self.status()
            if current.state == ServiceState.STOPPED:
                return OperationResult(True, "Database stopped.", {"state": current.to_dict()})
            time.sleep(0.1)
        LOGGER.error("Database stop failed: %s", status.message)
        return OperationResult(False, status.message, {"state": status.to_dict()})

    def restart_runtime(self) -> OperationResult:
        self.process_manager.stop("database")
        return self.start_runtime()

    def _port_in_use(self, port: int) -> bool:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.1)
            return sock.connect_ex(("127.0.0.1", port)) == 0

    def read_log_tail(self, lines: int = 120) -> str:
        path = self.log_path()
        if not path.exists():
            return ""
        content = path.read_text(encoding="utf-8", errors="replace").splitlines()
        return "\n".join(content[-lines:])

    def _client_command_prefix(self) -> tuple[list[str], DatabaseRuntime, dict[str, str]] | None:
        runtime = self.active_runtime()
        if runtime is None:
            return None

        client_candidates = self._client_candidates(runtime)
        client_path = next((candidate for candidate in client_candidates if candidate.exists()), None)
        if client_path is None:
            return None

        settings = self.settings_service.get_settings()
        env = os.environ.copy()
        runtime_password = self._password_for_runtime(runtime)
        if runtime_password:
            env["MYSQL_PWD"] = runtime_password
        socket_path = self.safe_socket_path(runtime)
        prefix = [str(client_path), "-u", "root", f"--socket={socket_path}"]
        tcp_prefix = [str(client_path), "-u", "root", "--protocol=TCP", "-h", "127.0.0.1", "-P", str(settings.database_port)]

        for attempt in (prefix, tcp_prefix):
            try:
                subprocess.run(attempt + ["-e", "SELECT 1"], capture_output=True, text=True, check=True, env=env)
                return attempt, runtime, env
            except Exception:
                continue
        return prefix, runtime, env

    def _clear_database_content(self, database_name: str) -> OperationResult:
        cleaned = database_name.strip()
        if not cleaned:
            return OperationResult(False, "Database name is required.")

        command_info = self._client_command_prefix()
        if command_info is None:
            return OperationResult(False, "Database client binary not found for the active runtime.")
        prefix, runtime, env = command_info

        try:
            escaped_db = cleaned.replace("'", "''")
            query = (
                "SELECT TABLE_NAME, TABLE_TYPE "
                "FROM information_schema.tables "
                f"WHERE table_schema = '{escaped_db}' "
                "ORDER BY TABLE_NAME"
            )
            result = subprocess.run(
                prefix + ["--database", cleaned, "--batch", "--skip-column-names", "-e", query],
                capture_output=True,
                text=True,
                check=True,
                env=env,
            )
            tables: list[str] = []
            views: list[str] = []
            for line in result.stdout.splitlines():
                parts = [part.strip() for part in line.split("\t")]
                if len(parts) < 2 or not parts[0]:
                    continue
                name = parts[0].replace("`", "``")
                table_type = parts[1].strip().upper()
                if table_type == "VIEW":
                    views.append(name)
                else:
                    tables.append(name)

            if views:
                drop_views = "DROP VIEW IF EXISTS " + ", ".join(f"`{name}`" for name in views)
                subprocess.run(
                    prefix + ["--database", cleaned, "-e", drop_views],
                    capture_output=True,
                    text=True,
                    check=True,
                    env=env,
                )

            if tables:
                drop_tables = (
                    "SET FOREIGN_KEY_CHECKS=0; "
                    "DROP TABLE IF EXISTS " + ", ".join(f"`{name}`" for name in tables) + "; "
                    "SET FOREIGN_KEY_CHECKS=1;"
                )
                subprocess.run(
                    prefix + ["--database", cleaned, "-e", drop_tables],
                    capture_output=True,
                    text=True,
                    check=True,
                    env=env,
                )
            return OperationResult(True, f"Cleared existing database content: {cleaned}", {"database": cleaned, "tables": len(tables), "views": len(views)})
        except subprocess.CalledProcessError as exc:
            details = "\n".join(part for part in [exc.stdout.strip(), exc.stderr.strip()] if part).strip()
            if details:
                self.log_path(runtime).write_text("$ CLEAR DATABASE CONTENT\n" + details + "\n", encoding="utf-8")
                return OperationResult(False, f"Clear database content failed: {details}", {"database": cleaned})
            return OperationResult(False, f"Clear database content failed with exit code {exc.returncode}.", {"database": cleaned})
        except Exception as exc:
            return OperationResult(False, f"Clear database content failed: {exc}", {"database": cleaned})

    def create_database(self, name: str, charset: str = "utf8mb4") -> OperationResult:
        cleaned = name.strip()
        if not cleaned:
            return OperationResult(False, "Database name is required.", {"database": name})
        if not all(char.isalnum() or char == "_" for char in cleaned):
            return OperationResult(False, "Database name may only contain letters, numbers, and underscores.", {"database": name})
        cleaned_charset = charset.strip().lower() or "utf8mb4"
        charset_map = {
            "utf8mb4": "utf8mb4_unicode_ci",
            "utf8": "utf8_unicode_ci",
            "latin1": "latin1_swedish_ci",
        }
        if cleaned_charset not in charset_map:
            return OperationResult(False, "Unsupported charset selected.", {"database": cleaned, "charset": cleaned_charset})

        command_info = self._client_command_prefix()
        if command_info is None:
            return OperationResult(False, "Database client binary not found for the active runtime.", {"database": name})
        prefix, runtime, env = command_info
        collation = charset_map[cleaned_charset]
        command = prefix + ["-e", f"CREATE DATABASE `{cleaned}` CHARACTER SET {cleaned_charset} COLLATE {collation}"]

        try:
            result = subprocess.run(command, capture_output=True, text=True, check=True, env=env)
            output = "\n".join(part for part in [result.stdout.strip(), result.stderr.strip()] if part)
            log_lines = ["$ " + " ".join(command)]
            if output:
                log_lines.append(output)
            self.log_path(runtime).write_text("\n".join(log_lines) + "\n", encoding="utf-8")
            return OperationResult(True, f"Created database: {cleaned}", {"database": cleaned, "charset": cleaned_charset})
        except subprocess.CalledProcessError as exc:
            details = "\n".join(part for part in [exc.stdout.strip(), exc.stderr.strip()] if part).strip()
            if details:
                self.log_path(runtime).write_text("$ " + " ".join(command) + "\n" + details + "\n", encoding="utf-8")
                return OperationResult(False, f"Create database failed: {details}", {"database": cleaned, "charset": cleaned_charset})
            return OperationResult(False, f"Create database failed with exit code {exc.returncode}.", {"database": cleaned, "charset": cleaned_charset})
        except Exception as exc:
            return OperationResult(False, f"Create database failed: {exc}", {"database": cleaned, "charset": cleaned_charset})

    def drop_database(self, name: str) -> OperationResult:
        cleaned = name.strip()
        if not cleaned:
            return OperationResult(False, "Database name is required.", {"database": name})
        if cleaned in {"information_schema", "mysql", "performance_schema", "sys"}:
            return OperationResult(False, f"Refusing to drop protected system database: {cleaned}", {"database": cleaned})
        if not re.match(r"^[A-Za-z0-9_]+$", cleaned):
            return OperationResult(False, "Database name can only contain letters, numbers, and underscores.", {"database": cleaned})

        command_info = self._client_command_prefix()
        if command_info is None:
            return OperationResult(False, "Database client binary not found for the active runtime.", {"database": cleaned})
        prefix, runtime, env = command_info
        command = prefix + ["-e", f"DROP DATABASE `{cleaned}`"]

        try:
            result = subprocess.run(command, capture_output=True, text=True, check=True, env=env)
            output = "\n".join(part for part in [result.stdout.strip(), result.stderr.strip()] if part)
            log_lines = ["$ " + " ".join(command)]
            if output:
                log_lines.append(output)
            self.log_path(runtime).write_text("\n".join(log_lines) + "\n", encoding="utf-8")
            return OperationResult(True, f"Dropped database: {cleaned}", {"database": cleaned})
        except subprocess.CalledProcessError as exc:
            details = "\n".join(part for part in [exc.stdout.strip(), exc.stderr.strip()] if part).strip()
            if details:
                self.log_path(runtime).write_text("$ " + " ".join(command) + "\n" + details + "\n", encoding="utf-8")
                return OperationResult(False, f"Drop database failed: {details}", {"database": cleaned})
            return OperationResult(False, f"Drop database failed with exit code {exc.returncode}.", {"database": cleaned})
        except Exception as exc:
            return OperationResult(False, f"Drop database failed: {exc}", {"database": cleaned})

    def import_dump(self, name: str, dump_path: str) -> OperationResult:
        cleaned = name.strip()
        cleaned_path = dump_path.strip()
        if not cleaned:
            return OperationResult(False, "Database name is required.", {"database": name, "dump_path": dump_path})
        if not cleaned_path:
            return OperationResult(False, "Import file is required.", {"database": name, "dump_path": dump_path})
        return self.import_dump_with_progress(cleaned, cleaned_path)

    def export_dump(self, name: str, dump_path: str) -> OperationResult:
        return OperationResult(False, "Database export is not implemented in phase 1.", {"database": name, "dump_path": dump_path})

    def test_connection(self) -> OperationResult:
        return OperationResult(False, "Database connectivity testing is not implemented in phase 1.")

    def root_password(self) -> str:
        return self._password_for_runtime()

    def update_root_password(self, new_password: str) -> OperationResult:
        runtime = self.active_runtime()
        if runtime is None:
            return OperationResult(False, "No active database runtime selected.")

        new_value = new_password.strip()
        if not new_value:
            return OperationResult(False, "New root password is required.")

        command_info = self._client_command_prefix()
        if command_info is None:
            return OperationResult(False, "Database client binary not found for the active runtime.")

        prefix, runtime, env = command_info
        escaped_password = new_value.replace("\\", "\\\\").replace("'", "''")
        sql = (
            f"ALTER USER IF EXISTS 'root'@'localhost' IDENTIFIED BY '{escaped_password}'; "
            f"ALTER USER IF EXISTS 'root'@'127.0.0.1' IDENTIFIED BY '{escaped_password}'; "
            "FLUSH PRIVILEGES"
        )
        command = prefix + ["-e", sql]
        try:
            result = subprocess.run(command, capture_output=True, text=True, check=True, env=env)
            settings = self.settings_service.get_settings()
            settings.database_root_password = new_value
            runtime_passwords = dict(settings.database_runtime_passwords or {})
            runtime_passwords[self._runtime_key(runtime)] = new_value
            settings.database_runtime_passwords = runtime_passwords
            self.settings_service.save_settings(settings)
            output = "\n".join(part for part in [result.stdout.strip(), result.stderr.strip()] if part)
            log_lines = ["$ " + " ".join(prefix + ["-e", "ALTER USER ..."])]
            if output:
                log_lines.append(output)
            self.log_path(runtime).write_text("\n".join(log_lines) + "\n", encoding="utf-8")
            return OperationResult(True, "Updated root password.")
        except subprocess.CalledProcessError as exc:
            details = "\n".join(part for part in [exc.stdout.strip(), exc.stderr.strip()] if part).strip()
            if details:
                self.log_path(runtime).write_text("$ " + " ".join(prefix + ["-e", "ALTER USER ..."]) + "\n" + details + "\n", encoding="utf-8")
                if "ERROR 1045" in details or "Access denied" in details:
                    return self._force_reset_root_password(runtime, new_value)
                return OperationResult(False, f"Root password update failed: {details}")
            return OperationResult(False, f"Root password update failed with exit code {exc.returncode}.")
        except Exception as exc:
            return OperationResult(False, f"Root password update failed: {exc}")

    def list_databases(self) -> OperationResult:
        runtime = self.active_runtime()
        if runtime is None:
            return OperationResult(False, "No active database runtime selected.")

        client_candidates = []
        if runtime.client_path:
            client_candidates.append(Path(runtime.client_path))
        client_candidates.append(Path(runtime.home) / "bin" / "mysql")
        client_candidates.append(Path(runtime.home) / "bin" / "mariadb")
        client_path = next((candidate for candidate in client_candidates if candidate.exists()), None)
        if client_path is None:
            return OperationResult(False, "Database client binary not found for the active runtime.")

        settings = self.settings_service.get_settings()
        base_command = [
            str(client_path),
            "-u",
            "root",
            "--batch",
            "--skip-column-names",
            "-e",
            "SHOW DATABASES",
        ]
        socket_path = self.safe_socket_path(runtime)
        attempts = [
            base_command[:3] + [f"--socket={socket_path}"] + base_command[3:],
            base_command[:3] + ["--protocol=TCP", "-h", "127.0.0.1", "-P", str(settings.database_port)] + base_command[3:],
            base_command,
        ]

        last_error = "Unable to query database list."
        for command in attempts:
            try:
                env = os.environ.copy()
                runtime_password = self._password_for_runtime(runtime)
                if runtime_password:
                    env["MYSQL_PWD"] = runtime_password
                result = subprocess.run(command, capture_output=True, text=True, check=True, env=env)
                names = [
                    line.strip()
                    for line in result.stdout.splitlines()
                    if line.strip() and line.strip() not in {"information_schema", "mysql", "performance_schema", "sys"}
                ]
                payload = {
                    "databases": [{"name": name} for name in names],
                    "runtime": runtime.to_dict(),
                    "port": settings.database_port,
                }
                return OperationResult(True, "Loaded databases.", payload)
            except Exception as exc:
                last_error = str(exc)

        return OperationResult(False, f"Could not query databases: {last_error}")

    def list_backups(self, database_name: str | None = None) -> OperationResult:
        runtime = self.active_runtime()
        if runtime is None:
            return OperationResult(False, "No active database runtime selected.")
        items: list[dict[str, object]] = []
        backup_root = self.backup_root(runtime)
        target_name = database_name.strip() if database_name else ""
        for archive_path in sorted(backup_root.glob("*.zip"), reverse=True):
            parts = archive_path.stem.split("__", 1)
            stored_database = parts[1] if len(parts) == 2 else ""
            if target_name and stored_database != target_name:
                continue
            created_at = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(archive_path.stat().st_mtime))
            items.append(
                {
                    "name": archive_path.name,
                    "database": stored_database,
                    "path": str(archive_path),
                    "size": archive_path.stat().st_size,
                    "created_at": created_at,
                }
            )
        return OperationResult(True, "Loaded database backups.", {"items": items})

    def create_backup(self, database_name: str, progress_callback=None, cancel_callback=None) -> OperationResult:
        start = time.perf_counter()
        cleaned = database_name.strip()
        if not cleaned:
            return OperationResult(False, "Database name is required.")
        runtime = self.active_runtime()
        if runtime is None:
            return OperationResult(False, "No active database runtime selected.")
        LOGGER.debug("create_backup: start database=%s runtime=%s", cleaned, runtime.id)
        dump_binary = next((candidate for candidate in self._dump_candidates(runtime) if candidate.exists()), None)
        if dump_binary is None:
            return OperationResult(False, "Database dump binary not found for the active runtime.")
        self._report_progress(progress_callback, 5, "Preparing backup...")
        LOGGER.debug(
            "create_backup: prepared database=%s dump_binary=%s elapsed=%.1fms",
            cleaned,
            dump_binary,
            (time.perf_counter() - start) * 1000.0,
        )

        command_info = self._client_command_prefix()
        if command_info is None:
            return OperationResult(False, "Database client binary not found for the active runtime.")
        prefix, _, env = command_info
        dump_command = [str(dump_binary)]
        for token in prefix[1:]:
            dump_command.append(token)
        dump_command.append(cleaned)

        timestamp = time.strftime("%Y%m%d-%H%M%S")
        archive_name = f"{timestamp}__{cleaned}.zip"
        archive_path = self.backup_root(runtime) / archive_name
        metadata = {
            "database": cleaned,
            "engine": runtime.engine,
            "runtime": runtime.version,
            "created_at": timestamp,
        }
        try:
            with tempfile.TemporaryDirectory(prefix="server-engine-db-backup-") as temp_dir:
                temp_root = Path(temp_dir)
                dump_path = temp_root / f"{cleaned}.sql"
                metadata_path = temp_root / "metadata.json"
                self._report_progress(progress_callback, 25, "Dumping database...")
                dump_start = time.perf_counter()
                with open(dump_path, "w", encoding="utf-8") as dump_handle:
                    process = subprocess.Popen(
                        dump_command,
                        stdout=dump_handle,
                        stderr=subprocess.PIPE,
                        text=True,
                        env=env,
                        start_new_session=True,
                    )
                    try:
                        while process.poll() is None:
                            if cancel_callback is not None and cancel_callback():
                                self._terminate_temp_process(process)
                                return OperationResult(False, "Backup cancelled.")
                            time.sleep(0.1)
                        stderr_output = process.stderr.read().strip() if process.stderr is not None else ""
                        if process.returncode != 0:
                            details = stderr_output or f"exit code {process.returncode}"
                            return OperationResult(False, f"Backup failed: {details}")
                    finally:
                        if process.stderr is not None:
                            try:
                                process.stderr.close()
                            except Exception:
                                pass
                LOGGER.debug(
                    "create_backup: dump finished database=%s path=%s size=%d elapsed=%.1fms",
                    cleaned,
                    dump_path,
                    dump_path.stat().st_size if dump_path.exists() else 0,
                    (time.perf_counter() - dump_start) * 1000.0,
                )
                metadata_path.write_text(json.dumps(metadata, indent=2), encoding="utf-8")
                if cancel_callback is not None and cancel_callback():
                    return OperationResult(False, "Backup cancelled.")
                self._report_progress(progress_callback, 75, "Compressing backup archive...")
                zip_start = time.perf_counter()
                with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
                    archive.write(dump_path, dump_path.name)
                    archive.write(metadata_path, metadata_path.name)
                LOGGER.debug(
                    "create_backup: zip finished database=%s archive=%s size=%d elapsed=%.1fms",
                    cleaned,
                    archive_path,
                    archive_path.stat().st_size if archive_path.exists() else 0,
                    (time.perf_counter() - zip_start) * 1000.0,
                )
                if cancel_callback is not None and cancel_callback():
                    try:
                        archive_path.unlink(missing_ok=True)
                    except Exception:
                        pass
                    return OperationResult(False, "Backup cancelled.")
            with open(self.backup_log_path(runtime), "a", encoding="utf-8") as log_handle:
                log_handle.write("$ " + " ".join(dump_command) + "\n")
                log_handle.write("Created backup: " + str(archive_path) + "\n")
            self._report_progress(progress_callback, 100, "Backup complete.")
            LOGGER.debug(
                "create_backup: done database=%s archive=%s total=%.1fms",
                cleaned,
                archive_path,
                (time.perf_counter() - start) * 1000.0,
            )
            return OperationResult(True, f"Created backup: {archive_name}", {"archive_path": str(archive_path), "database": cleaned})
        except Exception as exc:
            LOGGER.debug(
                "create_backup: error database=%s error=%s total=%.1fms",
                cleaned,
                exc,
                (time.perf_counter() - start) * 1000.0,
            )
            return OperationResult(False, f"Backup failed: {exc}")

    def restore_backup(self, archive_path: str, progress_callback=None, cancel_callback=None) -> OperationResult:
        start = time.perf_counter()
        cleaned_path = archive_path.strip()
        if not cleaned_path:
            return OperationResult(False, "Backup archive path is required.")
        runtime = self.active_runtime()
        if runtime is None:
            return OperationResult(False, "No active database runtime selected.")
        LOGGER.debug("restore_backup: start archive=%s runtime=%s", cleaned_path, runtime.id)
        archive_file = Path(cleaned_path)
        if not archive_file.exists():
            return OperationResult(False, "Backup archive not found.")
        command_info = self._client_command_prefix()
        if command_info is None:
            return OperationResult(False, "Database client binary not found for the active runtime.")
        prefix, _, env = command_info
        self._report_progress(progress_callback, 5, "Reading backup archive...")
        try:
            with tempfile.TemporaryDirectory(prefix="server-engine-db-restore-") as temp_dir:
                temp_root = Path(temp_dir)
                unzip_start = time.perf_counter()
                with zipfile.ZipFile(archive_file, "r") as archive:
                    archive.extractall(temp_root)
                LOGGER.debug(
                    "restore_backup: unzip finished archive=%s temp_root=%s elapsed=%.1fms",
                    archive_file,
                    temp_root,
                    (time.perf_counter() - unzip_start) * 1000.0,
                )
                metadata_path = temp_root / "metadata.json"
                metadata: dict[str, object] = {}
                if metadata_path.exists():
                    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
                database_name = str(metadata.get("database", "")).strip()
                if not database_name:
                    sql_files = sorted(temp_root.glob("*.sql"))
                    if not sql_files:
                        return OperationResult(False, "Backup archive does not contain a SQL dump.")
                    database_name = sql_files[0].stem
                dump_path = temp_root / f"{database_name}.sql"
                if not dump_path.exists():
                    sql_files = sorted(temp_root.glob("*.sql"))
                    if not sql_files:
                        return OperationResult(False, "Backup archive does not contain a SQL dump.")
                    dump_path = sql_files[0]

                self._report_progress(progress_callback, 25, "Preparing database for restore...")
                create_start = time.perf_counter()
                create_command = prefix + ["-e", f"CREATE DATABASE IF NOT EXISTS `{database_name}`"]
                subprocess.run(create_command, capture_output=True, text=True, check=True, env=env)
                LOGGER.debug(
                    "restore_backup: create database finished database=%s elapsed=%.1fms",
                    database_name,
                    (time.perf_counter() - create_start) * 1000.0,
                )

                restore_command = prefix + [database_name]
                self._report_progress(progress_callback, 10, "Importing SQL dump...")
                import_start = time.perf_counter()
                with open(dump_path, "rb") as dump_handle:
                    process = subprocess.Popen(
                        restore_command,
                        stdin=subprocess.PIPE,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        env=env,
                        start_new_session=True,
                    )
                    try:
                        assert process.stdin is not None
                        total = max(dump_path.stat().st_size, 1)
                        sent = 0
                        while True:
                            if cancel_callback is not None and cancel_callback():
                                self._terminate_temp_process(process)
                                return OperationResult(False, "Restore cancelled.")
                            chunk = dump_handle.read(1024 * 1024)
                            if not chunk:
                                break
                            process.stdin.write(chunk)
                            sent += len(chunk)
                            percent = 10 + int((sent / total) * 85)
                            self._report_progress(progress_callback, percent, "Importing SQL dump...")
                        try:
                            process.stdin.close()
                        except Exception:
                            pass
                        while process.poll() is None:
                            if cancel_callback is not None and cancel_callback():
                                self._terminate_temp_process(process)
                                return OperationResult(False, "Restore cancelled.")
                            time.sleep(0.1)
                        stdout = process.stdout.read().decode("utf-8", errors="replace") if process.stdout is not None else ""
                        stderr = process.stderr.read().decode("utf-8", errors="replace") if process.stderr is not None else ""
                        if process.returncode != 0:
                            details = (stderr or stdout or f"exit code {process.returncode}").strip()
                            return OperationResult(False, f"Restore failed: {details}")
                    finally:
                        for pipe in (process.stdin, process.stdout, process.stderr):
                            if pipe is not None:
                                try:
                                    pipe.close()
                                except Exception:
                                    pass
                LOGGER.debug(
                    "restore_backup: import finished database=%s archive=%s elapsed=%.1fms",
                    database_name,
                    archive_file,
                    (time.perf_counter() - import_start) * 1000.0,
                )

            with open(self.backup_log_path(runtime), "a", encoding="utf-8") as log_handle:
                log_handle.write("Restored backup: " + str(archive_file) + "\n")
                log_handle.write("Target database: " + database_name + "\n")
            self._report_progress(progress_callback, 100, "Restore complete.")
            LOGGER.debug(
                "restore_backup: done database=%s archive=%s total=%.1fms",
                database_name,
                archive_file,
                (time.perf_counter() - start) * 1000.0,
            )
            return OperationResult(True, f"Restored backup into database: {database_name}", {"database": database_name, "archive_path": str(archive_file)})
        except Exception as exc:
            LOGGER.debug(
                "restore_backup: error archive=%s error=%s total=%.1fms",
                cleaned_path,
                exc,
                (time.perf_counter() - start) * 1000.0,
            )
            return OperationResult(False, f"Restore failed: {exc}")

    def delete_backup(self, archive_path: str) -> OperationResult:
        start = time.perf_counter()
        cleaned_path = archive_path.strip()
        if not cleaned_path:
            return OperationResult(False, "Backup archive path is required.")
        runtime = self.active_runtime()
        if runtime is None:
            return OperationResult(False, "No active database runtime selected.")
        LOGGER.debug("delete_backup: start archive=%s runtime=%s", cleaned_path, runtime.id)
        target = Path(cleaned_path)
        if not target.exists() or not target.is_file():
            return OperationResult(False, "Backup archive not found.")
        try:
            backup_root = self.backup_root(runtime).resolve()
            target_resolved = target.resolve()
            if backup_root not in target_resolved.parents:
                return OperationResult(False, "Backup path is outside managed backup folder.")
            delete_start = time.perf_counter()
            target.unlink()
            LOGGER.debug(
                "delete_backup: unlink finished archive=%s elapsed=%.1fms",
                target_resolved,
                (time.perf_counter() - delete_start) * 1000.0,
            )
            with open(self.backup_log_path(runtime), "a", encoding="utf-8") as log_handle:
                log_handle.write("Deleted backup: " + str(target_resolved) + "\n")
            LOGGER.debug(
                "delete_backup: done archive=%s total=%.1fms",
                target_resolved,
                (time.perf_counter() - start) * 1000.0,
            )
            return OperationResult(True, f"Deleted backup: {target.name}")
        except Exception as exc:
            LOGGER.debug(
                "delete_backup: error archive=%s error=%s total=%.1fms",
                cleaned_path,
                exc,
                (time.perf_counter() - start) * 1000.0,
            )
            return OperationResult(False, f"Delete backup failed: {exc}")

    def _extract_import_source(self, source_path: Path, working_dir: Path, progress_callback=None) -> Path:
        suffixes = [part.lower() for part in source_path.suffixes]
        destination_sql = working_dir / (source_path.stem + ".sql")
        self._report_progress(progress_callback, 10, "Inspecting import file...")

        if source_path.suffix.lower() == ".sql":
            return source_path

        if source_path.suffix.lower() == ".zip":
            with zipfile.ZipFile(source_path, "r") as archive:
                sql_entries = [info for info in archive.infolist() if not info.is_dir() and info.filename.lower().endswith(".sql")]
                if not sql_entries:
                    raise ValueError("ZIP archive does not contain a .sql file.")
                target = sql_entries[0]
                total = max(target.file_size, 1)
                extracted = 0
                self._report_progress(progress_callback, 20, "Extracting ZIP archive...")
                with archive.open(target, "r") as source_handle, open(destination_sql, "wb") as dest_handle:
                    while True:
                        chunk = source_handle.read(1024 * 1024)
                        if not chunk:
                            break
                        dest_handle.write(chunk)
                        extracted += len(chunk)
                        percent = 20 + int((extracted / total) * 25)
                        self._report_progress(progress_callback, percent, "Extracting ZIP archive...")
                return destination_sql

        if suffixes[-2:] == [".tar", ".gz"] or source_path.suffix.lower() == ".tgz":
            with tarfile.open(source_path, "r:gz") as archive:
                members = [member for member in archive.getmembers() if member.isfile() and member.name.lower().endswith(".sql")]
                if not members:
                    raise ValueError("Archive does not contain a .sql file.")
                target = members[0]
                total = max(target.size, 1)
                extracted = 0
                self._report_progress(progress_callback, 20, "Extracting tar archive...")
                source_handle = archive.extractfile(target)
                if source_handle is None:
                    raise ValueError("Could not read SQL file from archive.")
                with source_handle, open(destination_sql, "wb") as dest_handle:
                    while True:
                        chunk = source_handle.read(1024 * 1024)
                        if not chunk:
                            break
                        dest_handle.write(chunk)
                        extracted += len(chunk)
                        percent = 20 + int((extracted / total) * 25)
                        self._report_progress(progress_callback, percent, "Extracting tar archive...")
                return destination_sql

        if source_path.suffix.lower() == ".gz":
            self._report_progress(progress_callback, 20, "Decompressing gzip file...")
            total = max(source_path.stat().st_size, 1)
            consumed = 0
            with gzip.open(source_path, "rb") as source_handle, open(destination_sql, "wb") as dest_handle:
                while True:
                    chunk = source_handle.read(1024 * 1024)
                    if not chunk:
                        break
                    dest_handle.write(chunk)
                    consumed = min(total, consumed + len(chunk))
                    percent = 20 + int((consumed / total) * 25)
                    self._report_progress(progress_callback, percent, "Decompressing gzip file...")
            return destination_sql

        raise ValueError("Unsupported import file. Use .sql, .zip, .tar.gz, .tgz, or .gz.")

    def import_dump_with_progress(self, name: str, dump_path: str, progress_callback=None, clear_existing: bool = False) -> OperationResult:
        cleaned = name.strip()
        source_path = Path(dump_path.strip())
        if not cleaned:
            return OperationResult(False, "Database name is required.")
        if not source_path.exists():
            return OperationResult(False, "Import file not found.")
        runtime = self.active_runtime()
        if runtime is None:
            return OperationResult(False, "No active database runtime selected.")
        command_info = self._client_command_prefix()
        if command_info is None:
            return OperationResult(False, "Database client binary not found for the active runtime.")
        prefix, _, env = command_info

        try:
            free_bytes = shutil.disk_usage(self.runtime_paths.data_dir).free
            source_bytes = source_path.stat().st_size
            if free_bytes < source_bytes * 2:
                return OperationResult(False, "Not enough free disk space for import staging.")
        except Exception:
            pass

        try:
            with tempfile.TemporaryDirectory(prefix="server-engine-db-import-") as temp_dir:
                working_dir = Path(temp_dir)
                sql_path = self._extract_import_source(source_path, working_dir, progress_callback)
                if not sql_path.exists():
                    return OperationResult(False, "Prepared SQL file not found for import.")

                self._report_progress(progress_callback, 50, "Preparing database...")
                create_command = prefix + ["-e", f"CREATE DATABASE IF NOT EXISTS `{cleaned}`"]
                subprocess.run(create_command, capture_output=True, text=True, check=True, env=env)

                if clear_existing:
                    self._report_progress(progress_callback, 55, "Clearing existing database content...")
                    clear_result = self._clear_database_content(cleaned)
                    if not clear_result.success:
                        return clear_result

                import_command = prefix + [cleaned]
                self._append_import_log(runtime, "$ " + " ".join(import_command))
                self._report_progress(progress_callback, 60, "Importing SQL...")
                total = max(sql_path.stat().st_size, 1)
                sent = 0
                process = subprocess.Popen(
                    import_command,
                    stdin=subprocess.PIPE,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    env=env,
                )
                try:
                    assert process.stdin is not None
                    with open(sql_path, "rb") as sql_handle:
                        while True:
                            chunk = sql_handle.read(1024 * 1024)
                            if not chunk:
                                break
                            process.stdin.write(chunk)
                            sent += len(chunk)
                            percent = 60 + int((sent / total) * 40)
                            self._report_progress(progress_callback, percent, "Importing SQL...")
                    process.stdin.close()
                except BrokenPipeError:
                    pass
                stdout = process.stdout.read() if process.stdout is not None else b""
                stderr = process.stderr.read() if process.stderr is not None else b""
                process.wait()
                if process.returncode != 0:
                    details = (
                        (stderr or stdout or f"exit code {process.returncode}").decode("utf-8", errors="replace")
                        if isinstance(stderr, bytes)
                        else (stderr or stdout or f"exit code {process.returncode}")
                    )
                    self._append_import_log(runtime, details)
                    return OperationResult(False, f"Import failed: {details.strip()}")

                if stdout:
                    if isinstance(stdout, bytes):
                        stdout = stdout.decode("utf-8", errors="replace")
                    self._append_import_log(runtime, stdout)
                if stderr:
                    if isinstance(stderr, bytes):
                        stderr = stderr.decode("utf-8", errors="replace")
                    self._append_import_log(runtime, stderr)
                self._report_progress(progress_callback, 100, "Import complete.")
                return OperationResult(True, f"Imported into database: {cleaned}", {"database": cleaned, "source": str(source_path)})
        except OSError as exc:
            if getattr(exc, "errno", None) == 28:
                self._append_import_log(runtime, "Import failed: no space left on device.")
                return OperationResult(False, "Import failed: disk is full.")
            self._append_import_log(runtime, f"Import failed: {exc}")
            return OperationResult(False, f"Import failed: {exc}")
        except subprocess.CalledProcessError as exc:
            details = exc.stderr.strip() or exc.stdout.strip() or f"exit code {exc.returncode}"
            self._append_import_log(runtime, details)
            return OperationResult(False, f"Import failed: {details}")
        except Exception as exc:
            self._append_import_log(runtime, f"Import failed: {exc}")
            return OperationResult(False, f"Import failed: {exc}")
