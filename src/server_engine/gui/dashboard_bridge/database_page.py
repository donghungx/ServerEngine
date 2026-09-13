from ._shared import *


LOGGER = logging.getLogger("server_engine.database")


class DatabasePageMixin(DashboardBridgeSignals):
    @Property("QVariantList", notify=dataChanged)
    def databaseRuntimeItems(self) -> list[dict[str, str]]:
        metadata = self._container.database_service.runtime_metadata()
        active_runtime = metadata.get("active_runtime") or {}
        active_runtime_id = str(active_runtime.get("id", ""))
        settings = self._container.settings_service.get_settings()
        items: list[dict[str, str]] = []
        for runtime in self._container.database_runtime_service.list_runtimes():
            is_active = runtime.id == active_runtime_id
            config_path = runtime.config_template_path or str(self._container.database_service.config_path())
            data_path = str(self._container.database_service.data_dir(runtime, create=False))
            items.append(
                {
                    "id": runtime.id,
                    "engine": runtime.engine,
                    "version": runtime.version,
                    "label": runtime.label,
                    "home": runtime.home,
                    "server_path": runtime.server_path,
                    "client_path": runtime.client_path or "",
                    "config_path": config_path,
                    "data_path": data_path,
                    "port": str(settings.database_port),
                    "status": "Active" if is_active else "Ready",
                }
            )
        return items

    @Property("QVariantList", notify=dataChanged)
    def databaseItems(self) -> list[dict[str, str]]:
        result = self._container.database_service.list_databases()
        if not result.success:
            return []
        runtime = result.payload.get("runtime") or {}
        port = str(result.payload.get("port", ""))
        items: list[dict[str, str]] = []
        for entry in result.payload.get("databases", []):
            name = str(entry.get("name", "")).strip()
            if not name:
                continue
            items.append(
                {
                    "name": name,
                    "engine": str(runtime.get("engine", "")).upper(),
                    "runtime": str(runtime.get("version", "")),
                    "host": "127.0.0.1",
                    "port": port,
                    "status": "Ready",
                }
            )
        return items

    @Property("QVariantList", notify=databaseBackupItemsChanged)
    def databaseBackupItems(self) -> list[dict[str, object]]:
        items = list(getattr(self, "_database_backup_items", []))
        LOGGER.debug(
            "databaseBackupItems getter: database=%s items=%d loading=%s",
            getattr(self, "_database_backup_items_database_name", ""),
            len(items),
            bool(getattr(self, "_database_backup_items_loading", False)),
        )
        return items

    @Property(bool, notify=databaseBackupItemsChanged)
    def databaseBackupItemsLoading(self) -> bool:
        loading = bool(getattr(self, "_database_backup_items_loading", False))
        LOGGER.debug(
            "databaseBackupItemsLoading getter: loading=%s database=%s pending=%s items=%d",
            loading,
            getattr(self, "_database_backup_items_database_name", ""),
            getattr(self, "_database_backup_items_pending_database_name", ""),
            len(getattr(self, "_database_backup_items", [])),
        )
        return loading

    @Slot(str)
    def refreshDatabaseBackupItemsAsync(self, database_name: str) -> None:
        cleaned = str(database_name or "").strip()
        LOGGER.debug(
            "refreshDatabaseBackupItemsAsync: requested database=%s loading=%s current=%s pending=%s",
            cleaned,
            bool(getattr(self, "_database_backup_items_loading", False)),
            getattr(self, "_database_backup_items_database_name", ""),
            getattr(self, "_database_backup_items_pending_database_name", ""),
        )
        if not cleaned:
            self._database_backup_items = []
            self._database_backup_items_database_name = ""
            self._database_backup_items_pending_database_name = ""
            self.databaseBackupItemsChanged.emit()
            return
        if self._database_backup_items_loading:
            self._database_backup_items_pending_database_name = cleaned
            return
        self._start_database_backup_items_job(cleaned)

    @Slot(str, object, bool, str)
    def _on_database_backup_items_ready(self, database_name: str, items, success: bool, message: str) -> None:
        LOGGER.debug(
            "_on_database_backup_items_ready: database=%s success=%s items=%d message=%s expected=%s pending=%s",
            database_name,
            success,
            len(items or []),
            message,
            getattr(self, "_database_backup_items_database_name", ""),
            getattr(self, "_database_backup_items_pending_database_name", ""),
        )
        if self._database_backup_items_database_name and str(database_name or "") != str(self._database_backup_items_database_name or ""):
            LOGGER.debug(
                "_on_database_backup_items_ready: stale result ignored database=%s expected=%s",
                database_name,
                getattr(self, "_database_backup_items_database_name", ""),
            )
            self._database_backup_items_loading = False
            self._database_backup_items_thread = None
            self._database_backup_items_worker = None
            pending = str(getattr(self, "_database_backup_items_pending_database_name", "") or "").strip()
            if pending and pending != self._database_backup_items_database_name:
                LOGGER.debug(
                    "_on_database_backup_items_ready: starting pending request database=%s",
                    pending,
                )
                self._database_backup_items_pending_database_name = ""
                self._start_database_backup_items_job(pending)
            return
        self._database_backup_items = list(items) if success else []
        self._database_backup_items_loading = False
        self._database_backup_items_thread = None
        self._database_backup_items_worker = None
        pending = str(getattr(self, "_database_backup_items_pending_database_name", "") or "").strip()
        if pending and pending != self._database_backup_items_database_name:
            LOGGER.debug(
                "_on_database_backup_items_ready: queue pending request database=%s after current=%s",
                pending,
                self._database_backup_items_database_name,
            )
            self._database_backup_items_pending_database_name = ""
            self._start_database_backup_items_job(pending)
        self.databaseBackupItemsChanged.emit()

    def _start_database_backup_items_job(self, database_name: str) -> None:
        cleaned = str(database_name or "").strip()
        if not cleaned:
            return
        LOGGER.debug(
            "_start_database_backup_items_job: database=%s current_items=%d loading=%s",
            cleaned,
            len(getattr(self, "_database_backup_items", [])),
            bool(getattr(self, "_database_backup_items_loading", False)),
        )
        self._database_backup_items_loading = True
        self._database_backup_items_database_name = cleaned
        thread = QThread(self)
        worker = DatabaseBackupItemsWorker(self._container.database_service, cleaned)
        worker.moveToThread(thread)
        worker.completed.connect(self._on_database_backup_items_ready)
        worker.completed.connect(thread.quit)
        thread.started.connect(worker.run)
        thread.finished.connect(worker.deleteLater)
        thread.finished.connect(thread.deleteLater)
        self._database_backup_items_thread = thread
        self._database_backup_items_worker = worker
        thread.start()

    @Property(str, notify=databaseRuntimeFeedbackChanged)
    def activeDatabaseRuntimeBrand(self) -> str:
        runtime = self._container.database_service.active_runtime()
        if runtime is None:
            return "Database"
        if runtime.engine.lower() == "mariadb":
            return "MariaDB"
        if runtime.engine.lower() == "mysql":
            return "MySQL"
        return runtime.engine

    @Property(str, notify=databaseRuntimeFeedbackChanged)
    def activeDatabaseRuntimeHome(self) -> str:
        runtime = self._container.database_service.active_runtime()
        return runtime.home if runtime else ""

    @Property(str, notify=databaseRuntimeFeedbackChanged)
    def activeDatabaseDataDir(self) -> str:
        runtime = self._container.database_service.active_runtime()
        return str(self._container.database_service.data_dir(runtime, create=False))

    @Property(str, notify=databaseRuntimeFeedbackChanged)
    def activeDatabaseConfigPath(self) -> str:
        return str(self._container.database_service.config_path())

    @Property(str, notify=databaseRuntimeFeedbackChanged)
    def activeDatabaseConfigContent(self) -> str:
        path = self._container.database_service.config_path()
        try:
            if path.exists():
                return path.read_text(encoding="utf-8")
        except Exception:
            pass
        return ""

    def _database_config_original_backup_path(self) -> Path:
        path = self._container.database_service.config_path()
        return path.with_suffix(path.suffix + ".original")

    def _database_config_last_backup_path(self) -> Path:
        path = self._container.database_service.config_path()
        return path.with_suffix(path.suffix + ".bak")

    def _atomic_write_text(self, path: Path, content: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as handle:
            handle.write(content)
            temp_path = Path(handle.name)
        temp_path.replace(path)

    @Slot(str, result=bool)
    def saveActiveDatabaseConfigContent(self, content: str) -> bool:
        try:
            if not str(content).strip():
                raise ValueError("Database config cannot be empty.")
            config_path = self._container.database_service.config_path()
            config_path.parent.mkdir(parents=True, exist_ok=True)
            current_text = config_path.read_text(encoding="utf-8") if config_path.exists() else ""

            original_backup = self._database_config_original_backup_path()
            last_backup = self._database_config_last_backup_path()

            if config_path.exists() and not original_backup.exists():
                self._atomic_write_text(original_backup, current_text)
            if config_path.exists():
                self._atomic_write_text(last_backup, current_text)

            self._atomic_write_text(config_path, str(content))
            self._database_runtime_message = (
                f"Saved database config with backup.\nOriginal: {original_backup}\nLatest backup: {last_backup}"
            )
            self._database_runtime_error = False
            self.databaseRuntimeFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._database_runtime_message = str(exc)
            self._database_runtime_error = True
            self.databaseRuntimeFeedbackChanged.emit()
            return False

    @Slot(result=bool)
    def restoreActiveDatabaseConfigOriginal(self) -> bool:
        try:
            config_path = self._container.database_service.config_path()
            original_backup = self._database_config_original_backup_path()
            if not original_backup.exists():
                raise ValueError("Original backup not found. Save the config once first.")
            current_text = config_path.read_text(encoding="utf-8") if config_path.exists() else ""
            self._atomic_write_text(self._database_config_last_backup_path(), current_text)
            self._atomic_write_text(config_path, original_backup.read_text(encoding="utf-8"))
            self._database_runtime_message = f"Restored original config from {original_backup}"
            self._database_runtime_error = False
            self.databaseRuntimeFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._database_runtime_message = str(exc)
            self._database_runtime_error = True
            self.databaseRuntimeFeedbackChanged.emit()
            return False

    @Property(str, notify=databaseRuntimeFeedbackChanged)
    def activeDatabasePort(self) -> str:
        return str(self._container.settings_service.get_settings().database_port)

    @Property(int, notify=databaseRuntimeFeedbackChanged)
    def activeDatabaseCount(self) -> int:
        return len(self.databaseItems)

    @Property(str, notify=databaseRuntimeFeedbackChanged)
    def activeDatabaseLogPath(self) -> str:
        return str(self._container.database_service.log_path())

    @Property(str, notify=databaseRuntimeFeedbackChanged)
    def activeDatabaseRuntimeHost(self) -> str:
        return "127.0.0.1"

    @Property(str, notify=databaseRuntimeFeedbackChanged)
    def activeDatabaseRuntimeSocket(self) -> str:
        return str(self._container.database_service.socket_path())

    @Property(str, notify=databaseRuntimeFeedbackChanged)
    def activeDatabaseRuntimeStartedAt(self) -> str:
        return str(getattr(self, "_database_runtime_started_at", ""))

    @Slot(result="QVariantMap")
    def databaseRuntimeSettings(self) -> dict[str, object]:
        return dict(getattr(self, "_database_runtime_settings", {
            "bind_address": "127.0.0.1",
            "time_zone": "UTC",
            "wait_timeout": "900",
            "interactive_timeout": "900",
            "log_queries_not_using_indexes": False,
            "log_slow_admin_statements": False,
            "log_slow_extra": False,
            "log_throttle_queries_not_using_indexes": "0",
        }))

    @Slot("QVariantMap", result=bool)
    def saveDatabaseRuntimeSettings(self, values: dict) -> bool:
        self._database_runtime_settings = self.databaseRuntimeSettings()
        self._database_runtime_settings.update(dict(values or {}))
        self._database_runtime_message = "Database runtime settings saved. Restart the runtime to apply."
        self._database_runtime_error = False
        self.databaseRuntimeFeedbackChanged.emit()
        return True

    @Property(bool, notify=databaseRuntimeFeedbackChanged)
    def supportsDatabaseQueryCache(self) -> bool:
        runtime = self._container.database_service.active_runtime()
        if runtime is None:
            return True
        engine = str(runtime.engine or "").strip().lower()
        if engine != "mysql":
            return True
        try:
            major = int(str(runtime.version).split(".", 1)[0])
            return major < 8
        except Exception:
            return True

    @Slot(result="QVariantMap")
    def databaseOptimizationSettings(self) -> dict[str, int]:
        settings = self._container.settings_service.get_settings()
        return dict(settings.database_optimization or {})

    @Slot("QVariantMap", result=bool)
    def saveDatabaseOptimizationSettings(self, values: dict) -> bool:
        try:
            current = self._container.settings_service.get_settings()
            defaults = current.database_optimization or {}
            supports_query_cache = self.supportsDatabaseQueryCache
            normalized: dict[str, int] = {}
            for key, default_value in defaults.items():
                if key == "query_cache_size_mb" and not supports_query_cache:
                    normalized[key] = 0
                    continue
                raw = values.get(key, default_value)
                number = int(str(raw).strip())
                if number < 0:
                    raise ValueError(f"{key} must be >= 0.")
                normalized[key] = number
            if normalized.get("table_open_cache", 0) > 2048:
                raise ValueError("table_open_cache must not exceed 2048.")
            settings = self._copy_settings(current, database_optimization=normalized)
            self._container.settings_service.save_settings(settings)
            self._database_runtime_message = "Optimization settings saved. Restart database runtime to apply."
            self._database_runtime_error = False
            self.databaseRuntimeFeedbackChanged.emit()
            self.dataChanged.emit()
            return True
        except Exception as exc:
            self._database_runtime_message = str(exc)
            self._database_runtime_error = True
            self.databaseRuntimeFeedbackChanged.emit()
            return False

    @Property(str, notify=databaseRuntimeFeedbackChanged)
    def activeDatabaseRuntimeLabel(self) -> str:
        runtime = self._container.database_service.active_runtime()
        if runtime is None:
            return "No runtime selected"
        engine = runtime.engine.title()
        return f"{engine} {runtime.version}"

    @Property(str, notify=databaseRuntimeFeedbackChanged)
    def activeDatabaseServiceState(self) -> str:
        return getattr(self, "_database_service_state_cache", "Stopped")

    @Property(str, notify=databaseRuntimeFeedbackChanged)
    def databaseRootPassword(self) -> str:
        return self._container.database_service.root_password()

    @Slot(str, str, result=bool)
    def createDatabase(self, name: str, charset: str) -> bool:
        result = self._container.database_service.create_database(name, charset)
        self._database_runtime_message = result.message
        self._database_runtime_error = not result.success
        self._database_runtime_log = self._container.database_service.read_log_tail()
        self.dataChanged.emit()
        self.databaseRuntimeFeedbackChanged.emit()
        return result.success

    @Slot(str, result=str)
    def validateNewDatabaseName(self, name: str) -> str:
        cleaned = name.strip()
        if not cleaned:
            return "Database name is required."
        if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", cleaned):
            return "Database name must start with a letter or underscore and use only letters, numbers, and underscores."

        result = self._container.database_service.list_databases()
        if not result.success:
            return result.message or "Could not check database name."

        for entry in result.payload.get("databases", []):
            existing = str(entry.get("name", "")).strip().lower()
            if existing == cleaned.lower():
                return "Database already exists. Choose another name."
        return ""

    @Slot(str, result=bool)
    def dropDatabase(self, name: str) -> bool:
        result = self._container.database_service.drop_database(name)
        self._database_runtime_message = result.message
        self._database_runtime_error = not result.success
        self._database_runtime_log = self._container.database_service.read_log_tail()
        self.dataChanged.emit()
        self.databaseRuntimeFeedbackChanged.emit()
        return result.success

    @Slot(str, result=bool)
    def updateDatabaseRootPassword(self, new_password: str) -> bool:
        result = self._container.database_service.update_root_password(new_password)
        self._database_runtime_message = result.message
        self._database_runtime_error = not result.success
        self._database_runtime_log = self._container.database_service.read_log_tail()
        self.dataChanged.emit()
        self.databaseRuntimeFeedbackChanged.emit()
        return result.success

    @Property(str, notify=databaseRuntimeFeedbackChanged)
    def databaseBackupMessage(self) -> str:
        return self._database_backup_message

    @Property(bool, notify=databaseRuntimeFeedbackChanged)
    def databaseBackupError(self) -> bool:
        return self._database_backup_error

    @Property(int, notify=databaseRuntimeFeedbackChanged)
    def databaseBackupProgress(self) -> int:
        return self._database_backup_progress

    @Property(str, notify=databaseRuntimeFeedbackChanged)
    def databaseBackupProgressLabel(self) -> str:
        return self._database_backup_progress_label

    @Property(str, notify=databaseRuntimeFeedbackChanged)
    def databaseBackupJobTitle(self) -> str:
        return self._database_backup_job_title

    @Property(str, notify=databaseRuntimeFeedbackChanged)
    def databaseImportMessage(self) -> str:
        return self._database_import_message

    @Property(bool, notify=databaseRuntimeFeedbackChanged)
    def databaseImportError(self) -> bool:
        return self._database_import_error

    @Property(int, notify=databaseRuntimeFeedbackChanged)
    def databaseImportProgress(self) -> int:
        return self._database_import_progress

    @Property(str, notify=databaseRuntimeFeedbackChanged)
    def databaseImportProgressLabel(self) -> str:
        return self._database_import_progress_label

    @Property(str, notify=databaseRuntimeFeedbackChanged)
    def databaseImportJobTitle(self) -> str:
        return self._database_import_job_title

    @Property(str, notify=databaseRuntimeFeedbackChanged)
    def databaseImportSelectedPath(self) -> str:
        return self._database_import_selected_path

    @Property(str, notify=databaseRuntimeFeedbackChanged)
    def databaseImportDetails(self) -> str:
        return self._database_import_details

    @Slot(str, result=bool)
    def createDatabaseBackup(self, database_name: str) -> bool:
        cleaned = database_name.strip()
        if not cleaned:
            return False
        self._enqueue_database_job("backup", cleaned, f"Backing up {cleaned or 'database'}")
        return True

    @Slot(str, str, result=bool)
    def restoreDatabaseBackup(self, archive_path: str, database_name: str) -> bool:
        cleaned = archive_path.strip()
        cleaned_name = database_name.strip()
        if not cleaned:
            return False
        title = f"Restoring {cleaned_name or 'database'}"
        self._enqueue_database_job("restore", cleaned, title)
        return True

    @Slot(str, result=bool)
    def deleteDatabaseBackup(self, archive_path: str) -> bool:
        if self._database_backup_busy:
            return False
        result = self._container.database_service.delete_backup(archive_path)
        self._database_backup_message = ""
        self._database_backup_error = False
        self._last_operation_message = result.message
        self._last_operation_error = not result.success
        self.operationFeedbackChanged.emit()
        self.dataChanged.emit()
        self.databaseRuntimeFeedbackChanged.emit()
        return bool(result.success)

    @Slot(result=bool)
    def cancelDatabaseBackupJob(self) -> bool:
        if not self._database_backup_busy or self._database_backup_worker is None:
            return False
        self._database_backup_worker.cancel()
        self._database_backup_message = "Cancelling job..."
        self._database_backup_error = False
        self.databaseRuntimeFeedbackChanged.emit()
        return True

    @Slot(result=bool)
    def openPhpMyAdmin(self) -> bool:
        if self._phpmyadmin_busy:
            return False
        self._phpmyadmin_busy = True
        self.actionStateChanged.emit()
        thread = QThread(self)
        worker = PhpMyAdminWorker(self._container)
        worker.moveToThread(thread)
        worker.completed.connect(self._on_phpmyadmin_open_completed)
        worker.completed.connect(thread.quit)
        thread.started.connect(worker.run)
        thread.finished.connect(worker.deleteLater)
        thread.finished.connect(thread.deleteLater)
        self._phpmyadmin_thread = thread
        self._phpmyadmin_worker = worker
        thread.start()
        return True

    @Slot(result=str)
    def chooseDatabaseImportFile(self) -> str:
        parent = QApplication.activeWindow()
        selected, _ = QFileDialog.getOpenFileName(
            parent,
            "Choose Database Import File",
            "",
            "Database Files (*.sql *.zip *.tar.gz *.tgz *.gz)",
        )
        if selected:
            self._database_import_selected_path = selected
            self._database_import_message = ""
            self._database_import_error = False
            self._database_import_details = "Selected file: " + selected
            self.databaseRuntimeFeedbackChanged.emit()
        return selected

    @Slot(str, str, bool, result=bool)
    def importDatabaseFile(self, database_name: str, import_path: str, clear_existing: bool = False) -> bool:
        cleaned_name = database_name.strip()
        cleaned_path = import_path.strip()
        if not cleaned_name or not cleaned_path:
            self._database_import_message = "Database name and import file are required."
            self._database_import_error = True
            self.databaseRuntimeFeedbackChanged.emit()
            return False
        self._database_import_selected_path = cleaned_path
        flag = "1" if clear_existing else "0"
        self._enqueue_database_job(
            "import",
            cleaned_name + "\n" + cleaned_path + "\n" + flag,
            f"Importing SQL into {cleaned_name}",
        )
        return True

    @Slot()
    def clearDatabaseImportSelection(self) -> None:
        self._database_import_selected_path = ""
        if not self._database_import_busy:
            self._database_import_details = ""
            self._database_import_message = ""
            self._database_import_error = False
            self._database_import_progress = 0
            self._database_import_progress_label = ""
            self._database_import_job_title = ""
        self.databaseRuntimeFeedbackChanged.emit()

    @Slot()
    def clearDatabaseRuntimeFeedback(self) -> None:
        self._database_runtime_message = ""
        self._database_runtime_error = False
        self._database_backup_message = ""
        self._database_backup_error = False
        if not self._database_backup_busy:
            self._database_backup_progress = 0
            self._database_backup_progress_label = ""
            self._database_backup_job_title = ""
        self._database_import_message = ""
        self._database_import_error = False
        if not self._database_import_busy:
            self._database_import_progress = 0
            self._database_import_progress_label = ""
            self._database_import_details = ""
            self._database_import_job_title = ""
        self.databaseRuntimeFeedbackChanged.emit()

    @Slot(str, result="QVariantList")
    def databaseRuntimesByEngine(self, engine: str) -> list[dict[str, str]]:
        filtered: list[dict[str, str]] = []
        target = engine.strip().lower()
        for item in self.databaseRuntimeItems:
            item_engine = str(item.get("engine", "")).strip().lower()
            if not target or item_engine == target:
                filtered.append(item)
        return filtered

    @Slot(str, result=bool)
    def updateDatabaseRuntimePort(self, database_port: str) -> bool:
        try:
            current = self._container.settings_service.get_settings()
            normalized_database_port = self._parse_port_value(database_port, "Database")
            current_port = int(current.database_port)
            if normalized_database_port != current_port and not self._is_tcp_port_available(normalized_database_port):
                raise ValueError(f"Port {normalized_database_port} is already in use.")
            settings = self._copy_settings(
                current,
                database_port=normalized_database_port,
            )
            self._container.settings_service.save_settings(settings)
            self._database_runtime_message = (
                f"Database port saved as {normalized_database_port}. Restart database runtime to apply."
            )
            self._database_runtime_error = False
            self.dataChanged.emit()
            self.databaseRuntimeFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._database_runtime_message = str(exc)
            self._database_runtime_error = True
            self.databaseRuntimeFeedbackChanged.emit()
            return False

    @Property(str, notify=databaseRuntimeFeedbackChanged)
    def databaseRuntimeMessage(self) -> str:
        return self._database_runtime_message

    @Property(bool, notify=databaseRuntimeFeedbackChanged)
    def databaseRuntimeError(self) -> bool:
        return self._database_runtime_error

    @Property(str, notify=databaseRuntimeFeedbackChanged)
    def databaseRuntimeLog(self) -> str:
        return self._database_runtime_log

    @Property(bool, notify=actionStateChanged)
    def databaseBackupBusy(self) -> bool:
        return self._database_backup_busy

    @Property(bool, notify=actionStateChanged)
    def databaseImportBusy(self) -> bool:
        return self._database_import_busy

    @Property(bool, notify=actionStateChanged)
    def databaseJobsQueued(self) -> bool:
        return bool(self._database_job_queue)

    @Property(bool, notify=actionStateChanged)
    def databaseAnyJobBusy(self) -> bool:
        return bool(
            self._database_backup_busy
            or self._database_import_busy
            or self._postgresql_backup_busy
            or self._postgresql_import_busy
            or self._mongodb_backup_busy
            or self._mongodb_import_busy
            or self._database_action_busy
            or self._postgresql_action_busy
            or self._mongodb_action_busy
            or self._database_job_queue
        )

    def _start_database_backup_job(self, mode: str, value: str) -> None:
        self._database_backup_busy = True
        self.actionStateChanged.emit()
        self.databaseRuntimeFeedbackChanged.emit()
        thread = QThread(self)
        worker = DatabaseBackupWorker(self._container.database_service, mode, value)
        worker.moveToThread(thread)
        worker.progressChanged.connect(self._on_database_backup_progress)
        worker.completed.connect(self._on_database_backup_completed)
        worker.completed.connect(thread.quit)
        thread.started.connect(worker.run)
        thread.finished.connect(worker.deleteLater)
        thread.finished.connect(thread.deleteLater)
        self._database_backup_thread = thread
        self._database_backup_worker = worker
        thread.start()

    def _start_database_import_job(self, database_name: str, import_path: str, clear_existing: bool = False) -> None:
        self._database_import_busy = True
        self.actionStateChanged.emit()
        self.databaseRuntimeFeedbackChanged.emit()
        thread = QThread(self)
        flag = "1" if clear_existing else "0"
        worker = DatabaseBackupWorker(
            self._container.database_service,
            "import",
            database_name + "\n" + import_path + "\n" + flag,
        )
        worker.moveToThread(thread)
        worker.progressChanged.connect(self._on_database_import_progress)
        worker.completed.connect(self._on_database_import_completed)
        worker.completed.connect(thread.quit)
        thread.started.connect(worker.run)
        thread.finished.connect(worker.deleteLater)
        thread.finished.connect(thread.deleteLater)
        self._database_import_thread = thread
        self._database_import_worker = worker
        thread.start()

    def _enqueue_database_job(self, mode: str, value: str, title: str) -> bool:
        job = {
            "mode": mode,
            "value": value,
            "title": title,
        }
        self._database_job_queue.append(job)
        self.actionStateChanged.emit()
        if self._database_backup_busy or self._database_import_busy:
            self._database_runtime_message = f"Queued {title.lower()}."
            self._database_runtime_error = False
            self.databaseRuntimeFeedbackChanged.emit()
            return True
        self._start_next_database_job()
        return True

    def _start_next_database_job(self) -> None:
        if self._database_backup_busy or self._database_import_busy:
            return
        if not getattr(self, "_database_job_queue", None):
            return
        job = self._database_job_queue.popleft()
        self.actionStateChanged.emit()
        mode = str(job.get("mode", ""))
        value = str(job.get("value", ""))
        title = str(job.get("title", ""))
        if mode == "backup":
            cleaned = value.strip()
            self._database_backup_message = ""
            self._database_backup_error = False
            self._database_backup_progress = 0
            self._database_backup_progress_label = "Starting backup..."
            self._database_backup_job_title = title or f"Backing up {cleaned or 'database'}"
            self._database_backup_items_reload_database_name = cleaned
            QTimer.singleShot(
                1000,
                lambda mode=mode, value=value: self._start_database_backup_job(mode, value),
            )
        elif mode == "restore":
            cleaned_path = value.strip()
            self._database_backup_message = ""
            self._database_backup_error = False
            self._database_backup_progress = 0
            self._database_backup_progress_label = "Starting restore..."
            self._database_backup_job_title = title or "Restoring database backup"
            QTimer.singleShot(
                1000,
                lambda mode=mode, value=value: self._start_database_backup_job(mode, value),
            )
        elif mode == "import":
            database_name, import_path = value.split("\n", 1)
            self._database_import_message = ""
            self._database_import_error = False
            self._database_import_progress = 0
            self._database_import_job_title = title or f"Importing SQL into {database_name.strip() or 'database'}"
            self._database_import_progress_label = self._database_import_job_title
            self._database_import_details = "Preparing import for " + database_name.strip() + "\nSource: " + import_path.strip()
            self._database_import_busy = True
            self.actionStateChanged.emit()
            self.databaseRuntimeFeedbackChanged.emit()
            thread = QThread(self)
            worker = DatabaseBackupWorker(self._container.database_service, "import", value)
            worker.moveToThread(thread)
            worker.progressChanged.connect(self._on_database_import_progress)
            worker.completed.connect(self._on_database_import_completed)
            worker.completed.connect(thread.quit)
            thread.started.connect(worker.run)
            thread.finished.connect(worker.deleteLater)
            thread.finished.connect(thread.deleteLater)
            self._database_import_thread = thread
            self._database_import_worker = worker
            thread.start()

    @Slot(int, str)
    def _on_database_backup_progress(self, value: int, message: str) -> None:
        self._database_backup_progress = value
        self._database_backup_progress_label = message
        self.databaseRuntimeFeedbackChanged.emit()

    @Slot(bool, str, bool)
    def _on_database_backup_completed(self, success: bool, message: str, canceled: bool) -> None:
        self._database_backup_busy = False
        self._database_backup_message = message
        self._database_backup_error = False if canceled else not success
        self._database_backup_progress = 0
        self._database_backup_progress_label = "Done" if success else ""
        self._database_backup_job_title = ""
        self._database_backup_thread = None
        self._database_backup_worker = None
        self.dataChanged.emit()
        self.databaseRuntimeFeedbackChanged.emit()
        self.actionStateChanged.emit()
        reload_database_name = str(getattr(self, "_database_backup_items_reload_database_name", "") or "").strip()
        self._database_backup_items_reload_database_name = ""
        if reload_database_name:
            self.refreshDatabaseBackupItemsAsync(reload_database_name)
        self._start_next_database_job()

    @Slot(bool, str)
    def _on_phpmyadmin_open_completed(self, success: bool, message: str) -> None:
        self._phpmyadmin_busy = False
        self._phpmyadmin_thread = None
        self._phpmyadmin_worker = None
        self._database_runtime_message = message
        self._database_runtime_error = not success
        self.databaseRuntimeFeedbackChanged.emit()
        self.dataChanged.emit()
        self.actionStateChanged.emit()

    @Slot(bool, str)
    def _on_database_restart_completed(self, success: bool, message: str) -> None:
        final_running = getattr(self, "_database_service_state_cache", "Stopped").lower() == "running"
        if final_running:
            success = True
            message = message or "Database restarted."
        self._database_runtime_message = message
        self._database_runtime_error = not success
        self._database_runtime_log = self._container.database_service.read_log_tail()
        self._database_service_state_cache = "Running" if success else "Stopped"
        self._database_action_busy = False
        self._database_restart_thread = None
        self._database_restart_worker = None
        self.databaseRuntimeFeedbackChanged.emit()
        self.dataChanged.emit()
        self.actionStateChanged.emit()

    @Slot(int, str)
    def _on_database_import_progress(self, value: int, message: str) -> None:
        self._database_import_progress = value
        details = self._database_import_details.splitlines() if self._database_import_details else []
        if not details or details[-1] != message:
            details.append(message)
            self._database_import_details = "\n".join(details[-12:])
        self.databaseRuntimeFeedbackChanged.emit()

    @Slot(bool, str, bool)
    def _on_database_import_completed(self, success: bool, message: str, canceled: bool) -> None:
        self._database_import_busy = False
        self._database_import_message = message
        self._database_import_error = False if canceled else not success
        self._database_import_progress = 0
        self._database_import_progress_label = "Done" if success else ""
        self._database_import_job_title = ""
        details = self._database_import_details.splitlines() if self._database_import_details else []
        details.append(message)
        self._database_import_details = "\n".join(details[-12:])
        self._database_import_thread = None
        self._database_import_worker = None
        self.dataChanged.emit()
        self.databaseRuntimeFeedbackChanged.emit()
        self.actionStateChanged.emit()
        self._start_next_database_job()

    @Slot()
    def startDatabaseRuntime(self) -> None:
        LOGGER.debug("startDatabaseRuntime: busy=%s", self._database_action_busy)
        runtime = self._container.database_service.active_runtime()
        runtime_label = (
            f"{runtime.engine.upper()} {runtime.version}"
            if runtime is not None
            else "database"
        )
        self._database_runtime_message = (
            f"Starting {runtime_label}. "
            "If this is the first run, initializing system tables can take up to about a minute."
        )
        self._database_runtime_error = False
        self.databaseRuntimeFeedbackChanged.emit()
        self.setHomeServiceRunning("database", True)

    @Slot()
    def stopDatabaseRuntime(self) -> None:
        LOGGER.debug("stopDatabaseRuntime: busy=%s", self._database_action_busy)
        self.setHomeServiceRunning("database", False)

    @Slot()
    def restartDatabaseRuntime(self) -> None:
        LOGGER.debug("restartDatabaseRuntime: busy=%s", self._database_action_busy)
        if self._database_action_busy:
            return
        self._database_action_busy = True
        thread = QThread(self)
        worker = DatabaseRestartWorker(self._container)
        worker.moveToThread(thread)
        worker.completed.connect(self._on_database_restart_completed)
        worker.completed.connect(thread.quit)
        thread.started.connect(worker.run)
        thread.finished.connect(worker.deleteLater)
        thread.finished.connect(thread.deleteLater)
        self._database_restart_thread = thread
        self._database_restart_worker = worker
        thread.start()
        self._defer_action_state_changed()

    @Slot()
    def refreshDatabaseRuntime(self) -> None:
        result = self._container.database_service.list_databases()
        if not result.success and not self._database_runtime_message:
            self._database_runtime_message = result.message
            self._database_runtime_error = True
        self._database_runtime_log = self._container.database_service.read_log_tail()
        self.dataChanged.emit()
        self.databaseRuntimeFeedbackChanged.emit()

    def _apply_database_runtime_feedback(self, result) -> None:
        self._database_runtime_message = result.message
        self._database_runtime_error = not result.success
        self._database_runtime_log = self._container.database_service.read_log_tail()
        self.dataChanged.emit()
        self.databaseRuntimeFeedbackChanged.emit()
        self.dataChanged.emit()
