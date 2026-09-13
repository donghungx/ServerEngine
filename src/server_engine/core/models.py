from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
from typing import Any
from uuid import uuid4
from urllib.parse import urlparse


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def normalize_web_root(value: str | None) -> str:
    if value is None:
        return "public"
    cleaned = value.strip()
    if not cleaned:
        return "public"
    if cleaned in {"/", "."}:
        return "."
    return cleaned.strip("/")


def normalize_domains(primary_domain: str, aliases: list[str] | None = None) -> tuple[str, list[str]]:
    primary = primary_domain.strip().lower()
    normalized_aliases: list[str] = []
    for value in aliases or []:
        cleaned = value.strip().lower()
        if cleaned and cleaned != primary and cleaned not in normalized_aliases:
            normalized_aliases.append(cleaned)
    return primary, normalized_aliases


class FrameworkPreset(str, Enum):
    GENERIC_PHP = "generic_php"
    LARAVEL = "laravel"
    WORDPRESS = "wordpress"
    CUSTOM = "custom"
    SYMFONY = "symfony"
    CODEIGNITER = "codeigniter"


class ServerType(str, Enum):
    APACHE = "apache"
    NGINX = "nginx"


class SiteStatus(str, Enum):
    INACTIVE = "inactive"
    ACTIVE = "active"
    ERROR = "error"

class NodeProjectStatus(str, Enum):
    STOPPED = "stopped"
    RUNNING = "running"
    ERROR = "error"


@dataclass(slots=True)
class Proxy:
    """A domain mapping to an already-running local service."""

    id: str
    name: str
    local_domain: str
    target: str
    notes: str = ""
    ssl_enabled: bool = False
    ssl_enforce_tls: bool = False
    ssl_allow_http: bool = True
    created_at: str = field(default_factory=utc_now)
    updated_at: str = field(default_factory=utc_now)

    @classmethod
    def create(cls, name: str, local_domain: str, target: str, notes: str = "") -> "Proxy":
        proxy = cls(str(uuid4()), name.strip(), local_domain.strip().lower(), target.strip(), notes.strip())
        proxy.validate()
        return proxy

    def validate(self) -> None:
        if not self.name:
            raise ValueError("Proxy name is required.")
        if "." not in self.local_domain:
            raise ValueError("Domain must be a valid development hostname.")
        if not self.target:
            raise ValueError("Proxy target is required.")
        if self.target.startswith("unix:"):
            if not self.target.removeprefix("unix:").startswith("/"):
                raise ValueError("Unix socket targets must use unix:/absolute/path.sock.")
        else:
            parsed = urlparse(self.target)
            if parsed.scheme not in {"http", "https"} or not parsed.netloc:
                raise ValueError("Proxy target must be an http(s) URL or unix:/absolute/path.sock.")

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


class ServiceKind(str, Enum):
    APACHE = "apache"
    NGINX = "nginx"
    PHP_FPM = "php_fpm"
    DATABASE = "database"
    REDIS = "redis"
    MAILPIT = "mailpit"

class ServiceState(str, Enum):
    STOPPED = "stopped"
    STARTING = "starting"
    RUNNING = "running"
    STOPPING = "stopping"
    ERROR = "error"


@dataclass(slots=True)
class Site:
    id: str
    name: str
    local_domain: str
    project_path: str
    web_root: str
    domain_aliases: list[str] = field(default_factory=list)
    php_version: str = "8.3"
    framework_preset: FrameworkPreset = FrameworkPreset.GENERIC_PHP
    server_type: ServerType = ServerType.APACHE
    ssl_enabled: bool = False
    ssl_enforce_tls: bool = False
    ssl_allow_http: bool = True
    database_enabled: bool = False
    database_name: str | None = None
    database_user: str | None = None
    notes: str = ""
    created_at: str = field(default_factory=utc_now)
    updated_at: str = field(default_factory=utc_now)
    status: SiteStatus = SiteStatus.INACTIVE
    tags: list[str] = field(default_factory=list)

    @classmethod
    def create(
        cls,
        name: str,
        local_domain: str,
        project_path: str,
        web_root: str | None = None,
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
    ) -> "Site":
        site = cls(
            id=str(uuid4()),
            name=name.strip(),
            local_domain=normalize_domains(local_domain, [])[0],
            domain_aliases=[],
            project_path=str(Path(project_path).expanduser()),
            web_root=normalize_web_root(web_root),
            php_version=php_version.strip(),
            framework_preset=framework_preset,
            server_type=server_type,
            ssl_enabled=ssl_enabled,
            ssl_enforce_tls=ssl_enforce_tls,
            ssl_allow_http=ssl_allow_http,
            database_enabled=database_enabled,
            database_name=database_name.strip() if database_name else None,
            database_user=database_user.strip() if database_user else None,
            notes=notes.strip(),
            tags=sorted({tag.strip() for tag in tags or [] if tag.strip()}),
        )
        site.validate()
        return site

    def validate(self) -> None:
        if not self.name:
            raise ValueError("Site name is required.")
        self.local_domain, self.domain_aliases = normalize_domains(self.local_domain, self.domain_aliases)
        for domain in self.all_domains():
            if "." not in domain or domain.startswith(".") or domain.endswith("."):
                raise ValueError("Local domain must be a valid development hostname.")
        if not self.project_path:
            raise ValueError("Project path is required.")
        self.web_root = normalize_web_root(self.web_root)
        if not self.web_root:
            raise ValueError("Web root is required.")
        if self.database_enabled and not self.database_name:
            raise ValueError("Database name is required when database support is enabled.")

    def touch(self) -> None:
        self.updated_at = utc_now()

    def document_root(self) -> Path:
        project_root = Path(self.project_path)
        if self.web_root == ".":
            return project_root
        return project_root / self.web_root

    def all_domains(self) -> list[str]:
        return [self.local_domain, *self.domain_aliases]

    def to_dict(self) -> dict[str, Any]:
        data = asdict(self)
        data["framework_preset"] = self.framework_preset.value
        data["server_type"] = self.server_type.value
        data["status"] = self.status.value
        data["web_root_display"] = "/" if self.web_root == "." else self.web_root
        return data


