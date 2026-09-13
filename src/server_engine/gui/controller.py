from __future__ import annotations

from pathlib import Path

from server_engine.bootstrap import AppContainer
from server_engine.core.models import AppSettings, ServiceState, Site, StackStatus


class MainController:
    def __init__(self, window: object, container: AppContainer) -> None:
        self.window = window
        self.container = container

    def initialize(self) -> None:
        self.window.bind_controller(self)
        self.refresh_all()

    def refresh_all(self) -> None:
        sites = self.container.site_service.list_sites()
        self.window.set_sites(sites)
        self.window.set_stack_status(self.container.stack_service.status())
        self.window.set_log_sources(self.container.log_service.list_sources())
        self.window.set_settings(self.container.settings_service.get_settings())
        self.window.set_php_versions(self.container.php_runtime_service.list_versions())
        self.window.set_database_runtimes([runtime.id for runtime in self.container.database_runtime_service.list_runtimes()])
        if sites:
            self.select_site(sites[0].id)
        else:
            self.window.show_site(None)

    def select_site(self, site_id: str) -> None:
        self.window.show_site(self.container.site_service.get_site(site_id))

    def get_site(self, site_id: str) -> Site | None:
        return self.container.site_service.get_site(site_id)

    def create_site(self, payload: dict[str, object]) -> None:
        self.container.site_service.create_site(
            name=str(payload["name"]),
            local_domain=str(payload["local_domain"]),
            project_path=str(payload["project_path"]),
            web_root=str(payload["web_root"]),
            php_version=str(payload["php_version"]),
            database_enabled=bool(payload["database_enabled"]),
            database_name=str(payload["database_name"]).strip() or None,
            database_user=str(payload["database_user"]).strip() or None,
            notes=str(payload["notes"]),
            tags=[tag.strip() for tag in str(payload["tags"]).split(",") if tag.strip()],
        )
        self.refresh_all()

    def update_current_site(self, site_id: str, payload: dict[str, object]) -> None:
        site = self.container.site_service.update_site(
            site_id,
            name=str(payload["name"]),
            local_domain=str(payload["local_domain"]),
            project_path=str(payload["project_path"]),
            web_root=str(payload["web_root"]),
            php_version=str(payload["php_version"]),
            database_enabled=bool(payload["database_enabled"]),
            database_name=str(payload["database_name"]).strip() or None,
            database_user=str(payload["database_user"]).strip() or None,
            notes=str(payload["notes"]),
            tags=[tag.strip() for tag in str(payload["tags"]).split(",") if tag.strip()],
        )
        self.refresh_all()
        self.window.select_site(site.id)

    def delete_site(self, site_id: str) -> None:
        self.container.site_service.delete_site(site_id)
        self.refresh_all()

    def start_stack(self) -> None:
        self.container.stack_service.start_all()
        self._apply_stack_status(self.container.stack_service.status(), action="start")

    def stop_stack(self) -> None:
        self.container.stack_service.stop_all()
        self._apply_stack_status(self.container.stack_service.status(), action="stop")

    def restart_stack(self) -> None:
        self.container.stack_service.restart_all()
        self._apply_stack_status(self.container.stack_service.status(), action="restart")

    def refresh_logs(self, source_id: str) -> None:
        self.window.set_log_text(self.container.log_service.read_tail(source_id))

    def save_settings(self, payload: dict[str, object]) -> None:
        current = self.container.settings_service.get_settings()
        settings = AppSettings(
            app_name=current.app_name,
            default_php_version=str(payload["default_php_version"]),
            default_server_type=current.default_server_type,
            active_web_server=current.active_web_server,
            apache_port=int(payload["apache_port"]),
            preferred_database_engine=str(payload["preferred_database_engine"]),
            active_database_version=str(payload["active_database_version"]).strip() or None,
            database_port=int(payload["database_port"]),
            database_root_password=current.database_root_password,
            database_runtime_passwords=current.database_runtime_passwords,
            active_redis_version=current.active_redis_version,
            redis_port=current.redis_port,
            redis_password=current.redis_password,
            redis_runtime_passwords=current.redis_runtime_passwords,
            bottom_terminal_panel_height=current.bottom_terminal_panel_height,
            auto_start_stack=bool(payload["auto_start_stack"]),
            auto_update_hosts=bool(payload["auto_update_hosts"]),
            environment_root=str(payload["environment_root"]).strip() or current.environment_root,
            enable_simulated_processes=bool(payload["enable_simulated_processes"]),
        )
        self.container.settings_service.save_settings(settings)
        self.container.database_service.generate_config()
        self.window.set_settings(settings)
        self.window.show_stack_feedback("Settings saved. Restart Apache to apply port or runtime changes.")

    def choose_project_path(self) -> str | None:
        return self.window.ask_for_directory()

    def _apply_stack_status(self, status: StackStatus, action: str) -> None:
        self.window.set_stack_status(status)
        messages = [service.message for service in status.services if service.message]
        errors = [service.message for service in status.services if service.state == ServiceState.ERROR]
        if errors:
            self.window.show_stack_feedback(f"{action.title()} failed: {' | '.join(errors)}", is_error=True)
            return
        if messages:
            self.window.show_stack_feedback(f"{action.title()} result: {' | '.join(messages)}")
