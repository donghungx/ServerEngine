from __future__ import annotations

import base64
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import hashlib
import json
import logging
import os
from pathlib import Path
import platform
import sys
import urllib.error
import urllib.request
import uuid

try:
    from nacl.exceptions import BadSignatureError
    from nacl.signing import VerifyKey as NaClVerifyKey
    _HAS_NACL = True
except Exception:
    BadSignatureError = Exception  # type: ignore[assignment]
    NaClVerifyKey = None  # type: ignore[assignment]
    _HAS_NACL = False

try:
    from cryptography.exceptions import InvalidSignature
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
    _HAS_CRYPTO = True
except Exception:
    InvalidSignature = Exception  # type: ignore[assignment]
    AESGCM = None  # type: ignore[assignment]
    Ed25519PublicKey = None  # type: ignore[assignment]
    _HAS_CRYPTO = False

from server_engine.infrastructure.ssl_support import default_ssl_context

from server_engine.core.models import RuntimePaths


PRODUCTION_LICENSE_API_URL = "https://ninacoder.top/wp-json/server-engine/v1"
DEVELOPMENT_LICENSE_API_URL = "https://ninacoder.top/wp-json/server-engine/v1"
FIRST_RUN_GRACE_DAYS = 1
LICENSE_SIGNING_PUBLIC_KEY_B64 = "GabE4DfG+PNl0LGT+e0j+gWzh/OrOeFt/c6vkHYh1Oc="
ONLINE_VALIDATE_INTERVAL_HOURS = 24
LICENSE_STATE_ENCRYPTION_CONTEXT = "server-engine-license-state-v1"


@dataclass(frozen=True)
class LicenseStatus:
    valid: bool
    enforced: bool
    status: str
    message: str
    licensed_to: str = ""
    license_key: str = ""
    expires_at: str = ""
    days_remaining: int = 0


class LicenseApiError(Exception):
    def __init__(self, status: int | None, code: str, message: str) -> None:
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message


