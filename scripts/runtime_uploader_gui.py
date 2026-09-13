#!/usr/bin/env python3
"""
GUI uploader for Server Engine runtime bundles.

This tool is intentionally build-side only. It packages local runtime directories
from ~/Library/Application Support/Server Engine, shows the remote WordPress runtime manifest, and uploads a
selected runtime through /wp-json/server-engine/v1/runtime/admin/upload.
"""

from __future__ import annotations

import hashlib
import http.client
import json
import os
import platform
import queue
import re
import shlex
import ssl
import shutil
import subprocess
import tarfile
import tempfile
import threading
import time
import zipfile
from datetime import datetime, timezone
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import tkinter as tk
from tkinter import filedialog, ttk


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_RUNTIME_ROOT = REPO_ROOT / "dist" / "runtime"
DEFAULT_PKG_ROOT = REPO_ROOT / "dist" / "pkg"
CONFIG_DIR = Path.home() / "Library" / "Application Support" / "Server Engine"
CONFIG_PATH = CONFIG_DIR / "runtime-uploader.json"
APP_PKG_TAB = "app_pkg"
APP_MIN_OS_VERSION = "14.0"
SERVICES = (
    "php",
    "phpmyadmin",
    "apache",
    "nginx",
    "mysql",
    "mariadb",
    "mongodb",
    "postgresql",
    "redis",
    "memcached",
    "mailpit",
    "node",
)

SERVICE_DIRS = {
    "php": ("php",),
    "phpmyadmin": ("tools/phpmyadmin",),
    "apache": ("server", "apache"),
    "nginx": ("server", "nginx"),
    "mysql": ("database",),
    "mariadb": ("database",),
    "mongodb": ("database",),
    "postgresql": ("database",),
    "redis": ("redis",),
    "memcached": ("memcached",),
    "mailpit": ("mailpit",),
    "node": ("node",),
}

SERVICE_PREFIXES = {
    "php": ("php",),
    "phpmyadmin": ("phpmyadmin",),
    "apache": ("apache", "httpd"),
    "nginx": ("nginx",),
    "mysql": ("mysql",),
    "mariadb": ("mariadb",),
    "mongodb": ("mongodb-", "mongodb"),
    "postgresql": ("postgresql-", "postgresql@", "postgresql"),
    "redis": ("redis",),
    "memcached": ("memcached",),
    "mailpit": ("mailpit",),
    "node": ("node",),
}

DEFAULT_BINARIES = {
    "php": ("bin/php", "bin/php-cgi"),
    "phpmyadmin": (),
    "apache": ("bin/httpd", "bin/apachectl"),
    "nginx": ("sbin/nginx", "bin/nginx"),
    "mysql": ("bin/mysqld", "bin/mysql"),
    "mariadb": ("bin/mariadbd", "bin/mysqld", "bin/mariadb", "bin/mysql"),
    "mongodb": ("bin/mongod", "bin/mongos"),
    "postgresql": ("bin/postgres", "bin/psql", "bin/pg_ctl"),
    "redis": ("bin/redis-server", "bin/redis-cli"),
    "memcached": ("bin/memcached",),
    "mailpit": ("bin/mailpit",),
    "node": ("bin/node", "bin/npm", "bin/npx"),
}


def build_ssl_context() -> ssl.SSLContext:
    if os.environ.get("SE_INSECURE_SSL", "").strip().lower() in {"1", "true", "yes", "on"}:
        return ssl._create_unverified_context()
    context = ssl.create_default_context()
    # Prefer certifi bundle when available to avoid host Python/macOS trust-store mismatches.
    try:
        import certifi  # type: ignore

        context.load_verify_locations(cafile=certifi.where())
    except Exception:
        pass
    return context


SSL_CONTEXT = build_ssl_context()


@dataclass
class RuntimeItem:
    service: str
    version: str
    platform: str
    os_version: str
    arch: str
    path: Path
    install_path: str
    binaries: list[str] = field(default_factory=list)
    extensions: list[str] = field(default_factory=list)
    signed: str = ""
    notarized: str = "No"
    status: str = "stable"

    @property
    def key(self) -> tuple[str, str, str, str]:
        return (self.service, self.version, self.platform, self.arch)


@dataclass
class ServerRuntime:
    service: str
    version: str
    platform: str
    os_version: str
    arch: str
    status: str = ""
    sha256: str = ""
    size_bytes: str = ""
    release_date: str = ""
    package_url: str = ""
    install_path: str = ""

    @property
    def key(self) -> tuple[str, str, str, str]:
        return (self.service, self.version, self.platform, self.arch)


def current_platform() -> str:
    if platform.system() == "Darwin":
        return "macos"
    return platform.system().lower()


def current_os_version() -> str:
    system = platform.system()
    if system == "Darwin":
        version = (platform.mac_ver()[0] or "").strip()
        return version
    release = (platform.release() or "").strip()
    return release


def infer_version(service: str, runtime_name: str) -> str:
    patterns = {
        "php": ("php",),
        "phpmyadmin": ("phpmyadmin-", "phpmyadmin", "pma-", "pma"),
        "apache": ("apache-", "httpd-"),
        "nginx": ("nginx-", "nginx"),
        "mysql": ("mysql-",),
        "mariadb": ("mariadb-", "mariadb@"),
        "mongodb": ("mongodb-", "mongodb"),
        "postgresql": ("postgresql-", "postgresql@"),
        "redis": ("redis-", "redis"),
        "memcached": ("memcached-", "memcached"),
        "mailpit": ("mailpit-", "mailpit"),
        "node": ("node-", "node"),
    }
    for prefix in patterns.get(service, ()):
        if runtime_name.startswith(prefix):
            return runtime_name[len(prefix) :]
    if runtime_name == "current":
        return "current"
    return runtime_name


def looks_like_service_dir(service: str, path: Path) -> bool:
    name = path.name.lower()
    prefixes = SERVICE_PREFIXES.get(service, ())
    return any(name.startswith(prefix) for prefix in prefixes)


def detect_binaries(service: str, runtime_path: Path) -> list[str]:
    found = []
    for binary in DEFAULT_BINARIES.get(service, ()):
        if (runtime_path / binary).is_file():
            found.append(binary)
    return found or list(DEFAULT_BINARIES.get(service, ()))


def detect_php_extensions(runtime_path: Path) -> list[str]:
    extension_root = runtime_path / "lib" / "php" / "extensions"
    if not extension_root.is_dir():
        return []
    names = {item.stem for item in extension_root.glob("*/*.so")}
    return sorted(names)


def detect_runtime_os_version(service: str, runtime_path: Path) -> str:
    if current_platform() != "macos":
        return ""
    candidates = [runtime_path / rel for rel in DEFAULT_BINARIES.get(service, ())]
    if service == "phpmyadmin":
        return ""
    binary = next((item for item in candidates if item.is_file()), None)
    if binary is None:
        return ""
    # Prefer vtool output (minos), fallback to otool if needed.
    try:
        result = subprocess.run(
            ["vtool", "-show-build", str(binary)],
            capture_output=True,
            text=True,
            check=False,
        )
        text = (result.stdout or "") + "\n" + (result.stderr or "")
        match = re.search(r"\bminos\s+([0-9]+(?:\.[0-9]+){0,2})\b", text)
        if match:
            return match.group(1)
    except Exception:
        pass
    try:
        result = subprocess.run(
            ["otool", "-l", str(binary)],
            capture_output=True,
            text=True,
            check=False,
        )
        text = (result.stdout or "") + "\n" + (result.stderr or "")
        match = re.search(r"\bminos\s+([0-9]+(?:\.[0-9]+){0,2})\b", text)
        if match:
            return match.group(1)
    except Exception:
        pass
    return ""


def collect_macho_files(root: Path, candidates: list[str] | None = None) -> list[Path]:
    macho_files: list[Path] = []
    if not root.exists():
        return macho_files
    if candidates:
        for rel_path in candidates:
            path = root / rel_path
            if not path.is_file() or path.is_symlink():
                continue
            probe = subprocess.run(["file", str(path)], capture_output=True, text=False, check=False)
            output = (probe.stdout or b"").decode("utf-8", "replace")
            if "Mach-O" in output:
                macho_files.append(path)
        return macho_files

    for path in root.rglob("*"):
        if not path.is_file() or path.is_symlink():
            continue
        probe = subprocess.run(["file", str(path)], capture_output=True, text=False, check=False)
        output = (probe.stdout or b"").decode("utf-8", "replace")
        if "Mach-O" in output:
            macho_files.append(path)
    return macho_files


def detect_runtime_signature_state(runtime_path: Path, runtime_binaries: list[str] | None = None) -> str:
    if platform.system() != "Darwin":
        return "Unknown"
    macho_files = collect_macho_files(runtime_path, runtime_binaries)
    if not macho_files:
        return "N/A"
    if shutil.which("codesign") is None:
        return "Unknown"
    result = subprocess.run(["codesign", "-dv", "--verbose=4", str(macho_files[0])], capture_output=True, text=True, check=False)
    if result.returncode != 0:
        return "No"
    output = (result.stdout or "") + "\n" + (result.stderr or "")
    if "Signature=adhoc" in output or "adhoc,linker-signed" in output or "TeamIdentifier=not set" in output:
        return "No"
    return "Yes"


def _pkg_is_stapled(pkg_path: Path) -> bool:
    if platform.system() != "Darwin":
        return False
    if not pkg_path.is_file():
        return False
    xcrun = shutil.which("xcrun")
    if xcrun is not None:
        cmd = ["xcrun", "stapler", "validate", str(pkg_path)]
        result = subprocess.run(cmd, capture_output=True, text=True, check=False)
        if result.returncode == 0:
            return True
    pkgutil = shutil.which("pkgutil")
    if pkgutil is not None:
        cmd = [pkgutil, "--check-signature", str(pkg_path)]
        result = subprocess.run(cmd, capture_output=True, text=True, check=False)
        output = ((result.stdout or "") + "\n" + (result.stderr or "")).strip()
        if "Notarization: trusted by the Apple notary service" in output:
            return True
    spctl = shutil.which("spctl")
    if spctl is not None:
        cmd = [spctl, "-a", "-vvv", "-t", "install", str(pkg_path)]
        result = subprocess.run(cmd, capture_output=True, text=True, check=False)
        if result.returncode == 0:
            return True
    return False


def detect_runtime_staple_state(runtime_path: Path, service: str, version: str, runtime_platform: str, arch: str) -> str:
    if platform.system() != "Darwin":
        return "Unknown"
    archive_path = runtime_notary_archive_path(runtime_path, service, version, runtime_platform, arch)
    if archive_path.suffix.lower() == ".pkg":
        if _pkg_is_stapled(archive_path):
            return "Yes"
        return "No"
    marker_path = archive_path.with_suffix(".notarized")
    legacy_marker_path = archive_path.with_suffix(".stapled")
    if not marker_path.exists() and not legacy_marker_path.exists():
        return "No"
    return "Yes"


def scan_local_runtimes(runtime_root: Path, service: str) -> list[RuntimeItem]:
    items: list[RuntimeItem] = []
    for relative_dir in SERVICE_DIRS.get(service, (service,)):
        base = runtime_root / relative_dir
        if not base.is_dir():
            continue
        for child in sorted(base.iterdir()):
            if not child.is_dir():
                continue
            if service in (
                "apache",
                "nginx",
                "mysql",
                "mariadb",
                "mongodb",
                "postgresql",
            ) and not looks_like_service_dir(service, child):
                continue
            version = infer_version(service, child.name)
            items.append(
                RuntimeItem(
                    service=service,
                    version=version,
                    platform=current_platform(),
                    os_version=detect_runtime_os_version(service, child) or current_os_version(),
                    arch=platform.machine(),
                    path=child,
                    install_path=f"{service}/{child.name}",
                    binaries=detect_binaries(service, child),
                    extensions=detect_php_extensions(child) if service == "php" else [],
                    signed=detect_runtime_signature_state(child, detect_binaries(service, child)),
                    notarized=detect_runtime_staple_state(child, service, version, current_platform(), platform.machine()),
                )
            )
    return items


def runtime_from_manifest(raw: dict[str, Any]) -> ServerRuntime:
    return ServerRuntime(
        service=str(raw.get("service", "")),
        version=str(raw.get("version", "")),
        platform=str(raw.get("platform", "")),
        os_version=str(raw.get("osVersion") or raw.get("os_version") or ""),
        arch=str(raw.get("arch", "")),
        status=str(raw.get("status", "")),
        sha256=str(raw.get("sha256", "")),
        size_bytes=str(raw.get("sizeBytes") or raw.get("size_bytes") or ""),
        release_date=str(raw.get("releaseDate") or raw.get("release_date") or ""),
        package_url=str(raw.get("packageUrl") or raw.get("package_url") or ""),
        install_path=str(raw.get("installPath") or raw.get("install_path") or ""),
    )


def human_size(value: str) -> str:
    try:
        size = float(value)
    except (TypeError, ValueError):
        return value
    units = ("B", "KB", "MB", "GB", "TB")
    unit = 0
    while size >= 1024 and unit < len(units) - 1:
        size /= 1024
        unit += 1
    if unit == 0:
        return f"{int(size)} {units[unit]}"
    return f"{size:.1f} {units[unit]}"


def human_date(value: str) -> str:
    if not value:
        return ""
    normalized = value.strip()
    try:
        parsed = datetime.fromisoformat(normalized.replace("Z", "+00:00"))
        local = parsed.astimezone()
        return local.strftime("%Y-%m-%d %H:%M")
    except ValueError:
        return value


