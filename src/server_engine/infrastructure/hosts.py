from __future__ import annotations

import os
import shlex
import subprocess
import sys
from pathlib import Path

from server_engine.core.models import OperationResult, RuntimePaths
from server_engine.infrastructure.privileged_helper import PrivilegedHelperClient


class HostsGateway:
    def __init__(self, runtime_paths: RuntimePaths) -> None:
        self.runtime_paths = runtime_paths
        override = os.environ.get("SERVER_ENGINE_HOSTS_PATH")
        self.hosts_path = Path(override).expanduser() if override else Path("/etc/hosts")
        self.marker = "# server-engine"
        self.block_start = "#Start ServerEngine"
        self.block_end = "#End ServerEngine"
        self._helper_client = PrivilegedHelperClient(runtime_paths)

    def preview_mapping(self, domain: str) -> str:
        normalized = domain.strip().lower()
        if not normalized:
            return ""
        return "\n".join(self._managed_domain_lines(normalized))

    def ensure_mapping(self, domain: str) -> OperationResult:
        normalized = domain.strip().lower()
        if not normalized:
            return OperationResult(False, "Domain cannot be empty.")
        lines = self._read_lines()
        domains = self._managed_domains(lines)
        if normalized in domains:
            return OperationResult(True, f"Hosts entry already exists for {domain}.", {"domain": domain, "path": str(self.hosts_path)})
        domains.add(normalized)
        self._write_lines(self._with_managed_domains(lines, domains))
        return OperationResult(True, f"Hosts entry ensured for {domain}.", {"domain": domain, "path": str(self.hosts_path)})

    def replace_mapping(self, old_domain: str, new_domain: str) -> OperationResult:
        lines = self._read_lines()
        domains = self._managed_domains(lines)
        old_normalized = old_domain.strip().lower()
        new_normalized = new_domain.strip().lower()
        if old_normalized:
            domains.discard(old_normalized)
        if new_normalized:
            domains.add(new_normalized)
        self._write_lines(self._with_managed_domains(lines, domains))
        return OperationResult(
            True,
            f"Hosts entry updated from {old_domain} to {new_domain}.",
            {"old_domain": old_domain, "new_domain": new_domain, "path": str(self.hosts_path)},
        )

    def remove_mapping(self, domain: str) -> OperationResult:
        lines = self._read_lines()
        normalized = domain.strip().lower()
        domains = self._managed_domains(lines)
        domains.discard(normalized)
        self._write_lines(self._with_managed_domains(lines, domains))
        return OperationResult(True, f"Hosts entry removed for {domain}.", {"domain": domain, "path": str(self.hosts_path)})

    def sync_serverengine_block(self, domains: list[str]) -> OperationResult:
        normalized: list[str] = []
        seen: set[str] = set()
        for raw in domains:
            value = str(raw or "").strip().lower()
            if not value or value == "localhost":
                continue
            if value in seen:
                continue
            seen.add(value)
            normalized.append(value)

        lines = self._read_lines()
        self._write_lines(self._with_managed_domains(lines, set(normalized)))
        return OperationResult(True, "Server Engine hosts block synced.", {"path": str(self.hosts_path)})

    def clear_serverengine_block(self) -> OperationResult:
        lines = self._read_lines()
        preserved: list[str] = []
        inside_block = False
        marker_text = self.marker.lstrip("#").strip().lower()
        for line in lines:
            stripped = line.strip()
            if stripped == self.block_start:
                inside_block = True
                continue
            if stripped == self.block_end:
                inside_block = False
                continue
            if inside_block:
                continue
            left, sep, right = stripped.partition("#")
            if sep and marker_text in right.strip().lower():
                continue
            preserved.append(line)
        self._write_lines(preserved)
        return OperationResult(True, "Server Engine hosts block cleared.", {"path": str(self.hosts_path)})

    def _read_lines(self) -> list[str]:
        if not self.hosts_path.exists():
            return []
        return self.hosts_path.read_text(encoding="utf-8").splitlines()

    def _write_lines(self, lines: list[str]) -> None:
        content = "\n".join(lines).strip()
        if content:
            content += "\n"
        current_content = ""
        if self.hosts_path.exists():
            try:
                current_content = self.hosts_path.read_text(encoding="utf-8")
            except Exception:
                current_content = ""
        if current_content == content:
            return
        try:
            self.hosts_path.write_text(content, encoding="utf-8")
            self._flush_dns_cache_if_needed()
        except PermissionError:
            self._write_lines_with_admin_prompt(content)

    def _write_lines_with_admin_prompt(self, content: str) -> None:
        helper_message = ""
        helper_result = self._helper_client.write_hosts_content(self.hosts_path, content)
        if helper_result.success:
            self._flush_dns_cache_if_needed()
            return
        helper_message = helper_result.message.strip()

        # SMJobBless path: do not fall back to osascript cp/chown/chmod flows.
        if sys.platform == "darwin":
            raise PermissionError(helper_message or "Privileged helper failed.")

        temp_dir = self.runtime_paths.temp_dir
        temp_dir.mkdir(parents=True, exist_ok=True)
        temp_file = temp_dir / "hosts.pending"
        temp_file.write_text(content, encoding="utf-8")

        if sys.platform == "darwin":
            copy_cmd = f"/bin/cp {shlex.quote(str(temp_file))} {shlex.quote(str(self.hosts_path))}"
            prompt = (
                "Server Engine needs administrator permission to update /etc/hosts "
                "for local domain mapping."
            )
            escaped_prompt = prompt.replace("\\", "\\\\").replace('"', '\\"')
            osascript = [
                "osascript",
                "-e",
                f'do shell script "{copy_cmd}" with administrator privileges with prompt "{escaped_prompt}"',
            ]
            completed = subprocess.run(osascript, capture_output=True, text=True)
            if completed.returncode != 0:
                osascript_message = completed.stderr.strip() or completed.stdout.strip() or "Administrator authorization was cancelled."
                raise PermissionError(f"{helper_message}; osascript fallback failed: {osascript_message}")
            self._flush_dns_cache_if_needed()
            return

        raise PermissionError(helper_message or "Privileged helper failed.")

    def _matches_domain(self, line: str, domain: str) -> bool:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            return False
        tokens = stripped.split()
        if len(tokens) < 2:
            return False
        return domain in tokens[1:]

    def _managed_domains(self, lines: list[str]) -> set[str]:
        domains: set[str] = set()
        marker_text = self.marker.lstrip("#").strip().lower()
        inside_block = False
        for line in lines:
            stripped = line.strip()
            if not stripped:
                continue
            if stripped == self.block_start:
                inside_block = True
                continue
            if stripped == self.block_end:
                inside_block = False
                continue
            if inside_block:
                left, _, _ = stripped.partition("#")
                tokens = left.split()
                if len(tokens) >= 2 and tokens[0] in {"127.0.0.1", "::1"}:
                    for host in tokens[1:]:
                        normalized = host.strip().lower()
                        if normalized and normalized != "localhost":
                            domains.add(normalized)
                continue
            left, sep, right = stripped.partition("#")
            if not sep:
                continue
            if marker_text not in right.strip().lower():
                continue
            tokens = left.split()
            if len(tokens) < 2:
                continue
            for host in tokens[1:]:
                normalized = host.strip().lower()
                if normalized and normalized != "localhost":
                    domains.add(normalized)
        # Migrate legacy local loopback entries into managed set so we keep one
        # consolidated managed IPv4 mapping block and avoid fragmented resolver paths.
        for line in lines:
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            left, _, _ = stripped.partition("#")
            tokens = left.split()
            if len(tokens) < 2:
                continue
            ip = tokens[0]
            if ip != "127.0.0.1":
                continue
            for host in tokens[1:]:
                normalized = host.strip().lower()
                if not normalized or normalized == "localhost":
                    continue
                if normalized == "serverengine" or normalized.endswith(".engine"):
                    domains.add(normalized)
        return domains

    def _with_managed_domains(self, lines: list[str], domains: set[str]) -> list[str]:
        marker_text = self.marker.lstrip("#").strip().lower()
        preserved: list[str] = []
        inside_block = False
        for line in lines:
            stripped = line.strip()
            if stripped == self.block_start:
                inside_block = True
                continue
            if stripped == self.block_end:
                inside_block = False
                continue
            if inside_block:
                continue
            if not stripped:
                preserved.append(line)
                continue
            left, sep, right = stripped.partition("#")
            if sep and marker_text in right.strip().lower():
                continue
            # Remove fragmented legacy loopback local-domain lines; these are
            # replaced by the consolidated managed block below.
            tokens = left.split()
            if len(tokens) >= 2 and tokens[0] in {"127.0.0.1", "::1"}:
                hosts = [item.strip().lower() for item in tokens[1:]]
                if any(host == "serverengine" or host.endswith(".engine") for host in hosts):
                    continue
            # Keep all Server Engine loopback mappings under the managed block.
            if stripped == "::1" or stripped.startswith("::1 "):
                continue
            preserved.append(line)

        managed_lines = self._managed_block_lines(domains)
        if not managed_lines:
            return preserved

        if preserved and preserved[-1].strip():
            return [*preserved, *managed_lines]
        return [*preserved, *managed_lines]

    def _managed_block_lines(self, domains: set[str]) -> list[str]:
        ordered_domains = sorted(domain for domain in domains if domain)
        if not ordered_domains:
            return []
        lines = [self.block_start]
        for domain in ordered_domains:
            lines.extend(self._managed_domain_lines(domain))
        lines.append(self.block_end)
        return lines

    def _managed_domain_lines(self, domain: str) -> list[str]:
        normalized = domain.strip().lower()
        if not normalized:
            return []
        return [
            f"127.0.0.1 {normalized}",
            f"::1 {normalized}",
        ]

    def _flush_dns_cache_if_needed(self) -> None:
        if sys.platform != "darwin":
            return
        try:
            subprocess.run(["dscacheutil", "-flushcache"], capture_output=True, text=True, check=False)
            subprocess.run(["killall", "-HUP", "mDNSResponder"], capture_output=True, text=True, check=False)
        except Exception:
            pass
