import logging
from collections import deque

from ._shared import *


LOGGER = logging.getLogger("server_engine.status")
from .navigation_page import NavigationPageMixin
from .dashboard_overview import DashboardOverviewMixin
from .home_stack_services import HomeStackServicesMixin
from .website_page import WebsitePageMixin
from .php_page import PhpPageMixin
from .database_page import DatabasePageMixin
from .postgresql_page import PostgresqlPageMixin
from .mongodb_page import MongodbPageMixin
from .redis_memcached_mail_page import RedisMemcachedMailPageMixin
from .log_sources import LogSourcesMixin
from .node_projects_page import NodeProjectsPageMixin
from .app_settings import AppSettingsMixin
from .runtime_manager import RuntimeManagerMixin
from .system_helpers import SystemHelpersMixin
from .proxy_page import ProxyPageMixin


class DashboardBridge(NavigationPageMixin, DashboardOverviewMixin, HomeStackServicesMixin, WebsitePageMixin, PhpPageMixin, DatabasePageMixin, PostgresqlPageMixin, MongodbPageMixin, RedisMemcachedMailPageMixin, LogSourcesMixin, NodeProjectsPageMixin, ProxyPageMixin, AppSettingsMixin, RuntimeManagerMixin, SystemHelpersMixin, NavigationBridgeMixin, QObject):
    def __init__(self, container: AppContainer) -> None:
        super().__init__()
        self._container = container
        self._current_page = "home"
        self._navigation_items = [
            {"id": "home", "label": "Home", "badge": "", "icon": "house"},
            {"id": "website", "label": "Website", "badge": "", "icon": "globe"},
            {"id": "php", "label": "PHP", "badge": "", "icon": "code-xml"},
            {"id": "database", "label": "Database", "badge": "", "icon": "database"},
            {"id": "redis", "label": "Redis", "badge": "", "icon": "server"},
            {"id": "cache", "label": "Memcached", "badge": "", "icon": "box"},
            {"id": "mail", "label": "Mail Server", "badge": "", "icon": "mail"},
        ]

        self._last_operation_message = ""
        self._last_operation_error = False
        self._last_status_bar_log_message = ""
        self._last_status_bar_log_error = False
        self._stack_feedback_message = ""
        self._stack_feedback_error = False
        self._app_settings_message = ""
        self._app_settings_error = False
        self._app_settings_save_thread: QThread | None = None
        self._app_settings_save_worker: AppSettingsSaveWorker | None = None
        self._app_settings_save_busy = False
        self._app_settings_save_current_kind = ""
        self._app_settings_save_pending: tuple[str, dict[str, object]] | None = None
        self._database_runtime_message = ""
        self._database_runtime_error = False
        self._database_runtime_log = ""
        self._database_service_state_cache = "Stopped"
        self._postgresql_runtime_message = ""
        self._postgresql_runtime_error = False
        self._postgresql_runtime_log = ""
        self._postgresql_service_state_cache = "Stopped"
        self._postgresql_action_busy = False
        self._postgresql_backup_message = ""
        self._postgresql_backup_error = False
        self._postgresql_backup_progress = 0
        self._postgresql_backup_progress_label = ""
        self._postgresql_backup_busy = False
        self._postgresql_import_message = ""
        self._postgresql_import_error = False
        self._postgresql_import_progress = 0
        self._postgresql_import_progress_label = ""
        self._postgresql_import_selected_path = ""
        self._postgresql_import_details = ""
        self._postgresql_import_busy = False
        self._adminer_busy = False
        self._mongodb_runtime_message = ""
        self._mongodb_runtime_error = False
        self._mongodb_runtime_log = ""
        self._mongodb_service_state_cache = "Stopped"
        self._mongodb_action_busy = False
        self._mongodb_items: list[dict[str, str]] = []
        self._mongodb_items_loading = False
        self._mongodb_items_thread: QThread | None = None
        self._mongodb_items_worker: MongodbItemsWorker | None = None
        self._mongodb_action_thread: QThread | None = None
        self._mongodb_action_worker: MongodbActionWorker | None = None
        self._mongodb_backup_message = ""
        self._mongodb_backup_error = False
        self._mongodb_backup_progress = 0
        self._mongodb_backup_progress_label = ""
        self._mongodb_backup_busy = False
        self._mongodb_import_message = ""
        self._mongodb_import_error = False
        self._mongodb_import_progress = 0
        self._mongodb_import_progress_label = ""
        self._mongodb_import_selected_path = ""
        self._mongodb_import_details = ""
        self._mongodb_import_busy = False
        self._database_backup_message = ""
        self._database_backup_error = False
        self._database_backup_busy = False
        self._database_backup_progress = 0
        self._database_backup_progress_label = ""
        self._database_backup_job_title = ""
        self._database_backup_thread: QThread | None = None
        self._database_backup_worker: DatabaseBackupWorker | None = None
        self._database_backup_items: list[dict[str, object]] = []
        self._database_backup_items_loading = False
        self._database_backup_items_thread: QThread | None = None
        self._database_backup_items_worker: DatabaseBackupItemsWorker | None = None
        self._database_backup_items_database_name = ""
        self._database_backup_items_pending_database_name = ""
        self._database_backup_items_reload_database_name = ""
        self._database_job_queue = deque()
        self._database_import_message = ""
        self._database_import_error = False
        self._database_import_busy = False
        self._database_import_progress = 0
        self._database_import_progress_label = ""
        self._database_import_job_title = ""
        self._database_import_selected_path = ""
        self._database_import_details = ""
        self._database_import_thread: QThread | None = None
        self._database_import_worker: DatabaseBackupWorker | None = None
        self._database_sizes_map: dict[str, int] = {}
        self._database_sizes_loading = False
        self._database_sizes_thread: QThread | None = None
        self._database_sizes_worker: DatabaseSizeWorker | None = None
        self._home_service_threads: dict[str, QThread] = {}
        self._home_service_workers: dict[str, HomeServiceWorker] = {}
        self._home_service_targets: dict[str, bool] = {}
        self._global_action_busy = False
        self._global_action_mode = ""
        self._global_action_thread: QThread | None = None
        self._global_action_worker: GlobalStackWorker | None = None
        self._mailpit_action_thread: QThread | None = None
        self._mailpit_action_worker: MailpitActionWorker | None = None
        self._redis_restart_thread: QThread | None = None
        self._redis_restart_worker: RedisRestartWorker | None = None
        self._memcached_restart_thread: QThread | None = None
        self._memcached_restart_worker: MemcachedRestartWorker | None = None
        self._phpmyadmin_busy = False
        self._phpmyadmin_thread: QThread | None = None
        self._phpmyadmin_worker: PhpMyAdminWorker | None = None
        self._database_restart_thread: QThread | None = None
        self._database_restart_worker: DatabaseRestartWorker | None = None
        self._web_reload_thread: QThread | None = None
        self._web_reload_worker: WebRouteReloadWorker | None = None
        self._web_restart_thread: QThread | None = None
        self._web_restart_worker: WebRestartWorker | None = None
        self._php_runtime_service_action_thread: QThread | None = None
        self._php_runtime_service_action_worker: PhpRuntimeServiceActionWorker | None = None
        self._redis_runtime_message = ""
        self._redis_runtime_error = False
        self._redis_runtime_log = ""
        self._redis_service_state_cache = "Stopped"
        self._memcached_runtime_message = ""
        self._memcached_runtime_error = False
        self._memcached_runtime_log = ""
        self._memcached_service_state_cache = "Stopped"
        self._mailpit_runtime_message = ""
        self._mailpit_runtime_error = False
        self._mailpit_runtime_log = ""
        self._mailpit_service_state_cache = "Stopped"
        self._mailpit_mailbox_live_updates = False
        self._mailpit_mailbox_timer = QTimer(self)
        self._mailpit_mailbox_timer.setInterval(5000)
        self._mailpit_mailbox_timer.timeout.connect(self._emit_mailpit_mailbox_changed)
        self._redis_inspector_live_updates = False
        self._redis_inspector_timer = QTimer(self)
        self._redis_inspector_timer.setInterval(3000)
        self._redis_inspector_timer.timeout.connect(self._refresh_live_redis_inspector)
        self._redis_inspector_filter = ""
        self._redis_inspector_keys = []
        self._redis_inspector_namespaces = []
        self._redis_inspector_selected_key = ""
        self._redis_inspector_selected_value = ""
        self._redis_inspector_selected_summary = ""
        self._node_project_runtime_message = ""
        self._node_project_runtime_error = False
        self._node_project_runtime_action_busy = False
        self._node_project_modules_busy = False
        self._node_project_modules_loaded = False
        self._node_project_modules_has_node_modules = False
        self._node_project_modules_project_id = ""
        self._node_project_modules_items: list[dict[str, str]] = []
        self._node_project_modules_message = ""
        self._node_project_modules_error = False
        self._node_project_modules_thread: QThread | None = None
        self._node_project_modules_worker: NodeProjectModulesWorker | None = None
        self._node_project_modules_install_thread: QThread | None = None
        self._node_project_modules_install_worker: NodeProjectInstallDependenciesWorker | None = None
        self._php_runtime_service_message = ""
        self._php_runtime_service_error = False
        self._php_runtime_service_action_busy = False
        self._node_project_runtime_thread: QThread | None = None
        self._node_project_runtime_worker: NodeProjectRuntimeActionWorker | None = None
        self._node_project_save_busy = False
        self._node_project_save_thread: QThread | None = None
        self._node_project_save_worker: NodeProjectSaveWorker | None = None
        self._site_creation_busy = False
        self._site_creation_thread: QThread | None = None
        self._site_creation_worker: SiteCreationWorker | None = None
        self._site_creation_cancel_requested = False
        self._stack_action_busy = False
        self._database_action_busy = False
        self._redis_action_busy = False
        self._memcached_action_busy = False
        self._mailpit_action_busy = False
        self._system_notifier: Callable[[str, bool], None] | None = None
        self._node_install_busy = False
        self._runtime_manager_busy = False
        self._runtime_install_busy = False
        self._runtime_install_progress = 0
        self._runtime_install_status = ""
        self._runtime_install_thread: QThread | None = None
        self._runtime_install_worker: RuntimeInstallWorker | None = None
        self._runtime_install_item_service = ""
        self._runtime_install_item_id = ""
        self._runtime_install_item_version = ""
        self._runtime_manifest_thread: QThread | None = None
        self._runtime_manifest_worker: RuntimeManifestWorker | None = None
        self._runtime_server_items_model: list[dict[str, object]] = []
        self._runtime_server_items_service = ""
        self._optional_database_runtime_download_cache: dict[str, bool] = {}
        self._required_runtime_bootstrap_open = False
        self._required_runtime_bootstrap_busy = False
        self._required_runtime_bootstrap_progress = 0
        self._required_runtime_bootstrap_status = ""
        self._required_runtime_bootstrap_error = False
        self._required_runtime_bootstrap_missing: list[str] = []
        self._required_runtime_bootstrap_items: list[dict[str, str]] = []
        self._required_runtime_bootstrap_thread: QThread | None = None
        self._required_runtime_bootstrap_worker: RequiredRuntimeBootstrapWorker | None = None
        self._node_install_progress = 0
        self._node_install_log = ""
        self._node_install_process: QProcess | None = None
        self._php_extension_action_busy = False
        self._php_extension_action_target = ""
        self._phpinfo_thread: QThread | None = None
        self._phpinfo_worker: PhpInfoWorker | None = None
        self._phpinfo_pending_version = ""
        self._service_port_conflict_open = False
        self._service_port_conflict_port = 0
        self._service_port_conflict_message = ""
        self._service_port_conflict_service_id = ""
        self._service_port_conflict_service_label = ""
        self._system_tray_visible = True
        self._system_tray_visibility_handler: Callable[[bool], None] | None = None
        self._refresh_optional_database_runtime_cache()
        self._refresh_home_service_items_cache()
        self._hero_metrics = [
            {
                "id": "load",
                "title": "Load average",
                "value": "0.0%",
                "percent": 0.0,
                "detail": "0.00 / 0.00 / 0.00",
                "caption": "Normalized by CPU cores",
            },
            {
                "id": "cpu",
                "title": f"{max(os.cpu_count() or 1, 1)} Core(s)",
                "value": "0.0%",
                "percent": 0.0,
                "detail": "Current CPU usage",
                "caption": "Machine snapshot",
            },
            {
                "id": "ram",
                "title": "RAM usage",
                "value": "0.0%",
                "percent": 0.0,
                "detail": "0 / 0 MB",
                "caption": "Memory footprint",
            },
        ]
        self._disk_metric = {
            "title": "Disk",
            "mount": "/",
            "value": "0%",
            "percent": 0.0,
            "detail": "0.00 / 0.00 GB",
            "free": "0.00 GB free",
            "total": "0.00 GB total",
        }
        self._metrics_thread = QThread(self)
        self._metrics_worker = MetricsWorker()
        self._metrics_worker.moveToThread(self._metrics_thread)
        self._metrics_worker.metricsReady.connect(self._apply_metrics)
        self._metrics_thread.finished.connect(self._metrics_worker.deleteLater)
        self._metrics_thread.start()
        self._metrics_timer = QTimer(self)
        self._metrics_timer.setInterval(5000)
        self._metrics_timer.timeout.connect(self.refreshMetrics)
        self._metrics_timer.start()
        self._shutting_down = False
        app = QCoreApplication.instance()
        if app is not None:
            app.aboutToQuit.connect(self._shutdown_metrics_thread)
        self.refreshMetrics()
        self._refresh_optional_database_runtime_cache()

    @Slot(str, bool)
    def logStatusBarMessage(self, message: str, is_error: bool = False) -> None:
        text = str(message or "").strip()
        if not text:
            return
        if text == self._last_status_bar_log_message and bool(is_error) == self._last_status_bar_log_error:
            return
        self._last_status_bar_log_message = text
        self._last_status_bar_log_error = bool(is_error)
        if is_error:
            LOGGER.error(text)
        else:
            LOGGER.info(text)

    def _global_database_job_busy(self) -> bool:
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
        )

    def _enqueue_database_job(self, kind: str, value: str, title: str) -> bool:
        self._database_job_queue.append(
            {
                "kind": kind,
                "value": value,
                "title": title,
            }
        )
        self.actionStateChanged.emit()
        if self._global_database_job_busy():
            self._database_runtime_message = f"Queued {title.lower()}."
            self._database_runtime_error = False
            self.databaseRuntimeFeedbackChanged.emit()
            return True
        self._start_next_database_job()
        return True

    def _start_next_database_job(self) -> None:
        if self._global_database_job_busy():
            return
        if not self._database_job_queue:
            return
        job = self._database_job_queue.popleft()
        self.actionStateChanged.emit()
        kind = str(job.get("kind", ""))
        value = str(job.get("value", ""))
        title = str(job.get("title", ""))
        if kind in {"backup", "database-backup"}:
            cleaned = value.strip()
            self._database_backup_message = ""
            self._database_backup_error = False
            self._database_backup_progress = 0
            self._database_backup_progress_label = "Starting backup..."
            self._database_backup_job_title = title or f"Backing up {cleaned or 'database'}"
            self._start_database_backup_job("backup", value)
            return
        if kind in {"restore", "database-restore"}:
            cleaned_path = value.strip()
            self._database_backup_message = ""
            self._database_backup_error = False
            self._database_backup_progress = 0
            self._database_backup_progress_label = "Starting restore..."
            self._database_backup_job_title = title or "Restoring database"
            self._start_database_backup_job("restore", value)
            return
        if kind in {"import", "database-import"}:
            parts = value.split("\n", 2)
            database_name = parts[0]
            import_path = parts[1] if len(parts) > 1 else ""
            clear_existing = len(parts) > 2 and parts[2].strip() == "1"
            self._database_import_message = ""
            self._database_import_error = False
            self._database_import_progress = 0
            self._database_import_job_title = title or f"Importing SQL into {database_name.strip() or 'database'}"
            self._database_import_progress_label = self._database_import_job_title
            self._database_import_details = "Preparing import for " + database_name.strip() + "\nSource: " + import_path.strip()
            self._database_import_busy = True
            self.actionStateChanged.emit()
            self.databaseRuntimeFeedbackChanged.emit()
            self._start_database_import_job(database_name, import_path, clear_existing)
            return
        if kind == "postgresql-backup":
            try:
                self._run_postgresql_backup_job(value)
            finally:
                self._start_next_database_job()
            return
        if kind == "postgresql-restore":
            try:
                self._run_postgresql_restore_job(value)
            finally:
                self._start_next_database_job()
            return
        if kind == "postgresql-import":
            try:
                database_name, import_path = value.split("\n", 1)
                self._run_postgresql_import_job(database_name, import_path)
            finally:
                self._start_next_database_job()
            return
        if kind == "mongodb-backup":
            try:
                self._run_mongodb_backup_job(value)
            finally:
                self._start_next_database_job()
            return
        if kind == "mongodb-restore":
            try:
                self._run_mongodb_restore_job(value)
            finally:
                self._start_next_database_job()
            return
        if kind == "mongodb-import":
            try:
                database_name, import_path = value.split("\n", 1)
                self._run_mongodb_import_job(database_name, import_path)
            finally:
                self._start_next_database_job()
            return
        self._start_next_database_job()
