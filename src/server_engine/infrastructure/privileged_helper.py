from __future__ import annotations

import ctypes
import json
import os
import subprocess
import shlex
import socket
import sys
import time
from pathlib import Path

from server_engine.core.models import OperationResult, RuntimePaths


class PrivilegedHelperClient:
    def __init__(self, runtime_paths: RuntimePaths) -> None:
        self.runtime_paths = runtime_paths
        self.helper_id = "com.serverengine.app.helper"
        self.install_path = Path(f"/Library/PrivilegedHelperTools/{self.helper_id}")

        override = os.environ.get("SERVER_ENGINE_PRIVILEGED_HELPER_PATH", "").strip()
        if override:
            self.helper_path = Path(override).expanduser()
        else:
            self.helper_path = self.install_path

        self.helper_socket_path = "/var/run/com.serverengine.app.helper.sock"
        self.root_osascript_mode = os.environ.get("SERVER_ENGINE_ROOT_OSASCRIPT", "").strip() == "1"

    def is_available(self) -> bool:
        if self.helper_path == self.install_path:
            # SMJobBless-managed helper is launched by launchd as root.
            # User-level X_OK checks are not a reliable availability signal.
            return self.helper_path.exists()
        return self.helper_path.exists() and os.access(self.helper_path, os.X_OK)

    def _needs_install(self) -> bool:
        # For the standard SMJobBless path, only bless when helper is missing.
        # Re-blessing on binary diffs causes repeated prompts/failures for already
        # installed helpers and is not required for normal runtime operations.
        if self.helper_path == self.install_path:
            return not self.is_available()
        return not self.is_available()

    def ensure_installed(self) -> OperationResult:
        if not self._needs_install():
            return OperationResult(True, "Privileged helper already installed.", {"path": str(self.helper_path)})

        # Standard install path must use SMJobBless, not manual privileged copy.
        if self.helper_path == self.install_path:
            bless_result = self._install_via_smjobbless()
            if not bless_result.success:
                return bless_result
        else:
            return OperationResult(
                False,
                (
                    "Custom privileged helper override path is set, but helper is not available there. "
                    "Unset SERVER_ENGINE_PRIVILEGED_HELPER_PATH to use SMJobBless install."
                ),
                {"path": str(self.helper_path)},
            )

        if not self.is_available():
            return OperationResult(False, f"Helper install completed but executable not found at {self.helper_path}.")

        return OperationResult(True, "Privileged helper installed.", {"path": str(self.helper_path)})

    def _install_via_smjobbless(self) -> OperationResult:
        if sys.platform != "darwin":
            return OperationResult(False, "SMJobBless is supported on macOS only.")

        try:
            security = ctypes.cdll.LoadLibrary("/System/Library/Frameworks/Security.framework/Security")
            service_mgmt = ctypes.cdll.LoadLibrary("/System/Library/Frameworks/ServiceManagement.framework/ServiceManagement")
            core_foundation = ctypes.cdll.LoadLibrary("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
        except OSError as exc:
            return OperationResult(False, f"Unable to load macOS frameworks for SMJobBless: {exc}")

        c_uint32 = ctypes.c_uint32
        c_int32 = ctypes.c_int32
        c_void_p = ctypes.c_void_p
        c_char_p = ctypes.c_char_p

        class AuthorizationItem(ctypes.Structure):
            _fields_ = [
                ("name", c_char_p),
                ("valueLength", c_uint32),
                ("value", c_void_p),
                ("flags", c_uint32),
            ]

        class AuthorizationRights(ctypes.Structure):
            _fields_ = [
                ("count", c_uint32),
                ("items", ctypes.POINTER(AuthorizationItem)),
            ]

        k_authorization_flag_defaults = 0
        k_authorization_flag_interaction_allowed = 1 << 0
        k_authorization_flag_extend_rights = 1 << 1
        k_authorization_flag_pre_authorize = 1 << 2
        auth_flags = (
            k_authorization_flag_defaults
            | k_authorization_flag_interaction_allowed
            | k_authorization_flag_extend_rights
            | k_authorization_flag_pre_authorize
        )

        security.AuthorizationCreate.argtypes = [c_void_p, c_void_p, c_uint32, ctypes.POINTER(c_void_p)]
        security.AuthorizationCreate.restype = c_int32
        security.AuthorizationCopyRights.argtypes = [c_void_p, ctypes.POINTER(AuthorizationRights), c_void_p, c_uint32, c_void_p]
        security.AuthorizationCopyRights.restype = c_int32
        security.AuthorizationFree.argtypes = [c_void_p, c_uint32]
        security.AuthorizationFree.restype = c_int32

        core_foundation.CFStringCreateWithCString.argtypes = [c_void_p, c_char_p, c_uint32]
        core_foundation.CFStringCreateWithCString.restype = c_void_p
        core_foundation.CFErrorCopyDescription.argtypes = [c_void_p]
        core_foundation.CFErrorCopyDescription.restype = c_void_p
        core_foundation.CFStringGetLength.argtypes = [c_void_p]
        core_foundation.CFStringGetLength.restype = ctypes.c_long
        core_foundation.CFStringGetMaximumSizeForEncoding.argtypes = [ctypes.c_long, c_uint32]
        core_foundation.CFStringGetMaximumSizeForEncoding.restype = ctypes.c_long
        core_foundation.CFStringGetCString.argtypes = [c_void_p, c_char_p, ctypes.c_long, c_uint32]
        core_foundation.CFStringGetCString.restype = ctypes.c_bool
        core_foundation.CFRelease.argtypes = [c_void_p]
        core_foundation.CFRelease.restype = None

        service_mgmt.SMJobBless.argtypes = [c_void_p, c_void_p, c_void_p, ctypes.POINTER(c_void_p)]
        service_mgmt.SMJobBless.restype = ctypes.c_bool

        k_cf_string_encoding_utf8 = 0x08000100

        def cfstring_from_text(text: str) -> c_void_p:
            return core_foundation.CFStringCreateWithCString(None, text.encode("utf-8"), k_cf_string_encoding_utf8)

        def cfstring_to_text(value: c_void_p) -> str:
            if not value:
                return ""
            length = core_foundation.CFStringGetLength(value)
            size = core_foundation.CFStringGetMaximumSizeForEncoding(length, k_cf_string_encoding_utf8) + 1
            buffer = ctypes.create_string_buffer(size)
            if core_foundation.CFStringGetCString(value, buffer, size, k_cf_string_encoding_utf8):
                return buffer.value.decode("utf-8", "replace")
            return ""

        auth_ref = c_void_p()
        status = security.AuthorizationCreate(None, None, auth_flags, ctypes.byref(auth_ref))
        if status != 0:
            return OperationResult(False, f"AuthorizationCreate failed with status {status}.")

        item = AuthorizationItem()
        item.name = b"com.apple.ServiceManagement.blesshelper"
        item.valueLength = 0
        item.value = None
        item.flags = 0
        rights = AuthorizationRights()
        rights.count = 1
        rights.items = ctypes.pointer(item)

        try:
            status = security.AuthorizationCopyRights(auth_ref, ctypes.byref(rights), None, auth_flags, None)
            if status != 0:
                return OperationResult(False, f"AuthorizationCopyRights failed with status {status}.")

            helper_label = cfstring_from_text(self.helper_id)
            if not helper_label:
                return OperationResult(False, "Unable to create helper label CFString.")
            error_ref = c_void_p()

            try:
                domain_ref = c_void_p.in_dll(service_mgmt, "kSMDomainSystemLaunchd")
            except ValueError:
                core_foundation.CFRelease(helper_label)
                return OperationResult(False, "Unable to resolve kSMDomainSystemLaunchd.")

            success = service_mgmt.SMJobBless(domain_ref, helper_label, auth_ref, ctypes.byref(error_ref))
            core_foundation.CFRelease(helper_label)
            if not success:
                message = "SMJobBless failed."
                if error_ref:
                    desc = core_foundation.CFErrorCopyDescription(error_ref)
                    if desc:
                        text = cfstring_to_text(desc).strip()
                        if text:
                            message = text
                        core_foundation.CFRelease(desc)
                    core_foundation.CFRelease(error_ref)
                return OperationResult(False, message)
        finally:
            security.AuthorizationFree(auth_ref, 0)

        return OperationResult(True, "Privileged helper installed via SMJobBless.", {"path": str(self.helper_path)})

    def write_hosts_content(self, hosts_path: Path, content: str) -> OperationResult:
        if self.root_osascript_mode:
            return self._write_hosts_content_via_osascript(hosts_path, content)

        install_result = self.ensure_installed()
        if not install_result.success:
            return install_result

        pending_path = self.runtime_paths.temp_dir / "hosts.pending"
        pending_path.parent.mkdir(parents=True, exist_ok=True)
        pending_path.write_text(content, encoding="utf-8")

        payload = {
            "command": "write-hosts",
            "hosts_path": str(hosts_path),
            "input": str(pending_path),
        }
        call_result = self._call_helper(payload)
        if not call_result.success:
            return call_result

        return OperationResult(True, "Hosts file updated via privileged helper.")

    def flush_dns(self) -> OperationResult:
        if self.root_osascript_mode:
            return self._flush_dns_via_osascript()

        install_result = self.ensure_installed()
        if not install_result.success:
            return install_result
        call_result = self._call_helper({"command": "flush-dns"})
        if not call_result.success:
            return call_result

        return OperationResult(True, "DNS cache flushed via privileged helper.")

    def _call_helper(self, payload: dict[str, str], timeout: float = 10.0) -> OperationResult:
        # Ensure launchd has started helper after blessing.
        if not Path(self.helper_socket_path).exists():
            subprocess.run(
                ["launchctl", "kickstart", "-k", f"system/{self.helper_id}"],
                capture_output=True,
                text=True,
                check=False,
            )
        response = ""
        last_error = ""
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
                    client.settimeout(min(2.0, max(0.5, deadline - time.time())))
                    client.connect(self.helper_socket_path)
                    body = (json.dumps(payload) + "\n").encode("utf-8")
                    client.sendall(body)
                    chunks: list[bytes] = []
                    while True:
                        chunk = client.recv(4096)
                        if not chunk:
                            break
                        chunks.append(chunk)
                        if b"\n" in chunk:
                            break
                    response = b"".join(chunks).decode("utf-8", "replace").strip()
                    break
            except Exception as exc:
                last_error = str(exc)
                time.sleep(0.2)
        if not response:
            return OperationResult(False, f"Privileged helper IPC failed: {last_error or 'no response'}")

        try:
            parsed = json.loads(response)
            if isinstance(parsed, dict) and bool(parsed.get("ok")):
                return OperationResult(True, str(parsed.get("message") or "OK"))
            if isinstance(parsed, dict):
                return OperationResult(False, str(parsed.get("message") or "Privileged helper failed."))
        except Exception:
            pass
        return OperationResult(False, response or "Privileged helper failed.")

    def _write_hosts_content_via_osascript(self, hosts_path: Path, content: str) -> OperationResult:
        try:
            if str(hosts_path) != "/etc/hosts":
                return OperationResult(False, "Refusing write outside /etc/hosts.")
            pending_path = self.runtime_paths.temp_dir / "hosts.pending"
            pending_path.parent.mkdir(parents=True, exist_ok=True)
            pending_path.write_text(content, encoding="utf-8")
            cmd = (
                f"/bin/cp {shlex.quote(str(pending_path))} /etc/hosts && "
                "/usr/sbin/chown root:wheel /etc/hosts && "
                "/bin/chmod 0644 /etc/hosts && "
                "/usr/bin/dscacheutil -flushcache && "
                "/usr/bin/killall -HUP mDNSResponder"
            )
            completed = subprocess.run(
                ["/usr/bin/osascript", "-e", f'do shell script "{cmd}" with administrator privileges'],
                capture_output=True,
                text=True,
                check=False,
            )
            if completed.returncode != 0:
                message = (completed.stderr or completed.stdout or "osascript hosts update failed.").strip()
                return OperationResult(False, message)
            return OperationResult(True, "Hosts file updated via osascript.")
        except Exception as exc:
            return OperationResult(False, f"osascript hosts update failed: {exc}")

    def _flush_dns_via_osascript(self) -> OperationResult:
        try:
            cmd = "/usr/bin/dscacheutil -flushcache && /usr/bin/killall -HUP mDNSResponder"
            completed = subprocess.run(
                ["/usr/bin/osascript", "-e", f'do shell script "{cmd}" with administrator privileges'],
                capture_output=True,
                text=True,
                check=False,
            )
            if completed.returncode != 0:
                message = (completed.stderr or completed.stdout or "osascript DNS flush failed.").strip()
                return OperationResult(False, message)
            return OperationResult(True, "DNS cache flushed via osascript.")
        except Exception as exc:
            return OperationResult(False, f"osascript DNS flush failed: {exc}")
