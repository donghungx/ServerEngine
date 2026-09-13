from __future__ import annotations

import json
import logging
import os
import signal
import subprocess
import sys
import threading
import time

from server_engine.core.models import RuntimePaths, ServiceDefinition, ServiceState, ServiceStatus, utc_now

LOGGER = logging.getLogger("server_engine.runtime_install")


class ProcessManager:
    def __init__(self, runtime_paths: RuntimePaths) -> None:
        self.runtime_paths = runtime_paths
        self.state_file = runtime_paths.runtime_dir / "process_state.json"

    def _load_state(self) -> dict[str, dict[str, object]]:
        if not self.state_file.exists():
            return {}
        return json.loads(self.state_file.read_text(encoding="utf-8"))

    def _save_state(self, data: dict[str, dict[str, object]]) -> None:
        self.state_file.write_text(json.dumps(data, indent=2), encoding="utf-8")

    def start(self, definition: ServiceDefinition) -> ServiceStatus:
        if definition.executable_path:
            return self._start_real_process(definition)
        return self._start_simulated(definition.id, definition.default_port)

    def _start_simulated(self, service_id: str, port: int) -> ServiceStatus:
        state = self._load_state()
        next_pid = max([int(item.get("pid", 1000)) for item in state.values()] + [1000]) + 1
        status = {
            "state": ServiceState.RUNNING.value,
            "pid": next_pid,
            "port": port,
            "message": "Simulated process active",
            "started_at": utc_now(),
        }
        state[service_id] = status
        self._save_state(state)
        return ServiceStatus(service_id=service_id, state=ServiceState.RUNNING, pid=next_pid, port=port, message="Simulated process active", started_at=status["started_at"])

    def _start_real_process(self, definition: ServiceDefinition) -> ServiceStatus:
        executable_path = definition.executable_path or ""
        path = os.path.expanduser(executable_path)
        if not os.path.exists(path):
            return ServiceStatus(service_id=definition.id, state=ServiceState.ERROR, port=definition.default_port, message=f"Executable not found: {path}")
        if not os.access(path, os.X_OK):
            return ServiceStatus(service_id=definition.id, state=ServiceState.ERROR, port=definition.default_port, message=f"Executable is not runnable: {path}")
        current = self.status(definition)
        if current.state == ServiceState.RUNNING:
            return current
        popen_kwargs = {
            "cwd": definition.working_directory or self.runtime_paths.root,
            "start_new_session": True,
            "env": self._process_env(definition.environment),
        }
        log_handle = None
        log_path = None
        mirror_to_screen = False
        if definition.log_path:
            log_path = os.path.expanduser(definition.log_path)
            os.makedirs(os.path.dirname(log_path), exist_ok=True)
            mirror_to_screen = bool(definition.log_to_screen)
            if mirror_to_screen:
                popen_kwargs["stdout"] = subprocess.PIPE
                popen_kwargs["stderr"] = subprocess.STDOUT
                popen_kwargs["text"] = True
                popen_kwargs["bufsize"] = 1
            else:
                log_handle = open(log_path, "a", encoding="utf-8")
                popen_kwargs["stdout"] = log_handle
                popen_kwargs["stderr"] = subprocess.STDOUT
        elif definition.log_to_screen:
            # Inherit parent stdout/stderr so logs are visible in terminal runs.
            pass
        else:
            popen_kwargs["stdout"] = subprocess.DEVNULL
            popen_kwargs["stderr"] = subprocess.DEVNULL
        try:
            process = subprocess.Popen([path, *definition.arguments], **popen_kwargs)
        except Exception as exc:
            LOGGER.exception(
                "Failed to start process %s (%s) args=%s cwd=%s",
                definition.id,
                path,
                definition.arguments,
                popen_kwargs.get("cwd"),
            )
            return ServiceStatus(
                service_id=definition.id,
                state=ServiceState.ERROR,
                port=definition.default_port,
                message=f"Process spawn failed: {exc}",
            )
        finally:
            if definition.log_path and not mirror_to_screen and log_handle is not None:
                log_handle.close()
        if log_path and mirror_to_screen and process.stdout is not None:
            threading.Thread(
                target=self._stream_process_output,
                args=(process.stdout, log_path),
                daemon=True,
            ).start()
        for _ in range(10):
            time.sleep(0.1)
            if process.poll() is not None:
                startup_details = ""
                if log_path and os.path.exists(log_path):
                    startup_details = self._tail_text_file(log_path, lines=20)
                if startup_details:
                    LOGGER.error(
                        "Process %s exited during startup code=%s. Recent log:\n%s",
                        definition.id,
                        process.returncode,
                        startup_details,
                    )
                else:
                    LOGGER.error(
                        "Process %s exited during startup code=%s",
                        definition.id,
                        process.returncode,
                    )
                message = f"Process exited during startup with code {process.returncode}"
                if startup_details:
                    compact = " | ".join(line.strip() for line in startup_details.splitlines() if line.strip())
                    if compact:
                        message = f"{message}: {compact[:600]}"
                return ServiceStatus(
                    service_id=definition.id,
                    state=ServiceState.ERROR,
                    port=definition.default_port,
                    message=message,
                )
        state = self._load_state()
        status = {
            "state": ServiceState.RUNNING.value,
            "pid": process.pid,
            "port": definition.default_port,
            "message": f"Running {os.path.basename(path)}",
            "started_at": utc_now(),
            "executable_path": path,
        }
        state[definition.id] = status
        self._save_state(state)
        return ServiceStatus(
            service_id=definition.id,
            state=ServiceState.RUNNING,
            pid=process.pid,
            port=definition.default_port,
            message=str(status["message"]),
            started_at=str(status["started_at"]),
        )

    def _stream_process_output(self, stream, log_path: str) -> None:
        try:
            with open(log_path, "a", encoding="utf-8") as handle:
                for line in stream:
                    handle.write(line)
                    handle.flush()
                    try:
                        sys.stdout.write(line)
                        sys.stdout.flush()
                    except Exception:
                        pass
        except Exception:
            pass

    def stop(self, service_id: str) -> ServiceStatus:
        state = self._load_state()
        record = state.get(service_id)
        if record and record.get("pid"):
            pid = int(record["pid"])
            stopped, forced, error = self._terminate_pid(pid)
            if error:
                # Guard against false negatives: process may have exited while stop was in-flight.
                if not self._is_running(pid):
                    state.pop(service_id, None)
                    self._save_state(state)
                    return ServiceStatus(service_id=service_id, state=ServiceState.STOPPED, message="Service stopped")
                self._save_state(state)
                return ServiceStatus(service_id=service_id, state=ServiceState.ERROR, message=error)
            if not stopped:
                # Guard against timing race where process exits right after terminate attempts.
                for _ in range(6):
                    if not self._is_running(pid):
                        state.pop(service_id, None)
                        self._save_state(state)
                        return ServiceStatus(service_id=service_id, state=ServiceState.STOPPED, message="Service stopped")
                    time.sleep(0.1)
                self._save_state(state)
                return ServiceStatus(service_id=service_id, state=ServiceState.ERROR, message=f"Failed to stop PID {pid}")
            state.pop(service_id, None)
            self._save_state(state)
            message = "Service stopped"
            if forced:
                message = f"Service stopped after force-kill of PID {pid}"
            return ServiceStatus(service_id=service_id, state=ServiceState.STOPPED, message=message)
        else:
            state.pop(service_id, None)
            self._save_state(state)
        return ServiceStatus(service_id=service_id, state=ServiceState.STOPPED, message="Service stopped")

    def status(self, definition: ServiceDefinition) -> ServiceStatus:
        state = self._load_state()
        record = state.get(definition.id)
        if not record:
            return ServiceStatus(service_id=definition.id, state=ServiceState.STOPPED, port=definition.default_port, message="Service not running")
        pid = int(record["pid"]) if record.get("pid") else None
        if pid is not None and not self._is_running(pid):
            state.pop(definition.id, None)
            self._save_state(state)
            return ServiceStatus(service_id=definition.id, state=ServiceState.STOPPED, port=definition.default_port, message="Service not running")
        return ServiceStatus(
            service_id=definition.id,
            state=ServiceState(record["state"]),
            pid=pid,
            port=int(record["port"]) if record.get("port") else definition.default_port,
            message=str(record.get("message", "")),
            started_at=str(record.get("started_at")) if record.get("started_at") else None,
        )

    def stop_all(self) -> None:
        state = self._load_state()
        for service_id in list(state.keys()):
            self.stop(service_id)
        self._save_state({})

    def _is_running(self, pid: int) -> bool:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return False
        except PermissionError:
            try:
                result = subprocess.run(
                    ["ps", "-o", "pid=", "-p", str(pid)],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                return bool(result.stdout.strip())
            except Exception:
                return True
        try:
            result = subprocess.run(
                ["ps", "-o", "stat=", "-p", str(pid)],
                capture_output=True,
                text=True,
                check=False,
            )
            state = result.stdout.strip()
            if not state or "Z" in state:
                return False
        except Exception:
            pass
        return True

    def _process_env(self, overrides: dict[str, str] | None = None) -> dict[str, str]:
        env = os.environ.copy()
        for key in ("LANG", "LC_ALL", "LC_CTYPE"):
            value = env.get(key, "").strip()
            if not value or value.upper() == "C" or value.upper() == "C.UTF-8":
                env[key] = "en_US.UTF-8"
        if overrides:
            for key, value in overrides.items():
                env[str(key)] = str(value)
        return env

    def _tail_text_file(self, path: str, lines: int = 20) -> str:
        try:
            content = open(path, "r", encoding="utf-8", errors="replace").read().splitlines()
            return "\n".join(content[-lines:])
        except Exception:
            return ""

    def _terminate_pid(self, pid: int) -> tuple[bool, bool, str | None]:
        try:
            os.killpg(pid, signal.SIGTERM)
        except ProcessLookupError:
            return True, False, None
        except PermissionError:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                return True, False, None
            except PermissionError:
                return False, False, f"Permission denied while stopping PID {pid}"

        for _ in range(20):
            time.sleep(0.1)
            if not self._is_running(pid):
                return True, False, None

        try:
            os.killpg(pid, signal.SIGKILL)
        except ProcessLookupError:
            return True, True, None
        except PermissionError:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                return True, True, None
            except PermissionError:
                return False, False, f"Permission denied while force-stopping PID {pid}"

        for _ in range(20):
            time.sleep(0.1)
            if not self._is_running(pid):
                return True, True, None
        return False, False, None