@dataclass(slots=True)
class NodeProject:
    id: str
    name: str
    local_domain: str
    project_path: str
    document_root: str
    node_version: str
    run_script_name: str
    run_script_command: str
    port: int
    notes: str = ""
    ssl_enabled: bool = False
    ssl_enforce_tls: bool = False
    ssl_allow_http: bool = True
    created_at: str = field(default_factory=utc_now)
    updated_at: str = field(default_factory=utc_now)
    status: NodeProjectStatus = NodeProjectStatus.STOPPED

    @classmethod
    def create(
        cls,
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
    ) -> "NodeProject":
        project = cls(
            id=str(uuid4()),
            name=name.strip(),
            local_domain=local_domain.strip().lower(),
            project_path=str(Path(project_path).expanduser()),
            document_root=str(Path(document_root).expanduser()),
            node_version=node_version.strip(),
            run_script_name=run_script_name.strip(),
            run_script_command=run_script_command.strip(),
            port=int(port),
            notes=notes.strip(),
            ssl_enabled=bool(ssl_enabled),
            ssl_enforce_tls=bool(ssl_enforce_tls),
            ssl_allow_http=bool(ssl_allow_http),
        )
        project.validate()
        return project

    def validate(self) -> None:
        if not self.name:
            raise ValueError("Project name is required.")
        if "." not in self.local_domain:
            raise ValueError("Domain must be a valid development hostname.")
        if not self.project_path:
            raise ValueError("Project path is required.")
        if not self.document_root:
            raise ValueError("Document root is required.")
        if not self.node_version:
            raise ValueError("Node version is required.")
        if not self.run_script_name:
            raise ValueError("Run option is required.")
        if not self.run_script_command:
            raise ValueError("Run command is required.")
        if self.port < 1 or self.port > 65535:
            raise ValueError("Port must be between 1 and 65535.")

    def touch(self) -> None:
        self.updated_at = utc_now()

    def to_dict(self) -> dict[str, Any]:
        data = asdict(self)
        data["status"] = self.status.value
        return data


@dataclass(slots=True)
class AppSettings:
    app_name: str = "Server Engine"
    # Shipping defaults
    default_php_version: str = "8.3.30"
    default_mysql_version: str = "mysql-8.4.9"
    default_mariadb_version: str = "mariadb-12.2.2"
    default_redis_version: str = "redis-8.6.3"
    default_memcached_version: str = "memcached-1.6.41"
    default_mailpit_version: str = "mailpit-1.29.7"
    default_apache_version: str = "apache-2.4.67"
    default_nginx_version: str = "nginx-1.31.0"
    preferred_database_engine: str = "mysql"
    active_database_version: str | None = "mysql-8.4.9"
    active_node_version: str | None = "22.22.3"
    active_phpmyadmin_version: str | None = "5.2.3"
    phpmyadmin_php_version: str = "8.3.30"
    default_server_type: ServerType = ServerType.APACHE
    active_web_server: ServerType = ServerType.APACHE
    active_apache_version: str | None = None
    active_nginx_version: str | None = None
    cache_driver: str = "memcached"
    active_redis_version: str | None = None
    active_memcached_version: str | None = None
    active_mailpit_version: str | None = None
    active_mongodb_version: str | None = None
    active_postgresql_version: str | None = None

    # PHP runtime behavior
    php_runtime_log_to_file: bool = True
    php_runtime_log_to_screen: bool = False
    php_runtime_log_dir: str = ""

    # Ports and host/runtime controls
    apache_port: int = 80
    database_port: int = 3306
    redis_port: int = 6379
    mailpit_smtp_port: int = 1025
    mailpit_http_port: int = 8025
    auto_start_stack: bool = False
    auto_update_hosts: bool = True
    environment_root: str | None = None
    enable_simulated_processes: bool = True
    default_project_folder: str = "~/ServerEngine"
    phpmyadmin_hosts_registered: bool = False

    # Web server settings
    apache_enabled_modules: list[str] = field(default_factory=list)
    apache_error_log_path: str = ""
    nginx_worker_processes: str = "1"
    nginx_worker_connections: int = 1024
    nginx_keepalive_timeout: int = 65
    nginx_client_max_body_size: str = "64m"
    nginx_sendfile: bool = True
    nginx_gzip: bool = True
    nginx_server_tokens: bool = False
    nginx_error_log_path: str = ""

    # Database
    database_root_password: str = ""
    database_runtime_passwords: dict[str, str] = field(default_factory=dict)
    database_optimization: dict[str, int] = field(default_factory=lambda: {
        "key_buffer_size_mb": 16,
        "query_cache_size_mb": 64,
        "tmp_table_size_mb": 128,
        "innodb_buffer_pool_size_mb": 1024,
        "innodb_log_buffer_size_mb": 128,
        "sort_buffer_size_kb": 256,
        "read_buffer_size_kb": 256,
        "read_rnd_buffer_size_kb": 256,
        "join_buffer_size_kb": 256,
        "thread_stack_kb": 256,
        "binlog_cache_size_kb": 64,
        "thread_cache_size": 96,
        "table_open_cache": 1400,
        "max_connections": 160,
    })

    # Redis
    redis_password: str = ""
    redis_runtime_passwords: dict[str, str] = field(default_factory=dict)

    # UI/App behavior
    appearance_theme: str = "system"
    appearance_accent_color: str = "#007bff"
    appearance_language: str = "en"
    home_global_services: dict[str, bool] = field(default_factory=lambda: {
        "web": True,
        "database": True,
        "redis": False,
        "memcached": False,
        "mailpit": False,
    })
    bottom_terminal_panel_height: int = 260

    def to_dict(self) -> dict[str, Any]:
        data = asdict(self)
        data["default_server_type"] = self.default_server_type.value
        return data


