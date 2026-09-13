from ._shared import *


class HomeStackServicesMixin(DashboardBridgeSignals):
    @Property("QVariantList", notify=homeServiceChanged)
    def homeServiceItems(self) -> list[dict[str, object]]:
        if not hasattr(self, "_home_service_items_cache") or not self._home_service_items_cache:
            self._refresh_home_service_items_cache()
        return list(self._home_service_items_cache)

    def _refresh_home_service_items_cache(self) -> None:
        settings = self._container.settings_service.get_settings()
        stack_status = self._container.stack_service.status()
        stack_by_id = {service.service_id: service for service in stack_status.services}
        if settings.active_web_server == settings.active_web_server.APACHE:
            web_id = "apache"
            web_state = stack_by_id.get(web_id)
        else:
            web_id = "nginx"
            web_state = stack_by_id.get(web_id)
        database_state = self._container.database_service.status()
        redis_state = self._container.redis_service.status()
        redis_runtime = self._container.redis_service.active_runtime()
        memcached_state = self._container.memcached_service.status()
        memcached_runtime = self._container.memcached_service.active_runtime()
        mailpit_state = self._container.mailpit_service.status()
        items = [
            {
                "id": "web",
                "title": "Server",
                "label": self.currentWebServerLabel,
                "status": (web_state.state.value.title() if web_state else "Stopped"),
                "detail": f"Port {settings.apache_port}",
                "running": bool(web_state and web_state.state.value == "running"),
                "busy": self._stack_action_busy,
            },
            {
                "id": "database",
                "title": "Database",
                "label": self.activeDatabaseRuntimeLabel,
                "status": database_state.state.value.title(),
                "detail": f"Port {settings.database_port}",
                "running": database_state.state.value == "running",
                "busy": self._database_action_busy,
            },
            {
                "id": "redis",
                "title": "Redis",
                "label": f"Redis {redis_runtime.version}" if redis_runtime is not None else "No runtime selected",
                "status": redis_state.state.value.title(),
                "detail": f"Port {settings.redis_port}",
                "running": redis_state.state.value == "running",
                "busy": self._redis_action_busy,
            },
            {
                "id": "memcached",
                "title": "Memcached",
                "label": f"Memcached {memcached_runtime.version}" if memcached_runtime is not None else "No runtime selected",
                "status": memcached_state.state.value.title(),
                "detail": f"Port {self._container.memcached_service.port()}",
                "running": memcached_state.state.value == "running",
                "busy": self._memcached_action_busy,
            },
            {
                "id": "mailpit",
                "title": "Mailpit",
                "label": "SMTP",
                "status": mailpit_state.state.value.title(),
                "detail": f"Port {settings.mailpit_smtp_port} ",
                "running": mailpit_state.state.value == "running",
                "busy": self._mailpit_action_busy,
            },
        ]
        if self.optionalDatabaseRuntimeDownloaded("mongodb"):
            mongodb_state = self._container.mongodb_service.status()
            mongodb_runtime = self._container.mongodb_service.active_runtime()
            items.append(
                {
                    "id": "mongodb",
                    "title": "MongoDB",
                    "label": f"MongoDB {mongodb_runtime.version}" if mongodb_runtime is not None else "No runtime selected",
                    "status": mongodb_state.state.value.title(),
                    "detail": f"Port {self._container.mongodb_service.port}",
                    "running": mongodb_state.state.value == "running",
                    "busy": self._mongodb_action_busy,
                }
            )
        if self.optionalDatabaseRuntimeDownloaded("postgresql"):
            postgresql_state = self._container.postgresql_service.status()
            postgresql_runtime = self._container.postgresql_service.active_runtime()
            items.append(
                {
                    "id": "postgresql",
                    "title": "PostgreSQL",
                    "label": f"PostgreSQL {postgresql_runtime.version}" if postgresql_runtime is not None else "No runtime selected",
                    "status": postgresql_state.state.value.title(),
                    "detail": f"Port {self._container.postgresql_service.port}",
                    "running": postgresql_state.state.value == "running",
                    "busy": self._postgresql_action_busy,
                }
            )
        self._home_service_items_cache = items
        self._home_service_running_cache = {item["id"]: bool(item["running"]) for item in items}
        self._database_service_state_cache = database_state.state.value.title()
        self._redis_service_state_cache = redis_state.state.value.title()
        self._memcached_service_state_cache = memcached_state.state.value.title()
        self._mailpit_service_state_cache = mailpit_state.state.value.title()
        if self.optionalDatabaseRuntimeDownloaded("mongodb"):
            self._mongodb_service_state_cache = mongodb_state.state.value.title()
        if self.optionalDatabaseRuntimeDownloaded("postgresql"):
            self._postgresql_service_state_cache = postgresql_state.state.value.title()

    @Slot()
    def reloadWebRoutes(self) -> None:
        if self._web_reload_thread is not None and self._web_reload_thread.isRunning():
            return
        self._last_operation_message = "Reloading web routes..."
        self._last_operation_error = False
        self.operationFeedbackChanged.emit()
        self._start_web_route_reload()

    @Slot()
    def validateConfiguration(self) -> None:
        try:
            settings = self._container.settings_service.get_settings()
            sites = self._container.site_service.list_sites()
            node_projects = self._container.node_project_service.list_projects()
            proxies = self._container.proxy_service.list_proxies()
            self._container.config_service.apache_main_config(sites, node_projects=node_projects, proxies=proxies, port=settings.apache_port)
            self._container.config_service.nginx_main_config(sites, node_projects=node_projects, proxies=proxies, port=settings.apache_port)
            for site in sites:
                self._container.config_service.apache_virtual_host(site, port=settings.apache_port)
                self._container.config_service.nginx_server_block(site, port=settings.apache_port)
                self._container.config_service.php_fpm_pool(site)
            self._last_operation_message = "Configuration validation passed."
            self._last_operation_error = False
        except Exception as exc:
            self._last_operation_message = f"Configuration validation failed: {exc}"
            self._last_operation_error = True
        self.operationFeedbackChanged.emit()

    @Slot()
    def regenerateWebServerConfigs(self) -> None:
        try:
            settings = self._container.settings_service.get_settings()
            sites = self._container.site_service.list_sites()
            node_projects = self._container.node_project_service.list_projects()
            proxies = self._container.proxy_service.list_proxies()
            apache_path = self._container.config_service.write_apache_stack_config(
                sites,
                node_projects=node_projects,
                proxies=proxies,
                port=settings.apache_port,
            )
            nginx_path = self._container.config_service.write_nginx_stack_config(
                sites,
                node_projects=node_projects,
                proxies=proxies,
                port=settings.apache_port,
            )
            for site in sites:
                self._container.config_service.write_site_configs(site, apache_port=settings.apache_port)
            self._last_operation_message = f"Regenerated web server configs: {apache_path} | {nginx_path}"
            self._last_operation_error = False
            self.dataChanged.emit()
        except Exception as exc:
            self._last_operation_message = f"Regenerate web server configs failed: {exc}"
            self._last_operation_error = True
        self.operationFeedbackChanged.emit()

    @Slot(result=bool)
    def testApacheConfig(self) -> bool:
        try:
            command = [
                str(self._container.binary_locator.apache_httpd()),
                "-t",
                "-f",
                str(self._container.config_service.apache_main_config_path()),
                "-d",
                str(self._container.binary_locator.apache_home()),
            ]
            result = subprocess.run(command, capture_output=True, text=True, check=False)
            output = (result.stdout or "").strip()
            error = (result.stderr or "").strip()
            if result.returncode == 0:
                self._app_settings_message = ("Apache config test passed.\n" + output).strip()
                self._app_settings_error = False
            else:
                details = error or output or f"Exit code {result.returncode}"
                self._app_settings_message = "Apache config test failed.\n" + details
                self._app_settings_error = True
            self.appSettingsFeedbackChanged.emit()
            return result.returncode == 0
        except Exception as exc:
            self._app_settings_message = f"Apache config test failed: {exc}"
            self._app_settings_error = True
            self.appSettingsFeedbackChanged.emit()
            return False

    @Slot(result=bool)
    def testNginxConfig(self) -> bool:
        try:
            command = [
                str(self._container.binary_locator.nginx_binary()),
                "-t",
                "-c",
                str(self._container.config_service.nginx_main_config_path()),
                "-p",
                str(self._container.binary_locator.nginx_home()),
            ]
            result = subprocess.run(command, capture_output=True, text=True, check=False)
            output = (result.stdout or "").strip()
            error = (result.stderr or "").strip()
            if result.returncode == 0:
                message = error or output
                self._app_settings_message = ("Nginx config test passed.\n" + message).strip()
                self._app_settings_error = False
            else:
                details = error or output or f"Exit code {result.returncode}"
                self._app_settings_message = "Nginx config test failed.\n" + details
                self._app_settings_error = True
            self.appSettingsFeedbackChanged.emit()
            return result.returncode == 0
        except Exception as exc:
            self._app_settings_message = f"Nginx config test failed: {exc}"
            self._app_settings_error = True
            self.appSettingsFeedbackChanged.emit()
            return False

    @Property(str, notify=operationFeedbackChanged)
    def lastOperationMessage(self) -> str:
        return self._last_operation_message

    @Property(bool, notify=operationFeedbackChanged)
    def lastOperationError(self) -> bool:
        return self._last_operation_error

    @Property(str, notify=stackFeedbackChanged)
    def stackFeedbackMessage(self) -> str:
        return self._stack_feedback_message

    @Property(bool, notify=stackFeedbackChanged)
    def stackFeedbackError(self) -> bool:
        return self._stack_feedback_error

    @Property(bool, notify=actionStateChanged)
    def stackActionBusy(self) -> bool:
        return self._stack_action_busy

    @Property(bool, notify=actionStateChanged)
    def databaseActionBusy(self) -> bool:
        return self._database_action_busy

    @Property(bool, notify=actionStateChanged)
    def phpMyAdminBusy(self) -> bool:
        return self._phpmyadmin_busy

    @Property(bool, notify=actionStateChanged)
    def redisActionBusy(self) -> bool:
        return self._redis_action_busy

    @Property(bool, notify=actionStateChanged)
    def memcachedActionBusy(self) -> bool:
        return self._memcached_action_busy

    @Property(bool, notify=actionStateChanged)
    def mailpitActionBusy(self) -> bool:
        return self._mailpit_action_busy

    @Property(bool, notify=actionStateChanged)
    def globalStackBusy(self) -> bool:
        return self._global_action_busy

    @Property(str, notify=dataChanged)
    def globalStackActionLabel(self) -> str:
        included = self._included_home_services()
        if not included:
            return "Start"
        all_running = all(self._is_home_service_running(service_id) for service_id in included)
        return "Stop" if all_running else "Start"

    def _start_home_service_job(self, service_id: str, running: bool) -> None:
        LOGGER.debug("_start_home_service_job: service_id=%s running=%s", service_id, running)
        thread = QThread(self)
        worker = HomeServiceWorker(self._container, service_id, running)
        worker.moveToThread(thread)
        worker.completed.connect(self._on_home_service_completed)
        worker.completed.connect(thread.quit)
        thread.started.connect(worker.run)
        thread.finished.connect(worker.deleteLater)
        thread.finished.connect(thread.deleteLater)
        self._home_service_threads[service_id] = thread
        self._home_service_workers[service_id] = worker
        thread.start()

    def _defer_action_state_changed(self) -> None:
        QTimer.singleShot(0, lambda: self.actionStateChanged.emit())

    def _start_global_stack_action(self, action: str, service_ids: list[str] | None = None) -> None:
        LOGGER.debug("_start_global_stack_action: action=%s service_ids=%s busy=%s", action, service_ids, self._global_action_busy)
        if self._global_action_busy:
            return
        included = service_ids or self._included_home_services()
        if not included:
            self._stack_feedback_message = "No services selected for global actions."
            self._stack_feedback_error = True
            self.stackFeedbackChanged.emit()
            return
        actionable = included
        if action == "start":
            actionable = [service_id for service_id in included if not self._is_home_service_running(service_id)]
            if not actionable:
                self._stack_feedback_message = "All selected services are already running."
                self._stack_feedback_error = False
                self.stackFeedbackChanged.emit()
                return
        elif action == "stop":
            actionable = [service_id for service_id in included if self._is_home_service_running(service_id)]
            if not actionable:
                self._stack_feedback_message = "All selected services are already stopped."
                self._stack_feedback_error = False
                self.stackFeedbackChanged.emit()
                return
        if action in {"start", "restart"} and "web" in actionable:
            ok, error_message = self._validate_web_php_runtime_compat()
            if not ok:
                fixed, fix_message = self._prompt_and_fix_missing_site_php_runtimes()
                if not fixed:
                    self._stack_feedback_message = error_message
                    self._stack_feedback_error = True
                    self.stackFeedbackChanged.emit()
                    self._last_operation_message = error_message
                    self._last_operation_error = True
                    self.operationFeedbackChanged.emit()
                    return
                self._last_operation_message = fix_message
                self._last_operation_error = False
                self.operationFeedbackChanged.emit()
        self._global_action_busy = True
        self._global_action_mode = action
        for service_id in actionable:
            self._set_home_service_busy(service_id, True)
        self.homeServiceChanged.emit()
        thread = QThread(self)
        worker = GlobalStackWorker(self._container, action, actionable)
        worker.moveToThread(thread)
        worker.completed.connect(self._on_global_stack_action_completed)
        worker.completed.connect(thread.quit)
        thread.started.connect(worker.run)
        thread.finished.connect(worker.deleteLater)
        thread.finished.connect(thread.deleteLater)
        self._global_action_thread = thread
        self._global_action_worker = worker
        thread.start()
        self._defer_action_state_changed()

    @Slot(str, bool, str, "QVariantMap")
    def _on_home_service_completed(self, service_id: str, success: bool, message: str, payload: dict[str, object]) -> None:
        started_at = time.perf_counter()
        LOGGER.debug(
            "_on_home_service_completed: service_id=%s success=%s message=%s running=%s status=%s",
            service_id,
            success,
            message,
            payload.get("running"),
            payload.get("status"),
        )
        target_running = bool(self._home_service_targets.get(service_id, False))
        final_running = bool(payload.get("running", target_running if success else False))
        status_text = str(payload.get("status", "Running" if final_running else "Stopped"))
        log_tail = str(payload.get("log_tail", ""))
        self._set_home_service_busy(service_id, False)
        self._cleanup_home_service_job(service_id)
        LOGGER.debug("_on_home_service_completed: post-busy emit service_id=%s took=%.1fms", service_id, (time.perf_counter() - started_at) * 1000.0)
        if service_id == "web":
            action = "start" if target_running else "stop"
            if target_running and not success:
                self._maybe_open_service_port_conflict(service_id, message)
            if not success and message:
                LOGGER.error("Web server action failed: %s", message)
                self._stack_feedback_message = f"Web server action failed: {message}"
                self._stack_feedback_error = True
            elif message:
                self._stack_feedback_message = f"{action.title()} result: {message}"
                self._stack_feedback_error = False
            else:
                self._stack_feedback_message = f"{action.title()} completed."
                self._stack_feedback_error = False
            self.stackFeedbackChanged.emit()
            LOGGER.debug("_on_home_service_completed: web branch service_id=%s took=%.1fms", service_id, (time.perf_counter() - started_at) * 1000.0)
        elif service_id == "database":
            if target_running and not success:
                self._maybe_open_service_port_conflict(service_id, message)
            if target_running and final_running:
                success = True
                message = message or "Database started."
            if not target_running and not final_running:
                success = True
                message = "Database stopped."
            self._database_service_state_cache = "Running" if final_running else "Stopped"
            self._database_runtime_message = message or (
                ("Database started." if target_running else "Database stopped.") if success else "Database action failed."
            )
            self._database_runtime_error = not success
            self._database_runtime_log = log_tail
            self.dataChanged.emit()
            self.databaseRuntimeFeedbackChanged.emit()
            LOGGER.debug("_on_home_service_completed: database branch service_id=%s took=%.1fms", service_id, (time.perf_counter() - started_at) * 1000.0)
        elif service_id == "redis":
            if target_running and not success:
                self._maybe_open_service_port_conflict(service_id, message)
            cache_name = "Redis"
            self._redis_service_state_cache = "Running" if final_running else "Stopped"
            self._redis_runtime_message = message or (
                (f"{cache_name} started." if target_running else f"{cache_name} stopped.") if success else f"{cache_name} action failed."
            )
            self._redis_runtime_error = not success
            self._redis_runtime_log = log_tail
            self.redisRuntimeFeedbackChanged.emit()
            LOGGER.debug("_on_home_service_completed: redis branch service_id=%s took=%.1fms", service_id, (time.perf_counter() - started_at) * 1000.0)
        elif service_id == "memcached":
            if target_running and not success:
                self._maybe_open_service_port_conflict(service_id, message)
            cache_name = "Memcached"
            self._memcached_service_state_cache = "Running" if final_running else "Stopped"
            self._memcached_runtime_message = message or (
                (f"{cache_name} started." if target_running else f"{cache_name} stopped.") if success else f"{cache_name} action failed."
            )
            self._memcached_runtime_error = not success
            self._memcached_runtime_log = log_tail
            self.redisRuntimeFeedbackChanged.emit()
            LOGGER.debug("_on_home_service_completed: memcached branch service_id=%s took=%.1fms", service_id, (time.perf_counter() - started_at) * 1000.0)
        elif service_id == "mailpit":
            if target_running and not success:
                self._maybe_open_service_port_conflict(service_id, message)
            self._mailpit_service_state_cache = "Running" if final_running else "Stopped"
            self._mailpit_runtime_message = message or (
                ("Mailpit started." if target_running else "Mailpit stopped.") if success else "Mailpit action failed."
            )
            self._mailpit_runtime_error = not success
            self._mailpit_runtime_log = log_tail
            self.mailpitRuntimeFeedbackChanged.emit()
            LOGGER.debug("_on_home_service_completed: mailpit branch service_id=%s took=%.1fms", service_id, (time.perf_counter() - started_at) * 1000.0)
        elif service_id == "mongodb":
            if target_running and not success:
                self._maybe_open_service_port_conflict(service_id, message)
            self._mongodb_service_state_cache = "Running" if final_running else "Stopped"
            self._mongodb_runtime_message = message or (
                ("MongoDB started." if target_running else "MongoDB stopped.") if success else "MongoDB action failed."
            )
            self._mongodb_runtime_error = not success
            self._mongodb_runtime_log = log_tail
            self.mongodbRuntimeFeedbackChanged.emit()
            LOGGER.debug("_on_home_service_completed: mongodb branch service_id=%s took=%.1fms", service_id, (time.perf_counter() - started_at) * 1000.0)
        elif service_id == "postgresql":
            if target_running and not success:
                self._maybe_open_service_port_conflict(service_id, message)
            self._postgresql_service_state_cache = "Running" if final_running else "Stopped"
            self._postgresql_runtime_message = message or (
                ("PostgreSQL started." if target_running else "PostgreSQL stopped.") if success else "PostgreSQL action failed."
            )
            self._postgresql_runtime_error = not success
            self._postgresql_runtime_log = log_tail
            self.postgresqlRuntimeFeedbackChanged.emit()
            LOGGER.debug("_on_home_service_completed: postgresql branch service_id=%s took=%.1fms", service_id, (time.perf_counter() - started_at) * 1000.0)
        self._update_home_service_item_cache(service_id, final_running, status_text)
        self.homeServiceChanged.emit()
        self._defer_action_state_changed()
        LOGGER.debug("_on_home_service_completed: total service_id=%s took=%.1fms", service_id, (time.perf_counter() - started_at) * 1000.0)

    def _update_home_service_item_cache(self, service_id: str, running: bool, status: str) -> None:
        if not hasattr(self, "_home_service_running_cache"):
            self._home_service_running_cache = {}
        self._home_service_running_cache[service_id] = bool(running)
        if not hasattr(self, "_home_service_items_cache") or not self._home_service_items_cache:
            return
        for item in self._home_service_items_cache:
            if item.get("id") == service_id:
                item["running"] = bool(running)
                item["status"] = status or ("Running" if running else "Stopped")
                item["busy"] = self.homeServiceBusy(service_id)
                break

    def _service_label(self, service_id: str) -> str:
        return {
            "web": "Web Server",
            "database": "Database",
            "mongodb": "MongoDB",
            "postgresql": "PostgreSQL",
            "redis": "Redis",
            "memcached": "Memcached",
            "mailpit": "Mailpit",
        }.get(service_id, service_id.title())

    def _maybe_open_service_port_conflict(self, service_id: str, message: str) -> None:
        match = re.search(r"Port\s+(\d+)\s+is already in use", message or "", re.IGNORECASE)
        if not match:
            return
        try:
            port = int(match.group(1))
        except Exception:
            return
        label = self._service_label(service_id)
        self._service_port_conflict_service_id = service_id
        self._service_port_conflict_service_label = label
        self._service_port_conflict_port = port
        self._service_port_conflict_message = (
            f"Port {port} is already in use. Server Engine can stop the process on this port and retry starting {label.lower()}."
        )
        self._service_port_conflict_open = True
        self.servicePortConflictChanged.emit()

    def _clear_service_port_conflict(self) -> None:
        if (
            not self._service_port_conflict_open
            and self._service_port_conflict_port == 0
            and not self._service_port_conflict_message
            and not self._service_port_conflict_service_id
        ):
            return
        self._service_port_conflict_open = False
        self._service_port_conflict_port = 0
        self._service_port_conflict_message = ""
        self._service_port_conflict_service_id = ""
        self._service_port_conflict_service_label = ""
        self.servicePortConflictChanged.emit()

    def _kill_listener_on_port(self, port: int) -> tuple[bool, str]:
        if port <= 0:
            return False, "Invalid port."
        try:
            result = subprocess.run(
                ["lsof", "-nP", f"-iTCP:{port}", "-sTCP:LISTEN", "-t"],
                capture_output=True,
                text=True,
                check=False,
            )
            pids = []
            for line in (result.stdout or "").splitlines():
                text = line.strip()
                if text.isdigit():
                    pids.append(int(text))
            if not pids:
                return False, f"No listening process found on port {port}."
            for pid in sorted(set(pids)):
                try:
                    os.kill(pid, 15)
                except ProcessLookupError:
                    continue
                except Exception:
                    pass
            deadline = datetime.now().timestamp() + 2.0
            remaining = set(sorted(set(pids)))
            while remaining and datetime.now().timestamp() < deadline:
                next_remaining: set[int] = set()
                for pid in remaining:
                    try:
                        os.kill(pid, 0)
                        next_remaining.add(pid)
                    except ProcessLookupError:
                        pass
                    except Exception:
                        next_remaining.add(pid)
                if not next_remaining:
                    break
                remaining = next_remaining
                QThread.msleep(120)
            for pid in sorted(remaining):
                try:
                    os.kill(pid, 9)
                except ProcessLookupError:
                    pass
                except Exception:
                    pass
            return True, f"Released port {port}."
        except Exception as exc:
            return False, str(exc)

    @Property(bool, notify=servicePortConflictChanged)
    def servicePortConflictOpen(self) -> bool:
        return self._service_port_conflict_open

    @Property(int, notify=servicePortConflictChanged)
    def servicePortConflictPort(self) -> int:
        return self._service_port_conflict_port

    @Property(str, notify=servicePortConflictChanged)
    def servicePortConflictMessage(self) -> str:
        return self._service_port_conflict_message

    @Property(str, notify=servicePortConflictChanged)
    def servicePortConflictServiceId(self) -> str:
        return self._service_port_conflict_service_id

    @Property(str, notify=servicePortConflictChanged)
    def servicePortConflictServiceLabel(self) -> str:
        return self._service_port_conflict_service_label

    @Slot()
    def dismissServicePortConflict(self) -> None:
        self._clear_service_port_conflict()

    @Slot()
    def resolveServicePortConflictAndRetry(self) -> None:
        service_id = self._service_port_conflict_service_id.strip()
        if not service_id:
            return
        if self.homeServiceBusy(service_id):
            return
        port = int(self._service_port_conflict_port)
        label = self._service_label(service_id)
        self._clear_service_port_conflict()
        ok, message = self._kill_listener_on_port(port)
        if ok:
            self._last_operation_message = f"{message} Retrying {label.lower()} start."
        else:
            self._last_operation_message = message
        self._last_operation_error = not ok
        self.operationFeedbackChanged.emit()
        if not ok:
            return
        self.setHomeServiceRunning(service_id, True)

    def _set_home_service_busy(self, service_id: str, busy: bool) -> None:
        if service_id == "web":
            self._stack_action_busy = busy
        elif service_id == "database":
            self._database_action_busy = busy
        elif service_id == "redis":
            self._redis_action_busy = busy
        elif service_id == "memcached":
            self._memcached_action_busy = busy
        elif service_id == "mailpit":
            self._mailpit_action_busy = busy
        elif service_id == "mongodb":
            self._mongodb_action_busy = busy
        elif service_id == "postgresql":
            self._postgresql_action_busy = busy
        if hasattr(self, "_home_service_items_cache") and self._home_service_items_cache:
            for item in self._home_service_items_cache:
                if item.get("id") == service_id:
                    item["busy"] = bool(busy)
                    break

    def _cleanup_home_service_job(self, service_id: str) -> None:
        self._home_service_workers.pop(service_id, None)
        self._home_service_threads.pop(service_id, None)
        self._home_service_targets.pop(service_id, None)

    @Slot(str, "QVariantList")
    def _on_global_stack_action_completed(self, action: str, results: list[dict[str, object]]) -> None:
        LOGGER.debug(
            "_on_global_stack_action_completed: action=%s results=%s",
            action,
            [{k: row.get(k) for k in ("service_id", "success", "message", "running")} for row in results],
        )
        failures = [r for r in results if not bool(r.get("success"))]
        parts: list[str] = []
        touched_services: set[str] = set()
        for row in results:
            service_id = str(row.get("service_id", ""))
            touched_services.add(service_id)
            label = {
                "web": "Web",
                "database": "Database",
                "mongodb": "MongoDB",
                "postgresql": "PostgreSQL",
                "redis": "Redis",
                "memcached": "Memcached",
                "mailpit": "Mailpit",
            }.get(service_id, service_id)
            ok = bool(row.get("success"))
            msg = str(row.get("message", "")).strip()
            if ok:
                parts.append(f"{label}: ok")
            else:
                parts.append(f"{label}: {msg or 'failed'}")
            self._set_home_service_busy(service_id, False)
            if ok:
                running = bool(row.get("running", action != "stop"))
                self._update_home_service_item_cache(service_id, running, "Running" if running else "Stopped")
        self._global_action_busy = False
        self._global_action_mode = ""
        if failures:
            self._stack_feedback_message = f"{action.title()} selected finished with errors | " + " | ".join(parts)
            self._stack_feedback_error = True
        else:
            self._stack_feedback_message = f"{action.title()} selected completed | " + " | ".join(parts)
            self._stack_feedback_error = False
        self._global_action_thread = None
        self._global_action_worker = None
        if "mailpit" in touched_services:
            self._mailpit_runtime_log = str(next((row.get("log_tail", "") for row in results if str(row.get("service_id", "")) == "mailpit"), ""))
            self.mailpitRuntimeFeedbackChanged.emit()
            self._mailpit_service_state_cache = "Running" if bool(next((row.get("running", False) for row in results if str(row.get("service_id", "")) == "mailpit"), action != "stop")) else "Stopped"
        if "mongodb" in touched_services:
            self._mongodb_runtime_log = str(next((row.get("log_tail", "") for row in results if str(row.get("service_id", "")) == "mongodb"), ""))
            self.mongodbRuntimeFeedbackChanged.emit()
            self._mongodb_service_state_cache = "Running" if bool(next((row.get("running", False) for row in results if str(row.get("service_id", "")) == "mongodb"), action != "stop")) else "Stopped"
        if "postgresql" in touched_services:
            self._postgresql_runtime_log = str(next((row.get("log_tail", "") for row in results if str(row.get("service_id", "")) == "postgresql"), ""))
            self.postgresqlRuntimeFeedbackChanged.emit()
            self._postgresql_service_state_cache = "Running" if bool(next((row.get("running", False) for row in results if str(row.get("service_id", "")) == "postgresql"), action != "stop")) else "Stopped"
        self.actionStateChanged.emit()
        self.stackFeedbackChanged.emit()
        self.homeServiceChanged.emit()

    @Slot(bool, str)
    def _on_web_restart_completed(self, success: bool, message: str) -> None:
        self._stack_action_busy = False
        self._web_restart_thread = None
        self._web_restart_worker = None
        status = self._container.stack_service.status()
        self._apply_stack_feedback(status, "restart")
        if not success and message:
            self._stack_feedback_message = f"Web server restart failed: {message}"
            self._stack_feedback_error = True
            self.stackFeedbackChanged.emit()
        self.dataChanged.emit()
        self.actionStateChanged.emit()

    @Slot(bool, str)
    def _on_web_route_reload_completed(self, success: bool, message: str) -> None:
        self._web_reload_thread = None
        self._web_reload_worker = None
        if success:
            self._last_operation_message = message or "Web routes reloaded."
            self._last_operation_error = False
            self.operationFeedbackChanged.emit()
        elif message:
            self._last_operation_message = f"{self._last_operation_message} | Web reload failed: {message}"
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
        self.dataChanged.emit()

    def _included_home_services(self) -> list[str]:
        settings = self._container.settings_service.get_settings()
        mapping = settings.home_global_services or {}
        ordered = ["web", "database", "mongodb", "postgresql", "redis", "memcached", "mailpit"]
        return [
            service_id
            for service_id in ordered
            if self._is_home_service_available(service_id) and bool(mapping.get(service_id, True))
        ]

    def _is_home_service_running(self, service_id: str) -> bool:
        if service_id == "web":
            settings = self._container.settings_service.get_settings()
            web_id = "nginx" if settings.active_web_server == settings.active_web_server.NGINX else "apache"
            status = self._container.stack_service.status()
            item = next((s for s in status.services if s.service_id == web_id), None)
            return bool(item and item.state.value == "running")
        if service_id == "database":
            return self._container.database_service.status().state.value == "running"
        if service_id == "redis":
            return self._container.redis_service.status().state.value == "running"
        if service_id == "memcached":
            return self._container.memcached_service.status().state.value == "running"
        if service_id == "mailpit":
            return self._container.mailpit_service.status().state.value == "running"
        if service_id == "mongodb":
            return self._container.mongodb_service.status().state.value == "running"
        if service_id == "postgresql":
            return self._container.postgresql_service.status().state.value == "running"
        return False

    def _is_home_service_available(self, service_id: str) -> bool:
        if service_id in {"web", "database", "redis", "memcached", "mailpit"}:
            return True
        if service_id == "mongodb":
            return self.optionalDatabaseRuntimeDownloaded("mongodb")
        if service_id == "postgresql":
            return self.optionalDatabaseRuntimeDownloaded("postgresql")
        return False

    @Slot()
    def startStack(self) -> None:
        self._start_global_stack_action("start")

    @Slot()
    def stopStack(self) -> None:
        self._start_global_stack_action("stop")

    @Slot()
    def toggleGlobalStack(self) -> None:
        included = self._included_home_services()
        if not included:
            self._stack_feedback_message = "No services selected for global actions."
            self._stack_feedback_error = True
            self.stackFeedbackChanged.emit()
            return
        all_running = all(self._is_home_service_running(service_id) for service_id in included)
        self._start_global_stack_action("stop" if all_running else "start")

    @Slot()
    def restartStack(self) -> None:
        self._start_global_stack_action("restart")

    @Slot()
    def startAllServices(self) -> None:
        self._start_global_stack_action("start")

    @Slot()
    def stopAllServices(self) -> None:
        self._start_global_stack_action("stop")

    @Slot()
    def restartAllServices(self) -> None:
        self._start_global_stack_action("restart")

    @Slot(str, bool)
    def setHomeServiceRunning(self, service_id: str, running: bool) -> None:
        LOGGER.debug("setHomeServiceRunning: service_id=%s running=%s busy=%s", service_id, running, self.homeServiceBusy(service_id))
        if self.homeServiceBusy(service_id):
            return
        if service_id not in ("web", "database", "redis", "memcached", "mailpit", "mongodb", "postgresql"):
            return
        if not self._is_home_service_available(service_id):
            return
        if service_id == "web" and running:
            ok, error_message = self._validate_web_php_runtime_compat()
            if not ok:
                fixed, fix_message = self._prompt_and_fix_missing_site_php_runtimes()
                if not fixed:
                    self._stack_feedback_message = error_message
                    self._stack_feedback_error = True
                    self.stackFeedbackChanged.emit()
                    self._last_operation_message = error_message
                    self._last_operation_error = True
                    self.operationFeedbackChanged.emit()
                    return
                self._last_operation_message = fix_message
                self._last_operation_error = False
                self.operationFeedbackChanged.emit()
        self._home_service_targets[service_id] = bool(running)
        if not hasattr(self, "_home_service_running_cache"):
            self._home_service_running_cache = {}
        self._home_service_running_cache[service_id] = bool(running)
        self._set_home_service_busy(service_id, True)
        self._start_home_service_job(service_id, running)
        self._defer_action_state_changed()

    @Slot()
    def startWebServerRuntime(self) -> None:
        self.setHomeServiceRunning("web", True)

    @Slot()
    def stopWebServerRuntime(self) -> None:
        self.setHomeServiceRunning("web", False)

    @Slot()
    def restartWebServerRuntime(self) -> None:
        if self._stack_action_busy:
            return
        self._stack_action_busy = True
        thread = QThread(self)
        worker = WebRestartWorker(self._container)
        worker.moveToThread(thread)
        worker.completed.connect(self._on_web_restart_completed)
        worker.completed.connect(thread.quit)
        thread.started.connect(worker.run)
        thread.finished.connect(worker.deleteLater)
        thread.finished.connect(thread.deleteLater)
        self._web_restart_thread = thread
        self._web_restart_worker = worker
        thread.start()
        self._defer_action_state_changed()

    @Slot(str, result=bool)
    def homeServiceBusy(self, service_id: str) -> bool:
        if service_id == "web":
            return self._stack_action_busy
        if service_id == "database":
            return self._database_action_busy
        if service_id == "redis":
            return self._redis_action_busy
        if service_id == "memcached":
            return self._memcached_action_busy
        if service_id == "mailpit":
            return self._mailpit_action_busy
        if service_id == "mongodb":
            return self._mongodb_action_busy
        if service_id == "postgresql":
            return self._postgresql_action_busy
        return False

    @Slot(str, result=bool)
    def homeServiceRunning(self, service_id: str) -> bool:
        if not hasattr(self, "_home_service_running_cache") or not self._home_service_running_cache:
            self._refresh_home_service_items_cache()
        return bool(self._home_service_running_cache.get(service_id, False))

    @Slot(str, result=bool)
    def homeServiceIncludedInGlobal(self, service_id: str) -> bool:
        settings = self._container.settings_service.get_settings()
        if not self._is_home_service_available(service_id):
            return False
        defaults = {
            "web": True,
            "database": True,
            "redis": False,
            "memcached": False,
            "mailpit": False,
            "mongodb": False,
            "postgresql": False,
        }
        return bool(settings.home_global_services.get(service_id, defaults.get(service_id, False)))

    @Slot(str, bool, result=bool)
    def setHomeServiceIncludedInGlobal(self, service_id: str, included: bool) -> bool:
        try:
            if service_id not in ("web", "database", "redis", "memcached", "mailpit", "mongodb", "postgresql"):
                raise ValueError("Unknown service.")
            if not self._is_home_service_available(service_id):
                raise ValueError("Service is not available.")
            current = self._container.settings_service.get_settings()
            mapping = dict(current.home_global_services or {})
            mapping[service_id] = bool(included)
            settings = self._copy_settings(current, home_global_services=mapping)
            self._container.settings_service.save_settings(settings)
            self.dataChanged.emit()
            return True
        except Exception:
            return False

    @Slot(result=bool)
    def webServerRunning(self) -> bool:
        settings = self._container.settings_service.get_settings()
        active_web_server = settings.active_web_server.value
        status = self._container.stack_service.status()
        current_web = next((service for service in status.services if service.service_id == active_web_server), None)
        return bool(current_web is not None and current_web.state.value == "running")

    def _apply_stack_feedback(self, status, action: str) -> None:
        messages = [service.message for service in status.services if service.message]
        errors = [service.message for service in status.services if service.state.value == "error"]

        if errors:
            self._stack_feedback_message = f"{action.title()} failed: {' | '.join(errors)}"
            self._stack_feedback_error = True
            LOGGER.error("Stack %s failed: %s", action, " | ".join(errors))
        elif messages:
            self._stack_feedback_message = f"{action.title()} result: {' | '.join(messages)}"
            self._stack_feedback_error = False
        else:
            self._stack_feedback_message = f"{action.title()} completed."
            self._stack_feedback_error = False

        self.dataChanged.emit()
        self.stackFeedbackChanged.emit()

    def _set_web_service_running(self, running: bool):
        settings = self._container.settings_service.get_settings()
        stack_service = self._container.stack_service
        web_service_id = "nginx" if settings.active_web_server == settings.active_web_server.NGINX else "apache"

        if running:
            stack_service.start_service(web_service_id)
            return stack_service.status()

        stack_service.stop_service(web_service_id)
        return stack_service.status()

    def _active_web_server_running(self) -> bool:
        settings = self._container.settings_service.get_settings()
        target = "nginx" if settings.active_web_server == settings.active_web_server.NGINX else "apache"
        status = self._container.stack_service.status()
        for service in status.services:
            if service.service_id == target:
                return service.state.value == "running"
        return False

    def _reload_active_web_server_for_routes(self) -> None:
        settings = self._container.settings_service.get_settings()
        web_id = "nginx" if settings.active_web_server == settings.active_web_server.NGINX else "apache"
        status = self._container.stack_service.status()
        web_status = next((item for item in status.services if item.service_id == web_id), None)
        if web_status is None:
            return
        if web_status.state == web_status.state.RUNNING:
            self._container.stack_service.stop_service(web_id)
            self._container.stack_service.start_service(web_id)

    def _start_web_route_reload(self) -> None:
        if self._web_reload_thread is not None and self._web_reload_thread.isRunning():
            return
        thread = QThread(self)
        worker = WebRouteReloadWorker(self._container)
        worker.moveToThread(thread)
        worker.completed.connect(self._on_web_route_reload_completed)
        worker.completed.connect(thread.quit)
        thread.started.connect(worker.run)
        thread.finished.connect(worker.deleteLater)
        thread.finished.connect(thread.deleteLater)
        self._web_reload_thread = thread
        self._web_reload_worker = worker
        thread.start()
