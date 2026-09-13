import logging

from ._shared import *


LOGGER = logging.getLogger("server_engine.postgresql")


class PostgresqlPageMixin(DashboardBridgeSignals):
    def _log_postgresql_runtime_feedback(self, message: str, *, error: bool, include_log: bool = False) -> None:
        text = str(message or "").strip()
        if text:
            if error:
                LOGGER.error(text)
            else:
                LOGGER.info(text)
        if include_log:
            log_text = str(self._postgresql_runtime_log or "").strip()
            if log_text:
                if error:
                    LOGGER.error("PostgreSQL runtime log:\n%s", log_text)
                else:
                    LOGGER.info("PostgreSQL runtime log:\n%s", log_text)

    @Property(bool, notify=appSettingsFeedbackChanged)
    def postgresqlRuntimeDownloaded(self) -> bool:
        return self.optionalDatabaseRuntimeDownloaded("postgresql")

    def _active_postgresql_runtime(self):
        return self._container.postgresql_service.active_runtime()

    def _postgresql_data_dir(self) -> Path:
        return self._container.postgresql_service.data_dir(create=False)

    def _postgresql_config_path(self) -> Path:
        return self._container.postgresql_service.config_path()

    def _postgresql_log_path(self) -> Path:
        return self._container.postgresql_service.log_path()

    def _set_postgresql_pending_message(self, action: str) -> bool:
        self._postgresql_runtime_message = f"PostgreSQL {action} backend is not wired yet."
        self._postgresql_runtime_error = True
        self._log_postgresql_runtime_feedback(self._postgresql_runtime_message, error=True)
        self.postgresqlRuntimeFeedbackChanged.emit()
        return False

    @Property("QVariantList", notify=postgresqlRuntimeFeedbackChanged)
    def postgresqlItems(self) -> list[dict[str, str]]:
        result = self._container.postgresql_service.list_databases()
        if not result.success:
            return []
        runtime = result.payload.get("runtime") or {}
        port = str(result.payload.get("port", "5432"))
        items: list[dict[str, str]] = []
        for entry in result.payload.get("databases", []):
            name = str(entry.get("name", "")).strip()
            if not name:
                continue
            items.append(
                {
                    "name": name,
                    "engine": "POSTGRESQL",
                    "runtime": str(runtime.get("version", "")),
                    "host": "127.0.0.1",
                    "port": port,
                    "status": "Ready",
                }
            )
        return items

    @Slot(str, result="QVariantList")
    def postgresqlBackupItems(self, database_name: str) -> list[dict[str, object]]:
        result = self._container.postgresql_service.list_backups(database_name)
        if not result.success:
            return []
        return list(result.payload.get("items", []))

    @Property(str, notify=postgresqlRuntimeFeedbackChanged)
    def activePostgresqlRuntimeBrand(self) -> str:
        return "PostgreSQL"

    @Property(str, notify=postgresqlRuntimeFeedbackChanged)
    def activePostgresqlRuntimeLabel(self) -> str:
        runtime = self._active_postgresql_runtime()
        return f"PostgreSQL {runtime.version}" if runtime is not None else "No PostgreSQL runtime"

    @Property(str, notify=postgresqlRuntimeFeedbackChanged)
    def activePostgresqlRuntimeHome(self) -> str:
        runtime = self._active_postgresql_runtime()
        return runtime.home if runtime is not None else ""

    @Property(str, notify=postgresqlRuntimeFeedbackChanged)
    def activePostgresqlDataDir(self) -> str:
        return str(self._postgresql_data_dir())

    @Property(str, notify=postgresqlRuntimeFeedbackChanged)
    def activePostgresqlConfigPath(self) -> str:
        return str(self._postgresql_config_path())

    @Property(str, notify=postgresqlRuntimeFeedbackChanged)
    def activePostgresqlConfigContent(self) -> str:
        path = self._postgresql_config_path()
        try:
            if path.exists():
                return path.read_text(encoding="utf-8")
        except Exception:
            pass
        return ""

    @Property(str, notify=postgresqlRuntimeFeedbackChanged)
    def activePostgresqlPort(self) -> str:
        return str(self._container.postgresql_service.port)

    @Property(str, notify=postgresqlRuntimeFeedbackChanged)
    def activePostgresqlServiceState(self) -> str:
        return getattr(self, "_postgresql_service_state_cache", "Stopped")

    @Slot(result="QVariantMap")
    def postgresqlRuntimeSettings(self) -> dict[str, object]:
        return dict(getattr(self, "_postgresql_runtime_settings", {"listen_addresses": "localhost", "max_connections": "100"}))

    @Slot("QVariantMap", result=bool)
    def savePostgresqlRuntimeSettings(self, values: dict) -> bool:
        self._postgresql_runtime_settings = self.postgresqlRuntimeSettings()
        self._postgresql_runtime_settings.update(dict(values or {}))
        self._postgresql_runtime_message = "PostgreSQL runtime settings saved. Restart the runtime to apply."
        self._postgresql_runtime_error = False
        self.postgresqlRuntimeFeedbackChanged.emit()
        return True

    @Property(str, notify=postgresqlRuntimeFeedbackChanged)
    def postgresqlPassword(self) -> str:
        return ""

    @Property(str, notify=postgresqlRuntimeFeedbackChanged)
    def postgresqlRuntimeMessage(self) -> str:
        return self._postgresql_runtime_message

    @Property(bool, notify=postgresqlRuntimeFeedbackChanged)
    def postgresqlRuntimeError(self) -> bool:
        return self._postgresql_runtime_error

    @Property(str, notify=postgresqlRuntimeFeedbackChanged)
    def postgresqlRuntimeLog(self) -> str:
        path = self._postgresql_log_path()
        try:
            if path.exists():
                return "\n".join(path.read_text(encoding="utf-8", errors="ignore").splitlines()[-250:])
        except Exception:
            pass
        return self._postgresql_runtime_log

    @Property(bool, notify=postgresqlRuntimeFeedbackChanged)
    def postgresqlActionBusy(self) -> bool:
        return self._postgresql_action_busy

    @Property(bool, notify=postgresqlRuntimeFeedbackChanged)
    def adminerBusy(self) -> bool:
        return self._adminer_busy

    @Property(bool, notify=postgresqlRuntimeFeedbackChanged)
    def postgresqlBackupBusy(self) -> bool:
        return self._postgresql_backup_busy

    @Property(str, notify=postgresqlRuntimeFeedbackChanged)
    def postgresqlBackupMessage(self) -> str:
        return self._postgresql_backup_message

    @Property(bool, notify=postgresqlRuntimeFeedbackChanged)
    def postgresqlBackupError(self) -> bool:
        return self._postgresql_backup_error

    @Property(int, notify=postgresqlRuntimeFeedbackChanged)
    def postgresqlBackupProgress(self) -> int:
        return self._postgresql_backup_progress

    @Property(str, notify=postgresqlRuntimeFeedbackChanged)
    def postgresqlBackupProgressLabel(self) -> str:
        return self._postgresql_backup_progress_label

    @Property(bool, notify=postgresqlRuntimeFeedbackChanged)
    def postgresqlImportBusy(self) -> bool:
        return self._postgresql_import_busy

    @Property(str, notify=postgresqlRuntimeFeedbackChanged)
    def postgresqlImportMessage(self) -> str:
        return self._postgresql_import_message

    @Property(bool, notify=postgresqlRuntimeFeedbackChanged)
    def postgresqlImportError(self) -> bool:
        return self._postgresql_import_error

    @Property(int, notify=postgresqlRuntimeFeedbackChanged)
    def postgresqlImportProgress(self) -> int:
        return self._postgresql_import_progress

    @Property(str, notify=postgresqlRuntimeFeedbackChanged)
    def postgresqlImportProgressLabel(self) -> str:
        return self._postgresql_import_progress_label

    @Property(str, notify=postgresqlRuntimeFeedbackChanged)
    def postgresqlImportSelectedPath(self) -> str:
        return self._postgresql_import_selected_path

    @Property(str, notify=postgresqlRuntimeFeedbackChanged)
    def postgresqlImportDetails(self) -> str:
        return self._postgresql_import_details

    @Slot()
    def clearPostgresqlRuntimeFeedback(self) -> None:
        self._postgresql_runtime_message = ""
        self._postgresql_runtime_error = False
        self._postgresql_backup_message = ""
        self._postgresql_backup_error = False
        self._postgresql_backup_progress = 0
        self._postgresql_backup_progress_label = ""
        self._postgresql_import_message = ""
        self._postgresql_import_error = False
        self._postgresql_import_progress = 0
        self._postgresql_import_progress_label = ""
        self.postgresqlRuntimeFeedbackChanged.emit()

    @Slot()
    def refreshPostgresqlRuntime(self) -> None:
        self.postgresqlRuntimeFeedbackChanged.emit()

    @Slot(str, result=bool)
    def saveActivePostgresqlConfigContent(self, content: str) -> bool:
        try:
            if not str(content).strip():
                raise ValueError("PostgreSQL config cannot be empty.")
            config_path = self._postgresql_config_path()
            current_text = config_path.read_text(encoding="utf-8") if config_path.exists() else ""
            original_backup = config_path.with_suffix(config_path.suffix + ".original")
            last_backup = config_path.with_suffix(config_path.suffix + ".bak")
            if config_path.exists() and not original_backup.exists():
                self._atomic_write_text(original_backup, current_text)
            if config_path.exists():
                self._atomic_write_text(last_backup, current_text)
            self._atomic_write_text(config_path, str(content))
            self._postgresql_runtime_message = f"Saved PostgreSQL config with backup.\nOriginal: {original_backup}\nLatest backup: {last_backup}"
            self._postgresql_runtime_error = False
            self._log_postgresql_runtime_feedback(self._postgresql_runtime_message, error=False)
            self.postgresqlRuntimeFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._postgresql_runtime_message = str(exc)
            self._postgresql_runtime_error = True
            self._log_postgresql_runtime_feedback(self._postgresql_runtime_message, error=True)
            self.postgresqlRuntimeFeedbackChanged.emit()
            return False

    @Slot(result=bool)
    def restoreActivePostgresqlConfigOriginal(self) -> bool:
        try:
            config_path = self._postgresql_config_path()
            original_backup = config_path.with_suffix(config_path.suffix + ".original")
            if not original_backup.exists():
                raise ValueError("Original backup not found. Save the config once first.")
            current_text = config_path.read_text(encoding="utf-8") if config_path.exists() else ""
            self._atomic_write_text(config_path.with_suffix(config_path.suffix + ".bak"), current_text)
            self._atomic_write_text(config_path, original_backup.read_text(encoding="utf-8"))
            self._postgresql_runtime_message = f"Restored original PostgreSQL config from {original_backup}"
            self._postgresql_runtime_error = False
            self._log_postgresql_runtime_feedback(self._postgresql_runtime_message, error=False)
            self.postgresqlRuntimeFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._postgresql_runtime_message = str(exc)
            self._postgresql_runtime_error = True
            self._log_postgresql_runtime_feedback(self._postgresql_runtime_message, error=True)
            self.postgresqlRuntimeFeedbackChanged.emit()
            return False

    @Slot(str, result=bool)
    def updatePostgresqlRuntimePort(self, postgresql_port: str) -> bool:
        self._postgresql_runtime_message = "PostgreSQL port is fixed at 5432 for this build."
        self._postgresql_runtime_error = False
        self._log_postgresql_runtime_feedback(self._postgresql_runtime_message, error=False)
        self.postgresqlRuntimeFeedbackChanged.emit()
        return True

    @Slot(str, result=bool)
    def updatePostgresqlPassword(self, new_password: str) -> bool:
        result = self._container.postgresql_service.update_password(new_password)
        self._postgresql_runtime_message = result.message
        self._postgresql_runtime_error = not result.success
        self._postgresql_runtime_log = self._container.postgresql_service.read_log_tail()
        self._log_postgresql_runtime_feedback(self._postgresql_runtime_message, error=not result.success, include_log=True)
        self.dataChanged.emit()
        self.postgresqlRuntimeFeedbackChanged.emit()
        return result.success

    @Slot(str, str, result=bool)
    def createPostgresqlDatabase(self, name: str, encoding: str) -> bool:
        result = self._container.postgresql_service.create_database(name, encoding)
        self._postgresql_runtime_message = result.message
        self._postgresql_runtime_error = not result.success
        self._postgresql_runtime_log = self._container.postgresql_service.read_log_tail()
        self._log_postgresql_runtime_feedback(self._postgresql_runtime_message, error=not result.success, include_log=True)
        self.dataChanged.emit()
        self.postgresqlRuntimeFeedbackChanged.emit()
        return result.success

    @Slot(str, result=bool)
    def dropPostgresqlDatabase(self, name: str) -> bool:
        result = self._container.postgresql_service.drop_database(name)
        self._postgresql_runtime_message = result.message
        self._postgresql_runtime_error = not result.success
        self._postgresql_runtime_log = self._container.postgresql_service.read_log_tail()
        self._log_postgresql_runtime_feedback(self._postgresql_runtime_message, error=not result.success, include_log=True)
        self.dataChanged.emit()
        self.postgresqlRuntimeFeedbackChanged.emit()
        return result.success

    @Slot(str, result=bool)
    def createPostgresqlBackup(self, database_name: str) -> bool:
        cleaned = database_name.strip()
        if not cleaned:
            return False
        self._enqueue_database_job("postgresql-backup", cleaned, f"Backing up {cleaned or 'database'}")
        return True

    @Slot(str, result=bool)
    def restorePostgresqlBackup(self, archive_path: str) -> bool:
        cleaned = archive_path.strip()
        if not cleaned:
            return False
        self._enqueue_database_job("postgresql-restore", cleaned, f"Restoring {Path(cleaned).name if cleaned else 'backup'}")
        return True

    @Slot(str, result=bool)
    def deletePostgresqlBackup(self, archive_path: str) -> bool:
        result = self._container.postgresql_service.delete_backup(archive_path)
        self._postgresql_backup_message = result.message
        self._postgresql_backup_error = not result.success
        self._log_postgresql_runtime_feedback(self._postgresql_backup_message, error=not result.success)
        self.postgresqlRuntimeFeedbackChanged.emit()
        return result.success

    @Slot(result=str)
    def choosePostgresqlImportFile(self) -> str:
        parent = QApplication.activeWindow()
        selected, _ = QFileDialog.getOpenFileName(
            parent,
            "Choose PostgreSQL Import File",
            "",
            "Database Files (*.sql *.zip *.tar.gz *.tgz *.gz)",
        )
        if selected:
            self._postgresql_import_selected_path = selected
            self._postgresql_import_details = "Selected file: " + selected
            self._postgresql_import_message = ""
            self._postgresql_import_error = False
            self._log_postgresql_runtime_feedback(self._postgresql_import_details, error=False)
            self.postgresqlRuntimeFeedbackChanged.emit()
        return selected

    @Slot(str, str, result=bool)
    def importPostgresqlFile(self, database_name: str, import_path: str) -> bool:
        cleaned_name = database_name.strip()
        cleaned_path = import_path.strip()
        if not cleaned_name or not cleaned_path:
            self._postgresql_import_message = "Database name and import file are required."
            self._postgresql_import_error = True
            self.postgresqlRuntimeFeedbackChanged.emit()
            return False
        self._postgresql_import_selected_path = cleaned_path
        self._enqueue_database_job("postgresql-import", cleaned_name + "\n" + cleaned_path, f"Importing {cleaned_name}")
        return True

    def _run_postgresql_backup_job(self, database_name: str) -> bool:
        self._postgresql_backup_busy = True
        self._postgresql_backup_message = ""
        self._postgresql_backup_error = False
        self._postgresql_backup_progress = 5
        self._postgresql_backup_progress_label = "Creating backup..."
        self.postgresqlRuntimeFeedbackChanged.emit()
        try:
            result = self._container.postgresql_service.create_backup(database_name)
            self._postgresql_backup_message = result.message
            self._postgresql_backup_error = not result.success
            self._postgresql_backup_progress = 100 if result.success else 0
            self._postgresql_backup_progress_label = "Done" if result.success else ""
            self._log_postgresql_runtime_feedback(self._postgresql_backup_message, error=not result.success)
            self.postgresqlRuntimeFeedbackChanged.emit()
            return result.success
        finally:
            self._postgresql_backup_busy = False
            self._postgresql_backup_progress = 0 if self._postgresql_backup_progress < 100 else self._postgresql_backup_progress
            self.postgresqlRuntimeFeedbackChanged.emit()

    def _run_postgresql_restore_job(self, archive_path: str) -> bool:
        self._postgresql_backup_busy = True
        self._postgresql_backup_message = ""
        self._postgresql_backup_error = False
        self._postgresql_backup_progress = 5
        self._postgresql_backup_progress_label = "Restoring..."
        self.postgresqlRuntimeFeedbackChanged.emit()
        QCoreApplication.processEvents()

        try:
            result = self._container.postgresql_service.restore_backup(archive_path)
            self._postgresql_backup_message = result.message
            self._postgresql_backup_error = not result.success
            self._postgresql_backup_progress = 100 if result.success else 0
            self._postgresql_backup_progress_label = "Done" if result.success else ""
            self._log_postgresql_runtime_feedback(self._postgresql_backup_message, error=not result.success)
            self.dataChanged.emit()
            self.postgresqlRuntimeFeedbackChanged.emit()
            return result.success
        finally:
            self._postgresql_backup_busy = False
            self.postgresqlRuntimeFeedbackChanged.emit()

    def _run_postgresql_import_job(self, database_name: str, import_path: str) -> bool:
        self._postgresql_import_busy = True
        self._postgresql_import_message = ""
        self._postgresql_import_error = False
        self._postgresql_import_progress = 5
        self._postgresql_import_progress_label = "Importing..."
        self._postgresql_import_details = "Importing " + database_name.strip()
        self.postgresqlRuntimeFeedbackChanged.emit()
        try:
            result = self._container.postgresql_service.import_dump(database_name, import_path)
            self._postgresql_import_message = result.message
            self._postgresql_import_error = not result.success
            self._postgresql_import_progress = 100 if result.success else 0
            self._postgresql_import_progress_label = "Done" if result.success else ""
            self._postgresql_import_details = result.message
            self._log_postgresql_runtime_feedback(self._postgresql_import_message, error=not result.success, include_log=True)
            self.dataChanged.emit()
            self.postgresqlRuntimeFeedbackChanged.emit()
            return result.success
        finally:
            self._postgresql_import_busy = False
            self._postgresql_import_progress = 0 if self._postgresql_import_progress < 100 else self._postgresql_import_progress
            self.postgresqlRuntimeFeedbackChanged.emit()

    @Slot()
    def clearPostgresqlImportSelection(self) -> None:
        self._postgresql_import_selected_path = ""
        self._postgresql_import_details = ""
        self._postgresql_import_message = ""
        self._postgresql_import_error = False
        self._postgresql_import_progress = 0
        self._postgresql_import_progress_label = ""
        self.postgresqlRuntimeFeedbackChanged.emit()

    @Slot(result=bool)
    def openAdminer(self) -> bool:
        self._postgresql_runtime_message = "Adminer backend is not wired yet."
        self._postgresql_runtime_error = True
        self._log_postgresql_runtime_feedback(self._postgresql_runtime_message, error=True)
        self.postgresqlRuntimeFeedbackChanged.emit()
        return False

    @Slot()
    def startPostgresqlRuntime(self) -> None:
        LOGGER.debug("startPostgresqlRuntime: busy=%s", self._postgresql_action_busy)
        if self._postgresql_action_busy:
            return
        self._postgresql_runtime_message = "Starting PostgreSQL runtime..."
        self._postgresql_runtime_error = False
        self._log_postgresql_runtime_feedback(self._postgresql_runtime_message, error=False)
        self.postgresqlRuntimeFeedbackChanged.emit()
        self.setHomeServiceRunning("postgresql", True)

    @Slot()
    def stopPostgresqlRuntime(self) -> None:
        LOGGER.debug("stopPostgresqlRuntime: busy=%s", self._postgresql_action_busy)
        if self._postgresql_action_busy:
            return
        self._postgresql_runtime_message = "Stopping PostgreSQL runtime..."
        self._postgresql_runtime_error = False
        self._log_postgresql_runtime_feedback(self._postgresql_runtime_message, error=False)
        self.postgresqlRuntimeFeedbackChanged.emit()
        self.setHomeServiceRunning("postgresql", False)

    @Slot()
    def restartPostgresqlRuntime(self) -> None:
        LOGGER.debug("restartPostgresqlRuntime: busy=%s", self._postgresql_action_busy)
        if self._postgresql_action_busy:
            return
        self._postgresql_runtime_message = "Restarting PostgreSQL runtime..."
        self._postgresql_runtime_error = False
        self._log_postgresql_runtime_feedback(self._postgresql_runtime_message, error=False)
        self.postgresqlRuntimeFeedbackChanged.emit()
        self._start_global_stack_action("restart", ["postgresql"])
