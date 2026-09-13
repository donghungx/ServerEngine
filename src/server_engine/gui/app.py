from __future__ import annotations

import logging
import os
import platform
import plistlib
import shutil
import signal
import subprocess
import sys
import time
import webbrowser
from urllib.parse import quote
from datetime import datetime
from pathlib import Path
import traceback
from typing import Any

from server_engine import __version__, __build_at__
from server_engine.bootstrap import build_container
from server_engine.core.models import RuntimePaths
from server_engine.gui.dashboard_bridge._shared import macos_prefers_dark_appearance
from server_engine.infrastructure.paths import PathProvider

_MACOS_WINDOW_OBSERVERS: list[Any] = []
_MACOS_THEME_OBSERVERS: list[Any] = []
_MACOS_OBSERVED_WINDOW_IDS: set[int] = set()


class _DailyFileHandler(logging.Handler):
    def __init__(self, log_dir: Path, prefix: str = "app") -> None:
        super().__init__()
        self._log_dir = log_dir
        self._prefix = prefix
        self._current_date = ""
        self._stream: Any | None = None

    def _target_path(self) -> Path:
        current_date = datetime.now().strftime("%d-%m-%Y")
        if current_date != self._current_date:
            self._current_date = current_date
            self._close_stream()
        day_dir = self._log_dir / self._prefix
        day_dir.mkdir(parents=True, exist_ok=True)
        return day_dir / f"{self._prefix}-{current_date}.log"

    def _ensure_stream(self) -> Any:
        path = self._target_path()
        if self._stream is None:
            self._stream = path.open("a", encoding="utf-8")
        return self._stream

    def _close_stream(self) -> None:
        if self._stream is not None:
            try:
                self._stream.close()
            finally:
                self._stream = None

    def emit(self, record: logging.LogRecord) -> None:
        try:
            stream = self._ensure_stream()
            stream.write(self.format(record) + "\n")
            stream.flush()
        except Exception:
            self.handleError(record)

    def close(self) -> None:
        self._close_stream()
        super().close()


def _bundled_runtime_root() -> Path | None:
    exe_path = Path(sys.executable).resolve()
    candidate = exe_path.parent.parent / "Resources" / "runtime"
    return candidate if candidate.is_dir() else None


def _bundled_app_version() -> str:
    try:
        exe_path = Path(sys.executable).resolve()
        for anchor in (exe_path.parent, *exe_path.parents):
            info_plist = anchor / "Info.plist"
            if info_plist.is_file():
                with info_plist.open("rb") as handle:
                    info = plistlib.load(handle)
                return str(
                    info.get("CFBundleVersion")
                    or info.get("CFBundleShortVersionString")
                    or __version__
                )
    except Exception:
        return __version__
    return __version__


def _macos_app_font() -> QFont:
    from PySide6.QtGui import QFont, QFontDatabase

    font_db = QFontDatabase()
    if "SF Pro Text" in font_db.families():
        return QFont("SF Pro Text")
    return QFontDatabase.systemFont(QFontDatabase.GeneralFont)


def _bundled_runtime_seed_marker_path(runtime_paths: RuntimePaths, bundle_version: str) -> Path:
    return runtime_paths.root / f".bundled_runtime_seed_{bundle_version}"


def _seed_bundled_runtime_if_needed(logger: logging.Logger) -> None:
    bundled_root = _bundled_runtime_root()
    if bundled_root is None:
        return
    runtime_paths = PathProvider().ensure()
    target_bin = runtime_paths.bin_dir
    bundled_version = _bundled_app_version()
    marker_path = _bundled_runtime_seed_marker_path(runtime_paths, bundled_version)
    if marker_path.exists():
        return
    target_bin.mkdir(parents=True, exist_ok=True)
    for child in bundled_root.iterdir():
        target = target_bin / child.name
        if child.is_dir():
            if target.exists() and not target.is_dir():
                if target.is_file() or target.is_symlink():
                    target.unlink()
                else:
                    shutil.rmtree(target)
            shutil.copytree(child, target, dirs_exist_ok=True)
        else:
            if target.exists() and target.is_dir():
                shutil.rmtree(target)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(child, target)
    marker_path.write_text("ok\n", encoding="utf-8")
    logger.info("Bundled runtime seed completed: version=%s source=%s target=%s", bundled_version, bundled_root, target_bin)


def _configure_app_logging() -> Path:
    runtime_paths = PathProvider().ensure()
    log_path = runtime_paths.logs_dir / "app" / f"app-{datetime.now().strftime('%d-%m-%Y')}.log"
    file_handler = _DailyFileHandler(runtime_paths.logs_dir)
    file_handler.setFormatter(
        logging.Formatter("%(asctime)s %(levelname)s [%(name)s] %(message)s")
    )
    level_name = os.environ.get("SERVER_ENGINE_LOG_LEVEL", "INFO").strip().upper() or "INFO"
    level = getattr(logging, level_name, logging.INFO)
    root_logger = logging.getLogger()
    root_logger.setLevel(level)
    root_logger.handlers.clear()
    root_logger.addHandler(file_handler)
    if os.environ.get("SERVER_ENGINE_LOG_STDOUT", "").strip().lower() in {"1", "true", "yes", "on"}:
        stream_handler = logging.StreamHandler(sys.stdout)
        stream_handler.setFormatter(
            logging.Formatter("%(asctime)s %(levelname)s [%(name)s] %(message)s")
        )
        root_logger.addHandler(stream_handler)
    return log_path


def qml_main_path() -> Path:
    if getattr(sys, "frozen", False):
        meipass = getattr(sys, "_MEIPASS", None)
        if meipass:
            candidate = Path(meipass) / "server_engine" / "gui" / "qml" / "Main.qml"
            if candidate.exists():
                return candidate
    return Path(__file__).resolve().parent / "qml" / "Main.qml"


