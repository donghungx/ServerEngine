from ._shared import *


class RuntimeManagerMixin(DashboardBridgeSignals):
    @Property(bool, notify=appSettingsFeedbackChanged)
    def runtimeManagerBusy(self) -> bool:
        return self._runtime_manager_busy or self._runtime_install_busy

    @Slot(str, result=bool)
    def optionalDatabaseRuntimeDownloaded(self, service: str) -> bool:
        service_id = service.strip().lower()
        if service_id not in OPTIONAL_DATABASE_RUNTIME_SERVICES:
            return False
        return bool(self._optional_database_runtime_download_cache.get(service_id, False))

    def _refresh_optional_database_runtime_cache(self, service_id: str | None = None) -> None:
        database_root = self._container.binary_locator.database_root().resolve()
        services = [service_id] if service_id in OPTIONAL_DATABASE_RUNTIME_SERVICES else list(OPTIONAL_DATABASE_RUNTIME_SERVICES)
        runtimes = self._container.database_runtime_service.list_runtimes()
        for current_service in services:
            downloaded = False
            for runtime in runtimes:
                if runtime.engine != current_service:
                    continue
                try:
                    runtime_home = Path(runtime.home).resolve()
                except Exception:
                    continue
                if runtime_home == database_root or database_root in runtime_home.parents:
                    downloaded = True
                    break
            self._optional_database_runtime_download_cache[current_service] = downloaded

    @Property(bool, notify=appSettingsFeedbackChanged)
    def runtimeInstallBusy(self) -> bool:
        return self._runtime_install_busy

    @Property(int, notify=appSettingsFeedbackChanged)
    def runtimeInstallProgress(self) -> int:
        return self._runtime_install_progress

    @Property(str, notify=appSettingsFeedbackChanged)
    def runtimeInstallStatus(self) -> str:
        return self._runtime_install_status

    @Property(bool, notify=appSettingsFeedbackChanged)
    def requiredRuntimeBootstrapOpen(self) -> bool:
        return self._required_runtime_bootstrap_open

    @Property(bool, notify=appSettingsFeedbackChanged)
    def requiredRuntimeBootstrapBusy(self) -> bool:
        return self._required_runtime_bootstrap_busy

    @Property(int, notify=appSettingsFeedbackChanged)
    def requiredRuntimeBootstrapProgress(self) -> int:
        return self._required_runtime_bootstrap_progress

    @Property(str, notify=appSettingsFeedbackChanged)
    def requiredRuntimeBootstrapStatus(self) -> str:
        return self._required_runtime_bootstrap_status

    @Property(bool, notify=appSettingsFeedbackChanged)
    def requiredRuntimeBootstrapError(self) -> bool:
        return self._required_runtime_bootstrap_error

    @Property("QVariantList", notify=appSettingsFeedbackChanged)
    def requiredRuntimeBootstrapMissing(self) -> list[str]:
        return list(self._required_runtime_bootstrap_missing)

    @Property("QVariantList", notify=appSettingsFeedbackChanged)
    def requiredRuntimeBootstrapItems(self) -> list[dict[str, str]]:
        return [dict(item) for item in self._required_runtime_bootstrap_items]

    @Slot()
    def ensureRequiredRuntimesAtStartup(self) -> None:
        if self._required_runtime_bootstrap_busy:
            return
        if self._required_runtime_bootstrap_cache_valid():
            payload = json.loads(self._required_runtime_bootstrap_cache_path().read_text(encoding="utf-8"))
            if payload.get("activation_version") == 1:
                return
        if self._required_runtime_bootstrap_open and not self._required_runtime_bootstrap_error:
            return
        self._required_runtime_bootstrap_open = False
        self._required_runtime_bootstrap_busy = True
        self._required_runtime_bootstrap_progress = 0
        self._required_runtime_bootstrap_error = False
        self._required_runtime_bootstrap_status = "Checking required runtimes..."
        self._required_runtime_bootstrap_missing = []
        self._required_runtime_bootstrap_items = []
        self.appSettingsFeedbackChanged.emit()
        thread = QThread(self)
        worker = RequiredRuntimeBootstrapWorker(self)
        worker.moveToThread(thread)
        worker.progressChanged.connect(self._on_required_runtime_bootstrap_progress)
        worker.completed.connect(self._on_required_runtime_bootstrap_completed)
        worker.completed.connect(thread.quit)
        thread.started.connect(worker.run)
        thread.finished.connect(worker.deleteLater)
        thread.finished.connect(thread.deleteLater)
        self._required_runtime_bootstrap_thread = thread
        self._required_runtime_bootstrap_worker = worker
        thread.start()

    @Slot()
    def retryRequiredRuntimeBootstrap(self) -> None:
        self.ensureRequiredRuntimesAtStartup()

    @Property("QVariantList", notify=runtimeServerItemsChanged)
    def runtimeServerItemsModel(self) -> list[dict[str, object]]:
        return self._runtime_server_items_model

    @Property(str, notify=runtimeServerItemsChanged)
    def runtimeServerItemsService(self) -> str:
        return self._runtime_server_items_service

    @Slot(str)
    def requestRuntimeServerItems(self, service: str) -> None:
        service_id = service.strip().lower()
        if service_id not in RUNTIME_MANAGER_SERVICES:
            return
        if self._runtime_manager_busy or self._runtime_install_busy:
            self._app_settings_message = "Another runtime action is already running."
            self._app_settings_error = True
            self.appSettingsFeedbackChanged.emit()
            return
        self._runtime_manager_busy = True
        self._app_settings_message = "Loading runtime list..."
        self._app_settings_error = False
        self.appSettingsFeedbackChanged.emit()
        thread = QThread(self)
        worker = RuntimeManifestWorker(self, service_id)
        worker.moveToThread(thread)
        worker.completed.connect(self._on_runtime_manifest_completed)
        worker.completed.connect(thread.quit)
        thread.started.connect(worker.run)
        thread.finished.connect(worker.deleteLater)
        thread.finished.connect(thread.deleteLater)
        self._runtime_manifest_thread = thread
        self._runtime_manifest_worker = worker
        thread.start()

    @Slot(str, result="QVariantList")
    def runtimeManagerItems(self, service: str) -> list[dict[str, object]]:
        service_id = service.strip().lower()
        settings = self._container.settings_service.get_settings()
        allow_remove_default = self._allow_remove_default_runtimes()
        if service_id == "php":
            active = settings.default_php_version
            items: list[dict[str, object]] = []
            for runtime in self._container.php_runtime_service.list_runtimes():
                is_active = runtime.version == active
                items.append(self._runtime_manager_item("php", runtime.version, runtime.version, runtime.label, runtime.home, is_active))
            can_remove = allow_remove_default or len(items) > 1
            for item in items:
                item["canRemove"] = can_remove and (allow_remove_default or not self._is_protected_default_runtime(settings, "php", str(item.get("id", ""))))
            return items
        if service_id == "phpmyadmin":
            active = settings.active_phpmyadmin_version or ""
            items = []
            for version in self._container.binary_locator.available_phpmyadmin_versions():
                runtime_home = self._container.binary_locator.phpmyadmin_root(version)
                is_active = version == active or runtime_home.name == active
                item = self._runtime_manager_item("phpmyadmin", version, version, version, str(runtime_home), is_active)
                item["canActivate"] = False
                items.append(item)
            can_remove = allow_remove_default or len(items) > 1
            for item in items:
                item["canRemove"] = can_remove and (allow_remove_default or not self._is_protected_default_runtime(settings, "phpmyadmin", str(item.get("id", ""))))
            return items
        if service_id == "apache":
            active = settings.active_apache_version or self._container.binary_locator.apache_home().name
            items = []
            for home in self._container.binary_locator.available_apache_runtimes():
                version = home.name.removeprefix("apache-").lstrip("-")
                is_active = home.name == active or version == active
                item = self._runtime_manager_item("apache", home.name, version, home.name, str(home), is_active)
                item["canActivate"] = False
                items.append(item)
            can_remove = allow_remove_default or len(items) > 1
            for item in items:
                item["canRemove"] = can_remove and (allow_remove_default or not self._is_protected_default_runtime(settings, "apache", str(item.get("id", ""))))
            return items
        if service_id == "nginx":
            active = settings.active_nginx_version or self._container.binary_locator.nginx_home().name
            items = []
            for home in self._container.binary_locator.available_nginx_runtimes():
                version = home.name.removeprefix("nginx-").lstrip("-")
                is_active = home.name == active or version == active
                item = self._runtime_manager_item("nginx", home.name, version, home.name, str(home), is_active)
                item["canActivate"] = False
                items.append(item)
            can_remove = allow_remove_default or len(items) > 1
            for item in items:
                item["canRemove"] = can_remove and (allow_remove_default or not self._is_protected_default_runtime(settings, "nginx", str(item.get("id", ""))))
            return items
        if service_id in SQL_DATABASE_RUNTIME_SERVICES:
            active = settings.active_database_version or ""
            if not active or not active.startswith(service_id + "-"):
                active = (
                    settings.default_mysql_version
                    if service_id == "mysql"
                    else settings.default_mariadb_version
                )
            items = []
            for runtime in self._container.database_runtime_service.list_runtimes():
                if runtime.engine != service_id:
                    continue
                is_active = runtime.id == active
                item = self._runtime_manager_item(service_id, runtime.id, runtime.version, runtime.label, runtime.home, is_active)
                item["canActivate"] = False
                items.append(item)
            can_remove = allow_remove_default or len(items) > 1
            for item in items:
                item["canRemove"] = can_remove and (allow_remove_default or not self._is_protected_default_runtime(settings, service_id, str(item.get("id", ""))))
            return items
        if service_id in OPTIONAL_DATABASE_RUNTIME_SERVICES:
            active = (
                settings.active_mongodb_version
                if service_id == "mongodb"
                else settings.active_postgresql_version
            ) or ""
            if not active:
                runtime = (
                    self._container.mongodb_service.active_runtime()
                    if service_id == "mongodb"
                    else self._container.postgresql_service.active_runtime()
                )
                active = runtime.id if runtime is not None else ""
            items = []
            for runtime in self._container.database_runtime_service.list_runtimes():
                if runtime.engine != service_id:
                    continue
                is_active = runtime.id == active
                item = self._runtime_manager_item(service_id, runtime.id, runtime.version, runtime.label, runtime.home, is_active)
                items.append(item)
            can_remove = allow_remove_default or len(items) > 1
            for item in items:
                item["canRemove"] = can_remove and (allow_remove_default or not self._is_protected_default_runtime(settings, service_id, str(item.get("id", ""))))
            self._optional_database_runtime_download_cache[service_id] = len(items) > 0
            return items
        if service_id == "redis":
            active = settings.active_redis_version or settings.default_redis_version or ""
            items = []
            for runtime in self._container.redis_runtime_service.list_runtimes():
                is_active = runtime.id == active
                items.append(self._runtime_manager_item("redis", runtime.id, runtime.version, runtime.label, runtime.home, is_active))
            can_remove = allow_remove_default or len(items) > 1
            for item in items:
                item["canRemove"] = can_remove and (allow_remove_default or not self._is_protected_default_runtime(settings, "redis", str(item.get("id", ""))))
            return items
        if service_id == "memcached":
            active = settings.active_memcached_version or settings.default_memcached_version or ""
            items = []
            for runtime in self._container.memcached_runtime_service.list_runtimes():
                is_active = runtime.id == active
                items.append(self._runtime_manager_item("memcached", runtime.id, runtime.version, runtime.label, runtime.home, is_active))
            can_remove = allow_remove_default or len(items) > 1
            for item in items:
                item["canRemove"] = can_remove and (allow_remove_default or not self._is_protected_default_runtime(settings, "memcached", str(item.get("id", ""))))
            return items
        if service_id == "mailpit":
            preferred_mailpit = settings.active_mailpit_version or settings.default_mailpit_version
            active_runtime = self._container.binary_locator.mailpit_runtime(preferred_mailpit)
            active = active_runtime.id if active_runtime is not None else (preferred_mailpit or "")
            items = []
            for runtime in self._container.binary_locator.available_mailpit_runtimes():
                is_active = runtime.id == active
                items.append(self._runtime_manager_item("mailpit", runtime.id, runtime.version, runtime.label, runtime.home, is_active))
            can_remove = allow_remove_default or len(items) > 1
            for item in items:
                item["canRemove"] = can_remove and (allow_remove_default or not self._is_protected_default_runtime(settings, "mailpit", str(item.get("id", ""))))
            return items
        if service_id == "node":
            active = str(settings.active_node_version or "").strip()
            items = []
            for runtime in self._container.binary_locator.available_node_runtimes():
                runtime_id = str(runtime.get("label") or "")
                version = str(runtime.get("version") or "").strip()
                is_active = bool(active and (version == active or runtime_id == active or f"node{active}" == runtime_id))
                item = self._runtime_manager_item(
                    "node",
                    runtime_id,
                    version,
                    runtime_id or version,
                    str(runtime.get("home") or ""),
                    is_active,
                )
                item["canActivate"] = False
                item["canRemove"] = True
                items.append(item)
            return items
        return []

    @Slot(str, result="QVariantList")
    def runtimeServerItems(self, service: str) -> list[dict[str, object]]:
        service_id = service.strip().lower()
        if service_id not in RUNTIME_MANAGER_SERVICES:
            return []
        try:
            return self._load_runtime_server_items(service_id)
        except Exception:
            return []

    def _load_runtime_server_items(self, service_id: str) -> list[dict[str, object]]:
        manifest = self._fetch_runtime_manifest()
        items = manifest.get("items", manifest.get("runtimes", manifest.get("runtime", [])))
        if isinstance(items, dict):
            items = list(items.values())
        if not isinstance(items, list):
            items = []
        local_ids = {str(item.get("id") or "") for item in self.runtimeManagerItems(service_id)}
        local_ids.update(str(item.get("version") or "") for item in self.runtimeManagerItems(service_id))
        result: list[dict[str, object]] = []
        for raw in items:
            if not isinstance(raw, dict):
                continue
            normalized = self._normalize_server_runtime_item(raw)
            item_service = str(normalized.get("service") or "").lower()
            if item_service == "memcache":
                item_service = "memcached"
            if item_service != service_id:
                continue
            runtime_id = str(normalized.get("id") or "")
            version = str(normalized.get("version") or "")
            exists = runtime_id in local_ids or version in local_ids
            normalized["installed"] = exists
            normalized["actionLabel"] = "Overwrite" if exists else "Install"
            result.append(normalized)
        result.sort(
            key=lambda item: self._runtime_version_sort_key(str(item.get("version") or "")),
            reverse=True,
        )
        return result

    @Slot(bool, str, str, "QVariantList")
    def _on_runtime_manifest_completed(self, success: bool, service_id: str, message: str, items: list[dict[str, object]]) -> None:
        self._runtime_manifest_thread = None
        self._runtime_manifest_worker = None
        if success:
            self._runtime_server_items_service = service_id
            self._runtime_server_items_model = items
            self._app_settings_message = f"Loaded {len(items)} server runtime(s)."
            self._app_settings_error = False
            self.runtimeServerItemsChanged.emit()
        else:
            self._runtime_server_items_service = service_id
            self._runtime_server_items_model = []
            self._app_settings_message = message
            self._app_settings_error = True
            self.runtimeServerItemsChanged.emit()
        self._runtime_manager_busy = False
        self.appSettingsFeedbackChanged.emit()

    @Slot("QVariantMap", bool, result=bool)
    def installServerRuntime(self, item: dict, overwrite: bool) -> bool:
        if self._runtime_manager_busy or self._runtime_install_busy:
            self._app_settings_message = "Another runtime action is already running."
            self._app_settings_error = True
            self.appSettingsFeedbackChanged.emit()
            return False
        normalized = self._normalize_server_runtime_item(dict(item or {}))
        try:
            service_id = str(normalized.get("service") or "").lower()
            runtime_id = str(normalized.get("id") or "").strip()
            download_url = str(normalized.get("downloadUrl") or "").strip()
            if service_id == "memcache":
                service_id = "memcached"
                normalized["service"] = service_id
            if service_id not in RUNTIME_MANAGER_SERVICES:
                raise ValueError("Unknown runtime service.")
            if not runtime_id:
                raise ValueError("Runtime id is missing.")
            if not download_url:
                raise ValueError("Download URL is missing.")
            target = self._runtime_install_target_path(normalized)
            if target.exists() and not overwrite:
                raise ValueError("Runtime already exists. Confirm overwrite before installing.")
            self._runtime_install_item_service = service_id
            self._runtime_install_item_id = runtime_id
            self._runtime_install_item_version = str(normalized.get("version") or "")
            LOGGER.info(
                "Runtime install requested service=%s id=%s version=%s overwrite=%s url=%s target=%s",
                service_id,
                runtime_id,
                self._runtime_install_item_version,
                overwrite,
                download_url,
                str(target),
            )
            self._runtime_install_busy = True
            self._runtime_install_progress = 0
            self._runtime_install_status = "Preparing install..."
            self.appSettingsFeedbackChanged.emit()
            thread = QThread(self)
            worker = RuntimeInstallWorker(self, normalized, overwrite)
            worker.moveToThread(thread)
            worker.progressChanged.connect(self._on_runtime_install_progress)
            worker.completed.connect(self._on_runtime_install_completed)
            worker.completed.connect(thread.quit)
            thread.started.connect(worker.run)
            thread.finished.connect(worker.deleteLater)
            thread.finished.connect(thread.deleteLater)
            self._runtime_install_thread = thread
            self._runtime_install_worker = worker
            thread.start()
            return True
        except Exception as exc:
            LOGGER.exception("Runtime install request failed: %s", exc)
            self._app_settings_message = str(exc)
            self._app_settings_error = True
            self.appSettingsFeedbackChanged.emit()
            return False

    def _runtime_manager_item(self, service: str, runtime_id: str, version: str, label: str, home: str, active: bool) -> dict[str, object]:
        return {
            "service": service,
            "id": runtime_id,
            "version": version,
            "label": label,
            "home": home,
            "platform": "macos",
            "arch": self._runtime_arch(),
            "downloaded": True,
            "status": "Active" if active else "Downloaded",
            "canActivate": not active,
            "canRemove": True,
            "hasConfigBackup": self._runtime_restore_config_path(service, runtime_id).exists(),
        }

    def _invalidate_optional_database_runtime_cache(self, service_id: str | None = None) -> None:
        if service_id in OPTIONAL_DATABASE_RUNTIME_SERVICES:
            self._refresh_optional_database_runtime_cache(service_id)
            if service_id in {"mongodb", "postgresql"} and not self.optionalDatabaseRuntimeDownloaded(service_id):
                if self._current_page == service_id:
                    self._current_page = "home"
                    self.currentPageChanged.emit()
            self.dataChanged.emit()
            return
        self._refresh_optional_database_runtime_cache()
        if self._current_page in OPTIONAL_DATABASE_RUNTIME_SERVICES and not self.optionalDatabaseRuntimeDownloaded(self._current_page):
            self._current_page = "home"
            self.currentPageChanged.emit()
        self.dataChanged.emit()

    def _runtime_inventory_kind(self, service_id: str) -> str:
        service = service_id.strip().lower()
        if service in {"mysql", "mariadb", "mongodb", "postgresql"}:
            return "database"
        if service == "memcache":
            return "memcached"
        return service

    def _refresh_runtime_inventory(self, service_id: str) -> None:
        kind = self._runtime_inventory_kind(service_id)
        try:
            self._container.runtime_inventory_service.clear_and_rebuild(kind)
        except Exception:
            LOGGER.exception("Failed to refresh runtime inventory cache for %s", service_id)

    def _emit_runtime_feedback_changed(self, service_id: str) -> None:
        if service_id == "mongodb":
            self.mongodbRuntimeFeedbackChanged.emit()
        elif service_id == "postgresql":
            self.postgresqlRuntimeFeedbackChanged.emit()
        elif service_id in {"redis", "memcached"}:
            self.redisRuntimeFeedbackChanged.emit()
        elif service_id == "mailpit":
            self.mailpitRuntimeFeedbackChanged.emit()

    @Slot(str, str, bool, result=bool)
    def activateRuntime(self, service: str, runtime_id: str, copy_config: bool) -> bool:
        service_id = service.strip().lower()
        target_id = runtime_id.strip()
        if self._runtime_manager_busy:
            self._app_settings_message = "Another runtime action is already running."
            self._app_settings_error = True
            self.appSettingsFeedbackChanged.emit()
            return False
        self._runtime_manager_busy = True
        self.appSettingsFeedbackChanged.emit()
        try:
            if service_id not in {"redis", "memcached", "mailpit", "mongodb", "postgresql"}:
                raise ValueError("Runtime activation in Runtime Manager is only supported for Redis, Memcached, Mailpit, MongoDB, and PostgreSQL.")
            if not target_id:
                raise ValueError("Runtime is required.")
            self._require_local_runtime(service_id, target_id)
            current = self._container.settings_service.get_settings()
            current_id = self._active_runtime_id_for_service(service_id, current)
            if current_id == target_id:
                self._app_settings_message = f"{self._runtime_service_label(service_id)} {target_id} is already active."
                self._app_settings_error = False
                return True
            stop_ok, stop_message = self._stop_runtime_service_for_switch(service_id)
            if not stop_ok:
                raise ValueError(stop_message)
            if copy_config and current_id:
                self._copy_runtime_config(service_id, current_id, target_id)
            updates = self._runtime_activation_updates(service_id, target_id, current)
            settings = self._copy_settings(current, **updates)
            self._container.settings_service.save_settings(settings)
            self._app_settings_message = f"Activated {self._runtime_service_label(service_id)} {target_id}. Start the service again when ready."
            if stop_message:
                self._app_settings_message += " " + stop_message
            self._app_settings_error = False
            self.dataChanged.emit()
            self._emit_runtime_feedback_changed(service_id)
            self._invalidate_optional_database_runtime_cache(service_id)
            return True
        except Exception as exc:
            self._app_settings_message = str(exc)
            self._app_settings_error = True
            return False
        finally:
            self._runtime_manager_busy = False
            self.appSettingsFeedbackChanged.emit()

    @Slot(str, str, result=bool)
    def removeRuntime(self, service: str, runtime_id: str) -> bool:
        service_id = service.strip().lower()
        target_id = runtime_id.strip()
        if self._runtime_manager_busy:
            self._app_settings_message = "Another runtime action is already running."
            self._app_settings_error = True
            self.appSettingsFeedbackChanged.emit()
            return False
        self._runtime_manager_busy = True
        self.appSettingsFeedbackChanged.emit()
        try:
            if service_id not in RUNTIME_MANAGER_SERVICES:
                raise ValueError("Unknown runtime service.")
            if not target_id:
                raise ValueError("Runtime is required.")
            current = self._container.settings_service.get_settings()
            allow_remove_default = self._allow_remove_default_runtimes()
            if not allow_remove_default and self._is_protected_default_runtime(current, service_id, target_id):
                raise ValueError(
                    f"Cannot remove default {self._runtime_service_label(service_id)} runtime ({target_id}). "
                    "Install another version and set it as default/active first."
                )
            installed_count = len(self.runtimeManagerItems(service_id))
            if service_id not in OPTIONAL_DATABASE_RUNTIME_SERVICES and not allow_remove_default and installed_count <= 1:
                raise ValueError(f"Cannot remove the last installed {self._runtime_service_label(service_id)} runtime.")
            home = self._runtime_home_path(service_id, target_id)
            if home is None or not home.exists() or not home.is_dir():
                raise ValueError(f"{self._runtime_service_label(service_id)} runtime {target_id} is not installed locally.")
            current_id = self._active_runtime_id_for_service(service_id, current)
            is_active = current_id == target_id or home.name == current_id
            stop_message = ""
            if self.runtimeServiceRunning(service_id):
                stop_ok, stop_message = self._stop_runtime_service_for_switch(service_id)
                if not stop_ok:
                    raise ValueError(stop_message)
            reassigned_sites = 0
            if service_id == "php":
                fallback_php = str(current.default_php_version or "").strip()
                if not fallback_php or fallback_php == target_id:
                    raise ValueError("Cannot determine fallback PHP version for websites.")
                affected_sites = [site for site in self._container.site_service.list_sites() if str(site.php_version).strip() == target_id]
                for site in affected_sites:
                    self._container.site_service.update_site(site.id, php_version=fallback_php)
                reassigned_sites = len(affected_sites)
            self._backup_runtime_config_for_restore(service_id, target_id)
            shutil.rmtree(home)
            self._refresh_runtime_inventory(service_id)
            if is_active:
                if service_id in {"redis", "memcached", "mailpit"}:
                    remaining = [item for item in self.runtimeManagerItems(service_id) if str(item.get("id", "")) != target_id]
                    fallback_id = str(remaining[0].get("id", "")) if remaining else ""
                    updates = (
                        {"active_redis_version": fallback_id or None}
                        if service_id == "redis"
                        else ({"active_memcached_version": fallback_id or None}
                        if service_id == "memcached"
                        else {"active_mailpit_version": fallback_id or None})
                    )
                    settings = self._copy_settings(current, **updates)
                    self._container.settings_service.save_settings(settings)
                elif service_id not in {"apache", "nginx"} and service_id not in SQL_DATABASE_RUNTIME_SERVICES:
                    settings = self._copy_settings(current, **self._runtime_clear_updates(service_id))
                    self._container.settings_service.save_settings(settings)
            message = f"Removed {self._runtime_service_label(service_id)} {target_id}."
            if reassigned_sites > 0:
                message += f" Reassigned {reassigned_sites} website(s) to PHP {current.default_php_version}."
            if stop_message:
                message += " " + stop_message
            self._app_settings_message = message
            self._app_settings_error = False
            self._invalidate_optional_database_runtime_cache(service_id)
            self.dataChanged.emit()
            self._emit_runtime_feedback_changed(service_id)
            return True
        except Exception as exc:
            self._app_settings_message = str(exc)
            self._app_settings_error = True
            return False
        finally:
            self._runtime_manager_busy = False
            self.appSettingsFeedbackChanged.emit()

    @Slot(str, result=bool)
    def runtimeServiceRunning(self, service: str) -> bool:
        service_id = service.strip().lower()
        if service_id in SQL_DATABASE_RUNTIME_SERVICES:
            return self._container.database_service.status().state.value == "running"
        if service_id == "mongodb":
            return self._container.mongodb_service.status().state.value == "running"
        if service_id == "postgresql":
            return self._container.postgresql_service.status().state.value == "running"
        if service_id == "redis":
            return self._container.redis_service.status().state.value == "running"
        if service_id == "memcached":
            return self._container.memcached_service.status().state.value == "running"
        if service_id == "mailpit":
            return self._container.mailpit_service.status().state.value == "running"
        if service_id in {"apache", "nginx"}:
            status = self._container.stack_service.status()
            item = next((s for s in status.services if s.service_id == service_id), None)
            return bool(item and item.state.value == "running")
        return False

    @Slot(str, str, result=bool)
    def restoreRuntimeConfig(self, service: str, runtime_id: str) -> bool:
        service_id = service.strip().lower()
        target_id = runtime_id.strip()
        if self._runtime_manager_busy:
            self._app_settings_message = "Another runtime action is already running."
            self._app_settings_error = True
            self.appSettingsFeedbackChanged.emit()
            return False
        self._runtime_manager_busy = True
        self.appSettingsFeedbackChanged.emit()
        try:
            self._require_local_runtime(service_id, target_id)
            backup_path = self._runtime_restore_config_path(service_id, target_id)
            if not backup_path.exists():
                raise ValueError("No saved config backup is available for this runtime.")
            target_path = self._runtime_config_path(service_id, target_id)
            if target_path is None:
                raise ValueError("This runtime does not have a managed config file.")
            target_path.parent.mkdir(parents=True, exist_ok=True)
            if target_path.exists():
                existing_backup = self._runtime_config_backup_path(target_path)
                existing_backup.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(target_path, existing_backup)
            shutil.copy2(backup_path, target_path)
            self._app_settings_message = f"Restored config for {self._runtime_service_label(service_id)} {target_id}."
            self._app_settings_error = False
            self.dataChanged.emit()
            self._emit_runtime_feedback_changed(service_id)
            return True
        except Exception as exc:
            self._app_settings_message = str(exc)
            self._app_settings_error = True
            return False
        finally:
            self._runtime_manager_busy = False
            self.appSettingsFeedbackChanged.emit()

    def _runtime_arch(self) -> str:
        try:
            machine = subprocess.run(["uname", "-m"], capture_output=True, text=True, check=False).stdout.strip()
            return machine or "unknown"
        except Exception:
            return "unknown"

    @Slot(int, str)
    def _on_runtime_install_progress(self, value: int, message: str) -> None:
        self._runtime_install_progress = max(0, min(int(value), 100))
        self._runtime_install_status = message
        self.appSettingsFeedbackChanged.emit()

    @Slot()
    def clearRuntimeInstallFeedback(self) -> None:
        if self._runtime_install_busy:
            return
        self._runtime_install_progress = 0
        self._runtime_install_status = ""
        self.appSettingsFeedbackChanged.emit()

    @Slot(bool, str)
    def _on_runtime_install_completed(self, success: bool, message: str) -> None:
        LOGGER.info(
            "Runtime install completed service=%s id=%s version=%s success=%s message=%s",
            self._runtime_install_item_service,
            self._runtime_install_item_id,
            self._runtime_install_item_version,
            success,
            message,
        )
        self._runtime_install_busy = False
        self._runtime_install_progress = 100 if success else 0
        self._runtime_install_status = "Done" if success else ""
        self._runtime_install_thread = None
        self._runtime_install_worker = None
        if success and self._runtime_server_items_service == self._runtime_install_item_service:
            updated_items: list[dict[str, object]] = []
            for item in self._runtime_server_items_model:
                item_id = str(item.get("id") or "")
                item_version = str(item.get("version") or "")
                if item_id == self._runtime_install_item_id or item_version == self._runtime_install_item_version:
                    updated = dict(item)
                    updated["installed"] = True
                    updated["actionLabel"] = "Overwrite"
                    updated_items.append(updated)
                else:
                    updated_items.append(item)
            self._runtime_server_items_model = updated_items
            self.runtimeServerItemsChanged.emit()
        if success:
            self._refresh_runtime_inventory(self._runtime_install_item_service)
            self._invalidate_optional_database_runtime_cache(self._runtime_install_item_service)
        self._app_settings_message = message
        self._app_settings_error = not success
        self._runtime_install_item_service = ""
        self._runtime_install_item_id = ""
        self._runtime_install_item_version = ""
        self.dataChanged.emit()
        self.redisRuntimeFeedbackChanged.emit()
        self.appSettingsFeedbackChanged.emit()

    @Slot(int, str)
    def _on_required_runtime_bootstrap_progress(self, value: int, message: str) -> None:
        self._required_runtime_bootstrap_progress = max(0, min(int(value), 100))
        self._required_runtime_bootstrap_status = str(message or "").strip()
        self.appSettingsFeedbackChanged.emit()

    @Slot(bool, str)
    def _on_required_runtime_bootstrap_completed(self, success: bool, message: str) -> None:
        self._required_runtime_bootstrap_busy = False
        self._required_runtime_bootstrap_thread = None
        self._required_runtime_bootstrap_worker = None
        self._required_runtime_bootstrap_error = not success
        self._required_runtime_bootstrap_progress = 100 if success else self._required_runtime_bootstrap_progress
        self._required_runtime_bootstrap_status = str(message or "").strip()
        self._required_runtime_bootstrap_open = not success
        self._app_settings_message = self._required_runtime_bootstrap_status
        self._app_settings_error = not success
        if success:
            self._refresh_home_service_items_cache()
            self.homeServiceChanged.emit()
            self.dataChanged.emit()
            self.redisRuntimeFeedbackChanged.emit()
        self.appSettingsFeedbackChanged.emit()

    def _run_required_runtime_bootstrap(self, progress) -> None:
        progress(2, "Checking local runtime state...")
        settings = self._container.settings_service.get_settings()
        if self._required_runtime_bootstrap_cache_valid():
            # Older completion markers may coexist with empty inventories and
            # unset active versions. Repair locally without reopening downloads.
            self._container.runtime_inventory_service.clear_and_rebuild_all()
            self._ensure_required_runtime_default_settings()
            self._write_required_runtime_bootstrap_cache()
            progress(100, "Installed runtimes activated.")
            return
        required_specs: list[tuple[str, str] | tuple[str, str, str]] = [
            ("apache", settings.default_apache_version.strip() or "apache-2.4.67"),
            ("nginx", settings.default_nginx_version.strip() or "nginx-1.31.0"),
            ("php", settings.default_php_version.strip() or "8.3.30"),
            ("phpmyadmin", "5.2.3", settings.phpmyadmin_php_version.strip() or "8.3.30"),
            ("mysql", settings.default_mysql_version.strip() or "mysql-8.4.9"),
            ("redis", settings.default_redis_version.strip() or "redis-8.6.3"),
            ("mailpit", settings.default_mailpit_version.strip() or "mailpit-1.29.7"),
            ("memcached", settings.default_memcached_version.strip() or "memcached-1.6.41"),
        ]

        parsed_specs: list[tuple[str, str, str]] = []
        for spec in required_specs:
            if len(spec) == 2:
                service, required = spec
                parsed_specs.append((service, required, ""))
            else:
                service, required, required_php = spec
                parsed_specs.append((service, required, required_php))

        # Recover inventories left stale by an interrupted or older bootstrap.
        self._container.runtime_inventory_service.clear_and_rebuild_all()
        if all(
            self._runtime_home_path(service, required) is not None
            and (not required_php or self._runtime_home_path("php", required_php) is not None)
            for service, required, required_php in parsed_specs
        ):
            self._ensure_required_runtime_default_settings()
            self._write_required_runtime_bootstrap_cache()
            progress(100, "All required runtimes are installed.")
            return

        local_by_service: dict[str, list[dict[str, object]]] = {}
        for service, _required, _required_php in parsed_specs:
            local_by_service[service] = self.runtimeManagerItems(service)

        manifest = self._fetch_runtime_manifest()
        items_raw = manifest.get("items", manifest.get("runtimes", manifest.get("runtime", [])))
        if isinstance(items_raw, dict):
            items_raw = list(items_raw.values())
        if not isinstance(items_raw, list):
            items_raw = []
        manifest_items: list[dict[str, object]] = []
        for raw in items_raw:
            if isinstance(raw, dict):
                manifest_items.append(self._normalize_server_runtime_item(raw))

        install_queue: list[dict[str, object]] = []
        missing_labels: list[str] = []
        bootstrap_items: list[dict[str, str]] = []
        for service, required, required_php in parsed_specs:
            service_items = [item for item in manifest_items if str(item.get("service") or "").strip().lower() == service]
            if not service_items:
                raise ValueError(f"Runtime manifest does not contain {service} packages.")
            selected: dict[str, object] | None = None
            if required:
                required_norm = required.strip().lower()
                for item in service_items:
                    item_id = str(item.get("id") or "").strip().lower()
                    version = str(item.get("version") or "").strip().lower()
                    folder_name = self._runtime_folder_name(service, version).strip().lower()
                    if required_norm in {item_id, version, folder_name}:
                        selected = item
                        break
            else:
                selected = sorted(
                    service_items,
                    key=lambda item: self._runtime_version_sort_key(str(item.get("version") or "")),
                    reverse=True,
                )[0]
            if selected is None:
                raise ValueError(f"Required {service} runtime ({required}) is not available in runtime manifest.")
            selected_id = str(selected.get("id") or "").strip().lower()
            selected_version = str(selected.get("version") or "").strip().lower()
            selected_folder = self._runtime_folder_name(service, selected_version).strip().lower()
            local_items = local_by_service.get(service, [])
            installed = self._runtime_install_target_path(selected).is_dir()
            for local in local_items:
                local_id = str(local.get("id") or "").strip().lower()
                local_ver = str(local.get("version") or "").strip().lower()
                if selected_id and local_id == selected_id:
                    installed = True
                    break
                if selected_version and local_ver == selected_version:
                    installed = True
                    break
                if selected_folder and local_id == selected_folder:
                    installed = True
                    break
            if not installed:
                install_queue.append(selected)
                selected_label = str(selected.get("label") or selected.get("id") or f"{service} {selected_version}")
                missing_labels.append(selected_label)
                bootstrap_items.append({"key": f"{service}:{selected_version}", "label": selected_label, "status": "pending"})
                if service == "phpmyadmin" and required_php:
                    php_runtime = self._container.php_runtime_service.get_runtime(required_php)
                    if php_runtime is None:
                        missing_labels.append(f"php {required_php}")

        self._required_runtime_bootstrap_open = bool(install_queue)
        self._required_runtime_bootstrap_missing = missing_labels
        self._required_runtime_bootstrap_items = bootstrap_items
        self.appSettingsFeedbackChanged.emit()
        if not install_queue:
            progress(100, "All required runtimes are installed.")
            self._ensure_required_runtime_default_settings()
            self._write_required_runtime_bootstrap_cache()
            return

        # Keep declared service order (apache/nginx before php), but enforce
        # php before phpmyadmin when both are missing.
        php_index = next(
            (idx for idx, queued in enumerate(install_queue)
             if str(queued.get("service") or "").strip().lower() == "php"
             and str(queued.get("version") or "").strip() == "8.3.30"),
            None,
        )
        pma_index = next(
            (idx for idx, queued in enumerate(install_queue)
             if str(queued.get("service") or "").strip().lower() == "phpmyadmin"),
            None,
        )
        if php_index is not None and pma_index is not None and php_index > pma_index:
            php_item = install_queue.pop(php_index)
            install_queue.insert(pma_index, php_item)

        total = len(install_queue)
        for index, item in enumerate(install_queue, start=1):
            service = str(item.get("service") or "").strip().lower()
            label = str(item.get("label") or item.get("id") or service)
            version = str(item.get("version") or "").strip()
            item_key = f"{service}:{version}"
            for row in self._required_runtime_bootstrap_items:
                if str(row.get("key") or "") == item_key:
                    row["status"] = "installing"
            self.appSettingsFeedbackChanged.emit()
            stage_start = int(((index - 1) / total) * 100)
            stage_span = max(1, int(100 / total))
            progress(stage_start, f"Installing {label} ({index}/{total})...")

            def item_progress(value: int, message: str) -> None:
                mapped = stage_start + int((max(0, min(int(value), 100)) / 100.0) * stage_span)
                progress(mapped, f"{label}: {message}")

            try:
                self._install_runtime_package(item, False, item_progress)
                # Default selection below must see the newly installed files,
                # not the inventory cached before the bootstrap started.
                self._container.runtime_inventory_service.clear_and_rebuild(
                    self._runtime_inventory_kind(service)
                )
                for row in self._required_runtime_bootstrap_items:
                    if str(row.get("key") or "") == item_key:
                        row["status"] = "done"
                self.appSettingsFeedbackChanged.emit()
            except Exception:
                for row in self._required_runtime_bootstrap_items:
                    if str(row.get("key") or "") == item_key:
                        row["status"] = "error"
                self.appSettingsFeedbackChanged.emit()
                raise

        self._ensure_required_runtime_default_settings()
        self._write_required_runtime_bootstrap_cache()
        progress(100, "All required runtimes installed.")

    def _required_runtime_bootstrap_cache_path(self) -> Path:
        return self._container.runtime_paths.runtime_dir / "required-runtimes.ready.json"

    def _required_runtime_bootstrap_cache_valid(self) -> bool:
        path = self._required_runtime_bootstrap_cache_path()
        if not path.exists():
            return False
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
            if not isinstance(payload, dict):
                return False
            items = payload.get("items")
            if not isinstance(items, list) or not items:
                return False
            for item in items:
                if not isinstance(item, dict):
                    return False
                service = str(item.get("service") or "").strip().lower()
                runtime_id = str(item.get("id") or "").strip()
                if not service or not runtime_id:
                    return False
            return True
        except Exception:
            return False

    def _write_required_runtime_bootstrap_cache(self) -> None:
        settings = self._container.settings_service.get_settings()
        items = [
            {"service": "apache", "id": settings.default_apache_version.strip() or "apache-2.4.67"},
            {"service": "nginx", "id": settings.default_nginx_version.strip() or "nginx-1.31.0"},
            {"service": "php", "id": "8.3.30"},
            {"service": "phpmyadmin", "id": "5.2.3"},
            {"service": "mysql", "id": settings.default_mysql_version.strip() or "mysql-8.4.9"},
            {"service": "redis", "id": settings.default_redis_version.strip() or "redis-8.6.3"},
            {"service": "mailpit", "id": settings.default_mailpit_version.strip() or "mailpit-1.29.7"},
            {"service": "memcached", "id": settings.default_memcached_version.strip() or "memcached-1.6.41"},
        ]
        payload = {
            "activation_version": 1,
            "generated_at": datetime.utcnow().isoformat() + "Z",
            "items": items,
        }
        path = self._required_runtime_bootstrap_cache_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    def _ensure_required_runtime_default_settings(self) -> None:
        current = self._container.settings_service.get_settings()
        apache_runtime = self._container.binary_locator.apache_home()
        nginx_runtime = self._container.binary_locator.nginx_home()
        default_apache = current.default_apache_version.strip() or "apache-2.4.67"
        default_nginx = current.default_nginx_version.strip() or "nginx-1.31.0"
        default_php = current.default_php_version.strip() or "8.3.30"
        default_phpmyadmin = "5.2.3"
        default_redis = current.default_redis_version.strip() or "redis-8.6.3"
        default_memcached = current.default_memcached_version.strip() or "memcached-1.6.41"
        default_mysql = current.default_mysql_version.strip() or "mysql-8.4.9"
        updates: dict[str, object] = {
            "default_server_type": current.default_server_type,
            "active_web_server": current.active_web_server,
            "default_apache_version": default_apache,
            "default_nginx_version": default_nginx,
            "default_php_version": default_php,
            "active_phpmyadmin_version": default_phpmyadmin,
            "phpmyadmin_php_version": default_php,
            "default_redis_version": default_redis,
            "default_memcached_version": default_memcached,
            "active_apache_version": default_apache if self._container.binary_locator.apache_runtime_home(default_apache) is not None else (apache_runtime.name if apache_runtime.exists() else current.active_apache_version),
            "active_nginx_version": default_nginx if self._container.binary_locator.nginx_runtime_home(default_nginx) is not None else (nginx_runtime.name if nginx_runtime.exists() else current.active_nginx_version),
            "preferred_database_engine": "mysql",
        }
        if self._container.php_runtime_service.get_runtime(default_php) is not None:
            updates["default_php_version"] = default_php
            updates["phpmyadmin_php_version"] = default_php
        if any(str(item.get("id") or "").strip() == default_phpmyadmin for item in self.runtimeManagerItems("phpmyadmin")):
            updates["active_phpmyadmin_version"] = default_phpmyadmin
        if self._container.database_runtime_service.resolve(default_mysql, preferred_engine="mysql") is not None:
            updates["default_mysql_version"] = default_mysql
            updates["active_database_version"] = default_mysql
        if self._container.redis_runtime_service.resolve(default_redis) is not None:
            updates["default_redis_version"] = default_redis
            updates["active_redis_version"] = default_redis
        if self._container.memcached_runtime_service.resolve(default_memcached) is not None:
            updates["default_memcached_version"] = default_memcached
            updates["active_memcached_version"] = default_memcached
        default_mailpit = current.default_mailpit_version.strip() or "mailpit-1.29.7"
        if self._runtime_home_path("mailpit", default_mailpit) is not None:
            updates["active_mailpit_version"] = default_mailpit
        # Bootstrap fills missing selections; existing valid user selections win.
        for service, field in (
            ("apache", "active_apache_version"),
            ("nginx", "active_nginx_version"),
            (current.preferred_database_engine, "active_database_version"),
            ("redis", "active_redis_version"),
            ("memcached", "active_memcached_version"),
            ("mailpit", "active_mailpit_version"),
            ("phpmyadmin", "active_phpmyadmin_version"),
        ):
            selected = getattr(current, field)
            if selected and self._runtime_home_path(service, selected) is not None:
                updates[field] = selected
                if field == "active_database_version":
                    updates["preferred_database_engine"] = current.preferred_database_engine
        settings = self._copy_settings(current, **updates)
        self._container.settings_service.save_settings(settings)

    def _fetch_runtime_manifest(self) -> dict[str, object]:
        base = self._container.license_service.license_api_url().rstrip("/")
        if not base:
            raise ValueError("License server is not configured.")
        url = base.rsplit("/server-engine/v1", 1)[0] + "/server-engine/v1/runtime/manifest"
        status = self._container.license_service.status()
        params = {
            "product": "server-engine",
            "device_id": self._container.license_service.device_id(),
        }
        license_key = str(status.license_key or "").strip()
        if license_key:
            params["license_key"] = license_key
        full_url = url + "?" + urllib.parse.urlencode(params)
        request = urllib.request.Request(
            full_url,
            headers=self._request_headers({"Accept": "application/json"}),
            method="GET",
        )
        ssl_context = default_ssl_context(full_url)
        try:
            with urllib.request.urlopen(request, timeout=20, context=ssl_context) as response:
                payload = json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            if exc.code in {401, 403}:
                raise ValueError("License is invalid or not found. Please check your license in Settings.") from exc
            raise ValueError(f"Runtime server request failed (HTTP {exc.code}).") from exc
        if not isinstance(payload, dict):
            raise ValueError("Runtime manifest response is invalid.")
        return payload

    def _normalize_server_runtime_item(self, raw: dict[str, object]) -> dict[str, object]:
        service = str(raw.get("service") or "").strip().lower()
        version = str(raw.get("version") or "").strip()
        platform_value = str(raw.get("platform") or raw.get("os") or "macos").strip()
        arch = str(raw.get("arch") or raw.get("architecture") or "").strip()
        runtime_id = str(raw.get("id") or raw.get("runtime_id") or self._runtime_folder_name(service, version)).strip()
        download_url = str(raw.get("downloadUrl") or raw.get("download_url") or raw.get("url") or raw.get("packageUrl") or "").strip()
        size_bytes = int(raw.get("sizeBytes") or raw.get("size_bytes") or 0)
        return {
            "id": runtime_id,
            "service": service,
            "version": version,
            "label": str(raw.get("label") or runtime_id or version),
            "platform": platform_value,
            "arch": arch,
            "status": str(raw.get("status") or "stable"),
            "downloadUrl": download_url,
            "sha256": str(raw.get("sha256") or raw.get("checksum") or ""),
            "sizeBytes": size_bytes,
            "sizeLabel": self._format_bytes(size_bytes),
            "releaseDate": str(raw.get("releaseDate") or raw.get("release_date") or ""),
            "releaseDateLabel": self._humanize_runtime_release_date(
                str(raw.get("releaseDate") or raw.get("release_date") or "")
            ),
        }

    def _runtime_version_sort_key(self, version: str) -> tuple[int, ...]:
        cleaned = str(version or "").strip().lower()
        if cleaned.startswith("v"):
            cleaned = cleaned[1:]
        parts = re.findall(r"\d+", cleaned)
        if not parts:
            return (0,)
        return tuple(int(part) for part in parts)

    def _humanize_runtime_release_date(self, raw_value: str) -> str:
        value = str(raw_value or "").strip()
        if not value:
            return "-"
        candidate = value.replace("Z", "+00:00")
        parsed: datetime | None = None
        try:
            parsed = datetime.fromisoformat(candidate)
        except Exception:
            parsed = None
        if parsed is None:
            for fmt in ("%Y-%m-%d", "%Y/%m/%d", "%d-%m-%Y"):
                try:
                    parsed = datetime.strptime(value, fmt)
                    break
                except Exception:
                    continue
        if parsed is None:
            return value
        return parsed.strftime("%b %d, %Y %H:%M")

    def _runtime_folder_name(self, service_id: str, version: str) -> str:
        service = "memcached" if service_id == "memcache" else service_id
        if service == "php":
            return "php" + version
        if service == "phpmyadmin":
            return version
        if service == "node":
            return "node" + version
        if service in {"apache", "nginx", "mysql", "mariadb", "mongodb", "postgresql", "redis", "memcached", "mailpit"}:
            return service + "-" + version
        return version

    def _runtime_install_root(self, service_id: str) -> Path:
        service = "memcached" if service_id == "memcache" else service_id
        locator = self._container.binary_locator
        if service == "php":
            return self._container.runtime_paths.bin_dir / "php"
        if service in {"apache", "nginx"}:
            return locator.deployed_apache_root()
        if service in {"mysql", "mariadb", "mongodb", "postgresql"}:
            return self._container.runtime_paths.bin_dir / "database"
        if service == "redis":
            return self._container.runtime_paths.bin_dir / "redis"
        if service == "memcached":
            return self._container.runtime_paths.bin_dir / "memcached"
        if service == "mailpit":
            return self._container.runtime_paths.bin_dir / "mailpit"
        if service == "node":
            return locator.deployed_node_root()
        if service == "phpmyadmin":
            return locator.deployed_tools_root() / "phpmyadmin"
        return self._container.runtime_paths.bin_dir / service

    def _runtime_install_target_path(self, item: dict[str, object]) -> Path:
        service = str(item.get("service") or "").strip().lower()
        version = str(item.get("version") or "").strip()
        runtime_id = str(item.get("id") or self._runtime_folder_name(service, version)).strip()
        return self._runtime_install_root(service) / runtime_id

    def _install_runtime_package(self, item: dict[str, object], overwrite: bool, progress) -> None:
        target = self._runtime_install_target_path(item)
        download_url = str(item.get("downloadUrl") or "").strip()
        expected_sha = str(item.get("sha256") or "").strip().lower()
        service = str(item.get("service") or "").strip().lower()
        runtime_id = str(item.get("id") or target.name).strip()
        archive_name = self._runtime_download_filename(download_url)
        package_is_pkg = archive_name.lower().endswith(".pkg")
        LOGGER.info(
            "Runtime install package start service=%s id=%s overwrite=%s source=%s target=%s expected_sha=%s kind=%s",
            service,
            runtime_id,
            overwrite,
            download_url,
            str(target),
            expected_sha,
            "pkg" if package_is_pkg else "tar",
        )
        if target.exists() and not overwrite:
            raise ValueError("Runtime already exists.")
        target.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="server-engine-runtime-install-") as tmp:
            tmp_path = Path(tmp)
            archive_path = tmp_path / archive_name
            progress(5, "Downloading...")
            parsed = urllib.parse.urlparse(download_url)
            cache_buster = str(int(time.time()))
            existing_query = parsed.query
            joined_query = (existing_query + "&" if existing_query else "") + "se_cache_bust=" + cache_buster
            bust_url = urllib.parse.urlunparse(parsed._replace(query=joined_query))
            LOGGER.info("Runtime install downloading from %s", bust_url)
            ssl_context = default_ssl_context(download_url)
            digest = hashlib.sha256()
            total = int(item.get("sizeBytes") or 0)
            received = 0
            retry_limit = 8
            retry_count = 0
            while True:
                headers = {
                    "User-Agent": "ServerEngineRuntimeInstaller/1.0",
                    "Cache-Control": "no-cache, no-store, must-revalidate",
                    "Pragma": "no-cache",
                    "Expires": "0",
                }
                headers = self._request_headers(headers)
                if received > 0:
                    headers["Range"] = f"bytes={received}-"
                request = urllib.request.Request(bust_url, headers=headers)
                try:
                    with urllib.request.urlopen(request, timeout=120, context=ssl_context) as response:
                        status_code = int(getattr(response, "status", 200) or 200)
                        if received > 0 and status_code == 200:
                            # Server ignored Range; restart from scratch to avoid corrupt archive.
                            received = 0
                            digest = hashlib.sha256()
                            if archive_path.exists():
                                archive_path.unlink()
                        if total <= 0:
                            total_header = int(response.headers.get("Content-Length") or 0)
                            if total_header > 0:
                                total = total_header + received
                        mode = "ab" if received > 0 else "wb"
                        with archive_path.open(mode) as fh:
                            while True:
                                chunk = response.read(1024 * 256)
                                if not chunk:
                                    break
                                fh.write(chunk)
                                digest.update(chunk)
                                received += len(chunk)
                                if total > 0:
                                    progress(
                                        5 + int((received / total) * 55),
                                        f"Downloading {self._format_bytes(received)} / {self._format_bytes(total)}",
                                    )
                    if total == 0 or received >= total:
                        break
                except Exception as exc:
                    retry_count += 1
                    if retry_count > retry_limit:
                        raise ValueError(
                            f"Runtime download failed after {retry_limit} retries: {exc}"
                        ) from exc
                    wait_seconds = min(6, retry_count)
                    progress(
                        min(60, 5 + int((received / max(total, 1)) * 55) if total > 0 else 20),
                        f"Network issue detected. Retrying download ({retry_count}/{retry_limit}) in {wait_seconds}s...",
                    )
                    time.sleep(wait_seconds)
                    continue
            actual_sha = digest.hexdigest()
            LOGGER.info(
                "Runtime install downloaded service=%s id=%s actual_sha=%s expected_sha=%s size=%s",
                service,
                runtime_id,
                actual_sha,
                expected_sha,
                archive_path.stat().st_size if archive_path.exists() else 0,
            )
            if expected_sha and actual_sha != expected_sha:
                raise ValueError(
                    "Downloaded runtime checksum does not match manifest. "
                    f"expected={expected_sha} actual={actual_sha}"
                )
            if target.exists():
                service = str(item.get("service") or "").strip().lower()
                runtime_id = str(item.get("id") or target.name)
                current = self._container.settings_service.get_settings()
                current_id = self._active_runtime_id_for_service(service, current)
                if current_id == runtime_id or current_id == target.name:
                    stop_ok, stop_message = self._stop_runtime_service_for_switch(service)
                    if not stop_ok:
                        raise ValueError(stop_message)
                    if stop_message:
                        progress(80, stop_message)
                self._backup_runtime_config_for_restore(service, runtime_id)
                shutil.rmtree(target)
            if package_is_pkg:
                progress(65, "Installing package...")
                installer_path = Path("/usr/sbin/installer")
                if not installer_path.exists():
                    raise ValueError("macOS installer tool is not available.")
                install_target = "CurrentUserHomeDirectory"
                LOGGER.info(
                    "Runtime install invoking installer service=%s id=%s package=%s target=%s",
                    service,
                    runtime_id,
                    str(archive_path),
                    install_target,
                )
                result = subprocess.run(
                    [str(installer_path), "-pkg", str(archive_path), "-target", install_target],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    check=False,
                )
                if result.returncode != 0:
                    output = "\n".join(part for part in (result.stdout.strip(), result.stderr.strip()) if part)
                    raise ValueError(
                        "macOS installer failed while installing runtime package."
                        + (f"\n{output}" if output else "")
                    )
                if not target.exists():
                    raise ValueError(f"Runtime installer finished but missing {target}.")
                self._verify_runtime_tree(target, progress)
                self._clear_quarantine_tree(target)
            else:
                progress(65, "Extracting...")
                extract_dir = tmp_path / "extract"
                extract_dir.mkdir()
                with tarfile.open(archive_path, "r:*") as tar:
                    self._safe_extract_tar(tar, extract_dir)
                candidates = [child for child in extract_dir.iterdir()]
                source = candidates[0] if len(candidates) == 1 and candidates[0].is_dir() else extract_dir
                self._verify_runtime_tree(source, progress)
                progress(85, "Installing...")
                if source == extract_dir:
                    target.mkdir(parents=True, exist_ok=True)
                    for child in extract_dir.iterdir():
                        shutil.move(str(child), str(target / child.name))
                else:
                    shutil.move(str(source), str(target))
                self._clear_quarantine_tree(target)
            LOGGER.info("Runtime install package finished service=%s id=%s target=%s", service, runtime_id, str(target))
            progress(100, "Installed.")

    def _runtime_download_filename(self, download_url: str) -> str:
        parsed = urllib.parse.urlparse(download_url)
        filename = Path(parsed.path).name.strip()
        if not filename:
            return "runtime-package.tar.gz"
        lowered = filename.lower()
        if lowered.endswith(".pkg"):
            return filename
        if lowered.endswith(".tar.gz") or lowered.endswith(".tgz"):
            return filename
        return "runtime-package.tar.gz"

    def _safe_extract_tar(self, tar: tarfile.TarFile, destination: Path) -> None:
        dest = destination.resolve()
        safe_members: list[tarfile.TarInfo] = []
        for member in tar.getmembers():
            member_path = (destination / member.name).resolve()
            if not str(member_path).startswith(str(dest) + os.sep) and member_path != dest:
                raise ValueError("Runtime archive contains unsafe paths.")

            # Drop unsafe symlink/hardlink members instead of failing whole install.
            # Some upstream runtime packages include legacy links (for example
            # rcmysql -> /etc/init.d/mysql) that are not needed for app runtime.
            if member.issym() or member.islnk():
                linkname = str(member.linkname or "")
                if linkname.startswith("/"):
                    continue
                base_dir = (destination / member.name).parent
                target_path = (base_dir / linkname).resolve()
                if not str(target_path).startswith(str(dest) + os.sep) and target_path != dest:
                    continue
            safe_members.append(member)
        tar.extractall(destination, members=safe_members)

    def _collect_runtime_macho_files(self, root: Path) -> list[Path]:
        candidates: list[Path] = []
        for path in root.rglob("*"):
            if not path.is_file() or path.is_symlink():
                continue
            if path.suffix in {".dylib", ".so"} or os.access(path, os.X_OK):
                candidates.append(path)
        return candidates

    def _verify_runtime_tree(self, root: Path, progress=None) -> None:
        if os.uname().sysname != "Darwin":
            return
        if progress is not None:
            progress(92, "Verifying runtime signatures...")
        candidates = self._collect_runtime_macho_files(root)
        if not candidates:
            return
        codesign_path = shutil.which("codesign")
        if codesign_path is None:
            LOGGER.warning("codesign not available; skipping runtime signature verification.")
            if progress is not None:
                progress(94, "codesign unavailable; skipping signature check.")
            return
        version_probe = subprocess.run([codesign_path, "--version"], capture_output=True, text=True, check=False)
        if version_probe.returncode != 0:
            LOGGER.warning("codesign is present but unusable; skipping runtime signature verification.")
            if progress is not None:
                progress(94, "codesign unusable; skipping signature check.")
            return
        for path in candidates:
            probe = subprocess.run(["file", str(path)], capture_output=True, text=True, check=False)
            if "Mach-O" not in (probe.stdout or ""):
                continue
            result = subprocess.run([codesign_path, "-dv", "--verbose=4", str(path)], capture_output=True, text=True, check=False)
            output = (result.stdout or "") + "\n" + (result.stderr or "")
            if result.returncode != 0:
                LOGGER.warning("codesign verification failed for %s; skipping signature enforcement.", path)
                if progress is not None:
                    progress(94, "codesign verification unavailable; skipping signature enforcement.")
                return
            if "Signature=adhoc" in output or "adhoc,linker-signed" in output or "TeamIdentifier=not set" in output:
                raise ValueError(f"Runtime is not Developer ID signed: {path}")
        if progress is not None:
            progress(94, "Runtime signatures verified.")

    def _clear_quarantine_tree(self, root: Path) -> None:
        if os.uname().sysname != "Darwin":
            return
        try:
            subprocess.run(
                ["xattr", "-dr", "com.apple.quarantine", str(root)],
                capture_output=True,
                text=True,
                check=False,
            )
        except Exception:
            return

    @Slot(str)
    def openRuntimePath(self, path_key: str) -> None:
        paths = {
            "runtime": self._container.runtime_paths.root,
            "config": self._container.runtime_paths.config_dir,
            "logs": self._container.runtime_paths.logs_dir,
            "backups": self._container.runtime_paths.backups_dir,
            "hosts": self._container.hosts_gateway.hosts_path,
        }
        target = paths.get(path_key.strip().lower())
        if target is None:
            self._last_operation_message = "Unknown runtime path."
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return
        try:
            if path_key.strip().lower() == "hosts":
                target.parent.mkdir(parents=True, exist_ok=True)
            elif target.suffix:
                target.parent.mkdir(parents=True, exist_ok=True)
            else:
                target.mkdir(parents=True, exist_ok=True)
            subprocess.Popen(["open", str(target)])
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()

    def _virtual_log_source_path(self, source_id: str) -> Path | None:
        if source_id.startswith("php-runtime-"):
            version = source_id.removeprefix("php-runtime-").replace("_", ".")
            return self._php_runtime_specific_log_path(version)
        if source_id.startswith("node-project-log-"):
            project_id = source_id.removeprefix("node-project-log-")
            return self._container.node_project_runtime_service.log_path(project_id)
        return None

    def _require_local_runtime(self, service_id: str, runtime_id: str) -> None:
        if service_id == "php":
            if self._container.binary_locator.php_runtime(runtime_id) is None:
                raise ValueError(f"PHP runtime {runtime_id} is not installed locally.")
            return
        if service_id == "apache":
            if self._container.binary_locator.apache_runtime_home(runtime_id) is None:
                raise ValueError(f"Apache runtime {runtime_id} is not installed locally.")
            return
        if service_id == "nginx":
            if self._container.binary_locator.nginx_runtime_home(runtime_id) is None:
                raise ValueError(f"Nginx runtime {runtime_id} is not installed locally.")
            return
        if service_id in SQL_DATABASE_RUNTIME_SERVICES:
            runtime = self._container.binary_locator.database_runtime(runtime_id, service_id)
            if runtime is None or runtime.engine != service_id:
                raise ValueError(f"{self._runtime_service_label(service_id)} runtime {runtime_id} is not installed locally.")
            return
        if service_id in OPTIONAL_DATABASE_RUNTIME_SERVICES:
            runtime = self._container.binary_locator.database_runtime(runtime_id, service_id)
            if runtime is None or runtime.engine != service_id:
                raise ValueError(f"{self._runtime_service_label(service_id)} runtime {runtime_id} is not installed locally.")
            return
        if service_id == "redis":
            if self._container.binary_locator.redis_runtime(runtime_id) is None:
                raise ValueError(f"Redis runtime {runtime_id} is not installed locally.")
            return
        if service_id == "memcached":
            if self._container.binary_locator.memcached_runtime(runtime_id) is None:
                raise ValueError(f"Memcached runtime {runtime_id} is not installed locally.")
            return
        if service_id == "mailpit":
            if self._container.binary_locator.mailpit_runtime(runtime_id) is None:
                raise ValueError(f"Mailpit runtime {runtime_id} is not installed locally.")
            return
        if service_id == "node":
            if self._container.binary_locator.node_runtime_home(runtime_id) is None:
                raise ValueError(f"Node runtime {runtime_id} is not installed locally.")
            return
        if service_id == "phpmyadmin":
            root = self._container.binary_locator.phpmyadmin_root(runtime_id)
            if root is None or not root.exists() or not root.is_dir():
                raise ValueError(f"phpMyAdmin runtime {runtime_id} is not installed locally.")

    def _active_runtime_id_for_service(self, service_id: str, settings) -> str:
        if service_id == "php":
            return settings.default_php_version
        if service_id == "phpmyadmin":
            return settings.active_phpmyadmin_version or self._container.config_service.phpmyadmin_root().name
        if service_id == "apache":
            return settings.active_apache_version or self._container.binary_locator.apache_home().name
        if service_id == "nginx":
            return settings.active_nginx_version or self._container.binary_locator.nginx_home().name
        if service_id in SQL_DATABASE_RUNTIME_SERVICES:
            active = settings.active_database_version or ""
            if active and active.startswith(service_id + "-"):
                return active
            return settings.default_mysql_version if service_id == "mysql" else settings.default_mariadb_version
        if service_id == "mongodb":
            active = settings.active_mongodb_version or ""
            if active:
                return active
            runtime = self._container.mongodb_service.active_runtime()
            return runtime.id if runtime is not None else ""
        if service_id == "postgresql":
            active = settings.active_postgresql_version or ""
            if active:
                return active
            runtime = self._container.postgresql_service.active_runtime()
            return runtime.id if runtime is not None else ""
        if service_id == "redis":
            return settings.active_redis_version or settings.default_redis_version or ""
        if service_id == "memcached":
            return settings.active_memcached_version or settings.default_memcached_version or ""
        if service_id == "mailpit":
            active = settings.active_mailpit_version or settings.default_mailpit_version or ""
            if active:
                return active
            runtime = self._container.binary_locator.mailpit_runtime()
            return runtime.id if runtime is not None else ""
        if service_id == "node":
            active = str(settings.active_node_version or "").strip()
            return ("node" + active) if active and not active.startswith("node") else active
        return ""

    def _runtime_activation_updates(self, service_id: str, target_id: str, current) -> dict[str, object]:
        if service_id == "php":
            return {"default_php_version": target_id}
        if service_id == "phpmyadmin":
            return {"active_phpmyadmin_version": target_id}
        if service_id == "apache":
            return {"active_apache_version": target_id}
        if service_id == "nginx":
            return {"active_nginx_version": target_id}
        if service_id in SQL_DATABASE_RUNTIME_SERVICES:
            runtime_passwords = dict(current.database_runtime_passwords or {})
            return {
                "preferred_database_engine": service_id,
                "active_database_version": target_id,
                "database_root_password": runtime_passwords.get(target_id, current.database_root_password),
                "database_runtime_passwords": runtime_passwords,
            }
        if service_id == "mongodb":
            return {"active_mongodb_version": target_id}
        if service_id == "postgresql":
            return {"active_postgresql_version": target_id}
        if service_id == "redis":
            return {"active_redis_version": target_id}
        if service_id == "memcached":
            return {"active_memcached_version": target_id}
        if service_id == "mailpit":
            return {"active_mailpit_version": target_id}
        return {}

    def _runtime_clear_updates(self, service_id: str) -> dict[str, object]:
        if service_id == "apache":
            return {"active_apache_version": None}
        if service_id == "nginx":
            return {"active_nginx_version": None}
        if service_id in SQL_DATABASE_RUNTIME_SERVICES:
            return {"active_database_version": None}
        if service_id == "mongodb":
            return {"active_mongodb_version": None}
        if service_id == "postgresql":
            return {"active_postgresql_version": None}
        if service_id == "redis":
            return {"active_redis_version": None}
        if service_id == "memcached":
            return {"active_memcached_version": None}
        if service_id == "mailpit":
            return {"active_mailpit_version": None}
        if service_id == "node":
            return {"active_node_version": None}
        if service_id == "php":
            remaining = [
                runtime.version for runtime in self._container.php_runtime_service.list_runtimes()
                if runtime.home and Path(runtime.home).exists()
            ]
            return {"default_php_version": remaining[-1] if remaining else "8.3.30"}
        if service_id == "phpmyadmin":
            remaining = self._container.binary_locator.available_phpmyadmin_versions()
            return {"active_phpmyadmin_version": remaining[-1] if remaining else "5.2.3"}
        return {}

    def _runtime_home_path(self, service_id: str, runtime_id: str) -> Path | None:
        if service_id == "php":
            runtime = self._container.binary_locator.php_runtime(runtime_id)
            return Path(runtime.home) if runtime is not None else None
        if service_id == "phpmyadmin":
            root = self._container.binary_locator.phpmyadmin_root(runtime_id)
            return root if root.exists() else None
        if service_id == "apache":
            return self._container.binary_locator.apache_runtime_home(runtime_id)
        if service_id == "nginx":
            return self._container.binary_locator.nginx_runtime_home(runtime_id)
        if service_id in SQL_DATABASE_RUNTIME_SERVICES or service_id in OPTIONAL_DATABASE_RUNTIME_SERVICES:
            runtime = self._container.binary_locator.database_runtime(runtime_id, service_id)
            return Path(runtime.home) if runtime is not None else None
        if service_id == "redis":
            runtime = self._container.binary_locator.redis_runtime(runtime_id)
            return Path(runtime.home) if runtime is not None else None
        if service_id == "memcached":
            runtime = self._container.binary_locator.memcached_runtime(runtime_id)
            return Path(runtime.home) if runtime is not None else None
        if service_id == "mailpit":
            runtime = self._container.binary_locator.mailpit_runtime(runtime_id)
            return Path(runtime.home) if runtime is not None else None
        if service_id == "node":
            runtime = self._container.binary_locator.node_runtime_home(runtime_id)
            return runtime if runtime is not None else None
        return None

    def _stop_runtime_service_for_switch(self, service_id: str) -> tuple[bool, str]:
        if service_id == "php":
            settings = self._container.settings_service.get_settings()
            active_web = "nginx" if settings.active_web_server == settings.active_web_server.NGINX else "apache"
            status = self._container.stack_service.status()
            running = any(item.service_id == active_web and item.state.value == "running" for item in status.services)
            if not running:
                return True, ""
            stopped = self._container.stack_service.stop_service(active_web)
            if stopped.state.value == "error":
                return False, stopped.message or "Could not stop web server."
            return True, "Web server was stopped before switching."
        if service_id in {"apache", "nginx"}:
            settings = self._container.settings_service.get_settings()
            active_web = "nginx" if settings.active_web_server == settings.active_web_server.NGINX else "apache"
            if active_web != service_id:
                return True, ""
            status = self._container.stack_service.status()
            running = any(item.service_id == service_id and item.state.value == "running" for item in status.services)
            if not running:
                return True, ""
            stopped = self._container.stack_service.stop_service(service_id)
            if stopped.state.value == "error":
                return False, stopped.message or f"Could not stop {self._runtime_service_label(service_id)}."
            return True, f"{self._runtime_service_label(service_id)} was stopped before switching."
        if service_id in SQL_DATABASE_RUNTIME_SERVICES:
            if self._container.database_service.status().state.value != "running":
                return True, ""
            result = self._container.database_service.stop_runtime()
            return result.success, result.message or "Database was stopped before switching."
        if service_id == "mongodb":
            if self._container.mongodb_service.status().state.value != "running":
                return True, ""
            result = self._container.mongodb_service.stop_runtime()
            return result.success, result.message or "MongoDB was stopped before switching."
        if service_id == "postgresql":
            if self._container.postgresql_service.status().state.value != "running":
                return True, ""
            result = self._container.postgresql_service.stop_runtime()
            return result.success, result.message or "PostgreSQL was stopped before switching."
        if service_id == "redis":
            if self._container.redis_service.status().state.value != "running":
                return True, ""
            result = self._container.redis_service.stop_runtime()
            return result.success, result.message or "Redis was stopped before switching."
        if service_id == "memcached":
            if self._container.memcached_service.status().state.value != "running":
                return True, ""
            result = self._container.memcached_service.stop_runtime()
            return result.success, result.message or "Memcached was stopped before switching."
        if service_id == "mailpit":
            if self._container.mailpit_service.status().state.value != "running":
                return True, ""
            result = self._container.mailpit_service.stop_runtime()
            return result.success, result.message or "Mailpit was stopped before switching."
        return True, ""

    def _copy_runtime_config(self, service_id: str, current_id: str, target_id: str) -> None:
        source_path = self._runtime_config_path(service_id, current_id)
        target_path = self._runtime_config_path(service_id, target_id)
        if source_path is None or target_path is None or source_path == target_path:
            return
        if not source_path.exists():
            return
        target_path.parent.mkdir(parents=True, exist_ok=True)
        if target_path.exists():
            backup_path = self._runtime_config_backup_path(target_path)
            backup_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(target_path, backup_path)
        shutil.copy2(source_path, target_path)

    def _runtime_config_path(self, service_id: str, runtime_id: str) -> Path | None:
        if service_id == "php":
            try:
                return self._php_ini_path(runtime_id)
            except Exception:
                runtime = self._container.binary_locator.php_runtime(runtime_id)
                if runtime is not None:
                    return Path(runtime.ini_dir) / "php.ini"
                return None
        if service_id == "apache":
            home = self._container.binary_locator.apache_runtime_home(runtime_id)
            key = home.name if home is not None else runtime_id
            return self._container.runtime_paths.config_dir / key / "httpd.conf"
        if service_id == "nginx":
            home = self._container.binary_locator.nginx_runtime_home(runtime_id)
            key = home.name if home is not None else runtime_id
            return self._container.runtime_paths.config_dir / key / "nginx.conf"
        if service_id in SQL_DATABASE_RUNTIME_SERVICES:
            runtime = self._container.binary_locator.database_runtime(runtime_id, service_id)
            if runtime is None:
                runtime = self._container.binary_locator.database_runtime(runtime_id)
            return self._container.database_service.config_path(runtime)
        if service_id == "mongodb":
            runtime = self._container.binary_locator.database_runtime(runtime_id, "mongodb")
            if runtime is None:
                return None
            return self._container.mongodb_service.config_path(runtime)
        if service_id == "postgresql":
            runtime = self._container.binary_locator.database_runtime(runtime_id, "postgresql")
            if runtime is None:
                return None
            return self._container.postgresql_service.config_path(runtime)
        if service_id == "redis":
            runtime = self._container.binary_locator.redis_runtime(runtime_id)
            return self._container.redis_service.config_path(runtime)
        if service_id == "memcached":
            runtime = self._container.binary_locator.memcached_runtime(runtime_id)
            return self._container.memcached_service.config_path(runtime)
        if service_id == "mailpit":
            runtime = self._container.binary_locator.mailpit_runtime(runtime_id)
            if runtime is None:
                return None
            return Path(runtime.home) / "config.toml"
        return None

    def _runtime_config_backup_path(self, path: Path) -> Path:
        timestamp = datetime.utcnow().strftime("%Y%m%d%H%M%S")
        return path.with_name(f"{path.name}.bak-{timestamp}")

    def _runtime_restore_config_path(self, service_id: str, runtime_id: str) -> Path:
        safe_service = service_id.strip().lower().replace("/", "_").replace("\\", "_") or "runtime"
        safe_runtime = runtime_id.strip().replace("/", "_").replace("\\", "_") or "unknown"
        return self._container.runtime_paths.backups_dir / "runtime-configs" / safe_service / safe_runtime / "config.restore"

    def _backup_runtime_config_for_restore(self, service_id: str, runtime_id: str) -> Path | None:
        source_path = self._runtime_config_path(service_id, runtime_id)
        if source_path is None or not source_path.exists():
            return None
        backup_path = self._runtime_restore_config_path(service_id, runtime_id)
        backup_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source_path, backup_path)
        return backup_path

    def _runtime_service_label(self, service_id: str) -> str:
        labels = {
            "php": "PHP",
            "apache": "Apache",
            "nginx": "Nginx",
            "mysql": "MySQL",
            "mariadb": "MariaDB",
            "mongodb": "MongoDB",
            "postgresql": "PostgreSQL",
            "redis": "Redis",
            "memcached": "Memcached",
            "mailpit": "Mailpit",
            "node": "Node",
            "phpmyadmin": "phpMyAdmin",
        }
        return labels.get(service_id, service_id.title())

    def _default_runtime_id_for_service(self, settings, service_id: str) -> str:
        if service_id == "php":
            return str(settings.default_php_version or "").strip()
        if service_id == "phpmyadmin":
            return str(settings.active_phpmyadmin_version or self._container.config_service.phpmyadmin_root().name or "").strip()
        if service_id == "apache":
            return str(settings.default_apache_version or settings.active_apache_version or self._container.binary_locator.apache_home().name or "").strip()
        if service_id == "nginx":
            return str(settings.default_nginx_version or settings.active_nginx_version or self._container.binary_locator.nginx_home().name or "").strip()
        if service_id == "mysql":
            return str(settings.default_mysql_version or "").strip()
        if service_id == "mariadb":
            return str(settings.default_mariadb_version or "").strip()
        if service_id == "redis":
            return str(settings.default_redis_version or "").strip()
        if service_id == "memcached":
            return str(settings.default_memcached_version or "").strip()
        if service_id == "mailpit":
            return str(settings.default_mailpit_version or "").strip()
        return ""

    def _is_protected_default_runtime(self, settings, service_id: str, runtime_id: str) -> bool:
        target = str(runtime_id or "").strip()
        if not target:
            return False
        default_id = self._default_runtime_id_for_service(settings, service_id)
        if default_id and target == default_id:
            return True
        home = self._runtime_home_path(service_id, target)
        if home is not None and home.name and home.name == default_id:
            return True
        return False

    def _allow_remove_default_runtimes(self) -> bool:
        value = os.environ.get("SERVER_ENGINE_ALLOW_REMOVE_DEFAULT_RUNTIME", "").strip().lower()
        return value in {"1", "true", "yes", "on"}

    def _validate_web_php_runtime_compat(self) -> tuple[bool, str]:
        missing: list[str] = []
        for site in self._container.site_service.list_sites():
            version = str(site.php_version or "").strip()
            if not version:
                continue
            if self._container.binary_locator.php_runtime(version) is None:
                missing.append(f"{site.local_domain} -> PHP {version}")
        if not missing:
            return True, ""
        details = "; ".join(missing[:6])
        if len(missing) > 6:
            details += f"; +{len(missing) - 6} more"
        return False, (
            "Web server start blocked: some websites use missing PHP runtimes. "
            f"Fix PHP version per site first. {details}"
        )

    def _missing_site_php_runtime_sites(self) -> list[object]:
        affected: list[object] = []
        for site in self._container.site_service.list_sites():
            version = str(site.php_version or "").strip()
            if not version:
                continue
            if self._container.binary_locator.php_runtime(version) is None:
                affected.append(site)
        return affected

    def _prompt_and_fix_missing_site_php_runtimes(self) -> tuple[bool, str]:
        affected = self._missing_site_php_runtime_sites()
        if not affected:
            return True, ""
        fallback_php = str(self._container.settings_service.get_settings().default_php_version or "").strip()
        if not fallback_php:
            return False, "No default PHP version configured."
        if self._container.binary_locator.php_runtime(fallback_php) is None:
            return False, f"Default PHP runtime {fallback_php} is not installed."

        preview_lines = [f"- {site.local_domain} (PHP {site.php_version})" for site in affected[:8]]
        suffix = f"\n...and {len(affected) - 8} more" if len(affected) > 8 else ""
        answer = QMessageBox.question(
            QApplication.activeWindow(),
            "Missing PHP Runtime",
            "Some websites use missing PHP runtimes.\n\n"
            + "\n".join(preview_lines)
            + suffix
            + f"\n\nAuto-fix now by switching them to default PHP {fallback_php}?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.Cancel,
            QMessageBox.StandardButton.Yes,
        )
        if answer != QMessageBox.StandardButton.Yes:
            return False, "Auto-fix cancelled."

        for site in affected:
            self._container.site_service.update_site(site.id, php_version=fallback_php)
        self.dataChanged.emit()
        return True, f"Auto-fixed {len(affected)} website(s) to PHP {fallback_php}."