def manifest_items(payload: Any) -> list[ServerRuntime]:
    if isinstance(payload, list):
        raw_items = payload
    elif isinstance(payload, dict):
        raw_items = payload.get("runtimes") or payload.get("items") or payload.get("data") or []
        if isinstance(raw_items, dict):
            raw_items = raw_items.get("runtimes") or raw_items.get("items") or []
    else:
        raw_items = []
    return [runtime_from_manifest(item) for item in raw_items if isinstance(item, dict)]


def make_runtime_archive(runtime_path: Path, service: str, version: str, runtime_platform: str, arch: str) -> Path:
    temp_dir = Path(tempfile.mkdtemp(prefix="se-runtime-upload-"))
    archive_path = temp_dir / f"{service}-{version}-{runtime_platform}-{arch}.tar.gz"
    with tarfile.open(archive_path, "w:gz") as archive:
        archive.add(runtime_path, arcname=runtime_path.name)
    return archive_path


def runtime_notary_archive_path(runtime_path: Path, service: str, version: str, runtime_platform: str, arch: str) -> Path:
    del service, version, runtime_platform, arch
    pkg_path = runtime_path.parent / f"{runtime_path.name}.pkg"
    if pkg_path.exists():
        return pkg_path
    return runtime_path.parent / f"{runtime_path.name}.zip"


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_api_error_body(body: str) -> str:
    detail = body.strip()
    try:
        payload = json.loads(body)
        if isinstance(payload, dict):
            message = payload.get("message")
            code = payload.get("code")
            if message and code:
                return f"{code}: {message}"
            if message:
                return str(message)
    except json.JSONDecodeError:
        pass
    return detail


class RuntimeUploadError(RuntimeError):
    pass


def load_config() -> dict[str, Any]:
    try:
        with CONFIG_PATH.open("r", encoding="utf-8") as handle:
            payload = json.load(handle)
        if isinstance(payload, dict):
            return payload
    except FileNotFoundError:
        pass
    except (OSError, json.JSONDecodeError):
        pass
    return {}


def save_config(config: dict[str, Any]) -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    with CONFIG_PATH.open("w", encoding="utf-8") as handle:
        json.dump(config, handle, indent=2, sort_keys=True)


def api_post_form(url: str, fields: dict[str, str], headers: dict[str, str] | None = None) -> dict[str, Any]:
    encoded = urllib.parse.urlencode(fields).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=encoded,
        headers={
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept": "application/json",
            **(headers or {}),
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=30, context=SSL_CONTEXT) as response:
        payload = json.loads(response.read().decode("utf-8"))
    if not isinstance(payload, dict):
        raise RuntimeError("Login returned an unexpected response.")
    return payload


def format_http_error(exc: urllib.error.HTTPError) -> str:
    body = exc.read().decode("utf-8", "replace")
    detail = body.strip()
    try:
        payload = json.loads(body)
        if isinstance(payload, dict):
            message = payload.get("message")
            code = payload.get("code")
            if message and code:
                detail = f"{code}: {message}"
            elif message:
                detail = str(message)
    except json.JSONDecodeError:
        pass
    if detail:
        return f"HTTP {exc.code} {exc.reason}: {detail}"
    return f"HTTP {exc.code} {exc.reason}"


def multipart_upload(
    url: str,
    token: str,
    extra_headers: dict[str, str],
    fields: list[tuple[str, str]],
    file_path: Path,
    file_field_name: str,
    file_content_type: str,
    progress_callback,
) -> str:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in ("http", "https"):
        raise ValueError(f"Unsupported upload URL scheme: {parsed.scheme}")
    if not parsed.hostname:
        raise ValueError("Upload URL is missing a host.")

    boundary = f"----ServerEngineRuntime{int(time.time() * 1000)}"
    field_parts: list[bytes] = []
    for name, value in fields:
        field_parts.append(
            (
                f"--{boundary}\r\n"
                f'Content-Disposition: form-data; name="{name}"\r\n\r\n'
                f"{value}\r\n"
            ).encode("utf-8")
        )
    file_header = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="{file_field_name}"; filename="{file_path.name}"\r\n'
        f"Content-Type: {file_content_type}\r\n\r\n"
    ).encode("utf-8")
    closing = f"\r\n--{boundary}--\r\n".encode("utf-8")
    file_size = file_path.stat().st_size
    total_size = sum(len(part) for part in field_parts) + len(file_header) + file_size + len(closing)

    path = parsed.path or "/"
    if parsed.query:
        path = f"{path}?{parsed.query}"
    if parsed.scheme == "https":
        connection = http.client.HTTPSConnection(parsed.hostname, parsed.port, timeout=60, context=SSL_CONTEXT)
    else:
        connection = http.client.HTTPConnection(parsed.hostname, parsed.port, timeout=60)
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": f"multipart/form-data; boundary={boundary}",
        "Content-Length": str(total_size),
        "Accept": "application/json",
        **extra_headers,
    }

    sent = 0

    def send_chunk(chunk: bytes) -> None:
        nonlocal sent
        connection.send(chunk)
        sent += len(chunk)
        progress_callback(min(100, int(sent * 100 / total_size)))

    try:
        connection.putrequest("POST", path)
        for name, value in headers.items():
            connection.putheader(name, value)
        connection.endheaders()
        for part in field_parts:
            send_chunk(part)
        send_chunk(file_header)
        with file_path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 512), b""):
                send_chunk(chunk)
        send_chunk(closing)

        response = connection.getresponse()
        body = response.read().decode("utf-8", "replace")
        if response.status < 200 or response.status >= 300:
            detail = parse_api_error_body(body)
            raise RuntimeUploadError(f"HTTP {response.status} {response.reason}: {detail}")
        return body
    finally:
        connection.close()


class UploadProgressDialog(tk.Toplevel):
    def __init__(self, parent: tk.Tk, title: str) -> None:
        super().__init__(parent)
        self.title(title)
        self.resizable(False, False)
        self.protocol("WM_DELETE_WINDOW", lambda: None)
        self.transient(parent)
        self.grab_set()

        body = ttk.Frame(self, padding=18)
        body.pack(fill="both", expand=True)
        self.status = tk.StringVar(value="Preparing upload...")
        ttk.Label(body, textvariable=self.status, width=54).pack(anchor="w", pady=(0, 10))
        self.progress = ttk.Progressbar(body, mode="indeterminate", length=420)
        self.progress.pack(fill="x")
        self.progress.start(12)
        self.percent = tk.StringVar(value="")
        ttk.Label(body, textvariable=self.percent).pack(anchor="e", pady=(8, 0))

        self.geometry(f"+{parent.winfo_rootx() + 180}+{parent.winfo_rooty() + 160}")

    def set_status(self, message: str) -> None:
        self.status.set(message)

    def set_progress(self, percent: int) -> None:
        self.progress.stop()
        self.progress.configure(mode="determinate", maximum=100, value=percent)
        self.percent.set(f"{percent}%")

    def close(self) -> None:
        self.grab_release()
        self.destroy()


class LoginDialog(tk.Toplevel):
    def __init__(self, parent: tk.Tk, config: dict[str, Any]) -> None:
        super().__init__(parent)
        self.title("Admin Login")
        self.resizable(False, False)
        self.result: dict[str, str] | None = None

        self.site_url = tk.StringVar(value=str(config.get("site_url", "")))
        self.email = tk.StringVar(value=str(config.get("email", "")))
        self.password = tk.StringVar()
        self.status = tk.StringVar(value="Login with a WordPress admin account.")

        body = ttk.Frame(self, padding=18)
        body.pack(fill="both", expand=True)

        ttk.Label(body, text="Site URL").grid(row=0, column=0, sticky="w", pady=5)
        ttk.Entry(body, textvariable=self.site_url, width=46).grid(row=0, column=1, sticky="ew", pady=5)
        ttk.Label(body, text="Admin Email").grid(row=1, column=0, sticky="w", pady=5)
        ttk.Entry(body, textvariable=self.email, width=46).grid(row=1, column=1, sticky="ew", pady=5)
        ttk.Label(body, text="Password").grid(row=2, column=0, sticky="w", pady=5)
        password_entry = ttk.Entry(body, textvariable=self.password, width=46, show="*")
        password_entry.grid(row=2, column=1, sticky="ew", pady=5)

        ttk.Label(body, textvariable=self.status, foreground="#555").grid(
            row=3, column=0, columnspan=2, sticky="w", pady=(8, 6)
        )

        actions = ttk.Frame(body)
        actions.grid(row=4, column=0, columnspan=2, sticky="e", pady=(8, 0))
        ttk.Button(actions, text="Cancel", command=self.cancel).pack(side="right", padx=(6, 0))
        self.login_button = ttk.Button(actions, text="Login", command=self.login)
        self.login_button.pack(side="right")

        body.columnconfigure(1, weight=1)
        self.bind("<Return>", lambda _event: self.login())
        self.protocol("WM_DELETE_WINDOW", self.cancel)
        self.transient(parent)
        self.grab_set()
        password_entry.focus_set()
        self.wait_visibility()
        self.geometry(f"+{parent.winfo_screenwidth() // 2 - 230}+{parent.winfo_screenheight() // 2 - 120}")

    def cancel(self) -> None:
        self.result = None
        self.destroy()

    def login(self) -> None:
        site = self.site_url.get().strip().rstrip("/")
        email = self.email.get().strip()
        password = self.password.get()
        if not site or not email or not password:
            self.status.set("Site URL, email, and password are required.")
            return

        self.login_button.configure(state="disabled")
        self.status.set("Logging in...")
        self.update_idletasks()
        try:
            payload = api_post_form(
                f"{site}/wp-json/engine/v1/auth/login",
                {"email": email, "password": password},
            )
            token = str(payload.get("access_token") or payload.get("token") or "")
            if not token:
                raise RuntimeError("Login response did not include access_token.")
            self.result = {"site_url": site, "email": email, "access_token": token}
            self.destroy()
        except Exception as exc:  # noqa: BLE001 - login dialog should show exact failure.
            self.status.set("Login failed.")
            self.login_button.configure(state="normal")