def _is_supported_macos_version() -> tuple[bool, str]:
    if sys.platform != "darwin":
        return False, "Server Engine supports macOS only."
    version_text = (platform.mac_ver()[0] or "").strip()
    if not version_text:
        try:
            result = subprocess.run(
                ["sw_vers", "-productVersion"],
                capture_output=True,
                text=True,
                check=True,
            )
            version_text = (result.stdout or "").strip()
        except Exception:
            version_text = ""

    parts = [part for part in version_text.split(".") if part.isdigit()]
    major = int(parts[0]) if parts else 0
    minor = int(parts[1]) if len(parts) > 1 else 0
    if major == 0:
        # Fallback for environments where product version cannot be read:
        # Darwin 23 -> macOS 14, 24 -> macOS 15, etc.
        try:
            darwin_major = int(platform.release().split(".", 1)[0])
            if darwin_major >= 4:
                major = darwin_major - 9
                minor = 0
        except Exception:
            pass
    if (major, minor) < (14, 0):
        return False, f"Server Engine requires macOS 14.0 or newer. Detected macOS {version_text or 'unknown'}."
    return True, ""


def _detected_macos_version_text() -> str:
    version_text = (platform.mac_ver()[0] or "").strip()
    if version_text:
        return version_text
    try:
        result = subprocess.run(
            ["sw_vers", "-productVersion"],
            capture_output=True,
            text=True,
            check=True,
        )
        version_text = (result.stdout or "").strip()
        if version_text:
            return version_text
    except Exception:
        pass
    return "unknown"


class _SparkleUpdater:
    def __init__(self, logger: logging.Logger) -> None:
        self._logger = logger
        self._updater: Any | None = None
        self._user_driver: Any | None = None
        self._host_bundle: Any | None = None
        self._enabled = False
        self._status_message = "Sparkle not initialized."
        if sys.platform != "darwin":
            self._status_message = "Sparkle is available on macOS only."
            return
        try:
            import AppKit
            import objc
        except ImportError:
            self._status_message = "Missing AppKit/objc PyObjC modules."
            self._logger.info("Sparkle integration unavailable (%s).", self._status_message)
            return
        try:
            sparkle_bundle = None
            framework_path: Path | None = None
            env_framework_path = os.environ.get("SERVER_ENGINE_SPARKLE_FRAMEWORK_PATH", "").strip()
            if env_framework_path:
                candidate = Path(env_framework_path).expanduser()
                if candidate.exists():
                    framework_path = candidate
                else:
                    self._status_message = f"SERVER_ENGINE_SPARKLE_FRAMEWORK_PATH not found: {candidate}"
            if getattr(sys, "frozen", False):
                frozen_framework = Path(sys.executable).resolve().parent.parent / "Frameworks" / "Sparkle.framework"
                if framework_path is None:
                    framework_path = frozen_framework
            elif framework_path is None:
                cask_root = Path("/opt/homebrew/Caskroom/sparkle")
                if cask_root.is_dir():
                    for version_dir in sorted(cask_root.iterdir(), reverse=True):
                        candidate = version_dir / "Sparkle.framework"
                        if candidate.exists():
                            framework_path = candidate
                            break
                        app_candidate = version_dir / "Sparkle Test App.app" / "Contents" / "Frameworks" / "Sparkle.framework"
                        if app_candidate.exists():
                            framework_path = app_candidate
                            break
            if framework_path is not None and framework_path.exists():
                sparkle_bundle = AppKit.NSBundle.bundleWithPath_(str(framework_path))
            elif getattr(sys, "frozen", False):
                self._status_message = f"Sparkle.framework not found at {framework_path}"
            if sparkle_bundle is not None and not sparkle_bundle.isLoaded():
                if not sparkle_bundle.load():
                    self._status_message = f"Sparkle.framework failed to load from {framework_path}"
                    self._logger.warning("Sparkle framework load returned False for %s", framework_path)
                    return

            try:
                updater_cls = objc.lookUpClass("SPUUpdater")
                user_driver_cls = objc.lookUpClass("SPUStandardUserDriver")
            except Exception as exc:
                self._status_message = f"Sparkle updater classes unavailable: {exc}"
                self._logger.info("Sparkle integration unavailable (%s).", self._status_message)
                return
            self._host_bundle = AppKit.NSBundle.mainBundle()
            if self._host_bundle is None:
                self._status_message = "Unable to resolve the main application bundle."
                return
            self._user_driver = user_driver_cls.alloc().initWithHostBundle_delegate_(self._host_bundle, None)
            self._updater = updater_cls.alloc().initWithHostBundle_applicationBundle_userDriver_delegate_(
                self._host_bundle,
                self._host_bundle,
                self._user_driver,
                None,
            )
            appcast_url = os.environ.get("SERVER_ENGINE_SPARKLE_FEED_URL", "").strip() or None
            if appcast_url and self._updater is not None:
                from Foundation import NSURL

                self._updater.setFeedURL_(NSURL.URLWithString_(appcast_url))
            self._enabled = self._updater is not None
            self._status_message = "Ready." if self._enabled else "Sparkle updater initialization returned None."
        except Exception as exc:
            self._logger.warning("Sparkle initialization failed: %s", exc)
            self._updater = None
            self._user_driver = None
            self._host_bundle = None
            self._enabled = False
            self._status_message = str(exc)

    @property
    def enabled(self) -> bool:
        return self._enabled

    @property
    def status_message(self) -> str:
        return self._status_message

    def check_for_updates(self) -> None:
        if not self._enabled or self._updater is None:
            return
        try:
            # Sparkle 2 exposes `checkForUpdates` on `SPUUpdater`.
            if hasattr(self._updater, "checkForUpdates"):
                self._updater.checkForUpdates()
                return
            if hasattr(self._updater, "checkForUpdates_"):
                self._updater.checkForUpdates_(None)
                return
            raise AttributeError("No supported Sparkle check-for-updates selector found.")
        except Exception as exc:
            self._logger.warning("Sparkle check-for-updates failed: %s", exc)


