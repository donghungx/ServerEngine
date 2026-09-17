from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import hashlib
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit

from server_engine.core.models import NodeProject, OperationResult, Proxy, RuntimePaths, Site
from server_engine.infrastructure.binary_locator import BinaryLocator
from server_engine.services.settings_service import SettingsService


class ConfigService:
    DEFAULT_APACHE_MODULES = [
        "mod_mpm_event.so",
        "mod_actions.so",
        "mod_authz_core.so",
        "mod_authz_host.so",
        "mod_cgid.so",
        "mod_dir.so",
        "mod_mime.so",
        "mod_headers.so",
        "mod_log_config.so",
        "mod_alias.so",
        "mod_unixd.so",
        "mod_autoindex.so",
        "mod_rewrite.so",
    ]
    SSL_APACHE_MODULES = [
        "mod_ssl.so",
        "mod_socache_shmcb.so",
    ]

    def __init__(self, runtime_paths: RuntimePaths, binary_locator: BinaryLocator, settings_service: SettingsService) -> None:
        self.runtime_paths = runtime_paths
        self.binary_locator = binary_locator
        self.settings_service = settings_service

    def openssl_binary(self) -> str:
        configured = os.environ.get("SERVER_ENGINE_OPENSSL", "").strip()
        if configured and Path(configured).is_file():
            return configured
        bundled = sorted((self.runtime_paths.bin_dir / "tools" / "openssl").glob("*/bin/openssl"))
        if bundled:
            binary = bundled[-1]
            self._prepare_bundled_openssl(binary)
            return str(binary)
        return shutil.which("openssl") or "/opt/homebrew/bin/openssl"

    @staticmethod
    def _prepare_bundled_openssl(binary: Path) -> None:
        """Relink a staged Homebrew OpenSSL runtime to its bundled libraries."""
        install_name_tool = shutil.which("install_name_tool") or "/usr/bin/install_name_tool"
        lib_dir = binary.parent.parent / "lib"
        if not lib_dir.is_dir() or not Path(install_name_tool).exists():
            return
        for library_name in ("libssl.3.dylib", "libcrypto.3.dylib"):
            library = lib_dir / library_name
            if not library.exists():
                continue
            try:
                dependencies = subprocess.run(
                    ["/usr/bin/otool", "-L", str(library)],
                    capture_output=True,
                    text=True,
                    check=False,
                ).stdout.splitlines()
                for dependency in dependencies[1:]:
                    dependency = dependency.strip().split(" ", 1)[0]
                    if "/openssl" in dependency and Path(dependency).name.startswith("lib"):
                        subprocess.run(
                            [install_name_tool, "-change", dependency, f"@loader_path/{Path(dependency).name}", str(library)],
                            capture_output=True,
                            check=False,
                        )
                subprocess.run(
                    [install_name_tool, "-id", f"@rpath/{library_name}", str(library)],
                    capture_output=True,
                    check=False,
                )
            except OSError:
                continue
        try:
            dependencies = subprocess.run(
                ["/usr/bin/otool", "-L", str(binary)],
                capture_output=True,
                text=True,
                check=False,
            ).stdout.splitlines()
            for dependency in dependencies[1:]:
                dependency = dependency.strip().split(" ", 1)[0]
                if "/openssl" in dependency and Path(dependency).name.startswith("lib"):
                    subprocess.run(
                        [install_name_tool, "-change", dependency, f"@loader_path/../lib/{Path(dependency).name}", str(binary)],
                        capture_output=True,
                        check=False,
                    )
        except OSError:
            pass

    def openssl_environment(self) -> dict[str, str]:
        environment = os.environ.copy()
        openssl_path = Path(self.openssl_binary())
        bundled_lib = openssl_path.parent.parent / "lib"
        if bundled_lib.is_dir():
            previous = environment.get("DYLD_LIBRARY_PATH", "")
            environment["DYLD_LIBRARY_PATH"] = f"{bundled_lib}:{previous}" if previous else str(bundled_lib)
        return environment

    def apache_runtime_key(self) -> str:
        return self.binary_locator.apache_home().name

    def apache_log_key(self) -> str:
        return self.binary_locator.apache_home().name.removeprefix("apache-").lstrip("-")

    def apache_config_dir(self) -> Path:
        return self.runtime_paths.config_dir / self.apache_runtime_key()

    def apache_main_config_path(self) -> Path:
        return self.apache_config_dir() / "httpd.conf"

    def apache_logs_dir(self) -> Path:
        return self.runtime_paths.logs_dir / "apache" / self.apache_log_key()

    def apache_runtime_dir(self) -> Path:
        return self.runtime_paths.runtime_dir / self.apache_runtime_key()

    def apache_virtual_host(self, site: Site, port: int = 8080) -> str:
        root_path = site.document_root()
        project_root = Path(site.project_path)
        wrapper_path = self.php_cgi_wrapper_path(site)
        logs_dir = self.apache_logs_dir()
        alias_line = ""
        if site.domain_aliases:
            alias_line = f"    ServerAlias {' '.join(site.domain_aliases)}\n"
        php_handler_block = (
            f"    ScriptAlias \"/__server_engine__/cgi/{site.id}/php-cgi\" \"{wrapper_path}\"\n"
            f"    Action application/x-httpd-php \"/__server_engine__/cgi/{site.id}/php-cgi\"\n"
            f"    AddHandler application/x-httpd-php .php\n"
        )
        http_vhost = (
            f"<VirtualHost *:{port}>\n"
            f"    ServerName {site.local_domain}\n"
            f"{alias_line}"
            f"    <Directory \"{project_root}\">\n"
            f"        AllowOverride None\n"
            f"        Require all granted\n"
            f"    </Directory>\n"
            f"    DocumentRoot \"{root_path}\"\n"
            f"    <Directory \"{root_path}\">\n"
            f"        AllowOverride All\n"
            f"        Require all granted\n"
            f"    </Directory>\n"
            f"{php_handler_block}"
            f"    ErrorLog \"{logs_dir / f'{site.id}-error.log'}\"\n"
            f"    CustomLog \"{logs_dir / f'{site.id}-access.log'}\" common\n"
            f"</VirtualHost>\n"
        )
        cert_path, key_path = self.site_ssl_paths(site)
        ssl_ready = site.ssl_enabled and cert_path.exists() and key_path.exists()
        if not ssl_ready:
            return http_vhost
        if not site.ssl_allow_http:
            http_vhost = (
                f"<VirtualHost *:{port}>\n"
                f"    ServerName {site.local_domain}\n"
                f"{alias_line}"
                f"    Redirect permanent / https://{site.local_domain}/\n"
                f"</VirtualHost>\n"
            )
        ssl_hardening = ""
        if site.ssl_enforce_tls:
            ssl_hardening = (
                "    SSLProtocol -all +TLSv1.2 +TLSv1.3\n"
                "    SSLHonorCipherOrder on\n"
            )
        https_vhost = (
            f"\n<VirtualHost *:443>\n"
            f"    ServerName {site.local_domain}\n"
            f"{alias_line}"
            f"    <Directory \"{project_root}\">\n"
            f"        AllowOverride None\n"
            f"        Require all granted\n"
            f"    </Directory>\n"
            f"    DocumentRoot \"{root_path}\"\n"
            f"    <Directory \"{root_path}\">\n"
            f"        AllowOverride All\n"
            f"        Require all granted\n"
            f"    </Directory>\n"
            f"    SSLEngine on\n"
            f"{ssl_hardening}"
            f"    SSLCertificateFile \"{cert_path}\"\n"
            f"    SSLCertificateKeyFile \"{key_path}\"\n"
            f"{php_handler_block}"
            f"    ErrorLog \"{logs_dir / f'{site.id}-ssl-error.log'}\"\n"
            f"    CustomLog \"{logs_dir / f'{site.id}-ssl-access.log'}\" common\n"
            f"</VirtualHost>\n"
        )
        return http_vhost + https_vhost

    def nginx_runtime_key(self) -> str:
        return self.binary_locator.nginx_home().name

    def nginx_log_key(self) -> str:
        return self.binary_locator.nginx_home().name.removeprefix("nginx-").lstrip("-")

    def nginx_config_dir(self) -> Path:
        return self.runtime_paths.config_dir / self.nginx_runtime_key()

    def nginx_main_config_path(self) -> Path:
        return self.nginx_config_dir() / "nginx.conf"

    def nginx_logs_dir(self) -> Path:
        return self.runtime_paths.logs_dir / "nginx" / self.nginx_log_key()

    def nginx_runtime_dir(self) -> Path:
        return self.runtime_paths.runtime_dir / self.nginx_runtime_key()

    def phpmyadmin_domain(self) -> str:
        return "serverengine"

    def phpmyadmin_route(self) -> str:
        return "/phpmyadmin/"

    def phpmyadmin_root(self) -> Path:
        settings = self.settings_service.get_settings()
        return self.binary_locator.phpmyadmin_root(settings.active_phpmyadmin_version)

    def phpmyadmin_config_dir(self) -> Path:
        settings = self.settings_service.get_settings()
        version = settings.active_phpmyadmin_version or self.phpmyadmin_root().name
        return self.runtime_paths.config_dir / "phpmyadmin" / version

    def phpmyadmin_config_path(self) -> Path:
        return self.phpmyadmin_config_dir() / "config.inc.php"

    def phpmyadmin_runtime(self):
        settings = self.settings_service.get_settings()
        requested = settings.phpmyadmin_php_version
        runtime = self.binary_locator.php_runtime(requested)
        if runtime is not None:
            return runtime
        runtimes = self.binary_locator.available_php_runtimes()
        if runtimes:
            return runtimes[-1]
        return None

    def phpmyadmin_wrapper_path(self) -> Path:
        return self.runtime_paths.runtime_dir / "php" / "cgi-bin" / "phpmyadmin-php-cgi"

    def phpmyadmin_fastcgi_port(self) -> int:
        runtime = self.phpmyadmin_runtime()
        token = runtime.label if runtime is not None else "phpmyadmin"
        seed = sum((index + 1) * ord(char) for index, char in enumerate("phpmyadmin-" + token))
        return 10000 + (seed % 40000)

    def phpmyadmin_base_url(self) -> str:
        port = self.settings_service.get_settings().apache_port
        port_suffix = "" if port == 80 else f":{port}"
        return f"http://{self.phpmyadmin_domain()}{port_suffix}{self.phpmyadmin_route()}"

    def phpmyadmin_url(self) -> str:
        return f"{self.phpmyadmin_base_url()}index.php"

    def apache_main_config(self, sites: list[Site], node_projects: list[NodeProject] | None = None, proxies: list[Proxy] | None = None, port: int = 8080) -> str:
        node_projects = node_projects or []
        proxies = proxies or []
        apache_home = self.binary_locator.apache_home()
        modules_dir = self.binary_locator.apache_modules_dir()
        runtime_dir = self.apache_runtime_dir()
        logs_dir = self.apache_logs_dir()
        mime_types_path = apache_home / "conf" / "mime.types"
        if not mime_types_path.exists():
            alternate_mime_types = apache_home / "share" / "httpd" / "mime.types"
            if alternate_mime_types.exists():
                mime_types_path = alternate_mime_types
        if not mime_types_path.exists():
            bottle_mime_types = apache_home / ".bottle" / "etc" / "httpd" / "mime.types"
            if bottle_mime_types.exists():
                mime_types_path = bottle_mime_types
        self._ensure_apache_dirs()
        site_includes = [f'Include "{self.site_config_paths(site)["apache"]}"' for site in sites]
        node_includes = [f'Include "{self.node_project_config_paths(project)["apache"]}"' for project in node_projects]
        proxy_includes = [f'Include "{self.proxy_config_paths(proxy)["apache"]}"' for proxy in proxies]
        includes = "\n".join([*site_includes, *node_includes, *proxy_includes])
        available_modules = set(self.binary_locator.available_apache_modules())
        settings = self.settings_service.get_settings()
        selected_modules = settings.apache_enabled_modules or self.DEFAULT_APACHE_MODULES
        modules = [name for name in selected_modules if name in available_modules]
        # Required for PHP Action/AddHandler routing (incl. phpMyAdmin).
        for module_name in ("mod_actions.so", "mod_mime.so"):
            if module_name in available_modules and module_name not in modules:
                modules.append(module_name)
        if any(site.ssl_enabled for site in sites) or any(project.ssl_enabled for project in node_projects) or any(proxy.ssl_enabled for proxy in proxies):
            for module_name in self.SSL_APACHE_MODULES:
                if module_name in available_modules and module_name not in modules:
                    modules.append(module_name)
        for module_name in ("mod_proxy.so", "mod_proxy_http.so", "mod_proxy_wstunnel.so"):
            if (node_projects or proxies) and module_name in available_modules and module_name not in modules:
                modules.append(module_name)
        if not modules:
            modules = [name for name in self.DEFAULT_APACHE_MODULES if name in available_modules]
        load_modules = "\n".join(f'LoadModule {name.removeprefix("mod_").removesuffix(".so")}_module "{modules_dir / name}"' for name in modules)
        ssl_listen = "Listen 443\n" if (any(site.ssl_enabled for site in sites) or any(project.ssl_enabled for project in node_projects) or any(proxy.ssl_enabled for proxy in proxies)) else ""
        apache_error_log = settings.apache_error_log_path.strip() or str(logs_dir / "httpd-error.log")
        return (
            f'ServerRoot "{apache_home}"\n'
            f'PidFile "{runtime_dir / "httpd.pid"}"\n'
            f'ScriptSock "{runtime_dir / "cgisock"}"\n'
            f'Listen {port}\n'
            f'{ssl_listen}'
            f'ErrorLog "{apache_error_log}"\n'
            f'ServerName localhost\n'
            f'User nobody\n'
            f'Group staff\n'
            f"Timeout 90\n"
            f"KeepAlive Off\n"
            f"HostnameLookups Off\n"
            f"<IfModule mpm_event_module>\n"
            f"    StartServers 4\n"
            f"    ThreadLimit 64\n"
            f"    ThreadsPerChild 25\n"
            f"    MinSpareThreads 50\n"
            f"    MaxSpareThreads 150\n"
            f"    MaxRequestWorkers 400\n"
            f"    MaxConnectionsPerChild 1000\n"
            f"</IfModule>\n"
            f"<IfModule cgid_module>\n"
            f"    CGIDScriptTimeout 120\n"
            f"</IfModule>\n"
            f'LogFormat "%h %l %u %t \\"%r\\" %>s %b" common\n'
            f'LogFormat "%h %l %u %t \\"%r\\" %>s %b \\"%{{Referer}}i\\" \\"%{{User-Agent}}i\\"" combined\n'
            f'TypesConfig "{mime_types_path}"\n'
            f"{load_modules}\n"
            f'DocumentRoot "{self.runtime_paths.root}"\n'
            f'<Directory "{self.runtime_paths.root}">\n'
            f"    Options FollowSymLinks\n"
            f"    AllowOverride All\n"
            f"    Require all granted\n"
            f"</Directory>\n"
            f'<Directory "{self.runtime_paths.runtime_dir / "php" / "cgi-bin"}">\n'
            f"    Options ExecCGI\n"
            f"    AllowOverride None\n"
            f"    Require all granted\n"
            f"</Directory>\n"
            f"{self.apache_phpmyadmin_virtual_host(port)}"
            f"DirectoryIndex index.php index.html\n"
            f"{includes}\n"
        )

    def apache_phpmyadmin_virtual_host(self, port: int) -> str:
        phpmyadmin_root = self.phpmyadmin_root()
        wrapper_path = self.phpmyadmin_wrapper_path()
        return (
            f"<VirtualHost *:{port}>\n"
            f"    ServerName {self.phpmyadmin_domain()}\n"
            f"    RedirectMatch 302 ^/$ {self.phpmyadmin_route()}index.php\n"
            f"    RedirectMatch 302 ^/phpmyadmin/?$ /phpmyadmin/index.php\n"
            f'    Alias "{self.phpmyadmin_route()}" "{phpmyadmin_root}/"\n'
            f'    ScriptAlias "/__server_engine__/cgi/phpmyadmin/php-cgi" "{wrapper_path}"\n'
            f'    <Directory "{phpmyadmin_root}">\n'
            f"        Options FollowSymLinks\n"
            f"        AllowOverride All\n"
            f"        Require all granted\n"
            f"        DirectoryIndex index.php index.html\n"
            f'        Action application/x-httpd-php "/__server_engine__/cgi/phpmyadmin/php-cgi"\n'
            f"        <FilesMatch \"\\.php$\">\n"
            f"            SetHandler application/x-httpd-php\n"
            f"        </FilesMatch>\n"
            f"    </Directory>\n"
            f"</VirtualHost>\n"
        )

    def nginx_server_block(self, site: Site, port: int = 8080) -> str:
        root_path = site.document_root()
        backend_port = self.php_fastcgi_port(site.php_version)
        logs_dir = self.nginx_logs_dir()
        server_names = " ".join(site.all_domains())
        framework = getattr(site.framework_preset, "value", site.framework_preset)
        rewrite_target = "/index.php?$args" if framework == "wordpress" else "/index.php?$query_string"
        ssl_block = ""
        cert_path, key_path = self.site_ssl_paths(site)
        ssl_ready = site.ssl_enabled and cert_path.exists() and key_path.exists()
        if ssl_ready:
            ssl_block = (
                f"\n    listen 443 ssl;\n"
                f"    ssl_certificate \"{cert_path}\";\n"
                f"    ssl_certificate_key \"{key_path}\";"
            )
        tls_hardening = ""
        if ssl_ready and site.ssl_enforce_tls:
            tls_hardening = (
                "\n    ssl_protocols TLSv1.2 TLSv1.3;\n"
                "    ssl_prefer_server_ciphers on;"
            )
        redirect_block = ""
        if ssl_ready and not site.ssl_allow_http:
            redirect_block = (
                f"server {{\n"
                f"    listen {port};\n"
                f"    server_name {server_names};\n"
                f"    return 301 https://$host$request_uri;\n"
                f"}}\n\n"
            )
            port = 80
        return (
            f"{redirect_block}"
            f"server {{\n"
            f"    listen {port};\n"
            f"{ssl_block}\n"
            f"{tls_hardening}\n"
            f"    server_name {server_names};\n"
            f"    root \"{root_path}\";\n"
            f"    index index.php index.html;\n\n"
            f"    location / {{\n"
            f"        try_files $uri $uri/ {rewrite_target};\n"
            f"    }}\n\n"
            f"    location ~ \\.php$ {{\n"
            f"        include \"{self.binary_locator.nginx_home() / 'conf' / 'fastcgi_params'}\";\n"
            f"        fastcgi_pass 127.0.0.1:{backend_port};\n"
            f"        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;\n"
            f"    }}\n"
            f"    error_log \"{logs_dir / f'{site.id}-error.log'}\";\n"
            f"    access_log \"{logs_dir / f'{site.id}-access.log'}\";\n"
            f"}}\n"
        )

    def apache_node_proxy_virtual_host(self, project: NodeProject, port: int = 8080) -> str:
        alias_line = ""
        log_name = project.id
        http_vhost = (
            f"<VirtualHost *:{port}>\n"
            f"    ServerName {project.local_domain}\n"
            f"{alias_line}"
            f"    ProxyPreserveHost On\n"
            f"    ProxyPass / http://127.0.0.1:{project.port}/ upgrade=websocket\n"
            f"    ProxyPassReverse / http://127.0.0.1:{project.port}/\n"
            f"    ErrorLog \"{self.apache_logs_dir() / f'{log_name}-error.log'}\"\n"
            f"    CustomLog \"{self.apache_logs_dir() / f'{log_name}-access.log'}\" common\n"
            f"</VirtualHost>\n"
        )
        cert_path, key_path = self.node_project_ssl_paths(project)
        ssl_ready = project.ssl_enabled and cert_path.exists() and key_path.exists()
        if not ssl_ready:
            return http_vhost
        if not project.ssl_allow_http:
            http_vhost = (
                f"<VirtualHost *:{port}>\n"
                f"    ServerName {project.local_domain}\n"
                f"{alias_line}"
                f"    Redirect permanent / https://{project.local_domain}/\n"
                f"</VirtualHost>\n"
            )
        ssl_hardening = ""
        if project.ssl_enforce_tls:
            ssl_hardening = (
                "    SSLProtocol -all +TLSv1.2 +TLSv1.3\n"
                "    SSLHonorCipherOrder on\n"
            )
        https_vhost = (
            f"\n<VirtualHost *:443>\n"
            f"    ServerName {project.local_domain}\n"
            f"{alias_line}"
            f"    <Directory \"{Path(project.project_path)}\">\n"
            f"        Require all granted\n"
            f"    </Directory>\n"
            f"{ssl_hardening}"
            f"    SSLEngine on\n"
            f"    SSLCertificateFile \"{cert_path}\"\n"
            f"    SSLCertificateKeyFile \"{key_path}\"\n"
            f"    ProxyPreserveHost On\n"
            f"    ProxyPass / http://127.0.0.1:{project.port}/ upgrade=websocket\n"
            f"    ProxyPassReverse / http://127.0.0.1:{project.port}/\n"
            f"    ErrorLog \"{self.apache_logs_dir() / f'{log_name}-ssl-error.log'}\"\n"
            f"    CustomLog \"{self.apache_logs_dir() / f'{log_name}-ssl-access.log'}\" common\n"
            f"</VirtualHost>\n"
        )
        return http_vhost + https_vhost

    def nginx_node_proxy_server_block(self, project: NodeProject, port: int = 8080) -> str:
        ssl_block = ""
        cert_path, key_path = self.node_project_ssl_paths(project)
        if project.ssl_enabled and cert_path.exists() and key_path.exists():
            ssl_block = (
                f"\n    listen 443 ssl;\n"
                f"    ssl_certificate \"{cert_path}\";\n"
                f"    ssl_certificate_key \"{key_path}\";"
            )
        tls_hardening = ""
        if project.ssl_enabled and project.ssl_enforce_tls and cert_path.exists() and key_path.exists():
            tls_hardening = (
                "    ssl_protocols TLSv1.2 TLSv1.3;\n"
                "    ssl_prefer_server_ciphers on;\n"
            )
        redirect_block = ""
        if project.ssl_enabled and not project.ssl_allow_http and cert_path.exists() and key_path.exists():
            redirect_block = (
                f"server {{\n"
                f"    listen {port};\n"
                f"    server_name {project.local_domain};\n"
                f"    return 301 https://$host$request_uri;\n"
                f"}}\n\n"
            )
            port = 80
        return (
            f"{redirect_block}"
            f"server {{\n"
            f"    listen {port};\n"
            f"{ssl_block}\n"
            f"{tls_hardening}"
            f"    server_name {project.local_domain};\n"
            f"    location / {{\n"
            f"        proxy_http_version 1.1;\n"
            f"        proxy_set_header Host $host;\n"
            f"        proxy_set_header X-Real-IP $remote_addr;\n"
            f"        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n"
            f"        proxy_set_header X-Forwarded-Proto $scheme;\n"
            f"        proxy_set_header Upgrade $http_upgrade;\n"
            f"        proxy_set_header Connection \"upgrade\";\n"
            f"        proxy_pass http://127.0.0.1:{project.port};\n"
            f"    }}\n"
            f"    error_log \"{self.nginx_logs_dir() / f'{project.id}-error.log'}\";\n"
            f"    access_log \"{self.nginx_logs_dir() / f'{project.id}-access.log'}\";\n"
            f"}}\n"
        )

    def apache_phpmyadmin_block(self) -> str:
        phpmyadmin_root = self.phpmyadmin_root()
        wrapper_path = self.phpmyadmin_wrapper_path()
        return (
            f"RedirectMatch 302 ^/phpmyadmin$ https://{self.phpmyadmin_domain()}{self.phpmyadmin_route()}\n"
            f"RedirectMatch 302 ^/phpmyadmin/(.*)$ https://{self.phpmyadmin_domain()}{self.phpmyadmin_route()}$1\n"
            f'Alias "{self.phpmyadmin_route()}" "{phpmyadmin_root}/"\n'
            f'ScriptAlias "/__server_engine__/cgi/phpmyadmin/php-cgi" "{wrapper_path}"\n'
            f'<Directory "{phpmyadmin_root}">\n'
            f"    Options FollowSymLinks\n"
            f"    AllowOverride All\n"
            f"    Require all granted\n"
            f"    DirectoryIndex index.php index.html\n"
            f'    Action application/x-httpd-php "/__server_engine__/cgi/phpmyadmin/php-cgi"\n'
            f"    AddHandler application/x-httpd-php .php\n"
            f"</Directory>\n"
        )

    def php_fpm_pool(self, site: Site) -> str:
        return (
            f"[{site.id}]\n"
            f"user = nobody\n"
            f"group = staff\n"
            f"listen = {self.runtime_paths.runtime_dir / (site.id + '.sock')}\n"
            f"pm = dynamic\n"
            f"pm.max_children = 5\n"
            f"pm.start_servers = 2\n"
            f"pm.min_spare_servers = 1\n"
            f"pm.max_spare_servers = 3\n"
            f"chdir = {site.project_path}\n"
        )

    def site_config_paths(self, site: Site) -> dict[str, Path]:
        return {
            "apache": self.runtime_paths.sites_config_dir / f"{site.id}.apache.conf",
            "nginx": self.runtime_paths.sites_config_dir / f"{site.id}.nginx.conf",
            "php_fpm": self.runtime_paths.php_config_dir / f"{site.id}.pool.conf",
        }

    def node_project_config_paths(self, project: NodeProject) -> dict[str, Path]:
        return {
            "apache": self.runtime_paths.sites_config_dir / f"{project.id}.node.apache.conf",
            "nginx": self.runtime_paths.sites_config_dir / f"{project.id}.node.nginx.conf",
        }

    def proxy_config_paths(self, proxy: Proxy) -> dict[str, Path]:
        return {
            "apache": self.runtime_paths.sites_config_dir / f"{proxy.id}.proxy.apache.conf",
            "nginx": self.runtime_paths.sites_config_dir / f"{proxy.id}.proxy.nginx.conf",
        }

    def apache_proxy_virtual_host(self, proxy: Proxy, port: int) -> str:
        target = self._proxy_target(proxy.target)
        websocket_routes = ""
        if target.startswith("unix:"):
            target = f"{target.rstrip('/')}|http://localhost/"
            websocket_block = ""
        else:
            target = target.rstrip("/") + "/"
            websocket_target = target
            upstream = urlsplit(target)
            if websocket_target.startswith("https://"):
                websocket_target = "wss://" + websocket_target.removeprefix("https://")
            elif websocket_target.startswith("http://"):
                websocket_target = "ws://" + websocket_target.removeprefix("http://")
            websocket_block = (
                "    RewriteEngine On\n"
                f'    RequestHeader set Host "{upstream.netloc}" "expr=%{{HTTP:Upgrade}} =~ m#(?i)^websocket$#"\n'
                f'    RequestHeader unset Origin "expr=%{{HTTP:Upgrade}} =~ m#(?i)^websocket$#"\n'
                "    RewriteCond %{REQUEST_URI} !^/_next/(hmr|webpack-hmr)(/|$) [NC]\n"
                "    RewriteCond %{HTTP:Upgrade} websocket [NC]\n"
                "    RewriteCond %{HTTP:Connection} (^|,)[[:space:]]*upgrade([[:space:]]*,|$) [NC]\n"
                f"    RewriteRule ^/?(.*)$ {websocket_target}$1 [P,L]\n"
            )
            # Next/Turbopack uses a dedicated HMR endpoint. Keep explicit
            # websocket mappings before the catch-all so Apache never lets
            # mod_proxy_http handle this upgrade request.
            websocket_routes = (
                f"    ProxyPass /_next/hmr {websocket_target}_next/hmr\n"
                f"    ProxyPassReverse /_next/hmr {websocket_target}_next/hmr\n"
                f"    ProxyPass /_next/webpack-hmr {websocket_target}_next/webpack-hmr\n"
                f"    ProxyPassReverse /_next/webpack-hmr {websocket_target}_next/webpack-hmr\n"
            )
        cert_path, key_path = self.proxy_ssl_paths(proxy)
        http_vhost = f'''<VirtualHost *:{port}>
    ServerName {proxy.local_domain}
    ProxyPreserveHost On
    ProxyWebsocketFallbackToProxyHttp Off
{websocket_block}
{websocket_routes}
    ProxyPass / {target} upgrade=websocket
    ProxyPassReverse / {target}
    ErrorLog "{self.apache_logs_dir() / f'{proxy.id}-error.log'}"
    CustomLog "{self.apache_logs_dir() / f'{proxy.id}-access.log'}" "%h %l %u %t \\"%r\\" %>s %{{Upgrade}}i %{{Connection}}i"
</VirtualHost>
'''
        ssl_ready = proxy.ssl_enabled and cert_path.exists() and key_path.exists()
        if ssl_ready and (proxy.ssl_enforce_tls or not proxy.ssl_allow_http):
            http_vhost = f'''<VirtualHost *:{port}>
    ServerName {proxy.local_domain}
    Redirect permanent / https://{proxy.local_domain}/
</VirtualHost>
'''
        if not ssl_ready:
            return http_vhost
        https_vhost = f'''<VirtualHost *:443>
    ServerName {proxy.local_domain}
    SSLEngine on
    SSLCertificateFile "{cert_path}"
    SSLCertificateKeyFile "{key_path}"
    ProxyPreserveHost On
    ProxyWebsocketFallbackToProxyHttp Off
{websocket_block}
{websocket_routes}
    ProxyPass / {target} upgrade=websocket
    ProxyPassReverse / {target}
    ErrorLog "{self.apache_logs_dir() / f'{proxy.id}-ssl-error.log'}"
    CustomLog "{self.apache_logs_dir() / f'{proxy.id}-ssl-access.log'}" "%h %l %u %t \\"%r\\" %>s %{{Upgrade}}i %{{Connection}}i"
</VirtualHost>
'''
        return http_vhost + https_vhost

    def nginx_proxy_server_block(self, proxy: Proxy, port: int) -> str:
        target = self._proxy_target(proxy.target).rstrip("/")
        if target.startswith("unix:"):
            target = f"http://{target}:"
        cert_path, key_path = self.proxy_ssl_paths(proxy)
        ssl_block = ""
        ssl_ready = proxy.ssl_enabled and cert_path.exists() and key_path.exists()
        if ssl_ready:
            ssl_block = f'\n    listen 443 ssl;\n    ssl_certificate "{cert_path}";\n    ssl_certificate_key "{key_path}";'
        redirect_block = ""
        if ssl_ready and (proxy.ssl_enforce_tls or not proxy.ssl_allow_http):
            redirect_block = (
                f"server {{\n"
                f"    listen {port};\n"
                f"    server_name {proxy.local_domain};\n"
                f"    return 301 https://$host$request_uri;\n"
                f"}}\n\n"
            )
            port = 80
        return f'''{redirect_block}server {{
    listen {port};
    {ssl_block.strip()}
    server_name {proxy.local_domain};
    location / {{
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_pass {target};
    }}
    error_log "{self.nginx_logs_dir() / f'{proxy.id}-error.log'}";
    access_log "{self.nginx_logs_dir() / f'{proxy.id}-access.log'}";
}}
'''

    def proxy_ssl_paths(self, proxy: Proxy) -> tuple[Path, Path]:
        certs_dir = self.ssl_certs_dir()
        return certs_dir / f"{proxy.id}.crt", certs_dir / f"{proxy.id}.key"

    def ensure_proxy_ssl_certificate(self, proxy: Proxy) -> OperationResult:
        return self.ensure_node_project_ssl_certificate(proxy)

    @staticmethod
    def _proxy_target(raw_target: str) -> str:
        """Use IPv4 loopback for local Docker targets on macOS."""
        target = str(raw_target or "").strip()
        if target.startswith("unix:"):
            return target
        try:
            parsed = urlsplit(target)
            if parsed.hostname == "localhost":
                host = "127.0.0.1"
                if parsed.username or parsed.password:
                    credentials = parsed.username or ""
                    if parsed.password is not None:
                        credentials += ":" + parsed.password
                    host = credentials + "@" + host
                netloc = host + (f":{parsed.port}" if parsed.port else "")
                return urlunsplit((parsed.scheme, netloc, parsed.path, parsed.query, parsed.fragment))
        except ValueError:
            pass
        return target

    def write_site_configs(self, site: Site, apache_port: int = 8080) -> dict[str, str]:
        paths = self.site_config_paths(site)
        apache = self.apache_virtual_host(site, port=apache_port)
        nginx = self.nginx_server_block(site, port=apache_port)
        php_fpm = self.php_fpm_pool(site)
        self._ensure_apache_dirs()
        self._ensure_nginx_dirs()
        self.write_php_cgi_wrapper(site)
        paths["apache"].write_text(apache, encoding="utf-8")
        paths["nginx"].write_text(nginx, encoding="utf-8")
        paths["php_fpm"].write_text(php_fpm, encoding="utf-8")
        return {"apache": str(paths["apache"]), "nginx": str(paths["nginx"]), "php_fpm": str(paths["php_fpm"])}

    def write_apache_stack_config(self, sites: list[Site], node_projects: list[NodeProject] | None = None, proxies: list[Proxy] | None = None, port: int = 8080) -> str:
        node_projects = node_projects or []
        proxies = proxies or []
        self._ensure_apache_dirs()
        self._prune_stale_site_configs(sites, node_projects, proxies)
        config_path = self.apache_main_config_path()
        config_path.write_text(self.apache_main_config(sites, node_projects=node_projects, proxies=proxies, port=port), encoding="utf-8")
        for site in sites:
            self.write_php_cgi_wrapper(site)
        self.write_phpmyadmin_php_cgi_wrapper()
        for project in node_projects:
            self.node_project_config_paths(project)["apache"].write_text(
                self.apache_node_proxy_virtual_host(project, port=port),
                encoding="utf-8",
            )
        for proxy in proxies:
            self.proxy_config_paths(proxy)["apache"].write_text(self.apache_proxy_virtual_host(proxy, port), encoding="utf-8")
        return str(config_path)

    def nginx_main_config(self, sites: list[Site], node_projects: list[NodeProject] | None = None, proxies: list[Proxy] | None = None, port: int = 8080) -> str:
        node_projects = node_projects or []
        proxies = proxies or []
        nginx_home = self.binary_locator.nginx_home()
        logs_dir = self.nginx_logs_dir()
        runtime_dir = self.nginx_runtime_dir()
        self._ensure_nginx_dirs()
        site_includes = [f'        include "{self.site_config_paths(site)["nginx"]}";' for site in sites]
        node_includes = [f'        include "{self.node_project_config_paths(project)["nginx"]}";' for project in node_projects]
        proxy_includes = [f'        include "{self.proxy_config_paths(proxy)["nginx"]}";' for proxy in proxies]
        includes = "\n".join([*site_includes, *node_includes, *proxy_includes])
        mime_types_path = self._nginx_support_file("mime.types")
        settings = self.settings_service.get_settings()
        nginx_error_log = settings.nginx_error_log_path.strip() or str(logs_dir / "nginx-error.log")
        worker_processes = settings.nginx_worker_processes
        worker_connections = settings.nginx_worker_connections
        keepalive_timeout = settings.nginx_keepalive_timeout
        client_max_body_size = settings.nginx_client_max_body_size
        sendfile = "on" if settings.nginx_sendfile else "off"
        gzip = "on" if settings.nginx_gzip else "off"
        server_tokens = "on" if settings.nginx_server_tokens else "off"
        return (
            f'pid "{runtime_dir / "nginx.pid"}";\n'
            f'error_log "{nginx_error_log}";\n'
            f"worker_processes {worker_processes};\n"
            f'events {{\n'
            f"    worker_connections {worker_connections};\n"
            f"}}\n"
            f"http {{\n"
            f'    include "{mime_types_path}";\n'
            f"    default_type application/octet-stream;\n"
            f"    sendfile {sendfile};\n"
            f"    gzip {gzip};\n"
            f"    server_tokens {server_tokens};\n"
            f"    client_max_body_size {client_max_body_size};\n"
            f"    keepalive_timeout {keepalive_timeout};\n"
            f'    client_body_temp_path "{runtime_dir / "client_body_temp"}";\n'
            f'    proxy_temp_path "{runtime_dir / "proxy_temp"}";\n'
            f'    fastcgi_temp_path "{runtime_dir / "fastcgi_temp"}";\n'
            f'    uwsgi_temp_path "{runtime_dir / "uwsgi_temp"}";\n'
            f'    scgi_temp_path "{runtime_dir / "scgi_temp"}";\n'
            f"{self.nginx_phpmyadmin_block()}\n"
            f"{includes}\n"
            f"}}\n"
        )

    def nginx_phpmyadmin_block(self) -> str:
        phpmyadmin_root = self.phpmyadmin_root()
        backend_port = self.phpmyadmin_fastcgi_port()
        fastcgi_params_path = self._nginx_support_file("fastcgi_params")
        escaped_root = str(phpmyadmin_root).replace("\\", "\\\\")
        return (
            f"    server {{\n"
            f"        listen {self.settings_service.get_settings().apache_port};\n"
            f"        server_name {self.phpmyadmin_domain()};\n"
            f"        location = {self.phpmyadmin_route().rstrip('/')} {{\n"
            f"            return 301 {self.phpmyadmin_route()};\n"
            f"        }}\n"
            f"        location = {self.phpmyadmin_route()} {{\n"
            f"            return 302 {self.phpmyadmin_route()}index.php;\n"
            f"        }}\n"
            f"        location /phpmyadmin/ {{\n"
            f'            alias "{phpmyadmin_root}/";\n'
            f"            index index.php index.html;\n"
            f"            try_files $uri $uri/ /phpmyadmin/index.php?$query_string;\n"
            f"        }}\n"
            f"        location ~ ^/phpmyadmin/(.+\\.php)$ {{\n"
            f'            include "{fastcgi_params_path}";\n'
            f"            fastcgi_pass 127.0.0.1:{backend_port};\n"
            f'            fastcgi_param SCRIPT_FILENAME "{escaped_root}/$1";\n'
            f"            fastcgi_param SCRIPT_NAME /phpmyadmin/$1;\n"
            f"        }}\n"
            f"    }}\n"
        )

    def write_nginx_stack_config(self, sites: list[Site], node_projects: list[NodeProject] | None = None, proxies: list[Proxy] | None = None, port: int = 8080) -> str:
        node_projects = node_projects or []
        proxies = proxies or []
        self._ensure_nginx_dirs()
        self._prune_stale_site_configs(sites, node_projects, proxies)
        config_path = self.nginx_main_config_path()
        config_path.write_text(self.nginx_main_config(sites, node_projects=node_projects, proxies=proxies, port=port), encoding="utf-8")
        for site in sites:
            self.site_config_paths(site)["nginx"].write_text(self.nginx_server_block(site, port=port), encoding="utf-8")
        for project in node_projects:
            self.node_project_config_paths(project)["nginx"].write_text(
                self.nginx_node_proxy_server_block(project, port=port),
                encoding="utf-8",
            )
        for proxy in proxies:
            self.proxy_config_paths(proxy)["nginx"].write_text(self.nginx_proxy_server_block(proxy, port), encoding="utf-8")
        return str(config_path)

    def node_project_ssl_paths(self, project: NodeProject) -> tuple[Path, Path]:
        certs_dir = self.ssl_certs_dir()
        return certs_dir / f"{project.id}.crt", certs_dir / f"{project.id}.key"

    def node_project_ssl_exists(self, project: NodeProject) -> bool:
        cert_path, key_path = self.node_project_ssl_paths(project)
        return cert_path.exists() and key_path.exists()

    def ensure_node_project_ssl_certificate(self, project: NodeProject) -> OperationResult:
        cert_path, key_path = self.node_project_ssl_paths(project)
        self.ssl_certs_dir().mkdir(parents=True, exist_ok=True)
        if cert_path.exists() and key_path.exists() and self._certificate_has_domains(cert_path, [project.local_domain]):
            return OperationResult(True, "SSL certificate already exists.", {"cert_path": str(cert_path), "key_path": str(key_path)})
        cert_path.unlink(missing_ok=True)
        key_path.unlink(missing_ok=True)

        primary = project.local_domain
        config_text = (
            "[req]\n"
            "distinguished_name = req_distinguished_name\n"
            "x509_extensions = v3_req\n"
            "prompt = no\n"
            "\n"
            "[req_distinguished_name]\n"
            f"CN = {primary}\n"
            "\n"
            "[v3_req]\n"
            f"subjectAltName = DNS:{primary}\n"
            "basicConstraints = critical, CA:true\n"
            "keyUsage = critical, keyCertSign, cRLSign, digitalSignature\n"
            "extendedKeyUsage = serverAuth\n"
        )
        openssl_bin = self.openssl_binary()
        try:
            with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False, suffix=".cnf") as handle:
                handle.write(config_text)
                config_path = Path(handle.name)
            subprocess.run(
                [
                    openssl_bin,
                    "req",
                    "-x509",
                    "-nodes",
                    "-newkey",
                    "rsa:2048",
                    "-days",
                    "825",
                    "-keyout",
                    str(key_path),
                    "-out",
                    str(cert_path),
                    "-config",
                    str(config_path),
                    "-extensions",
                    "v3_req",
                ],
                check=True,
                capture_output=True,
                text=True,
                env=self.openssl_environment(),
            )
            return OperationResult(True, "Created self-signed SSL certificate.", {"cert_path": str(cert_path), "key_path": str(key_path)})
        except subprocess.CalledProcessError as exc:
            details = exc.stderr.strip() or exc.stdout.strip() or f"exit code {exc.returncode}"
            return OperationResult(False, f"SSL certificate generation failed: {details}")
        except Exception as exc:
            return OperationResult(False, f"SSL certificate generation failed: {exc}")
        finally:
            try:
                if "config_path" in locals():
                    config_path.unlink(missing_ok=True)
            except Exception:
                pass

    def _ensure_apache_dirs(self) -> None:
        self.apache_config_dir().mkdir(parents=True, exist_ok=True)
        self.apache_logs_dir().mkdir(parents=True, exist_ok=True)
        self.apache_runtime_dir().mkdir(parents=True, exist_ok=True)
        # Backward-compatible fallback for older generated Apache configs that
        # still reference the legacy shared apache paths.
        (self.runtime_paths.logs_dir / "apache").mkdir(parents=True, exist_ok=True)
        (self.runtime_paths.runtime_dir / "apache").mkdir(parents=True, exist_ok=True)
        (self.runtime_paths.runtime_dir / "php" / "cgi-bin").mkdir(parents=True, exist_ok=True)

    def _ensure_nginx_dirs(self) -> None:
        self.nginx_config_dir().mkdir(parents=True, exist_ok=True)
        self.nginx_logs_dir().mkdir(parents=True, exist_ok=True)
        self.nginx_runtime_dir().mkdir(parents=True, exist_ok=True)
        for name in ("client_body_temp", "proxy_temp", "fastcgi_temp", "uwsgi_temp", "scgi_temp"):
            (self.nginx_runtime_dir() / name).mkdir(parents=True, exist_ok=True)

    def _prune_stale_site_configs(self, sites: list[Site], node_projects: list[NodeProject], proxies: list[Proxy] | None = None) -> None:
        active_site_ids = {site.id for site in sites}
        active_node_ids = {project.id for project in node_projects}
        active_proxy_ids = {proxy.id for proxy in proxies or []}
        config_dir = self.runtime_paths.sites_config_dir
        if not config_dir.exists():
            return
        for path in config_dir.glob("*.conf"):
            name = path.name
            if name.endswith(".proxy.apache.conf"):
                if name.removesuffix(".proxy.apache.conf") not in active_proxy_ids:
                    path.unlink(missing_ok=True)
                continue
            if name.endswith(".proxy.nginx.conf"):
                if name.removesuffix(".proxy.nginx.conf") not in active_proxy_ids:
                    path.unlink(missing_ok=True)
                continue
            if name.endswith(".node.apache.conf"):
                node_id = name.removesuffix(".node.apache.conf")
                if node_id not in active_node_ids:
                    path.unlink(missing_ok=True)
                continue
            if name.endswith(".node.nginx.conf"):
                node_id = name.removesuffix(".node.nginx.conf")
                if node_id not in active_node_ids:
                    path.unlink(missing_ok=True)
                continue
            if name.endswith(".apache.conf"):
                site_id = name.removesuffix(".apache.conf")
                if site_id not in active_site_ids:
                    path.unlink(missing_ok=True)
                continue
            if name.endswith(".nginx.conf"):
                site_id = name.removesuffix(".nginx.conf")
                if site_id not in active_site_ids:
                    path.unlink(missing_ok=True)

    def _nginx_support_file(self, filename: str) -> Path:
        nginx_home = self.binary_locator.nginx_home()
        candidates = [
            nginx_home / "conf" / filename,
            nginx_home / filename,
            nginx_home / ".bottle" / "etc" / "nginx" / filename,
            nginx_home / "etc" / "nginx" / filename,
        ]
        for candidate in candidates:
            if candidate.exists():
                return candidate
        return nginx_home / "conf" / filename

    def php_cgi_wrapper_path(self, site: Site) -> Path:
        return self.runtime_paths.runtime_dir / "php" / "cgi-bin" / f"{site.id}-php-cgi"

    def php_fastcgi_port(self, requested_version: str) -> int:
        runtime = self.binary_locator.php_runtime(requested_version)
        token = runtime.label if runtime is not None else requested_version
        seed = sum((index + 1) * ord(char) for index, char in enumerate(token))
        return 10000 + (seed % 40000)

    def php_fastcgi_port_for_site(self, site: Site) -> int:
        runtime = self.binary_locator.php_runtime(site.php_version)
        token = runtime.label if runtime is not None else site.php_version
        seed_source = f"site-{site.id}-{token}"
        seed = sum((index + 1) * ord(char) for index, char in enumerate(seed_source))
        return 10000 + (seed % 40000)

    def php_cgi_wrapper(self, site: Site) -> str:
        runtime = self.binary_locator.php_runtime(site.php_version)
        if runtime is None:
            raise ValueError(f"No bundled PHP runtime available for version {site.php_version}")
        log_path = self.php_runtime_log_path(runtime.version)
        ext_dir = self._php_extension_dir(runtime)
        return (
            "#!/bin/sh\n"
            f'PHPRC="{runtime.ini_dir}"\n'
            'PHP_INI_SCAN_DIR=""\n'
            'REDIRECT_STATUS="1"\n'
            "export PHPRC PHP_INI_SCAN_DIR REDIRECT_STATUS\n"
            f'exec "{runtime.php_cgi_path}" -d "extension_dir={ext_dir}" -d cgi.force_redirect=0 -d pcre.jit=0 -d log_errors=1 -d "error_log={log_path}" "$@"\n'
        )

    def phpmyadmin_php_cgi_wrapper(self) -> str:
        runtime = self.phpmyadmin_runtime()
        if runtime is None:
            raise ValueError("No bundled PHP runtime available for phpMyAdmin")
        log_path = self.php_runtime_log_path(runtime.version)
        ext_dir = self._php_extension_dir(runtime)
        return (
            "#!/bin/sh\n"
            f'PHPRC="{runtime.ini_dir}"\n'
            'PHP_INI_SCAN_DIR=""\n'
            'REDIRECT_STATUS="1"\n'
            "export PHPRC PHP_INI_SCAN_DIR REDIRECT_STATUS\n"
            f'exec "{runtime.php_cgi_path}" -d "extension_dir={ext_dir}" -d cgi.force_redirect=0 -d pcre.jit=0 -d log_errors=1 -d "error_log={log_path}" "$@"\n'
        )

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
            for child in [item for item in base.iterdir() if item.is_dir()]:
                if any(item.is_file() and item.suffix == ".so" for item in child.glob("*.so")):
                    return child
        opcache_hits = list(home.glob("**/opcache.so"))
        if opcache_hits:
            return opcache_hits[0].parent
        return direct_candidates[0]

    def php_runtime_log_path(self, version: str) -> Path:
        settings = self.settings_service.get_settings()
        log_path_value = (settings.php_runtime_log_dir or "").strip()
        safe_version = version.strip().replace("/", "-").replace("\\", "-")
        if not log_path_value:
            base_dir = self.runtime_paths.logs_dir / "php"
        else:
            log_path = Path(log_path_value).expanduser()
            if log_path.suffix:
                base_dir = log_path.parent
            elif log_path.name == "php.log":
                base_dir = log_path.parent
            else:
                base_dir = log_path
        return base_dir / safe_version / "php.log"

    def write_php_cgi_wrapper(self, site: Site) -> str:
        self._ensure_apache_dirs()
        self.php_runtime_log_path(site.php_version).parent.mkdir(parents=True, exist_ok=True)
        wrapper_path = self.php_cgi_wrapper_path(site)
        wrapper_path.write_text(self.php_cgi_wrapper(site), encoding="utf-8")
        os.chmod(wrapper_path, 0o755)
        return str(wrapper_path)

    def write_phpmyadmin_php_cgi_wrapper(self) -> str:
        self._ensure_apache_dirs()
        runtime = self.phpmyadmin_runtime()
        if runtime is not None:
            self.php_runtime_log_path(runtime.version).parent.mkdir(parents=True, exist_ok=True)
        wrapper_path = self.phpmyadmin_wrapper_path()
        wrapper_path.write_text(self.phpmyadmin_php_cgi_wrapper(), encoding="utf-8")
        os.chmod(wrapper_path, 0o755)
        return str(wrapper_path)

    def phpmyadmin_config(self) -> str:
        settings = self.settings_service.get_settings()
        secret_seed = f"server-engine-{settings.active_phpmyadmin_version or 'phpmyadmin'}-{self.runtime_paths.root}"
        secret = hashlib.sha256(secret_seed.encode("utf-8")).hexdigest()
        temp_dir = self.phpmyadmin_root() / "tmp"
        return (
            "<?php\n"
            "$cfg['blowfish_secret'] = '" + secret.replace("'", "\\'") + "';\n"
            "$i = 1;\n"
            "$cfg['Servers'][$i]['auth_type'] = 'config';\n"
            "$cfg['Servers'][$i]['host'] = '127.0.0.1';\n"
            "$cfg['Servers'][$i]['port'] = '" + str(settings.database_port) + "';\n"
            "$cfg['Servers'][$i]['user'] = 'root';\n"
            "$cfg['Servers'][$i]['password'] = '" + settings.database_root_password.replace("'", "\\'") + "';\n"
            "$cfg['Servers'][$i]['AllowNoPassword'] = true;\n"
            "$cfg['PmaAbsoluteUri'] = '" + self.phpmyadmin_base_url() + "';\n"
            "$cfg['TempDir'] = '" + str(temp_dir).replace("'", "\\'") + "';\n"
        )

    def write_phpmyadmin_config(self) -> str:
        self.phpmyadmin_config_dir().mkdir(parents=True, exist_ok=True)
        config_path = self.phpmyadmin_config_path()
        config_text = self.phpmyadmin_config()
        config_path.write_text(config_text, encoding="utf-8")
        phpmyadmin_root = self.phpmyadmin_root()
        phpmyadmin_root.mkdir(parents=True, exist_ok=True)
        (phpmyadmin_root / "tmp").mkdir(parents=True, exist_ok=True)
        (phpmyadmin_root / "upload").mkdir(parents=True, exist_ok=True)
        (phpmyadmin_root / "save").mkdir(parents=True, exist_ok=True)
        (phpmyadmin_root / "config.inc.php").write_text(config_text, encoding="utf-8")
        return str(config_path)

    def ssl_certs_dir(self) -> Path:
        return self.runtime_paths.config_dir / "ssl" / "certs"

    def _certificate_has_domains(self, cert_path: Path, domains: list[str]) -> bool:
        openssl_bin = self.openssl_binary()
        try:
            completed = subprocess.run(
                [openssl_bin, "x509", "-in", str(cert_path), "-noout", "-text"],
                capture_output=True,
                text=True,
                check=False,
                env=self.openssl_environment(),
            )
            return (
                completed.returncode == 0
                and all(f"DNS:{domain}" in completed.stdout for domain in domains)
                and "CA:TRUE" in completed.stdout
            )
        except OSError:
            return False

    def site_ssl_paths(self, site: Site) -> tuple[Path, Path]:
        certs_dir = self.ssl_certs_dir()
        return certs_dir / f"{site.id}.crt", certs_dir / f"{site.id}.key"

    def site_ssl_exists(self, site: Site) -> bool:
        cert_path, key_path = self.site_ssl_paths(site)
        return cert_path.exists() and key_path.exists()

    def ensure_site_ssl_certificate(self, site: Site) -> OperationResult:
        cert_path, key_path = self.site_ssl_paths(site)
        self.ssl_certs_dir().mkdir(parents=True, exist_ok=True)
        if cert_path.exists() and key_path.exists() and self._certificate_has_domains(cert_path, site.all_domains()):
            return OperationResult(True, "SSL certificate already exists.", {"cert_path": str(cert_path), "key_path": str(key_path)})
        cert_path.unlink(missing_ok=True)
        key_path.unlink(missing_ok=True)

        primary = site.local_domain
        san_value = ",".join(f"DNS:{domain}" for domain in site.all_domains())
        config_text = (
            "[req]\n"
            "distinguished_name = req_distinguished_name\n"
            "x509_extensions = v3_req\n"
            "prompt = no\n"
            "\n"
            "[req_distinguished_name]\n"
            f"CN = {primary}\n"
            "\n"
            "[v3_req]\n"
            f"subjectAltName = {san_value}\n"
            "basicConstraints = critical, CA:true\n"
            "keyUsage = critical, keyCertSign, cRLSign, digitalSignature\n"
            "extendedKeyUsage = serverAuth\n"
        )
        openssl_bin = self.openssl_binary()
        try:
            with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False, suffix=".cnf") as handle:
                handle.write(config_text)
                config_path = Path(handle.name)
            subprocess.run(
                [
                    openssl_bin,
                    "req",
                    "-x509",
                    "-nodes",
                    "-newkey",
                    "rsa:2048",
                    "-days",
                    "825",
                    "-keyout",
                    str(key_path),
                    "-out",
                    str(cert_path),
                    "-config",
                    str(config_path),
                    "-extensions",
                    "v3_req",
                ],
                check=True,
                capture_output=True,
                text=True,
                env=self.openssl_environment(),
            )
            return OperationResult(True, "Created self-signed SSL certificate.", {"cert_path": str(cert_path), "key_path": str(key_path)})
        except subprocess.CalledProcessError as exc:
            details = exc.stderr.strip() or exc.stdout.strip() or f"exit code {exc.returncode}"
            return OperationResult(False, f"SSL certificate generation failed: {details}")
        except Exception as exc:
            return OperationResult(False, f"SSL certificate generation failed: {exc}")
        finally:
            try:
                if "config_path" in locals():
                    config_path.unlink(missing_ok=True)
            except Exception:
                pass
