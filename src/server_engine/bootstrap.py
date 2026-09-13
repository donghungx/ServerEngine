from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from server_engine.core.models import RuntimePaths
from server_engine.infrastructure.binary_locator import BinaryLocator
from server_engine.infrastructure.hosts import HostsGateway
from server_engine.infrastructure.paths import PathProvider
from server_engine.infrastructure.process_manager import ProcessManager
from server_engine.infrastructure.repositories.settings_repository import SettingsRepository
from server_engine.infrastructure.repositories.node_project_repository import NodeProjectRepository
from server_engine.infrastructure.repositories.site_repository import SiteRepository
from server_engine.infrastructure.repositories.proxy_repository import ProxyRepository
from server_engine.infrastructure.sqlite import SQLiteDatabase
from server_engine.services.app_cache_service import AppCacheService
from server_engine.services.config_service import ConfigService
from server_engine.services.database_runtime_service import DatabaseRuntimeService
from server_engine.services.database_service import DatabaseService
from server_engine.services.health_service import HealthService
from server_engine.services.log_service import LogService
from server_engine.services.license_service import LicenseService
from server_engine.services.php_runtime_service import PhpRuntimeService
from server_engine.services.redis_runtime_service import RedisRuntimeService
from server_engine.services.redis_service import RedisService
from server_engine.services.memcached_runtime_service import MemcachedRuntimeService
from server_engine.services.memcached_service import MemcachedService
from server_engine.services.settings_service import SettingsService
from server_engine.services.site_service import SiteService
from server_engine.services.node_project_service import NodeProjectService
from server_engine.services.node_project_runtime_service import NodeProjectRuntimeService
from server_engine.services.stack_service import StackService
from server_engine.services.mailpit_service import MailpitService
from server_engine.services.postgresql_service import PostgresqlService
from server_engine.services.mongodb_service import MongodbService
from server_engine.services.runtime_inventory_service import RuntimeInventoryService
from server_engine.services.proxy_service import ProxyService


@dataclass(slots=True)
class AppContainer:
    paths: PathProvider
    runtime_paths: RuntimePaths
    database: SQLiteDatabase
    site_repository: SiteRepository
    node_project_repository: NodeProjectRepository
    proxy_repository: ProxyRepository
    settings_repository: SettingsRepository
    binary_locator: BinaryLocator
    app_cache_service: AppCacheService
    runtime_inventory_service: RuntimeInventoryService
    php_runtime_service: PhpRuntimeService
    database_runtime_service: DatabaseRuntimeService
    redis_runtime_service: RedisRuntimeService
    memcached_runtime_service: MemcachedRuntimeService
    site_service: SiteService
    node_project_service: NodeProjectService
    proxy_service: ProxyService
    node_project_runtime_service: NodeProjectRuntimeService
    settings_service: SettingsService
    config_service: ConfigService
    process_manager: ProcessManager
    stack_service: StackService
    log_service: LogService
    license_service: LicenseService
    database_service: DatabaseService
    redis_service: RedisService
    memcached_service: MemcachedService
    health_service: HealthService
    hosts_gateway: HostsGateway
    mailpit_service: MailpitService
    postgresql_service: PostgresqlService
    mongodb_service: MongodbService


def build_container(runtime_root: Path | None = None) -> AppContainer:
    paths = PathProvider(runtime_root=runtime_root)
    runtime_paths = paths.ensure()

    database = SQLiteDatabase(runtime_paths.db_path)
    database.initialize()

    site_repository = SiteRepository(database)
    node_project_repository = NodeProjectRepository(database)
    proxy_repository = ProxyRepository(database)
    settings_repository = SettingsRepository(database)


    app_cache_service = AppCacheService(database)
    binary_locator = BinaryLocator(runtime_paths, app_cache_service)
    runtime_inventory_service = RuntimeInventoryService(binary_locator, app_cache_service)
    runtime_inventory_service.ensure_seeded()

    php_runtime_service = PhpRuntimeService(binary_locator)
    database_runtime_service = DatabaseRuntimeService(binary_locator)
    redis_runtime_service = RedisRuntimeService(binary_locator)
    memcached_runtime_service = MemcachedRuntimeService(binary_locator)

    settings_service = SettingsService(settings_repository, runtime_paths)
    binary_locator.set_settings_provider(settings_service.get_settings)

    config_service = ConfigService(runtime_paths, binary_locator, settings_service)
    process_manager = ProcessManager(runtime_paths)
    hosts_gateway = HostsGateway(runtime_paths)

    site_service = SiteService(
        site_repository,
        config_service,
        php_runtime_service,
        hosts_gateway,
        settings_service,
    )

    node_project_service = NodeProjectService(
        node_project_repository,
        site_repository,
        hosts_gateway,
        settings_service,
    )
    proxy_service = ProxyService(proxy_repository, site_repository, node_project_repository, hosts_gateway)

    node_project_runtime_service = NodeProjectRuntimeService(
        node_project_service,
        binary_locator,
        process_manager,
    )

    stack_service = StackService(
        process_manager,
        runtime_paths,
        binary_locator,
        config_service,
        site_service,
        node_project_service,
        proxy_service,
        settings_service,
        hosts_gateway,
    )

    log_service = LogService(runtime_paths)
    license_service = LicenseService(runtime_paths)

    database_service = DatabaseService(
        runtime_paths,
        settings_service,
        database_runtime_service,
        process_manager,
    )

    redis_service = RedisService(
        runtime_paths,
        settings_service,
        redis_runtime_service,
        process_manager,
    )

    memcached_service = MemcachedService(
        runtime_paths,
        settings_service,
        memcached_runtime_service,
        process_manager,
    )

    mailpit_service = MailpitService(
        settings_service,
        binary_locator,
        process_manager,
    )

    postgresql_service = PostgresqlService(
        runtime_paths,
        settings_service,
        database_runtime_service,
        process_manager,
    )

    mongodb_service = MongodbService(
        runtime_paths,
        settings_service,
        database_runtime_service,
        process_manager,
    )

    health_service = HealthService(stack_service)

    return AppContainer(
        paths=paths,
        runtime_paths=runtime_paths,
        database=database,
        site_repository=site_repository,
        node_project_repository=node_project_repository,
        proxy_repository=proxy_repository,
        settings_repository=settings_repository,
        binary_locator=binary_locator,
        app_cache_service=app_cache_service,
        runtime_inventory_service=runtime_inventory_service,
        php_runtime_service=php_runtime_service,
        database_runtime_service=database_runtime_service,
        redis_runtime_service=redis_runtime_service,
        memcached_runtime_service=memcached_runtime_service,
        site_service=site_service,
        node_project_service=node_project_service,
        proxy_service=proxy_service,
        node_project_runtime_service=node_project_runtime_service,
        settings_service=settings_service,
        config_service=config_service,
        process_manager=process_manager,
        stack_service=stack_service,
        log_service=log_service,
        license_service=license_service,
        database_service=database_service,
        redis_service=redis_service,
        memcached_service=memcached_service,
        mailpit_service=mailpit_service,
        postgresql_service=postgresql_service,
        mongodb_service=mongodb_service,
        health_service=health_service,
        hosts_gateway=hosts_gateway,
    )
