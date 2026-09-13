from __future__ import annotations

import platform
import shutil
from pathlib import Path

from server_engine.core.models import FrameworkPreset, ServerType, Site, normalize_domains, normalize_web_root
from server_engine.infrastructure.hosts import HostsGateway
from server_engine.infrastructure.repositories.site_repository import SiteRepository
from server_engine.services.config_service import ConfigService
from server_engine.services.php_runtime_service import PhpRuntimeService
from server_engine.services.settings_service import SettingsService


def _move_project_to_trash(path: Path) -> None:
    if not path.exists():
        return
    system = platform.system()
    if system == "Darwin":
        trash = Path.home() / ".Trash"
    elif system == "Windows":
        trash = Path.home() / "AppData" / "Local" / "Temp" / "ServerEngineTrash"
    else:
        trash = Path.home() / ".local" / "share" / "Trash" / "files"
    trash.mkdir(parents=True, exist_ok=True)
    dest = trash / path.name
    if dest.exists():
        counter = 1
        while dest.exists():
            dest = trash / f"{path.name}_{counter}"
            counter += 1
    shutil.move(str(path), str(dest))


class SiteService:
    def __init__(
        self,
        repository: SiteRepository,
        config_service: ConfigService,
        php_runtime_service: PhpRuntimeService,
        hosts_gateway: HostsGateway,
        settings_service: SettingsService,
    ) -> None:
        self.repository = repository
        self.config_service = config_service
        self.php_runtime_service = php_runtime_service
        self.hosts_gateway = hosts_gateway
        self.settings_service = settings_service

    def list_sites(self) -> list[Site]:
        return self.repository.list_all()

    def get_site(self, site_id: str) -> Site | None:
        return self.repository.get(site_id)

    def create_site(
        self,
        name: str,
        local_domain: str,
        project_path: str,
        web_root: str = "public",
        php_version: str = "8.3",
        framework_preset: FrameworkPreset = FrameworkPreset.GENERIC_PHP,
        server_type: ServerType = ServerType.APACHE,
        ssl_enabled: bool = False,
        ssl_enforce_tls: bool = False,
        ssl_allow_http: bool = True,
        database_enabled: bool = False,
        database_name: str | None = None,
        database_user: str | None = None,
        notes: str = "",
        tags: list[str] | None = None,
        generate_configs: bool = True,
    ) -> Site:
        if self.repository.get_by_domain(local_domain.strip().lower()):
            raise ValueError(f"Local domain already exists: {local_domain}")
        runtime = self.php_runtime_service.require_runtime(php_version)
        site = Site.create(
            name=name,
            local_domain=local_domain,
            project_path=project_path,
            web_root=web_root,
            php_version=runtime.version,
            framework_preset=framework_preset,
            server_type=server_type,
            ssl_enabled=ssl_enabled,
            ssl_enforce_tls=ssl_enforce_tls,
            ssl_allow_http=ssl_allow_http,
            database_enabled=database_enabled,
            database_name=database_name,
            database_user=database_user,
            notes=notes,
            tags=tags,
        )
        if self.settings_service.get_settings().auto_update_hosts:
            for domain in site.all_domains():
                self.hosts_gateway.ensure_mapping(domain)
        self.repository.save(site)
        if generate_configs:
            self.config_service.write_site_configs(site, apache_port=self.settings_service.get_settings().apache_port)
        return site

    def update_site(self, site_id: str, **changes: object) -> Site:
        site = self.repository.get(site_id)
        if site is None:
            raise ValueError(f"Site not found: {site_id}")
        requested_primary = str(changes.get("local_domain", site.local_domain))
        requested_aliases = changes.get("domain_aliases", site.domain_aliases)
        new_domain, new_aliases = normalize_domains(requested_primary, list(requested_aliases) if isinstance(requested_aliases, list) else site.domain_aliases)
        self._ensure_domains_available([new_domain, *new_aliases], exclude_site_id=site_id)
        old_domains = set(site.all_domains())
        if "php_version" in changes:
            runtime = self.php_runtime_service.require_runtime(str(changes["php_version"]))
            changes["php_version"] = runtime.version
        if "web_root" in changes:
            changes["web_root"] = normalize_web_root(str(changes["web_root"]))
        for field_name, value in changes.items():
            if hasattr(site, field_name):
                setattr(site, field_name, value)
        site.local_domain, site.domain_aliases = normalize_domains(site.local_domain, site.domain_aliases)
        site.name = site.name.strip()
        site.touch()
        site.validate()
        if self.settings_service.get_settings().auto_update_hosts:
            new_domains = set(site.all_domains())
            for removed in sorted(old_domains - new_domains):
                self.hosts_gateway.remove_mapping(removed)
            for added in sorted(new_domains - old_domains):
                self.hosts_gateway.ensure_mapping(added)
        self.repository.save(site)
        self.config_service.write_site_configs(site, apache_port=self.settings_service.get_settings().apache_port)
        return site

    def delete_site(self, site_id: str, move_to_trash: bool = False) -> bool:
        site = self.repository.get(site_id)
        if site is None:
            return False
        if self.settings_service.get_settings().auto_update_hosts:
            for domain in site.all_domains():
                self.hosts_gateway.remove_mapping(domain)
        if move_to_trash:
            _move_project_to_trash(Path(site.project_path))
        return self.repository.delete(site_id)

    def _ensure_domains_available(self, domains: list[str], exclude_site_id: str | None = None) -> None:
        normalized = [domain.strip().lower() for domain in domains if domain.strip()]
        seen: set[str] = set()
        for domain in normalized:
            if domain in seen:
                raise ValueError(f"Local domain already exists in this site: {domain}")
            seen.add(domain)
            existing = self.repository.get_by_domain(domain)
            if existing and existing.id != exclude_site_id:
                raise ValueError(f"Local domain already exists: {domain}")
