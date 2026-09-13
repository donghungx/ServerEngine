from __future__ import annotations

from pathlib import Path

from server_engine.bootstrap import build_container


def test_redis_runtime_service_discovers_runtime(tmp_path: Path, monkeypatch) -> None:
    redis_root = tmp_path / "redis-root"
    runtime = redis_root / "redis-8.6.2" / "bin"
    runtime.mkdir(parents=True, exist_ok=True)
    (runtime / "redis-server").write_text("", encoding="utf-8")
    (runtime / "redis-cli").write_text("", encoding="utf-8")
    monkeypatch.setenv("SERVER_ENGINE_REDIS_ROOT", str(redis_root))
    monkeypatch.setenv("SERVER_ENGINE_PHP_ROOT", str(tmp_path / "php-root"))
    monkeypatch.setenv("SERVER_ENGINE_APACHE_HOME", str(tmp_path / "apache-home"))
    monkeypatch.setenv("SERVER_ENGINE_HOSTS_PATH", str(tmp_path / "hosts"))

    container = build_container(runtime_root=tmp_path / "runtime-root")

    runtimes = container.redis_runtime_service.list_runtimes()

    assert len(runtimes) == 1
    assert runtimes[0].id == "redis-8.6.2"
    assert runtimes[0].version == "8.6.2"


def test_redis_service_generates_config(container) -> None:
    config_path = Path(container.redis_service.generate_config())
    content = config_path.read_text(encoding="utf-8")

    assert config_path.exists()
    assert "bind 127.0.0.1" in content
    assert "port 6379" in content
    assert "appendonly no" in content
