from __future__ import annotations

from server_engine.core.models import FrameworkPreset


def test_create_update_delete_site(container) -> None:
    created = container.site_service.create_site(
        name="Demo",
        local_domain="demo.engine",
        project_path="/tmp/demo",
        framework_preset=FrameworkPreset.LARAVEL,
        tags=["api", "demo"],
    )

    assert created.name == "Demo"
    assert created.framework_preset == FrameworkPreset.LARAVEL
    assert created.server_type.value == "apache"
    assert container.site_service.list_sites()[0].local_domain == "demo.engine"
    hosts_path = container.hosts_gateway.hosts_path
    assert "demo.engine" in hosts_path.read_text(encoding="utf-8")

    updated = container.site_service.update_site(created.id, notes="Updated", web_root="public_html", php_version="8.2")
    assert updated.notes == "Updated"
    assert updated.web_root == "public_html"
    assert updated.php_version == "8.2.0"

    deleted = container.site_service.delete_site(created.id)
    assert deleted is True
    assert container.site_service.list_sites() == []
    assert "demo.engine" not in hosts_path.read_text(encoding="utf-8")


def test_create_site_rejects_duplicate_domain(container) -> None:
    container.site_service.create_site(name="First", local_domain="dup.engine", project_path="/tmp/one")

    try:
        container.site_service.create_site(name="Second", local_domain="dup.engine", project_path="/tmp/two")
    except ValueError as exc:
        assert "Local domain already exists" in str(exc)
    else:
        raise AssertionError("Expected duplicate domain validation to fail")


def test_create_site_requires_database_name_when_enabled(container) -> None:
    try:
        container.site_service.create_site(
            name="Bad",
            local_domain="bad.engine",
            project_path="/tmp/bad",
            database_enabled=True,
        )
    except ValueError as exc:
        assert "Database name is required" in str(exc)
    else:
        raise AssertionError("Expected validation error")


def test_create_site_rejects_missing_php_runtime(container) -> None:
    try:
        container.site_service.create_site(name="Bad", local_domain="bad.engine", project_path="/tmp/bad", php_version="9.9")
    except ValueError as exc:
        assert "PHP runtime not available" in str(exc)
    else:
        raise AssertionError("Expected PHP runtime validation error")


def test_update_site_replaces_hosts_entry(container) -> None:
    created = container.site_service.create_site(name="Demo", local_domain="demo.engine", project_path="/tmp/demo")

    container.site_service.update_site(created.id, local_domain="renamed.engine")

    hosts_content = container.hosts_gateway.hosts_path.read_text(encoding="utf-8")
    assert "demo.engine" not in hosts_content
    assert "renamed.engine" in hosts_content


def test_hosts_block_writes_one_domain_per_loopback_line(container) -> None:
    container.hosts_gateway.sync_serverengine_block(["alpha.engine", "beta.engine"])

    hosts_content = container.hosts_gateway.hosts_path.read_text(encoding="utf-8")

    assert (
        "#Start ServerEngine\n"
        "127.0.0.1 alpha.engine\n"
        "::1 alpha.engine\n"
        "127.0.0.1 beta.engine\n"
        "::1 beta.engine\n"
        "#End ServerEngine\n"
    ) in hosts_content
    assert "127.0.0.1 alpha.engine beta.engine" not in hosts_content
    assert "::1 alpha.engine beta.engine" not in hosts_content


def test_site_can_use_project_root_as_web_root(container) -> None:
    site = container.site_service.create_site(
        name="Root",
        local_domain="root.engine",
        project_path="/tmp/root-site",
        web_root="/",
    )

    assert site.web_root == "."
    assert str(site.document_root()) == "/tmp/root-site"
