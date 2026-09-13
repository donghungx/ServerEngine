from ._shared import *
import platform


class SystemHelpersMixin:
    @Slot(str, result="QVariantList")
    def websiteOpenWithEditors(self, path: str) -> list[dict[str, str]]:
        editors = [
            ("visual-studio-code", "Visual Studio Code", "Visual Studio Code"),
            ("cursor", "Cursor", "Cursor"),
            ("sublime-text", "Sublime Text", "Sublime Text"),
            ("zed", "Zed", "Zed"),
            ("textedit", "TextEdit", "TextEdit"),
        ]
        result = []
        for editor_id, label, application in editors:
            if sys.platform == "darwin" and not Path(f"/Applications/{application}.app").exists():
                continue
            result.append({"id": editor_id, "label": label, "iconSource": ""})
        return result

    @Slot(str, str, result=bool)
    def openPathWithEditor(self, path: str, editor_id: str) -> bool:
        cleaned_path = str(path or "").strip()
        selected = str(editor_id or "").strip().lower()
        applications = {
            "visual-studio-code": "Visual Studio Code",
            "cursor": "Cursor",
            "sublime-text": "Sublime Text",
            "zed": "Zed",
            "textedit": "TextEdit",
        }
        application = applications.get(selected)
        if not cleaned_path or not application:
            return False
        try:
            if sys.platform == "darwin":
                subprocess.Popen(["open", "-a", application, cleaned_path])
            else:
                subprocess.Popen([selected, cleaned_path])
            return True
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False

    @Slot(str, str, str, object, result=bool)
    def openPlainTextViewer(self, title: str, content: str, extension: str = "", background=None) -> bool:
        try:
            suffix = str(extension or ".txt")
            if not suffix.startswith("."):
                suffix = "." + suffix
            handle = tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=suffix, delete=False)
            with handle:
                handle.write(str(content or ""))
            opener = "open" if sys.platform == "darwin" else "xdg-open"
            subprocess.Popen([opener, handle.name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return True
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False

    @Property(bool, notify=appSettingsFeedbackChanged)
    def macOS26OrLater(self) -> bool:
        if platform.system() != "Darwin":
            return False
        try:
            major = int(str(platform.mac_ver()[0]).split(".", 1)[0])
            return major >= 26
        except (TypeError, ValueError):
            return False

    def _request_headers(self, headers: dict[str, str] | None = None) -> dict[str, str]:
        merged = dict(headers or {})
        merged.update(self._container.license_service.device_headers())
        return merged

    def _license_status_map(self, status=None) -> dict[str, object]:
        status = status or self._container.license_service.status()
        return {
            "valid": bool(status.valid),
            "enforced": bool(status.enforced),
            "status": str(status.status or ""),
            "message": str(status.message or ""),
            "licensedTo": str(status.licensed_to or ""),
            "licenseKey": str(status.license_key or ""),
            "expiresAt": str(status.expires_at or ""),
            "daysRemaining": int(status.days_remaining or 0),
        }

    @Slot(result="QVariantMap")
    def licenseStatus(self) -> dict[str, object]:
        return self._license_status_map()

    @Slot(str, result="QVariantMap")
    def activateLicense(self, license_key: str) -> dict[str, object]:
        status = self._container.license_service.activate(license_key)
        self.appSettingsFeedbackChanged.emit()
        return self._license_status_map(status)

    @Slot(result="QVariantMap")
    def startLicenseTrial(self) -> dict[str, object]:
        status = self._container.license_service.start_trial()
        self.appSettingsFeedbackChanged.emit()
        return self._license_status_map(status)

    @Slot(result="QVariantMap")
    def removeActiveLicense(self) -> dict[str, object]:
        status = self._container.license_service.remove_license()
        self.appSettingsFeedbackChanged.emit()
        return self._license_status_map(status)

    @Slot()
    def _shutdown_metrics_thread(self) -> None:
        if self._shutting_down:
            return
        self._shutting_down = True
        if self._metrics_timer.isActive():
            self._metrics_timer.stop()
        if self._database_backup_thread is not None and self._database_backup_thread.isRunning():
            if self._database_backup_worker is not None:
                try:
                    self._database_backup_worker.cancel()
                except Exception:
                    pass
            self._database_backup_thread.quit()
            self._database_backup_thread.wait(3000)
        if self._database_import_thread is not None and self._database_import_thread.isRunning():
            if self._database_import_worker is not None:
                try:
                    self._database_import_worker.cancel()
                except Exception:
                    pass
            self._database_import_thread.quit()
            self._database_import_thread.wait(3000)
        if self._database_sizes_thread is not None and self._database_sizes_thread.isRunning():
            self._database_sizes_thread.quit()
            self._database_sizes_thread.wait(3000)
        for service_id, thread in list(self._home_service_threads.items()):
            if thread.isRunning():
                thread.quit()
                thread.wait(3000)
            self._cleanup_home_service_job(service_id)
        if self._global_action_thread is not None and self._global_action_thread.isRunning():
            self._global_action_thread.quit()
            self._global_action_thread.wait(3000)
        self._global_action_thread = None
        self._global_action_worker = None
        if self._mailpit_action_thread is not None and self._mailpit_action_thread.isRunning():
            self._mailpit_action_thread.quit()
            self._mailpit_action_thread.wait(3000)
        self._mailpit_action_thread = None
        self._mailpit_action_worker = None
        if self._redis_restart_thread is not None and self._redis_restart_thread.isRunning():
            self._redis_restart_thread.quit()
            self._redis_restart_thread.wait(3000)
        self._redis_restart_thread = None
        self._redis_restart_worker = None
        if self._memcached_restart_thread is not None and self._memcached_restart_thread.isRunning():
            self._memcached_restart_thread.quit()
            self._memcached_restart_thread.wait(3000)
        self._memcached_restart_thread = None
        self._memcached_restart_worker = None
        if self._mongodb_items_thread is not None and self._mongodb_items_thread.isRunning():
            self._mongodb_items_thread.quit()
            self._mongodb_items_thread.wait(3000)
        self._mongodb_items_thread = None
        self._mongodb_items_worker = None
        if self._mongodb_action_thread is not None and self._mongodb_action_thread.isRunning():
            self._mongodb_action_thread.quit()
            self._mongodb_action_thread.wait(3000)
        self._mongodb_action_thread = None
        self._mongodb_action_worker = None
        if self._phpmyadmin_thread is not None and self._phpmyadmin_thread.isRunning():
            self._phpmyadmin_thread.quit()
            self._phpmyadmin_thread.wait(3000)
        self._phpmyadmin_thread = None
        self._phpmyadmin_worker = None
        if self._database_restart_thread is not None and self._database_restart_thread.isRunning():
            self._database_restart_thread.quit()
            self._database_restart_thread.wait(3000)
        self._database_restart_thread = None
        self._database_restart_worker = None
        if self._web_reload_thread is not None and self._web_reload_thread.isRunning():
            self._web_reload_thread.quit()
            self._web_reload_thread.wait(3000)
        self._web_reload_thread = None
        self._web_reload_worker = None
        if self._web_restart_thread is not None and self._web_restart_thread.isRunning():
            self._web_restart_thread.quit()
            self._web_restart_thread.wait(3000)
        self._web_restart_thread = None
        self._web_restart_worker = None
        if self._php_runtime_service_action_thread is not None:
            try:
                if self._php_runtime_service_action_thread.isRunning():
                    self._php_runtime_service_action_thread.quit()
                    self._php_runtime_service_action_thread.wait(3000)
            except RuntimeError:
                # Under app shutdown the wrapped C++ QThread may already be deleted.
                pass
        self._php_runtime_service_action_thread = None
        self._php_runtime_service_action_worker = None
        if self._phpinfo_thread is not None and self._phpinfo_thread.isRunning():
            self._phpinfo_thread.quit()
            self._phpinfo_thread.wait(3000)
        self._phpinfo_thread = None
        self._phpinfo_worker = None
        if self._site_creation_thread is not None and self._site_creation_thread.isRunning():
            self._site_creation_thread.quit()
            self._site_creation_thread.wait(3000)
        self._site_creation_thread = None
        self._site_creation_worker = None
        if self._required_runtime_bootstrap_thread is not None and self._required_runtime_bootstrap_thread.isRunning():
            self._required_runtime_bootstrap_thread.quit()
            self._required_runtime_bootstrap_thread.wait(3000)
        self._required_runtime_bootstrap_thread = None
        self._required_runtime_bootstrap_worker = None
        if self._node_install_process is not None:
            if self._node_install_process.state() != QProcess.ProcessState.NotRunning:
                self._node_install_process.kill()
                self._node_install_process.waitForFinished(2000)
            self._cleanup_node_install_process()
        if self._metrics_thread.isRunning():
            self._metrics_thread.quit()
            self._metrics_thread.wait(3000)

    def shutdown(self) -> None:
        self._shutdown_metrics_thread()

    def _semver_key(self, value: str) -> tuple[int, int, int]:
        cleaned = value.strip().lstrip("v")
        parts = cleaned.split(".")
        numbers: list[int] = []
        for index in range(3):
            token = parts[index] if index < len(parts) else "0"
            match = re.match(r"^(\d+)", token)
            numbers.append(int(match.group(1)) if match else 0)
        return numbers[0], numbers[1], numbers[2]

    def _format_bytes(self, size: int) -> str:
        value = float(size or 0)
        for unit in ["B", "KB", "MB", "GB"]:
            if value < 1024 or unit == "GB":
                return f"{value:.1f} {unit}" if unit != "B" else f"{int(value)} B"
            value /= 1024
        return f"{int(size)} B"

    @Slot(str, result=bool)
    def pathExists(self, path: str) -> bool:
        cleaned = str(path or "").strip()
        if not cleaned:
            return False
        return Path(cleaned).expanduser().exists()

    @Slot(str, result=bool)
    def pathIsEmpty(self, path: str) -> bool:
        cleaned = str(path or "").strip()
        if not cleaned:
            return True
        candidate = Path(cleaned).expanduser()
        return candidate.is_dir() and not any(candidate.iterdir())

    @Property(bool, notify=appSettingsFeedbackChanged)
    def systemTrayVisible(self) -> bool:
        return bool(getattr(self, "_system_tray_visible", True))

    @Slot(str)
    def revealInFinder(self, path: str) -> None:
        cleaned = path.strip()
        if not cleaned:
            return
        try:
            subprocess.Popen(["open", "-R", cleaned])
        except Exception:
            pass

    @Slot(str)
    def openPathInTerminal(self, path: str) -> None:
        cleaned = str(path or "").strip()
        if not cleaned:
            return
        try:
            subprocess.Popen(["open", "-a", "Terminal", cleaned])
        except Exception:
            pass

    @Slot(str, bool)
    def showSystemStatusNotification(self, message: str, is_error: bool) -> None:
        cleaned = str(message or "").strip()
        if not cleaned:
            return
        if self._system_notifier is not None:
            try:
                self._system_notifier(cleaned, bool(is_error))
                return
            except Exception:
                pass
        title = "Server Engine Error" if bool(is_error) else "Server Engine"
        try:
            if os.name == "posix":
                escaped_message = cleaned.replace("\\", "\\\\").replace('"', '\\"')
                escaped_title = title.replace("\\", "\\\\").replace('"', '\\"')
                subprocess.Popen(
                    [
                        "osascript",
                        "-e",
                        f'display notification "{escaped_message}" with title "{escaped_title}"',
                    ]
                )
        except Exception:
            pass

    def set_system_notifier(self, notifier: Callable[[str, bool], None] | None) -> None:
        self._system_notifier = notifier

    def set_system_tray_visibility_handler(self, handler: Callable[[bool], None] | None) -> None:
        self._system_tray_visibility_handler = handler

    @Slot(bool)
    def setSystemTrayVisible(self, visible: bool) -> None:
        self._system_tray_visible = bool(visible)
        handler = getattr(self, "_system_tray_visibility_handler", None)
        if handler is None:
            return
        try:
            handler(bool(visible))
        except Exception:
            pass

    @Slot(str)
    def copyTextToClipboard(self, text: str) -> None:
        cleaned = text.strip()
        if not cleaned:
            self.reportNoSelectedWebsite()
            return
        clipboard = QApplication.clipboard()
        clipboard.setText(cleaned)
        self._last_operation_message = f"Copied: {cleaned}"
        self._last_operation_error = False
        self.operationFeedbackChanged.emit()

    def _move_path_to_trash(self, path: Path) -> Path:
        if not path.exists():
            raise FileNotFoundError(f"Path does not exist: {path}")
        system = platform.system()
        if system == "Darwin":
            trash_root = Path.home() / ".Trash"
        elif system == "Windows":
            trash_root = Path.home() / "AppData" / "Local" / "Temp" / "ServerEngineTrash"
        else:
            trash_root = Path.home() / ".local" / "share" / "Trash" / "files"
        trash_root.mkdir(parents=True, exist_ok=True)
        dest = trash_root / path.name
        counter = 1
        while dest.exists():
            dest = trash_root / f"{path.name}_{counter}"
            counter += 1
        shutil.move(str(path), str(dest))
        return dest

    @Slot(str, result=bool)
    def emptyFile(self, path: str) -> bool:
        cleaned = Path(str(path or "")).expanduser()
        if not str(cleaned).strip():
            return False
        try:
            if not cleaned.exists() or not cleaned.is_file():
                raise ValueError(f"Not a file: {cleaned}")
            cleaned.write_text("", encoding="utf-8")
            self._last_operation_message = f"Emptied: {cleaned}"
            self._last_operation_error = False
            self.operationFeedbackChanged.emit()
            self.dataChanged.emit()
            return True
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False

    @Slot(str, result=bool)
    def movePathToTrash(self, path: str) -> bool:
        cleaned = Path(str(path or "")).expanduser()
        if not str(cleaned).strip():
            return False
        try:
            dest = self._move_path_to_trash(cleaned)
            self._last_operation_message = f"Moved to Trash: {dest}"
            self._last_operation_error = False
            self.operationFeedbackChanged.emit()
            self.dataChanged.emit()
            return True
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False

    @Slot()
    def chooseAndOpenProjectFolder(self) -> None:
        parent = QApplication.activeWindow()
        selected = QFileDialog.getExistingDirectory(
            parent,
            "Open Project Folder",
            "",
        )
        if not selected:
            return
        try:
            subprocess.Popen(["open", selected])
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()

    @Slot(str, str, result=bool)
    def confirmNative(self, title: str, message: str) -> bool:
        parent = QApplication.activeWindow()
        if parent is None or (hasattr(parent, "isVisible") and not parent.isVisible()) or isinstance(parent, QMessageBox):
            candidates = [
                widget
                for widget in QApplication.topLevelWidgets()
                if widget.isVisible() and not isinstance(widget, QMessageBox)
            ]
            if candidates:
                parent = max(
                    candidates,
                    key=lambda widget: widget.frameGeometry().width() * widget.frameGeometry().height(),
                )
        dialog = QDialog(parent)
        dialog.setWindowTitle(title.strip() or "Confirm")
        dialog.setModal(True)
        if parent is not None and parent.isVisible():
            dialog.setWindowModality(Qt.WindowModal)
        else:
            dialog.setWindowModality(Qt.ApplicationModal)
        dialog.setWindowFlag(Qt.WindowContextHelpButtonHint, False)
        dialog.setWindowFlag(Qt.WindowStaysOnTopHint, True)

        layout = QVBoxLayout(dialog)
        layout.setContentsMargins(18, 16, 18, 14)
        layout.setSpacing(14)

        label = QLabel(message.strip() or "Are you sure?")
        label.setWordWrap(True)
        layout.addWidget(label)

        buttons = QDialogButtonBox(QDialogButtonBox.Yes | QDialogButtonBox.No)
        yes_button = buttons.button(QDialogButtonBox.Yes)
        no_button = buttons.button(QDialogButtonBox.No)
        if yes_button is not None:
            yes_button.setText("Yes")
        if no_button is not None:
            no_button.setText("Cancel")
            no_button.setDefault(True)
        buttons.accepted.connect(dialog.accept)
        buttons.rejected.connect(dialog.reject)
        layout.addWidget(buttons)

        dialog.adjustSize()

        def _center_box() -> None:
            target_geo = None
            if parent is not None and parent.isVisible():
                target_geo = parent.frameGeometry()
            else:
                focus_window = QGuiApplication.focusWindow()
                if focus_window is not None and focus_window.isVisible():
                    target_geo = focus_window.geometry()
                else:
                    screen = QGuiApplication.primaryScreen()
                    if screen is not None:
                        target_geo = screen.availableGeometry()
            if target_geo is None:
                return
            x = target_geo.x() + max((target_geo.width() - dialog.width()) // 2, 0)
            y = target_geo.y() + max((target_geo.height() - dialog.height()) // 2, 0)
            dialog.move(x, y)

        QTimer.singleShot(0, _center_box)
        return dialog.exec() == QDialog.DialogCode.Accepted

    def _parse_port_value(self, raw_value: str, label: str) -> int:
        value = raw_value.strip()
        if not value:
            raise ValueError(f"{label} port is required.")
        try:
            port = int(value)
        except ValueError as exc:
            raise ValueError(f"{label} port must be a number.") from exc
        if port < 1 or port > 65535:
            raise ValueError(f"{label} port must be between 1 and 65535.")
        return port

    def _is_tcp_port_available(self, port: int) -> bool:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            try:
                sock.bind(("127.0.0.1", port))
                return True
            except OSError:
                return False

    def _process_usage(self, pid: int | None) -> tuple[str, str]:
        if not pid:
            return "-", "-"
        try:
            result = subprocess.run(
                ["ps", "-p", str(pid), "-o", "%cpu=,rss="],
                capture_output=True,
                text=True,
                check=True,
            )
            raw = result.stdout.strip().split()
            if len(raw) >= 2:
                cpu = f"{float(raw[0]):.1f}%"
                ram_mb = float(raw[1]) / 1024.0
                return cpu, f"{ram_mb:.0f} MB"
        except Exception:
            pass
        return "-", "-"
