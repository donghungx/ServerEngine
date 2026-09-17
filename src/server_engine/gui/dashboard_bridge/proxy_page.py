from ._shared import *
from server_engine.core.models import Proxy


class ProxyCertificateWorker(QObject):
    completed = Signal(bool, str)

    def __init__(self, container, proxy_id: str) -> None:
        super().__init__()
        self._container = container
        self._proxy_id = proxy_id

    @Slot()
    def run(self) -> None:
        try:
            proxy = self._container.proxy_service.repository.get(self._proxy_id)
            if proxy is None:
                raise ValueError("Proxy project not found.")
            result = self._container.config_service.ensure_proxy_ssl_certificate(proxy)
            if not result.success:
                raise ValueError(result.message)
            self.completed.emit(True, f"SSL certificate ready for {proxy.local_domain}")
        except Exception as exc:
            self.completed.emit(False, str(exc))


class ProxyPageMixin:
    @Property(bool, notify=operationFeedbackChanged)
    def proxySslCertificateBusy(self) -> bool:
        return bool(getattr(self, "_proxy_ssl_certificate_busy", False))

    @Property("QVariantList", notify=dataChanged)
    def proxyItems(self) -> list[dict[str, str]]:
        items = []
        for proxy in self._container.proxy_service.list_proxies():
            item = proxy.to_dict()
            cert_path, key_path = self._container.config_service.proxy_ssl_paths(proxy)
            item["ssl_certificate_path"] = str(cert_path)
            item["ssl_key_path"] = str(key_path)
            items.append(item)
        return items

    @Slot(str, str, str, str, bool, bool, bool, result=bool)
    def createProxy(self, name: str, domain: str, target: str, notes: str = "", ssl_enabled: bool = False, ssl_enforce_tls: bool = False, ssl_allow_http: bool = True) -> bool:
        try:
            proxy = self._container.proxy_service.create_proxy(name, domain, target, notes, ssl_enabled, ssl_enforce_tls, ssl_allow_http)
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

    @Slot(str, str, str, str, str, bool, bool, bool, result=bool)
    def updateProxy(self, proxy_id: str, name: str, domain: str, target: str, notes: str = "", ssl_enabled: bool = False, ssl_enforce_tls: bool = False, ssl_allow_http: bool = True) -> bool:
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
                ssl_enforce_tls=bool(ssl_enforce_tls) and bool(ssl_enabled),
                ssl_allow_http=bool(ssl_allow_http) and not bool(ssl_enforce_tls),
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

    @Slot(str, result=bool)
    def ensureProxySslCertificate(self, proxy_id: str) -> bool:
        """Create a proxy certificate in a worker so the QML window stays responsive."""
        if self.proxySslCertificateBusy:
            return False
        proxy_id = str(proxy_id or "").strip()
        if not proxy_id:
            self._last_operation_message = "Save the proxy project before creating its certificate."
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False
        self._proxy_ssl_certificate_busy = True
        self._last_operation_message = "Creating SSL certificate..."
        self._last_operation_error = False
        self.operationFeedbackChanged.emit()
        thread = QThread(self)
        worker = ProxyCertificateWorker(self._container, proxy_id)
        self._proxy_ssl_certificate_thread = thread
        self._proxy_ssl_certificate_worker = worker
        worker.moveToThread(thread)
        thread.started.connect(worker.run)
        worker.completed.connect(self._finish_proxy_ssl_certificate)
        worker.completed.connect(thread.quit)
        thread.finished.connect(worker.deleteLater)
        thread.finished.connect(thread.deleteLater)
        thread.start()
        return True

    @Slot(bool, str)
    def _finish_proxy_ssl_certificate(self, success: bool, message: str) -> None:
        self._proxy_ssl_certificate_busy = False
        self._last_operation_message = message
        self._last_operation_error = not success
        if not success:
            LOGGER.error("Proxy SSL certificate creation failed: %s", message)
        self.operationFeedbackChanged.emit()
        self.dataChanged.emit()

    @Slot(str, result=bool)
    def regenerateProxySelfSignedCertificate(self, proxy_id: str) -> bool:
        try:
            proxy = self._container.proxy_service.repository.get(str(proxy_id or "").strip())
            if proxy is None:
                raise ValueError("Proxy project not found.")
            cert_path, key_path = self._container.config_service.proxy_ssl_paths(proxy)
            cert_path.unlink(missing_ok=True)
            key_path.unlink(missing_ok=True)
            result = self._container.config_service.ensure_proxy_ssl_certificate(proxy)
            if not result.success:
                raise ValueError(result.message)
            self.regenerateWebServerConfigs()
            self.reloadWebRoutes()
            self._last_operation_message = f"Regenerated SSL certificate for {proxy.local_domain}."
            self._last_operation_error = False
            self.dataChanged.emit()
            self.operationFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            LOGGER.exception("Failed to regenerate proxy SSL certificate for proxy_id=%s", proxy_id)
            self.operationFeedbackChanged.emit()
            return False

    @Slot(str, result=bool)
    def trustProxyCertificate(self, proxy_id: str) -> bool:
        try:
            proxy = self._container.proxy_service.repository.get(str(proxy_id or "").strip())
            if proxy is None:
                raise ValueError("Proxy project not found.")
            cert_path, _ = self._container.config_service.proxy_ssl_paths(proxy)
            if not cert_path.exists():
                raise ValueError("Certificate file does not exist. Generate the certificate first.")
            if sys.platform != "darwin":
                raise ValueError("Certificate trust is only supported on macOS.")
            security_bin = shutil.which("security") or "/usr/bin/security"
            login_keychain = str(Path.home() / "Library" / "Keychains" / "login.keychain-db")
            completed = subprocess.run(
                [security_bin, "add-trusted-cert", "-r", "trustRoot", "-p", "ssl", "-k", login_keychain, str(cert_path)],
                capture_output=True,
                text=True,
            )
            if completed.returncode != 0:
                detail = (completed.stderr or completed.stdout or "Certificate trust failed.").strip()
                raise ValueError(f"{detail} Try adding the certificate to your login keychain manually.")
            self._last_operation_message = f"Trusted SSL certificate for {proxy.local_domain}"
            self._last_operation_error = False
            self.operationFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            LOGGER.exception("Failed to trust proxy SSL certificate for proxy_id=%s", proxy_id)
            self.operationFeedbackChanged.emit()
            return False
