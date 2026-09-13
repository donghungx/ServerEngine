from __future__ import annotations


def test_php_runtime_service_lists_versions(container) -> None:
    versions = container.php_runtime_service.list_versions()

    assert "8.2.0" in versions
    assert "8.3.0" in versions


def test_php_runtime_service_resolves_prefix_version(container) -> None:
    runtime = container.php_runtime_service.require_runtime("8.2")

    assert runtime.version == "8.2.0"
    assert runtime.php_cgi_path.endswith("/8.2.0/bin/php-cgi")
