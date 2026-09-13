from __future__ import annotations

import logging
import socket
import subprocess
import time
import re
from pathlib import Path

from server_engine.core.models import RuntimePaths, ServiceDefinition, ServiceKind, ServiceState, ServiceStatus, StackStatus
from server_engine.infrastructure.binary_locator import BinaryLocator
from server_engine.infrastructure.hosts import HostsGateway
from server_engine.infrastructure.process_manager import ProcessManager
from server_engine.services.config_service import ConfigService
from server_engine.services.node_project_service import NodeProjectService
from server_engine.services.proxy_service import ProxyService
from server_engine.services.site_service import SiteService
from server_engine.services.settings_service import SettingsService

LOGGER = logging.getLogger("server_engine.runtime_install")


class StackService:
    def __init__(
        self,
        process_manager: ProcessManager,
        runtime_paths: RuntimePaths,
        binary_locator: BinaryLocator,
        config_service: ConfigService,
        site_service: SiteService,
        node_project_service: NodeProjectService,
        proxy_service: ProxyService,
        settings_service: SettingsService,
        hosts_gateway: HostsGateway,
    ) -> None:
        self.process_manager = process_manager
        self.runtime_paths = runtime_paths
        self.binary_locator = binary_locator
        self.config_service = config_service
        self.site_service = site_service
        self.node_project_service = node_project_service
        self.proxy_service = proxy_service
        self.settings_service = settings_service
        self.hosts_gateway = hosts_gateway

    def definitions(self) -> list[ServiceDefinition]:
        settings = self.settings_service.get_settings()
        if settings.active_web_server == settings.active_web_server.NGINX:
            services: list[ServiceDefinition] = []
            sites = self.site_service.list_sites()
            versions: list[str] = []
            for site in sites:
                if site.php_version not in versions:
                    versions.append(site.php_version)
            phpmyadmin_runtime = self.config_service.phpmyadmin_runtime()
            sanitized_versions: set[str] = set()
            for version in versions:
                runtime = self.binary_locator.php_runtime(version)
                if runtime is None:
                    continue
                if runtime.version not in sanitized_versions:
                    self._sanitize_runtime_ini(runtime)
                    sanitized_versions.add(runtime.version)
                service_id = self._php_fastcgi_service_id(runtime.version)
                default_port = self.config_service.php_fastcgi_port(runtime.version)
                services.append(
                    ServiceDefinition(
                        id=service_id,
                        name=f"PHP {runtime.version} FastCGI",
                        kind=ServiceKind.PHP_FPM,
                        executable_name="php-cgi",
                        default_port=default_port,
                        executable_path=runtime.php_cgi_path,
                        arguments=[
                            "-d",
                            f"extension_dir={self._php_extension_dir(runtime)}",
                            "-d",
                            "cgi.force_redirect=0",
                            "-d",
                            "pcre.jit=0",
                            "-d",
                            "log_errors=1",
                            "-d",
                            f"error_log={self.config_service.php_runtime_log_path(runtime.version)}",
                            "-b",
                            f"127.0.0.1:{default_port}",
                        ],
                        working_directory=str(self.runtime_paths.runtime_dir / "php"),
                        log_path=self._php_service_log_path(runtime.version),
                        log_to_screen=self._php_service_log_to_screen(),
                        environment={
                            "PHPRC": str(runtime.ini_dir),
                            "PHP_INI_SCAN_DIR": "",
                            "REDIRECT_STATUS": "1",
                            "PHP_FCGI_CHILDREN": "1",
                            "PHP_FCGI_MAX_REQUESTS": "500",
                        },
                    )
                )
            if phpmyadmin_runtime is not None:
                if phpmyadmin_runtime.version not in sanitized_versions:
                    self._sanitize_runtime_ini(phpmyadmin_runtime)
                    sanitized_versions.add(phpmyadmin_runtime.version)
                services.append(
                    ServiceDefinition(
                        id="php-cgi-phpmyadmin",
                        name=f"phpMyAdmin PHP {phpmyadmin_runtime.version} FastCGI",
                        kind=ServiceKind.PHP_FPM,
                        executable_name="php-cgi",
                        default_port=self.config_service.phpmyadmin_fastcgi_port(),
                        executable_path=phpmyadmin_runtime.php_cgi_path,
                        arguments=[
                            "-d",
                            f"extension_dir={self._php_extension_dir(phpmyadmin_runtime)}",
                            "-d",
                            "cgi.force_redirect=0",
                            "-d",
                            "pcre.jit=0",
                            "-d",
                            "log_errors=1",
                            "-d",
                            f"error_log={self.config_service.php_runtime_log_path(phpmyadmin_runtime.version)}",
                            "-b",
                            f"127.0.0.1:{self.config_service.phpmyadmin_fastcgi_port()}",
                        ],
                        working_directory=str(self.runtime_paths.runtime_dir / "php"),
                        log_path=self._php_service_log_path(phpmyadmin_runtime.version),
                        log_to_screen=self._php_service_log_to_screen(),
                        environment={
                            "PHPRC": str(phpmyadmin_runtime.ini_dir),
                            "PHP_INI_SCAN_DIR": "",
                            "REDIRECT_STATUS": "1",
                            "PHP_FCGI_CHILDREN": "1",
                            "PHP_FCGI_MAX_REQUESTS": "500",
                        },
                    )
                )
            services.append(
                ServiceDefinition(
                    id="nginx",
                    name="Nginx",
                    kind=ServiceKind.NGINX,
                    executable_name="nginx",
                    default_port=settings.apache_port,
                    executable_path=str(self.binary_locator.nginx_binary()),
                    arguments=[
                        "-c",
                        str(self.config_service.nginx_main_config_path()),
                        "-p",
                        str(self.binary_locator.nginx_home()),
                        "-g",
                        "daemon off;",
                    ],
                    working_directory=str(self.config_service.nginx_runtime_dir()),
                    log_path=str(self.config_service.nginx_logs_dir() / "nginx-startup.log"),
                )
            )
            return services
        return [
            ServiceDefinition(
                id="apache",
                name="Apache",
                kind=ServiceKind.APACHE,
                executable_name="httpd",
                default_port=settings.apache_port,
                executable_path=str(self.binary_locator.apache_httpd()),
                arguments=[
                    "-DFOREGROUND",
                    "-f",
                    str(self.config_service.apache_main_config_path()),
                    "-d",
                    str(self.binary_locator.apache_home()),
                ],
                working_directory=str(self.config_service.apache_runtime_dir()),
            ),
        ]

    def status(self) -> StackStatus:
        services = [self._status_for(definition) for definition in self.definitions()]
        return StackStatus(services=services)

    def start_all(self) -> StackStatus:
        statuses = [self.start_service(definition.id) for definition in self.definitions()]
        return StackStatus(services=statuses)

    def stop_all(self) -> StackStatus:
        self.process_manager.stop_all()
        return self.status()

    def restart_all(self) -> StackStatus:
        self.process_manager.stop_all()
        return self.start_all()

    def start_service(self, service_id: str) -> ServiceStatus:
        definition = self._definition(service_id)
        current = self.process_manager.status(definition)
        if definition.kind == ServiceKind.NGINX and current.state == ServiceState.RUNNING:
            backend_error = self._ensure_php_backends_running()
            if backend_error is not None:
                LOGGER.error("Nginx start failed: %s", backend_error)
                return ServiceStatus(
                    service_id=definition.id,
                    state=ServiceState.ERROR,
                    port=definition.default_port,
                    message=backend_error,
                )
            return current
        if current.state == ServiceState.RUNNING:
            return current
        if self._port_in_use(definition.default_port):
            LOGGER.error("Service %s cannot start because port %s is already in use.", definition.id, definition.default_port)
            return ServiceStatus(
                service_id=definition.id,
                state=ServiceState.ERROR,
                port=definition.default_port,
                message=f"Port {definition.default_port} is already in use",
            )
        if definition.kind == ServiceKind.APACHE:
            hosts_error = self._sync_hosts_block()
            if hosts_error is not None:
                LOGGER.error("Apache start failed: %s", hosts_error)
                return ServiceStatus(
                    service_id=definition.id,
                    state=ServiceState.ERROR,
                    port=definition.default_port,
                    message=hosts_error,
                )
            sites = self.site_service.list_sites()
            node_projects = self.node_project_service.list_projects()
            proxies = self.proxy_service.list_proxies()
            self._sanitize_site_runtime_inis(sites)
            self._sanitize_phpmyadmin_runtime_ini()
            self.config_service.write_phpmyadmin_config()
            self.config_service.write_phpmyadmin_php_cgi_wrapper()
            self.config_service.write_apache_stack_config(sites, node_projects=node_projects, proxies=proxies, port=definition.default_port)
            for site in sites:
                self.config_service.write_site_configs(site, apache_port=definition.default_port)
        elif definition.kind == ServiceKind.NGINX:
            hosts_error = self._sync_hosts_block()
            if hosts_error is not None:
                LOGGER.error("Nginx start failed: %s", hosts_error)
                return ServiceStatus(
                    service_id=definition.id,
                    state=ServiceState.ERROR,
                    port=definition.default_port,
                    message=hosts_error,
                )
            sites = self.site_service.list_sites()
            node_projects = self.node_project_service.list_projects()
            proxies = self.proxy_service.list_proxies()
            self._sanitize_site_runtime_inis(sites)
            self._sanitize_phpmyadmin_runtime_ini()
            self.config_service.write_phpmyadmin_config()
            self.config_service.write_nginx_stack_config(sites, node_projects=node_projects, proxies=proxies, port=definition.default_port)
            backend_error = self._ensure_php_backends_running()
            if backend_error is not None:
                LOGGER.error("Nginx start failed: %s", backend_error)
                return ServiceStatus(
                    service_id=definition.id,
                    state=ServiceState.ERROR,
                    port=definition.default_port,
                    message=backend_error,
                )
        status = self.process_manager.start(definition)
        if status.state == ServiceState.ERROR:
            LOGGER.error("%s start failed: %s", definition.name, status.message)
        return status

    def _ensure_php_backends_running(self) -> str | None:
        for backend in [item for item in self.definitions() if item.kind == ServiceKind.PHP_FPM]:
            backend_status = self.process_manager.status(backend)
            if backend_status.state == ServiceState.RUNNING:
                continue
            if self._port_in_use(backend.default_port):
                released = self._release_stale_listener_port(backend.default_port)
                if released:
                    LOGGER.warning(
                        "Released stale listener(s) on %s for backend %s",
                        backend.default_port,
                        backend.id,
                    )
                    time.sleep(0.2)
            started = self.process_manager.start(backend)
            if started.state == ServiceState.ERROR:
                LOGGER.error(
                    "Failed to start backend %s (%s): %s",
                    backend.id,
                    backend.executable_path,
                    started.message,
                )
                return f"Failed to start {backend.name}: {started.message}"
        return None

    def _release_stale_listener_port(self, port: int) -> bool:
        try:
            result = subprocess.run(
                ["lsof", "-nP", f"-iTCP:{port}", "-sTCP:LISTEN", "-t"],
                capture_output=True,
                text=True,
                check=False,
            )
            pids = []
            for line in (result.stdout or "").splitlines():
                value = line.strip()
                if value.isdigit():
                    pids.append(int(value))
            if not pids:
                return False
            for pid in pids:
                try:
                    subprocess.run(["kill", "-TERM", str(pid)], capture_output=True, text=True, check=False)
                except Exception:
                    continue
            for _ in range(15):
                if not self._port_in_use(port):
                    return True
                time.sleep(0.1)
            for pid in pids:
                try:
                    subprocess.run(["kill", "-KILL", str(pid)], capture_output=True, text=True, check=False)
                except Exception:
                    continue
            for _ in range(10):
                if not self._port_in_use(port):
                    return True
                time.sleep(0.1)
            return False
        except Exception:
            return False

    def stop_service(self, service_id: str) -> ServiceStatus:
        definition = self._definition(service_id)
        if definition.kind in {ServiceKind.APACHE, ServiceKind.NGINX}:
            try:
                result = self.hosts_gateway.clear_serverengine_block()
                if not result.success:
                    LOGGER.error("%s stop failed while clearing hosts: %s", definition.name, result.message)
                    return ServiceStatus(service_id=definition.id, state=ServiceState.ERROR, message=result.message)
            except Exception as exc:
                LOGGER.exception("%s stop failed while clearing hosts", definition.name)
                return ServiceStatus(service_id=definition.id, state=ServiceState.ERROR, message=f"Hosts update failed: {exc}")
        if definition.kind == ServiceKind.NGINX:
            for backend in [item for item in self.definitions() if item.kind == ServiceKind.PHP_FPM]:
                self.process_manager.stop(backend.id)
        status = self.process_manager.stop(service_id)
        if status.state == ServiceState.ERROR:
            LOGGER.error("%s stop failed: %s", definition.name, status.message)
        return status

    def _sync_hosts_block(self) -> str | None:
        domains: list[str] = ["serverengine"]
        for site in self.site_service.list_sites():
            domains.extend(site.all_domains())
        for project in self.node_project_service.list_projects():
            domains.append(project.local_domain)
        for proxy in self.proxy_service.list_proxies():
            domains.append(proxy.local_domain)
        try:
            result = self.hosts_gateway.sync_serverengine_block(domains)
            if not result.success:
                return result.message
        except Exception as exc:
            return f"Hosts update failed: {exc}"
        return None

    def apache_runtime_paths(self) -> dict[str, str]:
        paths = self.binary_locator.apache_paths()
        paths["httpd_conf"] = str(self.config_service.apache_main_config_path())
        paths["logs_dir"] = str(self.config_service.apache_logs_dir())
        paths["runtime_dir"] = str(self.config_service.apache_runtime_dir())
        return paths

    def _definition(self, service_id: str) -> ServiceDefinition:
        for definition in self.definitions():
            if definition.id == service_id:
                return definition
        raise ValueError(f"Unknown service: {service_id}")

    def _status_for(self, definition: ServiceDefinition) -> ServiceStatus:
        status = self.process_manager.status(definition)
        if status.state == ServiceState.STOPPED and definition.executable_path:
            executable_path = definition.executable_path
            if executable_path and not self._binary_exists(definition):
                return ServiceStatus(
                    service_id=definition.id,
                    state=ServiceState.STOPPED,
                    port=definition.default_port,
                    message=f"{definition.name} binary not found at {executable_path}",
                )
            if self._port_in_use(definition.default_port):
                return ServiceStatus(
                    service_id=definition.id,
                    state=ServiceState.ERROR,
                    port=definition.default_port,
                    message=f"Port {definition.default_port} is already in use",
                )
        return status

    def _port_in_use(self, port: int) -> bool:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.1)
            return sock.connect_ex(("127.0.0.1", port)) == 0

    def _binary_exists(self, definition: ServiceDefinition) -> bool:
        if not definition.executable_path:
            return False
        return bool(definition.executable_path) and self._path_exists(definition.executable_path)

    def _path_exists(self, value: str) -> bool:
        from pathlib import Path

        return Path(value).exists()

    def _php_fastcgi_service_id(self, version: str) -> str:
        return "php-cgi-" + version.replace(".", "_")

    def _php_fastcgi_service_id_for_site(self, site_id: str) -> str:
        return f"php-cgi-site-{site_id}"

    def _php_service_log_to_screen(self) -> bool:
        settings = self.settings_service.get_settings()
        return bool(settings.php_runtime_log_to_screen)

    def _php_service_log_path(self, version: str) -> str | None:
        settings = self.settings_service.get_settings()
        if not settings.php_runtime_log_to_file:
            return None
        return str(self.config_service.php_runtime_log_path(version))

    def _php_extension_dir(self, runtime) -> Path:
        home = Path(runtime.home)
        direct_candidates = [
            home / "lib" / "php" / "extensions",
            home / "lib" / "php" / "modules",
            home / "modules",
        ]
        for base in direct_candidates:
            if not base.exists():
                continue
            if any(item.is_file() and item.suffix == ".so" for item in base.glob("*.so")):
                return base
            subdirs = [item for item in base.iterdir() if item.is_dir()]
            for child in subdirs:
                if any(item.is_file() and item.suffix == ".so" for item in child.glob("*.so")):
                    return child
        opcache_hits = list(home.glob("**/opcache.so"))
        if opcache_hits:
            return opcache_hits[0].parent
        return direct_candidates[0]

    def _sanitize_site_runtime_inis(self, sites) -> None:
        versions = {site.php_version for site in sites if getattr(site, "php_version", None)}
        for version in versions:
            runtime = self.binary_locator.php_runtime(version)
            if runtime is not None:
                self._sanitize_runtime_ini(runtime)

    def _sanitize_phpmyadmin_runtime_ini(self) -> None:
        runtime = self.config_service.phpmyadmin_runtime()
        if runtime is not None:
            self._sanitize_runtime_ini(runtime)

    def _sanitize_runtime_ini(self, runtime) -> None:
        ini_path = Path(runtime.ini_dir) / "php.ini"
        if not ini_path.exists():
            return
        text = ini_path.read_text(encoding="utf-8", errors="replace")
        lines = text.splitlines()
        changed = False
        ext_dir = self._php_extension_dir(runtime)
        rewritten: list[str] = []
        for line in lines:
            stripped = line.strip()
            lower = stripped.lower()
            if not stripped:
                rewritten.append(line)
                continue

            if lower.startswith(("zend_extension=", "extension=", "extension_dir=")):
                value = stripped.split("=", 1)[1].strip().strip('"').strip("'")
                key = stripped.split("=", 1)[0].strip().lower()

                if key in {"zend_extension", "extension"}:
                    normalized = value.replace("\\", "/")
                    if "/" in normalized:
                        name = Path(normalized).name
                        if key == "zend_extension":
                            if not name:
                                name = "opcache.so"
                            if not name.endswith(".so"):
                                name = name + ".so"
                            rewritten.append(f"zend_extension={name}")
                        else:
                            if name.lower() == "xdebug.so":
                                rewritten.append("zend_extension=xdebug.so")
                            else:
                                rewritten.append(f"extension={name}" if name else line)
                        changed = True
                        continue

                if key == "extension_dir":
                    normalized = value.replace("\\", "/")
                    if "/" in normalized:
                        rewritten.append(f'extension_dir="{ext_dir}"')
                        changed = True
                        continue

            rewritten.append(line)

        # Ensure extension_dir always points to runtime-local modules when a path is present.
        output = "\n".join(rewritten)
        sanitized_output = re.sub(
            r"(?im)^\s*extension_dir\s*=\s*['\"]?[A-Za-z/\\].*$",
            f'extension_dir="{ext_dir}"',
            output,
        )
        if sanitized_output != output:
            changed = True
        if changed:
            ini_path.write_text(sanitized_output.rstrip() + "\n", encoding="utf-8")
            LOGGER.warning("Sanitized php.ini prebuild paths for runtime %s at %s", runtime.version, ini_path)
