from ._shared import *


class AppSettingsMixin(DashboardBridgeSignals):
    @Property(str, notify=appSettingsFeedbackChanged)
    def settingsCacheDriver(self) -> str:
        return self._container.settings_service.get_settings().cache_driver

    @Property(str, notify=appSettingsFeedbackChanged)
    def settingsMemcachedRuntime(self) -> str:
        return self._container.settings_service.get_settings().active_memcached_version or ""

    @Property(str, notify=appSettingsFeedbackChanged)
    def settingsDatabaseEngine(self) -> str:
        return self._container.settings_service.get_settings().preferred_database_engine

    @Property(str, notify=appSettingsFeedbackChanged)
    def settingsWebServer(self) -> str:
        return self._container.settings_service.get_settings().active_web_server.value

    @Property(str, notify=appSettingsFeedbackChanged)
    def settingsApacheRuntime(self) -> str:
        settings = self._container.settings_service.get_settings()
        return settings.active_apache_version or self._container.binary_locator.apache_home().name

    @Property(str, notify=appSettingsFeedbackChanged)
    def settingsNginxRuntime(self) -> str:
        settings = self._container.settings_service.get_settings()
        return settings.active_nginx_version or self._container.binary_locator.nginx_home().name

    @Slot(str, result="QVariantList")
    def webServerRuntimeItems(self, service: str) -> list[dict[str, str]]:
        service_id = service.strip().lower()
        items: list[dict[str, str]] = []
        if service_id == "apache":
            settings = self._container.settings_service.get_settings()
            active_runtime_id = settings.active_apache_version or ""
            apache_runtimes = self._container.binary_locator.available_apache_runtimes()
            for home in apache_runtimes:
                version = home.name.removeprefix("apache-").lstrip("-")
                is_active = home.name == active_runtime_id or (not active_runtime_id and len(apache_runtimes) == 1)
                items.append(
                    {
                        "id": home.name,
                        "version": version,
                        "label": home.name,
                        "home": str(home),
                        "status": "Active" if is_active else "Ready",
                    }
                )
        elif service_id == "nginx":
            settings = self._container.settings_service.get_settings()
            active_runtime_id = settings.active_nginx_version or ""
            nginx_runtimes = self._container.binary_locator.available_nginx_runtimes()
            for home in nginx_runtimes:
                version = home.name.removeprefix("nginx-").lstrip("-")
                is_active = home.name == active_runtime_id or (not active_runtime_id and len(nginx_runtimes) == 1)
                items.append(
                    {
                        "id": home.name,
                        "version": version,
                        "label": home.name,
                        "home": str(home),
                        "status": "Active" if is_active else "Ready",
                    }
                )
        return items

    @Property(str, notify=appSettingsFeedbackChanged)
    def settingsApacheErrorLogPath(self) -> str:
        return self._container.settings_service.get_settings().apache_error_log_path

    @Property(str, notify=appSettingsFeedbackChanged)
    def activeApacheConfigPath(self) -> str:
        return str(self._container.config_service.apache_main_config_path())

    @Property(str, notify=appSettingsFeedbackChanged)
    def activeApacheConfigContent(self) -> str:
        path = self._container.config_service.apache_main_config_path()
        try:
            if path.exists():
                return path.read_text(encoding="utf-8")
        except Exception:
            pass
        return ""

    @Property(str, notify=appSettingsFeedbackChanged)
    def apacheRuntimeMessage(self) -> str:
        return getattr(self, "_apache_runtime_message", "")

    @Property(bool, notify=appSettingsFeedbackChanged)
    def apacheRuntimeError(self) -> bool:
        return getattr(self, "_apache_runtime_error", False)

    @Property(str, notify=appSettingsFeedbackChanged)
    def apacheRuntimeLog(self) -> str:
        path = self._container.settings_service.get_settings().apache_error_log_path.strip()
        if path:
            log_path = Path(path)
        else:
            log_path = self._container.config_service.apache_logs_dir() / "httpd-error.log"
        try:
            if not log_path.exists():
                return ""
            return "\n".join(log_path.read_text(encoding="utf-8", errors="replace").splitlines()[-120:])
        except Exception:
            return ""

    @Property(str, notify=appSettingsFeedbackChanged)
    def apacheRuntimeLogPath(self) -> str:
        path = self._container.settings_service.get_settings().apache_error_log_path.strip()
        if path:
            return path
        return str(self._container.config_service.apache_logs_dir() / "httpd-error.log")

    @Slot(int, bool, result=str)
    def apacheRuntimeLogContent(self, lines: int, tail_mode: bool) -> str:
        path = self._container.settings_service.get_settings().apache_error_log_path.strip()
        if path:
            return self.readFileLogContent(path, lines, tail_mode)
        return self.readFileLogContent(str(self._container.config_service.apache_logs_dir() / "httpd-error.log"), lines, tail_mode)

    @Slot(str, int, bool, result=str)
    def readFileLogContent(self, path: str, lines: int, tail_mode: bool) -> str:
        try:
            cleaned_lines = max(1, min(int(lines), 2000))
            path_value = str(path).strip()
            if not path_value:
                return ""
            log_path = Path(path_value)
            if not log_path.exists():
                return ""
            text = log_path.read_text(encoding="utf-8", errors="replace")
            if not tail_mode:
                return text
            rows = text.splitlines()
            return "\n".join(rows[-cleaned_lines:])
        except Exception as exc:
            return f"Unable to load log: {exc}"

    def _apache_config_path(self) -> Path:
        return self._container.config_service.apache_main_config_path()

    def _apache_config_original_backup_path(self) -> Path:
        path = self._apache_config_path()
        return path.with_suffix(path.suffix + ".original")

    def _apache_config_last_backup_path(self) -> Path:
        path = self._apache_config_path()
        return path.with_suffix(path.suffix + ".bak")

    @Slot(str, result=bool)
    def testActiveApacheConfigDraft(self, content: str) -> bool:
        """Validate unsaved Apache text without replacing the active config."""
        temporary_path = None
        try:
            with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".conf", delete=False) as handle:
                handle.write(str(content or ""))
                temporary_path = Path(handle.name)
            command = [
                str(self._container.binary_locator.apache_httpd()),
                "-t",
                "-f",
                str(temporary_path),
                "-d",
                str(self._container.binary_locator.apache_home()),
            ]
            result = subprocess.run(command, capture_output=True, text=True, check=False)
            output = (result.stdout or "").strip()
            error = (result.stderr or "").strip()
            if result.returncode == 0:
                self._apache_runtime_message = ("Apache draft config test passed.\n" + output).strip()
                self._apache_runtime_error = False
            else:
                self._apache_runtime_message = "Apache draft config test failed.\n" + (error or output or f"Exit code {result.returncode}")
                self._apache_runtime_error = True
            self.appSettingsFeedbackChanged.emit()
            return result.returncode == 0
        except Exception as exc:
            self._apache_runtime_message = f"Apache draft config test failed: {exc}"
            self._apache_runtime_error = True
            self.appSettingsFeedbackChanged.emit()
            return False
        finally:
            if temporary_path is not None:
                temporary_path.unlink(missing_ok=True)

    @Slot(str, result=bool)
    def saveActiveApacheConfigContent(self, content: str) -> bool:
        try:
            config_path = self._apache_config_path()
            config_path.parent.mkdir(parents=True, exist_ok=True)
            current_text = config_path.read_text(encoding="utf-8") if config_path.exists() else ""

            original_backup = self._apache_config_original_backup_path()
            last_backup = self._apache_config_last_backup_path()

            if config_path.exists() and not original_backup.exists():
                original_backup.write_text(current_text, encoding="utf-8")
            if config_path.exists():
                last_backup.write_text(current_text, encoding="utf-8")

            config_path.write_text(str(content), encoding="utf-8")
            self._apache_runtime_message = (
                f"Saved Apache config with backup.\nOriginal: {original_backup}\nLatest backup: {last_backup}"
            )
            self._apache_runtime_error = False
            self.appSettingsFeedbackChanged.emit()
            self.dataChanged.emit()
            return True
        except Exception as exc:
            self._apache_runtime_message = str(exc)
            self._apache_runtime_error = True
            self.appSettingsFeedbackChanged.emit()
            return False

    @Slot(result=bool)
    def restoreActiveApacheConfigOriginal(self) -> bool:
        try:
            config_path = self._apache_config_path()
            original_backup = self._apache_config_original_backup_path()
            if not original_backup.exists():
                raise ValueError("Original backup not found. Save the config once first.")
            current_text = config_path.read_text(encoding="utf-8") if config_path.exists() else ""
            self._apache_config_last_backup_path().write_text(current_text, encoding="utf-8")
            config_path.write_text(original_backup.read_text(encoding="utf-8"), encoding="utf-8")
            self._apache_runtime_message = f"Restored original config from {original_backup}"
            self._apache_runtime_error = False
            self.appSettingsFeedbackChanged.emit()
            self.dataChanged.emit()
            return True
        except Exception as exc:
            self._apache_runtime_message = str(exc)
            self._apache_runtime_error = True
            self.appSettingsFeedbackChanged.emit()
            return False

    @Property(str, notify=appSettingsFeedbackChanged)
    def settingsNginxWorkerProcesses(self) -> str:
        return self._container.settings_service.get_settings().nginx_worker_processes

    @Property(str, notify=appSettingsFeedbackChanged)
    def settingsNginxWorkerConnections(self) -> str:
        return str(self._container.settings_service.get_settings().nginx_worker_connections)

    @Property(str, notify=appSettingsFeedbackChanged)
    def settingsNginxKeepaliveTimeout(self) -> str:
        return str(self._container.settings_service.get_settings().nginx_keepalive_timeout)

    @Property(str, notify=appSettingsFeedbackChanged)
    def settingsNginxClientMaxBodySize(self) -> str:
        return self._container.settings_service.get_settings().nginx_client_max_body_size

    @Property(bool, notify=appSettingsFeedbackChanged)
    def settingsNginxSendfile(self) -> bool:
        return bool(self._container.settings_service.get_settings().nginx_sendfile)

    @Property(bool, notify=appSettingsFeedbackChanged)
    def settingsNginxGzip(self) -> bool:
        return bool(self._container.settings_service.get_settings().nginx_gzip)

    @Property(bool, notify=appSettingsFeedbackChanged)
    def settingsNginxServerTokens(self) -> bool:
        return bool(self._container.settings_service.get_settings().nginx_server_tokens)

    @Property(str, notify=appSettingsFeedbackChanged)
    def settingsNginxErrorLogPath(self) -> str:
        return self._container.settings_service.get_settings().nginx_error_log_path

    @Property(str, notify=appSettingsFeedbackChanged)
    def settingsNginxGlobalDirectives(self) -> str:
        return str(getattr(self._container.settings_service.get_settings(), "nginx_global_directives", "") or "")

    @Property(str, notify=appSettingsFeedbackChanged)
    def activeNginxConfigPath(self) -> str:
        return str(self._container.config_service.nginx_main_config_path())

    @Property(str, notify=appSettingsFeedbackChanged)
    def activeNginxConfigContent(self) -> str:
        path = self._container.config_service.nginx_main_config_path()
        try:
            if path.exists():
                return path.read_text(encoding="utf-8")
        except Exception:
            pass
        return ""

    @Property(str, notify=appSettingsFeedbackChanged)
    def nginxRuntimeMessage(self) -> str:
        return getattr(self, "_nginx_runtime_message", "")

    @Property(bool, notify=appSettingsFeedbackChanged)
    def nginxRuntimeError(self) -> bool:
        return getattr(self, "_nginx_runtime_error", False)

    @Property(str, notify=appSettingsFeedbackChanged)
    def nginxRuntimeLog(self) -> str:
        path = self._container.settings_service.get_settings().nginx_error_log_path.strip()
        if path:
            log_path = Path(path)
        else:
            log_path = self._container.config_service.nginx_logs_dir() / "nginx-error.log"
        try:
            if not log_path.exists():
                return ""
            return "\n".join(log_path.read_text(encoding="utf-8", errors="replace").splitlines()[-120:])
        except Exception:
            return ""

    def _nginx_config_path(self) -> Path:
        return self._container.config_service.nginx_main_config_path()

    def _nginx_config_original_backup_path(self) -> Path:
        path = self._nginx_config_path()
        return path.with_suffix(path.suffix + ".original")

    def _nginx_config_last_backup_path(self) -> Path:
        path = self._nginx_config_path()
        return path.with_suffix(path.suffix + ".bak")

    @Slot(str, result=bool)
    def saveActiveNginxConfigContent(self, content: str) -> bool:
        try:
            config_path = self._nginx_config_path()
            config_path.parent.mkdir(parents=True, exist_ok=True)
            current_text = config_path.read_text(encoding="utf-8") if config_path.exists() else ""

            original_backup = self._nginx_config_original_backup_path()
            last_backup = self._nginx_config_last_backup_path()

            if config_path.exists() and not original_backup.exists():
                original_backup.write_text(current_text, encoding="utf-8")
            if config_path.exists():
                last_backup.write_text(current_text, encoding="utf-8")

            config_path.write_text(str(content), encoding="utf-8")
            self._nginx_runtime_message = (
                f"Saved Nginx config with backup.\nOriginal: {original_backup}\nLatest backup: {last_backup}"
            )
            self._nginx_runtime_error = False
            self.appSettingsFeedbackChanged.emit()
            self.dataChanged.emit()
            return True
        except Exception as exc:
            self._nginx_runtime_message = str(exc)
            self._nginx_runtime_error = True
            self.appSettingsFeedbackChanged.emit()
            return False

    @Slot(result=bool)
    def restoreActiveNginxConfigOriginal(self) -> bool:
        try:
            config_path = self._nginx_config_path()
            original_backup = self._nginx_config_original_backup_path()
            if not original_backup.exists():
                raise ValueError("Original backup not found. Save the config once first.")
            current_text = config_path.read_text(encoding="utf-8") if config_path.exists() else ""
            self._nginx_config_last_backup_path().write_text(current_text, encoding="utf-8")
            config_path.write_text(original_backup.read_text(encoding="utf-8"), encoding="utf-8")
            self._nginx_runtime_message = f"Restored original config from {original_backup}"
            self._nginx_runtime_error = False
            self.appSettingsFeedbackChanged.emit()
            self.dataChanged.emit()
            return True
        except Exception as exc:
            self._nginx_runtime_message = str(exc)
            self._nginx_runtime_error = True
            self.appSettingsFeedbackChanged.emit()
            return False

    @Property(str, notify=appSettingsFeedbackChanged)
    def settingsAppearanceTheme(self) -> str:
        return self._container.settings_service.get_settings().appearance_theme

    @Property(str, notify=appSettingsFeedbackChanged)
    def settingsAppearanceAccentColor(self) -> str:
        return self._container.settings_service.get_settings().appearance_accent_color

    @Property(str, notify=appSettingsFeedbackChanged)
    def settingsAppearanceLanguage(self) -> str:
        return self._container.settings_service.get_settings().appearance_language

    @Property(bool, notify=appSettingsFeedbackChanged)
    def settingsAutoStartStack(self) -> bool:
        return bool(self._container.settings_service.get_settings().auto_start_stack)

    @Property(bool, notify=appSettingsFeedbackChanged)
    def settingsAutoUpdateHosts(self) -> bool:
        return bool(self._container.settings_service.get_settings().auto_update_hosts)

    @Property(bool, notify=appSettingsFeedbackChanged)
    def settingsEnableSimulatedProcesses(self) -> bool:
        return bool(self._container.settings_service.get_settings().enable_simulated_processes)

    @Property(str, notify=appSettingsFeedbackChanged)
    def settingsEnvironmentRoot(self) -> str:
        return str(self._container.settings_service.get_settings().environment_root or "")

    @Property(str, notify=appSettingsFeedbackChanged)
    def settingsDefaultProjectFolder(self) -> str:
        return str(self._container.settings_service.get_settings().default_project_folder or "~/ServerEngine")

    @Property(bool, notify=appSettingsFeedbackChanged)
    def osPrefersDark(self) -> bool:
        try:
            if sys.platform == "darwin":
                return macos_prefers_dark_appearance()
            app = QApplication.instance()
            if app is None:
                return False
            color = app.palette().window().color()
            if color.isValid():
                return color.lightness() < 128
            return app.styleHints().colorScheme() == Qt.ColorScheme.Dark
        except Exception:
            return False

    @Property(str, notify=appSettingsFeedbackChanged)
    def settingsNodeVersion(self) -> str:
        return self._container.settings_service.get_settings().active_node_version or ""

    @Property("QVariantList", notify=appSettingsFeedbackChanged)
    def nodeRuntimeVersions(self) -> list[str]:
        return self._container.binary_locator.available_node_versions()

    @Property("QVariantList", notify=appSettingsFeedbackChanged)
    def nodeRuntimeItems(self) -> list[dict[str, object]]:
        return list(self._container.binary_locator.available_node_runtimes())

    @Property(str, notify=appSettingsFeedbackChanged)
    def settingsDefaultPhpVersion(self) -> str:
        return self._container.settings_service.get_settings().default_php_version

    @Property("QVariantList", notify=appSettingsFeedbackChanged)
    def appSettingsPhpVersions(self) -> list[str]:
        versions = self._container.php_runtime_service.list_versions()
        current = self._container.settings_service.get_settings().default_php_version
        if current and current not in versions:
            versions = [*versions, current]
        return versions

    @Property("QVariantList", notify=appSettingsFeedbackChanged)
    def appSettingsInstalledPhpVersions(self) -> list[str]:
        return self._container.php_runtime_service.list_versions()

    @Property("QVariantList", notify=appSettingsFeedbackChanged)
    def appSettingsPhpMyAdminVersions(self) -> list[str]:
        return self._container.binary_locator.available_phpmyadmin_versions()

    @Property(bool, notify=appSettingsFeedbackChanged)
    def settingsPhpLogToFile(self) -> bool:
        return bool(self._container.settings_service.get_settings().php_runtime_log_to_file)

    @Property(bool, notify=appSettingsFeedbackChanged)
    def settingsPhpLogToScreen(self) -> bool:
        return bool(self._container.settings_service.get_settings().php_runtime_log_to_screen)

    @Property(str, notify=appSettingsFeedbackChanged)
    def settingsPhpLogPath(self) -> str:
        return self._container.settings_service.get_settings().php_runtime_log_dir

    @Property(str, notify=appSettingsFeedbackChanged)
    def settingsWebPort(self) -> str:
        return str(self._container.settings_service.get_settings().apache_port)

    @Property(str, notify=appSettingsFeedbackChanged)
    def settingsDatabasePort(self) -> str:
        return str(self._container.settings_service.get_settings().database_port)

    @Property(str, notify=appSettingsFeedbackChanged)
    def settingsRedisPort(self) -> str:
        return str(self._container.settings_service.get_settings().redis_port)

    @Property(str, notify=appSettingsFeedbackChanged)
    def settingsMailpitSmtpPort(self) -> str:
        return str(self._container.settings_service.get_settings().mailpit_smtp_port)

    @Property(str, notify=appSettingsFeedbackChanged)
    def settingsMailpitHttpPort(self) -> str:
        return str(self._container.settings_service.get_settings().mailpit_http_port)

    @Slot(str, result=bool)
    def updateApacheRuntimePort(self, apache_port: str) -> bool:
        try:
            current = self._container.settings_service.get_settings()
            normalized_port = self._parse_port_value(apache_port, "Web server")
            if normalized_port != current.apache_port and not self._is_tcp_port_available(normalized_port):
                raise ValueError(f"Port {normalized_port} is already in use.")
            settings = self._copy_settings(current, apache_port=normalized_port)
            self._container.settings_service.save_settings(settings)
            self._app_settings_message = f"Web server port saved as {normalized_port}."
            self._app_settings_error = False
            self.dataChanged.emit()
            self.homeServiceChanged.emit()
            self.appSettingsFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._app_settings_message = str(exc)
            self._app_settings_error = True
            self.appSettingsFeedbackChanged.emit()
            return False

    @Slot(str, result=bool)
    def updateNginxRuntimePort(self, nginx_port: str) -> bool:
        return self.updateApacheRuntimePort(nginx_port)

    @Property(int, notify=appSettingsFeedbackChanged)
    def settingsBottomTerminalPanelHeight(self) -> int:
        return max(80, int(self._container.settings_service.get_settings().bottom_terminal_panel_height or 260))

    @Property("QVariantList", notify=appSettingsFeedbackChanged)
    def apacheModuleItems(self) -> list[dict[str, object]]:
        settings = self._container.settings_service.get_settings()
        enabled = set(settings.apache_enabled_modules or [])
        items: list[dict[str, object]] = []
        for module_name in self._container.binary_locator.available_apache_modules():
            items.append(
                {
                    "name": module_name,
                    "description": self._apache_module_description(module_name),
                    "enabled": module_name in enabled or (not enabled and module_name in self._container.config_service.DEFAULT_APACHE_MODULES),
                }
            )
        return items

    @Property(str, notify=appSettingsFeedbackChanged)
    def apacheRuntimeLabel(self) -> str:
        return self._container.binary_locator.apache_home().name

    @Property(str, notify=appSettingsFeedbackChanged)
    def currentWebServerLabel(self) -> str:
        settings = self._container.settings_service.get_settings()
        if settings.active_web_server == settings.active_web_server.APACHE:
            runtime_label = self.apacheRuntimeLabel
            if runtime_label.lower().startswith("apache-"):
                return "Apache " + runtime_label.split("-", 1)[1]
            return "Apache"
        runtime = getattr(self._container.binary_locator, "nginx_home", None)
        if callable(runtime):
            try:
                nginx_home = runtime()
                name = nginx_home.name
                if name.lower().startswith("nginx-"):
                    return "Nginx " + name.split("-", 1)[1]
            except Exception:
                pass
        return "Nginx"

    @Property(str, notify=appSettingsFeedbackChanged)
    def activePhpMyAdminVersion(self) -> str:
        settings = self._container.settings_service.get_settings()
        versions = self._container.binary_locator.available_phpmyadmin_versions()
        active = settings.active_phpmyadmin_version or ""
        if active in versions:
            return active
        root = self._container.config_service.phpmyadmin_root()
        return root.name if root.exists() and (root / "index.php").exists() else (versions[-1] if versions else "")

    @Property(str, notify=appSettingsFeedbackChanged)
    def phpMyAdminPhpVersion(self) -> str:
        runtime = self._container.config_service.phpmyadmin_runtime()
        return runtime.version if runtime is not None else ""

    @Property(str, notify=appSettingsFeedbackChanged)
    def phpMyAdminUrl(self) -> str:
        return self._container.config_service.phpmyadmin_url()

    @Property(str, notify=appSettingsFeedbackChanged)
    def phpMyAdminRuntimePath(self) -> str:
        return str(self._container.config_service.phpmyadmin_root())

    @Property(str, notify=appSettingsFeedbackChanged)
    def phpMyAdminPhpRuntimePath(self) -> str:
        runtime = self._container.config_service.phpmyadmin_runtime()
        return runtime.home if runtime is not None else ""

    @Property(str, notify=appSettingsFeedbackChanged)
    def phpMyAdminPhpCgiPath(self) -> str:
        runtime = self._container.config_service.phpmyadmin_runtime()
        return runtime.php_cgi_path if runtime is not None else ""

    @Property(str, notify=appSettingsFeedbackChanged)
    def phpMyAdminWrapperPath(self) -> str:
        return str(self._container.config_service.phpmyadmin_wrapper_path())

    @Property(str, notify=appSettingsFeedbackChanged)
    def phpMyAdminConfigPath(self) -> str:
        return str(self._container.config_service.phpmyadmin_config_path())

    def _apache_module_description(self, module_name: str) -> str:
        descriptions = {
            "mod_access_compat.so": "Compatibility module for older allow, deny, and order access rules.",
            "mod_actions.so": "Map MIME types or handlers to CGI scripts and custom actions.",
            "mod_alias.so": "Create URL aliases, redirects, and path mappings.",
            "mod_allowmethods.so": "Restrict which HTTP methods are allowed.",
            "mod_asis.so": "Serve files exactly as-is without adding HTTP headers.",
            "mod_auth_basic.so": "Basic HTTP authentication support.",
            "mod_auth_digest.so": "Digest HTTP authentication support.",
            "mod_auth_form.so": "Form-based authentication support.",
            "mod_authn_anon.so": "Allow anonymous authentication.",
            "mod_authn_core.so": "Core authentication framework required by auth modules.",
            "mod_authn_dbd.so": "Authenticate users from a SQL database.",
            "mod_authn_dbm.so": "Authenticate users from DBM password files.",
            "mod_authn_file.so": "Authenticate users from password files.",
            "mod_authn_socache.so": "Cache authentication results.",
            "mod_authnz_fcgi.so": "Authorize users through a FastCGI application.",
            "mod_authnz_ldap.so": "Authenticate and authorize users through LDAP.",
            "mod_authz_core.so": "Core authorization framework required by many auth modules.",
            "mod_authz_dbd.so": "Authorize users from a SQL database.",
            "mod_authz_dbm.so": "Authorize users from DBM group files.",
            "mod_authz_groupfile.so": "Authorize users from group files.",
            "mod_authz_host.so": "Allow or deny access by host, IP, or domain.",
            "mod_authz_owner.so": "Authorize access based on file ownership.",
            "mod_authz_user.so": "Authorize access for authenticated users.",
            "mod_autoindex.so": "Generate directory listings when no index file exists.",
            "mod_brotli.so": "Compress responses using Brotli.",
            "mod_buffer.so": "Buffer input and output filters.",
            "mod_cache.so": "Core HTTP caching support.",
            "mod_cache_disk.so": "Disk-based HTTP caching.",
            "mod_cache_socache.so": "Shared-object-cache HTTP caching.",
            "mod_cern_meta.so": "Support CERN-style metadata files.",
            "mod_cgi.so": "Run classic CGI programs.",
            "mod_cgid.so": "Run CGI scripts through a daemon process.",
            "mod_charset_lite.so": "Perform character set translation.",
            "mod_data.so": "Convert response bodies into data URLs.",
            "mod_dav.so": "Core WebDAV support.",
            "mod_dav_fs.so": "Filesystem provider for WebDAV.",
            "mod_dav_lock.so": "Locking support for WebDAV.",
            "mod_dbd.so": "SQL database connection pooling.",
            "mod_deflate.so": "Compress responses using gzip/deflate.",
            "mod_dialup.so": "Simulate slow network connections.",
            "mod_dir.so": "Handle directory index files and trailing slash redirects.",
            "mod_dumpio.so": "Dump request and response I/O for debugging.",
            "mod_echo.so": "Simple echo server protocol module.",
            "mod_env.so": "Set environment variables for requests.",
            "mod_expires.so": "Set Expires and Cache-Control headers.",
            "mod_ext_filter.so": "Pass response content through external programs.",
            "mod_file_cache.so": "Cache frequently used static files in memory.",
            "mod_filter.so": "Smart output filter configuration.",
            "mod_headers.so": "Add, edit, or remove HTTP headers.",
            "mod_heartbeat.so": "Send server heartbeat status messages.",
            "mod_heartmonitor.so": "Monitor heartbeat messages from servers.",
            "mod_http2.so": "Enable HTTP/2 support.",
            "mod_ident.so": "Perform RFC 1413 ident lookups.",
            "mod_imagemap.so": "Server-side image map support.",
            "mod_include.so": "Server Side Includes support.",
            "mod_info.so": "Expose Apache server configuration information.",
            "mod_lbmethod_bybusyness.so": "Load-balance proxy workers by current busyness.",
            "mod_lbmethod_byrequests.so": "Load-balance proxy workers by request count.",
            "mod_lbmethod_bytraffic.so": "Load-balance proxy workers by traffic volume.",
            "mod_lbmethod_heartbeat.so": "Load-balance using heartbeat data.",
            "mod_ldap.so": "LDAP connection pooling and caching.",
            "mod_log_config.so": "Configure access log formats and logging rules.",
            "mod_log_debug.so": "Add debug logging hooks.",
            "mod_log_forensic.so": "Forensic request logging.",
            "mod_logio.so": "Log input and output byte counts.",
            "mod_lua.so": "Extend Apache using Lua scripts.",
            "mod_macro.so": "Reuse config snippets with macros.",
            "mod_md.so": "Manage ACME certificates for HTTPS.",
            "mod_mime.so": "Map file extensions to content types and handlers.",
            "mod_mime_magic.so": "Detect MIME types from file contents.",
            "mod_mpm_event.so": "Event-based multi-processing module for Apache.",
            "mod_mpm_prefork.so": "Prefork multi-processing module with one process per request.",
            "mod_mpm_worker.so": "Worker multi-processing module using threads.",
            "mod_negotiation.so": "Content negotiation for language, encoding, and media type.",
            "mod_proxy.so": "Core proxy support for reverse proxy and gateway features.",
            "mod_proxy_ajp.so": "Proxy AJP upstream servers.",
            "mod_proxy_balancer.so": "Load-balancing support for proxy workers.",
            "mod_proxy_connect.so": "Proxy CONNECT requests for SSL tunneling.",
            "mod_proxy_express.so": "Dynamic mass reverse proxy support.",
            "mod_proxy_fcgi.so": "Proxy FastCGI applications such as PHP-FPM.",
            "mod_proxy_fdpass.so": "Pass file descriptors to backend processes.",
            "mod_proxy_ftp.so": "Proxy FTP upstream servers.",
            "mod_proxy_hcheck.so": "Health checks for proxy backends.",
            "mod_proxy_html.so": "Rewrite HTML links in proxied content.",
            "mod_proxy_http.so": "Proxy HTTP upstream servers.",
            "mod_proxy_http2.so": "Proxy HTTP/2 upstream servers.",
            "mod_proxy_scgi.so": "Proxy SCGI applications.",
            "mod_proxy_uwsgi.so": "Proxy uWSGI applications.",
            "mod_proxy_wstunnel.so": "Proxy WebSocket connections.",
            "mod_ratelimit.so": "Limit response bandwidth per request.",
            "mod_reflector.so": "Reflect request bodies back in responses.",
            "mod_remoteip.so": "Use forwarded client IP addresses from proxies.",
            "mod_reqtimeout.so": "Set request timeout rules to protect against slow clients.",
            "mod_request.so": "Filter and process request bodies.",
            "mod_rewrite.so": "Advanced URL rewriting and routing rules.",
            "mod_sed.so": "Search and replace response content.",
            "mod_session.so": "Core session support.",
            "mod_session_cookie.so": "Store sessions in cookies.",
            "mod_session_crypto.so": "Encrypt session data.",
            "mod_session_dbd.so": "Store sessions in a SQL database.",
            "mod_setenvif.so": "Set environment variables based on request properties.",
            "mod_slotmem_plain.so": "Plain shared memory slot provider.",
            "mod_slotmem_shm.so": "Shared memory slot provider.",
            "mod_socache_dbm.so": "DBM-based shared object cache provider.",
            "mod_socache_memcache.so": "Memcached shared object cache provider.",
            "mod_socache_redis.so": "Redis shared object cache provider.",
            "mod_socache_shmcb.so": "Shared memory cyclic buffer cache provider.",
            "mod_speling.so": "Correct minor URL spelling and capitalization mistakes.",
            "mod_ssl.so": "SSL/TLS support for HTTPS virtual hosts.",
            "mod_status.so": "Expose server status and worker activity.",
            "mod_substitute.so": "Search and replace response content using filters.",
            "mod_suexec.so": "Run CGI scripts as different users.",
            "mod_unique_id.so": "Generate unique request identifiers.",
            "mod_unixd.so": "Unix-specific process and permission support.",
            "mod_userdir.so": "Serve user directories such as /~username.",
            "mod_usertrack.so": "Track users with cookies.",
            "mod_version.so": "Enable version-based conditional configuration.",
            "mod_vhost_alias.so": "Support dynamic mass virtual hosting.",
            "mod_watchdog.so": "Provide watchdog hooks for other modules.",
            "mod_xml2enc.so": "Character encoding support for XML and HTML filters.",
        }
        return descriptions.get(module_name, "Apache runtime module.")

    def _copy_settings(self, current, **updates):
        return replace(current, **updates)

    @Property(str, notify=appSettingsFeedbackChanged)
    def settingsDatabaseRuntime(self) -> str:
        return self._container.settings_service.get_settings().active_database_version or ""

    @Property(str, notify=appSettingsFeedbackChanged)
    def settingsRedisRuntime(self) -> str:
        return self._container.settings_service.get_settings().active_redis_version or ""

    @Property(str, notify=appSettingsFeedbackChanged)
    def appSettingsMessage(self) -> str:
        return self._app_settings_message

    @Property(bool, notify=appSettingsFeedbackChanged)
    def appSettingsError(self) -> bool:
        return self._app_settings_error

    @Property(str, notify=postgresqlRuntimeFeedbackChanged)
    def settingsPostgresqlPort(self) -> str:
        return str(self._container.postgresql_service.port)

    @Property(str, notify=mongodbRuntimeFeedbackChanged)
    def settingsMongodbPort(self) -> str:
        self._container.mongodb_service.status()
        return str(self._container.mongodb_service.port)

    @Slot()
    def clearAppFeedback(self) -> None:
        self._last_operation_message = ""
        self._last_operation_error = False
        self._stack_feedback_message = ""
        self._stack_feedback_error = False
        self._app_settings_message = ""
        self._app_settings_error = False
        self._database_runtime_message = ""
        self._database_runtime_error = False
        self._database_backup_message = ""
        self._database_backup_error = False
        self._database_import_message = ""
        self._database_import_error = False
        self._redis_runtime_message = ""
        self._redis_runtime_error = False
        self._mailpit_runtime_message = ""
        self._mailpit_runtime_error = False
        self._node_project_runtime_message = ""
        self._node_project_runtime_error = False
        self.operationFeedbackChanged.emit()
        self.stackFeedbackChanged.emit()
        self.appSettingsFeedbackChanged.emit()
        self.databaseRuntimeFeedbackChanged.emit()
        self.redisRuntimeFeedbackChanged.emit()
        self.mailpitRuntimeFeedbackChanged.emit()

    @Slot()
    def clearAppSettingsFeedback(self) -> None:
        self._app_settings_message = ""
        self._app_settings_error = False
        self.appSettingsFeedbackChanged.emit()

    @Slot(str, str, result=bool)
    def saveDatabaseAppSettings(self, engine: str, runtime_id: str) -> bool:
        try:
            current = self._container.settings_service.get_settings()
            selected_engine = engine.strip().lower()
            selected_runtime = runtime_id.strip() or None
            runtime_passwords = dict(current.database_runtime_passwords or {})
            selected_password = runtime_passwords.get(selected_runtime or "", "")
            settings = self._copy_settings(
                current,
                preferred_database_engine=selected_engine or current.preferred_database_engine,
                active_database_version=selected_runtime,
                database_root_password=selected_password,
                database_runtime_passwords=runtime_passwords,
            )
            self._container.settings_service.save_settings(settings)
            self._app_settings_message = "Settings saved. Restart the database runtime to apply runtime changes."
            self._app_settings_error = False
            self.dataChanged.emit()
            self.appSettingsFeedbackChanged.emit()
            self.databaseRuntimeFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._app_settings_message = str(exc)
            self._app_settings_error = True
            self.appSettingsFeedbackChanged.emit()
            return False

    @Slot(str, str, str, result=bool)
    def saveCacheAppSettings(self, cache_driver: str, redis_runtime_id: str, memcached_runtime_id: str) -> bool:
        try:
            current = self._container.settings_service.get_settings()
            driver = cache_driver.strip().lower() or current.cache_driver
            if driver not in {"redis", "memcached", "apcu", "file"}:
                raise ValueError("Invalid cache driver.")
            settings = self._copy_settings(
                current,
                cache_driver=driver,
                active_redis_version=redis_runtime_id.strip() or None,
                active_memcached_version=memcached_runtime_id.strip() or None,
            )
            self._container.settings_service.save_settings(settings)
            self._app_settings_message = "Cache settings saved. Restart cache services to apply runtime changes."
            self._app_settings_error = False
            self.dataChanged.emit()
            self.appSettingsFeedbackChanged.emit()
            self.redisRuntimeFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._app_settings_message = str(exc)
            self._app_settings_error = True
            self.appSettingsFeedbackChanged.emit()
            return False

    @Slot(str, result=bool)
    def saveRedisAppSettings(self, redis_runtime_id: str) -> bool:
        try:
            current = self._container.settings_service.get_settings()
            settings = self._copy_settings(
                current,
                active_redis_version=redis_runtime_id.strip() or None,
            )
            self._container.settings_service.save_settings(settings)
            self._app_settings_message = "Redis settings saved. Restart Redis to apply runtime changes."
            self._app_settings_error = False
            self.dataChanged.emit()
            self.appSettingsFeedbackChanged.emit()
            self.redisRuntimeFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._app_settings_message = str(exc)
            self._app_settings_error = True
            self.appSettingsFeedbackChanged.emit()
            return False

    @Slot("QVariantList", result=bool)
    def saveApacheModules(self, modules: list) -> bool:
        try:
            current = self._container.settings_service.get_settings()
            normalized = sorted(str(item).strip() for item in modules if str(item).strip())
            settings = self._copy_settings(current, apache_enabled_modules=normalized)
            self._container.settings_service.save_settings(settings)
            self._app_settings_message = "Apache module settings saved. Restart Apache to apply changes."
            self._app_settings_error = False
            self.dataChanged.emit()
            self.appSettingsFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._app_settings_message = str(exc)
            self._app_settings_error = True
            self.appSettingsFeedbackChanged.emit()
            return False

    @Slot(str, "QVariantList", result=bool)
    def saveWebServerAppSettings(self, web_server: str, modules: list) -> bool:
        try:
            current = self._container.settings_service.get_settings()
            selected_server = web_server.strip().lower() or current.active_web_server.value
            normalized_modules = sorted(str(item).strip() for item in modules if str(item).strip())
            apache_modules = normalized_modules if selected_server == "apache" else current.apache_enabled_modules
            settings = self._copy_settings(
                current,
                active_web_server=current.active_web_server.__class__(selected_server),
                apache_enabled_modules=apache_modules,
            )
            self._container.settings_service.save_settings(settings)
            self._app_settings_message = "Web server settings saved. Restart the stack to apply server changes."
            self._app_settings_error = False
            self.dataChanged.emit()
            if hasattr(self, "_refresh_home_service_items_cache"):
                self._refresh_home_service_items_cache()
            self.homeServiceChanged.emit()
            self.appSettingsFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._app_settings_message = str(exc)
            self._app_settings_error = True
            self.appSettingsFeedbackChanged.emit()
            return False

    @Slot(str, result=bool)
    def saveDefaultWebServerSelection(self, web_server: str) -> bool:
        try:
            current = self._container.settings_service.get_settings()
            selected_server = web_server.strip().lower() or current.active_web_server.value
            if selected_server not in {"apache", "nginx"}:
                raise ValueError("Invalid web server.")
            current_server_id = current.active_web_server.value
            current_server_label = "Apache" if current_server_id == "apache" else "Nginx"
            if selected_server != current_server_id:
                status = self._container.stack_service.status()
                current_service = next((item for item in status.services if item.service_id == current_server_id), None)
                if current_service is not None and current_service.state.value == "running":
                    stopped = self._container.stack_service.stop_service(current_server_id)
                    if stopped.state.value == "error":
                        raise ValueError(stopped.message or f"{current_server_label} stop failed.")
            settings = self._copy_settings(
                current,
                active_web_server=current.active_web_server.__class__(selected_server),
            )
            self._container.settings_service.save_settings(settings)
            if selected_server != current_server_id:
                self._app_settings_message = f"{current_server_label} stopped if it was running. Default web server saved."
            else:
                self._app_settings_message = "Default web server saved."
            self._app_settings_error = False
            self.dataChanged.emit()
            if hasattr(self, "_refresh_home_service_items_cache"):
                self._refresh_home_service_items_cache()
            self.homeServiceChanged.emit()
            self.appSettingsFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._app_settings_message = str(exc)
            self._app_settings_error = True
            self.appSettingsFeedbackChanged.emit()
            return False

    @Slot(str, str, str, result=bool)
    def saveWebServerRuntimeSettings(self, web_server: str, apache_runtime_id: str, nginx_runtime_id: str) -> bool:
        try:
            current = self._container.settings_service.get_settings()
            selected_server = web_server.strip().lower() or current.active_web_server.value
            if selected_server not in {"apache", "nginx"}:
                raise ValueError("Invalid web server.")
            apache_runtime = apache_runtime_id.strip() or None
            nginx_runtime = nginx_runtime_id.strip() or None
            if apache_runtime and self._container.binary_locator.apache_runtime_home(apache_runtime) is None:
                raise ValueError("Selected Apache runtime is not installed locally.")
            if nginx_runtime and self._container.binary_locator.nginx_runtime_home(nginx_runtime) is None:
                raise ValueError("Selected Nginx runtime is not installed locally.")
            settings = self._copy_settings(
                current,
                active_apache_version=apache_runtime,
                active_nginx_version=nginx_runtime,
            )
            self._container.settings_service.save_settings(settings)
            self._app_settings_message = "Web server runtime saved. Restart web server to apply runtime changes."
            self._app_settings_error = False
            self.dataChanged.emit()
            if hasattr(self, "_refresh_home_service_items_cache"):
                self._refresh_home_service_items_cache()
            self.homeServiceChanged.emit()
            self.appSettingsFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._app_settings_message = str(exc)
            self._app_settings_error = True
            self.appSettingsFeedbackChanged.emit()
            return False

    @Slot(str, "QVariantList", "QVariant", "QVariant", "QVariant", "QVariant", "QVariant", "QVariant", "QVariant", "QVariant", "QVariant", result=bool)
    def saveWebServerAdvancedAppSettings(
        self,
        web_server: str,
        modules: list,
        apache_error_log_path,
        nginx_worker_processes,
        nginx_worker_connections,
        nginx_keepalive_timeout,
        nginx_client_max_body_size,
        nginx_sendfile,
        nginx_gzip,
        nginx_server_tokens,
        nginx_error_log_path,
    ) -> bool:
        try:
            current = self._container.settings_service.get_settings()
            selected_server = web_server.strip().lower() or current.active_web_server.value
            normalized_modules = sorted(str(item).strip() for item in modules if str(item).strip())
            apache_modules = normalized_modules if normalized_modules else current.apache_enabled_modules
            worker_processes = str(nginx_worker_processes).strip() or "1"
            worker_connections = self._parse_port_value(str(nginx_worker_connections), "Nginx worker connections")
            keepalive_timeout = self._parse_port_value(str(nginx_keepalive_timeout), "Nginx keepalive timeout")
            client_max_body_size = str(nginx_client_max_body_size).strip() or "64m"
            settings = self._copy_settings(
                current,
                active_web_server=current.active_web_server.__class__(selected_server),
                apache_enabled_modules=apache_modules,
                apache_error_log_path=str(apache_error_log_path).strip(),
                nginx_worker_processes=worker_processes,
                nginx_worker_connections=worker_connections,
                nginx_keepalive_timeout=keepalive_timeout,
                nginx_client_max_body_size=client_max_body_size,
                nginx_sendfile=bool(nginx_sendfile),
                nginx_gzip=bool(nginx_gzip),
                nginx_server_tokens=bool(nginx_server_tokens),
                nginx_error_log_path=str(nginx_error_log_path).strip(),
            )
            self._container.settings_service.save_settings(settings)
            self._app_settings_message = "Web server settings saved. Restart web server to apply changes."
            self._app_settings_error = False
            self.dataChanged.emit()
            if hasattr(self, "_refresh_home_service_items_cache"):
                self._refresh_home_service_items_cache()
            self.homeServiceChanged.emit()
            self.appSettingsFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._app_settings_message = str(exc)
            self._app_settings_error = True
            self.appSettingsFeedbackChanged.emit()
            return False

    @Slot("QVariant", "QVariant", "QVariant", "QVariant", "QVariant", "QVariant", "QVariant", "QVariant", result=bool)
    def saveNginxAppSettings(
        self,
        nginx_worker_processes,
        nginx_worker_connections,
        nginx_keepalive_timeout,
        nginx_client_max_body_size,
        nginx_sendfile,
        nginx_gzip,
        nginx_server_tokens,
        nginx_error_log_path,
    ) -> bool:
        try:
            current = self._container.settings_service.get_settings()
            worker_processes = str(nginx_worker_processes).strip() or "1"
            worker_connections = self._parse_port_value(str(nginx_worker_connections), "Nginx worker connections")
            keepalive_timeout = self._parse_port_value(str(nginx_keepalive_timeout), "Nginx keepalive timeout")
            client_max_body_size = str(nginx_client_max_body_size).strip() or "64m"
            settings = self._copy_settings(
                current,
                nginx_worker_processes=worker_processes,
                nginx_worker_connections=worker_connections,
                nginx_keepalive_timeout=keepalive_timeout,
                nginx_client_max_body_size=client_max_body_size,
                nginx_sendfile=bool(nginx_sendfile),
                nginx_gzip=bool(nginx_gzip),
                nginx_server_tokens=bool(nginx_server_tokens),
                nginx_error_log_path=str(nginx_error_log_path).strip(),
            )
            self._container.settings_service.save_settings(settings)
            self._app_settings_message = "Nginx settings saved."
            self._app_settings_error = False
            self.dataChanged.emit()
            self.appSettingsFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._app_settings_message = str(exc)
            self._app_settings_error = True
            self.appSettingsFeedbackChanged.emit()
            return False

    @Slot(str, bool, bool, str, result=bool)
    def savePhpAppSettings(self, default_php_version: str, php_log_to_file: bool, php_log_to_screen: bool, php_log_path: str) -> bool:
        try:
            selected_php = default_php_version.strip()
            if not selected_php:
                raise ValueError("Default PHP version is required.")
            if not php_log_to_file and not php_log_to_screen:
                raise ValueError("Enable at least one PHP log output: file or screen.")
            cleaned_log_path = php_log_path.strip()
            if php_log_to_file and not cleaned_log_path:
                raise ValueError("Log path is required when PHP logging mode is set to file.")
            normalized_log_path = self._normalize_php_log_path(cleaned_log_path)
            if php_log_to_file:
                normalized_log_path.parent.mkdir(parents=True, exist_ok=True)
                normalized_log_path.touch(exist_ok=True)
            current = self._container.settings_service.get_settings()
            settings = self._copy_settings(
                current,
                default_php_version=selected_php,
                php_runtime_log_to_file=bool(php_log_to_file),
                php_runtime_log_to_screen=bool(php_log_to_screen),
                php_runtime_log_dir=str(normalized_log_path),
            )
            self._container.settings_service.save_settings(settings)
            self._app_settings_message = "PHP settings saved. Restart web server services to apply logging changes."
            self._app_settings_error = False
            self.dataChanged.emit()
            self.appSettingsFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._app_settings_message = str(exc)
            self._app_settings_error = True
            self.appSettingsFeedbackChanged.emit()
            return False

    @Slot(str, result=bool)
    def saveNodeAppSettings(self, node_version: str) -> bool:
        try:
            selected = node_version.strip()
            if not selected:
                raise ValueError("Node version is required.")
            current = self._container.settings_service.get_settings()
            settings = self._copy_settings(current, active_node_version=selected)
            self._container.settings_service.save_settings(settings)
            self._app_settings_message = "Node settings saved."
            self._app_settings_error = False
            self.dataChanged.emit()
            self.appSettingsFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._app_settings_message = str(exc)
            self._app_settings_error = True
            self.appSettingsFeedbackChanged.emit()
            return False

    def _ensure_app_settings_save_worker(self) -> None:
        if self._app_settings_save_thread is not None and self._app_settings_save_worker is not None:
            return

        thread = QThread(self)
        worker = AppSettingsSaveWorker(self._container)
        worker.moveToThread(thread)
        worker.completed.connect(self._handle_app_settings_save_completed)
        self.appSettingsSaveRequested.connect(worker.runSave)
        thread.start()
        self._app_settings_save_thread = thread
        self._app_settings_save_worker = worker

        app = QCoreApplication.instance()
        if app is not None:
            try:
                app.aboutToQuit.connect(self._cleanup_app_settings_save_worker)
            except Exception:
                pass

    @Slot()
    def _cleanup_app_settings_save_worker(self) -> None:
        thread = self._app_settings_save_thread
        self._app_settings_save_thread = None
        self._app_settings_save_worker = None
        self._app_settings_save_busy = False
        self._app_settings_save_current_kind = ""
        self._app_settings_save_pending = None
        if thread is None:
            return
        try:
            thread.quit()
            thread.wait(1000)
        except Exception:
            pass

    @Slot(bool, str)
    def _handle_app_settings_save_completed(self, success: bool, message: str) -> None:
        save_kind = self._app_settings_save_current_kind or "general"
        self._app_settings_save_busy = False
        self._app_settings_message = str(message or "")
        self._app_settings_error = not bool(success)
        self.appSettingsFeedbackChanged.emit()
        self.appSettingsSaveCompleted.emit(save_kind, bool(success), str(message or ""))
        pending = self._app_settings_save_pending
        self._app_settings_save_pending = None
        if pending is not None:
            pending_kind, pending_payload = pending
            QTimer.singleShot(0, lambda: self._queue_app_settings_save(pending_kind, pending_payload))

    def _queue_app_settings_save(self, kind: str, payload: dict[str, object]) -> bool:
        self._ensure_app_settings_save_worker()
        if self._app_settings_save_busy:
            self._app_settings_save_pending = (kind, dict(payload))
            return True

        self._app_settings_save_busy = True
        self._app_settings_save_current_kind = kind
        if self._app_settings_save_worker is None:
            self._app_settings_save_busy = False
            self._app_settings_save_pending = (kind, dict(payload))
            return True
        self.appSettingsSaveRequested.emit(kind, dict(payload))
        return True

    @Slot(str, str, str, result=bool)
    def saveAppearanceAppSettings(self, theme_mode: str, accent_color: str, language: str) -> bool:
        cleaned = theme_mode.strip().lower()
        if cleaned not in {"system", "light", "dark"}:
            raise ValueError("Theme mode must be one of: system, light, dark.")
        clean_accent = (accent_color or "#007bff").strip().lower()
        if not re.fullmatch(r"#[0-9a-f]{6}", clean_accent):
            raise ValueError("Accent color must be a hex color.")
        clean_language = (language or "en").strip().lower()
        if clean_language in {"zh_cn", "zh-sg"}:
            clean_language = "zh-hans"
        elif clean_language in {"zh_tw", "zh_hk", "zh-mo"}:
            clean_language = "zh-hant"
        if clean_language not in {"en", "de", "vi", "zh-hans", "zh-hant"}:
            raise ValueError("Language must be one of: en, de, vi, zh-hans, zh-hant.")
        return self._queue_app_settings_save(
            "appearance",
            {
                "theme_mode": cleaned,
                "accent_color": clean_accent,
                "language": clean_language,
            },
        )

    @Slot(bool, bool, bool, str, str, result=bool)
    def saveGeneralAppSettings(
        self,
        auto_start_stack: bool,
        auto_update_hosts: bool,
        enable_simulated_processes: bool,
        environment_root: str,
        default_project_folder: str,
    ) -> bool:
        current = self._container.settings_service.get_settings()
        cleaned_root = str(environment_root).strip()
        resolved_root = str(Path(cleaned_root).expanduser()) if cleaned_root else current.environment_root
        cleaned_folder = str(default_project_folder).strip() or "~/ServerEngine"
        return self._queue_app_settings_save(
            "general",
            {
                "auto_start_stack": bool(auto_start_stack),
                "auto_update_hosts": bool(auto_update_hosts),
                "enable_simulated_processes": bool(enable_simulated_processes),
                "environment_root": resolved_root,
                "default_project_folder": cleaned_folder,
            },
        )

    @Slot(str, str, result=bool)
    def savePhpMyAdminAppSettings(self, phpmyadmin_version: str, php_version: str) -> bool:
        try:
            current = self._container.settings_service.get_settings()
            selected_pma = phpmyadmin_version.strip()
            selected_php = php_version.strip()
            if not selected_pma:
                raise ValueError("phpMyAdmin version is required.")
            if not selected_php:
                raise ValueError("PHP version for phpMyAdmin is required.")
            if selected_pma not in self._container.binary_locator.available_phpmyadmin_versions():
                raise ValueError(f"phpMyAdmin runtime {selected_pma} is not installed locally.")
            selected_root = self._container.binary_locator.phpmyadmin_root(selected_pma)
            if not selected_root.exists() or not (selected_root / "index.php").exists():
                raise ValueError(f"phpMyAdmin runtime {selected_pma} is incomplete. Missing: {selected_root / 'index.php'}")
            selected_php_runtime = self._container.binary_locator.php_runtime(selected_php)
            if selected_php_runtime is None:
                raise ValueError(f"PHP runtime {selected_php} is not installed locally.")
            settings = self._copy_settings(
                current,
                active_phpmyadmin_version=selected_pma,
                phpmyadmin_php_version=selected_php,
            )
            self._container.settings_service.save_settings(settings)
            self._container.config_service.write_phpmyadmin_config()
            self._container.config_service.write_phpmyadmin_php_cgi_wrapper()
            self._app_settings_message = "phpMyAdmin settings saved. Restart web services to apply."
            self._app_settings_error = False
            self.dataChanged.emit()
            self.appSettingsFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._app_settings_message = str(exc)
            self._app_settings_error = True
            self.appSettingsFeedbackChanged.emit()
            return False

    @Slot(bool, bool, bool, bool, bool, result=bool)
    def saveHomeActionsAppSettings(
        self,
        include_web: bool,
        include_database: bool,
        include_redis: bool,
        include_memcached: bool,
        include_mailpit: bool,
    ) -> bool:
        try:
            current = self._container.settings_service.get_settings()
            mapping = dict(current.home_global_services or {})
            mapping["web"] = bool(include_web)
            mapping["database"] = bool(include_database)
            mapping["redis"] = bool(include_redis)
            mapping["memcached"] = bool(include_memcached)
            mapping["mailpit"] = bool(include_mailpit)
            settings = self._copy_settings(current, home_global_services=mapping)
            self._container.settings_service.save_settings(settings)
            self._app_settings_message = "Home action settings saved."
            self._app_settings_error = False
            self.dataChanged.emit()
            self.appSettingsFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._app_settings_message = str(exc)
            self._app_settings_error = True
            self.appSettingsFeedbackChanged.emit()
            return False

    @Slot(int, result=bool)
    def saveBottomTerminalPanelHeight(self, panel_height: int) -> bool:
        try:
            current = self._container.settings_service.get_settings()
            height = max(80, int(panel_height))
            settings = self._copy_settings(current, bottom_terminal_panel_height=height)
            self._container.settings_service.save_settings(settings)
            self.dataChanged.emit()
            return True
        except Exception as exc:
            self._app_settings_message = str(exc)
            self._app_settings_error = True
            self.appSettingsFeedbackChanged.emit()
            return False

    def _normalize_php_log_path(self, value: str) -> Path:
        path = Path((value or "").strip()).expanduser()
        if not str(path):
            return self._container.runtime_paths.logs_dir / "php"
        if path.suffix:
            return path.parent
        if path.name == "php.log":
            return path.parent
        return path

    @Slot(str, str, str, str, str, str, result=bool)
    def savePortsAppSettings(
        self,
        web_port: str,
        database_port: str,
        redis_port: str,
        memcached_port: str,
        mailpit_smtp_port: str,
        mailpit_http_port: str,
    ) -> bool:
        try:
            current = self._container.settings_service.get_settings()
            normalized_web_port = self._parse_port_value(web_port, "Web server")
            normalized_database_port = self._parse_port_value(database_port, "Database")
            normalized_redis_port = self._parse_port_value(redis_port, "Redis")
            normalized_memcached_port = self._parse_port_value(memcached_port, "Memcached")
            normalized_mailpit_smtp_port = self._parse_port_value(mailpit_smtp_port, "Mailpit SMTP")
            normalized_mailpit_http_port = self._parse_port_value(mailpit_http_port, "Mailpit Web")
            settings = self._copy_settings(
                current,
                apache_port=normalized_web_port,
                database_port=normalized_database_port,
                redis_port=normalized_redis_port,
                mailpit_smtp_port=normalized_mailpit_smtp_port,
                mailpit_http_port=normalized_mailpit_http_port,
            )
            self._container.settings_service.save_settings(settings)
            memcached_settings = self._container.memcached_service.read_config_settings()
            memcached_host = str(memcached_settings.get("host", "127.0.0.1"))
            memcached_saved = self._container.memcached_service.save_config_settings(memcached_host, normalized_memcached_port)
            if not memcached_saved.success:
                raise ValueError(memcached_saved.message)
            self._app_settings_message = "Ports saved. Restart the affected services to apply the new ports."
            self._app_settings_error = False
            self.dataChanged.emit()
            self.appSettingsFeedbackChanged.emit()
            self.databaseRuntimeFeedbackChanged.emit()
            self.redisRuntimeFeedbackChanged.emit()
            self.stackFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._app_settings_message = str(exc)
            self._app_settings_error = True
            self.appSettingsFeedbackChanged.emit()
            return False