class LicenseService:
    def __init__(self, runtime_paths: RuntimePaths) -> None:
        self.runtime_paths = runtime_paths
        self.license_path = runtime_paths.root / "license.json"
        self._logger = logging.getLogger("server_engine.license")
        self._apply_test_overrides()

    def _dev_license_logging_enabled(self) -> bool:
        return not self.is_enforced()

    def _dev_log(self, message: str, *args: object) -> None:
        if self._dev_license_logging_enabled():
            self._logger.info(message, *args)

    def is_enforced(self) -> bool:
        mode = os.environ.get("SERVER_ENGINE_RUNTIME_MODE", "").strip().lower()
        if mode in {"installed", "appsupport", "app-support"}:
            return True
        if mode in {"dev", "source", "dist"}:
            return False
        return bool(getattr(sys, "frozen", False))

    def status(self) -> LicenseStatus:
        enforced = self.is_enforced()
        state = self._read_state()
        if not state:
            state = self._new_grace_state()
            self._write_state(state)
        if state.get("status") == "active":
            return self._status_from_active_state(state)
        if state.get("status") == "grace":
            return self._status_from_grace_state(state)
        if state.get("status") == "trial":
            return self._status_from_trial_state(state)
        if state.get("status") in {"expired", "revoked", "banned"}:
            reason = str(state.get("status"))
            message = str(state.get("server_message") or ("License has expired." if reason == "expired" else "License is no longer valid."))
            return LicenseStatus(
                valid=False,
                enforced=enforced,
                status=reason,
                message=message,
                licensed_to=str(state.get("licensed_to") or "Licensed User"),
                license_key=str(state.get("license_key") or ""),
                expires_at=str(state.get("expires_at") or ""),
            )
        return LicenseStatus(
            valid=not enforced,
            enforced=enforced,
            status=str(state.get("status") or "invalid"),
            message="License is not valid.",
        )

    def revalidate_if_due(self, force: bool = False) -> LicenseStatus:
        state = self._read_state()
        local_status = str(state.get("status") or "missing").strip().lower()
        has_license_key = bool(str(state.get("license_key") or "").strip())
        has_trial = bool(str(state.get("trial_started_at") or "").strip())
        due = self._validation_due(state) if state else True
        self._dev_log(
            "License revalidation requested. force=%s state=%s due=%s has_license_key=%s has_trial=%s",
            force,
            local_status,
            due,
            has_license_key,
            has_trial,
        )
        if not force and not due:
            self._dev_log("License revalidation skipped: not due yet.")
            return self.status()
        if has_license_key:
            self._dev_log("License revalidation will call server validate().")
            return self.validate()
        if has_trial:
            self._dev_log("License revalidation will call server trial refresh().")
            return self.start_trial()
        self._dev_log("License revalidation skipped: no server-bound license data present.")
        return self.status()

    def start_trial(self) -> LicenseStatus:
        state = self._read_state()
        current = self.status()
        api_url = self.license_api_url()
        self._dev_log(
            "Trial start requested. enforced=%s api_url=%s device_id=%s existing_trial=%s",
            self.is_enforced(),
            api_url,
            self._mask_device_id(self.device_id()),
            bool(state.get("trial_started_at")),
        )
        if api_url:
            try:
                request_url = api_url.rstrip("/") + "/trial/start"
                payload = {
                    "product": "server-engine",
                    "device_id": self.device_id(),
                }
                data = self._post_json(request_url, payload, endpoint="/trial/start")
                if not self._verify_signed_response(data):
                    return LicenseStatus(
                        valid=False,
                        enforced=self.is_enforced(),
                        status="invalid",
                        message="Trial signature verification failed.",
                    )
                trial_payload = self._extract_payload(data)
                remote_status = str(trial_payload.get("status", data.get("status", ""))).lower()
                expires_at = str(
                    trial_payload.get("expires_at")
                    or trial_payload.get("trial_expires_at")
                    or ""
                )
                started_at = str(
                    trial_payload.get("started_at")
                    or trial_payload.get("trial_started_at")
                    or self._now().isoformat()
                )
                trial_state = {
                    "status": "trial",
                    "trial_started_at": started_at,
                    "trial_expires_at": expires_at,
                    "device_id": self.device_id(),
                }
                self._dev_log(
                    "Trial sync comparison local_started_at=%s local_expires_at=%s remote_status=%s remote_started_at=%s remote_expires_at=%s",
                    str(state.get("trial_started_at") or ""),
                    str(state.get("trial_expires_at") or ""),
                    remote_status or "unknown",
                    started_at,
                    expires_at,
                )
                self._write_state(trial_state)
                self._dev_log(
                    "Trial API success. started_at=%s expires_at=%s",
                    trial_state.get("trial_started_at", ""),
                    trial_state.get("trial_expires_at", ""),
                )
                return self.status()
            except LicenseApiError as exc:
                self._logger.error("Trial API failed: %s (%s)", exc.message, exc.code)
                if exc.status is not None:
                    self._stamp_validation_attempt(state, f"server_error:{exc.status}" if exc.status >= 500 else f"api_error:{exc.code}")
                return current
            except Exception:
                self._logger.exception("Trial API failed.")
                self._stamp_validation_attempt(state, "network_error")
                return current
        else:
            self._logger.warning("Trial API URL is empty.")
            return LicenseStatus(
                valid=False,
                enforced=self.is_enforced(),
                status="invalid",
                message="License server is not configured.",
            )

    def activate(self, license_key: str) -> LicenseStatus:
        cleaned = license_key.strip()
        if not cleaned:
            return LicenseStatus(False, self.is_enforced(), "invalid", "Activation code is required.")

        api_url = self.license_api_url()
        self._dev_log(
            "License activation requested. enforced=%s api_url=%s device_id=%s",
            self.is_enforced(),
            api_url,
            self._mask_device_id(self.device_id()),
        )
        if not api_url:
            return LicenseStatus(
                False,
                self.is_enforced(),
                "invalid",
                "License server is not configured.",
                license_key=cleaned,
            )
        try:
            request_url = api_url.rstrip("/") + "/activate"
            payload = {
                "product": "server-engine",
                "license_key": cleaned,
                "device_id": self.device_id(),
                "device_label": platform.node() or "Local Machine",
                "app_version": os.environ.get("SERVER_ENGINE_APP_VERSION", "dev"),
            }
            data = self._post_json(request_url, payload, endpoint="/activate")
            if not self._verify_signed_response(data):
                return LicenseStatus(
                    valid=False,
                    enforced=self.is_enforced(),
                    status="invalid",
                    message="Activation signature verification failed.",
                    license_key=cleaned,
                )
        except LicenseApiError as exc:
            self._logger.error("License activation API error: %s (%s)", exc.message, exc.code)
            return LicenseStatus(False, self.is_enforced(), "invalid", exc.message, license_key=cleaned)
        except (urllib.error.URLError, TimeoutError, ValueError) as exc:
            self._logger.exception("License activation request failed.")
            return LicenseStatus(False, self.is_enforced(), "invalid", f"Activation failed: {exc}", license_key=cleaned)

        active_payload = self._extract_payload(data)
        active_status = str(active_payload.get("status", data.get("status", ""))).lower()
        self._dev_log("License activation response status=%s", active_status or "unknown")
        if active_status != "active":
            return LicenseStatus(False, self.is_enforced(), "invalid", str(data.get("message") or "License was rejected."), license_key=cleaned)

        state = {
            "status": "active",
            "license_key": cleaned,
            "licensed_to": str(active_payload.get("licensed_to") or active_payload.get("customer_email") or data.get("licensed_to") or "Licensed User"),
            "expires_at": str(active_payload.get("expires_at") or data.get("expires_at") or ""),
            "activated_at": self._now().isoformat(),
        }
        self._write_state(state)
        self._dev_log("License activation stored. expires_at=%s", state.get("expires_at", ""))
        return self.status()

    def validate(self) -> LicenseStatus:
        state = self._read_state()
        license_key = str(state.get("license_key") or "").strip()
        if not license_key:
            self._dev_log("License validate skipped: no active license key.")
            return self.status()
        api_url = self.license_api_url()
        if not api_url:
            self._dev_log("License validate skipped: server URL is not configured.")
            return LicenseStatus(False, self.is_enforced(), "invalid", "License server is not configured.", license_key=license_key)
        self._dev_log(
            "License validate request starting. api_url=%s device_id=%s",
            api_url,
            self._mask_device_id(self.device_id()),
        )
        try:
            request_url = api_url.rstrip("/") + "/validate"
            payload = {
                "product": "server-engine",
                "license_key": license_key,
                "device_id": self.device_id(),
                "app_version": os.environ.get("SERVER_ENGINE_APP_VERSION", "dev"),
            }
            data = self._post_json(request_url, payload, endpoint="/validate")
            if not self._verify_signed_response(data):
                return LicenseStatus(
                    valid=False,
                    enforced=self.is_enforced(),
                    status="invalid",
                    message="Validate signature verification failed.",
                    license_key=license_key,
                )
        except LicenseApiError as exc:
            self._logger.error("License validate API error: %s (%s)", exc.message, exc.code)
            current = self.status()
            if exc.status is not None and exc.status >= 500:
                self._stamp_validation_attempt(state, f"server_error:{exc.status}")
                return current
            if exc.code in {"license_expired"}:
                self._mark_server_invalid(state, "expired", exc.message)
                return self.status()
            if exc.code in {"license_not_found", "license_revoked", "license_banned"}:
                self._mark_server_invalid(state, "revoked", exc.message)
                return self.status()
            self._stamp_validation_attempt(state, f"api_error:{exc.code}")
            return current
        except (urllib.error.URLError, TimeoutError, ValueError) as exc:
            self._logger.exception("License validate request failed.")
            self._stamp_validation_attempt(state, "network_error")
            return self.status()

        validate_payload = self._extract_payload(data)
        remote_status = str(validate_payload.get("status", data.get("status", ""))).lower()
        self._dev_log(
            "License sync comparison local_status=%s local_expires_at=%s remote_status=%s remote_license_key=%s remote_expires_at=%s",
            str(state.get("status") or "missing"),
            str(state.get("expires_at") or state.get("trial_expires_at") or ""),
            remote_status or "unknown",
            str(validate_payload.get("license_key") or data.get("license_key") or ""),
            str(validate_payload.get("expires_at") or ""),
        )
        if remote_status != "active":
            message = str(data.get("message") or "License is not active.")
            self._dev_log(
                "License validate response was not active. remote_status=%s message=%s",
                remote_status or "unknown",
                message,
            )
            if remote_status == "expired":
                self._mark_server_invalid(state, "expired", message)
                return self.status()
            if remote_status in {"revoked", "banned", "invalid"}:
                self._mark_server_invalid(state, "revoked", message)
                return self.status()
            self._stamp_validation_attempt(state, f"remote_{remote_status or 'unknown'}")
            return self.status()

        updated = dict(state)
        updated["status"] = "active"
        updated["license_key"] = str(validate_payload.get("license_key") or license_key)
        updated["licensed_to"] = str(validate_payload.get("customer_name") or validate_payload.get("customer_email") or updated.get("licensed_to") or "Licensed User")
        updated["expires_at"] = str(validate_payload.get("expires_at") or updated.get("expires_at") or "")
        updated["last_validated_at"] = self._now().isoformat()
        updated["last_validation_result"] = "active"
        updated.pop("server_message", None)
        self._write_state(updated)
        self._dev_log(
            "License validate completed successfully. expires_at=%s",
            updated.get("expires_at", ""),
        )
        return self.status()

    def deactivate(self) -> tuple[bool, str]:
        state = self._read_state()
        license_key = str(state.get("license_key") or "").strip()
        if not license_key:
            return True, "No active license key."
        api_url = self.license_api_url()
        if not api_url:
            return False, "License server is not configured."
        try:
            request_url = api_url.rstrip("/") + "/deactivate"
            payload = {
                "product": "server-engine",
                "license_key": license_key,
                "device_id": self.device_id(),
            }
            data = self._post_json(request_url, payload, endpoint="/deactivate")
        except LicenseApiError as exc:
            self._logger.error("License deactivate API error: %s (%s)", exc.message, exc.code)
            return False, exc.message
        except (urllib.error.URLError, TimeoutError, ValueError) as exc:
            self._logger.exception("License deactivate request failed.")
            return False, f"Deactivate failed: {exc}"
        # /deactivate is currently unsigned by design.
        success = bool(data.get("success"))
        message = str(data.get("message") or ("Device deactivated." if success else "Deactivate rejected."))
        return success, message

    def remove_license(self) -> LicenseStatus:
        state = self._read_state()
        if self.is_enforced() and state.get("status") == "active":
            success, message = self.deactivate()
            if not success:
                return LicenseStatus(
                    valid=False,
                    enforced=True,
                    status="invalid",
                    message=message,
                    license_key=str(state.get("license_key") or ""),
                )
        if state.get("status") == "active":
            state["status"] = "trial" if state.get("trial_started_at") else "removed"
            state.pop("license_key", None)
            state.pop("licensed_to", None)
            self._write_state(state)
        return self.status()

    def device_id(self) -> str:
        raw = f"{platform.node()}:{uuid.getnode()}:{Path.home()}"
        return hashlib.sha256(raw.encode("utf-8")).hexdigest()

    def device_headers(self) -> dict[str, str]:
        os_type = platform.system().strip().lower() or sys.platform
        if os_type == "darwin":
            os_version = platform.mac_ver()[0] or platform.release()
        else:
            os_version = platform.release()
        return {
            "X-ServerEngine-Device-ID": self.device_id(),
            "X-ServerEngine-OS-Type": os_type,
            "X-ServerEngine-OS-Version": os_version,
            "X-ServerEngine-Arch": platform.machine() or "unknown",
        }

    def license_api_url(self) -> str:
        explicit = os.environ.get("SERVER_ENGINE_LICENSE_API_URL", "").strip()
        if explicit:
            return explicit
        if self.is_enforced():
            return os.environ.get("SERVER_ENGINE_LICENSE_API_URL_PROD", PRODUCTION_LICENSE_API_URL).strip()
        return os.environ.get("SERVER_ENGINE_LICENSE_API_URL_DEV", DEVELOPMENT_LICENSE_API_URL).strip()

    def _post_json(self, url: str, payload: dict, endpoint: str = "") -> dict:
        self._dev_log(
            "HTTP POST endpoint=%s full_url=%s payload_keys=%s",
            endpoint or "unknown",
            url,
            ",".join(sorted(payload.keys())),
        )
        request = urllib.request.Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers={
                "Content-Type": "application/json",
                "Accept": "application/json",
                **self.device_headers(),
            },
            method="POST",
        )
        ssl_context = default_ssl_context(url)
        try:
            with urllib.request.urlopen(request, timeout=12, context=ssl_context) as response:
                data = json.loads(response.read().decode("utf-8"))
                self._dev_log(
                    "HTTP response endpoint=%s full_url=%s keys=%s",
                    endpoint or "unknown",
                    url,
                    ",".join(sorted(data.keys())) if isinstance(data, dict) else "non-dict",
                )
                return data if isinstance(data, dict) else {}
        except urllib.error.HTTPError as exc:
            body = ""
            try:
                raw = exc.read()
                body = raw.decode("utf-8", "replace") if raw else ""
            except Exception:
                body = ""
            code, message = self._parse_api_error_response(exc.code, body)
            raise LicenseApiError(exc.code, code, message) from exc

    def _extract_payload(self, data: dict) -> dict:
        payload = data.get("payload")
        if isinstance(payload, dict):
            return payload
        return data

    def _verify_signed_response(self, data: dict) -> bool:
        payload = data.get("payload")
        signature_b64 = str(data.get("signature") or "").strip()
        if not isinstance(payload, dict) or not signature_b64:
            self._logger.error("Signed response verification failed: missing payload/signature.")
            return False
        canonical_payload = self._canonical_json(payload)
        try:
            signature = base64.b64decode(signature_b64, validate=True)
            public_key_b64 = os.environ.get(
                "SERVER_ENGINE_LICENSE_PUBLIC_KEY_B64",
                LICENSE_SIGNING_PUBLIC_KEY_B64,
            ).strip()
            public_key = base64.b64decode(public_key_b64, validate=True)
            payload_bytes = canonical_payload.encode("utf-8")
            if _HAS_NACL and NaClVerifyKey is not None:
                verifier = NaClVerifyKey(public_key)
                verifier.verify(payload_bytes, signature)
                return True
            if _HAS_CRYPTO and Ed25519PublicKey is not None:
                verifier = Ed25519PublicKey.from_public_bytes(public_key)
                verifier.verify(signature, payload_bytes)
                return True
            self._logger.error(
                "Signed response verification failed: no Ed25519 backend available "
                "(install pynacl or cryptography). _HAS_NACL=%s _HAS_CRYPTO=%s",
                _HAS_NACL,
                _HAS_CRYPTO,
            )
            return False
        except (ValueError, BadSignatureError, InvalidSignature, TypeError) as exc:
            self._logger.error("Signed response verification failed: %s", exc)
            return False

    def _canonical_json(self, payload: dict) -> str:
        # PHP ksort-equivalent ordering for object keys.
        return json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)

    def _parse_api_error_response(self, status_code: int | None, body: str) -> tuple[str, str]:
        default_message = "License server request failed."
        code = "http_error"
        message = default_message
        if body:
            try:
                payload = json.loads(body)
                if isinstance(payload, dict):
                    code = str(payload.get("code") or code)
                    message = str(payload.get("message") or message)
            except Exception:
                pass
        if code == "license_not_found":
            return code, "License key was not found. Check the key and try again."
        if status_code == 404 and message == default_message:
            return code, "License key was not found. Check the key and try again."
        return code, message

    def _mask_device_id(self, value: str) -> str:
        cleaned = (value or "").strip()
        if len(cleaned) <= 12:
            return cleaned
        return cleaned[:6] + "..." + cleaned[-6:]

    def _status_from_active_state(self, state: dict) -> LicenseStatus:
        expires_at = str(state.get("expires_at") or "")
        days_remaining = 9999
        if expires_at:
            expiry = self._parse_datetime(expires_at)
            if expiry is not None:
                seconds = (expiry - self._now()).total_seconds()
                days_remaining = max(int(seconds // 86400), 0)
        return LicenseStatus(
            valid=True,
            enforced=self.is_enforced(),
            status="active",
            message="License is active.",
            licensed_to=str(state.get("licensed_to") or "Licensed User"),
            license_key=str(state.get("license_key") or ""),
            expires_at=expires_at,
            days_remaining=days_remaining,
        )

    def _state_encryption_key(self) -> bytes:
        material = f"{LICENSE_STATE_ENCRYPTION_CONTEXT}:{self.device_id()}".encode("utf-8")
        return hashlib.sha256(material).digest()

    def _encrypt_state(self, state: dict) -> dict:
        if AESGCM is None:
            self._logger.warning("State encryption unavailable; writing plaintext license state.")
            return dict(state)
        nonce = os.urandom(12)
        plaintext = json.dumps(state, indent=2, sort_keys=True).encode("utf-8")
        ciphertext = AESGCM(self._state_encryption_key()).encrypt(nonce, plaintext, None)
        return {
            "format": LICENSE_STATE_ENCRYPTION_CONTEXT,
            "nonce": base64.b64encode(nonce).decode("ascii"),
            "ciphertext": base64.b64encode(ciphertext).decode("ascii"),
        }

    def _decrypt_state(self, data: dict) -> dict | None:
        if data.get("format") != LICENSE_STATE_ENCRYPTION_CONTEXT:
            return None
        if AESGCM is None:
            self._logger.warning("State decryption unavailable; encrypted license state cannot be read.")
            return None
        nonce_b64 = str(data.get("nonce") or "").strip()
        ciphertext_b64 = str(data.get("ciphertext") or "").strip()
        if not nonce_b64 or not ciphertext_b64:
            return None
        try:
            nonce = base64.b64decode(nonce_b64, validate=True)
            ciphertext = base64.b64decode(ciphertext_b64, validate=True)
            plaintext = AESGCM(self._state_encryption_key()).decrypt(nonce, ciphertext, None)
            decoded = json.loads(plaintext.decode("utf-8"))
            return decoded if isinstance(decoded, dict) else {}
        except Exception:
            return None

    def _validation_due(self, state: dict) -> bool:
        stamp = str(state.get("last_validated_at") or "").strip()
        if not stamp:
            return True
        parsed = self._parse_datetime(stamp)
        if parsed is None:
            return True
        return (self._now() - parsed) >= timedelta(hours=ONLINE_VALIDATE_INTERVAL_HOURS)

    def _stamp_validation_attempt(self, state: dict, result: str) -> None:
        updated = dict(state)
        updated["last_validated_at"] = self._now().isoformat()
        updated["last_validation_result"] = result
        self._write_state(updated)

    def _mark_server_invalid(self, state: dict, status: str, message: str) -> None:
        updated = dict(state)
        updated["status"] = status
        updated["server_message"] = message.strip() or "License is not active."
        updated["last_validated_at"] = self._now().isoformat()
        updated["last_validation_result"] = status
        self._write_state(updated)

    def _status_from_trial_state(self, state: dict) -> LicenseStatus:
        expires_at = str(state.get("trial_expires_at") or "")
        expiry = self._parse_datetime(expires_at)
        if expiry is None:
            return LicenseStatus(False, self.is_enforced(), "invalid", "Trial state is invalid.")
        seconds = (expiry - self._now()).total_seconds()
        if seconds <= 0:
            return LicenseStatus(False, self.is_enforced(), "trial_expired", "Trial has ended.", expires_at=expires_at)
        return LicenseStatus(
            valid=True,
            enforced=self.is_enforced(),
            status="trial",
            message="Trial is active.",
            licensed_to="Trial User",
            expires_at=expires_at,
            days_remaining=max(int(seconds // 86400), 0),
        )

    def _status_from_grace_state(self, state: dict) -> LicenseStatus:
        expires_at = str(state.get("grace_expires_at") or "")
        expiry = self._parse_datetime(expires_at)
        if expiry is None:
            return LicenseStatus(False, self.is_enforced(), "invalid", "Grace state is invalid.")
        seconds = (expiry - self._now()).total_seconds()
        if seconds <= 0:
            return LicenseStatus(
                False,
                self.is_enforced(),
                "trial_expired",
                "Trial has ended.",
                expires_at=expires_at,
            )
        return LicenseStatus(
            valid=True,
            enforced=self.is_enforced(),
            status="grace",
            message="Start trial or activate license.",
            licensed_to="Trial Pending",
            expires_at=expires_at,
            days_remaining=max(int(seconds // 86400), 0),
        )

    def _new_grace_state(self) -> dict:
        now = self._now()
        return {
            "status": "grace",
            "grace_started_at": now.isoformat(),
            "grace_expires_at": (now + timedelta(days=FIRST_RUN_GRACE_DAYS)).isoformat(),
            "device_id": self.device_id(),
        }

    def _read_state(self) -> dict:
        try:
            if not self.license_path.exists():
                return {}
            data = json.loads(self.license_path.read_text(encoding="utf-8"))
            if not isinstance(data, dict):
                return {}
            decrypted = self._decrypt_state(data)
            if decrypted is not None:
                return decrypted
            if any(key in data for key in {"status", "trial_started_at", "trial_expires_at", "license_key", "grace_expires_at", "last_validated_at"}):
                try:
                    self._write_state(data)
                except Exception:
                    self._logger.exception("Failed to migrate plaintext license state to encrypted storage.")
                return data
            return {}
        except Exception:
            return {}

    def _write_state(self, state: dict) -> None:
        self.license_path.parent.mkdir(parents=True, exist_ok=True)
        encoded = self._encrypt_state(state)
        self.license_path.write_text(json.dumps(encoded, indent=2, sort_keys=True), encoding="utf-8")

    def _now(self) -> datetime:
        return datetime.now(timezone.utc)

    def _apply_test_overrides(self) -> None:
        reset_raw = os.environ.get("SERVER_ENGINE_LICENSE_RESET", "").strip().lower()
        if reset_raw in {"1", "true", "yes", "on"}:
            try:
                if self.license_path.exists():
                    self.license_path.unlink()
                    self._logger.info("License state reset requested. Deleted %s", self.license_path)
                else:
                    self._logger.info("License state reset requested. File already absent: %s", self.license_path)
            except Exception:
                self._logger.exception("Failed to reset license state: %s", self.license_path)

    def _parse_datetime(self, value: str) -> datetime | None:
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
            if parsed.tzinfo is None:
                return parsed.replace(tzinfo=timezone.utc)
            return parsed.astimezone(timezone.utc)
        except ValueError:
            return None
