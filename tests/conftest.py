from __future__ import annotations

from pathlib import Path

import pytest

from server_engine.bootstrap import build_container


@pytest.fixture()
def container(tmp_path: Path):
    return build_container(runtime_root=tmp_path / "server-engine-home")


@pytest.fixture(autouse=True)
def isolate_project_prebuilt_apache(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.setenv("SERVER_ENGINE_APACHE_HOME", str(tmp_path / "apache-home"))
    monkeypatch.setenv("SERVER_ENGINE_NGINX_HOME", str(tmp_path / "nginx-home"))
    monkeypatch.setenv("SERVER_ENGINE_HOSTS_PATH", str(tmp_path / "hosts"))
    php_root = tmp_path / "php-root"
    for version in ("8.2.0", "8.3.0"):
        runtime = php_root / version
        (runtime / "bin").mkdir(parents=True, exist_ok=True)
        (runtime / "conf").mkdir(parents=True, exist_ok=True)
        (runtime / "bin" / "php").write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        (runtime / "bin" / "php-cgi").write_text("#!/bin/sh\nprintf 'Content-Type: text/plain\\n\\n'\nprintf 'PHP %s' \"" + version + "\"\n", encoding="utf-8")
        (runtime / "bin" / "php").chmod(0o755)
        (runtime / "bin" / "php-cgi").chmod(0o755)
    monkeypatch.setenv("SERVER_ENGINE_PHP_ROOT", str(php_root))
    nginx_home = tmp_path / "nginx-home"
    (nginx_home / "bin").mkdir(parents=True, exist_ok=True)
    (nginx_home / "conf").mkdir(parents=True, exist_ok=True)
    (nginx_home / "conf" / "mime.types").write_text("", encoding="utf-8")
    (nginx_home / "conf" / "fastcgi_params").write_text("fastcgi_param QUERY_STRING $query_string;\n", encoding="utf-8")
    redis_root = tmp_path / "redis-root"
    redis_runtime = redis_root / "redis-8.0.0"
    (redis_runtime / "bin").mkdir(parents=True, exist_ok=True)
    (redis_runtime / "conf").mkdir(parents=True, exist_ok=True)
    (redis_runtime / "bin" / "redis-server").write_text("#!/bin/sh\nwhile true; do sleep 1; done\n", encoding="utf-8")
    (redis_runtime / "bin" / "redis-cli").write_text("#!/bin/sh\nprintf 'PONG\\n'\n", encoding="utf-8")
    (redis_runtime / "bin" / "redis-server").chmod(0o755)
    (redis_runtime / "bin" / "redis-cli").chmod(0o755)
    (redis_runtime / "conf" / "redis.conf").write_text("bind 127.0.0.1\n", encoding="utf-8")
    monkeypatch.setenv("SERVER_ENGINE_REDIS_ROOT", str(redis_root))
