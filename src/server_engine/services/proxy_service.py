from __future__ import annotations

from server_engine.core.models import Proxy
from server_engine.infrastructure.hosts import HostsGateway
from server_engine.infrastructure.repositories.proxy_repository import ProxyRepository
from server_engine.infrastructure.repositories.site_repository import SiteRepository
from server_engine.infrastructure.repositories.node_project_repository import NodeProjectRepository


class ProxyService:
    def __init__(self, repository: ProxyRepository, site_repository: SiteRepository, node_repository: NodeProjectRepository, hosts_gateway: HostsGateway) -> None:
        self.repository = repository
        self.site_repository = site_repository
        self.node_repository = node_repository
        self.hosts_gateway = hosts_gateway

    def list_proxies(self) -> list[Proxy]:
        return self.repository.list_all()

    def create_proxy(self, name: str, local_domain: str, target: str, notes: str = "", ssl_enabled: bool = False) -> Proxy:
        domain = local_domain.strip().lower()
        if self.site_repository.get_by_domain(domain) or self.node_repository.get_by_domain(domain) or self.repository.get_by_domain(domain):
            raise ValueError(f"Local domain already exists: {domain}")
        proxy = Proxy.create(name, domain, target, notes)
        proxy.ssl_enabled = bool(ssl_enabled)
        self.hosts_gateway.ensure_mapping(domain)
        return self.repository.save(proxy)

    def delete_proxy(self, proxy_id: str) -> bool:
        proxy = self.repository.get(proxy_id)
        if proxy is None:
            return False
        self.hosts_gateway.remove_mapping(proxy.local_domain)
        return self.repository.delete(proxy_id)