def run() -> int:
    startup_started = time.perf_counter()

    try:
        from PySide6.QtQml import QQmlApplicationEngine
        from PySide6.QtGui import QAction, QActionGroup, QKeySequence, QIcon
        from PySide6.QtWidgets import (
            QApplication,
            QMenu,
            QMenuBar,
            QMessageBox,
            QSystemTrayIcon,
            QStyle,
            QStyleFactory,
        )
        from PySide6.QtCore import QEventLoop, QMetaObject, Qt, QTimer
    except ImportError as exc:
        raise SystemExit("PySide6 is required to launch the GUI.") from exc

    from server_engine.gui.qml_bridge import DashboardBridge
    from server_engine.gui.terminal_controller import TerminalController

    log_path = _configure_app_logging()
    logger = logging.getLogger("server_engine.app")

    def startup_checkpoint(label: str) -> None:
        logger.info("Startup timing: %-28s %8.1f ms", label, (time.perf_counter() - startup_started) * 1000.0)

    try:
        _seed_bundled_runtime_if_needed(logger)
    except Exception:
        logger.exception("Bundled runtime seed failed.")
    startup_checkpoint("bundled runtime seed")

    def _handle_uncaught_exception(exc_type, exc_value, exc_tb):
        if issubclass(exc_type, KeyboardInterrupt):
            logger.info("KeyboardInterrupt received; shutting down.")
            return
        logger.error("Uncaught exception:\n%s", "".join(traceback.format_exception(exc_type, exc_value, exc_tb)))
        sys.__excepthook__(exc_type, exc_value, exc_tb)

    sys.excepthook = _handle_uncaught_exception

    app = QApplication(sys.argv)
    startup_checkpoint("QApplication created")

    def _apply_qt_color_scheme(theme_mode: str | None) -> None:
        mode = str(theme_mode or "system").strip().lower()
        try:
            if mode == "dark":
                app.styleHints().setColorScheme(Qt.ColorScheme.Dark)
            elif mode == "light":
                app.styleHints().setColorScheme(Qt.ColorScheme.Light)
            else:
                app.styleHints().setColorScheme(Qt.ColorScheme.Unknown)
        except Exception:
            pass
    app.setApplicationName("Server Engine")
    if sys.platform == "darwin":
        app.setFont(_macos_app_font())
    if sys.platform == "darwin":
        style = QStyleFactory.create("macOS") or QStyleFactory.create("macintosh")
        if style is not None:
            app.setStyle(style)
    app.setQuitOnLastWindowClosed(False)
    signal.signal(signal.SIGINT, lambda *_args: app.quit())
    interrupt_timer = QTimer()
    interrupt_timer.setInterval(150)
    interrupt_timer.timeout.connect(lambda: None)
    interrupt_timer.start()
    logger.info("Application startup. log=%s", log_path)
    sparkle_updater = _SparkleUpdater(logger)
    startup_checkpoint("Sparkle initialization")

    supported, support_message = _is_supported_macos_version()
    if not supported:
        detected_version = _detected_macos_version_text()
        logger.error(support_message)
        print(support_message, file=sys.stderr)
        QMessageBox.critical(
            None,
            "Unsupported macOS Version",
            support_message + f"\n\nDetected version: {detected_version}",
            QMessageBox.StandardButton.Ok,
        )
        return 1
    startup_checkpoint("platform checks")

    bridge = None
    engine = None
    status_tray = None
    try:
        container = build_container()
        startup_checkpoint("container and database")
        startup_license_status = container.license_service.status()
        logger.info(
            "License state: path=%s status=%s valid=%s enforced=%s expires=%s",
            container.license_service.license_path,
            startup_license_status.status,
            startup_license_status.valid,
            startup_license_status.enforced,
            startup_license_status.expires_at or "-",
        )
        settings = container.settings_service.get_settings()
        _apply_qt_color_scheme(getattr(settings, "appearance_theme", "system"))
        bridge = DashboardBridge(container)
        terminal_controller = TerminalController(container)
        startup_checkpoint("bridge and controllers")
        app.aboutToQuit.connect(terminal_controller.stopAll)
        tray_icon_dir = Path(__file__).resolve().parent / "qml" / "icons"

        def _prefers_dark_appearance() -> bool:
            if sys.platform == "darwin":
                return macos_prefers_dark_appearance()
            try:
                color = app.palette().window().color()
                if color.isValid():
                    return color.lightness() < 128
            except Exception:
                pass
            try:
                return app.styleHints().colorScheme() == Qt.ColorScheme.Dark
            except Exception:
                return False

        def _tray_icon() -> QIcon:
            if sys.platform == "darwin":
                icon_name = "menubar-white-44.png" if macos_prefers_dark_appearance() else "menubar-dark-44.png"
            else:
                icon_name = "menubar-white-44.png" if _prefers_dark_appearance() else "menubar-dark-44.png"
            icon = QIcon(str(tray_icon_dir / icon_name))
            if icon.isNull():
                icon = app.style().standardIcon(QStyle.StandardPixmap.SP_ComputerIcon)
            return icon

        def _refresh_os_theme_state() -> None:
            try:
                if root is not None:
                    root.setProperty("currentOsPrefersDark", macos_prefers_dark_appearance())
            except Exception:
                logger.exception("Failed to refresh OS theme state.")
            _update_tray_icon()

        def _update_tray_icon() -> None:
            if status_tray is not None:
                status_tray.setIcon(_tray_icon())

        def _sync_qt_color_scheme() -> None:
            _apply_qt_color_scheme(getattr(bridge, "settingsAppearanceTheme", "system"))

        bridge.appSettingsFeedbackChanged.connect(_sync_qt_color_scheme)
        bridge.appSettingsFeedbackChanged.connect(_update_tray_icon)
        _sync_qt_color_scheme()
        engine = QQmlApplicationEngine()
        engine.rootContext().setContextProperty("dashboardBridge", bridge)
        engine.rootContext().setContextProperty("terminalController", terminal_controller)
        engine.rootContext().setContextProperty("appTerminalController", terminal_controller)
        qml_path = qml_main_path()
        engine.load(str(qml_path))
        if not engine.rootObjects():
            raise SystemExit(f"Unable to load QML interface: {qml_path}")
        root = engine.rootObjects()[0]
        startup_checkpoint("QML interface loaded")

        if QSystemTrayIcon.isSystemTrayAvailable():
            status_tray = QSystemTrayIcon(_tray_icon(), app)
            status_tray.setToolTip("Server Engine")
            status_tray.show()

            def _set_tray_visible(visible: bool) -> None:
                if status_tray is None:
                    return
                try:
                    bridge._system_tray_visible = bool(visible)  # type: ignore[attr-defined]
                    if visible:
                        status_tray.show()
                        _update_tray_icon()
                    else:
                        status_tray.hide()
                except Exception:
                    logger.exception("Failed to update tray visibility.")

            bridge.set_system_tray_visibility_handler(_set_tray_visible)
            _refresh_os_theme_state()

            if sys.platform == "darwin":
                try:
                    import AppKit
                except ImportError:
                    logger.debug("macOS theme observer skipped: AppKit is not installed.")
                else:
                    theme_center = AppKit.NSDistributedNotificationCenter.defaultCenter()
                    observer_theme = theme_center.addObserverForName_object_queue_usingBlock_(
                        "AppleInterfaceThemeChangedNotification",
                        None,
                        None,
                        lambda _note: _refresh_os_theme_state(),
                    )
                    _MACOS_THEME_OBSERVERS.append(observer_theme)

            def _focus_main_window() -> None:
                try:
                    root.show()
                    root.raise_()
                    root.requestActivate()
                except Exception:
                    logger.exception("Failed to focus main window from notification click.")

            status_tray.messageClicked.connect(_focus_main_window)

            def _notify_status(message: str, is_error: bool) -> None:
                icon = QSystemTrayIcon.Critical if is_error else QSystemTrayIcon.Information
                title = "Server Engine Error" if is_error else "Server Engine"
                status_tray.showMessage(title, message, icon, 5000)

            bridge.set_system_notifier(_notify_status)

            def _toggle_main_window() -> None:
                try:
                    if root.isVisible():
                        root.hide()
                    else:
                        _focus_main_window()
                except Exception:
                    logger.exception("Failed to toggle main window from tray.")

        QTimer.singleShot(0, lambda: _apply_macos_window_chrome(root, logger))
        if sys.platform == "darwin":
            app.focusWindowChanged.connect(
                lambda window: _apply_macos_window_chrome(window, logger) if window is not None else None
            )
            app.applicationStateChanged.connect(
                lambda state: _restore_window_on_macos_activate(root, state)
            )

        menu_bar = QMenuBar()

        def invoke_root_action(method_name: str) -> None:
            try:
                root.show()
                QMetaObject.invokeMethod(root, method_name)
            except Exception:
                logger.exception("Menu action failed: %s", method_name)

        def show_coming_soon(title: str) -> None:
            QMessageBox.information(QApplication.activeWindow(), title, "Coming soon.")

        def stop_web_service_for_license() -> None:
            settings = container.settings_service.get_settings()
            web_id = "nginx" if settings.active_web_server == settings.active_web_server.NGINX else "apache"
            container.stack_service.stop_service(web_id)

        def stop_postgresql_for_license() -> None:
            if container.postgresql_service.active_runtime() is None:
                logger.info("Skipping PostgreSQL stop for license shutdown: runtime not installed.")
                return
            container.postgresql_service.stop_runtime()

        def stop_mongodb_for_license() -> None:
            if container.mongodb_service.active_runtime() is None:
                logger.info("Skipping MongoDB stop for license shutdown: runtime not installed.")
                return
            container.mongodb_service.stop_runtime()

        def stop_all_services_for_license() -> None:
            services_to_stop = (
                ("web", stop_web_service_for_license),
                ("database", container.database_service.stop_runtime),
                ("postgresql", stop_postgresql_for_license),
                ("mongodb", stop_mongodb_for_license),
                ("redis", container.redis_service.stop_runtime),
                ("memcached", container.memcached_service.stop_runtime),
                ("mailpit", container.mailpit_service.stop_runtime),
            )
            try:
                for label, callback in services_to_stop:
                    try:
                        callback()
                    except Exception:
                        logger.exception("Failed to stop %s for license shutdown.", label)
                for project in container.node_project_service.list_projects():
                    container.node_project_runtime_service.stop(project.id)
            except Exception:
                logger.exception("Failed to stop node projects for license shutdown.")

        def show_license_dialog(startup_enforced: bool = False) -> bool:
            result = {"accepted": False}
            loop = QEventLoop()

            def finish(accepted: bool) -> None:
                result["accepted"] = bool(accepted)
                loop.quit()

            root.licenseDialogFinished.connect(finish)
            try:
                root.setProperty("licenseDialogStartupEnforced", bool(startup_enforced))
                root.setProperty("licenseDialogOpen", True)
                root.show()
                root.raise_()
                root.requestActivate()
                loop.exec()
            finally:
                try:
                    root.licenseDialogFinished.disconnect(finish)
                except Exception:
                    pass
            return bool(result["accepted"])

        def enforce_license_or_quit() -> None:
            if not container.license_service.is_enforced():
                logger.info("DEV license check: startup enforcement running.")
            status = container.license_service.revalidate_if_due(force=True)
            if not container.license_service.is_enforced():
                logger.info(
                    "DEV license check: startup result status=%s valid=%s message=%s",
                    status.status,
                    status.valid,
                    status.message,
                )
            if status.valid:
                return
            stop_all_services_for_license()
            QMessageBox.critical(
                QApplication.activeWindow(),
                "License Required",
                status.message or "License is not valid. Server Engine will stop all services and quit unless a valid license is activated.",
            )
            accepted = show_license_dialog(startup_enforced=True) and container.license_service.status().valid
            if not accepted:
                stop_all_services_for_license()
                logger.info("License dialog rejected. Stopping all services before exit.")
                app.quit()

        def build_stamp_text() -> str:
            if __build_at__:
                return __build_at__
            build_raw = os.environ.get("SERVER_ENGINE_BUILD_AT", "").strip()
            if build_raw:
                try:
                    parsed = datetime.fromisoformat(build_raw.replace("Z", "+00:00"))
                    return parsed.astimezone().strftime("%Y-%m-%d %H:%M:%S")
                except ValueError:
                    return build_raw
            try:
                stamp = qml_main_path().stat().st_mtime
                return datetime.fromtimestamp(stamp).strftime("%Y-%m-%d %H:%M:%S")
            except Exception:
                return "Development build"

        def show_about_dialog() -> None:
            build_text = build_stamp_text()
            runtime_mode = os.environ.get("SERVER_ENGINE_RUNTIME_MODE", "").strip() or (
                "frozen" if getattr(sys, "frozen", False) else "source"
            )
            python_version = f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}"
            license_mode = "Enforced" if container.license_service.is_enforced() else "Development"
            app_support_path = str(PathProvider().ensure().root)
            logo_path = Path(__file__).resolve().parents[3] / "assets" / "logo.png"
            root.setProperty("aboutVersion", __version__)
            root.setProperty("aboutBuild", build_text)
            root.setProperty("aboutRuntimeMode", runtime_mode)
            root.setProperty("aboutLicenseMode", license_mode)
            root.setProperty("aboutPythonVersion", python_version)
            root.setProperty("aboutAppSupportPath", app_support_path)
            root.setProperty("aboutLogoSource", logo_path.as_uri() if logo_path.exists() else "")
            root.setProperty("aboutDialogOpen", True)
            root.show()
            root.raise_()
            root.requestActivate()

        about_action = QAction("About Server Engine", menu_bar)
        about_action.setMenuRole(QAction.AboutRole)
        about_action.triggered.connect(show_about_dialog)

        check_updates_action = QAction("Check for Updates...", menu_bar)
        check_updates_action.setMenuRole(QAction.ApplicationSpecificRole)
        if sparkle_updater.enabled:
            check_updates_action.triggered.connect(lambda: sparkle_updater.check_for_updates())
        else:
            check_updates_action.triggered.connect(
                lambda: QMessageBox.information(
                    QApplication.activeWindow(),
                    "Sparkle Unavailable",
                    f"Sparkle updater is unavailable.\n\nReason: {sparkle_updater.status_message}",
                )
            )

        settings_action = QAction("Settings", menu_bar)
        settings_action.setMenuRole(QAction.PreferencesRole)
        settings_action.setShortcut(QKeySequence(QKeySequence.StandardKey.Preferences))
        settings_action.triggered.connect(lambda: root.setProperty("appSettingsOpen", True))
        quit_action = QAction("Quit Server Engine", menu_bar)
        quit_action.setMenuRole(QAction.QuitRole)
        quit_action.setShortcut(QKeySequence(QKeySequence.StandardKey.Quit))
        quit_action.triggered.connect(app.quit)

        file_menu = menu_bar.addMenu("File")
        file_menu.addAction(about_action)
        file_menu.addAction(check_updates_action)
        file_menu.addSeparator()
        file_menu.addAction(settings_action)
        file_menu.addSeparator()
        file_menu.addAction(quit_action)
        file_menu.addSeparator()

        new_php_site_action = QAction("New PHP Website...", menu_bar)
        new_php_site_action.setShortcut(QKeySequence("Ctrl+N"))
        new_php_site_action.triggered.connect(lambda: invoke_root_action("openNewPhpWebsite"))
        file_menu.addAction(new_php_site_action)

        new_node_project_action = QAction("New Node Project...", menu_bar)
        new_node_project_action.setShortcut(QKeySequence("Ctrl+Shift+N"))
        new_node_project_action.triggered.connect(lambda: invoke_root_action("openNewNodeProject"))
        file_menu.addAction(new_node_project_action)

        new_database_action = QAction("New Database...", menu_bar)
        new_database_action.setShortcut(QKeySequence("Ctrl+Alt+N"))
        new_database_action.triggered.connect(lambda: invoke_root_action("openNewDatabase"))
        file_menu.addAction(new_database_action)

        file_menu.addSeparator()

        open_project_folder_action = QAction("Open Project Folder...", menu_bar)
        open_project_folder_action.setShortcut(QKeySequence(QKeySequence.StandardKey.Open))
        open_project_folder_action.triggered.connect(bridge.chooseAndOpenProjectFolder)
        file_menu.addAction(open_project_folder_action)

        file_menu.addSeparator()

        import_database_action = QAction("Import Database...", menu_bar)
        import_database_action.setShortcut(QKeySequence("Ctrl+I"))
        import_database_action.triggered.connect(lambda: invoke_root_action("openDatabaseImport"))
        file_menu.addAction(import_database_action)

        backup_database_action = QAction("Export/Backup Database...", menu_bar)
        backup_database_action.setShortcut(QKeySequence("Ctrl+E"))
        backup_database_action.triggered.connect(lambda: invoke_root_action("openDatabaseBackup"))
        file_menu.addAction(backup_database_action)

        file_menu.addSeparator()

        import_websites_action = QAction("Import Websites...", menu_bar)
        import_websites_action.triggered.connect(bridge.importWebsitesAndProjects)
        file_menu.addAction(import_websites_action)

        export_websites_action = QAction("Export Websites...", menu_bar)
        export_websites_action.triggered.connect(bridge.exportWebsitesAndProjects)
        file_menu.addAction(export_websites_action)

        file_menu.addSeparator()

        close_action = QAction("Close Window", menu_bar)
        close_action.setShortcut(QKeySequence(QKeySequence.StandardKey.Close))
        close_action.triggered.connect(lambda: root.hide())
        file_menu.addAction(close_action)

        edit_menu = menu_bar.addMenu("Edit")
        for label, shortcut in (
            ("Undo", QKeySequence.StandardKey.Undo),
            ("Redo", QKeySequence.StandardKey.Redo),
            ("Cut", QKeySequence.StandardKey.Cut),
            ("Copy", QKeySequence.StandardKey.Copy),
            ("Paste", QKeySequence.StandardKey.Paste),
            ("Select All", QKeySequence.StandardKey.SelectAll),
        ):
            action = QAction(label, menu_bar)
            action.setShortcut(QKeySequence(shortcut))
            edit_menu.addAction(action)

        view_menu = menu_bar.addMenu("View")
        view_page_group = QActionGroup(menu_bar)
        view_page_group.setExclusive(True)
        view_page_actions: dict[str, QAction] = {}
        for label, page_id, shortcut in (
            ("Home", "home", "Ctrl+1"),
            ("Websites", "website", "Ctrl+2"),
            ("PHP", "php", "Ctrl+3"),
            ("Database", "database", "Ctrl+4"),
            ("Redis", "redis", "Ctrl+5"),
            ("Memcached", "cache", "Ctrl+6"),
            ("Mail Server", "mail", "Ctrl+7"),
            ("Logs", "logs", "Ctrl+8"),
        ):
            action = QAction(label, menu_bar)
            action.setCheckable(True)
            action.setShortcut(QKeySequence(shortcut))
            action.triggered.connect(lambda _checked=False, target=page_id: bridge.setCurrentPage(target))
            view_page_group.addAction(action)
            view_menu.addAction(action)
            view_page_actions[page_id] = action

        def sync_view_menu_page() -> None:
            action = view_page_actions.get(bridge.currentPage)
            if action is not None:
                action.setChecked(True)

        bridge.currentPageChanged.connect(sync_view_menu_page)
        sync_view_menu_page()
        view_menu.addSeparator()

        fullscreen_action = QAction("Enter Full Screen", menu_bar)
        fullscreen_action.setShortcut(QKeySequence(QKeySequence.StandardKey.FullScreen))
        fullscreen_action.triggered.connect(
            lambda: root.setVisibility(root.FullScreen if root.visibility() != root.FullScreen else root.Windowed)
        )
        view_menu.addAction(fullscreen_action)

        stack_menu = menu_bar.addMenu("Stack")

        def add_stack_action(label: str, callback) -> QAction:
            action = QAction(label, menu_bar)
            action.triggered.connect(callback)
            stack_menu.addAction(action)
            return action

        start_all_action = add_stack_action("Start All Services", bridge.startAllServices)
        stop_all_action = add_stack_action("Stop All Services", bridge.stopAllServices)
        restart_all_action = add_stack_action("Restart All Services", bridge.restartAllServices)
        stack_menu.addSeparator()

        start_web_action = add_stack_action("Start Web Server", bridge.startWebServerRuntime)
        stop_web_action = add_stack_action("Stop Web Server", bridge.stopWebServerRuntime)
        restart_web_action = add_stack_action("Restart Web Server", bridge.restartWebServerRuntime)
        stack_menu.addSeparator()

        start_database_action = add_stack_action("Start Database", bridge.startDatabaseRuntime)
        stop_database_action = add_stack_action("Stop Database", bridge.stopDatabaseRuntime)
        restart_database_action = add_stack_action("Restart Database", bridge.restartDatabaseRuntime)
        stack_menu.addSeparator()

        start_redis_action = add_stack_action("Start Redis", bridge.startRedisRuntime)
        stop_redis_action = add_stack_action("Stop Redis", bridge.stopRedisRuntime)
        restart_redis_action = add_stack_action("Restart Redis", bridge.restartRedisRuntime)
        stack_menu.addSeparator()

        start_memcached_action = add_stack_action("Start Memcached", bridge.startMemcachedRuntime)
        stop_memcached_action = add_stack_action("Stop Memcached", bridge.stopMemcachedRuntime)
        stack_menu.addSeparator()

        start_mailpit_action = add_stack_action("Start Mailpit", bridge.startMailpitRuntime)
        stop_mailpit_action = add_stack_action("Stop Mailpit", bridge.stopMailpitRuntime)
        stack_menu.addSeparator()

        add_stack_action("Open phpMyAdmin", bridge.openPhpMyAdmin)

        def sync_stack_menu() -> None:
            service_items = {item["id"]: item for item in bridge.homeServiceItems}
            service_ids = ["web", "database", "redis", "memcached", "mailpit"]
            running = {service_id: bool(service_items.get(service_id, {}).get("running", False)) for service_id in service_ids}
            busy = {service_id: bridge.homeServiceBusy(service_id) for service_id in service_ids}
            all_running = all(running.values())
            any_busy = any(busy.values()) or bridge.globalStackBusy

            start_all_action.setVisible(not all_running)
            stop_all_action.setVisible(all_running)
            restart_all_action.setVisible(all_running)
            for action in (start_all_action, stop_all_action, restart_all_action):
                action.setEnabled(not any_busy)

            for service_id, start_action, stop_action, restart_action in (
                ("web", start_web_action, stop_web_action, restart_web_action),
                ("database", start_database_action, stop_database_action, restart_database_action),
                ("redis", start_redis_action, stop_redis_action, restart_redis_action),
            ):
                is_running = running[service_id]
                is_busy = busy[service_id]
                start_action.setVisible(not is_running)
                stop_action.setVisible(is_running)
                restart_action.setVisible(is_running)
                start_action.setEnabled(not is_busy)
                stop_action.setEnabled(not is_busy)
                restart_action.setEnabled(not is_busy)

            for service_id, start_action, stop_action in (
                ("memcached", start_memcached_action, stop_memcached_action),
                ("mailpit", start_mailpit_action, stop_mailpit_action),
            ):
                is_running = running[service_id]
                is_busy = busy[service_id]
                start_action.setVisible(not is_running)
                stop_action.setVisible(is_running)
                start_action.setEnabled(not is_busy)
                stop_action.setEnabled(not is_busy)

        stack_menu.aboutToShow.connect(sync_stack_menu)
        bridge.actionStateChanged.connect(sync_stack_menu)
        sync_stack_menu()

        website_menu = menu_bar.addMenu("Website")

        def add_website_action(label: str, method_name: str) -> QAction:
            action = QAction(label, menu_bar)
            action.triggered.connect(lambda _checked=False, target=method_name: invoke_root_action(target))
            website_menu.addAction(action)
            return action

        add_website_action("Add Website...", "openNewPhpWebsite")
        add_website_action("Add Node Project...", "openNewNodeProject")
        website_menu.addSeparator()

        add_website_action("Edit Selected Website...", "editSelectedWebsite")
        add_website_action("Delete Selected Website...", "deleteSelectedWebsite")
        website_menu.addSeparator()

        add_website_action("Open Website in Browser", "openSelectedWebsiteInBrowser")
        add_website_action("Reveal Project in Finder", "revealSelectedWebsiteProject")
        add_website_action("Copy Local Domain", "copySelectedWebsiteLocalDomain")
        website_menu.addSeparator()

        add_website_action("Generate Self-Signed SSL Certificate", "generateSelectedWebsiteSelfSignedCertificate")
        add_website_action("Reload Web Routes", "reloadWebRoutes")

        tools_menu = menu_bar.addMenu("Tools")

        def add_tools_action(label: str, callback) -> QAction:
            action = QAction(label, menu_bar)
            action.triggered.connect(callback)
            tools_menu.addAction(action)
            return action

        add_tools_action("Open Runtime Folder", lambda: bridge.openRuntimePath("runtime"))
        add_tools_action("Open Config Folder", lambda: bridge.openRuntimePath("config"))
        add_tools_action("Open Logs Folder", lambda: bridge.openRuntimePath("logs"))
        add_tools_action("Open Backups Folder", lambda: bridge.openRuntimePath("backups"))
        add_tools_action("Open Hosts File", lambda: bridge.openRuntimePath("hosts"))
        tools_menu.addSeparator()

        add_tools_action("Validate Configuration", bridge.validateConfiguration)
        add_tools_action("Regenerate Web Server Configs", bridge.regenerateWebServerConfigs)
        tools_menu.addSeparator()

        add_tools_action("Clear App Feedback", bridge.clearAppFeedback)
        add_tools_action("Tail Logs", lambda: invoke_root_action("tailLogs"))

        window_menu = menu_bar.addMenu("Window")
        minimize_action = QAction("Minimize", menu_bar)
        minimize_action.setShortcut(QKeySequence("Ctrl+M"))
        minimize_action.triggered.connect(lambda: root.showMinimized())
        window_menu.addAction(minimize_action)

        zoom_action = QAction("Zoom", menu_bar)
        zoom_action.triggered.connect(
            lambda: root.showNormal() if root.visibility() == root.Maximized else root.showMaximized()
        )
        window_menu.addAction(zoom_action)

        window_menu.addSeparator()

        bring_all_to_front_action = QAction("Bring All to Front", menu_bar)
        bring_all_to_front_action.triggered.connect(lambda: (root.show(), root.raise_(), root.requestActivate()))
        window_menu.addAction(bring_all_to_front_action)

        help_menu = menu_bar.addMenu("Help")
        support_action = QAction("Support", menu_bar)
        support_action.triggered.connect(
            lambda: webbrowser.open("http://support.ninacoder.com/serverengine")
        )
        help_menu.addAction(support_action)

        documentation_action = QAction("Documentation", menu_bar)
        documentation_action.triggered.connect(
            lambda: webbrowser.open("https://se-docs.ninacoder.top/")
        )
        help_menu.addAction(documentation_action)

        def open_report_issue_mail() -> None:
            subject = quote("Server Engine Issue")
            body = quote("Server Engine issue report:\n\n")
            subprocess.Popen(["open", f"mailto:reports@ninacoder.top?subject={subject}&body={body}"])

        report_issue_action = QAction("Report Issue", menu_bar)
        report_issue_action.triggered.connect(open_report_issue_mail)
        help_menu.addAction(report_issue_action)

        open_application_log_action = QAction("Open Application Log", menu_bar)
        open_application_log_action.triggered.connect(lambda: invoke_root_action("tailLogs"))
        help_menu.addAction(open_application_log_action)

        help_menu.addSeparator()
        register_action = QAction("Register...", menu_bar)
        register_action.triggered.connect(lambda: show_license_dialog(startup_enforced=False))
        help_menu.addAction(register_action)

        tray_menu = QMenu()
        tray_menu.setTitle("Server Engine")

        main_window_action = QAction("Main Window", tray_menu)
        main_window_action.triggered.connect(_toggle_main_window)

        open_logs_view_action = QAction("Open Logs View", tray_menu)
        open_logs_view_action.triggered.connect(lambda: invoke_root_action("tailLogs"))
        open_logs_folder_action = QAction("Open Logs Folder", tray_menu)
        open_logs_folder_action.triggered.connect(lambda: bridge.openRuntimePath("logs"))
        open_terminal_action = QAction("Open CLI", tray_menu)
        open_terminal_action.triggered.connect(lambda: invoke_root_action("openDefaultTerminal"))

        tray_menu.addAction(main_window_action)
        tray_menu.addSeparator()

        tray_menu.addSection("Logs")
        tray_menu.addAction(open_logs_view_action)
        tray_menu.addAction(open_logs_folder_action)
        tray_menu.addSeparator()

        tray_menu.addSection("CLI")
        tray_menu.addAction(open_terminal_action)
        tray_menu.addSeparator()

        tray_menu.addAction(new_php_site_action)
        tray_menu.addAction(new_node_project_action)
        tray_menu.addSeparator()
        tray_menu.addAction(settings_action)
        tray_menu.addAction(about_action)
        tray_menu.addAction(check_updates_action)
        tray_menu.addSeparator()
        tray_menu.addAction(start_web_action)
        tray_menu.addAction(stop_web_action)
        tray_menu.addAction(restart_web_action)
        tray_menu.addAction(start_database_action)
        tray_menu.addAction(stop_database_action)
        tray_menu.addAction(restart_database_action)
        tray_menu.addAction(start_redis_action)
        tray_menu.addAction(stop_redis_action)
        tray_menu.addAction(restart_redis_action)
        tray_menu.addAction(start_memcached_action)
        tray_menu.addAction(stop_memcached_action)
        tray_menu.addAction(start_mailpit_action)
        tray_menu.addAction(stop_mailpit_action)
        tray_menu.addSeparator()
        tray_menu.addAction(quit_action)

        if status_tray is not None:
            status_tray.setContextMenu(tray_menu)
            status_tray.activated.connect(
                lambda reason: _toggle_main_window()
                if reason in {QSystemTrayIcon.Trigger, QSystemTrayIcon.DoubleClick}
                else None
            )

        startup_checkpoint("menus and tray ready")

        def schedule_periodic_license_revalidate() -> None:
            timer = QTimer(app)
            timer.setInterval(6 * 60 * 60 * 1000)

            def run_revalidate() -> None:
                if not container.license_service.is_enforced():
                    logger.info("DEV license check: periodic timer fired.")
                next_status = container.license_service.revalidate_if_due(force=False)
                if not container.license_service.is_enforced():
                    logger.info(
                        "DEV license check: periodic result status=%s valid=%s message=%s",
                        next_status.status,
                        next_status.valid,
                        next_status.message,
                    )
                if next_status.valid:
                    return
                if next_status.status not in {"expired", "revoked", "banned"}:
                    return
                stop_all_services_for_license()
                QMessageBox.critical(
                    QApplication.activeWindow(),
                    "License Required",
                    next_status.message or "License is not valid.",
                )
                if not show_license_dialog(startup_enforced=True) or not container.license_service.status().valid:
                    app.quit()

            timer.timeout.connect(run_revalidate)
            timer.start()
            app._license_revalidate_timer = timer  # type: ignore[attr-defined]

        try:
            # Let the main window appear first, then perform the network-backed
            # license revalidation a few minutes later.
            QTimer.singleShot(5 * 60 * 1000, enforce_license_or_quit)
            schedule_periodic_license_revalidate()
            exit_code = app.exec()
            logger.info("Application exit with code %s", exit_code)
            return exit_code
        except KeyboardInterrupt:
            logger.warning("KeyboardInterrupt received; shutting down.")
            app.quit()
            return 130
    except Exception:
        logger.exception("Fatal error while bootstrapping application.")
        raise
    finally:
        if bridge is not None:
            bridge.set_system_notifier(None)
            bridge.set_system_tray_visibility_handler(None)
        if status_tray is not None:
            status_tray.hide()
        if engine is not None:
            for root in engine.rootObjects():
                try:
                    root.deleteLater()
                except Exception:
                    pass
        if bridge is not None:
            bridge.shutdown()
        logger.info("Application shutdown completed.")


