from ._shared import *


class NodeProjectsPageMixin(DashboardBridgeSignals):
    @Property("QVariantList", notify=dataChanged)
    def nodeProjectItems(self) -> list[dict[str, str]]:
        items: list[dict[str, str]] = []
        for project in self._container.node_project_service.list_projects():
            items.append(self._node_project_payload(project))
        return items

    @Slot(str, result="QVariantMap")
    def nodeProjectDetails(self, project_id: str) -> dict[str, str]:
        project = self._container.node_project_service.repository.get(project_id.strip())
        if project is None:
            return {}
        return self._node_project_payload(project)

    def _node_project_payload(self, project) -> dict[str, str]:
        web_port = self._container.settings_service.get_settings().apache_port
        status_text = "Stopped"
        pid_value: int | None = None
        try:
            state = self._container.node_project_runtime_service.status(project.id)
            status_text = state.state.value.title()
            pid_value = state.pid
        except Exception:
            status_text = "Error"
        cpu, ram = self._process_usage(pid_value)
        browse_url = f"http://{project.local_domain}"
        if web_port != 80:
            browse_url += f":{web_port}"
        cert_path, key_path = self._container.config_service.node_project_ssl_paths(project)
        return {
            "id": project.id,
            "name": project.name,
            "domain": project.local_domain,
            "status": status_text,
            "pid": str(pid_value) if pid_value else "-",
            "cpu": cpu,
            "ram": ram,
            "document_root": project.document_root,
            "node_version": project.node_version,
            "note": project.notes,
            "ssl": "On" if project.ssl_enabled else "Off",
            "ssl_enabled": bool(project.ssl_enabled),
            "ssl_enforce_tls": bool(project.ssl_enforce_tls),
            "ssl_allow_http": bool(project.ssl_allow_http),
            "ssl_certificate_path": str(cert_path),
            "ssl_key_path": str(key_path),
            "ssl_certificate_exists": self._container.config_service.node_project_ssl_exists(project),
            "run_script_name": project.run_script_name,
            "run_script_command": project.run_script_command,
            "port": str(project.port),
            "project_path": project.project_path,
            "browse_url": browse_url,
        }

    def _write_node_project_configs(self) -> None:
        settings = self._container.settings_service.get_settings()
        sites = self._container.site_service.list_sites()
        node_projects = self._container.node_project_service.list_projects()
        proxies = self._container.proxy_service.list_proxies()
        if settings.active_web_server == settings.active_web_server.NGINX:
            self._container.config_service.write_nginx_stack_config(
                sites,
                node_projects=node_projects,
                proxies=proxies,
                port=settings.apache_port,
            )
        else:
            self._container.config_service.write_apache_stack_config(
                sites,
                node_projects=node_projects,
                proxies=proxies,
                port=settings.apache_port,
            )

    @Property(bool, notify=actionStateChanged)
    def nodeProjectModulesBusy(self) -> bool:
        return self._node_project_modules_busy

    @Property(bool, notify=dataChanged)
    def nodeProjectModulesLoaded(self) -> bool:
        return self._node_project_modules_loaded

    @Property(bool, notify=dataChanged)
    def nodeProjectModulesHasNodeModules(self) -> bool:
        return self._node_project_modules_has_node_modules

    @Property(str, notify=dataChanged)
    def nodeProjectModulesProjectId(self) -> str:
        return self._node_project_modules_project_id

    @Property("QVariantList", notify=dataChanged)
    def nodeProjectModulesItems(self) -> list[dict[str, str]]:
        return [dict(item) for item in self._node_project_modules_items]

    @Property(str, notify=operationFeedbackChanged)
    def nodeProjectModulesMessage(self) -> str:
        return self._node_project_modules_message

    @Property(bool, notify=operationFeedbackChanged)
    def nodeProjectModulesError(self) -> bool:
        return self._node_project_modules_error

    @Slot(str, result=bool)
    def uninstallNodeRuntime(self, home_path: str) -> bool:
        try:
            target = Path(home_path).expanduser().resolve()
            deployed_root = self._container.binary_locator.deployed_node_root().resolve()
            if deployed_root not in target.parents:
                raise ValueError("Only installed Node runtimes can be removed here.")
            if not target.exists() or not target.is_dir():
                raise ValueError("Node runtime path does not exist.")
            shutil.rmtree(target)
            current = self._container.settings_service.get_settings()
            selected = (current.active_node_version or "").strip()
            if selected and target.name.removeprefix("node") == selected:
                self._container.settings_service.save_settings(self._copy_settings(current, active_node_version=None))
            self._app_settings_message = f"Removed Node runtime: {target.name}"
            self._app_settings_error = False
            self.appSettingsFeedbackChanged.emit()
            self.dataChanged.emit()
            return True
        except Exception as exc:
            self._app_settings_message = str(exc)
            self._app_settings_error = True
            self.appSettingsFeedbackChanged.emit()
            return False

    @Slot(str, result=bool)
    def installNodeRuntimeMajor(self, major: str) -> bool:
        try:
            if self._node_install_busy:
                raise ValueError("Node install is already running.")
            cleaned = major.strip()
            if not cleaned.isdigit():
                raise ValueError("Node major version must be numeric.")
            script_path = self._container.binary_locator.project_root / "scripts" / "install_node_runtime.sh"
            if not script_path.exists():
                raise ValueError(f"Installer script not found: {script_path}")
            install_args = [str(script_path), "--major", cleaned, "--overwrite"]
            process = QProcess(self)
            process.setProgram("bash")
            process.setArguments(install_args)
            process.setWorkingDirectory(str(self._container.binary_locator.project_root))
            process.setProcessChannelMode(QProcess.MergedChannels)
            process.readyReadStandardOutput.connect(self._on_node_install_stdout)
            process.finished.connect(self._on_node_install_finished)
            process.errorOccurred.connect(self._on_node_install_error)
            self._node_install_process = process
            self._node_install_busy = True
            self._node_install_progress = 5
            self._node_install_log = f"Installing Node major {cleaned}...\n"
            self._app_settings_message = "Installing Node runtime..."
            self._app_settings_error = False
            self.actionStateChanged.emit()
            self.appSettingsFeedbackChanged.emit()
            process.start()
            return True
        except Exception as exc:
            self._app_settings_message = str(exc)
            self._app_settings_error = True
            self.appSettingsFeedbackChanged.emit()
            return False

    @Slot()
    def clearNodeInstallLog(self) -> None:
        if self._node_install_busy:
            return
        self._node_install_log = ""
        self._node_install_progress = 0
        self.appSettingsFeedbackChanged.emit()

    @Slot()
    def _on_node_install_stdout(self) -> None:
        if self._node_install_process is None:
            return
        chunk = bytes(self._node_install_process.readAllStandardOutput()).decode("utf-8", "replace")
        if not chunk:
            return
        self._append_node_install_log_chunk(chunk)
        self._update_node_install_progress_from_log()
        self.appSettingsFeedbackChanged.emit()

    @Slot()
    def _on_node_install_stderr(self) -> None:
        if self._node_install_process is None:
            return
        chunk = bytes(self._node_install_process.readAllStandardError()).decode("utf-8", "replace")
        if not chunk:
            return
        self._append_node_install_log_chunk(chunk)
        self._update_node_install_progress_from_log()
        self.appSettingsFeedbackChanged.emit()

    def _append_node_install_log_chunk(self, chunk: str) -> None:
        # Normalize progress output and collapse repeated adjacent lines.
        normalized = chunk.replace("\r\n", "\n").replace("\r", "\n")
        existing_lines = self._node_install_log.splitlines()
        incoming_lines = normalized.split("\n")
        merged_lines = list(existing_lines)
        last_progress_key = ""
        if merged_lines:
            last_progress_key = self._node_progress_line_key(merged_lines[-1])
        for line in incoming_lines:
            if line == "":
                continue
            cleaned_line = re.sub(r"\s+", " ", line).strip()
            if not cleaned_line:
                continue
            progress_key = self._node_progress_line_key(cleaned_line)
            if progress_key and progress_key == last_progress_key:
                continue
            if merged_lines and re.sub(r"\s+", " ", merged_lines[-1]).strip() == cleaned_line:
                continue
            merged_lines.append(cleaned_line)
            if progress_key:
                last_progress_key = progress_key
        self._node_install_log = "\n".join(merged_lines)
        if self._node_install_log and not self._node_install_log.endswith("\n"):
            self._node_install_log += "\n"

    def _node_progress_line_key(self, line: str) -> str:
        match = re.search(r"(node\s+[0-9]+\.[0-9]+\.[0-9]+.*?major\s+[0-9]+).*?([0-9]{1,3})%", line.lower())
        if not match:
            return ""
        return f"{match.group(1)}::{match.group(2)}"

    @Slot(int, QProcess.ExitStatus)
    def _on_node_install_finished(self, exit_code: int, _exit_status: QProcess.ExitStatus) -> None:
        success = exit_code == 0
        self._node_install_busy = False
        self._node_install_progress = 100 if success else 0
        if success:
            try:
                node_roots = [
                    self._container.binary_locator.deployed_node_root(),
                ]
                for node_root in node_roots:
                    if node_root.exists():
                        self._clear_quarantine_tree(node_root)
                self._container.runtime_inventory_service.clear_and_rebuild("node")
            except Exception:
                pass
            self._app_settings_message = "Node runtime install completed."
            self._app_settings_error = False
            self._stack_feedback_message = "Node runtime installed successfully."
            self._stack_feedback_error = False
            self.dataChanged.emit()
            self.stackFeedbackChanged.emit()
        else:
            self._app_settings_message = f"Node install failed with exit code {exit_code}."
            self._app_settings_error = True
        self.actionStateChanged.emit()
        self.appSettingsFeedbackChanged.emit()
        self._cleanup_node_install_process()

    @Slot(QProcess.ProcessError)
    def _on_node_install_error(self, _error: QProcess.ProcessError) -> None:
        if not self._node_install_busy:
            return
        self._node_install_busy = False
        self._node_install_progress = 0
        self._app_settings_message = "Failed to start Node installer process."
        self._app_settings_error = True
        self.actionStateChanged.emit()
        self.appSettingsFeedbackChanged.emit()
        self._cleanup_node_install_process()

    def _cleanup_node_install_process(self) -> None:
        if self._node_install_process is None:
            return
        self._node_install_process.deleteLater()
        self._node_install_process = None

    def _update_node_install_progress_from_log(self) -> None:
        text = self._node_install_log.lower()
        progress = self._node_install_progress
        for match in re.finditer(r"(?:downloading node|download progress)[^\n]*?(\d{1,3})%", text):
            try:
                pct = int(match.group(1))
            except Exception:
                continue
            if 0 <= pct <= 100:
                progress = max(progress, min(70, 20 + int(pct * 0.5)))
        if "fetching node.js release index" in text:
            progress = max(progress, 15)
        if "installing node" in text:
            progress = max(progress, 35)
        if "extracting" in text or "staging" in text:
            progress = max(progress, 65)
        if "deployed runtime" in text:
            progress = max(progress, 85)
        if "installation complete" in text or "installed runtimes" in text:
            progress = max(progress, 95)
        self._node_install_progress = min(progress, 95)

    @Property(bool, notify=actionStateChanged)
    def nodeInstallBusy(self) -> bool:
        return self._node_install_busy

    @Property(bool, notify=actionStateChanged)
    def nodeProjectRuntimeActionBusy(self) -> bool:
        return self._node_project_runtime_action_busy

    @Property(bool, notify=actionStateChanged)
    def nodeProjectSaveBusy(self) -> bool:
        return self._node_project_save_busy

    @Property(str, notify=operationFeedbackChanged)
    def nodeProjectSaveStatus(self) -> str:
        return self._last_operation_message

    @Slot(int, result=int)
    def nextAvailableNodePort(self, starting_port: int) -> int:
        port = max(1, int(starting_port or 3000))
        while port <= 65535:
            if not self._node_port_in_use(port) and not any(
                int(project.port) == port for project in self._container.node_project_service.list_projects()
            ):
                return port
            port += 1
        return max(1, int(starting_port or 3000))

    @Slot()
    def cancelNodeProjectSave(self) -> None:
        worker = self._node_project_save_worker
        if worker is not None:
            worker.request_cancel()

    def _node_port_in_use(self, port: int) -> bool:
        import socket
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.05)
            return sock.connect_ex(("127.0.0.1", port)) == 0

    @Property(int, notify=appSettingsFeedbackChanged)
    def nodeInstallProgress(self) -> int:
        return self._node_install_progress

    @Property(str, notify=appSettingsFeedbackChanged)
    def nodeInstallLog(self) -> str:
        return self._node_install_log

    @Slot("QVariantMap", result=bool)
    def saveNodeProject(self, payload: dict) -> bool:
        try:
            project_id = str(payload.get("id", "")).strip()
            local_domain = str(payload.get("local_domain", "")).strip().lower()
            project_path = str(payload.get("project_path", "")).strip()
            node_version = str(payload.get("node_version", "")).strip()
            run_script_name = str(payload.get("run_script_name", "")).strip()
            run_script_command = str(payload.get("run_script_command", "")).strip()
            notes = str(payload.get("notes", "")).strip()
            ssl_enabled = bool(payload.get("ssl_enabled", False))
            ssl_enforce_tls = bool(payload.get("ssl_enforce_tls", False))
            ssl_allow_http = bool(payload.get("ssl_allow_http", True))
            port = int(str(payload.get("port", "0")).strip() or "0")
            if not local_domain:
                raise ValueError("Domain is required.")
            if not project_path:
                raise ValueError("Project path is required.")
            if not node_version:
                raise ValueError("Node version is required.")
            if not run_script_name or not run_script_command:
                raise ValueError("Run option is required.")
            if port < 1 or port > 65535:
                raise ValueError("Port must be between 1 and 65535.")

            name = str(payload.get("name", "")).strip() or local_domain.split(".")[0]
            if project_id:
                project = self._container.node_project_service.update_project(
                    project_id,
                    name=name,
                    local_domain=local_domain,
                    project_path=project_path,
                    document_root=project_path,
                    node_version=node_version,
                    run_script_name=run_script_name,
                    run_script_command=run_script_command,
                    port=port,
                    notes=notes,
                    ssl_enabled=ssl_enabled,
                    ssl_enforce_tls=ssl_enforce_tls,
                    ssl_allow_http=ssl_allow_http,
                )
                self._last_operation_message = f"Updated Node project: {local_domain}"
            else:
                project = self._container.node_project_service.create_project(
                    name=name,
                    local_domain=local_domain,
                    project_path=project_path,
                    document_root=project_path,
                    node_version=node_version,
                    run_script_name=run_script_name,
                    run_script_command=run_script_command,
                    port=port,
                    notes=notes,
                    ssl_enabled=ssl_enabled,
                    ssl_enforce_tls=ssl_enforce_tls,
                    ssl_allow_http=ssl_allow_http,
                )
                self._last_operation_message = f"Created Node project: {local_domain}"
            if ssl_enabled:
                cert_result = self._container.config_service.ensure_node_project_ssl_certificate(project)
                if not cert_result.success:
                    self._container.node_project_service.update_project(project.id, ssl_enabled=False)
                    raise ValueError(cert_result.message)
            self._write_node_project_configs()
            self._reload_active_web_server_for_routes()
            self._last_operation_error = False
            self.dataChanged.emit()
            self.operationFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False

    @Slot("QVariantMap", result=bool)
    def saveNodeProjectAsync(self, payload: dict) -> bool:
        return self._start_node_project_save(payload)

    @Slot(str, bool, bool, bool, result=bool)
    def updateNodeProjectSslSettings(self, project_id: str, ssl_enabled: bool, ssl_enforce_tls: bool, ssl_allow_http: bool) -> bool:
        try:
            project = self._container.node_project_service.update_project(
                project_id.strip(),
                ssl_enabled=bool(ssl_enabled),
                ssl_enforce_tls=bool(ssl_enforce_tls),
                ssl_allow_http=bool(ssl_allow_http),
            )
            if ssl_enabled:
                cert_result = self._container.config_service.ensure_node_project_ssl_certificate(project)
                if not cert_result.success:
                    self._container.node_project_service.update_project(project.id, ssl_enabled=False)
                    raise ValueError(cert_result.message)
            self._write_node_project_configs()
            self._reload_active_web_server_for_routes()
            self._last_operation_message = f"Updated SSL settings for {project.local_domain}. Web server reloaded."
            self._last_operation_error = False
            self.dataChanged.emit()
            self.operationFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False

    @Slot(str, result=bool)
    def createNodeProjectSelfSignedCertificate(self, project_id: str) -> bool:
        try:
            project = self._container.node_project_service.repository.get(project_id.strip())
            if project is None:
                raise ValueError("Node project not found.")
            result = self._container.config_service.ensure_node_project_ssl_certificate(project)
            if not result.success:
                raise ValueError(result.message)
            self._last_operation_message = result.message
            self._last_operation_error = False
            self.dataChanged.emit()
            self.operationFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False

    @Slot(str, result=bool)
    def trustNodeProjectCertificate(self, project_id: str) -> bool:
        try:
            project = self._container.node_project_service.repository.get(project_id.strip())
            if project is None:
                raise ValueError("Node project not found.")
            cert_path, _ = self._container.config_service.node_project_ssl_paths(project)
            if not cert_path.exists():
                raise ValueError("Certificate file does not exist. Generate certificate first.")
            if sys.platform != "darwin":
                raise ValueError("Certificate trust is only supported on macOS.")
            security_bin = shutil.which("security") or "/usr/bin/security"
            login_keychain = str(Path.home() / "Library" / "Keychains" / "login.keychain-db")
            completed = subprocess.run(
                [
                    security_bin,
                    "add-trusted-cert",
                    "-d",
                    "-r",
                    "trustRoot",
                    "-k",
                    login_keychain,
                    str(cert_path),
                ],
                capture_output=True,
                text=True,
            )
            if completed.returncode != 0:
                detail = (completed.stderr or completed.stdout or "Certificate trust failed.").strip()
                raise ValueError(f"{detail} Try adding the certificate to your login keychain manually.")
            self._last_operation_message = f"Trusted SSL certificate for {project.local_domain}"
            self._last_operation_error = False
            self.operationFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False

    @Slot(str, result=bool)
    def deleteNodeProject(self, project_id: str) -> bool:
        try:
            self._container.node_project_runtime_service.stop(project_id.strip())
            deleted = self._container.node_project_service.delete_project(project_id.strip())
            if not deleted:
                raise ValueError("Node project not found.")
            self._reload_active_web_server_for_routes()
            self._last_operation_message = "Node project deleted."
            self._last_operation_error = False
            self.dataChanged.emit()
            self.operationFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False

    @Property(str, notify=operationFeedbackChanged)
    def nodeProjectRuntimeMessage(self) -> str:
        return self._node_project_runtime_message

    @Property(bool, notify=operationFeedbackChanged)
    def nodeProjectRuntimeError(self) -> bool:
        return self._node_project_runtime_error

    @Slot(str, result="QVariantMap")
    def nodeProjectServiceState(self, project_id: str) -> dict:
        try:
            status = self._container.node_project_runtime_service.status(project_id.strip())
            cpu, ram = self._process_usage(status.pid)
            return {
                "state": status.state.value.title(),
                "pid": str(status.pid) if status.pid else "-",
                "cpu": cpu,
                "ram": ram,
                "port": str(status.port or ""),
                "message": status.message or "",
                "running": status.state == status.state.RUNNING,
            }
        except Exception as exc:
            return {"state": "Error", "pid": "-", "cpu": "-", "ram": "-", "port": "", "message": str(exc), "running": False}

    @Slot(str, result=str)
    def nodeProjectServiceLog(self, project_id: str) -> str:
        try:
            return self._container.node_project_runtime_service.read_log_tail(project_id.strip())
        except Exception:
            return ""

    @Slot(str, result=str)
    def nodeProjectServiceLogPath(self, project_id: str) -> str:
        try:
            path = self._container.node_project_runtime_service.log_path(project_id.strip())
            return str(path)
        except Exception:
            return ""

    @Slot(str, result=str)
    def nodeProjectResponseLogPath(self, project_id: str) -> str:
        try:
            project = self._container.node_project_service.repository.get(project_id.strip())
            if project is None:
                return ""
            settings = self._container.settings_service.get_settings()
            server = settings.active_web_server.value
            logs_dir = (
                self._container.config_service.nginx_logs_dir()
                if server == "nginx"
                else self._container.config_service.apache_logs_dir()
            )
            primary = logs_dir / f"{project.id}-access.log"
            ssl_variant = logs_dir / f"{project.id}-ssl-access.log"
            if primary.exists():
                return str(primary)
            if ssl_variant.exists():
                return str(ssl_variant)
            return str(primary)
        except Exception:
            return ""

    @Slot(str, int, result=str)
    def nodeProjectResponseLogContent(self, project_id: str, lines: int) -> str:
        try:
            cleaned_lines = max(1, min(int(lines), 2000))
            project = self._container.node_project_service.repository.get(project_id.strip())
            if project is None:
                return ""
            settings = self._container.settings_service.get_settings()
            server = settings.active_web_server.value
            logs_dir = (
                self._container.config_service.nginx_logs_dir()
                if server == "nginx"
                else self._container.config_service.apache_logs_dir()
            )
            primary = logs_dir / f"{project.id}-access.log"
            ssl_variant = logs_dir / f"{project.id}-ssl-access.log"
            candidates = [candidate for candidate in (primary, ssl_variant) if candidate.exists()]
            if not candidates:
                return f"Log file not found yet: {primary}"
            rows: list[str] = []
            for path in candidates:
                rows.extend(path.read_text(encoding="utf-8", errors="replace").splitlines())
            return "\n".join(rows[-cleaned_lines:])
        except Exception as exc:
            return f"Unable to load log: {exc}"

    @Slot(str, result=bool)
    def requestNodeProjectModulesAsync(self, project_id: str) -> bool:
        return self._start_node_project_modules_load(project_id, force=False)

    @Slot(str, result=bool)
    def reloadNodeProjectModulesAsync(self, project_id: str) -> bool:
        return self._start_node_project_modules_load(project_id, force=True)

    @Slot(str, result=bool)
    def installNodeProjectDependenciesAsync(self, project_id: str) -> bool:
        cleaned_project_id = project_id.strip()
        if self._node_project_modules_busy:
            self._last_operation_message = "Node project modules are already busy."
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False
        if not cleaned_project_id:
            self._last_operation_message = "Project id is required."
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False
        self._node_project_modules_busy = True
        self.actionStateChanged.emit()
        self._node_project_modules_message = "Installing Node dependencies..."
        self._node_project_modules_error = False
        self.operationFeedbackChanged.emit()
        thread = QThread(self)
        worker = NodeProjectInstallDependenciesWorker(self._container, cleaned_project_id)
        worker.moveToThread(thread)
        worker.completed.connect(lambda success, message: self._on_node_project_dependencies_install_completed(cleaned_project_id, success, message))
        worker.completed.connect(thread.quit)
        thread.started.connect(worker.run)
        thread.finished.connect(worker.deleteLater)
        thread.finished.connect(thread.deleteLater)
        self._node_project_modules_install_thread = thread
        self._node_project_modules_install_worker = worker
        thread.start()
        return True

    def _start_node_project_modules_load(self, project_id: str, force: bool) -> bool:
        cleaned_project_id = project_id.strip()
        if self._node_project_modules_busy:
            self._last_operation_message = "Node project modules are already loading."
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False
        if not cleaned_project_id:
            self._last_operation_message = "Project id is required."
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False
        if not force and self._node_project_modules_loaded and self._node_project_modules_project_id == cleaned_project_id:
            return True
        self._node_project_modules_busy = True
        self.actionStateChanged.emit()
        self._node_project_modules_project_id = cleaned_project_id
        self._node_project_modules_loaded = False
        self._node_project_modules_has_node_modules = False
        self._node_project_modules_items = []
        self._node_project_modules_message = "Loading modules..."
        self._node_project_modules_error = False
        self.dataChanged.emit()
        self.operationFeedbackChanged.emit()
        thread = QThread(self)
        worker = NodeProjectModulesWorker(self._container, cleaned_project_id)
        worker.moveToThread(thread)
        worker.completed.connect(self._on_node_project_modules_completed)
        worker.completed.connect(thread.quit)
        thread.started.connect(worker.run)
        thread.finished.connect(worker.deleteLater)
        thread.finished.connect(thread.deleteLater)
        self._node_project_modules_thread = thread
        self._node_project_modules_worker = worker
        thread.start()
        return True

    @Slot(bool, str, "QVariantList", bool)
    def _on_node_project_modules_completed(self, success: bool, message: str, items: list[dict[str, str]], has_node_modules: bool) -> None:
        self._node_project_modules_busy = False
        self._node_project_modules_loaded = True
        self._node_project_modules_has_node_modules = bool(has_node_modules)
        self._node_project_modules_items = [dict(item) for item in items]
        self._node_project_modules_message = message
        self._node_project_modules_error = not success
        if not success:
            self._last_operation_message = message
            self._last_operation_error = True
        self.dataChanged.emit()
        self.operationFeedbackChanged.emit()
        self.actionStateChanged.emit()

    @Slot(str, bool, str)
    def _on_node_project_dependencies_install_completed(self, project_id: str, success: bool, message: str) -> None:
        self._node_project_modules_busy = False
        self._node_project_modules_message = message
        self._node_project_modules_error = not success
        self._last_operation_message = message
        self._last_operation_error = not success
        self.operationFeedbackChanged.emit()
        self.actionStateChanged.emit()
        if success:
            self._start_node_project_modules_load(project_id, force=True)

    def _start_node_project_runtime_action(self, action: str, project_id: str) -> bool:
        if self._node_project_runtime_action_busy:
            self._node_project_runtime_message = "Node runtime action already running."
            self._node_project_runtime_error = True
            self._last_operation_message = self._node_project_runtime_message
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False
        cleaned_project_id = project_id.strip()
        if not cleaned_project_id:
            self._node_project_runtime_message = "Project id is required."
            self._node_project_runtime_error = True
            self._last_operation_message = self._node_project_runtime_message
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False
        self._node_project_runtime_action_busy = True
        self.actionStateChanged.emit()
        thread = QThread(self)
        worker = NodeProjectRuntimeActionWorker(self._container, action, cleaned_project_id)
        worker.moveToThread(thread)
        worker.completed.connect(self._on_node_project_runtime_action_completed)
        worker.completed.connect(thread.quit)
        thread.started.connect(worker.run)
        thread.finished.connect(worker.deleteLater)
        thread.finished.connect(thread.deleteLater)
        self._node_project_runtime_thread = thread
        self._node_project_runtime_worker = worker
        thread.start()
        return True

    @Slot(bool, str)
    def _on_node_project_runtime_action_completed(self, success: bool, message: str) -> None:
        self._node_project_runtime_action_busy = False
        self._node_project_runtime_message = message
        self._node_project_runtime_error = not success
        self._last_operation_message = message
        self._last_operation_error = not success
        self.dataChanged.emit()
        self.operationFeedbackChanged.emit()
        self.actionStateChanged.emit()
        self.nodeProjectRuntimeActionCompleted.emit(bool(success))

    def _start_node_project_save(self, payload: dict) -> bool:
        if self._node_project_save_busy:
            self._last_operation_message = "Node project save already running."
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False
        self._node_project_save_busy = True
        self.actionStateChanged.emit()
        thread = QThread(self)
        worker = NodeProjectSaveWorker(self._container, payload)
        worker.moveToThread(thread)
        worker.progress.connect(self._on_node_project_save_progress)
        worker.completed.connect(self._on_node_project_save_completed)
        worker.completed.connect(thread.quit)
        thread.started.connect(worker.run)
        thread.finished.connect(worker.deleteLater)
        thread.finished.connect(thread.deleteLater)
        self._node_project_save_thread = thread
        self._node_project_save_worker = worker
        thread.start()
        return True

    @Slot(int, str)
    def _on_node_project_save_progress(self, progress: int, message: str) -> None:
        self._last_operation_message = str(message or "")
        self.operationFeedbackChanged.emit()
        self.nodeProjectSaveProgressChanged.emit(int(progress), str(message or ""))

    @Slot(bool, str)
    def _on_node_project_save_completed(self, success: bool, message: str) -> None:
        self._node_project_save_busy = False
        self._last_operation_message = message
        self._last_operation_error = not success
        self.dataChanged.emit()
        self.operationFeedbackChanged.emit()
        self.actionStateChanged.emit()
        self.nodeProjectSaveCompleted.emit(bool(success))

    @Slot(str, result=bool)
    def startNodeProjectRuntime(self, project_id: str) -> bool:
        result = self._container.node_project_runtime_service.start(project_id.strip())
        self._node_project_runtime_message = result.message
        self._node_project_runtime_error = not result.success
        self.dataChanged.emit()
        self.operationFeedbackChanged.emit()
        return result.success

    @Slot(str, result=bool)
    def startNodeProjectRuntimeAsync(self, project_id: str) -> bool:
        return self._start_node_project_runtime_action("start", project_id)

    @Slot(str, result=bool)
    def stopNodeProjectRuntime(self, project_id: str) -> bool:
        result = self._container.node_project_runtime_service.stop(project_id.strip())
        self._node_project_runtime_message = result.message
        self._node_project_runtime_error = not result.success
        self.dataChanged.emit()
        self.operationFeedbackChanged.emit()
        return result.success

    @Slot(str, result=bool)
    def stopNodeProjectRuntimeAsync(self, project_id: str) -> bool:
        return self._start_node_project_runtime_action("stop", project_id)

    @Slot(str, result=bool)
    def restartNodeProjectRuntime(self, project_id: str) -> bool:
        result = self._container.node_project_runtime_service.restart(project_id.strip())
        self._node_project_runtime_message = result.message
        self._node_project_runtime_error = not result.success
        self.dataChanged.emit()
        self.operationFeedbackChanged.emit()
        return result.success

    @Slot(str, result=bool)
    def restartNodeProjectRuntimeAsync(self, project_id: str) -> bool:
        return self._start_node_project_runtime_action("restart", project_id)

    @Slot(str, result="QVariantMap")
    def inspectNodeProject(self, project_path: str) -> dict:
        cleaned = project_path.strip()
        if not cleaned:
            return {
                "valid": False,
                "message": "Project path is required.",
                "port": "",
                "script": "",
                "script_name": "",
                "scripts": [],
            }
        try:
            root = Path(cleaned).expanduser()
            if not root.exists() or not root.is_dir():
                return {
                    "valid": False,
                    "message": "Project path does not exist or is not a directory.",
                    "port": "",
                    "script": "",
                    "script_name": "",
                    "scripts": [],
                }
            package_json_path = root / "package.json"
            if not package_json_path.exists():
                return {
                    "valid": False,
                    "message": "package.json not found. This is not a Node project.",
                    "port": "",
                    "script": "",
                    "script_name": "",
                    "scripts": [],
                }
            payload = json.loads(package_json_path.read_text(encoding="utf-8"))
            scripts = payload.get("scripts", {}) if isinstance(payload, dict) else {}
            if not isinstance(scripts, dict):
                scripts = {}
            env_port = self._detect_node_project_port(root, "")
            script_entries: list[dict[str, str]] = []
            for key, value in scripts.items():
                if not isinstance(value, str) or not value.strip():
                    continue
                command = value.strip()
                detected_port = self._detect_node_project_port(root, command)
                script_entries.append(
                    {
                        "name": str(key),
                        "command": command,
                        "label": f"{key}: {command}",
                        "port": str(detected_port if detected_port > 0 else env_port),
                    }
                )
            if not script_entries:
                return {
                    "valid": False,
                    "message": "No scripts found in package.json.",
                    "port": "",
                    "script": "",
                    "script_name": "",
                    "scripts": [],
                }
            preferred = ["dev", "start", "serve"]
            script_entries.sort(key=lambda item: (preferred.index(item["name"]) if item["name"] in preferred else 99, item["name"]))
            selected = script_entries[0]
            selected_port = int(selected.get("port") or "0")
            port = selected_port if selected_port > 0 else env_port
            if port <= 0:
                port = 3000
            return {
                "valid": True,
                "message": "Node project detected.",
                "port": str(port),
                "script": selected.get("command", ""),
                "script_name": selected.get("name", ""),
                "scripts": script_entries,
            }
        except json.JSONDecodeError:
            return {
                "valid": False,
                "message": "Invalid package.json JSON format.",
                "port": "",
                "script": "",
                "script_name": "",
                "scripts": [],
            }
        except Exception as exc:
            return {
                "valid": False,
                "message": str(exc),
                "port": "",
                "script": "",
                "script_name": "",
                "scripts": [],
            }

    def _detect_node_project_port(self, root: Path, command: str) -> int:
        env_candidates = [root / ".env", root / ".env.local", root / ".env.development"]
        env_pattern = re.compile(r'^\s*(?:export\s+)?PORT\s*=\s*"?([0-9]{2,5})"?\s*$')
        for env_path in env_candidates:
            if not env_path.exists():
                continue
            for line in env_path.read_text(encoding="utf-8", errors="ignore").splitlines():
                match = env_pattern.match(line.strip())
                if match:
                    return int(match.group(1))

        script_patterns = [
            r"(?:--port|-p)\s+([0-9]{2,5})",
            r"--port=([0-9]{2,5})",
            r"-p([0-9]{2,5})",
            r"PORT=([0-9]{2,5})",
        ]
        for pattern in script_patterns:
            match = re.search(pattern, command)
            if match:
                return int(match.group(1))
        return 3000 if command else 0
