#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import platform
import plistlib
import re
import ssl
import hashlib
import http.client
import math
import shlex
import signal
import shutil
import subprocess
import threading
import time
import uuid
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
import tkinter as tk
from tkinter import filedialog, messagebox, ttk


REPO_ROOT = Path(__file__).resolve().parents[1]
APP_BUILD_SCRIPT_PATH = REPO_ROOT / "scripts" / "build_macos_app.sh"
PKG_BUILD_SCRIPT_PATH = REPO_ROOT / "scripts" / "build_macos_pkg.sh"
DMG_BUILD_SCRIPT_PATH = REPO_ROOT / "scripts" / "build_macos_dmg.sh"
SPARKLE_PREPARE_SCRIPT_PATH = REPO_ROOT / "scripts" / "sparkle_prepare_release.sh"
DEFAULT_ICON = REPO_ROOT / "assets" / "AppIcon.icns"
DEFAULT_RUNTIME_ROOT = REPO_ROOT / "dist" / "runtime"
CONFIG_DIR = Path.home() / "Library" / "Application Support" / "Server Engine"
CONFIG_PATH = CONFIG_DIR / "build-pkg-gui.json"
SERVICES = ("php", "database", "server", "redis", "memcached", "mailpit", "tools", "node")
DEFAULT_BINARIES = {
    "php": ("bin/php", "bin/php-cgi"),
    "database": ("bin/mysqld", "bin/mariadbd", "bin/mysql"),
    "server": ("bin/httpd", "sbin/nginx", "bin/nginx"),
    "redis": ("*/bin/redis-server", "bin/redis-server"),
    "memcached": ("*/bin/memcached", "bin/memcached"),
    "mailpit": ("*/bin/mailpit", "bin/mailpit"),
    "node": ("*/bin/node", "bin/node"),
    "tools": ("bin/openssl", "openssl*/bin/openssl"),
}


def detect_default_sparkle_framework() -> str:
    caskroom = Path("/opt/homebrew/Caskroom/sparkle")
    if caskroom.is_dir():
        for version_dir in sorted(caskroom.iterdir(), reverse=True):
            direct_framework = version_dir / "Sparkle.framework"
            if direct_framework.exists():
                return str(direct_framework)
            app_framework = version_dir / "Sparkle Test App.app" / "Contents" / "Frameworks" / "Sparkle.framework"
            if app_framework.exists():
                return str(app_framework)
    candidates = (
        REPO_ROOT / "dist" / "app" / "Server Engine.app" / "Contents" / "Frameworks" / "Sparkle.framework",
        Path("/Applications/Server Engine.app/Contents/Frameworks/Sparkle.framework"),
        Path.home() / "Applications" / "Server Engine.app" / "Contents" / "Frameworks" / "Sparkle.framework",
    )
    for candidate in candidates:
        if candidate.exists():
            return str(candidate)
    return str(candidates[0])


def detect_default_sparkle_tools_dir() -> str:
    caskroom = Path("/opt/homebrew/Caskroom/sparkle")
    if caskroom.is_dir():
        for version_dir in sorted(caskroom.iterdir(), reverse=True):
            bin_dir = version_dir / "bin"
            if (bin_dir / "generate_keys").exists() and (bin_dir / "sign_update").exists():
                return str(bin_dir)
    candidates = (
        REPO_ROOT / ".build" / "sparkle" / "bin",
        REPO_ROOT / "vendor" / "Sparkle" / "bin",
        REPO_ROOT / "Sparkle" / "bin",
        Path.home() / "Downloads" / "Sparkle" / "bin",
        Path("/opt/homebrew/bin"),
        Path("/usr/local/bin"),
    )
    for candidate in candidates:
        if (candidate / "generate_keys").exists() and (candidate / "sign_update").exists():
            return str(candidate)
    return ""


def load_config() -> dict:
    try:
        payload = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
        if isinstance(payload, dict):
            return payload
    except Exception:
        pass
    return {}


def save_config(config: dict) -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    CONFIG_PATH.write_text(json.dumps(config, indent=2, sort_keys=True), encoding="utf-8")


def build_ssl_context() -> ssl.SSLContext:
    if os.environ.get("SE_INSECURE_SSL", "").strip().lower() in {"1", "true", "yes", "on"}:
        return ssl._create_unverified_context()
    context = ssl.create_default_context()
    try:
        import certifi  # type: ignore
        context.load_verify_locations(cafile=certifi.where())
    except Exception:
        pass
    return context


SSL_CONTEXT = build_ssl_context()


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def api_post_form(url: str, fields: dict[str, str], headers: dict[str, str] | None = None) -> dict:
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
        raise RuntimeError("Unexpected JSON response.")
    return payload


def multipart_upload(
    url: str,
    token: str,
    fields: list[tuple[str, str]],
    file_path: Path,
    file_field_name: str,
    progress_callback,
) -> str:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        raise ValueError("Invalid upload URL.")

    boundary = f"----ServerEngineBuildGui{int(time.time() * 1000)}"
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
        "Content-Type: application/octet-stream\r\n\r\n"
    ).encode("utf-8")
    closing = f"\r\n--{boundary}--\r\n".encode("utf-8")
    file_size = file_path.stat().st_size
    total_size = sum(len(p) for p in field_parts) + len(file_header) + file_size + len(closing)
    path = parsed.path or "/"
    if parsed.query:
        path = f"{path}?{parsed.query}"
    conn = (
        http.client.HTTPSConnection(parsed.hostname, parsed.port, timeout=60, context=SSL_CONTEXT)
        if parsed.scheme == "https"
        else http.client.HTTPConnection(parsed.hostname, parsed.port, timeout=60)
    )
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": f"multipart/form-data; boundary={boundary}",
        "Content-Length": str(total_size),
        "Accept": "application/json",
    }
    sent = 0

    def send_chunk(chunk: bytes) -> None:
        nonlocal sent
        conn.send(chunk)
        sent += len(chunk)
        progress_callback(min(100, int(sent * 100 / total_size)))

    try:
        conn.putrequest("POST", path)
        for k, v in headers.items():
            conn.putheader(k, v)
        conn.endheaders()
        for part in field_parts:
            send_chunk(part)
        send_chunk(file_header)
        with file_path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 512), b""):
                send_chunk(chunk)
        send_chunk(closing)
        response = conn.getresponse()
        body = response.read().decode("utf-8", "replace")
        if response.status < 200 or response.status >= 300:
            raise RuntimeError(f"HTTP {response.status} {response.reason}: {body[:600]}")
        return body
    finally:
        conn.close()


def multipart_upload_bytes(
    url: str,
    token: str,
    fields: list[tuple[str, str]],
    file_field_name: str,
    file_name: str,
    file_bytes: bytes,
) -> str:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        raise ValueError("Invalid upload URL.")
    boundary = f"----ServerEngineBuildGuiChunk{int(time.time() * 1000)}"
    body_parts: list[bytes] = []
    for name, value in fields:
        body_parts.append(
            (
                f"--{boundary}\r\n"
                f'Content-Disposition: form-data; name="{name}"\r\n\r\n'
                f"{value}\r\n"
            ).encode("utf-8")
        )
    body_parts.append(
        (
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="{file_field_name}"; filename="{file_name}"\r\n'
            "Content-Type: application/octet-stream\r\n\r\n"
        ).encode("utf-8")
    )
    body_parts.append(file_bytes)
    body_parts.append(f"\r\n--{boundary}--\r\n".encode("utf-8"))
    payload = b"".join(body_parts)

    path = parsed.path or "/"
    if parsed.query:
        path = f"{path}?{parsed.query}"
    conn = (
        http.client.HTTPSConnection(parsed.hostname, parsed.port, timeout=120, context=SSL_CONTEXT)
        if parsed.scheme == "https"
        else http.client.HTTPConnection(parsed.hostname, parsed.port, timeout=120)
    )
    try:
        conn.putrequest("POST", path)
        conn.putheader("Authorization", f"Bearer {token}")
        conn.putheader("Content-Type", f"multipart/form-data; boundary={boundary}")
        conn.putheader("Content-Length", str(len(payload)))
        conn.putheader("Accept", "application/json")
        conn.endheaders()
        conn.send(payload)
        response = conn.getresponse()
        body = response.read().decode("utf-8", "replace")
        if response.status < 200 or response.status >= 300:
            raise RuntimeError(f"HTTP {response.status} {response.reason}: {body[:600]}")
        return body
    finally:
        conn.close()


