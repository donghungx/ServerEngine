from ._shared import *
from server_engine.core.models import Proxy


class ProxyPageMixin:
    @Property("QVariantList", notify=dataChanged)
    def proxyItems(self) -> list[dict[str, str]]:
        return [proxy.to_dict() for proxy in self._container.proxy_service.list_proxies()]

    @Slot(str, str, str, str, bool, result=bool)
    def createProxy(self, name: str, domain: str, target: str, notes: str = "", ssl_enabled: bool = False) -> bool:
        try:
            proxy = self._container.proxy_service.create_proxy(name, domain, target, notes, ssl_enabled)
            if proxy.ssl_enabled:
                result = self._container.config_service.ensure_proxy_ssl_certificate(proxy)
                if not result.success:
                    raise ValueError(result.message)
            self.regenerateWebServerConfigs()
            self.reloadWebRoutes()
            self.dataChanged.emit()
            return True
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False

    @Slot(str, str, str, str, str, bool, result=bool)
    def updateProxy(self, proxy_id: str, name: str, domain: str, target: str, notes: str = "", ssl_enabled: bool = False) -> bool:
        try:
            existing = self._container.proxy_service.repository.get(str(proxy_id or "").strip())
            if existing is None:
                raise ValueError("Proxy not found.")
            updated = Proxy(
                id=existing.id,
                name=str(name or "").strip(),
                local_domain=str(domain or "").strip().lower(),
                target=str(target or "").strip(),
                notes=str(notes or "").strip(),
                ssl_enabled=bool(ssl_enabled),
                ssl_enforce_tls=existing.ssl_enforce_tls,
                ssl_allow_http=existing.ssl_allow_http,
                created_at=existing.created_at,
                updated_at=existing.updated_at,
            )
            updated.validate()
            other = self._container.proxy_service.repository.get_by_domain(updated.local_domain)
            if other is not None and other.id != updated.id:
                raise ValueError(f"Local domain already exists: {updated.local_domain}")
            if self._container.site_service.repository.get_by_domain(updated.local_domain) or self._container.node_project_service.repository.get_by_domain(updated.local_domain):
                raise ValueError(f"Local domain already exists: {updated.local_domain}")
            self._container.proxy_service.hosts_gateway.replace_mapping(existing.local_domain, updated.local_domain)
            self._container.proxy_service.repository.save(updated)
            if updated.ssl_enabled:
                result = self._container.config_service.ensure_proxy_ssl_certificate(updated)
                if not result.success:
                    raise ValueError(result.message)
            self.regenerateWebServerConfigs()
            self.reloadWebRoutes()
            self.dataChanged.emit()
            return True
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False

    @Slot(str, result=bool)
    def deleteProxy(self, proxy_id: str) -> bool:
        try:
            result = self._container.proxy_service.delete_proxy(proxy_id)
            if result:
                self.regenerateWebServerConfigs()
                self.reloadWebRoutes()
            self.dataChanged.emit()
            return result
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False
