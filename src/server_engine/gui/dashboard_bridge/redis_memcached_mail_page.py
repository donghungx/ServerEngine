from ._shared import *


class RedisMemcachedMailPageMixin(DashboardBridgeSignals):
    @Property("QVariantMap", notify=redisRuntimeFeedbackChanged)
    def redisGeneralConfigSettings(self) -> dict[str, object]:
        defaults = {
            "bind_address": "127.0.0.1",
            "protected_mode": True,
            "appendonly": False,
            "log_level": "notice",
            "db_filename": "dump.rdb",
        }
        try:
            for line in self._redis_config_path().read_text(encoding="utf-8").splitlines():
                parts = line.strip().split(None, 1)
                if len(parts) != 2:
                    continue
                key, value = parts[0].lower(), parts[1].strip()
                if key == "bind":
                    defaults["bind_address"] = value.split()[0]
                elif key == "protected-mode":
                    defaults["protected_mode"] = value.lower() in {"yes", "1", "true"}
                elif key == "appendonly":
                    defaults["appendonly"] = value.lower() in {"yes", "1", "true"}
                elif key == "loglevel":
                    defaults["log_level"] = value
                elif key == "dbfilename":
                    defaults["db_filename"] = value
        except Exception:
            pass
        return defaults

    @Slot("QVariantMap", result=bool)
    def saveRedisGeneralSettings(self, values: dict) -> bool:
        try:
            current = self.activeRedisConfigContent or self._container.redis_service.generate_config()
            replacements = {
                "bind": str(values.get("bind_address", "127.0.0.1")).strip() or "127.0.0.1",
                "protected-mode": "yes" if bool(values.get("protected_mode", True)) else "no",
                "appendonly": "yes" if bool(values.get("appendonly", False)) else "no",
                "loglevel": str(values.get("log_level", "notice")).strip() or "notice",
                "dbfilename": str(values.get("db_filename", "dump.rdb")).strip() or "dump.rdb",
            }
            lines = current.splitlines()
            seen = set()
            output = []
            for line in lines:
                key = line.strip().split(None, 1)[0].lower() if line.strip() and not line.lstrip().startswith("#") else ""
                if key in replacements:
                    output.append(f"{key} {replacements[key]}")
                    seen.add(key)
                else:
                    output.append(line)
            for key, value in replacements.items():
                if key not in seen:
                    output.append(f"{key} {value}")
            return self.saveActiveRedisConfigContent("\n".join(output) + "\n")
        except Exception as exc:
            self._redis_runtime_message = str(exc)
            self._redis_runtime_error = True
            self.redisRuntimeFeedbackChanged.emit()
            return False

    @Property("QVariantMap", notify=mailpitRuntimeFeedbackChanged)
    def mailpitGeneralConfigSettings(self) -> dict[str, object]:
        return dict(getattr(self, "_mailpit_general_config_settings", {}))

    @Slot("QVariantMap", result=bool)
    def saveMailpitGeneralSettings(self, values: dict) -> bool:
        self._mailpit_general_config_settings = dict(values or {})
        self._mailpit_runtime_message = "Mailpit general settings saved. Restart Mailpit to apply."
        self._mailpit_runtime_error = False
        self.mailpitRuntimeFeedbackChanged.emit()
        return True

    @Slot()
    def startMailpitMailboxEvents(self) -> None:
        self._mailpit_mailbox_live_updates = True
        self.mailpitMailboxChanged.emit()

    @Slot()
    def stopMailpitMailboxEvents(self) -> None:
        self._mailpit_mailbox_live_updates = False

    @Property(bool, notify=mailpitMailboxChanged)
    def mailpitMailboxLiveUpdates(self) -> bool:
        return bool(getattr(self, "_mailpit_mailbox_live_updates", False))

    @Slot(int, result="QVariantList")
    def mailpitMailboxMessages(self, limit: int = 100) -> list[dict[str, object]]:
        try:
            safe_limit = max(1, min(int(limit or 100), 500))
            url = self._container.mailpit_service.web_url().rstrip("/") + f"/api/v1/messages?limit={safe_limit}"
            request = urllib.request.Request(url, headers={"Accept": "application/json"})
            with urllib.request.urlopen(request, timeout=3) as response:
                payload = json.loads(response.read().decode("utf-8"))
            messages = payload.get("messages", payload) if isinstance(payload, dict) else payload
            return [self._mailpit_message_summary(item) for item in (messages or []) if isinstance(item, dict)]
        except Exception as exc:
            LOGGER.debug("Unable to read Mailpit mailbox: %s", exc)
            return []

    @Slot(str, result="QVariantMap")
    def mailpitMailboxMessage(self, message_id: str) -> dict[str, object]:
        try:
            encoded = urllib.parse.quote(str(message_id or "").strip(), safe="")
            url = self._container.mailpit_service.web_url().rstrip("/") + "/api/v1/message/" + encoded
            request = urllib.request.Request(url, headers={"Accept": "application/json"})
            with urllib.request.urlopen(request, timeout=3) as response:
                payload = json.loads(response.read().decode("utf-8"))
            return self._mailpit_message_detail(payload if isinstance(payload, dict) else {})
        except Exception as exc:
            LOGGER.debug("Unable to read Mailpit message: %s", exc)
            return {}

    def _mailpit_value(self, payload: dict, *names: str) -> object:
        for name in names:
            if name in payload and payload[name] is not None:
                return payload[name]
            for key, value in payload.items():
                if str(key).lower() == name.lower() and value is not None:
                    return value
        return ""

    def _mailpit_address_text(self, value: object) -> str:
        if isinstance(value, dict):
            name = str(value.get("Name", value.get("name", "")) or "").strip()
            address = str(value.get("Address", value.get("address", "")) or "").strip()
            if name and address:
                return f"{name} <{address}>"
            return address or name
        if isinstance(value, (list, tuple)):
            return ", ".join(item for item in (self._mailpit_address_text(entry) for entry in value) if item)
        return str(value or "").strip()

    def _mailpit_message_summary(self, payload: dict) -> dict[str, object]:
        sender = self._mailpit_value(payload, "From", "from", "Sender", "sender")
        recipients = self._mailpit_value(payload, "To", "to", "Recipients", "recipients")
        read_value = self._mailpit_value(payload, "Read", "read", "IsRead", "is_read")
        return {
            "id": str(self._mailpit_value(payload, "ID", "id", "MessageID", "message_id")),
            "subject": str(self._mailpit_value(payload, "Subject", "subject") or "(no subject)"),
            "from": self._mailpit_address_text(sender),
            "to": self._mailpit_address_text(recipients),
            "date": str(self._mailpit_value(payload, "Date", "date", "Created", "created")),
            "created": str(self._mailpit_value(payload, "Created", "created")),
            "snippet": str(self._mailpit_value(payload, "Snippet", "snippet", "Text", "text")),
            "size": self._mailpit_value(payload, "Size", "size"),
            "read": bool(read_value) if isinstance(read_value, bool) else str(read_value).lower() in {"1", "true", "yes", "read"},
        }

    def _mailpit_message_detail(self, payload: dict) -> dict[str, object]:
        item = self._mailpit_message_summary(payload)
        item.update({
            "body_text": str(self._mailpit_value(payload, "Text", "text", "Body", "body")),
            "body_html": str(self._mailpit_value(payload, "HTML", "html", "BodyHTML", "body_html")),
            "html": str(self._mailpit_value(payload, "HTML", "html", "BodyHTML", "body_html")),
            "web_base_url": self._container.mailpit_service.web_url(),
        })
        return item

    @Property("QVariantList", notify=redisInspectorChanged)
    def redisInspectorKeys(self) -> list[dict[str, object]]:
        return list(getattr(self, "_redis_inspector_keys", []))

    @Property("QVariantList", notify=redisInspectorChanged)
    def redisInspectorNamespaces(self) -> list[dict[str, object]]:
        return list(getattr(self, "_redis_inspector_namespaces", []))

    @Property(str, notify=redisInspectorChanged)
    def redisInspectorSelectedKey(self) -> str:
        return getattr(self, "_redis_inspector_selected_key", "")

    @Property(str, notify=redisInspectorChanged)
    def redisInspectorSelectedValue(self) -> str:
        return getattr(self, "_redis_inspector_selected_value", "")

    @Property(str, notify=redisInspectorChanged)
    def redisInspectorSelectedSummary(self) -> str:
        return getattr(self, "_redis_inspector_selected_summary", "")

    def _redis_cli(self, *arguments: str) -> list[str]:
        runtime = self._container.redis_service.active_runtime()
        if runtime is None:
            return []
        command = [runtime.client_path or "redis-cli", "-h", "127.0.0.1", "-p", str(self._container.settings_service.get_settings().redis_port), "--raw"]
        password = self._container.redis_service.password()
        if password:
            command.extend(["-a", password, "--no-auth-warning"])
        command.extend(str(arg) for arg in arguments)
        result = subprocess.run(command, capture_output=True, text=True, timeout=5, check=False)
        if result.returncode != 0:
            raise RuntimeError(result.stderr.strip() or "Redis command failed")
        return result.stdout.splitlines()

    @Slot(str)
    def refreshRedisInspector(self, filter_text: str = "") -> None:
        self._redis_inspector_filter = str(filter_text or "").strip()
        try:
            pattern = self._redis_inspector_filter or "*"
            keys = self._redis_cli("--scan", "--pattern", pattern)[:500]
            rows = []
            namespaces = {}
            for key in keys:
                key = str(key)
                namespace = key.split(":", 1)[0] if ":" in key else "default"
                namespaces.setdefault(namespace, 0)
                namespaces[namespace] += 1
                kind = (self._redis_cli("TYPE", key) or ["string"])[0]
                ttl_lines = self._redis_cli("TTL", key)
                ttl = ttl_lines[0] if ttl_lines else "-1"
                rows.append({"key": key, "namespace": namespace, "type": kind, "ttl": ttl, "present": True})
            self._redis_inspector_keys = rows
            self._redis_inspector_namespaces = [{"path": name, "label": name, "count": count} for name, count in sorted(namespaces.items())]
            if self._redis_inspector_selected_key and not any(row["key"] == self._redis_inspector_selected_key for row in rows):
                self._redis_inspector_selected_key = ""
                self._redis_inspector_selected_value = ""
                self._redis_inspector_selected_summary = ""
        except Exception as exc:
            LOGGER.debug("Unable to inspect Redis: %s", exc)
            self._redis_inspector_keys = []
            self._redis_inspector_namespaces = []
        self.redisInspectorChanged.emit()

    @Slot(str)
    def selectRedisInspectorKey(self, key: str) -> None:
        key = str(key or "")
        self._redis_inspector_selected_key = key
        try:
            row = next((item for item in self._redis_inspector_keys if item.get("key") == key), {})
            kind = str(row.get("type", "string"))
            if kind == "hash":
                raw = self._redis_cli("HGETALL", key)
                value = [f"{raw[index]}: {raw[index + 1]}" for index in range(0, len(raw) - 1, 2)]
            elif kind == "list":
                value = self._redis_cli("LRANGE", key, "0", "99")
            elif kind == "set":
                value = self._redis_cli("SMEMBERS", key)
            elif kind == "zset":
                raw = self._redis_cli("ZRANGE", key, "0", "99", "WITHSCORES")
                value = [f"{raw[index]}: {raw[index + 1]}" for index in range(0, len(raw) - 1, 2)]
            elif kind == "stream":
                value = self._redis_cli("XRANGE", key, "-", "+", "COUNT", "100")
            else:
                value = self._redis_cli("GET", key)
            self._redis_inspector_selected_value = "\n".join(value)
            self._redis_inspector_selected_summary = f"{kind} • TTL {row.get('ttl', '-1')}"
        except Exception as exc:
            self._redis_inspector_selected_value = str(exc)
            self._redis_inspector_selected_summary = "Unable to read value"
        self.redisInspectorChanged.emit()

    @Slot(str)
    def deleteRedisInspectorKey(self, key: str) -> None:
        try:
            self._redis_cli("DEL", str(key))
        finally:
            self.refreshRedisInspector(self._redis_inspector_filter)

    @Slot(str)
    def deleteRedisInspectorNamespace(self, namespace: str) -> None:
        prefix = str(namespace or "default")
        keys = [item.get("key", "") for item in self._redis_inspector_keys if item.get("namespace") == prefix]
        if keys:
            self._redis_cli("DEL", *[str(key) for key in keys])
        self.refreshRedisInspector(self._redis_inspector_filter)

    @Slot()
    def startRedisInspectorLiveUpdates(self) -> None:
        self._redis_inspector_live_updates = True
        self._redis_inspector_timer.start()

    @Slot()
    def stopRedisInspectorLiveUpdates(self) -> None:
        self._redis_inspector_live_updates = False
        self._redis_inspector_timer.stop()

    def _refresh_live_redis_inspector(self) -> None:
        if self._redis_inspector_live_updates:
            self.refreshRedisInspector(self._redis_inspector_filter)

    def _emit_mailpit_mailbox_changed(self) -> None:
        if self._mailpit_mailbox_live_updates:
            self.mailpitMailboxChanged.emit()

    @Property("QVariantList", notify=redisRuntimeFeedbackChanged)
    def redisRuntimeItems(self) -> list[dict[str, str]]:
        metadata = self._container.redis_service.runtime_metadata()
        active_runtime = metadata.get("active_runtime") or {}
        active_runtime_id = str(active_runtime.get("id", ""))
        settings = self._container.settings_service.get_settings()
        items: list[dict[str, str]] = []
        for runtime in self._container.redis_runtime_service.list_runtimes():
            is_active = runtime.id == active_runtime_id
            config_path = runtime.config_template_path or str(self._container.redis_service.config_path(runtime))
            data_path = str(self._container.redis_service.data_dir(runtime, create=False))
            items.append(
                {
                    "id": runtime.id,
                    "version": runtime.version,
                    "label": runtime.label,
                    "home": runtime.home,
                    "server_path": runtime.server_path,
                    "client_path": runtime.client_path or "",
                    "config_path": config_path,
                    "data_path": data_path,
                    "port": str(settings.redis_port),
                    "status": "Active" if is_active else "Ready",
                }
            )
        return items

    @Property("QVariantList", notify=redisRuntimeFeedbackChanged)
    def memcachedRuntimeItems(self) -> list[dict[str, str]]:
        active_runtime_id = self._container.settings_service.get_settings().active_memcached_version or ""
        items: list[dict[str, str]] = []
        for runtime in self._container.memcached_runtime_service.list_runtimes():
            is_active = runtime.id == active_runtime_id
            items.append(
                {
                    "id": runtime.id,
                    "version": runtime.version,
                    "label": runtime.label,
                    "home": runtime.home,
                    "server_path": runtime.server_path,
                    "tool_path": runtime.tool_path or "",
                    "status": "Active" if is_active else "Ready",
                }
            )
        return items

    @Property("QVariantList", notify=mailpitRuntimeFeedbackChanged)
    def mailpitRuntimeItems(self) -> list[dict[str, str]]:
        active_runtime_id = self._container.settings_service.get_settings().active_mailpit_version or ""
        items: list[dict[str, str]] = []
        for runtime in self._container.binary_locator.available_mailpit_runtimes():
            is_active = runtime.id == active_runtime_id
            items.append(
                {
                    "id": runtime.id,
                    "version": runtime.version,
                    "label": runtime.label,
                    "home": runtime.home,
                    "server_path": runtime.server_path,
                    "status": "Active" if is_active else "Ready",
                }
            )
        return items

    @Slot(str, result=bool)
    def updateRedisRuntimePort(self, redis_port: str) -> bool:
        try:
            current = self._container.settings_service.get_settings()
            normalized_redis_port = self._parse_port_value(redis_port, "Redis")
            current_port = int(current.redis_port)
            if normalized_redis_port != current_port and not self._is_tcp_port_available(normalized_redis_port):
                raise ValueError(f"Port {normalized_redis_port} is already in use.")
            settings = self._copy_settings(
                current,
                redis_port=normalized_redis_port,
            )
            self._container.settings_service.save_settings(settings)
            self._redis_runtime_message = (
                f"Redis port saved as {normalized_redis_port}. Restart Redis runtime to apply."
            )
            self._redis_runtime_error = False
            self.dataChanged.emit()
            self.redisRuntimeFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._redis_runtime_message = str(exc)
            self._redis_runtime_error = True
            self.redisRuntimeFeedbackChanged.emit()
            return False

    @Slot(str, str, result=bool)
    def updateMailpitRuntimePorts(self, smtp_port: str, http_port: str) -> bool:
        try:
            current = self._container.settings_service.get_settings()
            normalized_smtp_port = self._parse_port_value(smtp_port, "Mailpit SMTP")
            normalized_http_port = self._parse_port_value(http_port, "Mailpit Web")

            current_smtp_port = int(current.mailpit_smtp_port)
            current_http_port = int(current.mailpit_http_port)

            if normalized_smtp_port != current_smtp_port and not self._is_tcp_port_available(normalized_smtp_port):
                raise ValueError(f"Port {normalized_smtp_port} is already in use.")
            if normalized_http_port != current_http_port and not self._is_tcp_port_available(normalized_http_port):
                raise ValueError(f"Port {normalized_http_port} is already in use.")

            settings = self._copy_settings(
                current,
                mailpit_smtp_port=normalized_smtp_port,
                mailpit_http_port=normalized_http_port,
            )
            self._container.settings_service.save_settings(settings)
            self._mailpit_runtime_message = (
                f"Mailpit ports saved (SMTP {normalized_smtp_port}, Web {normalized_http_port}). Restart Mailpit to apply."
            )
            self._mailpit_runtime_error = False
            self.dataChanged.emit()
            self.mailpitRuntimeFeedbackChanged.emit()
            self.appSettingsFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._mailpit_runtime_message = str(exc)
            self._mailpit_runtime_error = True
            self.mailpitRuntimeFeedbackChanged.emit()
            return False

    @Property(str, notify=redisRuntimeFeedbackChanged)
    def activeRedisRuntimeLabel(self) -> str:
        runtime = self._container.redis_service.active_runtime()
        if runtime is None:
            return "No runtime selected"
        return f"Redis {runtime.version}"

    @Property(str, notify=redisRuntimeFeedbackChanged)
    def activeRedisRuntimeHome(self) -> str:
        runtime = self._container.redis_service.active_runtime()
        return runtime.home if runtime else ""

    @Property(str, notify=redisRuntimeFeedbackChanged)
    def activeRedisDataDir(self) -> str:
        runtime = self._container.redis_service.active_runtime()
        return str(self._container.redis_service.data_dir(runtime, create=False))

    @Property(str, notify=redisRuntimeFeedbackChanged)
    def activeRedisConfigPath(self) -> str:
        runtime = self._container.redis_service.active_runtime()
        return str(self._container.redis_service.config_path(runtime))

    @Property(str, notify=redisRuntimeFeedbackChanged)
    def activeRedisConfigContent(self) -> str:
        runtime = self._container.redis_service.active_runtime()
        path = self._container.redis_service.config_path(runtime)
        try:
            if path.exists():
                return path.read_text(encoding="utf-8")
        except Exception:
            pass
        return ""

    def _redis_config_path(self) -> Path:
        runtime = self._container.redis_service.active_runtime()
        return self._container.redis_service.config_path(runtime)

    def _redis_config_original_backup_path(self) -> Path:
        path = self._redis_config_path()
        return path.with_suffix(path.suffix + ".original")

    def _redis_config_last_backup_path(self) -> Path:
        path = self._redis_config_path()
        return path.with_suffix(path.suffix + ".bak")

    @Slot(str, result=bool)
    def saveActiveRedisConfigContent(self, content: str) -> bool:
        try:
            config_path = self._redis_config_path()
            config_path.parent.mkdir(parents=True, exist_ok=True)
            current_text = config_path.read_text(encoding="utf-8") if config_path.exists() else ""

            original_backup = self._redis_config_original_backup_path()
            last_backup = self._redis_config_last_backup_path()

            if config_path.exists() and not original_backup.exists():
                original_backup.write_text(current_text, encoding="utf-8")
            if config_path.exists():
                last_backup.write_text(current_text, encoding="utf-8")

            config_path.write_text(str(content), encoding="utf-8")
            self._redis_runtime_message = (
                f"Saved redis config with backup.\nOriginal: {original_backup}\nLatest backup: {last_backup}"
            )
            self._redis_runtime_error = False
            self.redisRuntimeFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._redis_runtime_message = str(exc)
            self._redis_runtime_error = True
            self.redisRuntimeFeedbackChanged.emit()
            return False

    @Slot(result=bool)
    def restoreActiveRedisConfigOriginal(self) -> bool:
        try:
            config_path = self._redis_config_path()
            original_backup = self._redis_config_original_backup_path()
            if not original_backup.exists():
                raise ValueError("Original backup not found. Save the config once first.")
            current_text = config_path.read_text(encoding="utf-8") if config_path.exists() else ""
            self._redis_config_last_backup_path().write_text(current_text, encoding="utf-8")
            config_path.write_text(original_backup.read_text(encoding="utf-8"), encoding="utf-8")
            self._redis_runtime_message = f"Restored original config from {original_backup}"
            self._redis_runtime_error = False
            self.redisRuntimeFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._redis_runtime_message = str(exc)
            self._redis_runtime_error = True
            self.redisRuntimeFeedbackChanged.emit()
            return False

    @Property(str, notify=redisRuntimeFeedbackChanged)
    def activeRedisPort(self) -> str:
        return str(self._container.settings_service.get_settings().redis_port)

    @Property(str, notify=redisRuntimeFeedbackChanged)
    def activeRedisServiceState(self) -> str:
        return getattr(self, "_redis_service_state_cache", "Stopped")

    @Property(str, notify=redisRuntimeFeedbackChanged)
    def redisPassword(self) -> str:
        return self._container.redis_service.password()

    @Property(str, notify=redisRuntimeFeedbackChanged)
    def redisRuntimeMessage(self) -> str:
        return self._redis_runtime_message

    @Property(bool, notify=redisRuntimeFeedbackChanged)
    def redisRuntimeError(self) -> bool:
        return self._redis_runtime_error

    @Property(str, notify=redisRuntimeFeedbackChanged)
    def redisRuntimeLog(self) -> str:
        return self._redis_runtime_log

    @Property(str, notify=redisRuntimeFeedbackChanged)
    def activeMemcachedRuntimeLabel(self) -> str:
        runtime = self._container.memcached_service.active_runtime()
        if runtime is None:
            return "No runtime selected"
        return f"Memcached {runtime.version}"

    @Property(str, notify=redisRuntimeFeedbackChanged)
    def activeMemcachedRuntimeHome(self) -> str:
        runtime = self._container.memcached_service.active_runtime()
        return runtime.home if runtime else ""

    @Property(str, notify=redisRuntimeFeedbackChanged)
    def activeMemcachedDataDir(self) -> str:
        runtime = self._container.memcached_service.active_runtime()
        return str(self._container.memcached_service.data_dir(runtime, create=False))

    @Property(str, notify=redisRuntimeFeedbackChanged)
    def activeMemcachedConfigPath(self) -> str:
        runtime = self._container.memcached_service.active_runtime()
        return str(self._container.memcached_service.config_path(runtime))

    @Property(str, notify=redisRuntimeFeedbackChanged)
    def activeMemcachedConfigContent(self) -> str:
        runtime = self._container.memcached_service.active_runtime()
        path = self._container.memcached_service.config_path(runtime)
        try:
            if path.exists():
                return path.read_text(encoding="utf-8")
        except Exception:
            pass
        return ""

    def _memcached_config_path(self) -> Path:
        runtime = self._container.memcached_service.active_runtime()
        return self._container.memcached_service.config_path(runtime)

    def _memcached_config_original_backup_path(self) -> Path:
        path = self._memcached_config_path()
        return path.with_suffix(path.suffix + ".original")

    def _memcached_config_last_backup_path(self) -> Path:
        path = self._memcached_config_path()
        return path.with_suffix(path.suffix + ".bak")

    @Slot(str, result=bool)
    def saveActiveMemcachedConfigContent(self, content: str) -> bool:
        try:
            config_path = self._memcached_config_path()
            config_path.parent.mkdir(parents=True, exist_ok=True)
            current_text = config_path.read_text(encoding="utf-8") if config_path.exists() else ""

            original_backup = self._memcached_config_original_backup_path()
            last_backup = self._memcached_config_last_backup_path()

            if config_path.exists() and not original_backup.exists():
                original_backup.write_text(current_text, encoding="utf-8")
            if config_path.exists():
                last_backup.write_text(current_text, encoding="utf-8")

            config_path.write_text(str(content), encoding="utf-8")
            self._memcached_runtime_message = (
                f"Saved Memcached config with backup.\nOriginal: {original_backup}\nLatest backup: {last_backup}"
            )
            self._memcached_runtime_error = False
            self.redisRuntimeFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._memcached_runtime_message = str(exc)
            self._memcached_runtime_error = True
            self.redisRuntimeFeedbackChanged.emit()
            return False

    @Slot(result=bool)
    def restoreActiveMemcachedConfigOriginal(self) -> bool:
        try:
            config_path = self._memcached_config_path()
            original_backup = self._memcached_config_original_backup_path()
            if not original_backup.exists():
                raise ValueError("Original backup not found. Save the config once first.")
            current_text = config_path.read_text(encoding="utf-8") if config_path.exists() else ""
            self._memcached_config_last_backup_path().write_text(current_text, encoding="utf-8")
            config_path.write_text(original_backup.read_text(encoding="utf-8"), encoding="utf-8")
            self._memcached_runtime_message = f"Restored original config from {original_backup}"
            self._memcached_runtime_error = False
            self.redisRuntimeFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._memcached_runtime_message = str(exc)
            self._memcached_runtime_error = True
            self.redisRuntimeFeedbackChanged.emit()
            return False

    @Property(str, notify=redisRuntimeFeedbackChanged)
    def activeMemcachedPort(self) -> str:
        return str(self._container.memcached_service.port())

    @Property(str, notify=redisRuntimeFeedbackChanged)
    def activeMemcachedServiceState(self) -> str:
        return getattr(self, "_memcached_service_state_cache", "Stopped")

    @Property(str, notify=redisRuntimeFeedbackChanged)
    def memcachedRuntimeMessage(self) -> str:
        return self._memcached_runtime_message

    @Property(bool, notify=redisRuntimeFeedbackChanged)
    def memcachedRuntimeError(self) -> bool:
        return self._memcached_runtime_error

    @Property(str, notify=redisRuntimeFeedbackChanged)
    def memcachedRuntimeLog(self) -> str:
        return self._memcached_runtime_log

    @Property(str, notify=mailpitRuntimeFeedbackChanged)
    def mailpitRuntimeMessage(self) -> str:
        return self._mailpit_runtime_message

    @Property(bool, notify=mailpitRuntimeFeedbackChanged)
    def mailpitRuntimeError(self) -> bool:
        return self._mailpit_runtime_error

    @Property(str, notify=mailpitRuntimeFeedbackChanged)
    def mailpitRuntimeLog(self) -> str:
        return self._mailpit_runtime_log

    @Property(str, notify=mailpitRuntimeFeedbackChanged)
    def mailpitSmtpPort(self) -> str:
        return str(self._container.settings_service.get_settings().mailpit_smtp_port)

    @Property(str, notify=mailpitRuntimeFeedbackChanged)
    def mailpitHttpPort(self) -> str:
        return str(self._container.settings_service.get_settings().mailpit_http_port)

    @Property(str, notify=mailpitRuntimeFeedbackChanged)
    def mailpitWebUrl(self) -> str:
        return self._container.mailpit_service.web_url()

    @Property(str, notify=mailpitRuntimeFeedbackChanged)
    def mailpitServiceState(self) -> str:
        return getattr(self, "_mailpit_service_state_cache", "Stopped")

    @Slot()
    def startMailpitRuntime(self) -> None:
        LOGGER.debug("startMailpitRuntime: busy=%s", self._mailpit_action_busy)
        if self._mailpit_action_busy:
            return
        self._mailpit_action_busy = True
        self._start_mailpit_action_job("start")
        self._defer_action_state_changed()

    @Slot()
    def stopMailpitRuntime(self) -> None:
        LOGGER.debug("stopMailpitRuntime: busy=%s", self._mailpit_action_busy)
        if self._mailpit_action_busy:
            return
        self._mailpit_action_busy = True
        self._start_mailpit_action_job("stop")
        self._defer_action_state_changed()

    @Slot()
    def restartMailpitRuntime(self) -> None:
        LOGGER.debug("restartMailpitRuntime: busy=%s", self._mailpit_action_busy)
        if self._mailpit_action_busy:
            return
        self._mailpit_action_busy = True
        self._start_mailpit_action_job("restart")
        self._defer_action_state_changed()

    @Slot()
    def refreshMailpitRuntime(self) -> None:
        self._mailpit_runtime_log = self._container.mailpit_service.read_log_tail()
        self.mailpitRuntimeFeedbackChanged.emit()

    @Slot()
    def openMailpit(self) -> None:
        import webbrowser
        webbrowser.open(self._container.mailpit_service.web_url())

    @Slot(str, result=bool)
    def updateRedisPassword(self, new_password: str) -> bool:
        result = self._container.redis_service.update_password(new_password)
        self._apply_redis_runtime_feedback(result)
        return result.success

    @Slot()
    def clearRedisRuntimeFeedback(self) -> None:
        self._redis_runtime_message = ""
        self._redis_runtime_error = False
        self.redisRuntimeFeedbackChanged.emit()

    @Slot(str, result=bool)
    def saveRedisRuntimeSelection(self, runtime_id: str) -> bool:
        try:
            current = self._container.settings_service.get_settings()
            settings = self._copy_settings(current, active_redis_version=runtime_id.strip() or None)
            success_message = "Redis runtime selection saved. Restart Redis to use the new version."
            self._container.settings_service.save_settings(settings)
            self._redis_runtime_message = success_message
            self._redis_runtime_error = False
            self.dataChanged.emit()
            self.redisRuntimeFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._redis_runtime_message = str(exc)
            self._redis_runtime_error = True
            self.redisRuntimeFeedbackChanged.emit()
            return False

    @Slot(str, result=bool)
    def saveMemcachedRuntimeSelection(self, runtime_id: str) -> bool:
        try:
            current = self._container.settings_service.get_settings()
            settings = self._copy_settings(current, active_memcached_version=runtime_id.strip() or None)
            self._container.settings_service.save_settings(settings)
            self._memcached_runtime_message = "Memcached runtime selection saved. Restart Memcached to use the new version."
            self._memcached_runtime_error = False
            self.dataChanged.emit()
            self.redisRuntimeFeedbackChanged.emit()
            self.appSettingsFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._memcached_runtime_message = str(exc)
            self._memcached_runtime_error = True
            self.redisRuntimeFeedbackChanged.emit()
            return False

    def _start_mailpit_action_job(self, action: str) -> None:
        LOGGER.debug("_start_mailpit_action_job: action=%s busy=%s", action, self._mailpit_action_busy)
        thread = QThread(self)
        worker = MailpitActionWorker(self._container, action)
        worker.moveToThread(thread)
        worker.completed.connect(self._on_mailpit_action_completed)
        worker.completed.connect(thread.quit)
        thread.started.connect(worker.run)
        thread.finished.connect(worker.deleteLater)
        thread.finished.connect(thread.deleteLater)
        self._mailpit_action_thread = thread
        self._mailpit_action_worker = worker
        thread.start()

    @Slot(str, bool, str)
    def _on_mailpit_action_completed(self, action: str, success: bool, message: str) -> None:
        LOGGER.debug(
            "_on_mailpit_action_completed: action=%s success=%s message=%s",
            action,
            success,
            message,
        )
        if action == "stop" and success:
            self._mailpit_service_state_cache = "Stopped"
        elif action in {"start", "restart"} and success:
            self._mailpit_service_state_cache = "Running"
        # Use final observed state to suppress false negative stop errors.
        final_state = getattr(self, "_mailpit_service_state_cache", "Stopped").lower()
        if action == "stop" and final_state == "stopped":
            success = True
            message = "Mailpit stopped."
        if action == "start" and final_state == "running":
            success = True
        self._mailpit_runtime_message = message
        self._mailpit_runtime_error = not success
        self._mailpit_runtime_log = self._container.mailpit_service.read_log_tail()
        self._mailpit_action_busy = False
        self._mailpit_action_thread = None
        self._mailpit_action_worker = None
        self.mailpitRuntimeFeedbackChanged.emit()
        self.dataChanged.emit()
        self._defer_action_state_changed()

    @Slot(bool, str)
    def _on_redis_restart_completed(self, success: bool, message: str) -> None:
        LOGGER.debug("_on_redis_restart_completed: success=%s message=%s", success, message)
        self._redis_runtime_message = message
        self._redis_runtime_error = not success
        self._redis_runtime_log = self._container.redis_service.read_log_tail()
        self._redis_service_state_cache = "Running" if success else getattr(self, "_redis_service_state_cache", "Stopped")
        self._redis_action_busy = False
        self._redis_restart_thread = None
        self._redis_restart_worker = None
        self.redisRuntimeFeedbackChanged.emit()
        self.dataChanged.emit()
        self._defer_action_state_changed()

    @Slot(bool, str)
    def _on_memcached_restart_completed(self, success: bool, message: str) -> None:
        LOGGER.debug("_on_memcached_restart_completed: success=%s message=%s", success, message)
        self._memcached_runtime_message = message
        self._memcached_runtime_error = not success
        self._memcached_runtime_log = self._container.memcached_service.read_log_tail()
        self._memcached_service_state_cache = "Running" if success else getattr(self, "_memcached_service_state_cache", "Stopped")
        self._memcached_action_busy = False
        self._memcached_restart_thread = None
        self._memcached_restart_worker = None
        self.redisRuntimeFeedbackChanged.emit()
        self.dataChanged.emit()
        self._defer_action_state_changed()

    @Slot()
    def startRedisRuntime(self) -> None:
        LOGGER.debug("startRedisRuntime: busy=%s", self._redis_action_busy)
        self.setHomeServiceRunning("redis", True)

    @Slot()
    def stopRedisRuntime(self) -> None:
        LOGGER.debug("stopRedisRuntime: busy=%s", self._redis_action_busy)
        self.setHomeServiceRunning("redis", False)

    @Slot()
    def restartRedisRuntime(self) -> None:
        LOGGER.debug("restartRedisRuntime: busy=%s", self._redis_action_busy)
        if self._redis_action_busy:
            return
        self._redis_action_busy = True
        thread = QThread(self)
        worker = RedisRestartWorker(self._container)
        worker.moveToThread(thread)
        worker.completed.connect(self._on_redis_restart_completed)
        worker.completed.connect(thread.quit)
        thread.started.connect(worker.run)
        thread.finished.connect(worker.deleteLater)
        thread.finished.connect(thread.deleteLater)
        self._redis_restart_thread = thread
        self._redis_restart_worker = worker
        thread.start()
        self._defer_action_state_changed()

    @Slot()
    def refreshMemcachedRuntime(self) -> None:
        runtime = self._container.memcached_service.active_runtime()
        if runtime is None and not self._memcached_runtime_message:
            self._memcached_runtime_message = "No active Memcached runtime selected."
            self._memcached_runtime_error = True
        self._memcached_runtime_log = self._container.memcached_service.read_log_tail()
        self.dataChanged.emit()
        self.redisRuntimeFeedbackChanged.emit()

    @Slot(result="QVariantMap")
    def memcachedConfigSettings(self) -> dict[str, object]:
        settings = self._container.memcached_service.read_config_settings()
        return {
            "host": str(settings.get("host", "127.0.0.1")),
            "port": int(settings.get("port", 11211)),
        }

    @Slot(str, int, result=bool)
    def saveMemcachedConfigSettings(self, host: str, port: int) -> bool:
        result = self._container.memcached_service.save_config_settings(host, int(port))
        self._memcached_runtime_message = result.message
        self._memcached_runtime_error = not result.success
        self.redisRuntimeFeedbackChanged.emit()
        self.dataChanged.emit()
        return bool(result.success)

    @Slot(str, result=bool)
    def updateMemcachedRuntimePort(self, memcached_port: str) -> bool:
        try:
            normalized_memcached_port = self._parse_port_value(memcached_port, "Memcached")
            current_port = int(self._container.memcached_service.port())
            if normalized_memcached_port != current_port and not self._is_tcp_port_available(normalized_memcached_port):
                raise ValueError(f"Port {normalized_memcached_port} is already in use.")
            settings = self._container.memcached_service.read_config_settings()
            host = str(settings.get("host", "127.0.0.1"))
            result = self._container.memcached_service.save_config_settings(host, normalized_memcached_port)
            if not result.success:
                raise ValueError(result.message)
            self._memcached_runtime_message = (
                f"Memcached port saved as {normalized_memcached_port}. Restart Memcached runtime to apply."
            )
            self._memcached_runtime_error = False
            self.redisRuntimeFeedbackChanged.emit()
            self.dataChanged.emit()
            return True
        except Exception as exc:
            self._memcached_runtime_message = str(exc)
            self._memcached_runtime_error = True
            self.redisRuntimeFeedbackChanged.emit()
            return False

    @Slot()
    def startMemcachedRuntime(self) -> None:
        LOGGER.debug("startMemcachedRuntime: busy=%s", self._memcached_action_busy)
        self.setHomeServiceRunning("memcached", True)

    @Slot()
    def stopMemcachedRuntime(self) -> None:
        LOGGER.debug("stopMemcachedRuntime: busy=%s", self._memcached_action_busy)
        self.setHomeServiceRunning("memcached", False)

    @Slot()
    def restartMemcachedRuntime(self) -> None:
        LOGGER.debug("restartMemcachedRuntime: busy=%s", self._memcached_action_busy)
        if self._memcached_action_busy:
            return
        self._memcached_action_busy = True
        thread = QThread(self)
        worker = MemcachedRestartWorker(self._container)
        worker.moveToThread(thread)
        worker.completed.connect(self._on_memcached_restart_completed)
        worker.completed.connect(thread.quit)
        thread.started.connect(worker.run)
        thread.finished.connect(worker.deleteLater)
        thread.finished.connect(thread.deleteLater)
        self._memcached_restart_thread = thread
        self._memcached_restart_worker = worker
        thread.start()
        self._defer_action_state_changed()

    @Slot()
    def refreshRedisRuntime(self) -> None:
        runtime = self._container.redis_service.active_runtime()
        if runtime is None and not self._redis_runtime_message:
            self._redis_runtime_message = "No active Redis runtime selected."
            self._redis_runtime_error = True
        self._redis_runtime_log = self._container.redis_service.read_log_tail()
        if runtime is None and not self._redis_runtime_message:
            self._redis_runtime_error = True
        self.dataChanged.emit()
        self.redisRuntimeFeedbackChanged.emit()

    def _apply_redis_runtime_feedback(self, result) -> None:
        self._redis_runtime_message = result.message
        self._redis_runtime_error = not result.success
        self._redis_runtime_log = self._container.redis_service.read_log_tail()
        self.dataChanged.emit()
        self.redisRuntimeFeedbackChanged.emit()

    def _apply_mailpit_runtime_feedback(self, result) -> None:
        self._mailpit_runtime_message = result.message
        self._mailpit_runtime_error = not result.success
        self._mailpit_runtime_log = self._container.mailpit_service.read_log_tail()
        self.mailpitRuntimeFeedbackChanged.emit()
        self.dataChanged.emit()

    @Slot()
    def sendMailpitTestEmail(self) -> None:
        import smtplib
        from email.message import EmailMessage

        try:
            settings = self._container.settings_service.get_settings()

            message = EmailMessage()
            message["From"] = "server-engine@local.engine"
            message["To"] = "test@example.engine"
            message["Subject"] = "Server Engine Mailpit Test"
            message.set_content("Hello from Server Engine. Mailpit is working.")

            with smtplib.SMTP("127.0.0.1", settings.mailpit_smtp_port, timeout=5) as smtp:
                smtp.send_message(message)

            self._mailpit_runtime_message = "Test email sent to Mailpit."
            self._mailpit_runtime_error = False
            self._mailpit_runtime_log = self._container.mailpit_service.read_log_tail()
        except Exception as exc:
            self._mailpit_runtime_message = str(exc)
            self._mailpit_runtime_error = True

        self.mailpitRuntimeFeedbackChanged.emit()
        self.dataChanged.emit()
