from __future__ import annotations

from dataclasses import asdict, dataclass
from pathlib import Path

from server_engine.core.models import AppSettings, LogSource, Site, StackStatus

try:
    from PySide6.QtCore import Qt
    from PySide6.QtWidgets import (
        QCheckBox,
        QComboBox,
        QDialog,
        QDialogButtonBox,
        QFileDialog,
        QFormLayout,
        QFrame,
        QHBoxLayout,
        QLabel,
        QLineEdit,
        QListWidget,
        QListWidgetItem,
        QMainWindow,
        QMessageBox,
        QPushButton,
        QPlainTextEdit,
        QStackedWidget,
        QSpinBox,
        QSplitter,
        QToolBar,
        QVBoxLayout,
        QWidget,
    )
except ImportError:
    Qt = object
    QMainWindow = object


@dataclass(slots=True)
class SiteFormPayload:
    name: str
    local_domain: str
    project_path: str
    web_root: str
    php_version: str
    database_enabled: bool
    database_name: str
    database_user: str
    notes: str
    tags: str


class SiteDialog(QDialog):
    def __init__(self, parent: QWidget | None = None, site: Site | None = None, php_versions: list[str] | None = None) -> None:
        super().__init__(parent)
        self.setWindowTitle("Site")
        self.name_edit = QLineEdit(site.name if site else "")
        self.domain_edit = QLineEdit(site.local_domain if site else "")
        self.project_path_edit = QLineEdit(site.project_path if site else "")
        self.web_root_edit = QComboBox()
        self.web_root_edit.setEditable(True)
        self.php_version_edit = QComboBox()
        self.php_version_edit.setEditable(True)
        versions = php_versions or []
        for version in versions:
            self.php_version_edit.addItem(version)
        if site and site.php_version not in versions:
            self.php_version_edit.addItem(site.php_version)
        if site:
            self.php_version_edit.setCurrentText(site.php_version)
        elif versions:
            self.php_version_edit.setCurrentText(versions[-1])
        else:
            self.php_version_edit.setCurrentText("8.3")
        self.database_enabled_check = QCheckBox()
        self.database_enabled_check.setChecked(site.database_enabled if site else False)
        self.database_name_edit = QLineEdit(site.database_name or "" if site else "")
        self.database_user_edit = QLineEdit(site.database_user or "" if site else "")
        self.notes_edit = QLineEdit(site.notes if site else "")
        self.tags_edit = QLineEdit(", ".join(site.tags) if site else "")
        browse_button = QPushButton("Browse")
        browse_button.clicked.connect(self._browse)
        self.project_path_edit.textChanged.connect(self._reload_web_root_choices)

        layout = QFormLayout(self)
        project_row = QWidget()
        project_layout = QHBoxLayout(project_row)
        project_layout.setContentsMargins(0, 0, 0, 0)
        project_layout.addWidget(self.project_path_edit)
        project_layout.addWidget(browse_button)
        layout.addRow("Name", self.name_edit)
        layout.addRow("Local Domain", self.domain_edit)
        layout.addRow("Project Path", project_row)
        layout.addRow("Web Root", self.web_root_edit)
        layout.addRow("PHP Version", self.php_version_edit)
        layout.addRow("Database Enabled", self.database_enabled_check)
        layout.addRow("Database Name", self.database_name_edit)
        layout.addRow("Database User", self.database_user_edit)
        layout.addRow("Notes", self.notes_edit)
        layout.addRow("Tags", self.tags_edit)
        buttons = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        layout.addRow(buttons)
        selected_web_root = site.web_root if site else "public"
        self._reload_web_root_choices(self.project_path_edit.text(), selected_value=selected_web_root)

    def _browse(self) -> None:
        path = QFileDialog.getExistingDirectory(self, "Choose Project Directory")
        if path:
            self.project_path_edit.setText(path)

    def _reload_web_root_choices(self, project_path: str, selected_value: str | None = None) -> None:
        current = selected_value if selected_value is not None else self.web_root_edit.currentText()
        normalized_current = self._normalize_web_root_choice(current)
        project_root = Path(project_path).expanduser() if project_path.strip() else None
        choices = ["/"]
        if project_root and project_root.exists() and project_root.is_dir():
            directories = sorted(
                child.name
                for child in project_root.iterdir()
                if child.is_dir() and not child.name.startswith(".")
            )
            choices.extend(directories)
        unique_choices: list[str] = []
        for choice in choices:
            if choice not in unique_choices:
                unique_choices.append(choice)
        self.web_root_edit.clear()
        for choice in unique_choices:
            self.web_root_edit.addItem(choice)
        display_value = "/" if normalized_current == "." else normalized_current
        if display_value and display_value not in unique_choices:
            self.web_root_edit.addItem(display_value)
        self.web_root_edit.setCurrentText(display_value or "/")

    def _normalize_web_root_choice(self, value: str) -> str:
        cleaned = value.strip()
        if cleaned in {"", "/", "."}:
            return "."
        return cleaned.strip("/")

    def payload(self) -> dict[str, object]:
        data = SiteFormPayload(
            name=self.name_edit.text(),
            local_domain=self.domain_edit.text(),
            project_path=self.project_path_edit.text(),
            web_root=self.web_root_edit.currentText(),
            php_version=self.php_version_edit.currentText(),
            database_enabled=self.database_enabled_check.isChecked(),
            database_name=self.database_name_edit.text(),
            database_user=self.database_user_edit.text(),
            notes=self.notes_edit.text(),
            tags=self.tags_edit.text(),
        )
        return asdict(data)


