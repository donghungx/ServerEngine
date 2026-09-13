from types import SimpleNamespace
from unittest.mock import Mock

from server_engine.core.models import AppSettings
from server_engine.gui.dashboard_bridge.runtime_manager import RuntimeManagerMixin


def test_bootstrap_completion_publishes_refreshed_home_rows():
    bridge = SimpleNamespace(
        _required_runtime_bootstrap_progress=90,
        _home_service_items_cache=[{"label": "No runtime selected"}],
        homeServiceChanged=Mock(),
        dataChanged=Mock(),
        redisRuntimeFeedbackChanged=Mock(),
        appSettingsFeedbackChanged=Mock(),
    )
    observed = []

    def refresh():
        bridge._home_service_items_cache = [{"label": "Redis 8.6.3"}]

    bridge._refresh_home_service_items_cache = refresh
    bridge.homeServiceChanged.emit.side_effect = lambda: observed.extend(
        bridge._home_service_items_cache
    )
    RuntimeManagerMixin._on_required_runtime_bootstrap_completed(bridge, True, "Done")

    assert observed == [{"label": "Redis 8.6.3"}]
    assert bridge._required_runtime_bootstrap_open is False
    assert bridge._required_runtime_bootstrap_busy is False


def test_bootstrap_rebuilds_inventory_before_selecting_defaults():
    settings = AppSettings()
    versions = {
        "apache": settings.default_apache_version or "apache-2.4.67",
        "nginx": settings.default_nginx_version or "nginx-1.31.0",
        "php": settings.default_php_version or "8.3.30",
        "phpmyadmin": "5.2.3",
        "mysql": settings.default_mysql_version or "mysql-8.4.9",
        "redis": settings.default_redis_version or "redis-8.6.3",
        "mailpit": settings.default_mailpit_version or "mailpit-1.29.7",
        "memcached": settings.default_memcached_version or "memcached-1.6.41",
    }
    items = [dict(service=service, id=version, version=version)
             for service, version in versions.items()]
    installed = set()
    inventory = set()

    def rebuild(kind):
        service = "mysql" if kind == "database" else kind
        assert service in installed
        inventory.add(service)

    def select_defaults():
        assert inventory == set(versions)

    bridge = SimpleNamespace(
        _required_runtime_bootstrap_cache_valid=lambda: False,
        _container=SimpleNamespace(
            settings_service=SimpleNamespace(get_settings=lambda: settings),
            runtime_inventory_service=SimpleNamespace(clear_and_rebuild=rebuild, clear_and_rebuild_all=Mock()),
            php_runtime_service=SimpleNamespace(get_runtime=lambda version: None),
        ),
        _runtime_home_path=lambda service, version: None,
        _runtime_install_target_path=lambda item: SimpleNamespace(is_dir=lambda: False),
        runtimeManagerItems=lambda service: [],
        _fetch_runtime_manifest=lambda: {"items": items},
        _normalize_server_runtime_item=lambda item: item,
        _runtime_folder_name=lambda service, version: version,
        _runtime_inventory_kind=lambda service: "database" if service == "mysql" else service,
        _install_runtime_package=lambda item, overwrite, progress: installed.add(item["service"]),
        _ensure_required_runtime_default_settings=select_defaults,
        _write_required_runtime_bootstrap_cache=Mock(),
        appSettingsFeedbackChanged=Mock(),
    )
    RuntimeManagerMixin._run_required_runtime_bootstrap(bridge, Mock())
    assert inventory == set(versions)
    bridge._write_required_runtime_bootstrap_cache.assert_called_once()


def test_ready_cache_skips_startup_without_inventory_lookup(tmp_path):
    path = tmp_path / "required-runtimes.ready.json"
    bridge = SimpleNamespace(
        _container=SimpleNamespace(settings_service=SimpleNamespace(get_settings=AppSettings)),
        _required_runtime_bootstrap_cache_path=lambda: path,
        _required_runtime_bootstrap_busy=False,
    )
    RuntimeManagerMixin._write_required_runtime_bootstrap_cache(bridge)
    bridge._required_runtime_bootstrap_cache_valid = lambda: RuntimeManagerMixin._required_runtime_bootstrap_cache_valid(bridge)
    assert bridge._required_runtime_bootstrap_cache_valid()
    # No worker, runtime locator or modal state is needed with a ready cache.
    RuntimeManagerMixin.ensureRequiredRuntimesAtStartup(bridge)


def test_existing_runtimes_create_cache_without_manifest_or_download():
    cache_write = Mock()
    inventory = Mock()
    bridge = SimpleNamespace(
        _required_runtime_bootstrap_cache_valid=lambda: False,
        _container=SimpleNamespace(
            settings_service=SimpleNamespace(get_settings=AppSettings),
            runtime_inventory_service=inventory,
        ),
        _runtime_home_path=lambda service, version: "/installed/runtime",
        _ensure_required_runtime_default_settings=Mock(),
        _write_required_runtime_bootstrap_cache=cache_write,
        _required_runtime_bootstrap_open=False,
    )
    RuntimeManagerMixin._run_required_runtime_bootstrap(bridge, Mock())
    inventory.clear_and_rebuild_all.assert_called_once()
    cache_write.assert_called_once()
    assert not bridge._required_runtime_bootstrap_open
