from __future__ import annotations

import logging
import os
import shutil
import shlex
import sys
import threading
import selectors
from dataclasses import dataclass, field
from pathlib import Path

import pyte
from ptyprocess import PtyProcessUnicode
from PySide6.QtCore import QObject, Property, Signal, Slot
from PySide6.QtGui import QGuiApplication

from server_engine.bootstrap import AppContainer

LOGGER = logging.getLogger("server_engine.terminal")


@dataclass
class TerminalSession:
    id: str
    title: str
    profile_id: str
    process: PtyProcessUnicode | None = None
    screen: pyte.HistoryScreen | None = None
    stream: pyte.Stream | None = None
    thread: threading.Thread | None = None
    running: bool = False
    status: str = "Starting"
    rows: int = 80
    columns: int = 160
    lock: threading.Lock = field(default_factory=threading.Lock)


class TerminalController(QObject):
    screenUpdated = Signal(str, list, int, int)
    statusChanged = Signal(str, str)
    sessionItemsChanged = Signal()
    profileItemsChanged = Signal()

    def __init__(self, container: AppContainer) -> None:
        super().__init__()
        self._container = container
        self._sessions: dict[str, TerminalSession] = {}
        self._next_session_number = 1
        self._max_sessions = 4

    @Property("QVariantList", notify=sessionItemsChanged)
    def sessionItems(self) -> list[dict[str, object]]:
        return [
            {
                "id": session.id,
                "title": session.title,
                "profileId": session.profile_id,
                "status": session.status,
                "running": session.running,
            }
            for session in self._sessions.values()
        ]

    @Property("QVariantList", notify=profileItemsChanged)
    def profileItems(self) -> list[dict[str, str]]:
        try:
            return self._profile_items()
        except Exception:
            return [self._shell_profile()]

    @Slot(result=str)
    def ensureDefaultSession(self) -> str:
        LOGGER.debug("ensureDefaultSession: session_count=%d", len(self._sessions))
        if self._sessions:
            session_id = next(iter(self._sessions.keys()))
            LOGGER.debug("ensureDefaultSession: reusing session_id=%s", session_id)
            return session_id
        LOGGER.debug("ensureDefaultSession: opening default PHP CLI")
        return self.openDefaultPhpCli()

    @Slot(result=str)
    def openDefaultPhpCli(self) -> str:
        LOGGER.debug("openDefaultPhpCli: start")
        try:
            default_version = self._container.settings_service.get_settings().default_php_version
            LOGGER.debug("openDefaultPhpCli: default_php_version=%s", default_version or "<empty>")
            if default_version:
                runtime = self._container.php_runtime_service.get_runtime(default_version)
                if runtime is not None:
                    LOGGER.debug(
                        "openDefaultPhpCli: using configured runtime version=%s home=%s",
                        runtime.version,
                        runtime.home,
                    )
                    return self._open_profile(self._php_profile(runtime))
            runtimes = self._container.php_runtime_service.list_runtimes()
            if runtimes:
                LOGGER.debug(
                    "openDefaultPhpCli: using first available runtime version=%s home=%s",
                    runtimes[0].version,
                    runtimes[0].home,
                )
                return self._open_profile(self._php_profile(runtimes[0]))
        except Exception:
            LOGGER.exception("openDefaultPhpCli: failed to resolve PHP runtime")
        LOGGER.debug("openDefaultPhpCli: falling back to shell profile")
        return self._open_profile(self._shell_profile())

    @Slot(str, result=str)
    def openProfile(self, profile_id: str) -> str:
        normalized_profile_id = str(profile_id or "").strip()
        LOGGER.debug("openProfile: requested profile_id=%s", normalized_profile_id or "<empty>")
        existing_session_id = self._find_session_by_profile(profile_id)
        if existing_session_id:
            LOGGER.debug(
                "openProfile: reusing existing session_id=%s for profile_id=%s",
                existing_session_id,
                normalized_profile_id or "<empty>",
            )
            return existing_session_id
        try:
            for profile in self._profile_items():
                if str(profile.get("id", "")) == profile_id:
                    LOGGER.debug(
                        "openProfile: matched profile_id=%s kind=%s label=%s",
                        normalized_profile_id or "<empty>",
                        profile.get("kind", ""),
                        profile.get("label", ""),
                    )
                    return self._open_profile(profile)
        except Exception:
            LOGGER.exception("openProfile: failed while building profile list for profile_id=%s", normalized_profile_id or "<empty>")
        if profile_id == "shell":
            LOGGER.debug("openProfile: explicit shell fallback requested")
            return self._open_profile(self._shell_profile())
        LOGGER.debug("openProfile: no matching profile found for profile_id=%s", normalized_profile_id or "<empty>")
        return ""

    @Slot(result=str)
    def openActiveDatabaseCli(self) -> str:
        LOGGER.debug("openActiveDatabaseCli: start")
        try:
            profile_id = self.activeDatabaseProfileId()
            LOGGER.debug("openActiveDatabaseCli: profile_id=%s", profile_id or "<empty>")
            if not profile_id:
                LOGGER.debug("openActiveDatabaseCli: no active database profile")
                return ""
            return self.openProfile(profile_id)
        except Exception:
            LOGGER.exception("openActiveDatabaseCli: failed")
            return ""

    @Slot(result=str)
    def openActiveMongodbCli(self) -> str:
        LOGGER.debug("openActiveMongodbCli: start")
        try:
            profile_id = self.activeMongodbProfileId()
            LOGGER.debug("openActiveMongodbCli: profile_id=%s", profile_id or "<empty>")
            if not profile_id:
                LOGGER.debug("openActiveMongodbCli: no active mongodb profile")
                return ""
            return self.openProfile(profile_id)
        except Exception:
            LOGGER.exception("openActiveMongodbCli: failed")
            return ""

    @Slot(result=str)
    def openActivePostgresqlCli(self) -> str:
        LOGGER.debug("openActivePostgresqlCli: start")
        try:
            profile_id = self.activePostgresqlProfileId()
            LOGGER.debug("openActivePostgresqlCli: profile_id=%s", profile_id or "<empty>")
            if not profile_id:
                LOGGER.debug("openActivePostgresqlCli: no active postgresql profile")
                return ""
            return self.openProfile(profile_id)
        except Exception:
            LOGGER.exception("openActivePostgresqlCli: failed")
            return ""

    @Slot(result=str)
    def openActiveRedisCli(self) -> str:
        try:
            profile_id = self.activeRedisProfileId()
            if not profile_id:
                return ""
            return self.openProfile(profile_id)
        except Exception:
            LOGGER.exception("openActiveRedisCli: failed")
            return ""

    @Slot(str, result=str)
    def openNodeProjectCli(self, project_id: str) -> str:
        try:
            project = self._container.node_project_service.repository.get(str(project_id or "").strip())
            if project is None:
                return ""
            return self._open_profile(self._node_project_profile(project))
        except Exception:
            LOGGER.exception("openNodeProjectCli: failed")
            return ""

    def _node_project_profile(self, project) -> dict[str, str]:
        binaries = self._container.binary_locator.node_binary_paths(project.node_version)
        if binaries is None:
            raise ValueError(f"Node runtime {project.node_version} was not found.")
        label_name = project.name.strip() or project.local_domain.strip() or project.id
        return {
            "id": f"node-project:{project.id}",
            "kind": "node-project",
            "label": f"Node {label_name} CLI",
            "title": f"Node {label_name}",
            "cwd": str(Path(project.project_path).expanduser()),
            "binDir": str(binaries["bin_dir"]),
            "nodeVersion": str(project.node_version),
            "nodeHome": str(binaries["home"]),
            "projectPath": str(project.project_path),
            "command": "/bin/bash",
        }

    @Slot(str, result=str)
    def openWebsiteCli(self, site_id: str) -> str:
        try:
            site = self._container.site_service.get_site(str(site_id or "").strip())
            if site is None:
                return ""
            return self._open_profile(self._website_profile(site))
        except Exception:
            return ""

    @Slot(result=str)
    def activeDatabaseProfileId(self) -> str:
        try:
            runtime = self._container.database_service.active_runtime()
            if runtime is None or runtime.engine not in {"mysql", "mariadb"}:
                return ""
            return f"{runtime.engine}:{runtime.id}"
        except Exception:
            return ""

    @Slot(result=str)
    def activeMongodbProfileId(self) -> str:
        try:
            runtime = self._container.mongodb_service.active_runtime()
            if runtime is None or runtime.engine != "mongodb":
                return ""
            return f"{runtime.engine}:{runtime.id}"
        except Exception:
            return ""

    @Slot(result=str)
    def activePostgresqlProfileId(self) -> str:
        try:
            runtime = self._container.postgresql_service.active_runtime()
            if runtime is None or runtime.engine != "postgresql":
                return ""
            return f"{runtime.engine}:{runtime.id}"
        except Exception:
            return ""

    @Slot(result=str)
    def activeRedisProfileId(self) -> str:
        try:
            runtime = self._container.redis_service.active_runtime()
            if runtime is None:
                return ""
            return f"redis:{runtime.id}"
        except Exception:
            return ""

    @Slot(str)
    def requestSessionScreen(self, session_id: str) -> None:
        session = self._sessions.get(session_id)
        if session is not None:
            self._emit_screen(session)

    @Slot(str, result="QVariantMap")
    def sessionScreen(self, session_id: str) -> dict[str, object]:
        session = self._sessions.get(session_id)
        if session is None:
            return {"id": "", "rows": [], "cursorX": 0, "cursorY": 0, "status": "Idle"}
        lines, cursor_x, cursor_y = self._screen_payload(session)
        return {
            "id": session.id,
            "rows": lines,
            "cursorX": cursor_x,
            "cursorY": cursor_y,
            "status": session.status,
        }

    @Slot(str, str)
    def sendRaw(self, session_id: str, text: str) -> None:
        session = self._sessions.get(session_id)
        if session is None or session.process is None:
            return
        try:
            session.process.write(text)
        except Exception:
            self._set_status(session, "Write failed", False)

    @Slot(str)
    def pasteClipboard(self, session_id: str) -> None:
        text = QGuiApplication.clipboard().text()
        if not text:
            return
        text = text.replace("\r\n", "\n").replace("\r", "\n").replace("\n", "\r")
        self.sendRaw(session_id, text)

    @Slot(str)
    def copyText(self, text: str) -> None:
        if text:
            QGuiApplication.clipboard().setText(text)

    @Slot(str)
    def sendInterrupt(self, session_id: str) -> None:
        self.sendRaw(session_id, "\x03")

    @Slot(str)
    def stopSession(self, session_id: str) -> None:
        session = self._sessions.get(session_id)
        if session is None:
            return
        session.running = False
        if session.process is not None:
            try:
                session.process.terminate(force=True)
            except Exception:
                pass
        session.process = None
        self._set_status(session, "Stopped", False)

    @Slot(str)
    def closeSession(self, session_id: str) -> None:
        self.stopSession(session_id)
        if session_id in self._sessions:
            del self._sessions[session_id]
            self.sessionItemsChanged.emit()

    @Slot(str, int, int)
    def resizeTerminal(self, session_id: str, rows: int, columns: int) -> None:
        session = self._sessions.get(session_id)
        if session is None:
            return
        rows = max(8, int(rows))
        columns = max(20, int(columns))
        session.rows = rows
        session.columns = columns
        with session.lock:
            if session.screen is not None:
                try:
                    session.screen.resize(rows, columns)
                except Exception:
                    pass
        if session.process is not None:
            try:
                session.process.setwinsize(rows, columns)
            except Exception:
                pass

    @Slot()
    def stopAll(self) -> None:
        for session_id in list(self._sessions.keys()):
            self.stopSession(session_id)

    def _profile_items(self) -> list[dict[str, str]]:
        profiles: list[dict[str, str]] = [self._shell_profile()]
        for runtime in self._container.php_runtime_service.list_runtimes():
            profiles.append(self._php_profile(runtime))
        for item in self._container.binary_locator.available_node_runtimes():
            home = Path(str(item.get("home", "")))
            if (home / "bin" / "node").exists():
                version = str(item.get("version", "")).strip()
                profiles.append(
                    {
                        "id": f"node:{version}",
                        "kind": "node",
                        "label": f"Node {version}",
                        "title": f"Node {version}",
                        "binDir": str(home / "bin"),
                        "command": "/bin/bash",
                    }
                )
        for runtime in self._container.database_runtime_service.list_runtimes():
            client_path_text = runtime.client_path or ""
            client_path = Path(client_path_text) if client_path_text else None
            if client_path is not None and client_path.exists():
                label = f"{runtime.engine.title()} {runtime.version}"
                php_runtime = self._default_php_runtime()
                php_path = Path(php_runtime.php_path) if php_runtime is not None else None
                profiles.append(
                    {
                        "id": f"{runtime.engine}:{runtime.id}",
                        "kind": runtime.engine,
                        "label": label,
                        "title": label,
                        "binDir": str(client_path.parent),
                        "phpBinDir": str(php_path.parent) if php_path is not None else "",
                        "phpVersion": str(php_runtime.version) if php_runtime is not None else "",
                        "phpHome": str(php_runtime.home) if php_runtime is not None else "",
                        "iniDir": str(php_runtime.ini_dir) if php_runtime is not None else "",
                        "command": "/bin/bash",
                        "databaseEngine": runtime.engine,
                        "databaseVersion": runtime.version,
                        "databaseHome": runtime.home,
                    }
                )
        for runtime in self._container.redis_runtime_service.list_runtimes():
            client_path_text = runtime.client_path or ""
            client_path = Path(client_path_text) if client_path_text else None
            if client_path is not None and client_path.exists():
                profiles.append(
                    {
                        "id": f"redis:{runtime.id}",
                        "kind": "redis",
                        "label": f"Redis {runtime.version}",
                        "title": f"Redis {runtime.version}",
                        "binDir": str(client_path.parent),
                        "redisVersion": str(runtime.version),
                        "redisHome": str(runtime.home),
                        "redisBinDir": str(client_path.parent),
                        "command": "/bin/bash",
                    }
                )
        for runtime in self._container.memcached_runtime_service.list_runtimes():
            tool_path_text = runtime.tool_path or runtime.server_path or ""
            tool_path = Path(tool_path_text) if tool_path_text else None
            if tool_path is not None and tool_path.exists():
                profiles.append(
                    {
                        "id": f"memcached:{runtime.id}",
                        "kind": "memcached",
                        "label": f"Memcached {runtime.version}",
                        "title": f"Memcached {runtime.version}",
                        "binDir": str(tool_path.parent),
                        "command": "/bin/bash",
                    }
                )
        mongosh = shutil.which("mongosh") or shutil.which("mongo") or ""
        if mongosh:
            profiles.append(
                {
                    "id": "mongo:shell",
                    "kind": "mongodb",
                    "label": "Mongo shell",
                    "title": "Mongo",
                    "binDir": str(Path(mongosh).parent),
                    "command": "/bin/bash",
                }
            )
        return profiles

    def _shell_profile(self) -> dict[str, str]:
        return {
            "id": "shell",
            "kind": "shell",
            "label": "Local shell",
            "title": "Local",
            "binDir": "",
            "command": "/bin/bash",
        }

    def _php_profile(self, runtime) -> dict[str, str]:
        php_path = Path(runtime.php_path)
        short_version = ".".join(str(runtime.version).split(".")[:2]) or str(runtime.version)
        label = f"PHP {short_version} CLI"
        database_runtime = self._active_sql_runtime()
        return {
            "id": f"php:{runtime.version}",
            "kind": "php",
            "label": label,
            "title": label,
            "binDir": str(php_path.parent),
            "home": runtime.home,
            "iniDir": runtime.ini_dir,
            "phpVersion": str(runtime.version),
            "phpHome": str(runtime.home),
            "command": "/bin/bash",
            **self._database_profile_fields(database_runtime),
            **self._redis_profile_fields(),
        }

    def _website_profile(self, site) -> dict[str, str]:
        runtime = self._container.php_runtime_service.get_runtime(site.php_version)
        if runtime is None:
            runtime = self._container.php_runtime_service.require_runtime(site.php_version)
        php_path = Path(runtime.php_path)
        database_runtime = self._active_sql_runtime()
        return {
            "id": f"site:{site.id}",
            "kind": "site",
            "label": f"{site.local_domain} CLI",
            "title": f"{site.local_domain}",
            "cwd": str(Path(site.project_path).expanduser()),
            "binDir": str(php_path.parent),
            "home": runtime.home,
            "iniDir": runtime.ini_dir,
            "phpVersion": str(runtime.version),
            "phpHome": str(runtime.home),
            "siteDomain": str(site.local_domain),
            "siteRoot": str(site.project_path),
            "command": "/bin/bash",
            **self._database_profile_fields(database_runtime),
            **self._redis_profile_fields(),
        }

    def _open_profile(self, profile: dict[str, str], *, allow_shell_fallback: bool = True) -> str:
        profile_id = str(profile.get("id") or "")
        LOGGER.debug(
            "_open_profile: start profile_id=%s kind=%s label=%s",
            profile_id or "<empty>",
            profile.get("kind", ""),
            profile.get("label", ""),
        )
        existing_session_id = self._find_session_by_profile(profile_id)
        if existing_session_id:
            LOGGER.debug("_open_profile: reusing existing session_id=%s for profile_id=%s", existing_session_id, profile_id or "<empty>")
            return existing_session_id
        if len(self._sessions) >= self._max_sessions:
            LOGGER.debug("_open_profile: session limit reached max_sessions=%d profile_id=%s", self._max_sessions, profile_id or "<empty>")
            return ""
        session_id = f"terminal-{self._next_session_number}"
        self._next_session_number += 1
        title = str(profile.get("title") or profile.get("label") or "Local")
        session = TerminalSession(id=session_id, title=title, profile_id=profile_id)
        LOGGER.debug("_open_profile: created session_id=%s title=%s", session_id, title)
        self._reset_screen(session)
        self._sessions[session_id] = session
        self.sessionItemsChanged.emit()

        env = self._mapped_env(profile)
        command = str(profile.get("command") or "/bin/bash")
        rcfile = self._profile_rcfile(profile)
        args = [command, "--noprofile", "--rcfile", str(rcfile), "-i"] if Path(command).name == "bash" else [command]
        cwd = Path(str(profile.get("cwd") or Path.home())).expanduser()
        if not cwd.exists() or not cwd.is_dir():
            cwd = Path.home()
        LOGGER.debug(
            "_open_profile: spawning session_id=%s command=%s cwd=%s rcfile=%s",
            session_id,
            command,
            cwd,
            rcfile,
        )
        try:
            session.process = PtyProcessUnicode.spawn(
                args,
                cwd=str(cwd),
                env=env,
                dimensions=(session.rows, session.columns),
            )
        except Exception as exc:
            LOGGER.exception(
                "_open_profile: spawn failed session_id=%s profile_id=%s command=%s cwd=%s",
                session_id,
                profile_id or "<empty>",
                command,
                cwd,
            )
            if allow_shell_fallback and profile_id != "shell":
                LOGGER.debug("_open_profile: falling back to shell after spawn failure for profile_id=%s", profile_id or "<empty>")
                self._sessions.pop(session_id, None)
                self.sessionItemsChanged.emit()
                return self._open_profile(self._shell_profile(), allow_shell_fallback=False)
            self._set_status(session, f"Failed: {exc}", False)
            return session_id

        session.running = True
        LOGGER.debug("_open_profile: spawn succeeded session_id=%s pid=%s", session_id, getattr(session.process, "pid", None))
        self._set_status(session, f"Running: {title}", False)
        session.thread = threading.Thread(target=self._read_loop, args=(session,), daemon=True)
        session.thread.start()
        return session_id

    def _find_session_by_profile(self, profile_id: str) -> str:
        profile_id = str(profile_id or "")
        if not profile_id:
            return ""
        for session in self._sessions.values():
            if session.profile_id == profile_id:
                return session.id
        return ""

    def _mapped_env(self, profile: dict[str, str]) -> dict[str, str]:
        env = os.environ.copy()
        bin_dir = Path(str(profile.get("binDir") or ""))
        php_bin_dir = Path(str(profile.get("phpBinDir") or profile.get("binDir") or ""))
        path_parts = []
        if bin_dir.exists():
            path_parts.append(str(bin_dir))
        if php_bin_dir.exists() and str(php_bin_dir) not in path_parts:
            path_parts.insert(0, str(php_bin_dir))
        database_bin_dir = Path(str(profile.get("databaseBinDir") or ""))
        if database_bin_dir.exists() and str(database_bin_dir) not in path_parts:
            path_parts.append(str(database_bin_dir))
        redis_bin_dir = Path(str(profile.get("redisBinDir") or ""))
        if redis_bin_dir.exists() and str(redis_bin_dir) not in path_parts:
            path_parts.append(str(redis_bin_dir))
        default_node_bin_dir = self._default_node_bin_dir()
        if (
            default_node_bin_dir
            and str(profile.get("kind") or "") not in {"node", "node-project"}
            and default_node_bin_dir not in path_parts
        ):
            path_parts.insert(0, default_node_bin_dir)
        shim_dir = self._ensure_cli_shims()
        if shim_dir is not None:
            path_parts.insert(0, str(shim_dir))
        path_parts.append(env.get("PATH", ""))
        env["PATH"] = os.pathsep.join([part for part in path_parts if part])
        env["TERM"] = "xterm-256color"
        env["BASH_SILENCE_DEPRECATION_WARNING"] = "1"
        env["CLICOLOR"] = "0"
        env["NO_COLOR"] = "1"
        env["SERVER_ENGINE_CLI"] = "1"
        env["SERVER_ENGINE_RUNTIME"] = str(profile.get("label") or profile.get("id") or "")
        env["PS1"] = f"{profile.get('title') or 'Local'} $ "
        if str(profile.get("kind") or "") == "node-project":
            for key in ("NODE_OPTIONS", "npm_config_node_options", "NPM_CONFIG_NODE_OPTIONS"):
                env.pop(key, None)
        default_php_runtime = self._default_php_runtime()
        default_php_path = Path(default_php_runtime.php_path) if default_php_runtime is not None else None
        if profile.get("phpVersion"):
            php_binary = php_bin_dir / "php"
            env["PHP_BINARY"] = str(php_binary)
            env["PHPRC"] = str(profile.get("iniDir") or php_bin_dir.parent / "conf")
            env["COMPOSER_ALLOW_SUPERUSER"] = "1"
        elif default_php_path is not None and default_php_path.exists():
            env["PHP_BINARY"] = str(default_php_path)
            env["PHPRC"] = str(default_php_path.parent.parent / "conf")
            env["COMPOSER_ALLOW_SUPERUSER"] = "1"
        if profile.get("databaseEngine"):
            env["SERVER_ENGINE_DB_ENGINE"] = str(profile.get("databaseEngine") or "")
            env["SERVER_ENGINE_DB_VERSION"] = str(profile.get("databaseVersion") or "")
        return env

    def _active_sql_runtime(self):
        try:
            runtime = self._container.database_service.active_runtime()
            if runtime is not None and runtime.engine in {"mysql", "mariadb"}:
                return runtime
        except Exception:
            return None
        return None

    def _default_php_runtime(self):
        try:
            default_version = self._container.settings_service.get_settings().default_php_version
            if default_version:
                return self._container.php_runtime_service.get_runtime(default_version)
        except Exception:
            return None
        return None

    def _default_node_bin_dir(self) -> str:
        try:
            settings = self._container.settings_service.get_settings()
            default_version = str(
                getattr(settings, "default_node_version", "")
                or getattr(settings, "active_node_version", "")
                or ""
            ).strip()
            if not default_version:
                return ""
            normalized_default = default_version.removeprefix("node").strip()
            valid_bin_dirs: list[Path] = []
            for item in self._container.binary_locator.available_node_runtimes():
                version = str(item.get("version", "")).strip()
                label = str(item.get("label", "")).strip()
                home = Path(str(item.get("home", ""))).expanduser()
                node_bin_dir = home / "bin"
                if (node_bin_dir / "node").exists():
                    valid_bin_dirs.append(node_bin_dir)
                if normalized_default not in {
                    version.removeprefix("node").strip(),
                    label.removeprefix("node").strip(),
                }:
                    continue
                if (node_bin_dir / "node").exists():
                    return str(node_bin_dir)
            if len(valid_bin_dirs) == 1:
                return str(valid_bin_dirs[0])
        except Exception:
            return ""
        return ""

    def _database_profile_fields(self, runtime) -> dict[str, str]:
        if runtime is None:
            return {}
        client_path = Path(runtime.client_path or "") if runtime.client_path else None
        return {
            "databaseEngine": str(runtime.engine),
            "databaseVersion": str(runtime.version),
            "databaseHome": str(runtime.home),
            "databaseBinDir": str(client_path.parent) if client_path is not None else "",
        }

    def _redis_profile_fields(self) -> dict[str, str]:
        try:
            runtime = self._container.redis_service.active_runtime()
            if runtime is None:
                return {}
            client_path = Path(runtime.client_path or "") if runtime.client_path else None
            return {
                "redisVersion": str(runtime.version),
                "redisHome": str(runtime.home),
                "redisBinDir": str(client_path.parent) if client_path is not None else "",
            }
        except Exception:
            return {}

    def _profile_rcfile(self, profile: dict[str, str]) -> Path:
        rc_dir = self._container.runtime_paths.config_dir / "terminal"
        rc_dir.mkdir(parents=True, exist_ok=True)
        safe_id = str(profile.get("id") or "terminal").replace("/", "_").replace("\\", "_").replace(":", "_")
        rcfile = rc_dir / f"{safe_id}.bashrc"
        lines = [
            "# Generated by Server Engine. Do not edit.",
            "export BASH_SILENCE_DEPRECATION_WARNING=1",
            f"export PS1={shlex.quote(str(profile.get('title') or 'Local') + ' $ ')}",
            f"printf '%s\\n' {shlex.quote('[Server Engine CLI] ' + str(profile.get('label') or profile.get('id') or 'Terminal'))}",
        ]
        cwd = str(profile.get("cwd") or str(Path.home()))
        lines.append(f"printf '%s\\n' {shlex.quote('Working directory: ' + cwd)}")
        if profile.get("siteDomain"):
            lines.append(f"printf '%s\\n' {shlex.quote('Website: ' + str(profile.get('siteDomain')))}")
        if profile.get("phpVersion"):
            lines.append(f"printf '%s\\n' {shlex.quote('PHP: ' + str(profile.get('phpVersion')) + ' (' + str(profile.get('phpHome') or '') + ')')}")
        if profile.get("databaseEngine"):
            lines.append(f"printf '%s\\n' {shlex.quote('Database CLI: ' + str(profile.get('databaseEngine')) + ' ' + str(profile.get('databaseVersion') or '') + ' (' + str(profile.get('databaseHome') or '') + ')')}")
        redis_bin_dir = str(profile.get("redisBinDir") or "")
        if redis_bin_dir:
            lines.append(f"printf '%s\\n' {shlex.quote('Redis: current ' + str(profile.get('redisVersion') or '') + ' (' + str(profile.get('redisHome') or '') + ')')}")
        node_bin_dir = str(profile.get("binDir") or "") if str(profile.get("kind") or "") == "node" else self._default_node_bin_dir()
        if node_bin_dir:
            node_label = "selected" if str(profile.get("kind") or "") == "node" else "default"
            lines.append(f"printf '%s\\n' {shlex.quote('Node: ' + node_label + ' (' + node_bin_dir + ')')}")
        composer_phar = self._find_composer_phar()
        if composer_phar:
            lines.append(f"printf '%s\\n' {shlex.quote('Composer: managed (' + composer_phar + ')')}")
        wp_cli_phar = self._find_wp_cli_phar()
        if wp_cli_phar:
            lines.append(f"printf '%s\\n' {shlex.quote('WP-CLI: managed (' + wp_cli_phar + ')')}")
        mapped_commands = []
        mapped_commands.append("server-engine")
        if profile.get("phpVersion"):
            mapped_commands.append("php")
        if composer_phar:
            mapped_commands.append("composer")
        if wp_cli_phar:
            mapped_commands.append("wp")
        if node_bin_dir:
            mapped_commands.extend(["node", "npm"])
        if profile.get("databaseEngine"):
            mapped_commands.append(str(profile.get("databaseEngine")))
        if redis_bin_dir or str(profile.get("kind") or "") == "redis":
            mapped_commands.append("redis")
        if mapped_commands:
            lines.append(
                f"printf '%s\\n' {shlex.quote('Type ' + ', '.join(mapped_commands) + ' to use the mapped versions for this terminal.')}"
            )
        else:
            lines.append("printf '%s\\n' 'This terminal uses your system PATH.'")
        lines.extend([
            "printf '\\n'",
        ])
        rcfile.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return rcfile

    def _ensure_cli_shims(self) -> Path | None:
        shim_dir = self._container.runtime_paths.bin_dir / "shims"
        shim_dir.mkdir(parents=True, exist_ok=True)

        project_src = self._container.binary_locator.project_root / "src"
        server_engine_shim = shim_dir / "server-engine"
        server_engine_shim.write_text(
            "#!/bin/bash\n"
            f'export PYTHONPATH={shlex.quote(str(project_src))}:${{PYTHONPATH:-}}\n'
            f'exec {shlex.quote(sys.executable)} -m server_engine.cli.app "$@"\n',
            encoding="utf-8",
        )
        server_engine_shim.chmod(0o755)

        se_shim = shim_dir / "se"
        se_shim.write_text(
            "#!/bin/bash\n"
            f'export PYTHONPATH={shlex.quote(str(project_src))}:${{PYTHONPATH:-}}\n'
            f'exec {shlex.quote(sys.executable)} -m server_engine.cli.app "$@"\n',
            encoding="utf-8",
        )
        se_shim.chmod(0o755)

        composer_phar = self._find_composer_phar()
        wp_cli_phar = self._find_wp_cli_phar()
        redis_shim = shim_dir / "redis"
        redis_shim.write_text(
            "#!/bin/bash\n"
            "exec redis-cli \"$@\"\n",
            encoding="utf-8",
        )
        redis_shim.chmod(0o755)
        if not composer_phar and not wp_cli_phar:
            return shim_dir
        default_php_runtime = self._default_php_runtime()
        default_php_path = Path(default_php_runtime.php_path) if default_php_runtime is not None else None
        php_fallback = str(default_php_path) if default_php_path is not None and default_php_path.exists() else "php"
        if composer_phar:
            composer_shim = shim_dir / "composer"
            composer_shim.write_text(
                '#!/bin/bash\nPHP_BIN="${PHP_BINARY:-' + php_fallback + '}"\nexec "$PHP_BIN" -d pcre.jit=0 "' + composer_phar + '" "$@"\n',
                encoding="utf-8",
            )
            composer_shim.chmod(0o755)
        if wp_cli_phar:
            wp_shim = shim_dir / "wp"
            wp_shim.write_text(
                '#!/bin/bash\nPHP_BIN="${PHP_BINARY:-' + php_fallback + '}"\nexec "$PHP_BIN" -d pcre.jit=0 "' + wp_cli_phar + '" "$@"\n',
                encoding="utf-8",
            )
            wp_shim.chmod(0o755)
        return shim_dir

    def _find_composer_phar(self) -> str:
        managed_composer = self._container.binary_locator.latest_composer_phar()
        if managed_composer is not None:
            return str(managed_composer)
        candidates = [
            self._container.runtime_paths.bin_dir / "composer" / "composer.phar",
            self._container.runtime_paths.root / "composer.phar",
            Path("/usr/local/bin/composer.phar"),
            Path("/opt/homebrew/bin/composer.phar"),
        ]
        for candidate in candidates:
            if candidate.exists():
                return str(candidate)
        return shutil.which("composer") or ""

    def _find_wp_cli_phar(self) -> str:
        managed_wp_cli = self._container.binary_locator.latest_wp_cli_phar()
        if managed_wp_cli is not None:
            return str(managed_wp_cli)
        candidates = [
            self._container.runtime_paths.bin_dir / "wp-cli" / "wp-cli.phar",
            self._container.runtime_paths.root / "wp-cli.phar",
            Path.home() / ".wp-cli" / "bin" / "wp-cli.phar",
            Path("/usr/local/bin/wp-cli.phar"),
            Path("/opt/homebrew/bin/wp-cli.phar"),
        ]
        for candidate in candidates:
            if candidate.exists():
                return str(candidate)
        return shutil.which("wp") or ""

    def _reset_screen(self, session: TerminalSession) -> None:
        session.screen = pyte.HistoryScreen(session.columns, session.rows, history=1000)
        session.stream = pyte.Stream(session.screen)
        self._emit_screen(session)

    def _read_loop(self, session: TerminalSession) -> None:
        LOGGER.debug("_read_loop: started session_id=%s", session.id)
        selector = selectors.DefaultSelector()
        try:
            if session.process is not None:
                selector.register(session.process.fd, selectors.EVENT_READ)
        except Exception:
            LOGGER.exception("_read_loop: failed to register selector session_id=%s", session.id)
            session.running = False
            session.process = None
            self._set_status(session, "Closed", False)
            return
        while session.running and session.process is not None:
            try:
                ready = selector.select(0.03)
                if not ready:
                    continue
                data = session.process.read(4096)
                if not data:
                    break
                with session.lock:
                    if session.stream is not None:
                        session.stream.feed(data)
                self._emit_screen(session)
            except EOFError:
                LOGGER.debug("_read_loop: EOF session_id=%s", session.id)
                break
            except Exception as exc:
                LOGGER.exception("_read_loop: error session_id=%s", session.id)
                self._set_status(session, f"Terminal error: {exc}", False)
                break
        try:
            selector.close()
        except Exception:
            pass
        session.running = False
        session.process = None
        LOGGER.debug("_read_loop: stopped session_id=%s", session.id)
        self._set_status(session, "Closed", False)

    def _emit_screen(self, session: TerminalSession) -> None:
        if session.screen is None:
            return
        lines, cursor_x, cursor_y = self._screen_payload(session)
        self.screenUpdated.emit(session.id, lines, cursor_x, cursor_y)

    def _screen_payload(self, session: TerminalSession) -> tuple[list[str], int, int]:
        lines: list[str] = []
        with session.lock:
            if session.screen is None:
                return [], 0, 0
            history_rows = list(session.screen.history.top)
            for row in history_rows:
                lines.append(self._terminal_row_text(row, session.columns))
            for y in range(session.rows):
                row = session.screen.buffer.get(y, {})
                lines.append(self._terminal_row_text(row, session.columns))
            cursor_x = session.screen.cursor.x
            cursor_y = len(history_rows) + session.screen.cursor.y
        return lines, cursor_x, cursor_y

    def _terminal_row_text(self, row, columns: int) -> str:
        chars = []
        for x in range(columns):
            cell = row.get(x)
            chars.append(" " if cell is None else (cell.data or " "))
        return "".join(chars)

    def _set_status(self, session: TerminalSession, status: str, emit_screen: bool) -> None:
        session.status = status
        LOGGER.debug("_set_status: session_id=%s status=%s emit_screen=%s", session.id, status, emit_screen)
        self.statusChanged.emit(session.id, status)
        self.sessionItemsChanged.emit()
        if emit_screen:
            self._emit_screen(session)