@dataclass(slots=True)
class ServiceDefinition:
    id: str
    name: str
    kind: ServiceKind
    executable_name: str
    default_port: int
    executable_path: str | None = None
    arguments: list[str] = field(default_factory=list)
    working_directory: str | None = None
    log_path: str | None = None
    log_to_screen: bool = False
    environment: dict[str, str] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        data = asdict(self)
        data["kind"] = self.kind.value
        return data


@dataclass(slots=True)
class ServiceStatus:
    service_id: str
    state: ServiceState
    pid: int | None = None
    port: int | None = None
    message: str = ""
    started_at: str | None = None

    def to_dict(self) -> dict[str, Any]:
        data = asdict(self)
        data["state"] = self.state.value
        return data


@dataclass(slots=True)
class StackStatus:
    services: list[ServiceStatus]

    @property
    def overall_state(self) -> ServiceState:
        if any(service.state == ServiceState.ERROR for service in self.services):
            return ServiceState.ERROR
        if any(service.state == ServiceState.RUNNING for service in self.services):
            if all(service.state == ServiceState.RUNNING for service in self.services):
                return ServiceState.RUNNING
            return ServiceState.STARTING
        return ServiceState.STOPPED

    def to_dict(self) -> dict[str, Any]:
        return {
            "overall_state": self.overall_state.value,
            "services": [service.to_dict() for service in self.services],
        }


@dataclass(slots=True)
class LogSource:
    id: str
    name: str
    path: str
    category: str

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(slots=True)
class DatabaseConfig:
    engine: str
    host: str = "127.0.0.1"
    port: int = 3306
    username: str = "root"
    password: str = ""
    default_database: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(slots=True)
class DatabaseRuntime:
    id: str
    engine: str
    version: str
    label: str
    home: str
    server_path: str
    client_path: str | None = None
    config_template_path: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(slots=True)
class RedisRuntime:
    id: str
    version: str
    label: str
    home: str
    server_path: str
    client_path: str | None = None
    config_template_path: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(slots=True)
class MemcachedRuntime:
    id: str
    version: str
    label: str
    home: str
    server_path: str
    tool_path: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(slots=True)
class MailpitRuntime:
    id: str
    version: str
    label: str
    home: str
    server_path: str

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

@dataclass(slots=True)
class BackupRecord:
    id: str
    site_id: str
    created_at: str
    label: str
    archive_path: str
    includes_database: bool
    notes: str = ""

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(slots=True)
class PhpRuntime:
    version: str
    label: str
    home: str
    php_path: str
    php_cgi_path: str
    ini_dir: str

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(slots=True)
class RuntimePaths:
    root: Path
    bin_dir: Path
    config_dir: Path
    nginx_config_dir: Path
    php_config_dir: Path
    database_config_dir: Path
    redis_config_dir: Path
    sites_config_dir: Path
    logs_dir: Path
    data_dir: Path
    backups_dir: Path
    runtime_dir: Path
    temp_dir: Path
    db_path: Path

    def to_dict(self) -> dict[str, Any]:
        return {key: str(value) for key, value in asdict(self).items()}


@dataclass(slots=True)
class OperationResult:
    success: bool
    message: str
    payload: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)
