from __future__ import annotations


def test_site_repository_round_trip(container) -> None:
    site = container.site_service.create_site(name="Repo", local_domain="repo.engine", project_path="/tmp/repo")
    loaded = container.site_repository.get(site.id)

    assert loaded is not None
    assert loaded.id == site.id
    assert loaded.local_domain == "repo.engine"


def test_settings_repository_defaults_and_save(container) -> None:
    settings = container.settings_service.get_settings()
    assert settings.app_name == "Server Engine"
    assert settings.apache_port == 8080
    assert settings.database_port == 3306

    settings.default_php_version = "8.4"
    settings.apache_port = 9090
    settings.active_database_version = "mysql-5.7.39"
    settings.database_port = 3307
    settings.auto_update_hosts = False
    container.settings_service.save_settings(settings)

    saved = container.settings_service.get_settings()
    assert saved.default_php_version == "8.4"
    assert saved.apache_port == 9090
    assert saved.active_database_version == "mysql-5.7.39"
    assert saved.database_port == 3307
    assert saved.auto_update_hosts is False