class BuildPkgGui(tk.Tk):
    IDENTITY_PLACEHOLDER = "Select signing certificate"
    NOISY_LOG_PREFIXES = ("--prepared:", "--validated:")

    @staticmethod
    def _default_release_build_stamp() -> str:
        now = datetime.now()
        return now.strftime("%H%M.%d%m.%Y")

    def __init__(self) -> None:
        super().__init__()
        self.title("Server Engine Build App/DMG")
        self.geometry("1800x980")

        cfg = load_config()
        self.icon_path = tk.StringVar(value=str(cfg.get("icon_path") or (DEFAULT_ICON if DEFAULT_ICON.exists() else "")))
        self.runtime_root = tk.StringVar(value=str(cfg.get("runtime_root") or DEFAULT_RUNTIME_ROOT))
        self.version = tk.StringVar(value=str(cfg.get("version") or ""))
        self.app_artifact_path = tk.StringVar(value=str(cfg.get("app_artifact_path") or (REPO_ROOT / "dist" / "app" / "Server Engine.app")))
        self.clean = tk.BooleanVar(value=bool(cfg.get("clean", True)))
        self.bundle_app_runtime = tk.BooleanVar(value=bool(cfg.get("bundle_app_runtime", True)))
        self.skip_app_build = tk.BooleanVar(value=bool(cfg.get("skip_app_build", True)))
        self.pkg_select_mode = tk.StringVar(value=str(cfg.get("pkg_select_mode") or "last_built"))
        self.pkg_select_version = tk.StringVar(value=str(cfg.get("pkg_select_version") or ""))
        self.enable_sign = tk.BooleanVar(value=bool(cfg.get("enable_sign", False)))
        self.enable_notarize = tk.BooleanVar(value=bool(cfg.get("enable_notarize", False)))
        self.enable_app_sign = tk.BooleanVar(value=bool(cfg.get("enable_app_sign", False)))
        self.app_sign_identity = tk.StringVar(value=str(cfg.get("app_sign_identity") or ""))
        self.sign_identity = tk.StringVar(value=str(cfg.get("sign_identity") or ""))
        self.notary_apple_id = tk.StringVar(value=str(cfg.get("notary_apple_id") or ""))
        self.notary_team_id = tk.StringVar(value=str(cfg.get("notary_team_id") or ""))
        self.notary_password = tk.StringVar(value=str(cfg.get("notary_password") or ""))
        self.notary_submission_id = tk.StringVar(value=str(cfg.get("notary_submission_id") or ""))
        self.app_notary_submission_id = tk.StringVar(value=str(cfg.get("app_notary_submission_id") or ""))
        self.dmg_notary_submission_id = tk.StringVar(value=str(cfg.get("dmg_notary_submission_id") or ""))
        self.sparkle_enabled = tk.BooleanVar(value=bool(cfg.get("sparkle_enabled", True)))
        self.sparkle_framework_path = tk.StringVar(value=str(cfg.get("sparkle_framework_path") or detect_default_sparkle_framework()))
        self.sparkle_feed_url = tk.StringVar(value=str(cfg.get("sparkle_feed_url") or "https://ninacoder.top/wp-json/server-engine/v1/app-update/appcast.xml"))
        self.sparkle_public_ed_key = tk.StringVar(value=str(cfg.get("sparkle_public_ed_key") or ""))
        self.sparkle_tools_dir = tk.StringVar(value=str(cfg.get("sparkle_tools_dir") or detect_default_sparkle_tools_dir()))
        self.sparkle_private_key_file = tk.StringVar(value=str(cfg.get("sparkle_private_key_file") or ""))
        self.sparkle_key_account = tk.StringVar(value=str(cfg.get("sparkle_key_account") or "ed25519"))
        self.sparkle_release_channel = tk.StringVar(value=str(cfg.get("sparkle_release_channel") or "stable"))
        self.sparkle_arch_override = tk.StringVar(value=str(cfg.get("sparkle_arch_override") or ""))
        self.sparkle_metadata_json_path = tk.StringVar(value=str(cfg.get("sparkle_metadata_json_path") or ""))
        self.upload_site_url = tk.StringVar(value=str(cfg.get("upload_site_url") or ""))
        self.upload_email = tk.StringVar(value=str(cfg.get("upload_email") or ""))
        self.upload_password = tk.StringVar(value=str(cfg.get("upload_password") or ""))
        self.upload_version = tk.StringVar(value=str(cfg.get("upload_version") or cfg.get("version") or ""))
        self.upload_build = tk.StringVar(value=self._default_release_build_stamp())
        self.upload_min_system_version = tk.StringVar(value=str(cfg.get("upload_min_system_version") or "14.0"))
        self.upload_os = tk.StringVar(value=str(cfg.get("upload_os") or "macos"))
        self.upload_arch = tk.StringVar(value=str(cfg.get("upload_arch") or "arm64"))
        self.upload_sparkle_ed_signature = tk.StringVar(value=str(cfg.get("upload_sparkle_ed_signature") or ""))
        self.upload_release_notes_url = tk.StringVar(value=str(cfg.get("upload_release_notes_url") or ""))
        self.upload_critical_update = tk.BooleanVar(value=bool(cfg.get("upload_critical_update", False)))
        self.upload_phased_rollout_interval = tk.StringVar(value=str(cfg.get("upload_phased_rollout_interval") or "0"))
        self.upload_staging_percentage = tk.StringVar(value=str(cfg.get("upload_staging_percentage") or "0"))
        self.release_dmg_select_mode = tk.StringVar(value=str(cfg.get("release_dmg_select_mode") or "last_built"))
        self.release_dmg_select_version = tk.StringVar(value=str(cfg.get("release_dmg_select_version") or ""))
        self.release_dmg_path = tk.StringVar(value=str(cfg.get("release_dmg_path") or ""))
        self.upload_access_token = str(cfg.get("upload_access_token") or "")
        self.upload_manifest_items: list[dict] = []
        saved_services = cfg.get("services") or list(SERVICES)
        saved_runtime_items = cfg.get("runtime_items") or []
        self.service_vars = {name: tk.BooleanVar(value=name in saved_services) for name in SERVICES}
        self.runtime_item_vars: dict[str, tk.BooleanVar] = {}
        self.saved_runtime_items = set(saved_runtime_items)
        self.runtime_item_frames: dict[str, ttk.Frame] = {}
        self.running = False
        self.last_pkg_path: Path | None = None
        self.last_dmg_path: Path | None = None
        self.runtime_item_os_cache: dict[str, str] = {}
        self.build_process: subprocess.Popen[str] | None = None
        self.sign_process: subprocess.Popen[str] | None = None
        self.identity_map: dict[str, str] = {}
        self.app_identity_map: dict[str, str] = {}
        self._log_buffer: list[str] = []
        self._log_flush_scheduled = False

        self._build_ui()
        self._refresh_command_preview()
        self.protocol("WM_DELETE_WINDOW", self._on_close)

    def _build_ui(self) -> None:
        root = ttk.Frame(self, padding=14)
        root.pack(fill="both", expand=True)
        ttk.Label(root, text="PKG Build Settings", font=("TkDefaultFont", 14, "bold")).pack(anchor="w")

        layout = ttk.Panedwindow(root, orient="horizontal")
        layout.pack(fill="both", expand=True, pady=(8, 0))
        self.main_layout = layout

        left_panel = ttk.Frame(layout, padding=(0, 0, 10, 0))
        right_panel = ttk.Frame(layout, padding=(10, 0, 0, 0))
        layout.add(left_panel, weight=3)
        layout.add(right_panel, weight=2)

        tabs = ttk.Notebook(left_panel)
        tabs.pack(fill="both", expand=True)
        build_tab = ttk.Frame(tabs, padding=8)
        sparkle_tab = ttk.Frame(tabs, padding=8)
        sign_tab = ttk.Frame(tabs, padding=8)
        dmg_tab = ttk.Frame(tabs, padding=8)
        release_tab = ttk.Frame(tabs, padding=8)
        tabs.add(build_tab, text="Build/Sign .app")
        tabs.add(sparkle_tab, text="Sparkle")
        tabs.add(sign_tab, text="PKG")
        tabs.add(dmg_tab, text="DMG")
        tabs.add(release_tab, text="Release")

        form = ttk.Frame(build_tab)
        form.pack(fill="x", pady=(12, 0))
        form.columnconfigure(1, weight=1)

        ttk.Label(form, text="Icon (.icns)").grid(row=0, column=0, sticky="w", pady=6)
        ttk.Entry(form, textvariable=self.icon_path).grid(row=0, column=1, sticky="ew", pady=6)
        ttk.Button(form, text="Choose…", command=self._pick_icon).grid(row=0, column=2, padx=(8, 0), pady=6)

        ttk.Label(form, text="Runtime root").grid(row=1, column=0, sticky="w", pady=6)
        ttk.Entry(form, textvariable=self.runtime_root).grid(row=1, column=1, sticky="ew", pady=6)
        ttk.Button(form, text="Choose…", command=self._pick_runtime_root).grid(row=1, column=2, padx=(8, 0), pady=6)

        ttk.Label(form, text="Version (optional)").grid(row=2, column=0, sticky="w", pady=6)
        ttk.Entry(form, textvariable=self.version).grid(row=2, column=1, sticky="ew", pady=6)
        self.app_sign_check = ttk.Checkbutton(
            form,
            text="Sign .app (Developer ID Application)",
            variable=self.enable_app_sign,
            command=self._refresh_command_preview,
        )
        self.app_sign_check.grid(row=3, column=1, sticky="w", pady=6)
        self.app_sign_label = ttk.Label(form, text="App/runtime sign certificate")
        self.app_sign_label.grid(row=4, column=0, sticky="w", pady=6)
        self.app_identity_combo = ttk.Combobox(form, state="readonly", width=55)
        self.app_identity_combo.grid(row=4, column=1, sticky="ew", pady=6)
        self.app_identity_reload_button = ttk.Button(form, text="Reload", command=self._reload_app_sign_identities)
        self.app_identity_reload_button.grid(row=4, column=2, padx=(8, 0), pady=6)
        self.app_identity_combo.bind("<<ComboboxSelected>>", self._on_app_identity_selected)

        opts = ttk.Frame(build_tab)
        opts.pack(fill="x", pady=(8, 0))
        ttk.Checkbutton(opts, text="--clean", variable=self.clean, command=self._refresh_command_preview).pack(side="left")
        ttk.Checkbutton(
            opts,
            text="Bundle runtime into .app",
            variable=self.bundle_app_runtime,
            command=self._refresh_command_preview,
        ).pack(side="left", padx=(12, 0))

        svc = ttk.LabelFrame(build_tab, text="Runtime folders to package")
        svc.pack(fill="x", pady=(12, 0))
        grid = ttk.Frame(svc, padding=8)
        grid.pack(fill="x")
        for i, name in enumerate(SERVICES):
            cb = ttk.Checkbutton(grid, text=name, variable=self.service_vars[name], command=self._refresh_command_preview)
            cb.grid(row=i // 4, column=i % 4, sticky="w", padx=8, pady=4)

        item_box = ttk.LabelFrame(build_tab, text="Specific runtime versions (optional, overrides service selection)")
        item_box.pack(fill="both", expand=False, pady=(10, 0))
        self.items_tabs = ttk.Notebook(item_box)
        self.items_tabs.pack(fill="both", expand=True, padx=6, pady=6)
        for service in SERVICES:
            tab = ttk.Frame(self.items_tabs)
            self.items_tabs.add(tab, text=service)
            canvas = tk.Canvas(tab, height=130, highlightthickness=0)
            scroll = ttk.Scrollbar(tab, orient="vertical", command=canvas.yview)
            frame = ttk.Frame(canvas)
            frame.bind(
                "<Configure>",
                lambda _e, c=canvas: c.configure(scrollregion=c.bbox("all")),
            )
            canvas.create_window((0, 0), window=frame, anchor="nw")
            canvas.configure(yscrollcommand=scroll.set)
            canvas.pack(side="left", fill="both", expand=True)
            scroll.pack(side="right", fill="y")
            self.runtime_item_frames[service] = frame

        item_actions = ttk.Frame(build_tab)
        item_actions.pack(fill="x", pady=(6, 0))
        ttk.Button(item_actions, text="Reload runtime items", command=self._reload_runtime_items).pack(side="left")
        ttk.Button(item_actions, text="Clear item selection", command=self._clear_runtime_items).pack(side="left", padx=(8, 0))

        actions = ttk.Frame(build_tab)
        actions.pack(fill="x", pady=(10, 0))
        self.build_app_button = ttk.Button(actions, text="Build App", command=self._run_build_app)
        self.build_app_button.pack(side="left")
        self.cancel_button = ttk.Button(actions, text="Cancel", command=self._cancel_build, state="disabled")
        self.cancel_button.pack(side="left", padx=(8, 0))
        ttk.Button(actions, text="Save State", command=self._save_state).pack(side="left", padx=(8, 0))

        ttk.Label(left_panel, text="Command preview").pack(anchor="w", pady=(10, 0))
        self.command_preview = tk.Text(left_panel, height=3, wrap="word")
        self.command_preview.pack(fill="x")
        self.command_preview.configure(state="disabled")

        ttk.Label(right_panel, text="Logs", font=("TkDefaultFont", 12, "bold")).pack(anchor="w")
        log_wrap = ttk.Frame(right_panel)
        log_wrap.pack(fill="both", expand=True, pady=(8, 0))
        self.output = tk.Text(log_wrap, wrap="word")
        log_scroll = ttk.Scrollbar(log_wrap, orient="vertical", command=self.output.yview)
        self.output.configure(yscrollcommand=log_scroll.set)
        self.output.pack(side="left", fill="both", expand=True)
        log_scroll.pack(side="right", fill="y")

        self._build_sign_tab(sign_tab)
        self._build_dmg_tab(dmg_tab)
        self._build_sparkle_tab(sparkle_tab)
        self._build_release_tab(release_tab)

        self.icon_path.trace_add("write", lambda *_: self._refresh_command_preview())
        self.runtime_root.trace_add("write", lambda *_: self._refresh_command_preview())
        self.version.trace_add("write", lambda *_: self._refresh_command_preview())
        self.app_artifact_path.trace_add("write", lambda *_: self._refresh_app_actions_enabled())
        self.enable_app_sign.trace_add("write", lambda *_: self._refresh_command_preview())
        self.app_sign_identity.trace_add("write", lambda *_: self._refresh_command_preview())
        self.bundle_app_runtime.trace_add("write", lambda *_: self._refresh_command_preview())
        self.enable_sign.trace_add("write", lambda *_: self._refresh_command_preview())
        self.enable_notarize.trace_add("write", lambda *_: self._refresh_command_preview())
        self.sparkle_enabled.trace_add("write", lambda *_: self._refresh_command_preview())
        self.sparkle_framework_path.trace_add("write", lambda *_: self._refresh_command_preview())
        self.sparkle_feed_url.trace_add("write", lambda *_: self._refresh_command_preview())
        self.sparkle_public_ed_key.trace_add("write", lambda *_: self._refresh_command_preview())
        self.version.trace_add("write", lambda *_: self._prefill_release_from_sparkle())
        self.sparkle_release_channel.trace_add("write", lambda *_: self._prefill_release_from_sparkle())
        self.sparkle_arch_override.trace_add("write", lambda *_: self._prefill_release_from_sparkle())
        self.sparkle_metadata_json_path.trace_add("write", lambda *_: self._prefill_release_from_sparkle())
        self.release_dmg_path.trace_add("write", lambda *_: self._sync_release_version_from_dmg_selection())
        self.release_dmg_select_version.trace_add("write", lambda *_: self._sync_release_version_from_dmg_selection())
        self._reload_runtime_items()
        self._reload_app_sign_identities()
        self.after(80, self._set_initial_layout, 0)

    def _set_initial_layout(self, attempt: int = 0) -> None:
        try:
            self.update_idletasks()
            total_width = self.main_layout.winfo_width()
            if total_width <= 1:
                total_width = self.winfo_width() or 1260
            right_width = 500
            left_width = max(200, total_width - right_width)
            self.main_layout.sashpos(0, left_width)
            if attempt < 2:
                self.after(120, self._set_initial_layout, attempt + 1)
        except Exception:
            pass

    def _bind_mousewheel_to_canvas(self, canvas: tk.Canvas) -> None:
        def _on_mousewheel(event: tk.Event) -> None:
            delta = getattr(event, "delta", 0)
            if delta:
                steps = int(-delta / 120) if abs(delta) >= 120 else (-1 if delta > 0 else 1)
                canvas.yview_scroll(steps, "units")
                return
            num = getattr(event, "num", None)
            if num == 4:
                canvas.yview_scroll(-1, "units")
            elif num == 5:
                canvas.yview_scroll(1, "units")

        def _bind(_event: tk.Event) -> None:
            canvas.bind_all("<MouseWheel>", _on_mousewheel)
            canvas.bind_all("<Button-4>", _on_mousewheel)
            canvas.bind_all("<Button-5>", _on_mousewheel)

        def _unbind(_event: tk.Event) -> None:
            canvas.unbind_all("<MouseWheel>")
            canvas.unbind_all("<Button-4>")
            canvas.unbind_all("<Button-5>")

        canvas.bind("<Enter>", _bind)
        canvas.bind("<Leave>", _unbind)

    def _build_sign_tab(self, sign_tab: ttk.Frame) -> None:
        form = ttk.Frame(sign_tab)
        form.pack(fill="x", pady=(4, 0))
        form.columnconfigure(1, weight=1)

        ttk.Label(form, text="Use package").grid(row=0, column=0, sticky="w", pady=6)
        mode_frame = ttk.Frame(form)
        mode_frame.grid(row=0, column=1, sticky="w", pady=6)
        ttk.Radiobutton(mode_frame, text="Last Built", variable=self.pkg_select_mode, value="last_built").pack(side="left")
        ttk.Radiobutton(mode_frame, text="By Version", variable=self.pkg_select_mode, value="by_version").pack(side="left", padx=(8, 0))
        self.pkg_version_combo = ttk.Combobox(form, textvariable=self.pkg_select_version, state="readonly", width=30)
        self.pkg_version_combo.grid(row=1, column=1, sticky="w", pady=6)
        ttk.Button(form, text="Reload PKGs", command=self._reload_pkg_versions).grid(row=1, column=2, padx=(8, 0), pady=6)

        ttk.Checkbutton(form, text="Sign package", variable=self.enable_sign).grid(row=2, column=1, sticky="w", pady=6)
        ttk.Label(form, text="Sign certificate").grid(row=3, column=0, sticky="w", pady=6)
        self.identity_combo = ttk.Combobox(form, state="readonly", width=55)
        self.identity_combo.grid(row=3, column=1, sticky="w", pady=6)
        ttk.Button(form, text="Remove", command=self._remove_selected_identity).grid(row=3, column=2, sticky="w", padx=(8, 0), pady=6)
        self.identity_combo.bind("<<ComboboxSelected>>", self._on_identity_selected)

        ttk.Checkbutton(form, text="Notarize package", variable=self.enable_notarize).grid(row=4, column=1, sticky="w", pady=6)
        ttk.Label(form, text="Apple ID").grid(row=5, column=0, sticky="w", pady=6)
        ttk.Entry(form, textvariable=self.notary_apple_id).grid(row=5, column=1, sticky="ew", pady=6)
        ttk.Label(form, text="Team ID").grid(row=6, column=0, sticky="w", pady=6)
        ttk.Entry(form, textvariable=self.notary_team_id).grid(row=6, column=1, sticky="ew", pady=6)
        ttk.Label(form, text="App Password").grid(row=7, column=0, sticky="w", pady=6)
        ttk.Entry(form, textvariable=self.notary_password, show="*").grid(row=7, column=1, sticky="ew", pady=6)
        ttk.Label(form, text="Notary Submission ID").grid(row=8, column=0, sticky="w", pady=6)
        ttk.Entry(form, textvariable=self.notary_submission_id).grid(row=8, column=1, sticky="ew", pady=6)

        actions = ttk.Frame(sign_tab)
        actions.pack(fill="x", pady=(10, 0))
        self.build_pkg_button = ttk.Button(actions, text="Build PKG", command=self._run_build_pkg)
        self.sign_selected_button = ttk.Button(actions, text="Sign", command=self._sign_selected_pkg)
        self.verify_button = ttk.Button(actions, text="Check Sign", command=self._check_pkg_security)
        self.sign_notarize_selected_button = ttk.Button(actions, text="Sign + Notarize", command=self._sign_notarize_selected_pkg)
        self.notary_status_button = ttk.Button(actions, text="Notary Status", command=self._check_notary_status)
        self.staple_button = ttk.Button(actions, text="Staple", command=self._staple_selected_pkg)
        self.cancel_sign_button = ttk.Button(actions, text="Cancel Sign", command=self._cancel_sign, state="disabled")
        self.build_pkg_button.grid(row=0, column=0, sticky="w", padx=(0, 8), pady=(0, 6))
        self.sign_selected_button.grid(row=0, column=1, sticky="w", padx=(0, 8), pady=(0, 6))
        self.verify_button.grid(row=0, column=2, sticky="w", padx=(0, 8), pady=(0, 6))
        self.sign_notarize_selected_button.grid(row=0, column=3, sticky="w", pady=(0, 6))
        self.notary_status_button.grid(row=1, column=0, sticky="w", padx=(0, 8))
        self.staple_button.grid(row=1, column=1, sticky="w", padx=(0, 8))
        self.cancel_sign_button.grid(row=1, column=2, sticky="w")
        self.pkg_select_mode.trace_add("write", lambda *_: self._refresh_command_preview())
        self.pkg_select_version.trace_add("write", lambda *_: self._refresh_command_preview())
        self.pkg_select_mode.trace_add("write", lambda *_: self._refresh_sign_actions_enabled())
        self.pkg_select_version.trace_add("write", lambda *_: self._refresh_sign_actions_enabled())
        self.sign_identity.trace_add("write", lambda *_: self._refresh_command_preview())
        self.notary_apple_id.trace_add("write", lambda *_: self._refresh_command_preview())
        self.notary_team_id.trace_add("write", lambda *_: self._refresh_command_preview())
        self.notary_password.trace_add("write", lambda *_: self._refresh_command_preview())
        self._reload_pkg_versions()
        self._reload_sign_identities()
        self._refresh_sign_actions_enabled()

    def _build_dmg_tab(self, dmg_tab: ttk.Frame) -> None:
        app_box = ttk.LabelFrame(dmg_tab, text="App Sign / Notary")
        app_box.pack(fill="x", pady=(0, 8))
        app_form = ttk.Frame(app_box, padding=8)
        app_form.pack(fill="x")
        app_form.columnconfigure(1, weight=1)
        ttk.Label(app_form, text="App bundle").grid(row=0, column=0, sticky="w", pady=6)
        ttk.Entry(app_form, textvariable=self.app_artifact_path).grid(row=0, column=1, sticky="ew", pady=6)
        ttk.Button(app_form, text="Choose…", command=self._pick_app_bundle).grid(row=0, column=2, padx=(8, 0), pady=6)
        ttk.Label(app_form, text="App Notary Submission ID").grid(row=1, column=0, sticky="w", pady=6)
        ttk.Entry(app_form, textvariable=self.app_notary_submission_id).grid(row=1, column=1, sticky="ew", pady=6)

        app_actions = ttk.Frame(app_box, padding=(8, 0, 8, 8))
        app_actions.pack(fill="x")
        self.verify_app_button = ttk.Button(app_actions, text="Check App Sign", command=self._check_app_security)
        self.verify_app_runtime_button = ttk.Button(app_actions, text="Check Runtime Mach-O Sign", command=self._check_app_runtime_signatures)
        self.sign_app_runtime_button = ttk.Button(app_actions, text="Sign Runtime", command=self._sign_app_runtime)
        self.sign_app_button = ttk.Button(app_actions, text="Sign App", command=self._sign_selected_app)
        self.sign_notarize_app_button = ttk.Button(app_actions, text="Notarize App", command=self._notarize_selected_app)
        self.staple_app_button = ttk.Button(app_actions, text="Staple App", command=self._staple_selected_app)
        self.notary_status_app_button = ttk.Button(app_actions, text="App Notary Status", command=self._check_app_notary_status)
        self.verify_app_button.grid(row=0, column=0, sticky="w", padx=(0, 8), pady=(0, 6))
        self.verify_app_runtime_button.grid(row=0, column=1, sticky="w", padx=(0, 8), pady=(0, 6))
        self.sign_app_runtime_button.grid(row=0, column=2, sticky="w", pady=(0, 6))
        self.sign_app_button.grid(row=1, column=0, sticky="w", padx=(0, 8))
        self.sign_notarize_app_button.grid(row=1, column=1, sticky="w", padx=(0, 8))
        self.staple_app_button.grid(row=1, column=2, sticky="w")
        self.notary_status_app_button.grid(row=2, column=0, sticky="w", pady=(6, 0))

        ttk.Separator(dmg_tab, orient="horizontal").pack(fill="x", pady=(4, 10))

        form = ttk.Frame(dmg_tab)
        form.pack(fill="x", pady=(4, 0))
        form.columnconfigure(1, weight=1)

        ttk.Label(form, text="Use DMG").grid(row=0, column=0, sticky="w", pady=6)
        self.dmg_select_mode = tk.StringVar(value="last_built")
        self.dmg_select_version = tk.StringVar(value="")
        mode_frame = ttk.Frame(form)
        mode_frame.grid(row=0, column=1, sticky="w", pady=6)
        ttk.Radiobutton(mode_frame, text="Last Built", variable=self.dmg_select_mode, value="last_built").pack(side="left")
        ttk.Radiobutton(mode_frame, text="By Version", variable=self.dmg_select_mode, value="by_version").pack(side="left", padx=(8, 0))
        self.dmg_version_combo = ttk.Combobox(form, textvariable=self.dmg_select_version, state="readonly", width=30)
        self.dmg_version_combo.grid(row=1, column=1, sticky="w", pady=6)
        ttk.Button(form, text="Reload DMGs", command=self._reload_dmg_versions).grid(row=1, column=2, padx=(8, 0), pady=6)
        ttk.Label(form, text="DMG Notary Submission ID").grid(row=2, column=0, sticky="w", pady=6)
        ttk.Entry(form, textvariable=self.dmg_notary_submission_id).grid(row=2, column=1, sticky="ew", pady=6)

        actions = ttk.Frame(dmg_tab)
        actions.pack(fill="x", pady=(10, 0))
        self.build_dmg_button = ttk.Button(actions, text="Build DMG", command=self._run_build_dmg)
        self.build_dmg_button.pack(side="left")
        self.reveal_dmg_button = ttk.Button(actions, text="Reveal in Finder", command=self._reveal_dmg, state="disabled")
        self.reveal_dmg_button.pack(side="left", padx=(8, 0))
        self.run_dmg_button = ttk.Button(actions, text="Open DMG", command=self._run_dmg, state="disabled")
        self.run_dmg_button.pack(side="left", padx=(8, 0))

        sign_actions = ttk.Frame(dmg_tab)
        sign_actions.pack(fill="x", pady=(10, 0))
        self.verify_dmg_button = ttk.Button(sign_actions, text="Check Sign", command=self._check_dmg_security, state="disabled")
        self.sign_dmg_button = ttk.Button(sign_actions, text="Sign", command=self._sign_selected_dmg, state="disabled")
        self.sign_notarize_dmg_button = ttk.Button(
            sign_actions, text="Notarize DMG", command=self._notarize_selected_dmg, state="disabled"
        )
        self.notary_status_dmg_button = ttk.Button(sign_actions, text="DMG Notary Status", command=self._check_dmg_notary_status, state="disabled")
        self.staple_dmg_button = ttk.Button(sign_actions, text="Staple", command=self._staple_selected_dmg, state="disabled")
        self.verify_dmg_button.grid(row=0, column=0, sticky="w", padx=(0, 8), pady=(0, 6))
        self.sign_dmg_button.grid(row=0, column=1, sticky="w", padx=(0, 8), pady=(0, 6))
        self.sign_notarize_dmg_button.grid(row=0, column=2, sticky="w", pady=(0, 6))
        self.notary_status_dmg_button.grid(row=1, column=0, sticky="w", padx=(0, 8))
        self.staple_dmg_button.grid(row=1, column=1, sticky="w")

        self.dmg_select_mode.trace_add("write", lambda *_: self._refresh_dmg_actions_enabled())
        self.dmg_select_version.trace_add("write", lambda *_: self._refresh_dmg_actions_enabled())
        self._reload_dmg_versions()
        self._refresh_app_actions_enabled()

    def _build_sparkle_tab(self, sparkle_tab: ttk.Frame) -> None:
        body = ttk.Frame(sparkle_tab)
        body.pack(fill="both", expand=True)
        self._build_sparkle_section(body)

    def _build_release_tab(self, release_tab: ttk.Frame) -> None:
        canvas = tk.Canvas(release_tab, highlightthickness=0)
        scroll = ttk.Scrollbar(release_tab, orient="vertical", command=canvas.yview)
        content = ttk.Frame(canvas)
        content_window = canvas.create_window((0, 0), window=content, anchor="nw")

        def _sync_scrollregion(_event: tk.Event | None = None) -> None:
            canvas.configure(scrollregion=canvas.bbox("all"))

        def _sync_width(_event: tk.Event | None = None) -> None:
            canvas.itemconfigure(content_window, width=canvas.winfo_width())

        content.bind("<Configure>", _sync_scrollregion)
        canvas.bind("<Configure>", _sync_width)
        canvas.configure(yscrollcommand=scroll.set)
        canvas.pack(side="left", fill="both", expand=True)
        scroll.pack(side="right", fill="y")
        self._bind_mousewheel_to_canvas(canvas)

        dmg_box = ttk.LabelFrame(content, text="DMG Source")
        dmg_box.pack(fill="x", pady=(0, 10))
        dmg_form = ttk.Frame(dmg_box, padding=8)
        dmg_form.pack(fill="x")
        dmg_form.columnconfigure(1, weight=1)
        ttk.Label(dmg_form, text="Use DMG").grid(row=0, column=0, sticky="w", pady=4)
        mode = ttk.Frame(dmg_form)
        mode.grid(row=0, column=1, sticky="w", pady=4)
        ttk.Radiobutton(mode, text="Last Built", variable=self.release_dmg_select_mode, value="last_built").pack(side="left")
        ttk.Radiobutton(mode, text="By Version", variable=self.release_dmg_select_mode, value="by_version").pack(side="left", padx=(8, 0))
        self.release_dmg_combo = ttk.Combobox(dmg_form, textvariable=self.release_dmg_select_version, state="readonly", width=34)
        self.release_dmg_combo.grid(row=1, column=1, sticky="w", pady=4)
        self.release_dmg_combo.bind("<<ComboboxSelected>>", lambda _event: self._sync_release_version_from_dmg_selection())
        ttk.Button(dmg_form, text="Reload DMGs", command=self._reload_release_dmg_versions).grid(row=1, column=2, padx=(8, 0), pady=4)
        ttk.Label(dmg_form, text="Explicit file").grid(row=2, column=0, sticky="w", pady=4)
        ttk.Entry(dmg_form, textvariable=self.release_dmg_path).grid(row=2, column=1, sticky="ew", pady=4)
        ttk.Button(dmg_form, text="Choose…", command=self._pick_release_dmg).grid(row=2, column=2, padx=(8, 0), pady=4)

        auth_box = ttk.LabelFrame(content, text="Server Login")
        auth_box.pack(fill="x", pady=(0, 10))
        auth_row = ttk.Frame(auth_box, padding=8)
        auth_row.pack(fill="x")
        self.release_login_status = tk.StringVar(value="")
        ttk.Label(auth_row, textvariable=self.release_login_status).pack(side="left")
        self.release_login_button = ttk.Button(auth_row, text="Login…", command=self._open_upload_login_popup)
        self.release_login_button.pack(side="right")
        self.release_logout_button = ttk.Button(auth_row, text="Logout", command=self._upload_logout)
        self.release_logout_button.pack(side="right", padx=(0, 8))

        upload_box = ttk.LabelFrame(content, text="Sparkle Release Upload")
        upload_box.pack(fill="x", pady=(0, 8))
        upload_form = ttk.Frame(upload_box, padding=8)
        upload_form.pack(fill="x")
        upload_form.columnconfigure(1, weight=1)

        ttk.Label(upload_form, text="Version").grid(row=0, column=0, sticky="w", pady=4)
        ttk.Entry(upload_form, textvariable=self.upload_version).grid(row=0, column=1, sticky="ew", pady=4)
        ttk.Label(upload_form, text="Build").grid(row=1, column=0, sticky="w", pady=4)
        ttk.Entry(upload_form, textvariable=self.upload_build).grid(row=1, column=1, sticky="ew", pady=4)
        ttk.Label(upload_form, text="Min System").grid(row=2, column=0, sticky="w", pady=4)
        ttk.Entry(upload_form, textvariable=self.upload_min_system_version).grid(row=2, column=1, sticky="ew", pady=4)
        ttk.Label(upload_form, text="OS").grid(row=3, column=0, sticky="w", pady=4)
        ttk.Entry(upload_form, textvariable=self.upload_os).grid(row=3, column=1, sticky="ew", pady=4)
        ttk.Label(upload_form, text="Arch").grid(row=4, column=0, sticky="w", pady=4)
        ttk.Entry(upload_form, textvariable=self.upload_arch).grid(row=4, column=1, sticky="ew", pady=4)
        ttk.Label(upload_form, text="Release Notes URL").grid(row=5, column=0, sticky="w", pady=4)
        ttk.Entry(upload_form, textvariable=self.upload_release_notes_url).grid(row=5, column=1, sticky="ew", pady=4)
        ttk.Checkbutton(upload_form, text="Critical update", variable=self.upload_critical_update).grid(row=6, column=1, sticky="w", pady=4)
        ttk.Label(upload_form, text="Phased rollout interval").grid(row=7, column=0, sticky="w", pady=4)
        ttk.Entry(upload_form, textvariable=self.upload_phased_rollout_interval).grid(row=7, column=1, sticky="ew", pady=4)
        ttk.Label(upload_form, text="Staging percentage").grid(row=8, column=0, sticky="w", pady=4)
        ttk.Entry(upload_form, textvariable=self.upload_staging_percentage).grid(row=8, column=1, sticky="ew", pady=4)

        ttk.Label(upload_form, text="Release Notes HTML").grid(row=9, column=0, sticky="nw", pady=4)
        self.upload_release_notes_html_text = tk.Text(upload_form, height=6, wrap="word")
        self.upload_release_notes_html_text.grid(row=9, column=1, columnspan=2, sticky="ew", pady=4)

        upload_actions = ttk.Frame(upload_box, padding=(8, 0, 8, 8))
        upload_actions.pack(fill="x")
        ttk.Button(upload_actions, text="Use Sparkle Values", command=self._prefill_release_from_sparkle).pack(side="left")
        ttk.Button(upload_actions, text="Fetch Releases", command=lambda: self._upload_fetch_releases(silent=False)).pack(side="left")
        ttk.Button(upload_actions, text="Upload to Server", command=self._upload_dmg_to_server).pack(side="left", padx=(8, 0))
        self._prefill_release_from_sparkle()
        self._reload_release_dmg_versions()
        self._refresh_release_login_ui()

    def _prefill_release_from_sparkle(self) -> None:
        # Base defaults from existing build/sparkle tab fields.
        version_value = self.version.get().strip()
        if version_value and not self.upload_version.get().strip():
            self.upload_version.set(version_value)
        if version_value and not self.upload_build.get().strip():
            self.upload_build.set(self._default_release_build_stamp())
        arch_value = self.sparkle_arch_override.get().strip()
        if arch_value and not self.upload_arch.get().strip():
            self.upload_arch.set(arch_value)

        # If Sparkle metadata JSON exists, use authoritative upload values.
        metadata_path = self.sparkle_metadata_json_path.get().strip()
        if not metadata_path:
            return
        metadata_file = Path(metadata_path)
        if not metadata_file.exists():
            return
        try:
            payload = json.loads(metadata_file.read_text(encoding="utf-8"))
        except Exception:
            return
        if not isinstance(payload, dict):
            return
        version = str(payload.get("version") or "").strip()
        build = str(payload.get("build") or "").strip()
        arch = str(payload.get("arch") or "").strip()
        signature = str(payload.get("sparkleEdSignature") or payload.get("sparkle_ed_signature") or "").strip()
        if version:
            self.upload_version.set(version)
        if build and not self.upload_build.get().strip():
            self.upload_build.set(build)
        elif not self.upload_build.get().strip():
            self.upload_build.set(self._default_release_build_stamp())
        if arch:
            self.upload_arch.set(arch)
        if signature:
            self.upload_sparkle_ed_signature.set(signature)

    def _build_sparkle_section(self, parent: ttk.Frame) -> None:
        sparkle_box = ttk.LabelFrame(parent, text="Sparkle (Auto Update)")
        sparkle_box.pack(fill="x", pady=(12, 0))
        sparkle_form = ttk.Frame(sparkle_box, padding=8)
        sparkle_form.pack(fill="x")
        sparkle_form.columnconfigure(1, weight=1)

        ttk.Checkbutton(
            sparkle_form,
            text="Enable Sparkle in app build",
            variable=self.sparkle_enabled,
            command=self._refresh_command_preview,
        ).grid(row=0, column=0, columnspan=2, sticky="w", pady=4)

        ttk.Label(sparkle_form, text="Sparkle.framework").grid(row=1, column=0, sticky="w", pady=4)
        ttk.Entry(sparkle_form, textvariable=self.sparkle_framework_path).grid(row=1, column=1, sticky="ew", pady=4)
        ttk.Button(sparkle_form, text="Choose…", command=self._pick_sparkle_framework).grid(row=1, column=2, padx=(8, 0), pady=4)

        ttk.Label(sparkle_form, text="Framework sign certificate").grid(row=2, column=0, sticky="w", pady=4)
        self.sparkle_identity_combo = ttk.Combobox(sparkle_form, state="readonly", width=55)
        self.sparkle_identity_combo.grid(row=2, column=1, sticky="ew", pady=4)
        ttk.Button(sparkle_form, text="Reload", command=self._reload_app_sign_identities).grid(row=2, column=2, padx=(8, 0), pady=4)
        self.sparkle_identity_combo.bind("<<ComboboxSelected>>", self._on_sparkle_identity_selected)

        ttk.Entry(sparkle_form, textvariable=self.sparkle_feed_url).grid(row=3, column=1, columnspan=2, sticky="ew", pady=4)
        ttk.Label(sparkle_form, text="Appcast URL (SUFeedURL)").grid(row=3, column=0, sticky="w", pady=4)

        ttk.Label(sparkle_form, text="Public ED Key (SUPublicEDKey)").grid(row=4, column=0, sticky="w", pady=4)
        ttk.Entry(sparkle_form, textvariable=self.sparkle_public_ed_key).grid(row=4, column=1, sticky="ew", pady=4)
        ttk.Button(sparkle_form, text="Read Key", command=self._sparkle_read_public_key).grid(row=4, column=2, padx=(8, 0), pady=4)

        ttk.Label(sparkle_form, text="Sparkle tools dir").grid(row=5, column=0, sticky="w", pady=4)
        ttk.Entry(sparkle_form, textvariable=self.sparkle_tools_dir).grid(row=5, column=1, sticky="ew", pady=4)
        ttk.Button(sparkle_form, text="Choose…", command=self._pick_sparkle_tools_dir).grid(row=5, column=2, padx=(8, 0), pady=4)

        ttk.Label(sparkle_form, text="Key account").grid(row=6, column=0, sticky="w", pady=4)
        ttk.Entry(sparkle_form, textvariable=self.sparkle_key_account, width=20).grid(row=6, column=1, sticky="w", pady=4)

        ttk.Label(sparkle_form, text="Private key file (optional)").grid(row=7, column=0, sticky="w", pady=4)
        ttk.Entry(sparkle_form, textvariable=self.sparkle_private_key_file).grid(row=7, column=1, sticky="ew", pady=4)
        ttk.Button(sparkle_form, text="Choose…", command=self._pick_sparkle_private_key_file).grid(row=7, column=2, padx=(8, 0), pady=4)

        key_actions = ttk.Frame(sparkle_form)
        key_actions.grid(row=8, column=0, columnspan=3, sticky="w", pady=(6, 2))
        ttk.Button(key_actions, text="Check Framework Sign", command=self._check_sparkle_framework_security).pack(side="left")
        ttk.Button(key_actions, text="Sign Framework", command=self._sign_sparkle_framework_in_app).pack(side="left", padx=(8, 0))
        ttk.Button(key_actions, text="Inject Framework Into App", command=self._sparkle_inject_framework_into_app).pack(side="left", padx=(8, 0))
        ttk.Button(key_actions, text="Generate Key", command=self._sparkle_generate_key).pack(side="left")
        ttk.Button(key_actions, text="Export Key", command=self._sparkle_export_key).pack(side="left", padx=(8, 0))
        ttk.Button(key_actions, text="Import Key", command=self._sparkle_import_key).pack(side="left", padx=(8, 0))

        ttk.Separator(sparkle_box, orient="horizontal").pack(fill="x", padx=8, pady=(6, 6))
        meta_form = ttk.Frame(sparkle_box, padding=(8, 2, 8, 8))
        meta_form.pack(fill="x")
        meta_form.columnconfigure(1, weight=1)
        ttk.Label(meta_form, text="Release channel").grid(row=0, column=0, sticky="w", pady=4)
        ttk.Entry(meta_form, textvariable=self.sparkle_release_channel, width=20).grid(row=0, column=1, sticky="w", pady=4)
        ttk.Label(meta_form, text="Arch override").grid(row=1, column=0, sticky="w", pady=4)
        ttk.Entry(meta_form, textvariable=self.sparkle_arch_override, width=20).grid(row=1, column=1, sticky="w", pady=4)
        ttk.Label(meta_form, text="Metadata JSON output").grid(row=2, column=0, sticky="w", pady=4)
        ttk.Entry(meta_form, textvariable=self.sparkle_metadata_json_path).grid(row=2, column=1, sticky="ew", pady=4)
        ttk.Button(meta_form, text="Choose…", command=self._pick_sparkle_metadata_output).grid(row=2, column=2, padx=(8, 0), pady=4)
        ttk.Button(meta_form, text="Prepare Release Metadata", command=self._sparkle_prepare_release_metadata).grid(row=3, column=0, columnspan=3, sticky="w", pady=(6, 2))


    def _pick_icon(self) -> None:
        path = filedialog.askopenfilename(
            title="Choose App Icon",
            filetypes=[("ICNS files", "*.icns"), ("All files", "*.*")],
        )
        if path:
            self.icon_path.set(path)

    def _pick_runtime_root(self) -> None:
        path = filedialog.askdirectory(title="Choose Runtime Root")
        if path:
            self.runtime_root.set(path)

    def _pick_app_bundle(self) -> None:
        path = filedialog.askdirectory(title="Choose App Bundle (.app)")
        if path:
            self.app_artifact_path.set(path)

    def _pick_sparkle_framework(self) -> None:
        path = filedialog.askdirectory(title="Choose Sparkle.framework")
        if path:
            self.sparkle_framework_path.set(path)

    def _pick_sparkle_tools_dir(self) -> None:
        path = filedialog.askdirectory(title="Choose Sparkle tools directory (contains generate_keys/sign_update)")
        if path:
            self.sparkle_tools_dir.set(path)

    def _pick_sparkle_private_key_file(self) -> None:
        path = filedialog.askopenfilename(title="Choose Sparkle private key file")
        if path:
            self.sparkle_private_key_file.set(path)

    def _pick_sparkle_metadata_output(self) -> None:
        path = filedialog.asksaveasfilename(
            title="Choose Sparkle metadata JSON output",
            defaultextension=".json",
            filetypes=[("JSON files", "*.json"), ("All files", "*.*")],
        )
        if path:
            self.sparkle_metadata_json_path.set(path)

    def _sparkle_tool_binary(self, name: str) -> str | None:
        tools_dir = self.sparkle_tools_dir.get().strip()
        if tools_dir:
            candidate = Path(tools_dir) / name
            if candidate.exists() and os.access(candidate, os.X_OK):
                return str(candidate)
        framework_path = self.sparkle_framework_path.get().strip()
        if framework_path:
            framework = Path(framework_path)
            nearby_bins = (
                framework.parent / "bin",
                framework.parent.parent / "bin",
                framework.parent.parent.parent / "bin",
            )
            for bin_dir in nearby_bins:
                candidate = bin_dir / name
                if candidate.exists() and os.access(candidate, os.X_OK):
                    self.sparkle_tools_dir.set(str(bin_dir))
                    return str(candidate)
        for candidate in (
            REPO_ROOT / ".build" / "sparkle" / "bin" / name,
            REPO_ROOT / "vendor" / "Sparkle" / "bin" / name,
            REPO_ROOT / "Sparkle" / "bin" / name,
            Path.home() / "Downloads" / "Sparkle" / "bin" / name,
            Path("/opt/homebrew/Caskroom/sparkle/2.9.2/bin") / name,
            Path("/opt/homebrew/bin") / name,
            Path("/usr/local/bin") / name,
        ):
            if candidate.exists() and os.access(candidate, os.X_OK):
                self.sparkle_tools_dir.set(str(candidate.parent))
                return str(candidate)
        return None

    def _sparkle_inject_framework_into_app(self) -> None:
        app_bundle = self._selected_app_bundle()
        if not app_bundle.exists():
            messagebox.showwarning("Sparkle", f"App bundle not found:\n{app_bundle}")
            return
        source = Path(self.sparkle_framework_path.get().strip())
        if not source.exists() or source.name != "Sparkle.framework":
            auto_source = Path(detect_default_sparkle_framework())
            if auto_source.exists() and auto_source.name == "Sparkle.framework":
                source = auto_source
                self.sparkle_framework_path.set(str(source))
            else:
                messagebox.showwarning(
                    "Sparkle",
                    "Select a valid Sparkle.framework source path first.\n\n"
                    "Recommended source:\n"
                    "/opt/homebrew/Caskroom/sparkle/<version>/Sparkle.framework",
                )
                return
        target = app_bundle / "Contents" / "Frameworks" / "Sparkle.framework"
        if source.resolve() == target.resolve():
            messagebox.showwarning(
                "Sparkle",
                "Sparkle source path points to the app target itself.\n"
                "Choose external source framework from Homebrew Caskroom.",
            )
            return
        try:
            target.parent.mkdir(parents=True, exist_ok=True)
            if target.exists():
                shutil.rmtree(target)
            shutil.copytree(source, target, symlinks=True)
            plist_updates = self._apply_sparkle_and_helper_plist_settings(app_bundle)
            self._append_output(f"Injected Sparkle.framework into app:\n  source={source}\n  target={target}\n")
            if plist_updates:
                self._append_output("Updated app Info.plist entries:\n")
                for item in plist_updates:
                    self._append_output(f"  - {item}\n")
            self._refresh_app_actions_enabled()
        except Exception as exc:
            messagebox.showerror("Sparkle", f"Inject framework failed: {exc}")

    def _apply_sparkle_and_helper_plist_settings(self, app_bundle: Path) -> list[str]:
        info_plist = app_bundle / "Contents" / "Info.plist"
        if not info_plist.exists():
            raise FileNotFoundError(f"Info.plist not found: {info_plist}")
        with info_plist.open("rb") as f:
            data = plistlib.load(f)
        if not isinstance(data, dict):
            raise ValueError(f"Unexpected Info.plist format: {info_plist}")

        updates: list[str] = []
        feed_url = self.sparkle_feed_url.get().strip()
        public_key = self.sparkle_public_ed_key.get().strip()
        if feed_url:
            data["SUFeedURL"] = feed_url
            updates.append(f"SUFeedURL={feed_url}")
        if public_key:
            data["SUPublicEDKey"] = public_key
            updates.append("SUPublicEDKey=<set>")

        helper_id = "com.serverengine.app.helper"
        team_id = self._extract_team_id_from_identity(self.app_sign_identity.get().strip())
        team_id = team_id or "G54PTLH399"
        requirement = (
            f'identifier "{helper_id}" and anchor apple generic '
            f'and certificate leaf[subject.OU] = "{team_id}"'
        )
        sm_priv = data.get("SMPrivilegedExecutables")
        if not isinstance(sm_priv, dict):
            sm_priv = {}
            data["SMPrivilegedExecutables"] = sm_priv
        sm_priv[helper_id] = requirement
        updates.append(f'SMPrivilegedExecutables[{helper_id}] team={team_id}')

        with info_plist.open("wb") as f:
            plistlib.dump(data, f, sort_keys=False)
        return updates

    @staticmethod
    def _extract_team_id_from_identity(identity: str) -> str:
        text = (identity or "").strip()
        if not text:
            return ""
        match = re.search(r"\(([A-Z0-9]{10})\)\s*$", text)
        return match.group(1) if match else ""

    def _run_background_commands(self, commands: list[list[str]], success_message: str = "") -> None:
        if self.sign_process is not None:
            return
        self._save_state()
        self._set_sign_running(True)

        def worker() -> None:
            try:
                for cmd in commands:
                    self.after(0, self._append_output, f"\n$ {' '.join(shlex.quote(part) for part in cmd)}\n")
                    process = subprocess.Popen(
                        cmd,
                        cwd=str(REPO_ROOT),
                        stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT,
                        text=True,
                        bufsize=1,
                        preexec_fn=os.setsid if os.name == "posix" else None,
                    )
                    self.sign_process = process
                    self._stream_process_output(process)
                    code = process.wait()
                    if code != 0:
                        self.after(0, self._append_output, f"\nCommand failed with exit code {code}.\n")
                        return
                if success_message:
                    self.after(0, self._append_output, f"\n{success_message}\n")
            except Exception as exc:
                self.after(0, self._append_output, f"\nCommand error: {exc}\n")
            finally:
                self.sign_process = None
                self.after(0, self._set_sign_running, False)

        threading.Thread(target=worker, daemon=True).start()

    def _sparkle_read_public_key(self) -> None:
        generate_keys = self._sparkle_tool_binary("generate_keys")
        if not generate_keys:
            messagebox.showerror(
                "Sparkle",
                "generate_keys not found.\n\nSet Sparkle tools dir to the Sparkle distribution 'bin' folder that contains:\n- generate_keys\n- sign_update",
            )
            return
        account = self.sparkle_key_account.get().strip() or "ed25519"
        try:
            result = subprocess.run(
                [generate_keys, "--account", account, "-p"],
                capture_output=True,
                text=True,
                check=False,
            )
        except Exception as exc:
            messagebox.showerror("Sparkle", f"Read public key failed: {exc}")
            return
        output = ((result.stdout or "") + "\n" + (result.stderr or "")).strip()
        if result.returncode != 0:
            self._append_output(output + "\n")
            messagebox.showerror("Sparkle", "Cannot read key. Use Generate Key first.")
            return
        key = ""
        for line in output.splitlines():
            line = line.strip()
            if line and " " not in line and len(line) >= 40:
                key = line
        if not key:
            key = output.splitlines()[-1].strip() if output else ""
        self.sparkle_public_ed_key.set(key)
        self._append_output(f"Sparkle public key loaded: {key}\n")
        self._save_state()

    def _sparkle_generate_key(self) -> None:
        generate_keys = self._sparkle_tool_binary("generate_keys")
        if not generate_keys:
            messagebox.showerror(
                "Sparkle",
                "generate_keys not found.\n\nSet Sparkle tools dir to the Sparkle distribution 'bin' folder that contains:\n- generate_keys\n- sign_update",
            )
            return
        account = self.sparkle_key_account.get().strip() or "ed25519"
        self._run_background_commands([[generate_keys, "--account", account]], "Sparkle key generation completed.")
        self.after(900, self._sparkle_read_public_key)

    def _sparkle_export_key(self) -> None:
        generate_keys = self._sparkle_tool_binary("generate_keys")
        if not generate_keys:
            messagebox.showerror(
                "Sparkle",
                "generate_keys not found.\n\nSet Sparkle tools dir to the Sparkle distribution 'bin' folder that contains:\n- generate_keys\n- sign_update",
            )
            return
        default_name = "sparkle_private_key.txt"
        path = filedialog.asksaveasfilename(
            title="Export Sparkle Private Key",
            defaultextension=".txt",
            initialfile=default_name,
            filetypes=[("Text files", "*.txt"), ("All files", "*.*")],
        )
        if not path:
            return
        account = self.sparkle_key_account.get().strip() or "ed25519"
        self.sparkle_private_key_file.set(path)
        self._run_background_commands([[generate_keys, "--account", account, "-x", path]], f"Sparkle private key exported to {path}")

    def _sparkle_import_key(self) -> None:
        generate_keys = self._sparkle_tool_binary("generate_keys")
        if not generate_keys:
            messagebox.showerror(
                "Sparkle",
                "generate_keys not found.\n\nSet Sparkle tools dir to the Sparkle distribution 'bin' folder that contains:\n- generate_keys\n- sign_update",
            )
            return
        path = filedialog.askopenfilename(title="Import Sparkle Private Key File")
        if not path:
            return
        account = self.sparkle_key_account.get().strip() or "ed25519"
        self.sparkle_private_key_file.set(path)
        self._run_background_commands([[generate_keys, "--account", account, "-f", path]], "Sparkle private key imported.")
        self.after(900, self._sparkle_read_public_key)

    def _sparkle_prepare_release_metadata(self) -> None:
        if self.running or self.sign_process is not None:
            return
        if not SPARKLE_PREPARE_SCRIPT_PATH.exists():
            messagebox.showerror("Sparkle", f"Script not found: {SPARKLE_PREPARE_SCRIPT_PATH}")
            return
        dmg = self._resolved_dmg_for_sign()
        if dmg is None or not dmg.exists():
            messagebox.showwarning("Sparkle", "No DMG found. Build DMG first.")
            return
        app_bundle = self._selected_app_bundle()
        if not app_bundle.exists():
            messagebox.showwarning("Sparkle", f"App bundle not found:\n{app_bundle}")
            return
        sign_update = self._sparkle_tool_binary("sign_update")
        if not sign_update:
            messagebox.showerror("Sparkle", "sign_update not found. Set Sparkle tools dir first.")
            return

        cmd = [str(SPARKLE_PREPARE_SCRIPT_PATH), "--dmg", str(dmg), "--app", str(app_bundle), "--sign-update", sign_update]
        private_key_file = self.sparkle_private_key_file.get().strip()
        if private_key_file:
            cmd.extend(["--private-key-file", private_key_file])
        channel = self.sparkle_release_channel.get().strip()
        if channel:
            cmd.extend(["--channel", channel])
        arch = self.sparkle_arch_override.get().strip()
        if arch:
            cmd.extend(["--arch", arch])
        output_json = self.sparkle_metadata_json_path.get().strip()
        if output_json:
            cmd.extend(["--output-json", output_json])

        self._run_background_commands([cmd], "Sparkle release metadata generated.")

    def _sparkle_framework_in_selected_app(self) -> Path:
        return self._selected_app_bundle() / "Contents" / "Frameworks" / "Sparkle.framework"

    def _check_sparkle_framework_security(self) -> None:
        framework = self._sparkle_framework_in_selected_app()
        if not framework.exists():
            messagebox.showwarning("Sparkle", f"Sparkle.framework not found in selected app:\n{framework}")
            return
        self._run_sign_commands(
            [
                [
                    "sh",
                    "-lc",
                    "/usr/bin/codesign -dv --verbose=4 "
                    + shlex.quote(str(framework))
                    + " 2>&1",
                ],
                ["codesign", "--verify", "--deep", "--strict", "--verbose=4", str(framework)],
            ]
        )

    def _sign_sparkle_framework_in_app(self) -> None:
        framework = self._sparkle_framework_in_selected_app()
        if not framework.exists():
            messagebox.showwarning("Sparkle", f"Sparkle.framework not found in selected app:\n{framework}")
            return
        identity = self.app_sign_identity.get().strip()
        if not identity:
            messagebox.showwarning("Sparkle", "App sign identity is required.")
            return
        self._run_sign_commands(
            [
                ["codesign", "--force", "--timestamp", "--options", "runtime", "--sign", identity, str(framework)],
                ["codesign", "--verify", "--deep", "--strict", "--verbose=4", str(framework)],
            ]
        )

    def _selected_services(self) -> list[str]:
        return [name for name in SERVICES if self.service_vars[name].get()]

    def _runtime_scan_base(self, root: Path) -> Path:
        # Supports selecting either runtime root (.../Server Engine) or bin root (.../Server Engine/bin),
        # plus custom folders that directly contain runtime service directories.
        if (root / "bin").is_dir():
            return root / "bin"
        if any((root / name).is_dir() for name in ("php", "database", "server", "redis", "memcached", "mailpit", "tools", "node")):
            return root
        return root / "bin"

    def _runtime_items(self) -> list[str]:
        root = Path(self.runtime_root.get().strip() or DEFAULT_RUNTIME_ROOT)
        if not root.is_dir():
            return []
        base = self._runtime_scan_base(root)
        items: list[str] = []
        for service in SERVICES:
            service_root = base / service
            if service == "tools":
                # For tools, only include concrete leaf version folders (e.g. tools/openssl/openssl-3.6.2).
                if not service_root.is_dir():
                    continue
                for tool_dir in sorted(service_root.iterdir(), key=lambda p: p.name.lower()):
                    if not tool_dir.is_dir():
                        continue
                    for child in sorted(tool_dir.iterdir(), key=lambda p: p.name.lower()):
                        if child.is_dir():
                            rel = str(child.relative_to(base)).replace("\\", "/")
                            if rel not in items:
                                items.append(rel)
                continue
            if not service_root.is_dir():
                continue
            for child in sorted(service_root.iterdir(), key=lambda p: p.name.lower()):
                if child.is_dir():
                    items.append(str(child.relative_to(base)).replace("\\", "/"))
        return items

    def _item_built_os_version(self, service: str, rel: str) -> str:
        cache_key = f"{service}:{rel}"
        if cache_key in self.runtime_item_os_cache:
            return self.runtime_item_os_cache[cache_key]
        root = Path(self.runtime_root.get().strip() or DEFAULT_RUNTIME_ROOT)
        base = self._runtime_scan_base(root)
        path = base / rel
        if platform.system() != "Darwin" or not path.exists():
            self.runtime_item_os_cache[cache_key] = ""
            return ""
        candidates: list[Path] = []
        for pattern in DEFAULT_BINARIES.get(service, ()):
            candidates.extend(path.glob(pattern))
        binary = next((item for item in candidates if item.is_file()), None)
        if binary is None:
            self.runtime_item_os_cache[cache_key] = ""
            return ""
        text = ""
        for cmd in (["vtool", "-show-build", str(binary)], ["otool", "-l", str(binary)]):
            try:
                result = subprocess.run(cmd, capture_output=True, text=True, check=False)
                text = (result.stdout or "") + "\n" + (result.stderr or "")
                match = re.search(r"\bminos\s+([0-9]+(?:\.[0-9]+){0,2})\b", text)
                if match:
                    value = match.group(1)
                    self.runtime_item_os_cache[cache_key] = value
                    return value
            except Exception:
                continue
        self.runtime_item_os_cache[cache_key] = ""
        return ""

    def _reload_runtime_items(self) -> None:
        self.runtime_item_os_cache.clear()
        for frame in self.runtime_item_frames.values():
            for widget in frame.winfo_children():
                widget.destroy()
        self.runtime_item_vars.clear()
        counters = {service: 0 for service in SERVICES}
        for rel in self._runtime_items():
            var = tk.BooleanVar(value=rel in self.saved_runtime_items)
            self.runtime_item_vars[rel] = var
            service = rel.split("/", 1)[0]
            frame = self.runtime_item_frames.get(service)
            if frame is None:
                continue
            os_version = self._item_built_os_version(service, rel)
            label = rel if not os_version else f"{rel}  (macOS {os_version})"
            ttk.Checkbutton(
                frame,
                text=label,
                variable=var,
                command=self._refresh_command_preview,
            ).grid(row=counters[service], column=0, sticky="w", padx=8, pady=2)
            counters[service] += 1
        self._refresh_command_preview()

    def _clear_runtime_items(self) -> None:
        for var in self.runtime_item_vars.values():
            var.set(False)
        self._refresh_command_preview()

    def _selected_runtime_items(self) -> list[str]:
        return [rel for rel, var in self.runtime_item_vars.items() if var.get()]

    def _build_app_command(self) -> list[str]:
        cmd = [str(APP_BUILD_SCRIPT_PATH)]
        runtime_root = self.runtime_root.get().strip()
        if runtime_root:
            cmd.extend(["--runtime-root", runtime_root])
        icon_path = self.icon_path.get().strip()
        if icon_path:
            cmd.extend(["--icon", icon_path])
        version = self.version.get().strip()
        if version:
            cmd.extend(["--version", version])
        app_sign_identity = self.app_sign_identity.get().strip() if self.enable_app_sign.get() else ""
        if app_sign_identity:
            cmd.extend(["--app-sign-identity", app_sign_identity])
        if app_sign_identity:
            cmd.extend(["--helper-sign-identity", app_sign_identity])
        if self.sparkle_enabled.get():
            sparkle_framework = self.sparkle_framework_path.get().strip()
            sparkle_feed_url = self.sparkle_feed_url.get().strip()
            sparkle_public_ed_key = self.sparkle_public_ed_key.get().strip()
            if sparkle_framework:
                cmd.extend(["--sparkle-framework", sparkle_framework])
            if sparkle_feed_url:
                cmd.extend(["--sparkle-feed-url", sparkle_feed_url])
            if sparkle_public_ed_key:
                cmd.extend(["--sparkle-public-ed-key", sparkle_public_ed_key])
        runtime_items = self._selected_runtime_items()
        if runtime_items:
            cmd.extend(["--runtime-items", ",".join(runtime_items)])
        else:
            services = ",".join(self._selected_services())
            cmd.extend(["--services", services])
        if self.bundle_app_runtime.get():
            cmd.append("--bundle-runtime")
        else:
            cmd.append("--no-bundle-runtime")
        if self.clean.get():
            cmd.append("--clean")
        else:
            cmd.append("--no-clean")
        return cmd

    def _build_pkg_command(self) -> list[str]:
        cmd = [str(PKG_BUILD_SCRIPT_PATH)]
        app_path = self._selected_app_bundle()
        cmd.extend(["--app", str(app_path), "--skip-app-build"])
        runtime_root = self.runtime_root.get().strip()
        if runtime_root:
            cmd.extend(["--runtime-root", runtime_root])
        version = self.version.get().strip()
        if version:
            cmd.extend(["--version", version])
        icon_path = self.icon_path.get().strip()
        if icon_path:
            cmd.extend(["--icon", icon_path])
        runtime_sign_identity = self.app_sign_identity.get().strip()
        if runtime_sign_identity:
            cmd.extend(["--runtime-sign-identity", runtime_sign_identity])
        runtime_items = self._selected_runtime_items()
        if runtime_items:
            cmd.extend(["--runtime-items", ",".join(runtime_items)])
        else:
            services = ",".join(self._selected_services())
            cmd.extend(["--services", services])
        if self.clean.get():
            cmd.append("--clean")
        else:
            cmd.append("--no-clean")
        return cmd

    def _build_dmg_command(self) -> list[str]:
        cmd = [str(DMG_BUILD_SCRIPT_PATH)]
        version = self.version.get().strip()
        if version:
            cmd.extend(["--version", version])
        if self.clean.get():
            cmd.append("--clean")
        else:
            cmd.append("--no-clean")
        return cmd

    def _app_bundle_path(self) -> Path:
        return REPO_ROOT / "dist" / "app" / "Server Engine.app"

    def _selected_app_bundle(self) -> Path:
        return Path(self.app_artifact_path.get().strip() or self._app_bundle_path())

    def _refresh_command_preview(self) -> None:
        if not hasattr(self, "command_preview"):
            return
        cmd = " ".join(shlex.quote(part) for part in self._build_app_command())
        self.command_preview.configure(state="normal")
        self.command_preview.delete("1.0", "end")
        self.command_preview.insert("1.0", cmd)
        self.command_preview.configure(state="disabled")

    def _save_state(self) -> None:
        payload = {
            "icon_path": self.icon_path.get().strip(),
            "runtime_root": self.runtime_root.get().strip(),
            "app_artifact_path": self.app_artifact_path.get().strip(),
            "version": self.version.get().strip(),
            "clean": bool(self.clean.get()),
            "bundle_app_runtime": bool(self.bundle_app_runtime.get()),
            "skip_app_build": bool(self.skip_app_build.get()),
            "services": self._selected_services(),
            "runtime_items": self._selected_runtime_items(),
            "pkg_select_mode": self.pkg_select_mode.get(),
            "pkg_select_version": self.pkg_select_version.get().strip(),
            "enable_sign": bool(self.enable_sign.get()),
            "enable_notarize": bool(self.enable_notarize.get()),
            "enable_app_sign": bool(self.enable_app_sign.get()),
            "app_sign_identity": self.app_sign_identity.get().strip(),
            "sign_identity": self.sign_identity.get().strip(),
            "notary_apple_id": self.notary_apple_id.get().strip(),
            "notary_team_id": self.notary_team_id.get().strip(),
            "notary_password": self.notary_password.get(),
            "notary_submission_id": self.notary_submission_id.get().strip(),
            "app_notary_submission_id": self.app_notary_submission_id.get().strip(),
            "dmg_notary_submission_id": self.dmg_notary_submission_id.get().strip(),
            "sparkle_enabled": bool(self.sparkle_enabled.get()),
            "sparkle_framework_path": self.sparkle_framework_path.get().strip(),
            "sparkle_feed_url": self.sparkle_feed_url.get().strip(),
            "sparkle_public_ed_key": self.sparkle_public_ed_key.get().strip(),
            "sparkle_tools_dir": self.sparkle_tools_dir.get().strip(),
            "sparkle_private_key_file": self.sparkle_private_key_file.get().strip(),
            "sparkle_key_account": self.sparkle_key_account.get().strip(),
            "sparkle_release_channel": self.sparkle_release_channel.get().strip(),
            "sparkle_arch_override": self.sparkle_arch_override.get().strip(),
            "sparkle_metadata_json_path": self.sparkle_metadata_json_path.get().strip(),
            "upload_site_url": self.upload_site_url.get().strip(),
            "upload_email": self.upload_email.get().strip(),
            "upload_password": self.upload_password.get(),
            "upload_access_token": self.upload_access_token,
            "upload_version": self.upload_version.get().strip(),
            "upload_build": self.upload_build.get().strip(),
            "upload_min_system_version": self.upload_min_system_version.get().strip(),
            "upload_os": self.upload_os.get().strip(),
            "upload_arch": self.upload_arch.get().strip(),
            "upload_sparkle_ed_signature": self.upload_sparkle_ed_signature.get().strip(),
            "upload_release_notes_url": self.upload_release_notes_url.get().strip(),
            "upload_critical_update": bool(self.upload_critical_update.get()),
            "upload_phased_rollout_interval": self.upload_phased_rollout_interval.get().strip(),
            "upload_staging_percentage": self.upload_staging_percentage.get().strip(),
            "release_dmg_select_mode": self.release_dmg_select_mode.get(),
            "release_dmg_select_version": self.release_dmg_select_version.get().strip(),
            "release_dmg_path": self.release_dmg_path.get().strip(),
        }
        save_config(payload)
        self._append_output("Saved GUI state.\n")

    def _on_close(self) -> None:
        try:
            self._save_state()
        finally:
            self.destroy()

    def _append_output(self, text: str) -> None:
        if not hasattr(self, "output"):
            return
        if not text:
            return
        self._log_buffer.append(text)
        if not self._log_flush_scheduled:
            self._log_flush_scheduled = True
            self.after(40, self._flush_output)

    def _flush_output(self) -> None:
        self._log_flush_scheduled = False
        if not hasattr(self, "output") or not self._log_buffer:
            return
        text = "".join(self._log_buffer)
        self._log_buffer.clear()
        self.output.insert("end", text)
        self.output.see("end")
        line_count = int(float(self.output.index("end-1c").split(".")[0]))
        if line_count > 8000:
            self.output.delete("1.0", f"{line_count - 6000}.0")

    def _stream_process_output(self, process: subprocess.Popen[str], suppress_noisy: bool = False) -> None:
        assert process.stdout is not None
        suppressed = 0
        for line in iter(process.stdout.readline, ""):
            if suppress_noisy and line.startswith(self.NOISY_LOG_PREFIXES):
                suppressed += 1
                continue
            self.after(0, self._append_output, line)
        if suppressed:
            self.after(0, self._append_output, f"[filtered {suppressed} noisy lines]\n")

    def _set_running(self, value: bool) -> None:
        self.running = value
        self.build_app_button.configure(state="disabled" if value else "normal")
        if hasattr(self, "build_pkg_button"):
            self.build_pkg_button.configure(state="disabled" if value else "normal")
        if hasattr(self, "build_dmg_button"):
            self.build_dmg_button.configure(state="disabled" if value else "normal")
        self.cancel_button.configure(state="normal" if value else "disabled")
        if value:
            if hasattr(self, "reveal_dmg_button"):
                self.reveal_dmg_button.configure(state="disabled")
                self.run_dmg_button.configure(state="disabled")
                self.verify_app_button.configure(state="disabled")
                self.verify_app_runtime_button.configure(state="disabled")
                self.sign_app_runtime_button.configure(state="disabled")
                self.sign_app_button.configure(state="disabled")
                self.sign_notarize_app_button.configure(state="disabled")
                self.staple_app_button.configure(state="disabled")
                self.notary_status_app_button.configure(state="disabled")
                self.verify_dmg_button.configure(state="disabled")
                self.sign_dmg_button.configure(state="disabled")
                self.sign_notarize_dmg_button.configure(state="disabled")
                self.notary_status_dmg_button.configure(state="disabled")
                self.staple_dmg_button.configure(state="disabled")
            if hasattr(self, "sparkle_check_sign_button"):
                self.sparkle_check_sign_button.configure(state="disabled")
                self.sparkle_sign_button.configure(state="disabled")
            self.verify_button.configure(state="disabled")
            self.sign_selected_button.configure(state="disabled")
            self.sign_notarize_selected_button.configure(state="disabled")
            self.notary_status_button.configure(state="disabled")
            self.staple_button.configure(state="disabled")
        else:
            self._refresh_sign_actions_enabled()
            if hasattr(self, "build_dmg_button"):
                self._refresh_dmg_actions_enabled()
                self._refresh_app_actions_enabled()

    def _set_sign_running(self, value: bool) -> None:
        self.cancel_sign_button.configure(state="normal" if value else "disabled")
        if value:
            if hasattr(self, "build_pkg_button"):
                self.build_pkg_button.configure(state="disabled")
            self.verify_button.configure(state="disabled")
            self.sign_selected_button.configure(state="disabled")
            self.sign_notarize_selected_button.configure(state="disabled")
            self.notary_status_button.configure(state="disabled")
            self.staple_button.configure(state="disabled")
            if hasattr(self, "verify_dmg_button"):
                self.verify_app_button.configure(state="disabled")
                self.verify_app_runtime_button.configure(state="disabled")
                self.sign_app_runtime_button.configure(state="disabled")
                self.sign_app_button.configure(state="disabled")
                self.sign_notarize_app_button.configure(state="disabled")
                self.staple_app_button.configure(state="disabled")
                self.notary_status_app_button.configure(state="disabled")
                self.verify_dmg_button.configure(state="disabled")
                self.sign_dmg_button.configure(state="disabled")
                self.sign_notarize_dmg_button.configure(state="disabled")
                self.notary_status_dmg_button.configure(state="disabled")
                self.staple_dmg_button.configure(state="disabled")
            if hasattr(self, "sparkle_check_sign_button"):
                self.sparkle_check_sign_button.configure(state="disabled")
                self.sparkle_sign_button.configure(state="disabled")
            return
        if hasattr(self, "build_pkg_button"):
            self.build_pkg_button.configure(state="normal" if not self.running else "disabled")
        self._refresh_sign_actions_enabled()
        if hasattr(self, "verify_dmg_button"):
            self._refresh_dmg_actions_enabled()
            self._refresh_app_actions_enabled()

    def _cancel_build(self) -> None:
        process = self.build_process
        if process is None:
            return
        try:
            if os.name == "posix":
                os.killpg(process.pid, signal.SIGTERM)
            else:
                process.terminate()
            self._append_output("\nBuild cancellation requested...\n")
        except Exception as exc:
            self._append_output(f"\nCancel failed: {exc}\n")

    def _cancel_sign(self) -> None:
        process = self.sign_process
        if process is None:
            return
        try:
            if os.name == "posix":
                os.killpg(process.pid, signal.SIGTERM)
            else:
                process.terminate()
            self._append_output("\nSign cancellation requested...\n")
        except Exception as exc:
            self._append_output(f"\nCancel sign failed: {exc}\n")

    def _set_dmg_actions_enabled(self, enabled: bool) -> None:
        if not hasattr(self, "reveal_dmg_button"):
            return
        state = "normal" if enabled else "disabled"
        self.reveal_dmg_button.configure(state=state)
        self.run_dmg_button.configure(state=state)

    def _find_latest_pkg(self) -> Path | None:
        pkg_dir = REPO_ROOT / "dist" / "pkg"
        if not pkg_dir.is_dir():
            return None
        pkgs = sorted(pkg_dir.glob("*.pkg"), key=lambda p: p.stat().st_mtime)
        return pkgs[-1] if pkgs else None

    def _run_build_pkg(self) -> None:
        if self.running:
            return
        if not PKG_BUILD_SCRIPT_PATH.exists():
            messagebox.showerror("Build PKG", f"Script not found: {PKG_BUILD_SCRIPT_PATH}")
            return
        app_bundle = self._selected_app_bundle()
        if not app_bundle.exists():
            messagebox.showerror("Build PKG", f"App bundle not found: {app_bundle}\n\nBuild or choose the .app first.")
            return
        runtime_root = Path(self.runtime_root.get().strip() or DEFAULT_RUNTIME_ROOT)
        if not runtime_root.exists():
            messagebox.showerror("Build PKG", f"Runtime root not found: {runtime_root}")
            return
        runtime_sign_identity = self.app_sign_identity.get().strip()
        if not runtime_sign_identity:
            messagebox.showerror(
                "Build PKG",
                "Select a Developer ID Application certificate in App/runtime sign certificate.\n\n"
                "The PKG build signs the staged runtime and privileged helper before packaging. "
                "It does not sign the .app.",
            )
            return
        self._save_state()
        cmd = self._build_pkg_command()
        self._append_output(f"\n$ {' '.join(shlex.quote(part) for part in cmd)}\n")
        self._set_running(True)

        def worker() -> None:
            try:
                env = os.environ.copy()
                env["PYTHONUNBUFFERED"] = "1"
                process = subprocess.Popen(
                    cmd,
                    cwd=str(REPO_ROOT),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    bufsize=1,
                    env=env,
                    preexec_fn=os.setsid if os.name == "posix" else None,
                )
                self.build_process = process
                self._stream_process_output(process)
                code = process.wait()
                if code == 0:
                    latest_pkg = self._find_latest_pkg()
                    self.last_pkg_path = latest_pkg
                    self.after(0, self._reload_pkg_versions)
                    if latest_pkg is not None:
                        self.after(0, self._append_output, f"\nPKG build finished successfully.\nPKG: {latest_pkg}\n")
                    else:
                        self.after(0, self._append_output, "\nPKG build finished successfully.\n")
                    self.after(0, self._refresh_sign_actions_enabled)
                else:
                    self.after(0, self._append_output, f"\nPKG build failed with exit code {code}.\n")
                    self.after(0, self._refresh_sign_actions_enabled)
            except Exception as exc:
                self.after(0, self._append_output, f"\nPKG build error: {exc}\n")
                self.after(0, self._refresh_sign_actions_enabled)
            finally:
                self.build_process = None
                self.after(0, self._set_running, False)

        threading.Thread(target=worker, daemon=True).start()

    def _reveal_dmg(self) -> None:
        dmg = self._resolved_dmg_for_sign()
        if dmg is None or not dmg.exists():
            messagebox.showwarning("Build DMG", "No built DMG found yet.")
            return
        try:
            subprocess.run(["open", "-R", str(dmg)], check=False)
        except Exception as exc:
            messagebox.showerror("Build DMG", f"Cannot reveal DMG: {exc}")

    def _run_dmg(self) -> None:
        dmg = self._resolved_dmg_for_sign()
        if dmg is None or not dmg.exists():
            messagebox.showwarning("Build DMG", "No built DMG found yet.")
            return
        try:
            subprocess.run(["open", str(dmg)], check=False)
        except Exception as exc:
            messagebox.showerror("Build DMG", f"Cannot open DMG: {exc}")

    def _run_build_dmg(self) -> None:
        if self.running:
            return
        if not DMG_BUILD_SCRIPT_PATH.exists():
            messagebox.showerror("Build DMG", f"Script not found: {DMG_BUILD_SCRIPT_PATH}")
            return
        app_bundle = self._app_bundle_path()
        if not app_bundle.exists():
            messagebox.showerror("Build DMG", f"App bundle not found: {app_bundle}\n\nBuild App first.")
            return
        self._save_state()
        cmd = self._build_dmg_command()
        self._append_output(f"\n$ {' '.join(shlex.quote(part) for part in cmd)}\n")
        self._set_running(True)

        def worker() -> None:
            try:
                env = os.environ.copy()
                env["PYTHONUNBUFFERED"] = "1"
                process = subprocess.Popen(
                    cmd,
                    cwd=str(REPO_ROOT),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    bufsize=1,
                    env=env,
                    preexec_fn=os.setsid if os.name == "posix" else None,
                )
                self.build_process = process
                self._stream_process_output(process, suppress_noisy=True)
                code = process.wait()
                if code == 0:
                    latest_dmg = self._find_latest_dmg()
                    self.last_dmg_path = latest_dmg
                    if latest_dmg is not None and not self.sparkle_metadata_json_path.get().strip():
                        self.after(0, self.sparkle_metadata_json_path.set, str(latest_dmg) + ".sparkle.json")
                    self.after(0, self._reload_dmg_versions)
                    if latest_dmg is not None:
                        self.after(0, self._append_output, f"\nDMG build finished successfully.\nDMG: {latest_dmg}\n")
                    else:
                        self.after(0, self._append_output, "\nDMG build finished successfully.\n")
                    self.after(0, self._refresh_dmg_actions_enabled)
                else:
                    self.after(0, self._append_output, f"\nDMG build failed with exit code {code}.\n")
                    self.after(0, self._refresh_dmg_actions_enabled)
            except Exception as exc:
                self.after(0, self._append_output, f"\nDMG build error: {exc}\n")
                self.after(0, self._refresh_dmg_actions_enabled)
            finally:
                self.build_process = None
                self.after(0, self._set_running, False)

        threading.Thread(target=worker, daemon=True).start()

    def _pkg_versions(self) -> list[str]:
        pkg_dir = REPO_ROOT / "dist" / "pkg"
        if not pkg_dir.is_dir():
            return []
        names = sorted((p.name for p in pkg_dir.glob("*.pkg")), reverse=True)
        return names

    def _dmg_versions(self) -> list[str]:
        dmg_dir = REPO_ROOT / "dist" / "dmg"
        if not dmg_dir.is_dir():
            return []
        names = sorted((p.name for p in dmg_dir.glob("*.dmg")), reverse=True)
        return names

    def _reload_pkg_versions(self) -> None:
        versions = self._pkg_versions()
        self.pkg_version_combo.configure(values=versions)
        if versions and self.pkg_select_version.get() not in versions:
            self.pkg_select_version.set(versions[0])
        self._refresh_sign_actions_enabled()

    def _reload_dmg_versions(self) -> None:
        if not hasattr(self, "dmg_version_combo"):
            return
        versions = self._dmg_versions()
        self.dmg_version_combo.configure(values=versions)
        if versions and self.dmg_select_version.get() not in versions:
            self.dmg_select_version.set(versions[0])
        self._refresh_dmg_actions_enabled()

    def _find_latest_dmg(self) -> Path | None:
        dmg_dir = REPO_ROOT / "dist" / "dmg"
        if not dmg_dir.is_dir():
            return None
        dmgs = sorted(dmg_dir.glob("*.dmg"), key=lambda p: p.stat().st_mtime)
        return dmgs[-1] if dmgs else None

    def _resolved_dmg_for_sign(self) -> Path | None:
        if hasattr(self, "dmg_select_mode") and self.dmg_select_mode.get() == "by_version":
            version_name = self.dmg_select_version.get().strip()
            if version_name:
                candidate = REPO_ROOT / "dist" / "dmg" / version_name
                if candidate.exists():
                    return candidate
        return self.last_dmg_path if self.last_dmg_path and self.last_dmg_path.exists() else self._find_latest_dmg()

    def _refresh_dmg_actions_enabled(self) -> None:
        if not hasattr(self, "verify_dmg_button"):
            return
        if self.running or self.sign_process is not None:
            self.verify_dmg_button.configure(state="disabled")
            self.sign_dmg_button.configure(state="disabled")
            self.sign_notarize_dmg_button.configure(state="disabled")
            self.notary_status_dmg_button.configure(state="disabled")
            self.staple_dmg_button.configure(state="disabled")
            self._set_dmg_actions_enabled(False)
            return
        has_dmg = self._resolved_dmg_for_sign() is not None
        self._set_dmg_actions_enabled(has_dmg)
        state = "normal" if has_dmg else "disabled"
        self.verify_dmg_button.configure(state=state)
        self.sign_dmg_button.configure(state=state)
        self.sign_notarize_dmg_button.configure(state=state)
        self.notary_status_dmg_button.configure(state=state)
        self.staple_dmg_button.configure(state=state)

    def _refresh_app_actions_enabled(self) -> None:
        if not hasattr(self, "verify_app_button"):
            return
        if self.running or self.sign_process is not None:
            state = "disabled"
        else:
            state = "normal" if self._selected_app_bundle().exists() else "disabled"
        self.verify_app_button.configure(state=state)
        self.verify_app_runtime_button.configure(state=state)
        self.sign_app_runtime_button.configure(state=state)
        self.sign_app_button.configure(state=state)
        self.sign_notarize_app_button.configure(state=state)
        self.staple_app_button.configure(state=state)
        self.notary_status_app_button.configure(state=state)
        if hasattr(self, "sparkle_check_sign_button"):
            framework_state = "disabled"
            if state == "normal" and self._sparkle_framework_in_selected_app().exists():
                framework_state = "normal"
            self.sparkle_check_sign_button.configure(state=framework_state)
            self.sparkle_sign_button.configure(state=framework_state)

    def _refresh_sign_actions_enabled(self) -> None:
        if self.running or self.sign_process is not None:
            self.verify_button.configure(state="disabled")
            self.sign_selected_button.configure(state="disabled")
            self.sign_notarize_selected_button.configure(state="disabled")
            self.notary_status_button.configure(state="disabled")
            self.staple_button.configure(state="disabled")
            return
        has_pkg = self._resolved_pkg_for_sign() is not None
        state = "normal" if has_pkg else "disabled"
        self.verify_button.configure(state=state)
        self.sign_selected_button.configure(state=state)
        self.sign_notarize_selected_button.configure(state=state)
        self.notary_status_button.configure(state=state)
        self.staple_button.configure(state=state)

    def _reload_sign_identities(self) -> None:
        self.identity_map.clear()
        labels: list[str] = []
        saved_identity = self.sign_identity.get().strip()
        cmd = ["security", "find-identity", "-v", "-p", "basic"]
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, check=False)
            output = (result.stdout or "") + "\n" + (result.stderr or "")
            for line in output.splitlines():
                match = re.search(r'^\s*\d+\)\s+([0-9A-F]{40})\s+"([^"]+)"', line)
                if not match:
                    continue
                sha = match.group(1)
                name = match.group(2).strip()
                if "Developer ID Installer:" not in name and "3rd Party Mac Developer Installer:" not in name:
                    continue
                label = f"{name} [{sha[:8]}]"
                self.identity_map[label] = sha
                labels.append(label)
            options = [self.IDENTITY_PLACEHOLDER, *labels]
            self.identity_combo.configure(values=options)
            selected_label = next(
                (label for label in labels if label.rsplit(" [", 1)[0].strip() == saved_identity),
                "",
            )
            if selected_label:
                self.identity_combo.set(selected_label)
                self.sign_identity.set(saved_identity)
            else:
                self.identity_combo.set(self.IDENTITY_PLACEHOLDER)
                self.sign_identity.set("")
            self._append_output(f"Loaded {len(labels)} installer signing identities.\n")
        except Exception as exc:
            self.identity_combo.configure(values=[self.IDENTITY_PLACEHOLDER])
            self.identity_combo.set(self.IDENTITY_PLACEHOLDER)
            self.sign_identity.set("")
            self._append_output(f"Load identities failed: {exc}\n")

    def _reload_app_sign_identities(self) -> None:
        self.app_identity_map.clear()
        labels: list[str] = []
        saved_identity = self.app_sign_identity.get().strip()
        cmd = ["security", "find-identity", "-v", "-p", "basic"]
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, check=False)
            output = (result.stdout or "") + "\n" + (result.stderr or "")
            for line in output.splitlines():
                match = re.search(r'^\s*\d+\)\s+([0-9A-F]{40})\s+"([^"]+)"', line)
                if not match:
                    continue
                sha = match.group(1)
                name = match.group(2).strip()
                if "Developer ID Application:" not in name:
                    continue
                label = f"{name} [{sha[:8]}]"
                self.app_identity_map[label] = sha
                labels.append(label)
            options = [self.IDENTITY_PLACEHOLDER, *labels]
            self.app_identity_combo.configure(values=options)
            if hasattr(self, "sparkle_identity_combo"):
                self.sparkle_identity_combo.configure(values=options)
            selected_label = next(
                (label for label in labels if label.rsplit(" [", 1)[0].strip() == saved_identity),
                "",
            )
            if selected_label:
                self.app_identity_combo.set(selected_label)
                if hasattr(self, "sparkle_identity_combo"):
                    self.sparkle_identity_combo.set(selected_label)
                self.app_sign_identity.set(saved_identity)
            else:
                self.app_identity_combo.set(self.IDENTITY_PLACEHOLDER)
                if hasattr(self, "sparkle_identity_combo"):
                    self.sparkle_identity_combo.set(self.IDENTITY_PLACEHOLDER)
                self.app_sign_identity.set("")
            self._append_output(f"Loaded {len(labels)} app signing identities.\n")
        except Exception as exc:
            self.app_identity_combo.configure(values=[self.IDENTITY_PLACEHOLDER])
            self.app_identity_combo.set(self.IDENTITY_PLACEHOLDER)
            if hasattr(self, "sparkle_identity_combo"):
                self.sparkle_identity_combo.configure(values=[self.IDENTITY_PLACEHOLDER])
                self.sparkle_identity_combo.set(self.IDENTITY_PLACEHOLDER)
            self.app_sign_identity.set("")
            self._append_output(f"Load app identities failed: {exc}\n")

    def _on_app_identity_selected(self, _event: tk.Event | None = None) -> None:
        label = self.app_identity_combo.get().strip()
        if not label or label == self.IDENTITY_PLACEHOLDER:
            self.app_sign_identity.set("")
            self._save_state()
            return
        name = label.rsplit(" [", 1)[0].strip()
        self.app_sign_identity.set(name)
        self._save_state()
        self._append_output(f"Selected app sign identity: {name}\n")

    def _on_sparkle_identity_selected(self, _event: tk.Event | None = None) -> None:
        label = self.sparkle_identity_combo.get().strip()
        if not label or label == self.IDENTITY_PLACEHOLDER:
            self.app_sign_identity.set("")
            self._save_state()
            return
        name = label.rsplit(" [", 1)[0].strip()
        self.app_sign_identity.set(name)
        if hasattr(self, "app_identity_combo"):
            self.app_identity_combo.set(label)
        self._save_state()
        self._append_output(f"Selected app sign identity: {name}\n")

    def _toggle_app_sign_controls(self) -> None:
        show = bool(self.enable_app_sign.get())
        if show:
            self.app_sign_label.grid()
            self.app_identity_combo.grid()
            self.app_identity_reload_button.grid()
        else:
            self.app_sign_label.grid_remove()
            self.app_identity_combo.grid_remove()
            self.app_identity_reload_button.grid_remove()
        self._refresh_command_preview()

    def _on_identity_selected(self, _event: tk.Event | None = None) -> None:
        label = self.identity_combo.get().strip()
        if not label or label == self.IDENTITY_PLACEHOLDER:
            self.sign_identity.set("")
            self._save_state()
            return
        name = label.rsplit(" [", 1)[0].strip()
        self.sign_identity.set(name)
        self._save_state()
        self._append_output(f"Selected sign identity: {name}\n")

    def _remove_selected_identity(self) -> None:
        label = self.identity_combo.get().strip()
        if not label or label == self.IDENTITY_PLACEHOLDER:
            messagebox.showwarning("Remove identity", "Select a certificate first.")
            return
        sha = self.identity_map.get(label)
        if not sha:
            messagebox.showwarning("Remove identity", "Cannot resolve selected identity SHA-1.")
            return
        name = label.rsplit(" [", 1)[0].strip()
        ok = messagebox.askyesno(
            "Remove identity",
            f"Remove this certificate from your keychain?\n\n{name}\n{sha}",
        )
        if not ok:
            return
        cmd = ["security", "delete-certificate", "-Z", sha]
        self._run_sign_commands([cmd])
        self.after(700, self._reload_sign_identities)

    def _resolved_pkg_for_sign(self) -> Path | None:
        if self.pkg_select_mode.get() == "by_version":
            version_name = self.pkg_select_version.get().strip()
            if version_name:
                candidate = REPO_ROOT / "dist" / "pkg" / version_name
                if candidate.exists():
                    return candidate
        return self.last_pkg_path if self.last_pkg_path and self.last_pkg_path.exists() else self._find_latest_pkg()

    def _signed_temp_pkg(self, pkg: Path) -> Path:
        return pkg.with_name(f"{pkg.stem}.signed-{uuid.uuid4().hex}.pkg")

    def _pkg_has_signature(self, pkg: Path) -> bool:
        try:
            result = subprocess.run(
                ["pkgutil", "--check-signature", str(pkg)],
                capture_output=True,
                text=True,
                check=False,
            )
            text = ((result.stdout or "") + "\n" + (result.stderr or "")).lower()
            return "status: signed" in text
        except Exception:
            return False

    def _confirm_resign_if_needed(self, pkg: Path) -> bool:
        if not self._pkg_has_signature(pkg):
            return True
        return messagebox.askyesno(
            "Already Signed",
            f"This package already appears signed:\n\n{pkg.name}\n\nRe-sign and replace it?",
        )

    def _check_pkg_security(self) -> None:
        pkg = self._resolved_pkg_for_sign()
        if pkg is None:
            messagebox.showwarning("Verify", "No package found to verify.")
            return
        self._run_sign_commands(
            [
                ["pkgutil", "--check-signature", str(pkg)],
                ["spctl", "-a", "-vvv", "-t", "install", str(pkg)],
            ]
        )

    def _sign_selected_pkg(self) -> None:
        pkg = self._resolved_pkg_for_sign()
        if pkg is None:
            messagebox.showwarning("Sign", "No package found to sign.")
            return
        if not self._confirm_resign_if_needed(pkg):
            return
        identity = self.sign_identity.get().strip()
        if not identity:
            messagebox.showwarning("Sign", "Sign identity is required.")
            return
        signed_pkg = self._signed_temp_pkg(pkg)
        self._run_sign_commands(
            [
                ["productsign", "--sign", identity, str(pkg), str(signed_pkg)],
                ["mv", "-f", str(signed_pkg), str(pkg)],
            ]
        )
        self.last_pkg_path = pkg
        self._reload_pkg_versions()

    def _sign_notarize_selected_pkg(self) -> None:
        pkg = self._resolved_pkg_for_sign()
        if pkg is None:
            messagebox.showwarning("Sign", "No package found to sign/notarize.")
            return
        if not self._confirm_resign_if_needed(pkg):
            return
        identity = self.sign_identity.get().strip()
        apple_id = self.notary_apple_id.get().strip()
        team_id = self.notary_team_id.get().strip()
        password = self.notary_password.get().strip()
        if not identity:
            messagebox.showwarning("Sign", "Sign identity is required.")
            return
        if not apple_id or not team_id or not password:
            messagebox.showwarning("Notarize", "Apple ID, Team ID, and App Password are required.")
            return
        signed_pkg = self._signed_temp_pkg(pkg)
        self.last_pkg_path = pkg
        self._submit_notary_after_sign(pkg, signed_pkg, identity, apple_id, team_id, password)
        self._reload_pkg_versions()

    def _submit_notary_after_sign(self, pkg: Path, signed_pkg: Path, identity: str, apple_id: str, team_id: str, password: str) -> None:
        if self.sign_process is not None:
            return
        self._save_state()
        self._set_sign_running(True)

        def worker() -> None:
            try:
                sign_cmds = [
                    ["productsign", "--sign", identity, str(pkg), str(signed_pkg)],
                    ["mv", "-f", str(signed_pkg), str(pkg)],
                ]
                for cmd in sign_cmds:
                    self.after(0, self._append_output, f"\n$ {' '.join(shlex.quote(part) for part in cmd)}\n")
                    process = subprocess.Popen(
                        cmd,
                        cwd=str(REPO_ROOT),
                        stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT,
                        text=True,
                        bufsize=1,
                        preexec_fn=os.setsid if os.name == "posix" else None,
                    )
                    self.sign_process = process
                    self._stream_process_output(process)
                    code = process.wait()
                    if code != 0:
                        self.after(0, self._append_output, f"\nCommand failed with exit code {code}.\n")
                        return

                submit_cmd = [
                    "xcrun", "notarytool", "submit", str(pkg),
                    "--apple-id", apple_id,
                    "--team-id", team_id,
                    "--password", password,
                    "--output-format", "json",
                ]
                self.after(0, self._append_output, f"\n$ {' '.join(shlex.quote(part) for part in submit_cmd)}\n")
                result = subprocess.run(submit_cmd, cwd=str(REPO_ROOT), capture_output=True, text=True, check=False)
                output = (result.stdout or "").strip()
                errors = (result.stderr or "").strip()
                if output:
                    self.after(0, self._append_output, output + "\n")
                if errors:
                    self.after(0, self._append_output, errors + "\n")
                if result.returncode != 0:
                    self.after(0, self._append_output, f"\nNotary submit failed with exit code {result.returncode}.\n")
                    return

                submission_id = ""
                try:
                    payload = json.loads(output or "{}")
                    submission_id = str(payload.get("id") or "").strip()
                except Exception:
                    submission_id = ""
                if submission_id:
                    self.after(0, self.notary_submission_id.set, submission_id)
                    self.after(0, self._save_state)
                    self.after(0, self._append_output, f"Saved Notary Submission ID: {submission_id}\n")
                self.after(0, self._append_output, "\nNotary submitted. Use 'Check Notary Status'. Staple only after status is Accepted.\n")
            except Exception as exc:
                self.after(0, self._append_output, f"\nSign/notary error: {exc}\n")
            finally:
                self.sign_process = None
                self.after(0, self._set_sign_running, False)

        threading.Thread(target=worker, daemon=True).start()

    def _check_notary_status(self) -> None:
        submission_id = self.notary_submission_id.get().strip()
        apple_id = self.notary_apple_id.get().strip()
        team_id = self.notary_team_id.get().strip()
        password = self.notary_password.get().strip()
        if not submission_id:
            messagebox.showwarning("Notary", "Notary Submission ID is required.")
            return
        if not apple_id or not team_id or not password:
            messagebox.showwarning("Notary", "Apple ID, Team ID, and App Password are required.")
            return
        self._run_sign_commands(
            [[
                "xcrun", "notarytool", "info", submission_id,
                "--apple-id", apple_id,
                "--team-id", team_id,
                "--password", password,
            ]]
        )

    def _check_app_notary_status(self) -> None:
        submission_id = self.app_notary_submission_id.get().strip()
        apple_id = self.notary_apple_id.get().strip()
        team_id = self.notary_team_id.get().strip()
        password = self.notary_password.get().strip()
        if not submission_id:
            messagebox.showwarning("Notary", "App Notary Submission ID is required.")
            return
        if not apple_id or not team_id or not password:
            messagebox.showwarning("Notary", "Apple ID, Team ID, and App Password are required.")
            return
        self._run_sign_commands(
            [[
                "xcrun", "notarytool", "info", submission_id,
                "--apple-id", apple_id,
                "--team-id", team_id,
                "--password", password,
            ]]
        )

    def _check_dmg_notary_status(self) -> None:
        submission_id = self.dmg_notary_submission_id.get().strip()
        apple_id = self.notary_apple_id.get().strip()
        team_id = self.notary_team_id.get().strip()
        password = self.notary_password.get().strip()
        if not submission_id:
            messagebox.showwarning("Notary", "DMG Notary Submission ID is required.")
            return
        if not apple_id or not team_id or not password:
            messagebox.showwarning("Notary", "Apple ID, Team ID, and App Password are required.")
            return
        self._run_sign_commands(
            [[
                "xcrun", "notarytool", "info", submission_id,
                "--apple-id", apple_id,
                "--team-id", team_id,
                "--password", password,
            ]]
        )

    def _staple_selected_pkg(self) -> None:
        pkg = self._resolved_pkg_for_sign()
        if pkg is None:
            messagebox.showwarning("Staple", "No package found to staple.")
            return
        self._run_sign_commands([["xcrun", "stapler", "staple", str(pkg)]])

    def _check_app_security(self) -> None:
        app = self._selected_app_bundle()
        if not app.exists():
            messagebox.showwarning("Verify", "App bundle not found.")
            return
        self._run_sign_commands(
            [
                [
                    "sh",
                    "-lc",
                    "/usr/bin/codesign -dv --verbose=4 "
                    + shlex.quote(str(app))
                    + " 2>&1 | grep -E \"Authority=|TeamIdentifier=|Identifier=|Format=|Executable=|Timestamp=\" || true",
                ]
            ]
        )

    def _check_app_runtime_signatures(self) -> None:
        app = self._selected_app_bundle()
        if not app.exists():
            messagebox.showwarning("Verify", "App bundle not found.")
            return
        runtime_root = app / "Contents" / "Resources" / "runtime"
        if not runtime_root.exists():
            messagebox.showwarning("Verify", f"Runtime folder not found:\n{runtime_root}")
            return
        cmd = [
            "sh",
            "-lc",
            "set -eu; "
            f"find {shlex.quote(str(runtime_root))} -type f | "
            "while IFS= read -r f; do "
            "if /usr/bin/file -b \"$f\" | grep -q \"Mach-O\"; then "
            "echo \"\"; "
            "echo \"[mach-o] $f\"; "
            "/usr/bin/codesign -dv --verbose=4 \"$f\" 2>&1 | grep -E \"Authority|TeamIdentifier|Signature|Timestamp|Runtime|Identifier\" || true; "
            "fi; "
            "done",
        ]
        self._run_sign_commands([cmd])

    def _sign_app_runtime(self) -> None:
        app = self._selected_app_bundle()
        if not app.exists():
            messagebox.showwarning("Sign", "App bundle not found.")
            return
        identity = self.app_sign_identity.get().strip()
        if not identity:
            messagebox.showwarning("Sign", "App sign identity is required.")
            return
        runtime_root = app / "Contents" / "Resources" / "runtime"
        if not runtime_root.exists():
            messagebox.showwarning("Sign", f"Runtime folder not found:\n{runtime_root}")
            return
        helper_path = runtime_root / "server-engine-privileged-helper"
        helper_sign_cmd = (
            f"/usr/bin/codesign --force --timestamp --options runtime --sign {shlex.quote(identity)} {shlex.quote(str(helper_path))}"
            if helper_path.exists()
            else "true"
        )
        cmd = [
            "sh",
            "-lc",
            "set -eu; "
            f"runtime_root={shlex.quote(str(runtime_root))}; "
            f"helper_path={shlex.quote(str(helper_path))}; "
            f"identity={shlex.quote(identity)}; "
            f"{helper_sign_cmd}; "
            "find \"$runtime_root\" -type f | while IFS= read -r f; do "
            "[ \"$f\" = \"$helper_path\" ] && continue; "
            "if /usr/bin/file -b \"$f\" | grep -q 'Mach-O'; then "
            "echo \"[mach-o] $f\"; "
            "/usr/bin/codesign --force --timestamp --options runtime --sign \"$identity\" \"$f\"; "
            "fi; "
            "done",
        ]
        self._run_sign_commands([cmd])

    def _sign_selected_app(self) -> None:
        app = self._selected_app_bundle()
        if not app.exists():
            messagebox.showwarning("Sign", "App bundle not found.")
            return
        identity = self.app_sign_identity.get().strip()
        if not identity:
            messagebox.showwarning("Sign", "App sign identity is required.")
            return
        cmd = [
            "sh",
            "-lc",
            "set -eu; "
            f"app={shlex.quote(str(app))}; "
            f"identity={shlex.quote(identity)}; "
            "contents_root=\"$app/Contents\"; "
            "frameworks_root=\"$app/Contents/Frameworks\"; "
            "helper_in_app=\"$app/Contents/Library/LaunchServices/com.serverengine.app.helper\"; "
            "if [ -f \"$helper_in_app\" ]; then "
            "  /usr/bin/codesign --force --timestamp --options runtime --sign \"$identity\" \"$helper_in_app\"; "
            "fi; "
            "if [ -d \"$contents_root\" ]; then "
            "  find \"$contents_root\" -type f | while IFS= read -r f; do "
            "    if /usr/bin/file -b \"$f\" 2>/dev/null | grep -q 'Mach-O'; then "
            "      /usr/bin/codesign --force --timestamp --options runtime --sign \"$identity\" \"$f\"; "
            "    fi; "
            "  done; "
            "fi; "
            "if [ -d \"$frameworks_root\" ]; then "
            "  find \"$frameworks_root\" -maxdepth 2 -type d -name '*.framework' | while IFS= read -r d; do "
            "    /usr/bin/codesign --force --timestamp --options runtime --sign \"$identity\" \"$d\"; "
            "  done; "
            "fi; "
            "/usr/bin/codesign --force --timestamp --options runtime --sign \"$identity\" \"$app\"; "
            "/usr/bin/codesign --verify --deep --strict --verbose=4 \"$app\"; "
            "/usr/bin/codesign -dv --verbose=4 \"$app\" 2>&1 | grep -E \"Authority=|TeamIdentifier=|Identifier=|Format=|Executable=|Timestamp=\" || true",
        ]
        self._run_sign_commands([cmd])

    def _notarize_selected_app(self) -> None:
        app = self._selected_app_bundle()
        if not app.exists():
            messagebox.showwarning("Notarize", "App bundle not found.")
            return
        apple_id = self.notary_apple_id.get().strip()
        team_id = self.notary_team_id.get().strip()
        password = self.notary_password.get().strip()
        if not apple_id or not team_id or not password:
            messagebox.showwarning("Notarize", "Apple ID, Team ID, and App Password are required.")
            return
        zip_path = REPO_ROOT / ".build" / "notary" / f"{app.stem}.notary.zip"
        zip_path.parent.mkdir(parents=True, exist_ok=True)
        self._run_sign_commands(
            [
                ["ditto", "-c", "-k", "--keepParent", str(app), str(zip_path)],
                ["xcrun", "notarytool", "submit", str(zip_path), "--apple-id", apple_id, "--team-id", team_id, "--password", password, "--wait"],
            ]
        )

    def _staple_selected_app(self) -> None:
        app = self._selected_app_bundle()
        if not app.exists():
            messagebox.showwarning("Staple", "App bundle not found.")
            return
        self._run_sign_commands([["xcrun", "stapler", "staple", str(app)]])

    def _check_dmg_security(self) -> None:
        dmg = self._resolved_dmg_for_sign()
        if dmg is None:
            messagebox.showwarning("Verify", "No DMG found to verify.")
            return
        self._run_sign_commands(
            [
                [
                    "sh",
                    "-lc",
                    "/usr/bin/codesign -dv --verbose=4 "
                    + shlex.quote(str(dmg))
                    + " 2>&1 | grep -E \"Authority|TeamIdentifier|Signature|Timestamp|Runtime|Identifier\" || true",
                ],
                ["spctl", "-a", "-vvv", "-t", "open", str(dmg)],
            ]
        )

    def _sign_selected_dmg(self) -> None:
        dmg = self._resolved_dmg_for_sign()
        if dmg is None:
            messagebox.showwarning("Sign", "No DMG found to sign.")
            return
        identity = self.app_sign_identity.get().strip()
        if not identity:
            messagebox.showwarning("Sign", "App sign identity is required for DMG signing.")
            return
        self._run_sign_commands([["codesign", "--force", "--timestamp", "--options", "runtime", "--sign", identity, str(dmg)]])
        self.last_dmg_path = dmg

    def _notarize_selected_dmg(self) -> None:
        dmg = self._resolved_dmg_for_sign()
        if dmg is None:
            messagebox.showwarning("Notarize", "No DMG found to notarize.")
            return
        apple_id = self.notary_apple_id.get().strip()
        team_id = self.notary_team_id.get().strip()
        password = self.notary_password.get().strip()
        if not apple_id or not team_id or not password:
            messagebox.showwarning("Notarize", "Apple ID, Team ID, and App Password are required.")
            return
        self._run_sign_commands(
            [
                ["xcrun", "notarytool", "submit", str(dmg), "--apple-id", apple_id, "--team-id", team_id, "--password", password, "--wait"],
            ]
        )
        self.last_dmg_path = dmg

    def _staple_selected_dmg(self) -> None:
        dmg = self._resolved_dmg_for_sign()
        if dmg is None:
            messagebox.showwarning("Staple", "No DMG found to staple.")
            return
        self._run_sign_commands([["xcrun", "stapler", "staple", str(dmg)]])

    def _upload_admin_releases_url(self) -> str:
        site = self.upload_site_url.get().strip().rstrip("/")
        if not site:
            raise ValueError("Site URL is required.")
        return f"{site}/wp-json/server-engine/v1/app-update/admin/releases"

    def _reload_release_dmg_versions(self) -> None:
        if not hasattr(self, "release_dmg_combo"):
            return
        versions = self._dmg_versions()
        self.release_dmg_combo.configure(values=versions)
        if versions and self.release_dmg_select_version.get() not in versions:
            self.release_dmg_select_version.set(versions[0])
        self._sync_release_version_from_dmg_selection()

    def _pick_release_dmg(self) -> None:
        start = self.release_dmg_path.get().strip() or str(REPO_ROOT / "dist" / "dmg")
        path = filedialog.askopenfilename(
            title="Select DMG to upload",
            initialdir=str(Path(start).expanduser().parent if start else REPO_ROOT),
            filetypes=[("DMG files", "*.dmg"), ("All files", "*.*")],
        )
        if path:
            self.release_dmg_path.set(path)

    @staticmethod
    def _release_version_from_dmg_name(name: str) -> str:
        base = Path(name).name
        if base.lower().endswith(".dmg"):
            base = base[:-4]
        if not base.startswith("ServerEngine-"):
            return ""
        parts = base.split("-")
        if len(parts) < 4:
            return ""
        version = "-".join(parts[3:]).strip()
        return version

    def _sync_release_version_from_dmg_selection(self) -> None:
        version = ""
        explicit = self.release_dmg_path.get().strip()
        if explicit:
            version = self._release_version_from_dmg_name(Path(explicit).name)
        if not version:
            selected = self.release_dmg_select_version.get().strip()
            if selected:
                version = self._release_version_from_dmg_name(selected)
        if version and self.upload_version.get().strip() != version:
            self.upload_version.set(version)

    def _resolved_dmg_for_release_upload(self) -> Path | None:
        explicit = self.release_dmg_path.get().strip()
        if explicit:
            p = Path(explicit).expanduser()
            return p if p.exists() else None
        mode = self.release_dmg_select_mode.get().strip() or "last_built"
        if mode == "by_version":
            selected = self.release_dmg_select_version.get().strip()
            if selected:
                p = REPO_ROOT / "dist" / "dmg" / selected
                if p.exists():
                    return p
        return self._find_latest_dmg()

    def _refresh_release_login_ui(self) -> None:
        site = self.upload_site_url.get().strip()
        email = self.upload_email.get().strip()
        is_logged_in = bool(self.upload_access_token and site and email)
        if hasattr(self, "release_login_status"):
            if is_logged_in:
                self.release_login_status.set(f"Logged in: {email} @ {site}")
            else:
                self.release_login_status.set("Not logged in.")
        if hasattr(self, "release_login_button"):
            self.release_login_button.configure(text="Switch Login…" if is_logged_in else "Login…")
        if hasattr(self, "release_logout_button"):
            self.release_logout_button.configure(state="normal" if is_logged_in else "disabled")

    def _upload_logout(self) -> None:
        self.upload_access_token = ""
        self._save_state()
        self._refresh_release_login_ui()

    def _open_upload_login_popup(self) -> None:
        dialog = tk.Toplevel(self)
        dialog.title("Server Login")
        dialog.resizable(False, False)
        dialog.transient(self)
        dialog.grab_set()
        body = ttk.Frame(dialog, padding=12)
        body.pack(fill="both", expand=True)
        body.columnconfigure(1, weight=1)
        site_var = tk.StringVar(value=self.upload_site_url.get())
        email_var = tk.StringVar(value=self.upload_email.get())
        pass_var = tk.StringVar(value=self.upload_password.get())
        ttk.Label(body, text="Site URL").grid(row=0, column=0, sticky="w", pady=4)
        ttk.Entry(body, textvariable=site_var, width=44).grid(row=0, column=1, sticky="ew", pady=4)
        ttk.Label(body, text="Email").grid(row=1, column=0, sticky="w", pady=4)
        ttk.Entry(body, textvariable=email_var, width=44).grid(row=1, column=1, sticky="ew", pady=4)
        ttk.Label(body, text="Password").grid(row=2, column=0, sticky="w", pady=4)
        ttk.Entry(body, textvariable=pass_var, show="*", width=44).grid(row=2, column=1, sticky="ew", pady=4)

        actions = ttk.Frame(body)
        actions.grid(row=3, column=0, columnspan=2, sticky="e", pady=(8, 0))

        def do_login() -> None:
            self.upload_site_url.set(site_var.get().strip())
            self.upload_email.set(email_var.get().strip())
            self.upload_password.set(pass_var.get())
            self._upload_login()
            if self.upload_access_token:
                dialog.destroy()

        ttk.Button(actions, text="Cancel", command=dialog.destroy).pack(side="right")
        ttk.Button(actions, text="Login", command=do_login).pack(side="right", padx=(0, 8))

    def _upload_login(self) -> None:
        site = self.upload_site_url.get().strip().rstrip("/")
        email = self.upload_email.get().strip()
        password = self.upload_password.get()
        if not site or not email or not password:
            messagebox.showwarning("Upload Login", "Site URL, email, and password are required.")
            return
        try:
            payload = api_post_form(
                f"{site}/wp-json/engine/v1/auth/login",
                {"email": email, "password": password},
            )
            token = str(payload.get("access_token") or payload.get("token") or "")
            if not token:
                raise RuntimeError("Login response did not include access_token.")
            self.upload_access_token = token
            self._save_state()
            self._refresh_release_login_ui()
            self._append_output("Upload login success.\n")
            messagebox.showinfo("Upload Login", "Login successful.")
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", "replace")
            messagebox.showerror("Upload Login", f"HTTP {exc.code} {exc.reason}\n{detail[:500]}")
        except Exception as exc:
            messagebox.showerror("Upload Login", str(exc))

    def _upload_fetch_releases(self, silent: bool = True) -> None:
        if not self.upload_access_token:
            messagebox.showwarning("Fetch Releases", "Login first.")
            return
        def worker() -> None:
            try:
                url = self._upload_admin_releases_url()
                request = urllib.request.Request(
                    url,
                    headers={
                        "Accept": "application/json",
                        "Authorization": f"Bearer {self.upload_access_token}",
                    },
                )
                with urllib.request.urlopen(request, timeout=30, context=SSL_CONTEXT) as response:
                    payload = json.loads(response.read().decode("utf-8"))
                raw_items = payload.get("updates") if isinstance(payload, dict) else []
                if not isinstance(raw_items, list):
                    raw_items = []
                items = [item for item in raw_items if isinstance(item, dict)]
                self.after(0, setattr, self, "upload_manifest_items", items)
                self.after(0, self._append_output, f"Fetched {len(items)} existing Sparkle releases.\n")
                if not silent:
                    self.after(0, messagebox.showinfo, "Fetch Releases", f"Fetched {len(items)} release entries.")
            except urllib.error.HTTPError as exc:
                detail = exc.read().decode("utf-8", "replace")
                self.after(0, self._append_output, f"[release-upload] fetch failed: HTTP {exc.code} {exc.reason}\n{detail[:800]}\n")
                if not silent:
                    self.after(0, messagebox.showerror, "Fetch Releases", f"HTTP {exc.code} {exc.reason}\n{detail[:500]}")
            except Exception as exc:
                self.after(0, self._append_output, f"[release-upload] fetch exception: {exc}\n")
                if not silent:
                    self.after(0, messagebox.showerror, "Fetch Releases", str(exc))

        threading.Thread(target=worker, daemon=True).start()

    def _is_dmg_stapled(self, dmg: Path) -> tuple[bool, str]:
        try:
            result = subprocess.run(
                ["xcrun", "stapler", "validate", str(dmg)],
                capture_output=True,
                text=True,
                check=False,
            )
            out = ((result.stdout or "") + "\n" + (result.stderr or "")).strip()
            return result.returncode == 0, out
        except Exception as exc:
            return False, str(exc)

    def _upload_dmg_to_server(self) -> None:
        dmg = self._resolved_dmg_for_release_upload()
        if dmg is None or not dmg.exists():
            messagebox.showwarning("Upload", "No DMG found to upload.")
            return
        if not self.upload_access_token:
            messagebox.showwarning("Upload", "Login first.")
            return
        self._append_output("\n[release-upload] Starting upload flow\n")
        self._append_output(f"[release-upload] DMG: {dmg}\n")

        stapled, staple_output = self._is_dmg_stapled(dmg)
        self._append_output(f"[release-upload] Staple validate: {'OK' if stapled else 'FAILED'}\n")
        if staple_output:
            self._append_output(f"[release-upload] Staple output:\n{staple_output}\n")
        if not stapled:
            if not messagebox.askyesno("Upload", "DMG does not appear stapled. Upload anyway?"):
                self._append_output("[release-upload] Aborted by user (not stapled)\n")
                return

        version = self.upload_version.get().strip()
        build = self.upload_build.get().strip() or version
        min_system_version = self.upload_min_system_version.get().strip() or "14.0"
        os_value = self.upload_os.get().strip() or "macos"
        arch = self.upload_arch.get().strip() or "arm64"
        sparkle_sig = ""
        release_notes_url = self.upload_release_notes_url.get().strip()
        release_notes_html = self.upload_release_notes_html_text.get("1.0", "end").strip()
        critical_update = "true" if self.upload_critical_update.get() else "false"
        phased_rollout_interval = self.upload_phased_rollout_interval.get().strip() or "0"
        staging_percentage = self.upload_staging_percentage.get().strip() or "0"
        if not version:
            messagebox.showwarning("Upload", "Version is required.")
            self._append_output("[release-upload] Missing version; abort\n")
            return
        self._append_output(
            f"[release-upload] Metadata: version={version} build={build} min_system_version={min_system_version} os={os_value} arch={arch}\n"
        )
        sign_update = self._sparkle_tool_binary("sign_update")
        if not sign_update:
            messagebox.showwarning("Upload", "sign_update not found. Set Sparkle tools dir first.")
            self._append_output("[release-upload] sign_update not found; abort\n")
            return
        private_key_file = self.sparkle_private_key_file.get().strip()
        sign_cmd = [sign_update, str(dmg)]
        if private_key_file:
            sign_cmd.extend(["--ed-key-file", private_key_file])
        elif self.sparkle_key_account.get().strip():
            sign_cmd.extend(["--account", self.sparkle_key_account.get().strip()])
        self._append_output(f"[release-upload] Running sign_update:\n$ {' '.join(shlex.quote(p) for p in sign_cmd)}\n")
        if not build:
            build = self._default_release_build_stamp()
            self.upload_build.set(build)

        duplicate = next(
            (
                item for item in self.upload_manifest_items
                if str(item.get("version") or item.get("appVersion") or "") == version
                and str(item.get("build") or "") == build
                and str(item.get("arch") or "") == arch
            ),
            None,
        )
        if duplicate and not messagebox.askyesno("Upload", f"Release {version} build {build} ({arch}) exists. Overwrite?"):
            self._append_output("[release-upload] Aborted by user (overwrite declined)\n")
            return

        def worker() -> None:
            def log(text: str) -> None:
                self.after(0, self._append_output, text)

            try:
                sign_result = subprocess.run(sign_cmd, capture_output=True, text=True, check=False)
                sign_out = ((sign_result.stdout or "") + "\n" + (sign_result.stderr or "")).strip()
                if sign_out:
                    log(f"[release-upload] sign_update output:\n{sign_out}\n")
                if sign_result.returncode != 0:
                    log(f"[release-upload] sign_update failed with exit code {sign_result.returncode}\n")
                    self.after(0, messagebox.showerror, "Upload", f"sign_update failed:\n{sign_out[:1000]}")
                    return
                match = re.search(r"sparkle:edSignature=\"([^\"]+)\"", sign_out)
                if not match:
                    match = re.search(r"edSignature[:=]\s*([A-Za-z0-9+/=:_-]+)", sign_out)
                if not match:
                    log("[release-upload] Failed to parse sparkle_ed_signature\n")
                    self.after(0, messagebox.showerror, "Upload", f"Could not parse sparkle_ed_signature from sign_update output:\n{sign_out[:1000]}")
                    return
                parsed_sig = match.group(1).strip()
                self.after(0, self.upload_sparkle_ed_signature.set, parsed_sig)
                log(f"[release-upload] sparkle_ed_signature parsed: {parsed_sig[:24]}...\n")

                size_bytes = dmg.stat().st_size
                sha256 = file_sha256(dmg)
                pub_date = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
                log(f"[release-upload] file_size={size_bytes}\n")
                log(f"[release-upload] sha256={sha256}\n")
                log(f"[release-upload] pub_date_iso8601={pub_date}\n")
                base_fields = [
                    ("version", version),
                    ("build", build),
                    ("min_system_version", min_system_version),
                    ("os", os_value),
                    ("arch", arch),
                    ("file_name", dmg.name),
                    ("file_size", str(size_bytes)),
                    ("sha256", sha256),
                    ("sparkle_ed_signature", parsed_sig),
                    ("release_notes_html", release_notes_html),
                    ("release_notes_url", release_notes_url),
                    ("pub_date_iso8601", pub_date),
                    ("critical_update", critical_update),
                    ("phased_rollout_interval", phased_rollout_interval),
                    ("staging_percentage", staging_percentage),
                ]
                endpoint = self._upload_admin_releases_url()
                log(f"[release-upload] POST {endpoint}\n")
                chunk_size = 50 * 1024 * 1024
                upload_id = uuid.uuid4().hex
                total_chunks = int(math.ceil(size_bytes / chunk_size)) if size_bytes > 0 else 1
                log(f"[release-upload] Chunked upload: upload_id={upload_id} chunk_size={chunk_size} total_chunks={total_chunks}\n")
                final_body = ""
                with dmg.open("rb") as handle:
                    for chunk_index in range(total_chunks):
                        chunk_bytes = handle.read(chunk_size)
                        if not chunk_bytes and size_bytes > 0:
                            raise RuntimeError(f"Unexpected EOF at chunk {chunk_index}/{total_chunks}.")
                        chunk_fields = base_fields + [
                            ("upload_id", upload_id),
                            ("chunk_index", str(chunk_index)),
                            ("total_chunks", str(total_chunks)),
                        ]
                        log(
                            f"[release-upload] Uploading chunk {chunk_index + 1}/{total_chunks} "
                            f"({len(chunk_bytes)} bytes)\n"
                        )
                        body = multipart_upload_bytes(
                            endpoint,
                            self.upload_access_token,
                            chunk_fields,
                            "file",
                            dmg.name,
                            chunk_bytes,
                        )
                        final_body = body
                        log(f"[release-upload] Chunk {chunk_index + 1}/{total_chunks} response: {body[:500]}\n")
                        try:
                            parsed = json.loads(body)
                            if isinstance(parsed, dict) and parsed.get("complete") is True:
                                log("[release-upload] Server reported complete=true\n")
                        except Exception:
                            pass
                if not final_body:
                    raise RuntimeError("Chunk upload completed without server response.")
                log(f"Upload completed.\nStaple validate output:\n{staple_output}\nServer:\n{final_body[:1200]}\n")
                self.after(0, messagebox.showinfo, "Upload", "DMG upload completed.")
                self.after(0, self._upload_fetch_releases, True)
            except urllib.error.HTTPError as exc:
                detail = exc.read().decode("utf-8", "replace")
                log(f"[release-upload] HTTP error: {exc.code} {exc.reason}\n{detail[:1200]}\n")
                self.after(0, messagebox.showerror, "Upload", f"HTTP {exc.code} {exc.reason}\n{detail[:800]}")
            except Exception as exc:
                log(f"[release-upload] Exception: {exc}\n")
                self.after(0, messagebox.showerror, "Upload", str(exc))

        threading.Thread(target=worker, daemon=True).start()

    def _run_sign_commands(self, commands: list[list[str]]) -> None:
        if self.sign_process is not None:
            return
        self._save_state()
        self._set_sign_running(True)

        def worker() -> None:
            try:
                for cmd in commands:
                    self.after(0, self._append_output, f"\n$ {' '.join(shlex.quote(part) for part in cmd)}\n")
                    process = subprocess.Popen(
                        cmd,
                        cwd=str(REPO_ROOT),
                        stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT,
                        text=True,
                        bufsize=1,
                        preexec_fn=os.setsid if os.name == "posix" else None,
                    )
                    self.sign_process = process
                    self._stream_process_output(process)
                    code = process.wait()
                    if code != 0:
                        self.after(0, self._append_output, f"\nCommand failed with exit code {code}.\n")
                        return
                self.after(0, self._append_output, "\nSign/verify flow completed successfully.\n")
            except Exception as exc:
                self.after(0, self._append_output, f"\nSign/verify error: {exc}\n")
            finally:
                self.sign_process = None
                self.after(0, self._set_sign_running, False)

        threading.Thread(target=worker, daemon=True).start()

    def _run_build_app(self) -> None:
        if self.running:
            return
        if not APP_BUILD_SCRIPT_PATH.exists():
            messagebox.showerror("Build App", f"Script not found: {APP_BUILD_SCRIPT_PATH}")
            return
        self._save_state()
        cmd = self._build_app_command()
        self._append_output(f"\n$ {' '.join(shlex.quote(part) for part in cmd)}\n")
        self._set_running(True)

        def worker() -> None:
            try:
                env = os.environ.copy()
                env["PYTHONUNBUFFERED"] = "1"
                process = subprocess.Popen(
                    cmd,
                    cwd=str(REPO_ROOT),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    bufsize=1,
                    env=env,
                    preexec_fn=os.setsid if os.name == "posix" else None,
                )
                self.build_process = process
                self._stream_process_output(process)
                code = process.wait()
                if code == 0:
                    app_bundle = self._app_bundle_path()
                    self.after(0, self.app_artifact_path.set, str(app_bundle))
                    self.after(0, self._refresh_app_actions_enabled)
                    self.after(0, self._append_output, f"\nApp build finished successfully.\nAPP: {app_bundle}\n")
                else:
                    self.after(0, self._append_output, f"\nApp build failed with exit code {code}.\n")
            except Exception as exc:
                self.after(0, self._append_output, f"\nApp build error: {exc}\n")
            finally:
                self.build_process = None
                self.after(0, self._set_running, False)

        threading.Thread(target=worker, daemon=True).start()




if __name__ == "__main__":
    app = BuildPkgGui()
    app.mainloop()