def _apply_macos_window_chrome(root: Any, logger: logging.Logger) -> None:
    if sys.platform != "darwin":
        return
    try:
        import AppKit
        import ctypes
        import objc
    except ImportError:
        logger.debug("macOS chrome setup skipped: PyObjC AppKit/objc is not installed.")
        return

    try:
        win_id = int(root.winId())
        native_view = objc.objc_object(c_void_p=ctypes.c_void_p(win_id))
        native_window = native_view.window()
        if native_window is None:
            logger.warning("macOS chrome setup skipped: NSWindow not available.")
            return

        _apply_macos_titlebar_style(native_window)
        native_window_id = int(native_window.windowNumber())
        if native_window_id in _MACOS_OBSERVED_WINDOW_IDS:
            return

        center = AppKit.NSNotificationCenter.defaultCenter()
        observer_resize = center.addObserverForName_object_queue_usingBlock_(
            AppKit.NSWindowDidResizeNotification,
            native_window,
            None,
            lambda _note: _apply_macos_titlebar_style(native_window),
        )
        observer_exit_fullscreen = center.addObserverForName_object_queue_usingBlock_(
            AppKit.NSWindowDidExitFullScreenNotification,
            native_window,
            None,
            lambda _note: _apply_macos_titlebar_style(native_window),
        )
        observer_enter_fullscreen = center.addObserverForName_object_queue_usingBlock_(
            AppKit.NSWindowDidEnterFullScreenNotification,
            native_window,
            None,
            lambda _note: _apply_macos_titlebar_style(native_window),
        )
        _MACOS_WINDOW_OBSERVERS.extend(
            [observer_resize, observer_exit_fullscreen, observer_enter_fullscreen]
        )
        _MACOS_OBSERVED_WINDOW_IDS.add(native_window_id)
    except Exception as exc:
        logger.warning("macOS chrome setup failed: %s", exc)


def _apply_macos_titlebar_style(native_window: Any) -> None:
    import AppKit

    native_window.setStyleMask_(
        native_window.styleMask() | AppKit.NSWindowStyleMaskFullSizeContentView
    )
    native_window.setTitlebarAppearsTransparent_(True)
    native_window.setTitleVisibility_(AppKit.NSWindowTitleHidden)
    native_window.setMovableByWindowBackground_(True)

    for button_kind in (
        AppKit.NSWindowCloseButton,
        AppKit.NSWindowMiniaturizeButton,
        AppKit.NSWindowZoomButton,
    ):
        button = native_window.standardWindowButton_(button_kind)
        if button is not None:
            button.setHidden_(False)


def _restore_window_on_macos_activate(root: Any, state: Any) -> None:
    try:
        from PySide6.QtCore import Qt
    except ImportError:
        return
    if state != Qt.ApplicationActive:
        return
    if root is None or root.isVisible():
        return
    root.show()
    root.raise_()
    root.requestActivate()
