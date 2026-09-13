from __future__ import annotations

from server_engine.core.models import Site


def test_config_generation_contains_domain_and_root(container) -> None:
    site = Site.create(name="Demo", local_domain="demo.engine", project_path="/projects/demo", php_version="8.2.0")

    apache = container.config_service.apache_virtual_host(site)
    nginx = container.config_service.nginx_server_block(site)
    php_fpm = container.config_service.php_fpm_pool(site)
    wrapper = container.config_service.php_cgi_wrapper(site)

    assert "ServerName demo.engine" in apache
    assert 'DocumentRoot "/projects/demo/public"' in apache
    assert 'Action application/x-httpd-php "/__server_engine__/cgi/' in apache
    assert "server_name demo.engine;" in nginx
    assert "fastcgi_pass 127.0.0.1:" in nginx
    assert 'root "/projects/demo/public";' in nginx
    assert f"[{site.id}]" in php_fpm
    assert "listen =" in php_fpm
    assert 'exec "' in wrapper
    assert "php-cgi" in wrapper


def test_create_site_writes_config_files(container) -> None:
    site = container.site_service.create_site(name="Demo", local_domain="demo.engine", project_path="/tmp/demo")
    paths = container.config_service.site_config_paths(site)
    wrapper_path = container.config_service.php_cgi_wrapper_path(site)

    assert paths["apache"].exists()
    assert paths["nginx"].exists()
    assert paths["php_fpm"].exists()
    assert wrapper_path.exists()
