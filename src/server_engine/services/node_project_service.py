from __future__ import annotations

from server_engine.core.models import NodeProject
from server_engine.infrastructure.hosts import HostsGateway
from server_engine.infrastructure.repositories.node_project_repository import NodeProjectRepository
from server_engine.infrastructure.repositories.site_repository import SiteRepository
from server_engine.services.settings_service import SettingsService


class NodeProjectService:
    def __init__(
        self,
        repository: NodeProjectRepository,
        site_repository: SiteRepository,
        hosts_gateway: HostsGateway,
        settings_service: SettingsService,
    ) -> None:
        self.repository = repository
        self.site_repository = site_repository
        self.hosts_gateway = hosts_gateway
        self.settings_service = settings_service

    def list_projects(self) -> list[NodeProject]:
        return self.repository.list_all()

    def create_project(
        self,
        name: str,
        local_domain: str,
        project_path: str,
        document_root: str,
        node_version: str,
        run_script_name: str,
        run_script_command: str,
        port: int,
        notes: str = "",
        ssl_enabled: bool = False,
        ssl_enforce_tls: bool = False,
        ssl_allow_http: bool = True,
    ) -> NodeProject:
        domain = local_domain.strip().lower()
        self._ensure_domain_available(domain, None)
        project = NodeProject.create(
            name=name,
            local_domain=domain,
            project_path=project_path,
            document_root=document_root,
            node_version=node_version,
            run_script_name=run_script_name,
            run_script_command=run_script_command,
            port=port,
            notes=notes,
            ssl_enabled=ssl_enabled,
            ssl_enforce_tls=ssl_enforce_tls,
            ssl_allow_http=ssl_allow_http,
        )
        if self.settings_service.get_settings().auto_update_hosts:
            self.hosts_gateway.ensure_mapping(project.local_domain)
        return self.repository.save(project)

    def update_project(self, project_id: str, **changes: object) -> NodeProject:
        project = self.repository.get(project_id)
        if project is None:
            raise ValueError(f"Node project not found: {project_id}")
        next_domain = str(changes.get("local_domain", project.local_domain)).strip().lower()
        self._ensure_domain_available(next_domain, project_id)
        old_domain = project.local_domain
        for field_name, value in changes.items():
            if hasattr(project, field_name):
                setattr(project, field_name, value)
        project.local_domain = next_domain
        project.touch()
        project.validate()
        if self.settings_service.get_settings().auto_update_hosts and old_domain != project.local_domain:
            self.hosts_gateway.remove_mapping(old_domain)
            self.hosts_gateway.ensure_mapping(project.local_domain)
        return self.repository.save(project)

    def delete_project(self, project_id: str) -> bool:
        project = self.repository.get(project_id)
        if project is None:
            return False
        if self.settings_service.get_settings().auto_update_hosts:
            self.hosts_gateway.remove_mapping(project.local_domain)
        return self.repository.delete(project_id)

    def _ensure_domain_available(self, domain: str, exclude_project_id: str | None) -> None:
        existing_site = self.site_repository.get_by_domain(domain)
        if existing_site is not None:
            raise ValueError(f"Local domain already exists: {domain}")
        existing_project = self.repository.get_by_domain(domain)
        if existing_project is not None and existing_project.id != exclude_project_id:
            raise ValueError(f"Local domain already exists: {domain}")
