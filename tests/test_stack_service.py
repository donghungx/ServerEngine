from __future__ import annotations

from pathlib import Path

from server_engine.core.models import ServiceState, Site, SiteStatus


def test_stack_status_reports_missing_apache_binary(container) -> None:
    initial = container.stack_service.status()
    assert initial.overall_state == ServiceState.STOPPED
    assert "Apache binary not found" in initial.services[0].message


def test_apache_start_stop_with_fake_httpd(container) -> None:
    httpd = container.binary_locator.apache_httpd()
    httpd.parent.mkdir(parents=True, exist_ok=True)
    (container.binary_locator.apache_home() / "modules").mkdir(parents=True, exist_ok=True)
    (container.binary_locator.apache_home() / "conf").mkdir(parents=True, exist_ok=True)
    ((container.binary_locator.apache_home() / "conf") / "mime.types").write_text("", encoding="utf-8")
    httpd.write_text(
        "#!/bin/sh\n"
        "while [ $# -gt 0 ]; do\n"
        "  shift\n"
        "done\n"
        "trap 'exit 0' TERM INT\n"
        "while true; do\n"
        "  sleep 1\n"
        "done\n",
        encoding="utf-8",
    )
    httpd.chmod(0o755)

    started = container.stack_service.start_service("apache")
    assert started.state == ServiceState.RUNNING
    assert started.pid is not None

    status = container.stack_service.status()
    assert status.overall_state == ServiceState.RUNNING

    stopped = container.stack_service.stop_service("apache")
    assert stopped.state == ServiceState.STOPPED


def test_nginx_start_stop_with_fake_runtime(container) -> None:
    settings = container.settings_service.get_settings()
    settings.active_web_server = settings.active_web_server.__class__("nginx")
    container.settings_service.save_settings(settings)

    nginx = container.binary_locator.nginx_binary()
    nginx.parent.mkdir(parents=True, exist_ok=True)
    (container.binary_locator.nginx_home() / "conf").mkdir(parents=True, exist_ok=True)
    ((container.binary_locator.nginx_home() / "conf") / "mime.types").write_text("", encoding="utf-8")
    ((container.binary_locator.nginx_home() / "conf") / "fastcgi_params").write_text("", encoding="utf-8")
    nginx.write_text(
        "#!/bin/sh\n"
        "while [ $# -gt 0 ]; do\n"
        "  shift\n"
        "done\n"
        "trap 'exit 0' TERM INT\n"
        "while true; do\n"
        "  sleep 1\n"
        "done\n",
        encoding="utf-8",
    )
    nginx.chmod(0o755)

    php_runtime = container.binary_locator.php_runtime("8.2.0")
    assert php_runtime is not None
    Path(php_runtime.php_cgi_path).write_text(
        "#!/bin/sh\n"
        "while [ $# -gt 0 ]; do\n"
        "  shift\n"
        "done\n"
        "trap 'exit 0' TERM INT\n"
        "while true; do\n"
        "  sleep 1\n"
        "done\n",
        encoding="utf-8",
    )
    Path(php_runtime.php_cgi_path).chmod(0o755)

    site = Site.create(name="Demo", local_domain="demo.engine", project_path="/tmp/demo", php_version="8.2.0")
    site.status = SiteStatus.ACTIVE
    container.site_repository.save(site)

    started = container.stack_service.start_all()
    assert started.overall_state == ServiceState.RUNNING
    service_ids = {service.service_id for service in started.services}
    assert "nginx" in service_ids
    assert "php-cgi-8_2_0" in service_ids

    stopped = container.stack_service.stop_all()
    assert stopped.overall_state == ServiceState.STOPPED