class SettingsDialog(QDialog):
    def __init__(
        self,
        parent: QWidget | None = None,
        settings: AppSettings | None = None,
        php_versions: list[str] | None = None,
        database_runtimes: list[str] | None = None,
    ) -> None:
        super().__init__(parent)
        self.setWindowTitle("Settings")
        self.resize(860, 560)
        settings = settings or AppSettings()
        available_versions = php_versions or []
        available_database_runtimes = database_runtimes or []
        self.default_php_version_edit = QComboBox()
        self.default_php_version_edit.setEditable(True)
        for version in available_versions:
            self.default_php_version_edit.addItem(version)
        if settings.default_php_version not in available_versions:
            self.default_php_version_edit.addItem(settings.default_php_version)
        self.default_php_version_edit.setCurrentText(settings.default_php_version)
        self.apache_port_edit = QSpinBox()
        self.apache_port_edit.setRange(1024, 65535)
        self.apache_port_edit.setValue(settings.apache_port)
        self.database_engine_edit = QComboBox()
        self.database_engine_edit.addItems(["mariadb", "mysql"])
        if self.database_engine_edit.findText(settings.preferred_database_engine) == -1:
            self.database_engine_edit.addItem(settings.preferred_database_engine)
        self.database_engine_edit.setCurrentText(settings.preferred_database_engine)
        self.database_runtime_edit = QComboBox()
        self.database_runtime_edit.setEditable(True)
        for runtime_id in available_database_runtimes:
            self.database_runtime_edit.addItem(runtime_id)
        if settings.active_database_version and self.database_runtime_edit.findText(settings.active_database_version) == -1:
            self.database_runtime_edit.addItem(settings.active_database_version)
        self.database_runtime_edit.setCurrentText(settings.active_database_version or "")
        self.database_port_edit = QSpinBox()
        self.database_port_edit.setRange(1024, 65535)
        self.database_port_edit.setValue(settings.database_port)
        self.environment_root_edit = QLineEdit(settings.environment_root or "")
        self.environment_root_browse = QPushButton("Browse")
        self.environment_root_browse.clicked.connect(self._browse_environment_root)
        self.auto_start_check = QCheckBox()
        self.auto_start_check.setChecked(settings.auto_start_stack)
        self.auto_hosts_check = QCheckBox()
        self.auto_hosts_check.setChecked(settings.auto_update_hosts)
        self.simulated_process_check = QCheckBox()
        self.simulated_process_check.setChecked(settings.enable_simulated_processes)
        self.nav_list = QListWidget()
        self.nav_list.setFixedWidth(200)
        self.nav_list.addItems(["General", "Apache", "PHP", "Database"])
        self.pages = QStackedWidget()
        self.pages.addWidget(self._build_general_page())
        self.pages.addWidget(self._build_apache_page())
        self.pages.addWidget(self._build_php_page())
        self.pages.addWidget(self._build_database_page())
        self.nav_list.setCurrentRow(0)
        self.nav_list.currentRowChanged.connect(self.pages.setCurrentIndex)

        body = QHBoxLayout()
        body.setContentsMargins(0, 0, 0, 0)
        body.setSpacing(16)
        body.addWidget(self.nav_list)
        body.addWidget(self.pages, 1)

        layout = QVBoxLayout(self)
        layout.addLayout(body)
        buttons = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

    def _page_container(self, title: str, subtitle: str) -> tuple[QWidget, QVBoxLayout]:
        page = QWidget()
        layout = QVBoxLayout(page)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(10)
        title_label = QLabel(f"<b>{title}</b>")
        subtitle_label = QLabel(subtitle)
        subtitle_label.setWordWrap(True)
        layout.addWidget(title_label)
        layout.addWidget(subtitle_label)
        return page, layout

    def _card(self, section_title: str, form_rows: list[tuple[str, QWidget]]) -> QWidget:
        card = QFrame()
        card_layout = QVBoxLayout(card)
        card_layout.setContentsMargins(0, 0, 0, 0)
        card_layout.setSpacing(6)
        section_label = QLabel(f"<b>{section_title}</b>")
        card_layout.addWidget(section_label)
        form = QFormLayout()
        form.setContentsMargins(0, 0, 0, 0)
        form.setSpacing(10)
        for label, widget in form_rows:
            form.addRow(label, widget)
        card_layout.addLayout(form)
        return card

    def _build_general_page(self) -> QWidget:
        page, layout = self._page_container("General", "Core application behavior and runtime layout.")
        environment_row = QWidget()
        environment_row_layout = QHBoxLayout(environment_row)
        environment_row_layout.setContentsMargins(0, 0, 0, 0)
        environment_row_layout.addWidget(self.environment_root_edit)
        environment_row_layout.addWidget(self.environment_root_browse)
        layout.addWidget(
            self._card(
                "App",
                [
                    ("Environment Root", environment_row),
                    ("Auto Start Stack", self.auto_start_check),
                    ("Auto Hosts Updates", self.auto_hosts_check),
                    ("Simulated Processes", self.simulated_process_check),
                ],
            )
        )
        layout.addStretch(1)
        return page

    def _build_apache_page(self) -> QWidget:
        page, layout = self._page_container("Apache", "Configure the bundled web server and its listening behavior.")
        layout.addWidget(
            self._card(
                "Server",
                [
                    ("Listen Port", self.apache_port_edit),
                ],
            )
        )
        layout.addStretch(1)
        return page

    def _build_php_page(self) -> QWidget:
        page, layout = self._page_container("PHP", "Choose the default bundled PHP runtime for new sites.")
        layout.addWidget(
            self._card(
                "Runtime",
                [
                    ("Default PHP Version", self.default_php_version_edit),
                ],
            )
        )
        layout.addStretch(1)
        return page

    def _build_database_page(self) -> QWidget:
        page, layout = self._page_container("Database", "Set the preferred database engine used for new projects.")
        layout.addWidget(
            self._card(
                "Engine",
                [
                    ("Preferred Engine", self.database_engine_edit),
                    ("Active Runtime Version", self.database_runtime_edit),
                    ("Port", self.database_port_edit),
                ],
            )
        )
        layout.addStretch(1)
        return page

    def _browse_environment_root(self) -> None:
        path = QFileDialog.getExistingDirectory(self, "Choose Environment Root")
        if path:
            self.environment_root_edit.setText(path)

    def payload(self) -> dict[str, object]:
        return {
            "default_php_version": self.default_php_version_edit.currentText(),
            "apache_port": self.apache_port_edit.value(),
            "preferred_database_engine": self.database_engine_edit.currentText(),
            "active_database_version": self.database_runtime_edit.currentText(),
            "database_port": self.database_port_edit.value(),
            "environment_root": self.environment_root_edit.text(),
            "auto_start_stack": self.auto_start_check.isChecked(),
            "auto_update_hosts": self.auto_hosts_check.isChecked(),
            "enable_simulated_processes": self.simulated_process_check.isChecked(),
        }


class MainWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.controller = None
        self.current_site_id: str | None = None
        self.current_settings = AppSettings()
        self.available_php_versions: list[str] = []
        self.available_database_runtimes: list[str] = []
        self.stack_feedback_label = QLabel("")
        self.setWindowTitle("Server Engine")
        self.resize(1200, 720)

        toolbar = QToolBar("Stack")
        self.addToolBar(toolbar)
        start_button = QPushButton("Start")
        stop_button = QPushButton("Stop")
        restart_button = QPushButton("Restart")
        settings_button = QPushButton("Settings")
        toolbar.addWidget(start_button)
        toolbar.addWidget(stop_button)
        toolbar.addWidget(restart_button)
        toolbar.addSeparator()
        toolbar.addWidget(settings_button)

        self.stack_label = QLabel("Stack: stopped")
        toolbar.addSeparator()
        toolbar.addWidget(self.stack_label)
        toolbar.addSeparator()
        toolbar.addWidget(self.stack_feedback_label)

        self.site_list = QListWidget()
        self.site_list.currentItemChanged.connect(self._site_selected)
        add_button = QPushButton("Add Site")
        edit_button = QPushButton("Edit Site")
        delete_button = QPushButton("Delete Site")

        sidebar = QWidget()
        sidebar_layout = QVBoxLayout(sidebar)
        sidebar_layout.addWidget(add_button)
        sidebar_layout.addWidget(edit_button)
        sidebar_layout.addWidget(delete_button)
        sidebar_layout.addWidget(self.site_list)

        self.detail_name = QLabel("No site selected")
        self.detail_meta = QLabel("")
        self.detail_notes = QLabel("")
        self.detail_meta.setWordWrap(True)
        self.detail_notes.setWordWrap(True)

        detail_panel = QWidget()
        detail_layout = QVBoxLayout(detail_panel)
        detail_layout.addWidget(self.detail_name)
        detail_layout.addWidget(self.detail_meta)
        detail_layout.addWidget(self.detail_notes)

        self.log_source_combo = QComboBox()
        self.log_source_combo.currentTextChanged.connect(self._log_source_changed)
        self.log_output = QPlainTextEdit()
        self.log_output.setReadOnly(True)
        logs_panel = QWidget()
        logs_layout = QVBoxLayout(logs_panel)
        logs_layout.addWidget(self.log_source_combo)
        logs_layout.addWidget(self.log_output)

        right_split = QSplitter(Qt.Vertical)
        right_split.addWidget(detail_panel)
        right_split.addWidget(logs_panel)

        splitter = QSplitter()
        splitter.addWidget(sidebar)
        splitter.addWidget(right_split)
        splitter.setStretchFactor(1, 1)
        self.setCentralWidget(splitter)

        start_button.clicked.connect(lambda: self._run_guard(self.controller.start_stack))
        stop_button.clicked.connect(lambda: self._run_guard(self.controller.stop_stack))
        restart_button.clicked.connect(lambda: self._run_guard(self.controller.restart_stack))
        settings_button.clicked.connect(self._open_settings_dialog)
        add_button.clicked.connect(self._open_add_dialog)
        edit_button.clicked.connect(self._open_edit_dialog)
        delete_button.clicked.connect(self._delete_site)

    def bind_controller(self, controller: object) -> None:
        self.controller = controller

    def set_sites(self, sites: list[Site]) -> None:
        self.site_list.clear()
        for site in sites:
            item = QListWidgetItem(site.name)
            item.setData(Qt.UserRole, site.id)
            self.site_list.addItem(item)

    def select_site(self, site_id: str) -> None:
        for index in range(self.site_list.count()):
            item = self.site_list.item(index)
            if item.data(Qt.UserRole) == site_id:
                self.site_list.setCurrentItem(item)
                break

    def show_site(self, site: Site | None) -> None:
        self.current_site_id = site.id if site else None
        if site is None:
            self.detail_name.setText("No site selected")
            self.detail_meta.setText("")
            self.detail_notes.setText("")
            return
        self.detail_name.setText(site.name)
        self.detail_meta.setText(
            f"Domain: {site.local_domain}\n"
            f"Path: {site.project_path}\n"
            f"Web Root: {'/' if site.web_root == '.' else site.web_root}\n"
            f"PHP: {site.php_version}\n"
            f"Database: {'enabled' if site.database_enabled else 'disabled'}\n"
            f"Tags: {', '.join(site.tags) if site.tags else '-'}"
        )
        self.detail_notes.setText(site.notes or "")

    def set_stack_status(self, status: StackStatus) -> None:
        details = " | ".join(f"{service.service_id}: {service.state.value}" for service in status.services)
        self.stack_label.setText(f"Stack: {status.overall_state.value}")
        self.stack_feedback_label.setText(details)

    def set_log_sources(self, sources: list[LogSource]) -> None:
        self.log_source_combo.clear()
        for source in sources:
            self.log_source_combo.addItem(source.name, source.id)
        if sources:
            self.log_source_combo.setCurrentIndex(0)

    def set_log_text(self, text: str) -> None:
        self.log_output.setPlainText(text)

    def set_settings(self, settings: AppSettings) -> None:
        self.current_settings = settings

    def set_php_versions(self, versions: list[str]) -> None:
        self.available_php_versions = list(versions)

    def set_database_runtimes(self, runtimes: list[str]) -> None:
        self.available_database_runtimes = list(runtimes)

    def show_stack_feedback(self, message: str, is_error: bool = False) -> None:
        self.stack_feedback_label.setText(message)
        if is_error:
            QMessageBox.warning(self, "Stack Error", message)

    def ask_for_directory(self) -> str | None:
        return QFileDialog.getExistingDirectory(self, "Choose Directory")

    def _site_selected(self, current: QListWidgetItem | None, _: QListWidgetItem | None) -> None:
        if current is None:
            self.show_site(None)
            return
        self.controller.select_site(current.data(Qt.UserRole))

    def _log_source_changed(self, _: str) -> None:
        source_id = self.log_source_combo.currentData()
        if source_id:
            self.controller.refresh_logs(source_id)

    def _open_add_dialog(self) -> None:
        dialog = SiteDialog(self, php_versions=self.available_php_versions)
        if dialog.exec():
            self._run_guard(lambda: self.controller.create_site(dialog.payload()))

    def _open_edit_dialog(self) -> None:
        if not self.current_site_id:
            return
        current_item = self.site_list.currentItem()
        if current_item is None:
            return
        site = self.controller.get_site(self.current_site_id)
        dialog = SiteDialog(self, site=site, php_versions=self.available_php_versions)
        if dialog.exec():
            self._run_guard(lambda: self.controller.update_current_site(self.current_site_id, dialog.payload()))

    def _delete_site(self) -> None:
        if not self.current_site_id:
            return
        confirmation = QMessageBox.question(self, "Delete Site", "Delete selected site?")
        if confirmation == QMessageBox.Yes:
            self._run_guard(lambda: self.controller.delete_site(self.current_site_id))

    def _open_settings_dialog(self) -> None:
        dialog = SettingsDialog(
            self,
            settings=self.current_settings,
            php_versions=self.available_php_versions,
            database_runtimes=self.available_database_runtimes,
        )
        if dialog.exec():
            self._run_guard(lambda: self.controller.save_settings(dialog.payload()))

    def _run_guard(self, callback: object) -> None:
        try:
            callback()
        except Exception as exc:
            QMessageBox.critical(self, "Error", str(exc))
