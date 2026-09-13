from __future__ import annotations

import json
from pathlib import Path

from server_engine.infrastructure.paths import PathProvider
from server_engine.services.license_service import LicenseService


def _make_service(tmp_path: Path) -> LicenseService:
    runtime_paths = PathProvider(runtime_root=tmp_path / "server-engine-home").build()
    service = LicenseService(runtime_paths)
    service.device_id = lambda: "fixed-device-id"  # type: ignore[method-assign]
    return service


def test_license_state_is_encrypted_on_write(tmp_path: Path) -> None:
    service = _make_service(tmp_path)
    state = {
        "status": "trial",
        "trial_started_at": "2026-05-18T18:06:10+00:00",
        "trial_expires_at": "2026-06-17T18:06:10+00:00",
        "device_id": "fixed-device-id",
    }

    service._write_state(state)

    raw = json.loads(service.license_path.read_text(encoding="utf-8"))
    assert raw["format"] == "server-engine-license-state-v1"
    assert "trial_expires_at" not in raw
    assert service._read_state() == state


def test_plaintext_license_state_is_migrated_to_encrypted_storage(tmp_path: Path) -> None:
    service = _make_service(tmp_path)
    state = {
        "status": "trial",
        "trial_started_at": "2026-05-18T18:06:10+00:00",
        "trial_expires_at": "2026-06-17T18:06:10+00:00",
        "device_id": "fixed-device-id",
    }

    service.license_path.parent.mkdir(parents=True, exist_ok=True)
    service.license_path.write_text(json.dumps(state, indent=2, sort_keys=True), encoding="utf-8")

    assert service._read_state() == state

    raw = json.loads(service.license_path.read_text(encoding="utf-8"))
    assert raw["format"] == "server-engine-license-state-v1"
    assert "trial_expires_at" not in raw