class RuntimeUploaderApp(tk.Tk):
    IDENTITY_PLACEHOLDER = "Select signing certificate"

    def __init__(self) -> None:
        super().__init__()
        self._main_thread_id = threading.get_ident()
        self._ui_queue: queue.SimpleQueue[tuple[Any, tuple[Any, ...]]] = queue.SimpleQueue()
        self._ui_pump_after_id: str | None = None
        self._ui_pump_active = True
        self._ui_pump_after_id = super().after(16, self._drain_ui_queue)
        self.title("Server Engine Admin Login")
        self.geometry("520x260")

        self.local_items: dict[str, list[RuntimeItem]] = {service: [] for service in SERVICES}
        self.server_items: dict[str, list[ServerRuntime]] = {service: [] for service in SERVICES}
        self.local_selected_iid_by_service: dict[str, str] = {service: "" for service in SERVICES}
        self.local_tree_by_service: dict[str, ttk.Treeview] = {}
        self.server_tree_by_service: dict[str, ttk.Treeview] = {}
        self.upload_buttons: list[ttk.Button] = []
        self.fetch_buttons: list[ttk.Button] = []
        self.sign_buttons: list[ttk.Button] = []
        self.runtime_action_buttons: list[ttk.Button] = []
        self.login_in_progress = False
        self.fetch_in_progress = False
        self.upload_in_progress = False
        self.sign_in_progress = False
        self.runtime_task_in_progress = False
        self.reload_on_tab_change = True
        self.local_poll_after_id: str | None = None
        self.local_poll_interval_ms = 5000
        self.local_refresh_lock = threading.Lock()
        self.local_refresh_running = False
        self.local_refresh_pending = False
        self.local_refresh_pending_root: Path | None = None
        self.app_pkg_file = tk.StringVar(value="")
        self.app_pkg_root = tk.StringVar(value=str(DEFAULT_PKG_ROOT))
        self.app_pkg_version = tk.StringVar(value="")
        self.app_pkg_platform = tk.StringVar(value="macos")
        self.app_pkg_arch = tk.StringVar(value="arm64")
        self.app_pkg_channel = tk.StringVar(value="stable")
        self.app_pkg_required = tk.BooleanVar(value=False)
        self.app_pkg_changelog = tk.StringVar(value="")
        self.app_pkg_server_items: list[dict[str, str]] = []
        self.app_pkg_tree: ttk.Treeview | None = None
        self.app_pkg_combo: ttk.Combobox | None = None

        self.config_data = load_config()
        self.access_token = str(self.config_data.get("access_token") or "")
        self.site_url = tk.StringVar(value=str(self.config_data.get("site_url", "")))
        self.admin_email = tk.StringVar(value=str(self.config_data.get("email", "")))
        self.admin_password = tk.StringVar(value=str(self.config_data.get("password", "")))
        self.runtime_root = tk.StringVar(value=str(self.config_data.get("runtime_root") or DEFAULT_RUNTIME_ROOT))
        self.requires_app_version = tk.StringVar(value=str(self.config_data.get("requires_app_version") or ">=1.0.0"))
        self.local_http_dev = tk.BooleanVar(value=bool(self.config_data.get("local_http_dev", False)))
        self.app_pkg_file.set(str(self.config_data.get("app_pkg_file") or ""))
        self.app_pkg_root.set(str(self.config_data.get("app_pkg_root") or DEFAULT_PKG_ROOT))
        self.app_pkg_version.set(str(self.config_data.get("app_pkg_version") or ""))
        self.app_pkg_platform.set(str(self.config_data.get("app_pkg_platform") or "macos"))
        self.app_pkg_arch.set(str(self.config_data.get("app_pkg_arch") or "arm64"))
        self.app_pkg_channel.set(str(self.config_data.get("app_pkg_channel") or "stable"))
        self.app_pkg_required.set(bool(self.config_data.get("app_pkg_required", False)))
        self.app_pkg_changelog.set(str(self.config_data.get("app_pkg_changelog") or ""))
        self.runtime_sign_identity = tk.StringVar(value=str(self.config_data.get("runtime_sign_identity") or ""))
        self.runtime_sign_identity_map: dict[str, str] = {}
        self.runtime_sign_identity_combo: ttk.Combobox | None = None
        self.runtime_pkg_sign_identity = tk.StringVar(value=str(self.config_data.get("runtime_pkg_sign_identity") or ""))
        self.runtime_pkg_sign_identity_map: dict[str, str] = {}
        self.runtime_pkg_sign_identity_combo: ttk.Combobox | None = None
        self.runtime_notary_apple_id = tk.StringVar(value=str(self.config_data.get("runtime_notary_apple_id") or ""))
        self.runtime_notary_team_id = tk.StringVar(value=str(self.config_data.get("runtime_notary_team_id") or ""))
        self.runtime_notary_password = tk.StringVar(value=str(self.config_data.get("runtime_notary_password") or ""))
        self.runtime_notary_submission_id = tk.StringVar(value=str(self.config_data.get("runtime_notary_submission_id") or ""))
        self.runtime_notary_apple_id.trace_add("write", lambda *_: self.save_current_config())
        self.runtime_notary_team_id.trace_add("write", lambda *_: self.save_current_config())
        self.runtime_notary_password.trace_add("write", lambda *_: self.save_current_config())
        self.runtime_notary_submission_id.trace_add("write", lambda *_: self.save_current_config())

        if self.access_token and self.site_url.get().strip() and self.admin_email.get().strip():
            self._build_uploader()
        else:
            self._build_startup_login()

    def _build_startup_login(self) -> None:
        self.login_frame = ttk.Frame(self, padding=20)
        self.login_frame.pack(fill="both", expand=True)

        ttk.Label(self.login_frame, text="Admin Login", font=("TkDefaultFont", 16, "bold")).grid(
            row=0, column=0, columnspan=2, sticky="w", pady=(0, 14)
        )
        ttk.Label(self.login_frame, text="Site URL").grid(row=1, column=0, sticky="w", pady=5)
        ttk.Entry(self.login_frame, textvariable=self.site_url, width=44).grid(row=1, column=1, sticky="ew", pady=5)
        ttk.Label(self.login_frame, text="Admin Email").grid(row=2, column=0, sticky="w", pady=5)
        ttk.Entry(self.login_frame, textvariable=self.admin_email, width=44).grid(row=2, column=1, sticky="ew", pady=5)
        ttk.Label(self.login_frame, text="Password").grid(row=3, column=0, sticky="w", pady=5)
        password_entry = ttk.Entry(self.login_frame, textvariable=self.admin_password, width=44, show="*")
        password_entry.grid(row=3, column=1, sticky="ew", pady=5)
        ttk.Checkbutton(self.login_frame, text="Local HTTP dev mode", variable=self.local_http_dev).grid(
            row=4, column=1, sticky="w", pady=(4, 0)
        )

        self.login_status = tk.StringVar(value="Login with a WordPress admin account.")
        ttk.Label(self.login_frame, textvariable=self.login_status, foreground="#555").grid(
            row=5, column=0, columnspan=2, sticky="w", pady=(10, 4)
        )
        actions = ttk.Frame(self.login_frame)
        actions.grid(row=6, column=0, columnspan=2, sticky="e", pady=(8, 0))
        ttk.Button(actions, text="Quit", command=self.destroy).pack(side="right", padx=(6, 0))
        self.start_login_button = ttk.Button(actions, text="Login", command=self.startup_login)
        self.start_login_button.pack(side="right")

        self.login_frame.columnconfigure(1, weight=1)
        self.bind("<Return>", lambda _event: self.startup_login())
        password_entry.focus_set()

    def startup_login(self) -> None:
        if self.login_in_progress:
            return
        site = self.site_url.get().strip().rstrip("/")
        email = self.admin_email.get().strip()
        password = self.admin_password.get()
        if not site or not email or not password:
            self.login_status.set("Site URL, email, and password are required.")
            return

        self.login_in_progress = True
        self.start_login_button.configure(state="disabled")
        self.login_status.set("Logging in...")
        self.update_idletasks()
        try:
            payload = api_post_form(
                f"{site}/wp-json/engine/v1/auth/login",
                {"email": email, "password": password},
                self.dev_http_headers(),
            )
            token = str(payload.get("access_token") or payload.get("token") or "")
            if not token:
                raise RuntimeError("Login response did not include access_token.")
            self.access_token = token
            self.site_url.set(site)
            self.admin_email.set(email)
            self.save_current_config()
            self.login_frame.destroy()
            self.unbind("<Return>")
            self._build_uploader()
        except urllib.error.HTTPError as exc:
            self.login_in_progress = False
            self.login_status.set("Login failed.")
            self.start_login_button.configure(state="normal")
            self.log(f"Admin login failed: {format_http_error(exc)}")
        except Exception as exc:  # noqa: BLE001 - login screen should surface exact failure.
            self.login_in_progress = False
            self.login_status.set("Login failed.")
            if hasattr(self, "start_login_button") and self.start_login_button.winfo_exists():
                self.start_login_button.configure(state="normal")
            self.log(f"Admin login failed: {exc}")

    def _build_uploader(self) -> None:
        if hasattr(self, "login_frame") and self.login_frame.winfo_exists():
            self.login_frame.destroy()
        if hasattr(self, "uploader_frame") and self.uploader_frame.winfo_exists():
            self.uploader_frame.destroy()
        self.title("Server Engine Runtime Uploader")
        self.geometry("1400x760")
        self._build_ui()
        self._reload_sign_identities()
        self._reload_pkg_sign_identities()
        self.reload_local()
        self.fetch_manifest()
        self.start_local_runtime_poll()

    def open_uploader(self) -> None:
        self._build_uploader()

    def _build_ui(self) -> None:
        self.uploader_frame = ttk.Frame(self)
        self.uploader_frame.pack(fill="both", expand=True)

        config = ttk.LabelFrame(self.uploader_frame, text="Admin Server")
        config.pack(fill="x", padx=10, pady=(10, 6))

        self._entry(config, "Site URL", self.site_url, 0, 0, width=38)
        self._entry(config, "Admin Email", self.admin_email, 0, 2, width=30)
        self._entry(config, "Requires App", self.requires_app_version, 0, 4, width=18)
        ttk.Checkbutton(config, text="Local HTTP dev", variable=self.local_http_dev, command=self.save_current_config).grid(
            row=0, column=6, sticky="w", padx=4, pady=6
        )

        ttk.Label(config, text="Runtime Root").grid(row=1, column=0, sticky="w", padx=(10, 4), pady=6)
        ttk.Entry(config, textvariable=self.runtime_root, width=52).grid(
            row=1, column=1, columnspan=5, sticky="ew", padx=4, pady=6
        )
        ttk.Button(config, text="Browse", command=self.browse_runtime_root).grid(row=1, column=6, padx=4, pady=6)
        ttk.Button(config, text="Reload Local", command=self.reload_local).grid(row=0, column=7, padx=4, pady=6)
        fetch_button = ttk.Button(config, text="Fetch Server List", command=self.fetch_manifest)
        fetch_button.grid(row=0, column=8, padx=4, pady=6)
        self.fetch_buttons.append(fetch_button)
        auth_box = ttk.Frame(config)
        auth_box.grid(row=1, column=7, columnspan=2, sticky="w", padx=4, pady=6)
        self.login_button = ttk.Button(auth_box, text="Login…", command=self.switch_admin)
        self.login_button.pack(side="left")
        self.logout_button = ttk.Button(auth_box, text="Logout", command=self.logout_admin)
        self.logout_button.pack(side="left", padx=(8, 0))
        ttk.Label(config, text="PKG Root").grid(row=2, column=0, sticky="w", padx=(10, 4), pady=6)
        ttk.Entry(config, textvariable=self.app_pkg_root, width=52).grid(
            row=2, column=1, columnspan=5, sticky="ew", padx=4, pady=6
        )
        ttk.Button(config, text="Browse", command=self.browse_app_pkg_root).grid(row=2, column=6, padx=4, pady=6)
        ttk.Label(config, text="App Certificate").grid(row=3, column=0, sticky="w", padx=(10, 4), pady=6)
        self.runtime_sign_identity_combo = ttk.Combobox(config, state="readonly", width=52)
        self.runtime_sign_identity_combo.grid(row=3, column=1, columnspan=5, sticky="ew", padx=4, pady=6)
        ttk.Button(config, text="Reload", command=self._reload_sign_identities).grid(row=3, column=6, padx=4, pady=6)
        self.runtime_sign_identity_combo.bind("<<ComboboxSelected>>", self._on_sign_identity_selected)
        ttk.Label(config, text="Installer Certificate").grid(row=4, column=0, sticky="w", padx=(10, 4), pady=6)
        self.runtime_pkg_sign_identity_combo = ttk.Combobox(config, state="readonly", width=52)
        self.runtime_pkg_sign_identity_combo.grid(row=4, column=1, columnspan=5, sticky="ew", padx=4, pady=6)
        ttk.Button(config, text="Reload", command=self._reload_pkg_sign_identities).grid(row=4, column=6, padx=4, pady=6)
        self.runtime_pkg_sign_identity_combo.bind("<<ComboboxSelected>>", self._on_pkg_sign_identity_selected)
        ttk.Label(config, text="Notary Apple ID").grid(row=5, column=0, sticky="w", padx=(10, 4), pady=6)
        ttk.Entry(config, textvariable=self.runtime_notary_apple_id, width=52).grid(
            row=5, column=1, columnspan=5, sticky="ew", padx=4, pady=6
        )
        ttk.Label(config, text="Notary Team ID").grid(row=6, column=0, sticky="w", padx=(10, 4), pady=6)
        ttk.Entry(config, textvariable=self.runtime_notary_team_id, width=52).grid(
            row=6, column=1, columnspan=5, sticky="ew", padx=4, pady=6
        )
        ttk.Label(config, text="Notary Password").grid(row=7, column=0, sticky="w", padx=(10, 4), pady=6)
        ttk.Entry(config, textvariable=self.runtime_notary_password, width=52, show="*").grid(
            row=7, column=1, columnspan=5, sticky="ew", padx=4, pady=6
        )
        ttk.Label(config, text="Notary Submission ID").grid(row=8, column=0, sticky="w", padx=(10, 4), pady=6)
        ttk.Entry(config, textvariable=self.runtime_notary_submission_id, width=52).grid(
            row=8, column=1, columnspan=5, sticky="ew", padx=4, pady=6
        )
        config.columnconfigure(1, weight=1)

        self.main_layout = ttk.PanedWindow(self, orient="horizontal")
        self.main_layout.pack(fill="both", expand=True, padx=10, pady=6)

        left_panel = ttk.Frame(self.main_layout)
        right_panel = ttk.Frame(self.main_layout)
        self.main_layout.add(left_panel, weight=4)
        self.main_layout.add(right_panel, weight=2)

        self.tabs = ttk.Notebook(left_panel)
        self.tabs.pack(fill="both", expand=True)

        for service in SERVICES:
            self._build_service_tab(service)
        self._build_app_pkg_tab()
        self.tabs.bind("<<NotebookTabChanged>>", self.on_tab_changed)

        log_frame = ttk.LabelFrame(right_panel, text="Log")
        log_frame.pack(fill="both", expand=True)
        log_wrap = ttk.Frame(log_frame)
        log_wrap.pack(fill="both", expand=True, padx=8, pady=8)
        self.log_text = tk.Text(log_wrap, wrap="word", state="disabled")
        log_scroll = ttk.Scrollbar(log_wrap, orient="vertical", command=self.log_text.yview)
        self.log_text.configure(yscrollcommand=log_scroll.set)
        self.log_text.pack(side="left", fill="both", expand=True)
        log_scroll.pack(side="right", fill="y")
        self._refresh_login_ui()

    def _entry(
        self,
        parent: ttk.Frame,
        label: str,
        variable: tk.StringVar,
        row: int,
        column: int,
        width: int,
        show: str | None = None,
    ) -> None:
        ttk.Label(parent, text=label).grid(row=row, column=column, sticky="w", padx=(10, 4), pady=6)
        kwargs = {"textvariable": variable, "width": width}
        if show is not None:
            kwargs["show"] = show
        ttk.Entry(parent, **kwargs).grid(row=row, column=column + 1, sticky="ew", padx=4, pady=6)

    def _build_service_tab(self, service: str) -> None:
        frame = ttk.Frame(self.tabs)
        self.tabs.add(frame, text=service.upper())

        toolbar = ttk.Frame(frame)
        toolbar.pack(fill="x", pady=(8, 4))
        upload_button = ttk.Button(toolbar, text="Upload", command=lambda s=service: self.upload_selected(s))
        upload_button.pack(side="left", padx=4)
        self.upload_buttons.append(upload_button)
        sign_button = ttk.Button(toolbar, text="Sign Mach-O", command=lambda s=service: self.sign_selected_runtime(s))
        sign_button.pack(side="left", padx=4)
        self.sign_buttons.append(sign_button)
        check_button = ttk.Button(toolbar, text="Check Mach-O Sign", command=lambda s=service: self.check_selected_runtime_sign(s))
        check_button.pack(side="left", padx=4)
        self.runtime_action_buttons.append(check_button)
        build_pkg_button = ttk.Button(toolbar, text="Build PKG", command=lambda s=service: self.build_selected_runtime_pkg(s))
        build_pkg_button.pack(side="left", padx=4)
        self.runtime_action_buttons.append(build_pkg_button)
        sign_pkg_button = ttk.Button(toolbar, text="Sign PKG", command=lambda s=service: self.sign_selected_runtime_pkg(s))
        sign_pkg_button.pack(side="left", padx=4)
        self.runtime_action_buttons.append(sign_pkg_button)
        notarize_button = ttk.Button(toolbar, text="Notarize", command=lambda s=service: self.notarize_selected_runtime(s))
        notarize_button.pack(side="left", padx=4)
        self.runtime_action_buttons.append(notarize_button)
        staple_button = ttk.Button(toolbar, text="Staple", command=lambda s=service: self.staple_selected_runtime(s))
        staple_button.pack(side="left", padx=4)
        self.runtime_action_buttons.append(staple_button)
        refresh_button = ttk.Button(toolbar, text="Refresh Server List", command=self.fetch_manifest)
        refresh_button.pack(side="left", padx=4)
        self.fetch_buttons.append(refresh_button)

        pane = ttk.PanedWindow(frame, orient="horizontal")
        pane.pack(fill="both", expand=True)

        left = ttk.LabelFrame(pane, text="Local Runtimes")
        right = ttk.LabelFrame(pane, text="Server Runtimes")
        pane.add(left, weight=1)
        pane.add(right, weight=1)

        local_tree = ttk.Treeview(left, columns=("version", "signed", "notarized", "platform", "os_version", "arch", "path"), show="headings", height=18)
        local_tree.heading("version", text="Version")
        local_tree.heading("signed", text="Signed")
        local_tree.heading("notarized", text="Notarized")
        local_tree.heading("platform", text="Platform")
        local_tree.heading("os_version", text="OS Version (local)")
        local_tree.heading("arch", text="Arch")
        local_tree.heading("path", text="Path")
        local_tree.column("version", width=110, anchor="w")
        local_tree.column("signed", width=70, anchor="w")
        local_tree.column("notarized", width=80, anchor="w")
        local_tree.column("platform", width=90, anchor="w")
        local_tree.column("os_version", width=110, anchor="w")
        local_tree.column("arch", width=80, anchor="w")
        local_tree.column("path", width=420, anchor="w")
        local_tree.pack(fill="both", expand=True, padx=6, pady=6)
        local_tree.bind("<<TreeviewSelect>>", lambda _event, s=service: self._on_local_tree_selected(s))

        server_tree = ttk.Treeview(
            right,
            columns=("version", "platform", "os_version", "arch", "status", "sha256", "size", "release", "url"),
            show="headings",
            height=18,
        )
        for name, width in (
            ("version", 90),
            ("platform", 90),
            ("os_version", 90),
            ("arch", 70),
            ("status", 80),
            ("sha256", 110),
            ("size", 100),
            ("release", 150),
            ("url", 320),
        ):
            server_tree.heading(name, text=name.capitalize())
            server_tree.column(name, width=width, anchor="w")
        server_tree.pack(fill="both", expand=True, padx=6, pady=6)

        self.local_tree_by_service[service] = local_tree
        self.server_tree_by_service[service] = server_tree

    def browse_runtime_root(self) -> None:
        selected = filedialog.askdirectory(initialdir=self.runtime_root.get() or str(REPO_ROOT))
        if selected:
            self.runtime_root.set(selected)
            self.save_current_config()
            self.reload_local()

    def browse_app_pkg_root(self) -> None:
        selected = filedialog.askdirectory(initialdir=self.app_pkg_root.get() or str(REPO_ROOT))
        if selected:
            self.app_pkg_root.set(selected)
            self.save_current_config()
            self.reload_app_pkg_candidates()

    def save_current_config(self) -> None:
        save_config(
            {
                "site_url": self.site_url.get().strip().rstrip("/"),
                "email": self.admin_email.get().strip(),
                "password": self.admin_password.get(),
                "access_token": self.access_token,
                "runtime_root": self.runtime_root.get().strip(),
                "requires_app_version": self.requires_app_version.get().strip() or ">=1.0.0",
                "local_http_dev": self.local_http_dev.get(),
                "app_pkg_file": self.app_pkg_file.get().strip(),
                "app_pkg_root": self.app_pkg_root.get().strip(),
                "app_pkg_version": self.app_pkg_version.get().strip(),
                "app_pkg_platform": self.app_pkg_platform.get().strip() or "macos",
                "app_pkg_arch": self.app_pkg_arch.get().strip() or "arm64",
                "app_pkg_channel": self.app_pkg_channel.get().strip() or "stable",
                "app_pkg_required": self.app_pkg_required.get(),
                "app_pkg_changelog": self.app_pkg_changelog.get().strip(),
                "runtime_sign_identity": self.runtime_sign_identity.get().strip(),
                "runtime_pkg_sign_identity": self.runtime_pkg_sign_identity.get().strip(),
                "runtime_notary_apple_id": self.runtime_notary_apple_id.get().strip(),
                "runtime_notary_team_id": self.runtime_notary_team_id.get().strip(),
                "runtime_notary_password": self.runtime_notary_password.get().strip(),
                "runtime_notary_submission_id": self.runtime_notary_submission_id.get().strip(),
            }
        )

    def dev_http_headers(self) -> dict[str, str]:
        if not self.local_http_dev.get():
            return {}
        return {
            "X-Forwarded-Proto": "https",
            "X-Forwarded-Ssl": "on",
            "X-Url-Scheme": "https",
        }

    def switch_admin(self) -> None:
        login = LoginDialog(self, self.config_data | {"site_url": self.site_url.get(), "email": self.admin_email.get()})
        self.wait_window(login)
        if login.result is None:
            return
        self.access_token = login.result["access_token"]
        self.site_url.set(login.result["site_url"])
        self.admin_email.set(login.result["email"])
        self.save_current_config()
        self._refresh_login_ui()
        self.fetch_manifest()

    def logout_admin(self) -> None:
        self.access_token = ""
        self.save_current_config()
        self._refresh_login_ui()

    def _refresh_login_ui(self) -> None:
        is_logged_in = bool(self.access_token and self.site_url.get().strip() and self.admin_email.get().strip())
        if hasattr(self, "login_button"):
            self.login_button.configure(text="Switch Login…" if is_logged_in else "Login…")
        if hasattr(self, "logout_button"):
            self.logout_button.configure(state="normal" if is_logged_in else "disabled")
        if hasattr(self, "login_status"):
            if is_logged_in:
                self.login_status.set(f"Logged in: {self.admin_email.get().strip()} @ {self.site_url.get().strip()}")
            else:
                self.login_status.set("Not logged in.")

    def after(self, ms: int | None = None, func=None, *args):  # type: ignore[override]
        if threading.get_ident() != self._main_thread_id:
            if func is None:
                return f"thread-after-{time.time_ns()}"
            self._ui_queue.put((func, args))
            return f"thread-after-{time.time_ns()}"
        if func is None:
            if ms is None:
                return super().after()
            return super().after(ms)
        if ms is None:
            ms = 0
        return super().after(ms, func, *args)

    def _drain_ui_queue(self) -> None:
        if not self._ui_pump_active:
            return
        try:
            while True:
                callback, args = self._ui_queue.get_nowait()
                try:
                    callback(*args)
                except Exception as exc:  # noqa: BLE001 - UI callbacks should not stop the pump.
                    self._append_log(f"UI callback failed: {exc}")
        except queue.Empty:
            pass
        finally:
            if self._ui_pump_active and self.winfo_exists():
                self._ui_pump_after_id = super().after(16, self._drain_ui_queue)

    def _append_log(self, message: str) -> None:
        timestamp = time.strftime("%H:%M:%S")
        self.log_text.configure(state="normal")
        self.log_text.insert("end", f"[{timestamp}] {message}\n")
        self.log_text.see("end")
        self.log_text.configure(state="disabled")

    def log(self, message: str) -> None:
        if threading.get_ident() != self._main_thread_id:
            self.after(0, self._append_log, message)
            return
        self._append_log(message)

    def log_command(self, cmd: list[str]) -> None:
        self.log(f"$ {' '.join(shlex.quote(part) for part in cmd)}")

    def log_process_result(self, label: str, result: subprocess.CompletedProcess[str]) -> None:
        stdout = (result.stdout or "").strip()
        stderr = (result.stderr or "").strip()
        self.log(f"{label} exit code: {result.returncode}")
        if stdout:
            self.log(f"{label} stdout:\n{stdout}")
        if stderr:
            self.log(f"{label} stderr:\n{stderr}")

    def run_background(self, label: str, target) -> None:
        def worker() -> None:
            try:
                target()
            except urllib.error.HTTPError as exc:
                error_message = format_http_error(exc)
                self.after(0, lambda message=error_message: self.log(f"{label} failed: {message}"))
            except Exception as exc:  # noqa: BLE001 - GUI should surface any worker failure.
                error_message = str(exc)
                self.after(0, lambda message=error_message: self.log(f"{label} failed: {message}"))

        threading.Thread(target=worker, daemon=True).start()

    def set_fetch_buttons_enabled(self, enabled: bool) -> None:
        state = "normal" if enabled else "disabled"
        for button in self.fetch_buttons:
            button.configure(state=state)

    def set_upload_buttons_enabled(self, enabled: bool) -> None:
        state = "normal" if enabled else "disabled"
        for button in self.upload_buttons:
            button.configure(state=state)

    def set_sign_buttons_enabled(self, enabled: bool) -> None:
        state = "normal" if enabled else "disabled"
        for button in self.sign_buttons:
            button.configure(state=state)

    def set_runtime_action_buttons_enabled(self, enabled: bool) -> None:
        state = "normal" if enabled else "disabled"
        for button in self.runtime_action_buttons:
            button.configure(state=state)

    def _reload_sign_identities(self) -> None:
        if self.runtime_sign_identity_combo is None:
            return
        self.runtime_sign_identity_combo.configure(values=[self.IDENTITY_PLACEHOLDER])
        self.runtime_sign_identity_combo.set(self.IDENTITY_PLACEHOLDER)
        saved_identity = self.runtime_sign_identity.get().strip()

        def work() -> None:
            try:
                result = subprocess.run(["security", "find-identity", "-v", "-p", "basic"], capture_output=True, text=True, check=False)
                output = (result.stdout or "") + "\n" + (result.stderr or "")
                labels: list[str] = []
                identity_map: dict[str, str] = {}
                for line in output.splitlines():
                    match = re.search(r"^\s*\d+\)\s+([0-9A-F]{40})\s+\"([^\"]+)\"", line)
                    if not match:
                        continue
                    sha = match.group(1)
                    name = match.group(2).strip()
                    if "Developer ID Application:" not in name:
                        continue
                    label = f"{name} [{sha[:8]}]"
                    identity_map[label] = sha
                    labels.append(label)

                def update_ui() -> None:
                    self.runtime_sign_identity_map.clear()
                    self.runtime_sign_identity_map.update(identity_map)
                    options = [self.IDENTITY_PLACEHOLDER, *labels]
                    self.runtime_sign_identity_combo.configure(values=options)
                    selected_label = next((label for label in labels if label.rsplit(" [", 1)[0].strip() == saved_identity), "")
                    if selected_label:
                        self.runtime_sign_identity_combo.set(selected_label)
                        self.runtime_sign_identity.set(saved_identity)
                    else:
                        self.runtime_sign_identity_combo.set(self.IDENTITY_PLACEHOLDER)
                        self.runtime_sign_identity.set("")
                    self.save_current_config()
                    self.log(f"Loaded {len(labels)} runtime signing identities.")

                self.after(0, update_ui)
            except Exception as exc:
                def fail() -> None:
                    self.runtime_sign_identity_map.clear()
                    self.runtime_sign_identity_combo.configure(values=[self.IDENTITY_PLACEHOLDER])
                    self.runtime_sign_identity_combo.set(self.IDENTITY_PLACEHOLDER)
                    self.runtime_sign_identity.set("")
                    self.log(f"Load runtime signing identities failed: {exc}")

                self.after(0, fail)

        threading.Thread(target=work, daemon=True).start()

    def _reload_pkg_sign_identities(self) -> None:
        if self.runtime_pkg_sign_identity_combo is None:
            return
        self.runtime_pkg_sign_identity_combo.configure(values=[self.IDENTITY_PLACEHOLDER])
        self.runtime_pkg_sign_identity_combo.set(self.IDENTITY_PLACEHOLDER)
        saved_identity = self.runtime_pkg_sign_identity.get().strip()

        def work() -> None:
            try:
                result = subprocess.run(["security", "find-identity", "-v", "-p", "basic"], capture_output=True, text=True, check=False)
                output = (result.stdout or "") + "\n" + (result.stderr or "")
                labels: list[str] = []
                identity_map: dict[str, str] = {}
                for line in output.splitlines():
                    match = re.search(r"^\s*\d+\)\s+([0-9A-F]{40})\s+\"([^\"]+)\"", line)
                    if not match:
                        continue
                    sha = match.group(1)
                    name = match.group(2).strip()
                    if "Developer ID Installer:" not in name and "3rd Party Mac Developer Installer:" not in name:
                        continue
                    label = f"{name} [{sha[:8]}]"
                    identity_map[label] = sha
                    labels.append(label)

                def update_ui() -> None:
                    self.runtime_pkg_sign_identity_map.clear()
                    self.runtime_pkg_sign_identity_map.update(identity_map)
                    options = [self.IDENTITY_PLACEHOLDER, *labels]
                    self.runtime_pkg_sign_identity_combo.configure(values=options)
                    selected_label = next((label for label in labels if label.rsplit(" [", 1)[0].strip() == saved_identity), "")
                    if selected_label:
                        self.runtime_pkg_sign_identity_combo.set(selected_label)
                        self.runtime_pkg_sign_identity.set(saved_identity)
                    else:
                        self.runtime_pkg_sign_identity_combo.set(self.IDENTITY_PLACEHOLDER)
                        self.runtime_pkg_sign_identity.set("")
                    self.save_current_config()
                    self.log(f"Loaded {len(labels)} installer signing identities.")

                self.after(0, update_ui)
            except Exception as exc:
                def fail() -> None:
                    self.runtime_pkg_sign_identity_map.clear()
                    self.runtime_pkg_sign_identity_combo.configure(values=[self.IDENTITY_PLACEHOLDER])
                    self.runtime_pkg_sign_identity_combo.set(self.IDENTITY_PLACEHOLDER)
                    self.runtime_pkg_sign_identity.set("")
                    self.log(f"Load installer signing identities failed: {exc}")

                self.after(0, fail)

        threading.Thread(target=work, daemon=True).start()

    def _on_sign_identity_selected(self, _event: tk.Event | None = None) -> None:
        if self.runtime_sign_identity_combo is None:
            return
        label = self.runtime_sign_identity_combo.get().strip()
        if not label or label == self.IDENTITY_PLACEHOLDER:
            self.runtime_sign_identity.set("")
            self.save_current_config()
            return
        name = label.rsplit(" [", 1)[0].strip()
        self.runtime_sign_identity.set(name)
        self.save_current_config()
        self.log(f"Selected runtime sign identity: {name}")

    def _on_pkg_sign_identity_selected(self, _event: tk.Event | None = None) -> None:
        if self.runtime_pkg_sign_identity_combo is None:
            return
        label = self.runtime_pkg_sign_identity_combo.get().strip()
        if not label or label == self.IDENTITY_PLACEHOLDER:
            self.runtime_pkg_sign_identity.set("")
            self.save_current_config()
            return
        name = label.rsplit(" [", 1)[0].strip()
        self.runtime_pkg_sign_identity.set(name)
        self.save_current_config()
        self.log(f"Selected installer sign identity: {name}")

    def reload_local(self) -> None:
        root = Path(self.runtime_root.get()).expanduser()
        self._request_local_reload(root)

    def local_signature(self, items: list[RuntimeItem]) -> tuple[tuple[str, str, str, str], ...]:
        rows = [(item.version, item.platform, item.arch, str(item.path)) for item in items]
        return tuple(sorted(rows))

    def poll_local_runtimes(self) -> None:
        if not hasattr(self, "tabs"):
            self.start_local_runtime_poll()
            return
        if self.upload_in_progress:
            self.start_local_runtime_poll()
            return
        self.reload_local()
        self.start_local_runtime_poll()

    def start_local_runtime_poll(self) -> None:
        if self.local_poll_after_id is not None:
            try:
                self.after_cancel(self.local_poll_after_id)
            except Exception:
                pass
        self.local_poll_after_id = self.after(self.local_poll_interval_ms, self.poll_local_runtimes)

    def _on_local_tree_selected(self, service: str) -> None:
        tree = self.local_tree_by_service[service]
        selected = tree.selection()
        self.local_selected_iid_by_service[service] = selected[0] if selected else ""

    def _request_local_reload(self, root: Path) -> None:
        if not root.exists() or not root.is_dir():
            self.after(0, lambda: self.log(f"Loaded local runtimes from {root}"))
            return

        with self.local_refresh_lock:
            self.local_refresh_pending_root = root
            if self.local_refresh_running:
                self.local_refresh_pending = True
                return
            self.local_refresh_running = True
            scan_root = root

        def work() -> None:
            try:
                fresh_items = {service: scan_local_runtimes(scan_root, service) for service in SERVICES}
                self.after(0, lambda: self._apply_local_reload(scan_root, fresh_items))
            except Exception as exc:
                self.after(0, lambda: self._finish_local_reload())
                self.after(0, lambda: self.log(f"Loaded local runtimes from {scan_root} failed: {exc}"))

        threading.Thread(target=work, daemon=True).start()

    def _apply_local_reload(self, root: Path, fresh_items: dict[str, list[RuntimeItem]]) -> None:
        try:
            any_changed = False
            for service in SERVICES:
                current_items = self.local_items.get(service, [])
                updated_items = fresh_items.get(service, [])
                if self.local_signature(current_items) != self.local_signature(updated_items):
                    self.local_items[service] = updated_items
                    any_changed = True
                self.refresh_local_tree(service)
            if any_changed:
                self.log(f"Local runtimes updated from {root}")
            self.reload_app_pkg_candidates()
        finally:
            self._finish_local_reload()

    def _finish_local_reload(self) -> None:
        pending_root: Path | None = None
        with self.local_refresh_lock:
            self.local_refresh_running = False
            if self.local_refresh_pending_root is not None:
                pending_root = self.local_refresh_pending_root
            pending = self.local_refresh_pending
            self.local_refresh_pending = False
            self.local_refresh_pending_root = None
        if pending and pending_root is not None:
            self._request_local_reload(pending_root)

    def refresh_local_tree(self, service: str) -> None:
        tree = self.local_tree_by_service[service]
        selected_iid = self.local_selected_iid_by_service.get(service, "")
        if not selected_iid:
            selected = tree.selection()
            if selected:
                selected_iid = selected[0]
        tree.delete(*tree.get_children())
        valid_iids: set[str] = set()
        for item in self.local_items[service]:
            pkg_suffix = " (PKG)" if (item.path.parent / f"{item.path.name}.pkg").exists() else ""
            iid = str(item.path)
            valid_iids.add(iid)
            tree.insert(
                "",
                "end",
                iid=iid,
                values=(f"{item.version}{pkg_suffix}", item.signed, item.notarized, item.platform, item.os_version, item.arch, str(item.path)),
            )
        if selected_iid and selected_iid in valid_iids:
            tree.selection_set(selected_iid)
            tree.see(selected_iid)
            self.local_selected_iid_by_service[service] = selected_iid
        else:
            self.local_selected_iid_by_service[service] = ""

    def refresh_server_tree(self, service: str) -> None:
        tree = self.server_tree_by_service[service]
        tree.delete(*tree.get_children())
        for index, item in enumerate(self.server_items[service]):
            tree.insert(
                "",
                "end",
                iid=str(index),
                values=(
                    item.version,
                    item.platform,
                    item.os_version,
                    item.arch,
                    item.status,
                    item.sha256[:12],
                    human_size(item.size_bytes),
                    human_date(item.release_date),
                    item.package_url,
                ),
            )

    def show_server_loading(self) -> None:
        for service, tree in self.server_tree_by_service.items():
            tree.delete(*tree.get_children())
            tree.insert(
                "",
                "end",
                iid="__loading__",
                values=("Loading...", "", "", "", "", "", "", "", ""),
            )
        if self.app_pkg_tree is not None:
            self.app_pkg_tree.delete(*self.app_pkg_tree.get_children())
            self.app_pkg_tree.insert(
                "",
                "end",
                iid="__loading__",
                values=("Loading...", "", "", "", "", "", "", "", "", ""),
            )

    def on_tab_changed(self, _event: tk.Event) -> None:
        if not self.reload_on_tab_change or self.fetch_in_progress or self.upload_in_progress:
            return
        self.fetch_manifest()

    def manifest_url(self) -> str:
        site = self.site_url.get().strip().rstrip("/")
        if not site:
            raise ValueError("Site URL is required.")
        return f"{site}/wp-json/server-engine/v1/runtime/admin/manifest"

    def fetch_manifest(self) -> None:
        if self.fetch_in_progress:
            return
        self.fetch_in_progress = True
        self.set_fetch_buttons_enabled(False)
        self.show_server_loading()

        def work() -> None:
            try:
                url = self.manifest_url()
                self.after(0, lambda: self.log(f"Fetching manifest: {url}"))
                request = urllib.request.Request(
                    url,
                    headers={
                        "Accept": "application/json",
                        "Authorization": f"Bearer {self.access_token}",
                        **self.dev_http_headers(),
                    },
                )
                with urllib.request.urlopen(request, timeout=30, context=SSL_CONTEXT) as response:
                    payload = json.loads(response.read().decode("utf-8"))
                grouped = {service: [] for service in SERVICES}
                for item in manifest_items(payload):
                    if item.service in grouped:
                        grouped[item.service].append(item)

                def update_ui() -> None:
                    self.server_items.update(grouped)
                    for service in SERVICES:
                        self.refresh_server_tree(service)
                    self.log("Fetched server runtime manifest.")

                self.after(0, update_ui)
                self.after(0, self.fetch_app_pkg_manifest_async)
            finally:
                def finish() -> None:
                    self.fetch_in_progress = False
                    self.set_fetch_buttons_enabled(True)

                self.after(0, finish)

        self.run_background("Fetch manifest", work)

    def _build_app_pkg_tab(self) -> None:
        frame = ttk.Frame(self.tabs)
        self.tabs.add(frame, text="Sparkle")

        form = ttk.LabelFrame(frame, text="Sparkle Release Upload")
        form.pack(fill="x", padx=8, pady=(8, 6))
        form.columnconfigure(1, weight=1)

        ttk.Label(form, text="DMG File").grid(row=0, column=0, sticky="w", padx=8, pady=6)
        self.app_pkg_combo = ttk.Combobox(form, textvariable=self.app_pkg_file, state="readonly")
        self.app_pkg_combo.grid(row=0, column=1, sticky="ew", padx=6, pady=6)
        ttk.Button(form, text="Browse", command=self.browse_app_pkg_file).grid(row=0, column=2, padx=6, pady=6)

        ttk.Label(form, text="Version").grid(row=1, column=0, sticky="w", padx=8, pady=6)
        ttk.Entry(form, textvariable=self.app_pkg_version, width=16).grid(row=1, column=1, sticky="w", padx=6, pady=6)

        ttk.Label(form, text="Platform").grid(row=1, column=1, sticky="e", padx=(0, 150), pady=6)
        ttk.Combobox(form, textvariable=self.app_pkg_platform, values=("macos",), state="readonly", width=10).grid(
            row=1, column=1, sticky="e", padx=(0, 70), pady=6
        )
        ttk.Label(form, text="Arch").grid(row=1, column=1, sticky="e", padx=(0, 8), pady=6)
        ttk.Combobox(form, textvariable=self.app_pkg_arch, values=("arm64", "x64", "universal"), state="readonly", width=10).grid(
            row=1, column=2, sticky="w", padx=6, pady=6
        )

        ttk.Label(form, text="Channel").grid(row=2, column=0, sticky="w", padx=8, pady=6)
        ttk.Combobox(form, textvariable=self.app_pkg_channel, values=("stable", "beta", "alpha"), state="readonly", width=16).grid(
            row=2, column=1, sticky="w", padx=6, pady=6
        )
        ttk.Checkbutton(form, text="Required update", variable=self.app_pkg_required).grid(row=2, column=2, sticky="w", padx=6, pady=6)

        ttk.Label(form, text=f"Min OS Version (fixed): {APP_MIN_OS_VERSION}").grid(
            row=3, column=0, columnspan=3, sticky="w", padx=8, pady=(2, 6)
        )
        ttk.Label(form, text="Release Notes").grid(row=4, column=0, sticky="nw", padx=8, pady=6)
        self.app_pkg_changelog_text = tk.Text(form, height=5, wrap="word")
        self.app_pkg_changelog_text.grid(row=4, column=1, columnspan=2, sticky="ew", padx=6, pady=6)
        if self.app_pkg_changelog.get().strip():
            self.app_pkg_changelog_text.insert("1.0", self.app_pkg_changelog.get().strip())

        actions = ttk.Frame(form)
        actions.grid(row=5, column=0, columnspan=3, sticky="e", padx=6, pady=(2, 8))
        app_fetch_btn = ttk.Button(actions, text="Refresh Releases", command=self.fetch_app_pkg_manifest_async)
        app_fetch_btn.pack(side="left", padx=4)
        self.fetch_buttons.append(app_fetch_btn)
        app_upload_btn = ttk.Button(actions, text="Upload Sparkle Release", command=self.upload_app_pkg)
        app_upload_btn.pack(side="left", padx=4)
        self.upload_buttons.append(app_upload_btn)

        server_box = ttk.LabelFrame(frame, text="Server Sparkle Releases")
        server_box.pack(fill="both", expand=True, padx=8, pady=(0, 8))
        tree = ttk.Treeview(
            server_box,
            columns=("version", "platform", "min_os", "arch", "channel", "required", "size", "release", "downloads", "url"),
            show="headings",
            height=14,
        )
        for name, width in (
            ("version", 90),
            ("platform", 90),
            ("min_os", 90),
            ("arch", 80),
            ("channel", 80),
            ("required", 80),
            ("size", 100),
            ("release", 150),
            ("downloads", 90),
            ("url", 320),
        ):
            tree.heading(name, text=name.replace("_", " ").title())
            tree.column(name, width=width, anchor="w")
        tree.pack(fill="both", expand=True, padx=6, pady=6)
        self.app_pkg_tree = tree
        self.reload_app_pkg_candidates()

    def app_pkg_dir(self) -> Path:
        return Path(self.app_pkg_root.get().strip() or str(DEFAULT_PKG_ROOT)).expanduser()

    def app_pkg_candidates(self) -> list[Path]:
        pkg_dir = self.app_pkg_dir()
        if not pkg_dir.is_dir():
            return []
        candidates = [item for item in pkg_dir.glob("*.dmg") if item.is_file()]
        if not candidates:
            candidates = [item for item in pkg_dir.glob("*.pkg") if item.is_file()]
        return sorted(
            candidates,
            key=lambda item: item.stat().st_mtime,
            reverse=True,
        )

    def reload_app_pkg_candidates(self) -> None:
        if self.app_pkg_combo is None:
            return
        candidates = self.app_pkg_candidates()
        values = [path.name for path in candidates]
        self.app_pkg_combo.configure(values=values)
        current = self.app_pkg_file.get().strip()
        if current in values:
            return
        if values:
            self.app_pkg_file.set(values[0])
        elif current:
            self.app_pkg_combo.configure(values=[current])
        else:
            self.app_pkg_file.set("")

    def browse_app_pkg_file(self) -> None:
        selected = filedialog.askopenfilename(
            title="Choose ServerEngine .dmg",
            filetypes=[("DMG files", "*.dmg"), ("PKG files", "*.pkg"), ("All files", "*.*")],
        )
        if selected:
            selected_path = Path(selected).expanduser()
            self.app_pkg_root.set(str(selected_path.parent))
            self.app_pkg_file.set(selected_path.name)
            if self.app_pkg_combo is not None:
                current_values = list(self.app_pkg_combo.cget("values"))
                if selected_path.name not in current_values:
                    current_values.insert(0, selected_path.name)
                    self.app_pkg_combo.configure(values=current_values)
            self.save_current_config()

    def app_manifest_url(self) -> str:
        site = self.site_url.get().strip().rstrip("/")
        if not site:
            raise ValueError("Site URL is required.")
        return f"{site}/wp-json/server-engine/v1/app-update/admin/releases"

    def app_upload_url(self) -> str:
        site = self.site_url.get().strip().rstrip("/")
        if not site:
            raise ValueError("Site URL is required.")
        return f"{site}/wp-json/server-engine/v1/app-update/admin/releases"

    def fetch_app_pkg_manifest_async(self) -> None:
        if self.app_pkg_tree is None:
            return

        def work() -> None:
            url = self.app_manifest_url()
            request = urllib.request.Request(
                url,
                headers={
                    "Accept": "application/json",
                    "Authorization": f"Bearer {self.access_token}",
                    **self.dev_http_headers(),
                },
            )
            with urllib.request.urlopen(request, timeout=30, context=SSL_CONTEXT) as response:
                payload = json.loads(response.read().decode("utf-8"))
            raw_items = payload if isinstance(payload, list) else (
                payload.get("releases")
                or payload.get("items")
                or payload.get("updates")
                or payload.get("data")
                or []
            )
            if not isinstance(raw_items, list):
                raw_items = []
            items: list[dict[str, str]] = []
            for raw in raw_items:
                if not isinstance(raw, dict):
                    continue
                items.append(
                    {
                        "appVersion": str(raw.get("appVersion") or raw.get("version") or ""),
                        "platform": str(raw.get("platform") or raw.get("os") or ""),
                        "minOsVersion": str(raw.get("minOsVersion") or raw.get("min_system_version") or ""),
                        "arch": str(raw.get("arch") or ""),
                        "channel": str(raw.get("channel") or ""),
                        "required": str(raw.get("required") or ""),
                        "sizeBytes": str(raw.get("sizeBytes") or raw.get("file_size") or ""),
                        "releaseDate": str(raw.get("releaseDate") or raw.get("pub_date_iso8601") or raw.get("created_at") or ""),
                        "downloadCount": str(raw.get("downloadCount") or raw.get("download_count") or "0"),
                        "packageUrl": str(raw.get("packageUrl") or raw.get("directPackageUrl") or raw.get("release_url") or raw.get("file_url") or ""),
                    }
                )

            def update_ui() -> None:
                self.app_pkg_server_items = items
                self.refresh_app_pkg_tree()
                self.log("Fetched Sparkle release list.")

            self.after(0, update_ui)

        self.run_background("Fetch app manifest", work)

    def refresh_app_pkg_tree(self) -> None:
        if self.app_pkg_tree is None:
            return
        tree = self.app_pkg_tree
        tree.delete(*tree.get_children())
        for idx, item in enumerate(self.app_pkg_server_items):
            tree.insert(
                "",
                "end",
                iid=str(idx),
                values=(
                    item.get("appVersion", ""),
                    item.get("platform", ""),
                    item.get("minOsVersion", ""),
                    item.get("arch", ""),
                    item.get("channel", ""),
                    item.get("required", ""),
                    human_size(item.get("sizeBytes", "")),
                    human_date(item.get("releaseDate", "")),
                    item.get("downloadCount", "0"),
                    item.get("packageUrl", ""),
                ),
            )

    def upload_app_pkg(self) -> None:
        if self.upload_in_progress:
            return
        pkg_name = self.app_pkg_file.get().strip()
        pkg_path = self.app_pkg_dir() / pkg_name
        version = self.app_pkg_version.get().strip()
        channel = self.app_pkg_channel.get().strip() or "stable"
        platform_value = self.app_pkg_platform.get().strip() or "macos"
        arch = self.app_pkg_arch.get().strip() or "arm64"
        changelog = self.app_pkg_changelog_text.get("1.0", "end").strip() if hasattr(self, "app_pkg_changelog_text") else self.app_pkg_changelog.get().strip()
        required = "true" if self.app_pkg_required.get() else "false"

        if not pkg_path.is_file():
            self.log("Upload Sparkle Release: Select a valid .dmg file first.")
            return
        if pkg_path.suffix.lower() not in {".dmg", ".pkg"}:
            self.log("Upload Sparkle Release: File must be a .dmg (or .pkg for compatibility).")
            return
        if not version:
            self.log("Upload Sparkle Release: Version is required.")
            return
        if not changelog:
            self.log("Upload Sparkle Release: Release notes are required.")
            return

        self.app_pkg_changelog.set(changelog)
        self.save_current_config()
        self.upload_in_progress = True
        self.set_upload_buttons_enabled(False)
        self.set_fetch_buttons_enabled(False)
        dialog = UploadProgressDialog(self, f"Uploading Sparkle Release {version}")

        def work() -> None:
            try:
                endpoint = self.app_upload_url()
                file_size = pkg_path.stat().st_size
                sha256 = file_sha256(pkg_path)
                self.after(0, lambda: dialog.set_status(f"Uploading {pkg_path.name} ({human_size(str(file_size))})"))
                self.after(0, lambda: self.log(f"Uploading Sparkle release {version} ({file_size} bytes, sha256 {sha256[:12]}...)"))
                fields = [
                    ("app_id", "com.serverengine.app"),
                    ("version", version),
                    ("build", version),
                    ("min_system_version", APP_MIN_OS_VERSION),
                    ("os", platform_value),
                    ("arch", arch),
                    ("channel", channel),
                    ("file_name", pkg_path.name),
                    ("file_size", str(file_size)),
                    ("sha256", sha256),
                    ("release_notes_html", changelog),
                    ("pub_date_iso8601", datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")),
                    # compatibility fields
                    ("appVersion", version),
                    ("platform", platform_value),
                    ("minOsVersion", APP_MIN_OS_VERSION),
                    ("arch", arch),
                    ("channel", channel),
                    ("required", required),
                    ("changelog", changelog),
                ]
                _ = multipart_upload(
                    endpoint,
                    self.access_token,
                    self.dev_http_headers(),
                    fields,
                    pkg_path,
                    "file",
                    "application/octet-stream",
                    lambda percent: self.after(0, lambda value=percent: dialog.set_progress(value)),
                )

                def done() -> None:
                    self.upload_in_progress = False
                    self.set_upload_buttons_enabled(True)
                    self.set_fetch_buttons_enabled(True)
                    dialog.close()
                    self.log("Sparkle release upload completed.")
                    self.fetch_app_pkg_manifest_async()

                self.after(0, done)
            except Exception as exc:  # noqa: BLE001
                error_message = str(exc)

                def fail() -> None:
                    self.upload_in_progress = False
                    self.set_upload_buttons_enabled(True)
                    self.set_fetch_buttons_enabled(True)
                    dialog.close()
                    self.log(f"Upload Sparkle release failed: {error_message}")

                self.after(0, fail)

        threading.Thread(target=work, daemon=True).start()

    def selected_local_runtime(self, service: str) -> RuntimeItem | None:
        tree = self.local_tree_by_service[service]
        selected = tree.selection()
        if not selected:
            saved = self.local_selected_iid_by_service.get(service, "")
            if saved:
                selected = (saved,)
        if not selected:
            return None
        selected_iid = selected[0]
        items = self.local_items[service]
        return next((item for item in items if str(item.path) == selected_iid), None)

    def runtime_notary_archive_path(self, item: RuntimeItem) -> Path:
        return runtime_notary_archive_path(item.path, item.service, item.version, item.platform, item.arch)

    def _runtime_notary_credentials(self) -> tuple[str, str, str]:
        apple_id = self.runtime_notary_apple_id.get().strip()
        team_id = self.runtime_notary_team_id.get().strip()
        password = self.runtime_notary_password.get().strip()
        return apple_id, team_id, password

    def _prepare_runtime_notary_archive(self, item: RuntimeItem) -> Path:
        archive_path = self.runtime_notary_archive_path(item)
        archive_path.parent.mkdir(parents=True, exist_ok=True)
        for stale_path in (archive_path, archive_path.with_suffix(".notarized"), archive_path.with_suffix(".stapled")):
            try:
                stale_path.unlink()
            except FileNotFoundError:
                pass
        source_root = item.path.parent
        shutil.make_archive(str(archive_path.with_suffix("")), "zip", root_dir=source_root, base_dir=item.path.name)
        return archive_path

    def _runtime_pkg_path(self, item: RuntimeItem) -> Path:
        return item.path.parent / f"{item.path.name}.pkg"

    def _runtime_pkg_install_relative_path(self, item: RuntimeItem) -> Path:
        service = item.service.strip().lower()
        runtime_name = item.path.name
        if service == "php":
            return Path("php") / runtime_name
        if service == "phpmyadmin":
            return Path("tools") / "phpmyadmin" / runtime_name
        if service in {"apache", "nginx"}:
            return Path("server") / runtime_name
        if service in {"mysql", "mariadb", "mongodb", "postgresql"}:
            return Path("database") / runtime_name
        if service == "redis":
            return Path("redis") / runtime_name
        if service == "memcached":
            return Path("memcached") / runtime_name
        if service == "mailpit":
            return Path("mailpit") / runtime_name
        if service == "node":
            return Path("node") / runtime_name
        return Path(service) / runtime_name

    def _runtime_pkg_stage_root(self, item: RuntimeItem, stage_root: Path) -> Path:
        payload_root = stage_root / "Library" / "Application Support" / "Server Engine" / "bin" / self._runtime_pkg_install_relative_path(item)
        payload_root.parent.mkdir(parents=True, exist_ok=True)
        return payload_root

    def _prepare_runtime_pkg_staging(self, item: RuntimeItem, stage_root: Path) -> Path:
        payload_root = self._runtime_pkg_stage_root(item, stage_root)
        shutil.copytree(item.path, payload_root, symlinks=True)
        return stage_root

    def _runtime_sign_check(self, root: Path, candidates: list[str] | None = None) -> tuple[str, str, list[str]]:
        macho_files = collect_macho_files(root, candidates)
        if not macho_files:
            return "N/A", "", []
        if shutil.which("codesign") is None:
            return "Unknown", "", []

        failures: list[str] = []
        first_summary = ""
        for path in macho_files:
            result = subprocess.run(["codesign", "-dv", "--verbose=4", str(path)], capture_output=True, text=True, check=False)
            output = (result.stdout or "") + "\n" + (result.stderr or "")
            authority = ""
            team_id = ""
            signature = ""
            for line in output.splitlines():
                if line.startswith("Authority=") and not authority:
                    authority = line.partition("=")[2].strip()
                elif line.startswith("TeamIdentifier=") and not team_id:
                    team_id = line.partition("=")[2].strip()
                elif line.startswith("Signature=") and not signature:
                    signature = line.partition("=")[2].strip()
            if not first_summary and authority:
                summary_bits = [f"Authority: {authority}"]
                if team_id:
                    summary_bits.append(f"Team: {team_id}")
                if signature:
                    summary_bits.append(f"Signature: {signature}")
                first_summary = " | ".join(summary_bits)
            if result.returncode != 0 or "Signature=adhoc" in output or "adhoc,linker-signed" in output or "TeamIdentifier=not set" in output:
                failures.append(str(path))
        return ("Yes", first_summary, []) if not failures else ("No", first_summary, failures)

    def check_selected_runtime_sign(self, service: str) -> None:
        if self.runtime_task_in_progress or self.sign_in_progress or self.upload_in_progress:
            return
        item = self.selected_local_runtime(service)
        if item is None:
            self.log("Check Sign: Select a local runtime first.")
            return
        self.runtime_task_in_progress = True
        self.set_runtime_action_buttons_enabled(False)
        self.set_upload_buttons_enabled(False)
        self.set_fetch_buttons_enabled(False)
        self.set_sign_buttons_enabled(False)

        def work() -> None:
            try:
                archive_path = self.runtime_notary_archive_path(item)
                if archive_path.exists() and archive_path.suffix.lower() == ".zip":
                    self.after(0, lambda: self.log(f"Check Sign: using notarized archive {archive_path}"))
                    self.after(0, lambda: self.log(f"Notarized archive status: {item.notarized}"))
                    with tempfile.TemporaryDirectory(prefix="se-runtime-sign-check-") as temp_dir_name:
                        temp_dir = Path(temp_dir_name)
                        with zipfile.ZipFile(archive_path, "r") as archive:
                            archive.extractall(temp_dir)
                        extracted_root = temp_dir / item.path.name
                        check_root = extracted_root if extracted_root.exists() else temp_dir
                        state, summary, failures = self._runtime_sign_check(check_root, item.binaries)
                else:
                    if archive_path.exists() and archive_path.suffix.lower() == ".pkg":
                        self.after(0, lambda: self.log(f"Check Sign: using runtime folder {item.path} (PKG available at {archive_path})"))
                    else:
                        self.after(0, lambda: self.log(f"Check Sign: using runtime folder {item.path}"))
                    self.after(0, lambda: self.log(f"Notarized archive status: {item.notarized}"))
                    state, summary, failures = self._runtime_sign_check(item.path, item.binaries)

                def finish() -> None:
                    self.runtime_task_in_progress = False
                    self.set_runtime_action_buttons_enabled(True)
                    self.set_upload_buttons_enabled(True)
                    self.set_fetch_buttons_enabled(True)
                    self.set_sign_buttons_enabled(True)
                    if state == "Yes":
                        if summary:
                            self.log(f"Signature check passed for {item.path}. {summary}.")
                        else:
                            self.log(f"Signature check passed for {item.path}.")
                    elif state == "Unknown":
                        self.log(f"Signature check unavailable for {item.path}.")
                    elif failures:
                        message = f"Signature check failed for {item.path}."
                        if summary:
                            message += f" {summary}."
                        message += "\n" + "\n".join(failures)
                        self.log(message)
                    else:
                        self.log(f"Signature check found no Mach-O files in {item.path}.")

                self.after(0, finish)
            except Exception as exc:  # noqa: BLE001 - surface the full error to the UI.
                error_message = str(exc)

                def fail() -> None:
                    self.runtime_task_in_progress = False
                    self.set_runtime_action_buttons_enabled(True)
                    self.set_upload_buttons_enabled(True)
                    self.set_fetch_buttons_enabled(True)
                    self.set_sign_buttons_enabled(True)
                    self.log(f"Signature check failed: {error_message}")

                self.after(0, fail)

        threading.Thread(target=work, daemon=True).start()

    def build_selected_runtime_pkg(self, service: str) -> None:
        if self.runtime_task_in_progress or self.sign_in_progress or self.upload_in_progress:
            return
        item = self.selected_local_runtime(service)
        if item is None:
            self.log("Build PKG: Select a local runtime first.")
            return
        if platform.system() != "Darwin":
            self.log("Build PKG: macOS is required.")
            return
        if shutil.which("pkgbuild") is None:
            self.log("Build PKG: pkgbuild is not available on this machine.")
            return

        self.runtime_task_in_progress = True
        self.set_runtime_action_buttons_enabled(False)
        self.set_upload_buttons_enabled(False)
        self.set_fetch_buttons_enabled(False)
        self.set_sign_buttons_enabled(False)

        def work() -> None:
            pkg_path = self._runtime_pkg_path(item)
            try:
                pkg_path.parent.mkdir(parents=True, exist_ok=True)
                for stale_path in (
                    pkg_path,
                    pkg_path.with_suffix(".notarized"),
                    pkg_path.with_suffix(".stapled"),
                ):
                    try:
                        stale_path.unlink()
                    except FileNotFoundError:
                        pass
                with tempfile.TemporaryDirectory(prefix="se-runtime-pkg-stage-") as stage_name:
                    stage_root = Path(stage_name)
                    self._prepare_runtime_pkg_staging(item, stage_root)
                    identifier = f"com.serverengine.runtime.{item.service}.{item.version or item.path.name}"
                    identifier = re.sub(r"[^A-Za-z0-9.-]+", "-", identifier).strip(".-")
                    cmd = [
                        "pkgbuild",
                        "--root",
                        str(stage_root),
                        "--identifier",
                        identifier,
                        "--version",
                        item.version or item.path.name,
                        "--install-location",
                        "/",
                        str(pkg_path),
                    ]
                    self.after(0, lambda: self.log(f"Building runtime package: {pkg_path}"))
                    self.after(0, lambda: self.log_command(cmd))
                    result = subprocess.run(cmd, capture_output=True, text=True, check=False)
                    output = (result.stdout or "").strip()
                    errors = (result.stderr or "").strip()
                    self.after(0, lambda code=result.returncode: self.log(f"pkgbuild exit code: {code}"))
                    if output:
                        self.after(0, lambda value=output: self.log(f"pkgbuild stdout:\n{value}"))
                    if errors:
                        self.after(0, lambda value=errors: self.log(f"pkgbuild stderr:\n{value}"))
                    if result.returncode != 0:
                        raise subprocess.CalledProcessError(result.returncode, cmd, output=result.stdout, stderr=result.stderr)

                def finish() -> None:
                    self.runtime_task_in_progress = False
                    self.set_runtime_action_buttons_enabled(True)
                    self.set_upload_buttons_enabled(True)
                    self.set_fetch_buttons_enabled(True)
                    self.set_sign_buttons_enabled(True)
                    self.reload_local()
                    self.log(f"Built runtime package: {pkg_path}")

                self.after(0, finish)
            except Exception as exc:  # noqa: BLE001 - surface full package build failure to the UI.
                if isinstance(exc, subprocess.CalledProcessError):
                    error_message = (exc.stderr or exc.stdout or str(exc)).strip() or str(exc)
                else:
                    error_message = str(exc)

                def fail() -> None:
                    self.runtime_task_in_progress = False
                    self.set_runtime_action_buttons_enabled(True)
                    self.set_upload_buttons_enabled(True)
                    self.set_fetch_buttons_enabled(True)
                    self.set_sign_buttons_enabled(True)
                    self.log(f"Build PKG failed: {error_message}")

                self.after(0, fail)

        threading.Thread(target=work, daemon=True).start()

    def sign_selected_runtime_pkg(self, service: str) -> None:
        if self.runtime_task_in_progress or self.sign_in_progress or self.upload_in_progress:
            return
        item = self.selected_local_runtime(service)
        if item is None:
            self.log("Sign PKG: Select a local runtime first.")
            return
        if platform.system() != "Darwin":
            self.log("Sign PKG: macOS is required.")
            return
        if shutil.which("productsign") is None:
            self.log("Sign PKG: productsign is not available on this machine.")
            return

        pkg_path = self._runtime_pkg_path(item)
        if not pkg_path.exists():
            self.log(f"Sign PKG: No package found. Build it first: {pkg_path}")
            return
        identity = self.runtime_pkg_sign_identity.get().strip()
        if not identity:
            self.log("Sign PKG: Select a Developer ID Installer certificate first.")
            return

        self.runtime_task_in_progress = True
        self.set_runtime_action_buttons_enabled(False)
        self.set_upload_buttons_enabled(False)
        self.set_fetch_buttons_enabled(False)
        self.set_sign_buttons_enabled(False)

        def work() -> None:
            signed_pkg = pkg_path.with_suffix(".signed.pkg")
            try:
                for stale_path in (signed_pkg, pkg_path.with_suffix(".notarized"), pkg_path.with_suffix(".stapled")):
                    try:
                        stale_path.unlink()
                    except FileNotFoundError:
                        pass
                cmd = ["productsign", "--sign", identity, str(pkg_path), str(signed_pkg)]
                self.after(0, lambda: self.log(f"Signing runtime package: {pkg_path}"))
                self.after(0, lambda: self.log_command(cmd))
                result = subprocess.run(cmd, capture_output=True, text=True, check=False)
                output = (result.stdout or "").strip()
                errors = (result.stderr or "").strip()
                self.after(0, lambda code=result.returncode: self.log(f"productsign exit code: {code}"))
                if output:
                    self.after(0, lambda value=output: self.log(f"productsign stdout:\n{value}"))
                if errors:
                    self.after(0, lambda value=errors: self.log(f"productsign stderr:\n{value}"))
                if result.returncode != 0:
                    raise subprocess.CalledProcessError(result.returncode, cmd, output=result.stdout, stderr=result.stderr)
                signed_pkg.replace(pkg_path)

                def finish() -> None:
                    self.runtime_task_in_progress = False
                    self.set_runtime_action_buttons_enabled(True)
                    self.set_upload_buttons_enabled(True)
                    self.set_fetch_buttons_enabled(True)
                    self.set_sign_buttons_enabled(True)
                    self.reload_local()
                    self.log(f"Signed runtime package: {pkg_path}")

                self.after(0, finish)
            except Exception as exc:  # noqa: BLE001 - surface full package signing failure to the UI.
                if isinstance(exc, subprocess.CalledProcessError):
                    error_message = (exc.stderr or exc.stdout or str(exc)).strip() or str(exc)
                else:
                    error_message = str(exc)

                def fail() -> None:
                    self.runtime_task_in_progress = False
                    self.set_runtime_action_buttons_enabled(True)
                    self.set_upload_buttons_enabled(True)
                    self.set_fetch_buttons_enabled(True)
                    self.set_sign_buttons_enabled(True)
                    self.log(f"Sign PKG failed: {error_message}")

                self.after(0, fail)

        threading.Thread(target=work, daemon=True).start()

    def notarize_selected_runtime(self, service: str) -> None:
        if self.runtime_task_in_progress or self.sign_in_progress or self.upload_in_progress:
            return
        item = self.selected_local_runtime(service)
        if item is None:
            self.log("Notarize: Select a local runtime first.")
            return
        apple_id, team_id, password = self._runtime_notary_credentials()
        if not apple_id or not team_id or not password:
            self.log("Notarize: Apple ID, Team ID, and App Password are required.")
            return
        if shutil.which("xcrun") is None:
            self.log("Notarize: xcrun is not available on this machine.")
            return

        self.runtime_task_in_progress = True
        self.set_runtime_action_buttons_enabled(False)
        self.set_upload_buttons_enabled(False)
        self.set_fetch_buttons_enabled(False)
        self.set_sign_buttons_enabled(False)

        def work() -> None:
            try:
                pkg_path = self._runtime_pkg_path(item)
                archive_path = pkg_path if pkg_path.exists() else self.runtime_notary_archive_path(item)
                if archive_path.suffix.lower() == ".pkg":
                    self.after(0, lambda: self.log(f"Prepared notarization package: {archive_path}"))
                else:
                    archive_path = self._prepare_runtime_notary_archive(item)
                    self.after(0, lambda: self.log(f"Prepared notarization archive: {archive_path}"))
                cmd = [
                    "xcrun",
                    "notarytool",
                    "submit",
                    str(archive_path),
                    "--apple-id",
                    apple_id,
                    "--team-id",
                    team_id,
                    "--password",
                    password,
                    "--wait",
                    "--output-format",
                    "json",
                ]
                self.after(0, lambda: self.log_command(cmd))
                result = subprocess.run(cmd, capture_output=True, text=True, check=False)
                output = (result.stdout or "").strip()
                errors = (result.stderr or "").strip()
                self.after(0, lambda code=result.returncode: self.log(f"Apple notarization exit code: {code}"))
                if output:
                    self.after(0, lambda value=output: self.log(f"Apple notarization stdout:\n{value}"))
                if errors:
                    self.after(0, lambda value=errors: self.log(f"Apple notarization stderr:\n{value}"))
                if result.returncode != 0:
                    raise subprocess.CalledProcessError(result.returncode, cmd, output=result.stdout, stderr=result.stderr)

                submission_id = ""
                status = ""
                if output:
                    try:
                        payload = json.loads(output)
                    except json.JSONDecodeError:
                        payload = None
                    if isinstance(payload, dict):
                        submission_id = str(payload.get("id") or payload.get("submissionId") or payload.get("submission_id") or "").strip()
                        status = str(payload.get("status") or payload.get("state") or "").strip()
                if submission_id:
                    self.after(0, lambda value=submission_id: self.runtime_notary_submission_id.set(value))
                    self.after(0, self.save_current_config)
                    self.after(0, lambda value=submission_id: self.log(f"Apple submission ID: {value}"))
                    self.after(0, lambda value=submission_id: self.log(f"Saved Apple submission ID: {value}"))
                if status:
                    self.after(0, lambda value=status: self.log(f"Apple notarization status: {value}"))
                if not submission_id:
                    self.after(0, lambda: self.log("Apple submission ID not present in notarytool output."))

                def finish() -> None:
                    self.runtime_task_in_progress = False
                    self.set_runtime_action_buttons_enabled(True)
                    self.set_upload_buttons_enabled(True)
                    self.set_fetch_buttons_enabled(True)
                    self.set_sign_buttons_enabled(True)
                    marker_path = archive_path.with_suffix(".notarized")
                    marker_path.write_text(f"notarized {time.time()}\n", encoding="utf-8")
                    self.reload_local()
                    self.log(f"Notarized runtime archive: {archive_path}")

                self.after(0, finish)
            except Exception as exc:  # noqa: BLE001 - surface the full notary failure to the UI.
                if isinstance(exc, subprocess.CalledProcessError):
                    error_message = (exc.stderr or exc.stdout or str(exc)).strip() or str(exc)
                else:
                    error_message = str(exc)

                def fail() -> None:
                    self.runtime_task_in_progress = False
                    self.set_runtime_action_buttons_enabled(True)
                    self.set_upload_buttons_enabled(True)
                    self.set_fetch_buttons_enabled(True)
                    self.set_sign_buttons_enabled(True)
                    self.log(f"Notarize failed: {error_message}")

                self.after(0, fail)

        threading.Thread(target=work, daemon=True).start()

    def staple_selected_runtime(self, service: str) -> None:
        if self.runtime_task_in_progress or self.sign_in_progress or self.upload_in_progress:
            return
        item = self.selected_local_runtime(service)
        if item is None:
            self.log("Staple: Select a local runtime first.")
            return
        archive_path = self.runtime_notary_archive_path(item)
        if not archive_path.exists():
            self.log(f"Staple: No notarization archive found for this runtime. Expected: {archive_path}")
            return
        if shutil.which("xcrun") is None:
            self.log("Staple: xcrun is not available on this machine.")
            return
        if archive_path.suffix.lower() == ".zip":
            self.log(f"Staple: Zip archives cannot be stapled. Use the notarized archive as-is: {archive_path}")
            return

        self.runtime_task_in_progress = True
        self.set_runtime_action_buttons_enabled(False)
        self.set_upload_buttons_enabled(False)
        self.set_fetch_buttons_enabled(False)
        self.set_sign_buttons_enabled(False)

        def work() -> None:
            try:
                self.after(0, lambda: self.log(f"Stapling archive: {archive_path}"))
                cmd = ["xcrun", "stapler", "staple", str(archive_path)]
                self.after(0, lambda: self.log_command(cmd))
                result = subprocess.run(cmd, capture_output=True, text=True, check=False)
                output = (result.stdout or "").strip()
                errors = (result.stderr or "").strip()
                self.after(0, lambda code=result.returncode: self.log(f"Stapler exit code: {code}"))
                if output:
                    self.after(0, lambda value=output: self.log(f"Stapler stdout:\n{value}"))
                if errors:
                    self.after(0, lambda value=errors: self.log(f"Stapler stderr:\n{value}"))
                if result.returncode != 0:
                    raise subprocess.CalledProcessError(result.returncode, cmd, output=result.stdout, stderr=result.stderr)

                def finish() -> None:
                    self.runtime_task_in_progress = False
                    self.set_runtime_action_buttons_enabled(True)
                    self.set_upload_buttons_enabled(True)
                    self.set_fetch_buttons_enabled(True)
                    self.set_sign_buttons_enabled(True)
                    marker_path = archive_path.with_suffix(".stapled")
                    marker_path.write_text(f"stapled {time.time()}\n", encoding="utf-8")
                    self.reload_local()
                    self.log(f"Stapled runtime archive: {archive_path}")

                self.after(0, finish)
            except Exception as exc:  # noqa: BLE001 - surface the full staple failure to the UI.
                if isinstance(exc, subprocess.CalledProcessError):
                    error_message = (exc.stderr or exc.stdout or str(exc)).strip() or str(exc)
                else:
                    error_message = str(exc)

                def fail() -> None:
                    self.runtime_task_in_progress = False
                    self.set_runtime_action_buttons_enabled(True)
                    self.set_upload_buttons_enabled(True)
                    self.set_fetch_buttons_enabled(True)
                    self.set_sign_buttons_enabled(True)
                    self.log(f"Staple failed: {error_message}")

                self.after(0, fail)

        threading.Thread(target=work, daemon=True).start()

    def sign_selected_runtime(self, service: str) -> None:
        if self.sign_in_progress or self.upload_in_progress or self.runtime_task_in_progress:
            return
        item = self.selected_local_runtime(service)
        if item is None:
            self.log("Sign Mach-O Files: Select a local runtime first.")
            return
        if self.runtime_sign_identity_combo is None:
            self.log("Sign Mach-O Files: Signing certificate dropdown is not available.")
            return
        identity = self.runtime_sign_identity.get().strip()
        if not identity:
            self.log("Sign Mach-O Files: Select a Developer ID Application certificate first.")
            return
        if shutil.which("codesign") is None:
            self.log("Sign Mach-O Files: codesign is not available on this machine.")
            return

        archive_path = self.runtime_notary_archive_path(item)
        stale_paths = {
            archive_path,
            archive_path.with_suffix(".notarized"),
            archive_path.with_suffix(".stapled"),
            self._runtime_pkg_path(item),
            self._runtime_pkg_path(item).with_suffix(".notarized"),
            self._runtime_pkg_path(item).with_suffix(".stapled"),
        }
        for stale_path in stale_paths:
            try:
                stale_path.unlink()
            except FileNotFoundError:
                pass

        self.save_current_config()
        self.sign_in_progress = True
        self.set_sign_buttons_enabled(False)
        self.set_upload_buttons_enabled(False)
        self.set_fetch_buttons_enabled(False)
        self.set_runtime_action_buttons_enabled(False)

        def work() -> None:
            try:
                macho_files = collect_macho_files(item.path)
                if not macho_files:
                    def no_files() -> None:
                        self.sign_in_progress = False
                        self.set_sign_buttons_enabled(True)
                        self.set_upload_buttons_enabled(True)
                        self.set_fetch_buttons_enabled(True)
                        self.log(f"No Mach-O files found in {item.path}.")

                    self.after(0, no_files)
                    return

                self.log(f"Signing {len(macho_files)} Mach-O files in {item.path} with {identity}.")
                for path in macho_files:
                    subprocess.run(
                        [
                            "codesign",
                            "--force",
                            "--timestamp",
                            "--options",
                            "runtime",
                            "--sign",
                            identity,
                            str(path),
                        ],
                        capture_output=True,
                        text=True,
                        check=True,
                    )

                def finish() -> None:
                    self.sign_in_progress = False
                    self.set_sign_buttons_enabled(True)
                    self.set_upload_buttons_enabled(True)
                    self.set_fetch_buttons_enabled(True)
                    self.set_runtime_action_buttons_enabled(True)
                    self.reload_local()
                    self.log(f"Signed Mach-O files for {item.path}.")

                self.after(0, finish)
            except Exception as exc:  # noqa: BLE001 - surface full signing failure to the user.
                if isinstance(exc, subprocess.CalledProcessError):
                    error_message = (exc.stderr or exc.stdout or str(exc)).strip() or str(exc)
                else:
                    error_message = str(exc)

                def fail() -> None:
                    self.sign_in_progress = False
                    self.set_sign_buttons_enabled(True)
                    self.set_upload_buttons_enabled(True)
                    self.set_fetch_buttons_enabled(True)
                    self.set_runtime_action_buttons_enabled(True)
                    self.log(f"Sign Mach-O files failed: {error_message}")

                self.after(0, fail)

        threading.Thread(target=work, daemon=True).start()

    def upload_selected(self, service: str) -> None:
        if self.upload_in_progress or self.sign_in_progress or self.runtime_task_in_progress:
            return
        item = self.selected_local_runtime(service)
        if item is None:
            self.log("Upload Runtime: Select a local runtime first.")
            return

        site = self.site_url.get().strip().rstrip("/")
        if not site:
            self.log("Upload Runtime: Site URL is required.")
            return

        existing = [server_item for server_item in self.server_items.get(service, []) if server_item.key == item.key]
        if existing:
            self.log(
                f"Upload Runtime: {service} {item.version} for {item.platform}/{item.arch} already exists on the server; overwriting."
            )

        self.save_current_config()
        self.upload_in_progress = True
        self.set_upload_buttons_enabled(False)
        self.set_fetch_buttons_enabled(False)
        self.set_sign_buttons_enabled(False)
        self.set_runtime_action_buttons_enabled(False)
        dialog = UploadProgressDialog(self, f"Uploading {service} {item.version}")

        def work() -> None:
            try:
                self.upload_runtime(item, site, dialog)
            except Exception as exc:  # noqa: BLE001 - upload worker reports all failures to UI.
                error_message = str(exc)

                def fail() -> None:
                    self.upload_in_progress = False
                    self.set_upload_buttons_enabled(True)
                    self.set_fetch_buttons_enabled(True)
                    self.set_sign_buttons_enabled(True)
                    self.set_runtime_action_buttons_enabled(True)
                    dialog.close()
                    self.log(f"Upload runtime failed: {error_message}")

                self.after(0, fail)

        threading.Thread(target=work, daemon=True).start()

    def upload_runtime(self, item: RuntimeItem, site: str, dialog: UploadProgressDialog) -> None:
        endpoint = f"{site}/wp-json/server-engine/v1/runtime/admin/upload"
        self.after(0, lambda: dialog.set_status(f"Packaging {item.path}"))
        self.after(0, lambda: self.log(f"Packaging {item.path}"))
        pkg_path = self._runtime_pkg_path(item)
        use_pkg = pkg_path.exists()
        temp_dir = tempfile.TemporaryDirectory(prefix="se-runtime-upload-") if not use_pkg else None
        try:
            if use_pkg:
                archive_path = pkg_path
                self.after(0, lambda: self.log(f"Using existing runtime package: {archive_path}"))
            else:
                archive_path = Path(temp_dir.name) / f"{item.service}-{item.version}-{item.platform}-{item.arch}.tar.gz"
                self.after(0, lambda: self.log(f"Packaging runtime archive: {archive_path}"))
                with tarfile.open(archive_path, "w:gz") as archive:
                    archive.add(item.path, arcname=item.path.name)
            sha256 = file_sha256(archive_path)
            size_bytes = archive_path.stat().st_size
            self.after(
                0,
                lambda: dialog.set_status(
                    f"Uploading {item.service} {item.version} ({size_bytes} bytes, sha256 {sha256[:12]}...)"
                ),
            )
            self.after(
                0,
                lambda: self.log(
                    f"Uploading {item.service} {item.version} ({size_bytes} bytes, sha256 {sha256[:12]}...)"
                ),
            )
            fields = [
                ("service", item.service),
                ("version", item.version),
                ("platform", item.platform),
                ("osVersion", item.os_version or current_os_version()),
                ("arch", item.arch),
                ("status", item.status),
                ("requiresAppVersion", self.requires_app_version.get().strip() or ">=1.0.0"),
                ("installPath", item.install_path),
                ("sizeBytes", str(size_bytes)),
                ("releaseDate", datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")),
            ]
            for binary in item.binaries:
                fields.append(("binaries[]", binary))
            for extension in item.extensions:
                fields.append(("extensions[]", extension))

            result_body = multipart_upload(
                endpoint,
                self.access_token,
                self.dev_http_headers(),
                fields,
                archive_path,
                "package",
                "application/vnd.apple.installer+xml" if use_pkg else "application/gzip",
                lambda percent: self.after(0, lambda value=percent: dialog.set_progress(value)),
            )
            try:
                payload = json.loads(result_body)
                returned = manifest_items(payload.get("manifest", payload)) if isinstance(payload, dict) else []
                grouped = {service: list(values) for service, values in self.server_items.items()}
                if returned:
                    grouped = {service: [] for service in SERVICES}
                    for server_item in returned:
                        if server_item.service in grouped:
                            grouped[server_item.service].append(server_item)

                def update_after_upload() -> None:
                    self.upload_in_progress = False
                    self.set_upload_buttons_enabled(True)
                    self.set_fetch_buttons_enabled(True)
                    self.set_sign_buttons_enabled(True)
                    self.set_runtime_action_buttons_enabled(True)
                    dialog.close()
                    self.server_items.update(grouped)
                    for service in SERVICES:
                        self.refresh_server_tree(service)
                    self.log("Upload completed.")

                self.after(0, update_after_upload)
            except json.JSONDecodeError:
                def close_after_non_json() -> None:
                    self.upload_in_progress = False
                    self.set_upload_buttons_enabled(True)
                    self.set_fetch_buttons_enabled(True)
                    self.set_sign_buttons_enabled(True)
                    self.set_runtime_action_buttons_enabled(True)
                    dialog.close()

                self.after(0, close_after_non_json)
                self.after(0, lambda: self.log(f"Upload completed. Server response: {result_body[:1000]}"))
        finally:
            if temp_dir is not None:
                temp_dir.cleanup()

    def destroy(self) -> None:
        self._ui_pump_active = False
        if self._ui_pump_after_id is not None:
            try:
                self.after_cancel(self._ui_pump_after_id)
            except Exception:
                pass
            self._ui_pump_after_id = None
        if self.local_poll_after_id is not None:
            try:
                self.after_cancel(self.local_poll_after_id)
            except Exception:
                pass
            self.local_poll_after_id = None
        super().destroy()


if __name__ == "__main__":
    app = RuntimeUploaderApp()
    app.mainloop()
