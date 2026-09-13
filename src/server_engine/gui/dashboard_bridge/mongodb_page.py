import logging

from ._shared import *


LOGGER = logging.getLogger("server_engine.mongodb")


class MongodbPageMixin(DashboardBridgeSignals):
    def _log_mongodb_runtime_feedback(self, message: str, *, error: bool, include_log: bool = False) -> None:
        text = str(message or "").strip()
        if text:
            if error:
                LOGGER.error(text)
            else:
                LOGGER.info(text)
        if include_log:
            log_text = str(self._mongodb_runtime_log or "").strip()
            if log_text:
                if error:
                    LOGGER.error("MongoDB runtime log:\n%s", log_text)
                else:
                    LOGGER.info("MongoDB runtime log:\n%s", log_text)
    @Property(bool, notify=appSettingsFeedbackChanged)
    def mongodbRuntimeDownloaded(self) -> bool:
        return self.optionalDatabaseRuntimeDownloaded("mongodb")

    def _active_mongodb_runtime(self):
        return self._container.mongodb_service.active_runtime()

    def _mongodb_data_dir(self) -> Path:
        return self._container.mongodb_service.data_dir(create=False)

    def _mongodb_config_path(self) -> Path:
        return self._container.mongodb_service.config_path()

    def _mongodb_log_path(self) -> Path:
        return self._container.mongodb_service.log_path()

    @Property("QVariantList", notify=mongodbRuntimeFeedbackChanged)
    def mongodbItems(self) -> list[dict[str, str]]:
        return list(self._mongodb_items)

    @Slot(str, result="QVariantList")
    def mongodbBackupItems(self, database_name: str) -> list[dict[str, object]]:
        result = self._container.mongodb_service.list_backups(database_name)
        if not result.success:
            return []
        return list(result.payload.get("items", []))

    @Property(str, notify=mongodbRuntimeFeedbackChanged)
    def activeMongodbRuntimeBrand(self) -> str:
        return "MongoDB"

    @Property(str, notify=mongodbRuntimeFeedbackChanged)
    def activeMongodbRuntimeLabel(self) -> str:
        runtime = self._active_mongodb_runtime()
        return f"MongoDB {runtime.version}" if runtime is not None else "No MongoDB runtime"

    @Property(str, notify=mongodbRuntimeFeedbackChanged)
    def activeMongodbRuntimeHome(self) -> str:
        runtime = self._active_mongodb_runtime()
        return runtime.home if runtime is not None else ""

    @Property(str, notify=mongodbRuntimeFeedbackChanged)
    def activeMongodbDataDir(self) -> str:
        return str(self._mongodb_data_dir())

    @Property(str, notify=mongodbRuntimeFeedbackChanged)
    def activeMongodbConfigPath(self) -> str:
        return str(self._mongodb_config_path())

    @Property(str, notify=mongodbRuntimeFeedbackChanged)
    def activeMongodbConfigContent(self) -> str:
        path = self._mongodb_config_path()
        try:
            if path.exists():
                return path.read_text(encoding="utf-8")
        except Exception:
            pass
        return ""

    @Property(str, notify=mongodbRuntimeFeedbackChanged)
    def activeMongodbPort(self) -> str:
        return str(self._container.mongodb_service.port)

    @Property(str, notify=mongodbRuntimeFeedbackChanged)
    def activeMongodbServiceState(self) -> str:
        return getattr(self, "_mongodb_service_state_cache", "Stopped")

    @Slot(result="QVariantMap")
    def mongodbRuntimeSettings(self) -> dict[str, object]:
        return dict(getattr(self, "_mongodb_runtime_settings", {"bind_ip": "127.0.0.1", "max_connections": "100"}))

    @Slot("QVariantMap", result=bool)
    def saveMongodbRuntimeSettings(self, values: dict) -> bool:
        self._mongodb_runtime_settings = self.mongodbRuntimeSettings()
        self._mongodb_runtime_settings.update(dict(values or {}))
        self._mongodb_runtime_message = "MongoDB runtime settings saved. Restart the runtime to apply."
        self._mongodb_runtime_error = False
        self.mongodbRuntimeFeedbackChanged.emit()
        return True

    @Property(str, notify=mongodbRuntimeFeedbackChanged)
    def mongodbPassword(self) -> str:
        return ""

    @Property(str, notify=mongodbRuntimeFeedbackChanged)
    def mongodbRuntimeMessage(self) -> str:
        return self._mongodb_runtime_message

    @Property(bool, notify=mongodbRuntimeFeedbackChanged)
    def mongodbRuntimeError(self) -> bool:
        return self._mongodb_runtime_error

    @Property(str, notify=mongodbRuntimeFeedbackChanged)
    def mongodbRuntimeLog(self) -> str:
        path = self._mongodb_log_path()
        try:
            if path.exists():
                return "\n".join(path.read_text(encoding="utf-8", errors="ignore").splitlines()[-250:])
        except Exception:
            pass
        return self._mongodb_runtime_log

    @Property(bool, notify=mongodbRuntimeFeedbackChanged)
    def mongodbActionBusy(self) -> bool:
        return self._mongodb_action_busy

    @Property(bool, notify=mongodbRuntimeFeedbackChanged)
    def mongodbBackupBusy(self) -> bool:
        return self._mongodb_backup_busy

    @Property(str, notify=mongodbRuntimeFeedbackChanged)
    def mongodbBackupMessage(self) -> str:
        return self._mongodb_backup_message

    @Property(bool, notify=mongodbRuntimeFeedbackChanged)
    def mongodbBackupError(self) -> bool:
        return self._mongodb_backup_error

    @Property(int, notify=mongodbRuntimeFeedbackChanged)
    def mongodbBackupProgress(self) -> int:
        return self._mongodb_backup_progress

    @Property(str, notify=mongodbRuntimeFeedbackChanged)
    def mongodbBackupProgressLabel(self) -> str:
        return self._mongodb_backup_progress_label

    @Property(bool, notify=mongodbRuntimeFeedbackChanged)
    def mongodbImportBusy(self) -> bool:
        return self._mongodb_import_busy

    @Property(str, notify=mongodbRuntimeFeedbackChanged)
    def mongodbImportMessage(self) -> str:
        return self._mongodb_import_message

    @Property(bool, notify=mongodbRuntimeFeedbackChanged)
    def mongodbImportError(self) -> bool:
        return self._mongodb_import_error

    @Property(int, notify=mongodbRuntimeFeedbackChanged)
    def mongodbImportProgress(self) -> int:
        return self._mongodb_import_progress

    @Property(str, notify=mongodbRuntimeFeedbackChanged)
    def mongodbImportProgressLabel(self) -> str:
        return self._mongodb_import_progress_label

    @Property(str, notify=mongodbRuntimeFeedbackChanged)
    def mongodbImportSelectedPath(self) -> str:
        return self._mongodb_import_selected_path

    @Property(str, notify=mongodbRuntimeFeedbackChanged)
    def mongodbImportDetails(self) -> str:
        return self._mongodb_import_details

    @Slot()
    def clearMongodbRuntimeFeedback(self) -> None:
        self._mongodb_runtime_message = ""
        self._mongodb_runtime_error = False
        self._mongodb_backup_message = ""
        self._mongodb_backup_error = False
        self._mongodb_backup_progress = 0
        self._mongodb_backup_progress_label = ""
        self._mongodb_import_message = ""
        self._mongodb_import_error = False
        self._mongodb_import_progress = 0
        self._mongodb_import_progress_label = ""
        self.mongodbRuntimeFeedbackChanged.emit()

    @Slot()
    def refreshMongodbRuntime(self) -> None:
        self.mongodbRuntimeFeedbackChanged.emit()

    @Slot()
    def refreshMongodbItemsAsync(self) -> None:
        if self._mongodb_items_loading:
            return
        self._mongodb_items_loading = True
        thread = QThread(self)
        worker = MongodbItemsWorker(self._container)
        worker.moveToThread(thread)
        worker.completed.connect(self._on_mongodb_items_ready)
        worker.completed.connect(thread.quit)
        thread.started.connect(worker.run)
        thread.finished.connect(worker.deleteLater)
        thread.finished.connect(thread.deleteLater)
        self._mongodb_items_thread = thread
        self._mongodb_items_worker = worker
        thread.start()

    @Slot("QVariantList")
    def _on_mongodb_items_ready(self, items: list[dict[str, str]]) -> None:
        self._mongodb_items = list(items)
        self._mongodb_items_loading = False
        self._mongodb_items_thread = None
        self._mongodb_items_worker = None
        self.mongodbRuntimeFeedbackChanged.emit()

    @Slot(str, result=bool)
    def saveActiveMongodbConfigContent(self, content: str) -> bool:
        try:
            if not str(content).strip():
                raise ValueError("MongoDB config cannot be empty.")
            config_path = self._mongodb_config_path()
            current_text = config_path.read_text(encoding="utf-8") if config_path.exists() else ""
            original_backup = config_path.with_suffix(config_path.suffix + ".original")
            last_backup = config_path.with_suffix(config_path.suffix + ".bak")
            if config_path.exists() and not original_backup.exists():
                self._atomic_write_text(original_backup, current_text)
            if config_path.exists():
                self._atomic_write_text(last_backup, current_text)
            self._atomic_write_text(config_path, str(content))
            self._mongodb_runtime_message = f"Saved MongoDB config with backup.\nOriginal: {original_backup}\nLatest backup: {last_backup}"
            self._mongodb_runtime_error = False
            self._log_mongodb_runtime_feedback(self._mongodb_runtime_message, error=False)
            self.mongodbRuntimeFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._mongodb_runtime_message = str(exc)
            self._mongodb_runtime_error = True
            self._log_mongodb_runtime_feedback(self._mongodb_runtime_message, error=True)
            self.mongodbRuntimeFeedbackChanged.emit()
            return False

    @Slot(result=bool)
    def restoreActiveMongodbConfigOriginal(self) -> bool:
        try:
            config_path = self._mongodb_config_path()
            original_backup = config_path.with_suffix(config_path.suffix + ".original")
            if not original_backup.exists():
                raise ValueError("Original backup not found. Save the config once first.")
            current_text = config_path.read_text(encoding="utf-8") if config_path.exists() else ""
            self._atomic_write_text(config_path.with_suffix(config_path.suffix + ".bak"), current_text)
            self._atomic_write_text(config_path, original_backup.read_text(encoding="utf-8"))
            self._mongodb_runtime_message = f"Restored original MongoDB config from {original_backup}"
            self._mongodb_runtime_error = False
            self._log_mongodb_runtime_feedback(self._mongodb_runtime_message, error=False)
            self.mongodbRuntimeFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._mongodb_runtime_message = str(exc)
            self._mongodb_runtime_error = True
            self._log_mongodb_runtime_feedback(self._mongodb_runtime_message, error=True)
            self.mongodbRuntimeFeedbackChanged.emit()
            return False

    @Slot(str, result=bool)
    def updateMongodbRuntimePort(self, mongodb_port: str) -> bool:
        try:
            port = int(str(mongodb_port).strip())
            if port < 1 or port > 65535:
                raise ValueError
            self._container.mongodb_service.port = port
            self._container.mongodb_service.generate_config()
            self._mongodb_runtime_message = f"MongoDB port set to {port}. Restart MongoDB to apply it."
            self._mongodb_runtime_error = False
        except Exception:
            self._mongodb_runtime_message = "MongoDB port must be a number between 1 and 65535."
            self._mongodb_runtime_error = True
        self._log_mongodb_runtime_feedback(self._mongodb_runtime_message, error=self._mongodb_runtime_error)
        self.mongodbRuntimeFeedbackChanged.emit()
        return not self._mongodb_runtime_error

    @Slot(str, result=bool)
    def updateMongodbPassword(self, new_password: str) -> bool:
        self._mongodb_runtime_message = "MongoDB auth/password management is not wired yet."
        self._mongodb_runtime_error = True
        self._log_mongodb_runtime_feedback(self._mongodb_runtime_message, error=True)
        self.mongodbRuntimeFeedbackChanged.emit()
        return False

    @Slot(str, str, result=bool)
    def createMongodbDatabase(self, name: str, encoding: str) -> bool:
        result = self._container.mongodb_service.create_database(name)
        self._mongodb_runtime_message = result.message
        self._mongodb_runtime_error = not result.success
        self._mongodb_runtime_log = self._container.mongodb_service.read_log_tail()
        self._log_mongodb_runtime_feedback(self._mongodb_runtime_message, error=not result.success, include_log=True)
        self.dataChanged.emit()
        self.mongodbRuntimeFeedbackChanged.emit()
        return result.success

    @Slot(str, result=bool)
    def dropMongodbDatabase(self, name: str) -> bool:
        result = self._container.mongodb_service.drop_database(name)
        self._mongodb_runtime_message = result.message
        self._mongodb_runtime_error = not result.success
        self._mongodb_runtime_log = self._container.mongodb_service.read_log_tail()
        self._log_mongodb_runtime_feedback(self._mongodb_runtime_message, error=not result.success, include_log=True)
        self.dataChanged.emit()
        self.mongodbRuntimeFeedbackChanged.emit()
        return result.success

    @Slot(str, result=bool)
    def createMongodbBackup(self, database_name: str) -> bool:
        cleaned = database_name.strip()
        if not cleaned:
            return False
        self._enqueue_database_job("mongodb-backup", cleaned, f"Backing up {cleaned or 'database'}")
        return True

    @Slot(str, result=bool)
    def restoreMongodbBackup(self, archive_path: str) -> bool:
        cleaned = archive_path.strip()
        if not cleaned:
            return False
        self._enqueue_database_job("mongodb-restore", cleaned, f"Restoring {Path(cleaned).name if cleaned else 'backup'}")
        return True

    @Slot(str, result=bool)
    def deleteMongodbBackup(self, archive_path: str) -> bool:
        result = self._container.mongodb_service.delete_backup(archive_path)
        self._mongodb_backup_message = result.message
        self._mongodb_backup_error = not result.success
        self._log_mongodb_runtime_feedback(self._mongodb_backup_message, error=not result.success)
        self.mongodbRuntimeFeedbackChanged.emit()
        return result.success

    @Slot(result=str)
    def chooseMongodbImportFile(self) -> str:
        parent = QApplication.activeWindow()
        selected, _ = QFileDialog.getOpenFileName(
            parent,
            "Choose MongoDB Import File",
            "",
            "MongoDB Files (*.json *.bson *.zip *.tar.gz *.tgz *.gz)",
        )
        if selected:
            self._mongodb_import_selected_path = selected
            self._mongodb_import_details = "Selected file: " + selected
            self._mongodb_import_message = ""
            self._mongodb_import_error = False
            self._log_mongodb_runtime_feedback(self._mongodb_import_details, error=False)
            self.mongodbRuntimeFeedbackChanged.emit()
        return selected

    @Slot(str, str, result=bool)
    def importMongodbFile(self, database_name: str, import_path: str) -> bool:
        cleaned_name = database_name.strip()
        cleaned_path = import_path.strip()
        if not cleaned_name or not cleaned_path:
            self._mongodb_import_message = "Database name and import file are required."
            self._mongodb_import_error = True
            self.mongodbRuntimeFeedbackChanged.emit()
            return False
        self._mongodb_import_selected_path = cleaned_path
        self._enqueue_database_job("mongodb-import", cleaned_name + "\n" + cleaned_path, f"Importing {cleaned_name}")
        return True

    def _run_mongodb_backup_job(self, database_name: str) -> bool:
        self._mongodb_backup_busy = True
        self._mongodb_backup_message = ""
        self._mongodb_backup_error = False
        self._mongodb_backup_progress = 5
        self._mongodb_backup_progress_label = "Creating backup..."
        self.mongodbRuntimeFeedbackChanged.emit()
        try:
            result = self._container.mongodb_service.create_backup(database_name)
            self._mongodb_backup_message = result.message
            self._mongodb_backup_error = not result.success
            self._mongodb_backup_progress = 100 if result.success else 0
            self._mongodb_backup_progress_label = "Done" if result.success else ""
            self._log_mongodb_runtime_feedback(self._mongodb_backup_message, error=not result.success)
            self.mongodbRuntimeFeedbackChanged.emit()
            return result.success
        finally:
            self._mongodb_backup_busy = False
            self._mongodb_backup_progress = 0 if self._mongodb_backup_progress < 100 else self._mongodb_backup_progress
            self.mongodbRuntimeFeedbackChanged.emit()

    def _run_mongodb_restore_job(self, archive_path: str) -> bool:
        self._mongodb_backup_busy = True
        self._mongodb_backup_message = ""
        self._mongodb_backup_error = False
        self._mongodb_backup_progress = 5
        self._mongodb_backup_progress_label = "Restoring..."
        self.mongodbRuntimeFeedbackChanged.emit()
        QCoreApplication.processEvents()

        try:
            result = self._container.mongodb_service.restore_backup(archive_path)
            self._mongodb_backup_message = result.message
            self._mongodb_backup_error = not result.success
            self._mongodb_backup_progress = 100 if result.success else 0
            self._mongodb_backup_progress_label = "Done" if result.success else ""
            self._log_mongodb_runtime_feedback(self._mongodb_backup_message, error=not result.success)
            self.dataChanged.emit()
            self.mongodbRuntimeFeedbackChanged.emit()
            return result.success
        finally:
            self._mongodb_backup_busy = False
            self.mongodbRuntimeFeedbackChanged.emit()

    def _run_mongodb_import_job(self, database_name: str, import_path: str) -> bool:
        self._mongodb_import_busy = True
        self._mongodb_import_message = ""
        self._mongodb_import_error = False
        self._mongodb_import_progress = 5
        self._mongodb_import_progress_label = "Importing..."
        self._mongodb_import_details = "Importing " + database_name.strip()
        self.mongodbRuntimeFeedbackChanged.emit()
        try:
            result = self._container.mongodb_service.import_dump(database_name, import_path)
            self._mongodb_import_message = result.message
            self._mongodb_import_error = not result.success
            self._mongodb_import_progress = 100 if result.success else 0
            self._mongodb_import_progress_label = "Done" if result.success else ""
            self._mongodb_import_details = result.message
            self._log_mongodb_runtime_feedback(self._mongodb_import_message, error=not result.success, include_log=True)
            self.dataChanged.emit()
            self.mongodbRuntimeFeedbackChanged.emit()
            return result.success
        finally:
            self._mongodb_import_busy = False
            self._mongodb_import_progress = 0 if self._mongodb_import_progress < 100 else self._mongodb_import_progress
            self.mongodbRuntimeFeedbackChanged.emit()

    @Slot()
    def clearMongodbImportSelection(self) -> None:
        self._mongodb_import_selected_path = ""
        self._mongodb_import_details = ""
        self._mongodb_import_message = ""
        self._mongodb_import_error = False
        self._mongodb_import_progress = 0
        self._mongodb_import_progress_label = ""
        self.mongodbRuntimeFeedbackChanged.emit()

    @Slot(result=bool)
    def openMongodbCompass(self) -> bool:
        self._mongodb_runtime_message = "MongoDB Compass backend is not wired yet."
        self._mongodb_runtime_error = True
        self._log_mongodb_runtime_feedback(self._mongodb_runtime_message, error=True)
        self.mongodbRuntimeFeedbackChanged.emit()
        return False

    @Slot()
    def startMongodbRuntime(self) -> None:
        LOGGER.debug("startMongodbRuntime: busy=%s", self._mongodb_action_busy)
        self._start_mongodb_action_job("start")

    @Slot()
    def stopMongodbRuntime(self) -> None:
        LOGGER.debug("stopMongodbRuntime: busy=%s", self._mongodb_action_busy)
        self._start_mongodb_action_job("stop")

    @Slot()
    def restartMongodbRuntime(self) -> None:
        LOGGER.debug("restartMongodbRuntime: busy=%s", self._mongodb_action_busy)
        self._start_mongodb_action_job("restart")

    def _start_mongodb_action_job(self, action: str) -> None:
        LOGGER.debug("_start_mongodb_action_job: action=%s busy=%s", action, self._mongodb_action_busy)
        if self._mongodb_action_busy:
            return
        self._mongodb_action_busy = True
        self.mongodbRuntimeFeedbackChanged.emit()
        thread = QThread(self)
        worker = MongodbActionWorker(self._container, action)
        worker.moveToThread(thread)
        worker.completed.connect(self._on_mongodb_action_completed)
        worker.completed.connect(thread.quit)
        thread.started.connect(worker.run)
        thread.finished.connect(worker.deleteLater)
        thread.finished.connect(thread.deleteLater)
        self._mongodb_action_thread = thread
        self._mongodb_action_worker = worker
        thread.start()
        self._defer_action_state_changed()

    @Slot(str, bool, str, str)
    def _on_mongodb_action_completed(self, action: str, success: bool, message: str, log_tail: str) -> None:
        LOGGER.debug(
            "_on_mongodb_action_completed: action=%s success=%s message=%s",
            action,
            success,
            message,
        )
        self._mongodb_runtime_message = message
        self._mongodb_runtime_error = not success
        self._mongodb_runtime_log = log_tail
        if action in {"start", "restart"} and success:
            self._mongodb_service_state_cache = "Running"
        elif action == "stop" and success:
            self._mongodb_service_state_cache = "Stopped"
        self._mongodb_action_busy = False
        self._mongodb_action_thread = None
        self._mongodb_action_worker = None
        self._log_mongodb_runtime_feedback(self._mongodb_runtime_message, error=not success, include_log=True)
        self.dataChanged.emit()
        self.mongodbRuntimeFeedbackChanged.emit()
        self._defer_action_state_changed()
        if action in {"start", "restart"} and success:
            self.refreshMongodbItemsAsync()
        elif action == "stop" and success:
            self._mongodb_items = []
            self.mongodbRuntimeFeedbackChanged.emit()
