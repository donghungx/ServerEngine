from __future__ import annotations

import os
import socket
import subprocess
from pathlib import Path

from server_engine.core.models import NodeProject, NodeProjectStatus, OperationResult, ServiceDefinition, ServiceKind, ServiceState, ServiceStatus
from server_engine.infrastructure.binary_locator import BinaryLocator
from server_engine.infrastructure.process_manager import ProcessManager
from server_engine.services.node_project_service import NodeProjectService


class NodeProjectRuntimeService:
    def __init__(
        self,
        node_project_service: NodeProjectService,
        binary_locator: BinaryLocator,
        process_manager: ProcessManager,
    ) -> None:
        self.node_project_service = node_project_service
        self.binary_locator = binary_locator
        self.process_manager = process_manager

    def status(self, project_id: str) -> ServiceStatus:
        project = self._project(project_id)
        if project is None:
            return ServiceStatus(service_id=self._service_id(project_id), state=ServiceState.STOPPED, message="Project not found.")
        definition = self._service_definition(project)
        return self.process_manager.status(definition)

    def start(self, project_id: str) -> OperationResult:
        project = self._project(project_id)
        if project is None:
            return OperationResult(False, "Project not found.")
        definition = self._service_definition(project)
        current = self.process_manager.status(definition)
        if current.state == ServiceState.RUNNING:
            return OperationResult(True, "Project is already running.", {"state": current.to_dict()})
        if self._port_in_use(project.port):
            return OperationResult(False, f"Port {project.port} is already in use.", {"port": project.port})
        install_result = self._ensure_dependencies(project)
        if not install_result.success:
            return install_result
        status = self.process_manager.start(definition)
        if status.state == ServiceState.ERROR:
            return OperationResult(False, status.message, {"state": status.to_dict()})
        self.node_project_service.update_project(project.id, status=NodeProjectStatus.RUNNING)
        return OperationResult(True, status.message, {"state": status.to_dict()})

    def stop(self, project_id: str) -> OperationResult:
        project = self._project(project_id)
        if project is None:
            return OperationResult(False, "Project not found.")
        status = self.process_manager.stop(self._service_id(project.id))
        if status.state == ServiceState.ERROR:
            return OperationResult(False, status.message, {"state": status.to_dict()})
        self.node_project_service.update_project(project.id, status=NodeProjectStatus.STOPPED)
        return OperationResult(True, status.message, {"state": status.to_dict()})

    def restart(self, project_id: str) -> OperationResult:
        stopped = self.stop(project_id)
        if not stopped.success:
            return stopped
        return self.start(project_id)

    def install_dependencies(self, project_id: str) -> OperationResult:
        project = self._project(project_id)
        if project is None:
            return OperationResult(False, "Project not found.")
        install_result = self._ensure_dependencies(project)
        if install_result.success and install_result.message == "Dependencies ready.":
            return OperationResult(True, "Dependencies already installed.")
        return install_result

    def read_log_tail(self, project_id: str, lines: int = 120) -> str:
        path = self.log_path(project_id)
        if not path.exists():
            return ""
        return "\n".join(path.read_text(encoding="utf-8", errors="replace").splitlines()[-lines:])

    def log_path(self, project_id: str) -> Path:
        path = self.binary_locator.runtime_paths.logs_dir / "node-projects" / project_id / "node-project.log"
        path.parent.mkdir(parents=True, exist_ok=True)
        return path

    def _service_id(self, project_id: str) -> str:
        return f"node-project-{project_id}"

    def _project(self, project_id: str) -> NodeProject | None:
        return self.node_project_service.repository.get(project_id.strip())

    def _service_definition(self, project: NodeProject) -> ServiceDefinition:
        binaries = self.binary_locator.node_binary_paths(project.node_version)
        if binaries is None:
            raise ValueError(f"Node runtime {project.node_version} was not found.")
        bin_dir = binaries["bin_dir"]
        npm_path = binaries["npm"]
        script_name = project.run_script_name
        command = (
            f'export PATH="{bin_dir}:$PATH"; '
            f'export PORT="{project.port}"; '
            f'"{npm_path}" run {script_name}'
        )
        return ServiceDefinition(
            id=self._service_id(project.id),
            name=f"Node Project {project.name}",
            kind=ServiceKind.PHP_FPM,
            executable_name="sh",
            default_port=project.port,
            executable_path="/bin/sh",
            arguments=["-lc", command],
            working_directory=project.project_path,
            log_path=str(self.log_path(project.id)),
            log_to_screen=False,
        )

    def _ensure_dependencies(self, project: NodeProject) -> OperationResult:
        project_root = Path(project.project_path)
        package_json = project_root / "package.json"
        if not package_json.exists():
            return OperationResult(False, "package.json not found.")
        node_modules = project_root / "node_modules"
        if node_modules.exists():
            return OperationResult(True, "Dependencies ready.")

        binaries = self.binary_locator.node_binary_paths(project.node_version)
        if binaries is None:
            return OperationResult(False, f"Node runtime {project.node_version} was not found.")
        npm_path = binaries["npm"]
        has_lock = (project_root / "package-lock.json").exists()
        install_args = ["ci"] if has_lock else ["install"]
        log_path = self.log_path(project.id)
        env = os.environ.copy()
        env["PATH"] = f"{binaries['bin_dir']}:{env.get('PATH', '')}"
        try:
            with open(log_path, "a", encoding="utf-8") as handle:
                handle.write(f"$ {npm_path} {' '.join(install_args)}\n")
                result = subprocess.run(
                    [str(npm_path), *install_args],
                    cwd=str(project_root),
                    env=env,
                    stdout=handle,
                    stderr=subprocess.STDOUT,
                    text=True,
                    check=False,
                )
            if result.returncode != 0:
                return OperationResult(False, "Dependency install failed. See service log.")
            return OperationResult(True, "Dependencies installed.")
        except Exception as exc:
            return OperationResult(False, str(exc))

    def _port_in_use(self, port: int) -> bool:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.1)
            return sock.connect_ex(("127.0.0.1", port)) == 0
