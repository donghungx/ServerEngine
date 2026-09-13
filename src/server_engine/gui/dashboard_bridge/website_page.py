import logging
import sys

from server_engine.core.models import FrameworkPreset

from ._shared import *


LOGGER = logging.getLogger("server_engine.website")


class WebsitePageMixin(DashboardBridgeSignals):
    @Property("QVariantList", notify=dataChanged)
    def websiteItems(self) -> list[dict[str, str]]:
        sites = self._container.site_service.list_sites()
        apache_port = self._container.settings_service.get_settings().apache_port
        items: list[dict[str, str]] = []
        for site in sites:
            url = f"http://{site.local_domain}"
            if apache_port != 80:
                url += f":{apache_port}"
            items.append(
                {
                    "id": site.id,
                    "name": site.local_domain,
                    "primary_domain": site.local_domain,
                    "domains": site.all_domains(),
                    "project_path": site.project_path,
                    "status": "Running" if site.status.value == "active" else site.status.value.title(),
                    "php": site.php_version,
                    "web_root": site.web_root,
                    "web_root_display": "/" if site.web_root == "." else site.web_root,
                    "ssl_enabled": site.ssl_enabled,
                    "ssl_enforce_tls": site.ssl_enforce_tls,
                    "ssl_allow_http": site.ssl_allow_http,
                    "ssl_certificate_path": str(self._container.config_service.site_ssl_paths(site)[0]),
                    "ssl_key_path": str(self._container.config_service.site_ssl_paths(site)[1]),
                    "ssl_certificate_exists": self._container.config_service.site_ssl_exists(site),
                    "ssl": "60 Days" if site.ssl_enabled else "Not Set",
                    "browse_url": url,
                }
            )
        return items

    def _wordpress_archive_url(self, version: str) -> tuple[str, str, int | None]:
        cleaned = version.strip()
        if not cleaned or cleaned.lower() == "latest":
            return "https://wordpress.org/latest.zip", "latest.zip", 24 * 60 * 60
        safe_version = re.sub(r"[^0-9A-Za-z._-]", "", cleaned)
        if not safe_version:
            raise ValueError("WordPress version is invalid.")
        return f"https://wordpress.org/wordpress-{safe_version}.zip", f"wordpress-{safe_version}.zip", None

    def _download_wordpress_archive(self, version: str, progress: Callable[[int, str], None] | None = None) -> Path:
        url, filename, max_cache_age = self._wordpress_archive_url(version)
        cache_dir = self._container.runtime_paths.temp_dir / "wordpress"
        cache_dir.mkdir(parents=True, exist_ok=True)
        archive_path = cache_dir / filename
        if archive_path.exists() and archive_path.stat().st_size > 0:
            if max_cache_age is None or time.time() - archive_path.stat().st_mtime < max_cache_age:
                if progress is not None:
                    progress(18, "Using cached WordPress archive...")
                return archive_path

        partial_path = archive_path.with_suffix(archive_path.suffix + ".part")
        if partial_path.exists():
            partial_path.unlink()
        if progress is not None:
            progress(14, "Downloading WordPress archive...")
        request = urllib.request.Request(url, headers=self._request_headers({"User-Agent": "ServerEngine/1.0"}))
        try:
            with urllib.request.urlopen(request, timeout=30, context=default_ssl_context(url)) as response, partial_path.open("wb") as output:
                shutil.copyfileobj(response, output)
            if partial_path.stat().st_size <= 0:
                raise ValueError("Downloaded WordPress archive is empty.")
            partial_path.replace(archive_path)
            if progress is not None:
                progress(22, "WordPress archive downloaded.")
            return archive_path
        except Exception as exc:
            if partial_path.exists():
                partial_path.unlink()
            curl_path = shutil.which("curl")
            if curl_path:
                try:
                    subprocess.run(
                        [curl_path, "--fail", "--location", "--silent", "--show-error", "--output", str(partial_path), url],
                        check=True,
                        capture_output=True,
                        text=True,
                        timeout=120,
                    )
                    if partial_path.stat().st_size <= 0:
                        raise ValueError("Downloaded WordPress archive is empty.")
                    partial_path.replace(archive_path)
                    if progress is not None:
                        progress(22, "WordPress archive downloaded.")
                    return archive_path
                except Exception as curl_exc:
                    if partial_path.exists():
                        partial_path.unlink()
                    raise ValueError(f"WordPress download failed: {curl_exc}") from curl_exc
            raise ValueError(f"WordPress download failed: {exc}") from exc

    def _wordpress_salts(self) -> str:
        keys = [
            "AUTH_KEY",
            "SECURE_AUTH_KEY",
            "LOGGED_IN_KEY",
            "NONCE_KEY",
            "AUTH_SALT",
            "SECURE_AUTH_SALT",
            "LOGGED_IN_SALT",
            "NONCE_SALT",
        ]
        lines = []
        for key in keys:
            token = base64.b64encode(os.urandom(48)).decode("ascii").rstrip("=")
            lines.append(f"define( '{key}', '{token}' );")
        return "\n".join(lines)

    def _write_wordpress_config(
        self,
        project_root: Path,
        database_name: str,
        database_user: str,
        database_password: str,
        table_prefix: str,
        database_host: str = "localhost",
        database_port: int | None = None,
    ) -> None:
        config_path = project_root / "wp-config.php"
        sample_path = project_root / "wp-config-sample.php"
        if not sample_path.exists():
            raise ValueError("WordPress extraction failed: wp-config-sample.php is missing.")
        if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", table_prefix):
            raise ValueError("WordPress database prefix must start with a letter or underscore and use only letters, numbers, and underscores.")
        content = sample_path.read_text(encoding="utf-8")
        db_host_value = database_host.strip() or "localhost"
        if database_port is not None and database_port > 0 and ":" not in db_host_value:
            db_host_value = f"{db_host_value}:{database_port}"
        replacements = {
            "database_name_here": database_name,
            "username_here": database_user,
            "password_here": database_password,
            "localhost": db_host_value,
        }
        for old, new in replacements.items():
            content = content.replace(old, new)
        content = re.sub(r"\\$table_prefix\s*=\s*'[^']*';", f"$table_prefix = '{table_prefix}';", content)
        content = re.sub(
            r"define\(\s*'AUTH_KEY'.*?define\(\s*'NONCE_SALT'.*?\);",
            self._wordpress_salts(),
            content,
            flags=re.DOTALL,
        )
        config_path.write_text(content, encoding="utf-8")

    def _prepare_wordpress_project(
        self,
        payload: dict,
        project_root: Path,
        database_name: str,
        database_user: str,
        progress: Callable[[int, str], None] | None = None,
    ) -> None:
        if project_root.exists():
            raise ValueError("Project folder already exists. Choose a different domain or base folder.")

        version = str(payload.get("wordpress_version", "")).strip() or "Latest"
        table_prefix = str(payload.get("wordpress_database_prefix", "")).strip() or "wp_"
        database_host = str(payload.get("wordpress_database_host", "")).strip() or "localhost"
        database_port_raw = str(payload.get("wordpress_database_port", "")).strip()
        settings_port = int(self._container.settings_service.get_settings().database_port)
        database_port = int(database_port_raw) if database_port_raw.isdigit() else settings_port
        archive_path = self._download_wordpress_archive(version, progress=progress)

        temp_parent = self._container.runtime_paths.temp_dir / "wordpress"
        temp_parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="extract-", dir=temp_parent) as temp_dir_name:
            temp_dir = Path(temp_dir_name)
            try:
                if progress is not None:
                    progress(28, "Extracting WordPress files...")
                with zipfile.ZipFile(archive_path) as archive:
                    archive.extractall(temp_dir)
            except zipfile.BadZipFile as exc:
                raise ValueError("Downloaded WordPress archive is not a valid zip file.") from exc

            source_root = temp_dir / "wordpress"
            if not source_root.exists():
                candidates = [child for child in temp_dir.iterdir() if child.is_dir() and (child / "wp-settings.php").exists()]
                source_root = candidates[0] if candidates else temp_dir
            required = ["index.php", "wp-settings.php", "wp-admin", "wp-includes", "wp-content"]
            missing = [name for name in required if not (source_root / name).exists()]
            if missing:
                raise ValueError(f"WordPress extraction failed. Missing: {', '.join(missing)}")

            project_root.mkdir(parents=True, exist_ok=False)
            if progress is not None:
                progress(38, "Copying WordPress files to project folder...")
            for child in source_root.iterdir():
                target = project_root / child.name
                if child.is_dir():
                    shutil.copytree(child, target)
                else:
                    shutil.copy2(child, target)

        if progress is not None:
            progress(48, "Configuring wp-config.php...")
        self._write_wordpress_config(
            project_root,
            database_name=database_name,
            database_user=database_user,
            database_password=self._container.database_service.root_password(),
            table_prefix=table_prefix,
            database_host=database_host,
            database_port=database_port,
        )
        expected = ["index.php", "wp-settings.php", "wp-config.php", "wp-admin", "wp-content", "wp-includes"]
        missing = [name for name in expected if not (project_root / name).exists()]
        if missing:
            raise ValueError(f"WordPress install verification failed. Missing: {', '.join(missing)}")
        if progress is not None:
            progress(55, "WordPress files extracted and configured.")

    def _wordpress_tables_installed(self, database_name: str, table_prefix: str) -> bool:
        command_info = self._container.database_service._client_command_prefix()
        if command_info is None:
            return False
        prefix, _, env = command_info
        escaped_name = database_name.replace("`", "``")
        escaped_prefix = table_prefix.replace("\\", "\\\\").replace("'", "\\'")
        sql = (
            "SELECT COUNT(*) FROM information_schema.tables "
            f"WHERE table_schema='{escaped_name}' "
            f"AND table_name LIKE '{escaped_prefix}%';"
        )
        try:
            result = subprocess.run(
                prefix + ["--batch", "--skip-column-names", "-e", sql],
                capture_output=True,
                text=True,
                check=True,
                env=env,
            )
            count = int((result.stdout or "0").strip().splitlines()[-1] or "0")
            return count >= 6
        except Exception:
            return False

    def _resolve_bundled_composer(self) -> Path | None:
        return self._container.binary_locator.latest_composer_phar()

    def _write_laravel_env(
        self,
        project_root: Path,
        database_enabled: bool,
        database_name: str,
        app_url: str,
    ) -> None:
        env_path = project_root / ".env"
        if not env_path.exists():
            example_path = project_root / ".env.example"
            if example_path.exists():
                env_path.write_text(example_path.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
            else:
                env_path.write_text("", encoding="utf-8")
        content = env_path.read_text(encoding="utf-8", errors="replace")
        settings = self._container.settings_service.get_settings()
        updates: dict[str, str] = {"APP_URL": app_url.strip() or "http://localhost"}
        if database_enabled:
            cleaned_name = database_name.strip()
            updates.update(
                {
                    "DB_CONNECTION": "mysql",
                    "DB_HOST": "127.0.0.1",
                    "DB_PORT": str(settings.database_port),
                    "DB_USERNAME": "root",
                    "DB_PASSWORD": self._container.database_service.root_password(),
                    "DB_DATABASE": cleaned_name or "laravel",
                    "SESSION_DRIVER": "database",
                    "QUEUE_CONNECTION": "database",
                    "CACHE_STORE": "database",
                }
            )
        else:
            sqlite_db = project_root / "database" / "database.sqlite"
            sqlite_db.parent.mkdir(parents=True, exist_ok=True)
            sqlite_db.touch(exist_ok=True)
            updates.update(
                {
                    "DB_CONNECTION": "sqlite",
                    "DB_DATABASE": str(sqlite_db),
                    "DB_HOST": "",
                    "DB_PORT": "",
                    "DB_USERNAME": "",
                    "DB_PASSWORD": "",
                    "SESSION_DRIVER": "file",
                    "QUEUE_CONNECTION": "sync",
                    "CACHE_STORE": "file",
                }
            )
        for key, value in updates.items():
            replacement = f"{key}={value}"
            pattern = re.compile(rf"(?m)^(?:#\s*)?{re.escape(key)}=.*$")
            if pattern.search(content):
                content = pattern.sub(replacement, content, count=1)
            else:
                if content and not content.endswith("\n"):
                    content += "\n"
                content += replacement + "\n"
        env_path.write_text(content.rstrip() + "\n", encoding="utf-8")

    def _prepare_laravel_project(
        self,
        payload: dict,
        project_root: Path,
        php_version: str,
        progress: Callable[[int, str], None] | None = None,
    ) -> None:
        runtime = self._container.php_runtime_service.require_runtime(php_version)
        composer_phar = self._resolve_bundled_composer()
        if composer_phar is None:
            raise ValueError("Bundled Composer runtime is missing. Install Composer runtime first.")
        laravel_version = str(payload.get("laravel_version", "")).strip()
        if not laravel_version:
            versions = self._laravel_versions()
            laravel_version = versions[0] if versions else ""
        if laravel_version and not re.match(r"^[0-9A-Za-z.*^~_-]+$", laravel_version):
            raise ValueError("Laravel version is invalid.")
        project_root.parent.mkdir(parents=True, exist_ok=True)
        if progress is not None:
            progress(10, "Preparing Laravel installer...")
            progress(18, "Creating Laravel project with Composer...")
        env = os.environ.copy()
        env["COMPOSER_ALLOW_SUPERUSER"] = "1"
        env["COMPOSER_HOME"] = str(self._container.runtime_paths.temp_dir / "composer-home")
        Path(env["COMPOSER_HOME"]).mkdir(parents=True, exist_ok=True)
        try:
            command = [
                runtime.php_path,
                str(composer_phar),
                "create-project",
                "laravel/laravel",
                str(project_root),
            ]
            if laravel_version:
                command.append(laravel_version)
            command.extend(["--prefer-dist", "--no-interaction"])
            subprocess.run(
                command,
                check=True,
                capture_output=True,
                text=True,
                timeout=1800,
                env=env,
            )
        except subprocess.CalledProcessError as exc:
            stderr = (exc.stderr or "").strip()
            stdout = (exc.stdout or "").strip()
            detail = stderr or stdout or str(exc)
            raise ValueError(f"Laravel install failed: {detail}") from exc
        except Exception as exc:
            raise ValueError(f"Laravel install failed: {exc}") from exc

        if progress is not None:
            progress(52, "Writing Laravel .env database settings...")

        self._write_laravel_env(
            project_root=project_root,
            database_enabled=bool(payload.get("database_enabled", False)),
            database_name=str(payload.get("database_name", "")).strip(),
            app_url=("https://" if bool(payload.get("ssl_enabled", False)) else "http://") + str(payload.get("local_domain", "")).strip(),
        )
        if progress is not None:
            progress(58, "Laravel project ready.")

    def _prepare_composer_project(
        self,
        payload: dict,
        project_root: Path,
        php_version: str,
        progress: Callable[[int, str], None] | None = None,
    ) -> None:
        """Create one of the Composer-based site presets selected by the QML wizard."""
        package = str(payload.get("composer_package", "")).strip()
        if not re.match(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", package):
            raise ValueError("Composer package is invalid.")
        runtime = self._container.php_runtime_service.require_runtime(php_version)
        composer_phar = self._resolve_bundled_composer()
        if composer_phar is None:
            raise ValueError("Bundled Composer runtime is missing. Install Composer runtime first.")
        project_root.parent.mkdir(parents=True, exist_ok=True)
        if progress is not None:
            progress(10, "Preparing Composer project...")
            progress(18, "Creating project with Composer...")
        env = os.environ.copy()
        env["COMPOSER_ALLOW_SUPERUSER"] = "1"
        env["COMPOSER_HOME"] = str(self._container.runtime_paths.temp_dir / "composer-home")
        Path(env["COMPOSER_HOME"]).mkdir(parents=True, exist_ok=True)
        try:
            subprocess.run(
                [runtime.php_path, str(composer_phar), "create-project", package, str(project_root), "--prefer-dist", "--no-interaction"],
                check=True,
                capture_output=True,
                text=True,
                timeout=1800,
                env=env,
            )
        except subprocess.CalledProcessError as exc:
            detail = (exc.stderr or exc.stdout or str(exc)).strip()
            raise ValueError(f"Composer install failed: {detail}") from exc
        except Exception as exc:
            raise ValueError(f"Composer install failed: {exc}") from exc
        if progress is not None:
            progress(52, "Composer project ready...")

    def _guess_project_framework(self, project_root: Path) -> str:
        if not project_root.exists() or not project_root.is_dir():
            return FrameworkPreset.CUSTOM.value

        if (project_root / "wp-config.php").exists() or (project_root / "wp-content").exists() or (project_root / "wp-admin").exists():
            return FrameworkPreset.WORDPRESS.value

        if (project_root / "artisan").exists():
            return FrameworkPreset.LARAVEL.value

        composer_json = project_root / "composer.json"
        composer_text = ""
        if composer_json.exists():
            try:
                composer_text = composer_json.read_text(encoding="utf-8", errors="ignore")
            except Exception:
                composer_text = ""

        composer_lower = composer_text.lower()
        if "laravel/framework" in composer_lower or "laravel/laravel" in composer_lower:
            return FrameworkPreset.LARAVEL.value
        if "symfony/" in composer_lower or (project_root / "symfony.lock").exists() or (project_root / "bin" / "console").exists():
            return FrameworkPreset.SYMFONY.value
        if "codeigniter4/framework" in composer_lower or (project_root / "spark").exists() or (project_root / "app" / "Config" / "App.php").exists():
            return FrameworkPreset.CODEIGNITER.value
        return FrameworkPreset.CUSTOM.value

    def _install_wordpress_site(
        self,
        payload: dict,
        local_domain: str,
        project_root: Path,
        php_version: str,
    ) -> None:
        admin_user = str(payload.get("wordpress_admin_user", "")).strip()
        admin_password = str(payload.get("wordpress_admin_password", ""))
        if not admin_user or not admin_password:
            raise ValueError("WordPress admin username and password are required.")

        active_web_server = self._container.settings_service.get_settings().active_web_server.value
        web_status = self._container.stack_service.status()
        current_web = next((service for service in web_status.services if service.service_id == active_web_server), None)
        if current_web is None or current_web.state.value != "running":
            raise ValueError("Web server must be running before installing WordPress database tables.")

        table_prefix = str(payload.get("wordpress_database_prefix", "")).strip() or "wp_"
        database_name = str(payload.get("database_name", "")).strip()
        database_host = str(payload.get("wordpress_database_host", "")).strip() or "localhost"
        database_port_raw = str(payload.get("wordpress_database_port", "")).strip()
        settings_port = int(self._container.settings_service.get_settings().database_port)
        database_port = int(database_port_raw) if database_port_raw.isdigit() else settings_port
        wp_command = self._resolve_wp_command_for_php(php_version)
        if wp_command is None:
            self._install_wordpress_site_via_php_fallback(
                payload=payload,
                local_domain=local_domain,
                database_name=database_name,
                table_prefix=table_prefix,
            )
            return

        env = self._wp_cli_env()
        site_url = "https://" + local_domain if bool(payload.get("ssl_enabled", False)) else "http://" + local_domain
        title = str(payload.get("name", "")).strip() or local_domain
        admin_email = str(payload.get("wordpress_admin_email", "")).strip() or f"{admin_user}@{local_domain}"
        timeout_seconds = 90

        self._run_wp_cli(
            wp_command,
            ["db", "check", "--path=" + str(project_root)],
            cwd=project_root,
            env=env,
            timeout_seconds=timeout_seconds,
            details={"database_host": database_host, "database_port": database_port},
            retry_ssl_disabled=True,
        )
        self._run_wp_cli(
            wp_command,
            [
                "core",
                "install",
                "--path=" + str(project_root),
                "--url=" + site_url,
                "--title=" + title,
                "--admin_user=" + admin_user,
                "--admin_password=" + admin_password,
                "--admin_email=" + admin_email,
                "--skip-email",
            ],
            cwd=project_root,
            env=env,
            timeout_seconds=timeout_seconds,
            details={"table_prefix": table_prefix, "database_host": database_host, "database_port": database_port},
        )
        self._run_wp_cli(
            wp_command,
            ["core", "is-installed", "--path=" + str(project_root)],
            cwd=project_root,
            env=env,
            timeout_seconds=timeout_seconds,
        )
        self._run_wp_cli(
            wp_command,
            ["option", "get", "siteurl", "--path=" + str(project_root)],
            cwd=project_root,
            env=env,
            timeout_seconds=timeout_seconds,
        )
        self._run_wp_cli(
            wp_command,
            ["db", "check", "--path=" + str(project_root)],
            cwd=project_root,
            env=env,
            timeout_seconds=timeout_seconds,
            retry_ssl_disabled=True,
        )

    def _resolve_wp_command_for_php(self, php_version: str) -> list[str] | None:
        php_runtime = self._container.php_runtime_service.require_runtime(php_version)
        php_path = Path(str(php_runtime.php_path or "").strip())
        if not php_path.exists():
            php_home = Path(str(php_runtime.home or "").strip())
            fallback_php = php_home / "bin" / "php"
            if fallback_php.exists():
                php_path = fallback_php
        if not php_path.exists():
            raise ValueError(f"Selected PHP runtime binary is missing: {php_path}")
        managed_wp_cli = self._container.binary_locator.latest_wp_cli_phar()
        if managed_wp_cli is not None:
            return [str(php_path).strip(), str(managed_wp_cli).strip()]

        for location in self._wp_cli_fallback_locations():
            if location.exists() and location.is_file():
                if location.suffix == ".phar":
                    return [str(php_path).strip(), str(location).strip()]
                if os.access(location, os.X_OK):
                    return [str(location).strip()]
        return None

    def _wp_cli_fallback_locations(self) -> list[Path]:
        return [
            Path("/opt/homebrew/bin/wp"),
            Path("/usr/local/bin/wp"),
            Path.home() / ".composer" / "vendor" / "bin" / "wp",
            Path.home() / ".wp-cli" / "bin" / "wp",
        ]

    def _wp_cli_env(self) -> dict[str, str]:
        env = os.environ.copy()
        current_path = env.get("PATH", "")
        extra_path_parts = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            str(Path.home() / ".composer" / "vendor" / "bin"),
            str(Path.home() / ".wp-cli" / "bin"),
        ]
        merged_path = ":".join([part for part in extra_path_parts + [current_path] if part])
        env["PATH"] = merged_path
        return env

    def _run_wp_cli(
        self,
        wp_command: list[str],
        args: list[str],
        *,
        cwd: Path,
        env: dict[str, str],
        timeout_seconds: int,
        details: dict[str, object] | None = None,
        retry_ssl_disabled: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        command = [*wp_command, *args]
        try:
            return subprocess.run(
                command,
                cwd=str(cwd),
                env=env,
                capture_output=True,
                text=True,
                check=True,
                timeout=timeout_seconds,
            )
        except subprocess.TimeoutExpired as exc:
            payload = {
                "stage": "wp_cli_timeout",
                "command": command,
                "timeout_seconds": timeout_seconds,
                "stdout": exc.stdout or "",
                "stderr": exc.stderr or "",
                "details": details or {},
            }
            LOGGER.error("WordPress install WP-CLI timeout: %s", json.dumps(payload, ensure_ascii=True))
            raise ValueError(
                json.dumps(payload, ensure_ascii=True)
            ) from exc
        except subprocess.CalledProcessError as exc:
            stderr_text = exc.stderr or ""
            if retry_ssl_disabled and ("TLS/SSL error" in stderr_text or "certificate" in stderr_text.lower()):
                retry_variants = [
                    [*command, "--skip-ssl"],
                    [*command, "--ssl-mode=DISABLED"],
                ]
                for retry_command in retry_variants:
                    try:
                        return subprocess.run(
                            retry_command,
                            cwd=str(cwd),
                            env=env,
                            capture_output=True,
                            text=True,
                            check=True,
                            timeout=timeout_seconds,
                        )
                    except Exception:
                        continue
            payload = {
                "stage": "wp_cli_failed",
                "command": command,
                "returncode": exc.returncode,
                "stdout": exc.stdout or "",
                "stderr": stderr_text,
                "details": details or {},
            }
            LOGGER.error("WordPress install WP-CLI failed: %s", json.dumps(payload, ensure_ascii=True))
            raise ValueError(
                json.dumps(payload, ensure_ascii=True)
            ) from exc

    def _install_wordpress_site_via_php_fallback(
        self,
        payload: dict,
        local_domain: str,
        database_name: str,
        table_prefix: str,
    ) -> None:
        install_url = f"http://{local_domain}/wp-admin/install.php?step=2"
        form_data = urllib.parse.urlencode(
            {
                "weblog_title": str(payload.get("name", "")).strip() or local_domain,
                "user_name": str(payload.get("wordpress_admin_user", "")).strip(),
                "admin_password": str(payload.get("wordpress_admin_password", "")),
                "admin_password2": str(payload.get("wordpress_admin_password", "")),
                "admin_email": f"{str(payload.get('wordpress_admin_user', '')).strip()}@{local_domain}",
                "blog_public": "0",
                "pw_weak": "1",
                "Submit": "Install WordPress",
                "language": "en_US",
            }
        ).encode("utf-8")
        request = urllib.request.Request(
            install_url,
            data=form_data,
            headers=self._request_headers({
                "User-Agent": "ServerEngine/1.0",
                "Content-Type": "application/x-www-form-urlencoded",
            }),
            method="POST",
        )
        ready_url = f"http://{local_domain}/wp-admin/install.php"
        ready_error: Exception | None = None
        for _ in range(20):
            try:
                with urllib.request.urlopen(urllib.request.Request(ready_url, headers=self._request_headers({"User-Agent": "ServerEngine/1.0"})), timeout=5):
                    ready_error = None
                    break
            except Exception as exc:
                ready_error = exc
                time.sleep(0.3)
        if ready_error is not None:
            raise ValueError(f"WordPress install fallback failed: install page is not reachable yet: {ready_error}")
        try:
            with urllib.request.urlopen(request, timeout=60):
                pass
        except Exception as exc:
            raise ValueError(f"WordPress install fallback request failed: {exc}") from exc
        if database_name and self._wordpress_tables_installed(database_name, table_prefix):
            return
        raise ValueError("WordPress install fallback failed: database tables were not created.")

    def _create_site_internal(self, payload: dict, progress: Callable[[int, str], None] | None = None) -> str:
        from server_engine.core.models import FrameworkPreset, ServerType

        def step(percent: int, message: str) -> None:
            LOGGER.info("site_creation progress=%s message=%s", percent, message)
            if progress is not None:
                progress(percent, message)

        created_database_name: str | None = None
        created_project_root: Path | None = None
        site = None
        local_domain = ""
        framework = FrameworkPreset.GENERIC_PHP
        step(2, "Validating input...")

        try:
            local_domain = str(payload.get("local_domain", "")).strip().lower()
            project_path = str(payload.get("project_path", "")).strip()
            if not local_domain:
                raise ValueError("Domain is required.")
            if not LOCAL_DOMAIN_PATTERN.match(local_domain):
                raise ValueError("Domain may only use lowercase letters, numbers, hyphens, and dots, for example example.engine.")
            if not project_path:
                raise ValueError("Project path is required.")

            name = str(payload.get("name", "")).strip() or local_domain.split(".")[0]
            notes = str(payload.get("notes", "")).strip()
            default_php = self._container.settings_service.get_settings().default_php_version
            php_version = str(payload.get("php_version", "")).strip() or default_php
            ssl_enabled = bool(payload.get("ssl_enabled", False))
            ssl_enforce_tls = bool(payload.get("ssl_enforce_tls", False))
            ssl_allow_http = bool(payload.get("ssl_allow_http", True))
            database_enabled = bool(payload.get("database_enabled", False))
            database_name = str(payload.get("database_name", "")).strip() or None
            database_user = str(payload.get("database_user", "")).strip() or None
            create_starter = bool(payload.get("create_starter", False))
            template_choice = str(payload.get("template_choice", "")).strip().lower()
            requested_web_root = str(payload.get("web_root", "")).strip()
            framework_value = str(payload.get("framework_preset", "")).strip()
            framework = FrameworkPreset(framework_value) if framework_value in {"generic_php", "laravel", "wordpress", "custom", "symfony", "codeigniter"} else FrameworkPreset.GENERIC_PHP
            settings = self._container.settings_service.get_settings()
            server_type = ServerType(settings.active_web_server.value)
            project_root = Path(project_path).expanduser()

            if template_choice == "empty" and project_root.exists():
                if not project_root.is_dir() or any(project_root.iterdir()):
                    raise ValueError(
                        "Empty sites can only be created in a new or empty folder. "
                        "Choose Custom Site for an existing project."
                    )

            if framework == FrameworkPreset.GENERIC_PHP:
                guessed_framework = self._guess_project_framework(project_root)
                if guessed_framework != FrameworkPreset.CUSTOM.value:
                    framework = FrameworkPreset(guessed_framework)
                    LOGGER.info("site_creation framework_guess=%s project_path=%s", guessed_framework, project_root)

            generated_project = framework in {FrameworkPreset.WORDPRESS, FrameworkPreset.LARAVEL} or bool(str(payload.get("composer_package", "")).strip())
            if generated_project and project_root.exists() and (not project_root.is_dir() or any(project_root.iterdir())):
                raise ValueError("Choose a new or empty folder for this preset. Choose Custom Site for an existing project.")

            if framework == FrameworkPreset.WORDPRESS:
                if not database_name:
                    raise ValueError("WordPress database name is required.")
                database_check_message = self.validateNewDatabaseName(database_name)
                if database_check_message:
                    raise ValueError(database_check_message)
                created_project_root = project_root
                step(10, "Downloading WordPress...")
                self._prepare_wordpress_project(payload, project_root, database_name, database_user or "root", progress=step)
            elif framework == FrameworkPreset.LARAVEL:
                created_project_root = project_root
                self._prepare_laravel_project(payload, project_root, php_version=php_version, progress=step)
            elif str(payload.get("composer_package", "")).strip():
                created_project_root = project_root
                self._prepare_composer_project(payload, project_root, php_version=php_version, progress=step)

            if database_enabled and database_name:
                step(60, "Creating database...")
                database_check_message = self.validateNewDatabaseName(database_name)
                if database_check_message:
                    raise ValueError(database_check_message)
                database_result = self._container.database_service.create_database(database_name, "utf8mb4")
                if not database_result.success:
                    raise ValueError(database_result.message)
                created_database_name = database_name
                verify_result = self._container.database_service.list_databases()
                if not verify_result.success:
                    raise ValueError(verify_result.message or "Database verification failed.")
                database_names = {
                    str(entry.get("name", "")).strip().lower()
                    for entry in verify_result.payload.get("databases", [])
                }
                if database_name.lower() not in database_names:
                    raise ValueError(f"Database verification failed. Missing database: {database_name}")
                step(68, "Database ready.")

            web_root = "public" if framework == FrameworkPreset.LARAVEL else "."
            if requested_web_root:
                web_root = requested_web_root
            else:
                for candidate in ("public", "public_html", "web"):
                    if (project_root / candidate).is_dir():
                        web_root = candidate
                        break

            step(72, "Creating site and generating web server config...")
            site = self._container.site_service.create_site(
                name=name,
                local_domain=local_domain,
                project_path=project_path,
                web_root=web_root,
                php_version=php_version,
                framework_preset=framework,
                server_type=server_type,
                ssl_enabled=ssl_enabled,
                ssl_enforce_tls=ssl_enforce_tls,
                ssl_allow_http=ssl_allow_http,
                database_enabled=database_enabled,
                database_name=database_name,
                database_user=database_user,
                notes=notes,
            )

            if ssl_enabled:
                step(80, "Generating SSL certificate...")
                cert_result = self._container.config_service.ensure_site_ssl_certificate(site)
                if not cert_result.success:
                    raise ValueError(cert_result.message)
                self._container.config_service.write_site_configs(site, apache_port=settings.apache_port)

            if framework in {FrameworkPreset.WORDPRESS, FrameworkPreset.LARAVEL, FrameworkPreset.CUSTOM, FrameworkPreset.GENERIC_PHP}:
                step(85, "Reloading web server route...")
                web_service_id = settings.active_web_server.value
                status = self._container.stack_service.status()
                web_service = next((item for item in status.services if item.service_id == web_service_id), None)
                if web_service is None or web_service.state.value != "running":
                    raise ValueError("Start Apache or Nginx before creating the site.")
                self._container.stack_service.stop_service(web_service_id)
                start_result = self._container.stack_service.start_service(web_service_id)
                if start_result.state.value == "error":
                    raise ValueError(start_result.message or "Failed to restart web server after site creation.")
                if framework == FrameworkPreset.WORDPRESS:
                    step(90, "Web server ready, installing WordPress schema...")
                    step(92, "Installing WordPress database tables...")
                    self._install_wordpress_site(payload, local_domain, project_root, php_version)
                    step(96, "WordPress database tables installed.")

            project_root = Path(site.project_path)
            project_root.mkdir(parents=True, exist_ok=True)
            if create_starter and framework != FrameworkPreset.WORDPRESS:
                starter_file = project_root / "index.html"
                if not starter_file.exists():
                    starter_file.write_text(
                        "<!doctype html>\n"
                        "<html><head><meta charset=\"utf-8\"><title>"
                        f"{site.local_domain}"
                        "</title></head><body><h1>"
                        f"{site.local_domain}"
                        "</h1></body></html>\n",
                        encoding="utf-8",
                    )

            step(100, "Site created.")
            return f"Created site: {site.local_domain}"
        except Exception:
            if created_database_name:
                try:
                    self._container.database_service.drop_database(created_database_name)
                except Exception:
                    pass
            if created_project_root is not None and created_project_root.exists():
                try:
                    shutil.rmtree(created_project_root)
                except Exception:
                    pass
            LOGGER.exception(
                "site_creation failed domain=%s framework=%s project_path=%s",
                local_domain or str(payload.get("local_domain", "")).strip().lower(),
                getattr(framework, "value", framework),
                str(payload.get("project_path", "")).strip(),
            )
            raise

    def _cleanup_site_creation_job(self) -> None:
        if self._site_creation_thread is not None:
            self._site_creation_thread.deleteLater()
        self._site_creation_thread = None
        self._site_creation_worker = None
        self._site_creation_busy = False
        self._site_creation_cancel_requested = False
        self.actionStateChanged.emit()

    @Slot(int, str)
    def _on_site_creation_progress(self, value: int, message: str) -> None:
        self.siteCreationProgressChanged.emit(max(0, min(int(value), 100)), message or "")

    @Slot(bool, str)
    def _on_site_creation_completed(self, success: bool, message: str) -> None:
        LOGGER.info("site_creation completed success=%s message=%s", success, message)
        self._last_operation_message = message
        self._last_operation_error = not success
        if success:
            self.dataChanged.emit()
        self.operationFeedbackChanged.emit()
        self.siteCreationCompleted.emit(success, message)

    @Slot("QVariantMap", result=bool)
    def createSiteAsync(self, payload: dict) -> bool:
        if self._site_creation_busy:
            self._last_operation_message = "Another site creation is in progress. Please wait."
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False

        self._site_creation_cancel_requested = False
        thread = QThread(self)
        worker = SiteCreationWorker(self, dict(payload))
        worker.moveToThread(thread)
        thread.started.connect(worker.run)
        worker.progressChanged.connect(self._on_site_creation_progress)
        worker.completed.connect(self._on_site_creation_completed)
        worker.completed.connect(thread.quit)
        worker.completed.connect(worker.deleteLater)
        thread.finished.connect(self._cleanup_site_creation_job)
        thread.finished.connect(thread.deleteLater)
        self._site_creation_thread = thread
        self._site_creation_worker = worker
        self._site_creation_busy = True
        self.actionStateChanged.emit()
        thread.start()
        return True

    @Slot(result=bool)
    def cancelSiteCreation(self) -> bool:
        if not self._site_creation_busy:
            return False
        self._site_creation_cancel_requested = True
        self._last_operation_message = "Site creation cancelled."
        self._last_operation_error = False
        self.operationFeedbackChanged.emit()
        return True

    @Slot()
    def reportNoSelectedWebsite(self) -> None:
        self._last_operation_message = "Select a website first."
        self._last_operation_error = True
        self.operationFeedbackChanged.emit()

    @Slot()
    def exportWebsitesAndProjects(self) -> None:
        parent = QApplication.activeWindow()
        default_name = f"server-engine-websites-{datetime.now().strftime('%Y%m%d-%H%M%S')}.json"
        target_path, _ = QFileDialog.getSaveFileName(
            parent,
            "Export Websites",
            default_name,
            "JSON Files (*.json);;All Files (*)",
        )
        if not target_path:
            return
        try:
            sites = [site.to_dict() for site in self._container.site_service.list_sites()]
            node_projects = [project.to_dict() for project in self._container.node_project_service.list_projects()]
            payload = {
                "version": 1,
                "exported_at": datetime.now().isoformat(),
                "sites": sites,
                "node_projects": node_projects,
            }
            Path(target_path).write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")
            self._last_operation_message = f"Exported websites to {target_path}"
            self._last_operation_error = False
            self.operationFeedbackChanged.emit()
        except Exception as exc:
            self._last_operation_message = f"Export websites failed: {exc}"
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()

    @Slot()
    def importWebsitesAndProjects(self) -> None:
        from server_engine.core.models import FrameworkPreset, ServerType

        parent = QApplication.activeWindow()
        answer = QMessageBox.warning(
            parent,
            "Import Websites",
            "Import will overwrite existing websites/projects with the same domain. Continue?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.Cancel,
            QMessageBox.StandardButton.Cancel,
        )
        if answer != QMessageBox.StandardButton.Yes:
            return

        source_path, _ = QFileDialog.getOpenFileName(
            parent,
            "Import Websites",
            "",
            "JSON Files (*.json);;All Files (*)",
        )
        if not source_path:
            return

        try:
            payload = json.loads(Path(source_path).read_text(encoding="utf-8"))
            if not isinstance(payload, dict):
                raise ValueError("Invalid import payload.")

            raw_sites = payload.get("sites", [])
            raw_projects = payload.get("node_projects", [])
            if not isinstance(raw_sites, list) or not isinstance(raw_projects, list):
                raise ValueError("Invalid import payload format.")

            site_repo = self._container.site_service.repository
            node_repo = self._container.node_project_service.repository
            imported_sites = 0
            imported_projects = 0

            for item in raw_sites:
                if not isinstance(item, dict):
                    continue
                local_domain = str(item.get("local_domain", "")).strip().lower()
                if not local_domain:
                    continue
                conflicting_project = node_repo.get_by_domain(local_domain)
                if conflicting_project is not None:
                    self._container.node_project_service.delete_project(conflicting_project.id)
                existing_site = site_repo.get_by_domain(local_domain)

                name = str(item.get("name", "")).strip() or local_domain
                project_path = str(item.get("project_path", "")).strip()
                web_root = str(item.get("web_root", "public")).strip() or "public"
                php_version = str(item.get("php_version", "")).strip() or "8.3"
                notes = str(item.get("notes", "")).strip()
                aliases = item.get("domain_aliases", [])
                if not isinstance(aliases, list):
                    aliases = []
                aliases = [str(value).strip().lower() for value in aliases if str(value).strip()]
                tags = item.get("tags", [])
                if not isinstance(tags, list):
                    tags = []
                tags = [str(value).strip() for value in tags if str(value).strip()]
                framework_value = str(item.get("framework_preset", "generic_php")).strip() or "generic_php"
                server_type_value = str(item.get("server_type", "apache")).strip() or "apache"
                ssl_enabled = bool(item.get("ssl_enabled", False))
                ssl_enforce_tls = bool(item.get("ssl_enforce_tls", False))
                ssl_allow_http = bool(item.get("ssl_allow_http", True))
                database_enabled = bool(item.get("database_enabled", False))
                database_name = str(item.get("database_name", "")).strip() or None
                database_user = str(item.get("database_user", "")).strip() or None

                framework = FrameworkPreset(framework_value) if framework_value in {"generic_php", "laravel", "wordpress", "custom", "symfony", "codeigniter"} else FrameworkPreset.GENERIC_PHP
                server_type = ServerType(server_type_value) if server_type_value in {"apache", "nginx"} else ServerType.APACHE

                if existing_site is None:
                    created_site = self._container.site_service.create_site(
                        name=name,
                        local_domain=local_domain,
                        project_path=project_path,
                        web_root=web_root,
                        php_version=php_version,
                        framework_preset=framework,
                        server_type=server_type,
                        ssl_enabled=ssl_enabled,
                        ssl_enforce_tls=ssl_enforce_tls,
                        ssl_allow_http=ssl_allow_http,
                        database_enabled=database_enabled,
                        database_name=database_name,
                        database_user=database_user,
                        notes=notes,
                        tags=tags,
                    )
                    if aliases:
                        self._container.site_service.update_site(created_site.id, domain_aliases=aliases)
                else:
                    self._container.site_service.update_site(
                        existing_site.id,
                        name=name,
                        local_domain=local_domain,
                        project_path=project_path,
                        web_root=web_root,
                        php_version=php_version,
                        framework_preset=framework,
                        server_type=server_type,
                        domain_aliases=aliases,
                        ssl_enabled=ssl_enabled,
                        ssl_enforce_tls=ssl_enforce_tls,
                        ssl_allow_http=ssl_allow_http,
                        database_enabled=database_enabled,
                        database_name=database_name,
                        database_user=database_user,
                        notes=notes,
                        tags=tags,
                    )
                imported_sites += 1

            for item in raw_projects:
                if not isinstance(item, dict):
                    continue
                local_domain = str(item.get("local_domain", "")).strip().lower()
                if not local_domain:
                    continue
                conflicting_site = site_repo.get_by_domain(local_domain)
                if conflicting_site is not None:
                    self._container.site_service.delete_site(conflicting_site.id)
                existing_project = node_repo.get_by_domain(local_domain)

                name = str(item.get("name", "")).strip() or local_domain
                project_path = str(item.get("project_path", "")).strip()
                document_root = str(item.get("document_root", "")).strip() or project_path
                node_version = str(item.get("node_version", "")).strip()
                run_script_name = str(item.get("run_script_name", "")).strip() or "custom"
                run_script_command = str(item.get("run_script_command", "")).strip() or "npm run dev"
                notes = str(item.get("notes", "")).strip()
                ssl_enabled = bool(item.get("ssl_enabled", False))
                try:
                    port = int(item.get("port", 3000))
                except (TypeError, ValueError):
                    port = 3000

                if existing_project is None:
                    self._container.node_project_service.create_project(
                        name=name,
                        local_domain=local_domain,
                        project_path=project_path,
                        document_root=document_root,
                        node_version=node_version,
                        run_script_name=run_script_name,
                        run_script_command=run_script_command,
                        port=port,
                        notes=notes,
                        ssl_enabled=ssl_enabled,
                    )
                else:
                    self._container.node_project_service.update_project(
                        existing_project.id,
                        name=name,
                        local_domain=local_domain,
                        project_path=project_path,
                        document_root=document_root,
                        node_version=node_version,
                        run_script_name=run_script_name,
                        run_script_command=run_script_command,
                        port=port,
                        notes=notes,
                        ssl_enabled=ssl_enabled,
                    )
                imported_projects += 1

            self.dataChanged.emit()
            self._last_operation_message = (
                f"Imported {imported_sites} website(s) and {imported_projects} node project(s)."
            )
            self._last_operation_error = False
            self.operationFeedbackChanged.emit()
        except Exception as exc:
            self._last_operation_message = f"Import websites failed: {exc}"
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()

    @Slot("QVariantMap", result=bool)
    def createSite(self, payload: dict) -> bool:
        try:
            self._last_operation_message = self._create_site_internal(payload)
            self._last_operation_error = False
            self.dataChanged.emit()
            self.operationFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False

    @Slot(str, result="QVariantList")
    def siteDirectoryChoices(self, project_path: str) -> list[str]:
        choices = ["/"]
        try:
            project_root = Path(project_path).expanduser()
            if project_path.strip() and project_root.exists() and project_root.is_dir():
                directories = sorted(
                    child.name
                    for child in project_root.iterdir()
                    if child.is_dir() and not child.name.startswith(".")
                )
                choices.extend(directories)
        except Exception:
            pass

        unique_choices: list[str] = []
        for choice in choices:
            if choice not in unique_choices:
                unique_choices.append(choice)
        return unique_choices

    @Slot(str, result="QVariantMap")
    def siteDetails(self, site_id: str) -> dict:
        try:
            site = self._container.site_service.get_site(site_id)
            if site is None:
                return {}
            data = site.to_dict()
            cert_path, key_path = self._container.config_service.site_ssl_paths(site)
            data["ssl_certificate_path"] = str(cert_path)
            data["ssl_key_path"] = str(key_path)
            data["ssl_certificate_exists"] = self._container.config_service.site_ssl_exists(site)
            data["browse_url"] = (
                f"http://{site.local_domain}"
                + (f":{self._container.settings_service.get_settings().apache_port}" if self._container.settings_service.get_settings().apache_port != 80 else "")
            )
            LOGGER.debug(
                "siteDetails site_id=%s ssl_enabled=%s ssl_enforce_tls=%s ssl_allow_http=%s cert_exists=%s cert_path=%s key_path=%s",
                site.id,
                site.ssl_enabled,
                site.ssl_enforce_tls,
                site.ssl_allow_http,
                data["ssl_certificate_exists"],
                data["ssl_certificate_path"],
                data["ssl_key_path"],
            )
            return data
        except Exception:
            return {}

    @Slot(str, str, result=bool)
    def updateSiteWebRoot(self, site_id: str, web_root: str) -> bool:
        try:
            site = self._container.site_service.update_site(site_id, web_root=web_root)
            self._last_operation_message = (
                f"Updated running directory for {site.local_domain}. "
                "Reload/restart web server to apply."
            )
            self._last_operation_error = False
            self.dataChanged.emit()
            self.operationFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False

    @Slot(str, str, result=bool)
    def updateSiteProjectPath(self, site_id: str, project_path: str) -> bool:
        try:
            site = self._container.site_service.update_site(site_id, project_path=project_path)
            self._last_operation_message = (
                f"Updated site directory for {site.local_domain}. "
                "Reload/restart web server to apply."
            )
            self._last_operation_error = False
            self.dataChanged.emit()
            self.operationFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False

    @Slot(str, str, str, result=bool)
    def updateSiteDirectorySettings(self, site_id: str, project_path: str, web_root: str) -> bool:
        try:
            site = self._container.site_service.update_site(
                site_id,
                project_path=project_path.strip(),
                web_root=web_root.strip(),
            )
            self._last_operation_message = (
                f"Updated directory settings for {site.local_domain}. "
                "Reload/restart web server to apply."
            )
            self._last_operation_error = False
            self.dataChanged.emit()
            self.operationFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False

    @Slot(str, str, result=bool)
    def updateSitePhpVersion(self, site_id: str, php_version: str) -> bool:
        try:
            site = self._container.site_service.update_site(site_id, php_version=php_version)
            self._last_operation_message = f"Updated PHP version for {site.local_domain}"
            self._last_operation_error = False
            self.dataChanged.emit()
            self.operationFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False

    @Slot(str, bool, result=bool)
    def updateSiteSslEnabled(self, site_id: str, ssl_enabled: bool) -> bool:
        try:
            LOGGER.debug(
                "updateSiteSslEnabled requested site_id=%s ssl_enabled=%s",
                site_id,
                ssl_enabled,
            )
            site = self._container.site_service.update_site(site_id, ssl_enabled=ssl_enabled)
            if ssl_enabled:
                cert_result = self._container.config_service.ensure_site_ssl_certificate(site)
                if not cert_result.success:
                    self._container.site_service.update_site(site_id, ssl_enabled=False)
                    raise ValueError(cert_result.message)
            LOGGER.debug(
                "updateSiteSslEnabled saved site_id=%s ssl_enabled=%s",
                site.id,
                site.ssl_enabled,
            )
            state_label = "enabled" if site.ssl_enabled else "disabled"
            self._last_operation_message = f"SSL {state_label} for {site.local_domain}. Save SSL options to apply."
            self._last_operation_error = False
            self.dataChanged.emit()
            self.operationFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False

    @Slot(str, bool, bool, result=bool)
    def updateSiteSslOptions(self, site_id: str, ssl_enforce_tls: bool, ssl_allow_http: bool) -> bool:
        try:
            LOGGER.debug(
                "updateSiteSslOptions requested site_id=%s ssl_enforce_tls=%s ssl_allow_http=%s",
                site_id,
                ssl_enforce_tls,
                ssl_allow_http,
            )
            site = self._container.site_service.update_site(
                site_id,
                ssl_enforce_tls=bool(ssl_enforce_tls),
                ssl_allow_http=bool(ssl_allow_http),
            )
            LOGGER.debug(
                "updateSiteSslOptions saved site_id=%s ssl_enforce_tls=%s ssl_allow_http=%s",
                site.id,
                site.ssl_enforce_tls,
                site.ssl_allow_http,
            )
            self._container.config_service.write_site_configs(
                site, apache_port=self._container.settings_service.get_settings().apache_port
            )
            settings = self._container.settings_service.get_settings()
            web_service_id = settings.active_web_server.value
            status = self._container.stack_service.status()
            web_service = next((item for item in status.services if item.service_id == web_service_id), None)
            if web_service is not None and web_service.state.value == "running":
                self._container.stack_service.stop_service(web_service_id)
                start_result = self._container.stack_service.start_service(web_service_id)
                if start_result.state.value == "error":
                    raise ValueError(start_result.message or "Failed to restart web server after SSL settings update.")
            persisted = self._container.site_service.get_site(site_id)
            if persisted is not None:
                LOGGER.debug(
                    "updateSiteSslOptions persisted site_id=%s ssl_enforce_tls=%s ssl_allow_http=%s",
                    persisted.id,
                    persisted.ssl_enforce_tls,
                    persisted.ssl_allow_http,
                )
            self._last_operation_message = f"Updated SSL options for {site.local_domain}. Web server reloaded."
            self._last_operation_error = False
            self.dataChanged.emit()
            self.operationFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False

    @Slot(str, bool, bool, bool, result=bool)
    def updateSiteSslSettings(self, site_id: str, ssl_enabled: bool, ssl_enforce_tls: bool, ssl_allow_http: bool) -> bool:
        try:
            LOGGER.debug(
                "updateSiteSslSettings requested site_id=%s ssl_enabled=%s ssl_enforce_tls=%s ssl_allow_http=%s",
                site_id,
                ssl_enabled,
                ssl_enforce_tls,
                ssl_allow_http,
            )
            site = self._container.site_service.update_site(
                site_id,
                ssl_enabled=bool(ssl_enabled),
                ssl_enforce_tls=bool(ssl_enforce_tls),
                ssl_allow_http=bool(ssl_allow_http),
            )
            LOGGER.debug(
                "updateSiteSslSettings saved site_id=%s ssl_enabled=%s ssl_enforce_tls=%s ssl_allow_http=%s",
                site.id,
                site.ssl_enabled,
                site.ssl_enforce_tls,
                site.ssl_allow_http,
            )
            if ssl_enabled:
                cert_result = self._container.config_service.ensure_site_ssl_certificate(site)
                if not cert_result.success:
                    self._container.site_service.update_site(site_id, ssl_enabled=False)
                    raise ValueError(cert_result.message)
            self._container.config_service.write_site_configs(
                site, apache_port=self._container.settings_service.get_settings().apache_port
            )
            settings = self._container.settings_service.get_settings()
            web_service_id = settings.active_web_server.value
            status = self._container.stack_service.status()
            web_service = next((item for item in status.services if item.service_id == web_service_id), None)
            if web_service is not None and web_service.state.value == "running":
                self._container.stack_service.stop_service(web_service_id)
                start_result = self._container.stack_service.start_service(web_service_id)
                if start_result.state.value == "error":
                    raise ValueError(start_result.message or "Failed to restart web server after SSL settings update.")
            persisted = self._container.site_service.get_site(site_id)
            if persisted is not None:
                LOGGER.debug(
                    "updateSiteSslSettings persisted site_id=%s ssl_enabled=%s ssl_enforce_tls=%s ssl_allow_http=%s",
                    persisted.id,
                    persisted.ssl_enabled,
                    persisted.ssl_enforce_tls,
                    persisted.ssl_allow_http,
                )
            self._last_operation_message = f"Updated SSL settings for {site.local_domain}. Web server reloaded."
            self._last_operation_error = False
            self.dataChanged.emit()
            self.operationFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False

    @Slot(str, result=bool)
    def trustSiteCertificate(self, site_id: str) -> bool:
        try:
            site = self._container.site_service.get_site(site_id)
            if site is None:
                raise ValueError("Site not found.")
            cert_path, _ = self._container.config_service.site_ssl_paths(site)
            if not cert_path.exists():
                raise ValueError("Certificate file does not exist. Generate certificate first.")
            if sys.platform != "darwin":
                raise ValueError("Certificate trust is only supported on macOS.")
            security_bin = shutil.which("security") or "/usr/bin/security"
            login_keychain = str(Path.home() / "Library" / "Keychains" / "login.keychain-db")
            completed = subprocess.run(
                [
                    security_bin,
                    "add-trusted-cert",
                    "-d",
                    "-r",
                    "trustRoot",
                    "-k",
                    login_keychain,
                    str(cert_path),
                ],
                capture_output=True,
                text=True,
            )
            if completed.returncode != 0:
                detail = (completed.stderr or completed.stdout or "Certificate trust failed.").strip()
                raise ValueError(f"{detail} Try adding the certificate to your login keychain manually.")
            self._last_operation_message = f"Trusted SSL certificate for {site.local_domain}"
            self._last_operation_error = False
            LOGGER.info("Trusted SSL certificate for site_id=%s domain=%s cert=%s", site.id, site.local_domain, str(cert_path))
            self.operationFeedbackChanged.emit()
            return True
        except Exception as exc:
            LOGGER.warning("Failed to trust SSL certificate for site_id=%s: %s", site_id, exc)
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False

    @Slot(str, result=bool)
    def createSiteSelfSignedCertificate(self, site_id: str) -> bool:
        try:
            site = self._container.site_service.get_site(site_id)
            if site is None:
                raise ValueError(f"Site not found: {site_id}")
            result = self._container.config_service.ensure_site_ssl_certificate(site)
            if not result.success:
                raise ValueError(result.message)
            self._last_operation_message = result.message
            self._last_operation_error = False
            self.operationFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False

    @Slot(str, "QVariantList", result=bool)
    def updateSiteDomains(self, site_id: str, domains: list) -> bool:
        try:
            normalized = [str(item).strip().lower() for item in domains if str(item).strip()]
            if not normalized:
                raise ValueError("At least one domain is required.")
            for value in normalized:
                if not LOCAL_DOMAIN_PATTERN.match(value):
                    raise ValueError(
                        f"Invalid domain '{value}'. Use lowercase letters, numbers, hyphens and dots only (example.engine)."
                    )
            site = self._container.site_service.update_site(
                site_id,
                local_domain=normalized[0],
                domain_aliases=normalized[1:],
            )
            self._last_operation_message = f"Updated domains for {site.local_domain}"
            self._last_operation_error = False
            self.dataChanged.emit()
            self.operationFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False

    @Slot(str, result=str)
    def siteDefaultDocuments(self, site_id: str) -> str:
        try:
            site = self._container.site_service.get_site(site_id)
            if site is None:
                raise ValueError("Site not found.")
            config_paths = self._container.config_service.site_config_paths(site)

            apache_docs: list[str] = []
            nginx_docs: list[str] = []

            apache_path = config_paths.get("apache")
            if apache_path and Path(apache_path).exists():
                apache_content = Path(apache_path).read_text(encoding="utf-8")
                for match in re.findall(r"(?im)^\s*DirectoryIndex\s+(.+?)\s*$", apache_content):
                    apache_docs.extend([token.strip() for token in match.split() if token.strip()])

            nginx_path = config_paths.get("nginx")
            if nginx_path and Path(nginx_path).exists():
                nginx_content = Path(nginx_path).read_text(encoding="utf-8")
                match = re.search(r"(?im)^\s*index\s+(.+?)\s*;\s*$", nginx_content)
                if match:
                    nginx_docs.extend([token.strip() for token in match.group(1).split() if token.strip()])

            chosen = apache_docs if apache_docs else nginx_docs
            if not chosen:
                chosen = ["index.php", "index.html", "index.htm", "default.php", "default.htm", "default.html"]

            deduped: list[str] = []
            for doc in chosen:
                if doc and doc not in deduped:
                    deduped.append(doc)
            return "\n".join(deduped)
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return ""

    @Slot(str, str, result=bool)
    def saveSiteDefaultDocuments(self, site_id: str, documents_text: str) -> bool:
        try:
            site = self._container.site_service.get_site(site_id)
            if site is None:
                raise ValueError("Site not found.")
            lines = [line.strip() for line in documents_text.splitlines()]
            docs: list[str] = []
            for line in lines:
                if not line:
                    continue
                if line not in docs:
                    docs.append(line)
            if not docs:
                raise ValueError("At least one default document is required.")

            config_paths = self._container.config_service.site_config_paths(site)
            apache_path = config_paths.get("apache")
            nginx_path = config_paths.get("nginx")

            apache_line = f"    DirectoryIndex {' '.join(docs)}"
            nginx_line = f"    index {' '.join(docs)};"

            if nginx_path and Path(nginx_path).exists():
                nginx_file = Path(nginx_path)
                nginx_content = nginx_file.read_text(encoding="utf-8")
                if re.search(r"(?im)^\s*index\s+.+?;\s*$", nginx_content):
                    nginx_content = re.sub(r"(?im)^\s*index\s+.+?;\s*$", nginx_line, nginx_content, count=1)
                else:
                    nginx_content = re.sub(
                        r"(?im)^(\s*root\s+.+?;\s*)$",
                        r"\1\n" + nginx_line,
                        nginx_content,
                        count=1,
                    )
                nginx_file.write_text(nginx_content, encoding="utf-8")

            if apache_path and Path(apache_path).exists():
                apache_file = Path(apache_path)
                apache_content = apache_file.read_text(encoding="utf-8")
                if re.search(r"(?im)^\s*DirectoryIndex\s+.+?$", apache_content):
                    apache_content = re.sub(r"(?im)^\s*DirectoryIndex\s+.+?$", apache_line, apache_content)
                else:
                    apache_content = re.sub(
                        r'(?im)^(\s*DocumentRoot\s+".+?"\s*)$',
                        r"\1\n" + apache_line,
                        apache_content,
                    )
                apache_file.write_text(apache_content, encoding="utf-8")

            self._last_operation_message = (
                f"Updated default documents for {site.local_domain}. Reload/restart web server to apply."
            )
            self._last_operation_error = False
            self.operationFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False

    @Slot(str, result=str)
    def siteNginxRewriteRules(self, site_id: str) -> str:
        default_rules = ""
        try:
            site = self._container.site_service.get_site(site_id)
            if site is None:
                raise ValueError("Site not found.")
            config_paths = self._container.config_service.site_config_paths(site)
            nginx_path = config_paths.get("nginx")
            if not nginx_path or not Path(nginx_path).exists():
                return default_rules
            content = Path(nginx_path).read_text(encoding="utf-8")
            match = re.search(r"(?ms)^\s*location\s*/\s*\{.*?^\s*\}", content)
            if not match:
                return default_rules
            return match.group(0).strip()
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return default_rules

    @Slot(str, str, result=bool)
    def saveSiteNginxRewriteRules(self, site_id: str, rules_text: str) -> bool:
        try:
            settings = self._container.settings_service.get_settings()
            if settings.active_web_server.value != "nginx":
                raise ValueError("URL rewrite editor is available only when active web server is Nginx.")

            site = self._container.site_service.get_site(site_id)
            if site is None:
                raise ValueError("Site not found.")
            config_paths = self._container.config_service.site_config_paths(site)
            nginx_path = config_paths.get("nginx")
            if not nginx_path or not Path(nginx_path).exists():
                raise ValueError("Nginx site config was not found.")

            raw = str(rules_text or "").strip()
            if not raw:
                raise ValueError("Rewrite rules cannot be empty.")
            if "location" not in raw or "/" not in raw:
                raise ValueError("Rewrite rules must include a location / block.")

            lines = [line.rstrip() for line in raw.splitlines()]
            formatted = "\n".join(("    " + line.lstrip()) if line.strip() else "" for line in lines)

            nginx_file = Path(nginx_path)
            content = nginx_file.read_text(encoding="utf-8")
            pattern = r"(?ms)^\s*location\s*/\s*\{.*?^\s*\}"
            if re.search(pattern, content):
                updated = re.sub(pattern, formatted, content, count=1)
            else:
                updated = re.sub(
                    r"(?im)^(\s*index\s+.+?;\s*)$",
                    r"\1\n\n" + formatted,
                    content,
                    count=1,
                )
            if updated == content:
                raise ValueError("Unable to update location / block in Nginx config.")
            nginx_file.write_text(updated, encoding="utf-8")

            self._last_operation_message = (
                f"Updated URL rewrite for {site.local_domain}. Restart Nginx to apply."
            )
            self._last_operation_error = False
            self.operationFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False

    @Slot(str, str, result=bool)
    def testSiteNginxRewriteRulesDraft(self, site_id: str, rules_text: str) -> bool:
        try:
            settings = self._container.settings_service.get_settings()
            if settings.active_web_server.value != "nginx":
                raise ValueError("URL rewrite test is available only when active web server is Nginx.")
            site = self._container.site_service.get_site(site_id)
            if site is None:
                raise ValueError("Site not found.")
            # Ensure include targets exist before nginx -t
            try:
                sites = self._container.site_service.list_sites()
                node_projects = self._container.node_project_service.list_projects()
                proxies = self._container.proxy_service.list_proxies()
                self._container.config_service.write_nginx_stack_config(
                    sites,
                    node_projects=node_projects,
                    proxies=proxies,
                    port=settings.apache_port,
                )
                for item in sites:
                    self._container.config_service.write_site_configs(
                        item,
                        apache_port=settings.apache_port,
                    )
            except Exception:
                pass
            config_paths = self._container.config_service.site_config_paths(site)
            nginx_path = config_paths.get("nginx")
            if not nginx_path or not Path(nginx_path).exists():
                self._container.config_service.write_site_configs(site, apache_port=settings.apache_port)
                nginx_path = self._container.config_service.site_config_paths(site).get("nginx")
            if not nginx_path or not Path(nginx_path).exists():
                raise ValueError("Nginx site config was not found.")

            raw = str(rules_text or "").strip()
            if not raw:
                raise ValueError("Rewrite rules cannot be empty.")
            lines = [line.rstrip() for line in raw.splitlines()]
            formatted = "\n".join(("    " + line.lstrip()) if line.strip() else "" for line in lines)

            nginx_file = Path(nginx_path)
            original = nginx_file.read_text(encoding="utf-8")
            pattern = r"(?ms)^\s*location\s*/\s*\{.*?^\s*\}"
            if re.search(pattern, original):
                draft = re.sub(pattern, formatted, original, count=1)
            else:
                draft = re.sub(
                    r"(?im)^(\s*index\s+.+?;\s*)$",
                    r"\1\n\n" + formatted,
                    original,
                    count=1,
                )
            if draft == original:
                raise ValueError("Unable to apply draft rewrite rules for testing.")

            nginx_file.write_text(draft, encoding="utf-8")
            try:
                command = [
                    str(self._container.binary_locator.nginx_binary()),
                    "-t",
                    "-c",
                    str(self._container.config_service.nginx_main_config_path()),
                    "-p",
                    str(self._container.binary_locator.nginx_home()),
                ]
                result = subprocess.run(command, capture_output=True, text=True, check=False)
                output = (result.stdout or "").strip()
                error = (result.stderr or "").strip()
                if result.returncode == 0:
                    self._last_operation_message = ("Nginx rewrite test passed.\n" + (error or output)).strip()
                    self._last_operation_error = False
                else:
                    self._last_operation_message = "Nginx rewrite test failed.\n" + (error or output or f"Exit code {result.returncode}")
                    self._last_operation_error = True
                self.operationFeedbackChanged.emit()
                return result.returncode == 0
            finally:
                nginx_file.write_text(original, encoding="utf-8")
        except Exception as exc:
            self._last_operation_message = f"Nginx rewrite test failed: {exc}"
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False

    @Slot(str, result=str)
    def siteActiveConfigPath(self, site_id: str) -> str:
        try:
            site = self._container.site_service.get_site(site_id)
            if site is None:
                raise ValueError("Site not found.")
            paths = self._container.config_service.site_config_paths(site)
            settings = self._container.settings_service.get_settings()
            target = "nginx" if settings.active_web_server.value == "nginx" else "apache"
            path = paths.get(target)
            if path is None:
                raise ValueError("Site config path is unavailable.")
            return str(path)
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return ""

    @Slot(str, result=str)
    def siteActiveConfigContent(self, site_id: str) -> str:
        try:
            config_path = self.siteActiveConfigPath(site_id)
            if not config_path:
                return ""
            path = Path(config_path)
            if not path.exists():
                return ""
            return path.read_text(encoding="utf-8")
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return ""

    @Slot(str, str, result=bool)
    def saveSiteActiveConfig(self, site_id: str, content: str) -> bool:
        try:
            config_path = self.siteActiveConfigPath(site_id)
            if not config_path:
                raise ValueError("Site config path is unavailable.")
            path = Path(config_path)
            if not path.exists():
                raise ValueError("Site config file does not exist.")
            path.write_text(str(content), encoding="utf-8")
            settings = self._container.settings_service.get_settings()
            server_label = "Nginx" if settings.active_web_server.value == "nginx" else "Apache"
            self._last_operation_message = f"Saved {server_label} site config. Restart web server to apply."
            self._last_operation_error = False
            self.operationFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False

    @Slot(str, result=bool)
    def siteOpenBasedirEnabled(self, site_id: str) -> bool:
        try:
            site = self._container.site_service.get_site(site_id)
            if site is None:
                return True
            paths = self._container.config_service.site_config_paths(site)
            apache_path = paths.get("apache")
            nginx_path = paths.get("nginx")
            if apache_path and Path(apache_path).exists():
                apache_content = Path(apache_path).read_text(encoding="utf-8")
                if re.search(r"(?im)^\s*php_admin_value\s+open_basedir\s+", apache_content):
                    return True
            if nginx_path and Path(nginx_path).exists():
                nginx_content = Path(nginx_path).read_text(encoding="utf-8")
                if re.search(r"(?im)^\s*fastcgi_param\s+PHP_ADMIN_VALUE\s+\"open_basedir=", nginx_content):
                    return True
            return False
        except Exception:
            return True

    @Slot(str, bool, result=bool)
    def saveSiteOpenBasedir(self, site_id: str, enabled: bool) -> bool:
        try:
            site = self._container.site_service.get_site(site_id)
            if site is None:
                raise ValueError("Site not found.")
            paths = self._container.config_service.site_config_paths(site)
            apache_path = paths.get("apache")
            nginx_path = paths.get("nginx")
            open_basedir_value = (
                f"{Path(site.project_path)}:/tmp:/private/tmp:/private/var/tmp"
            )

            if apache_path and Path(apache_path).exists():
                apache_file = Path(apache_path)
                content = apache_file.read_text(encoding="utf-8")
                content = re.sub(
                    r"(?im)^\s*php_admin_value\s+open_basedir\s+\".*?\"\s*\n?",
                    "",
                    content,
                )
                if enabled:
                    insert_line = f'        php_admin_value open_basedir "{open_basedir_value}"\n'
                    content = re.sub(
                        r'(?im)^(\s*<Directory\s+".+?"\s*>\s*\n)(\s*AllowOverride\s+All\s*\n)',
                        r"\1\2" + insert_line,
                        content,
                        count=1,
                    )
                apache_file.write_text(content, encoding="utf-8")

            if nginx_path and Path(nginx_path).exists():
                nginx_file = Path(nginx_path)
                content = nginx_file.read_text(encoding="utf-8")
                content = re.sub(
                    r"(?im)^\s*fastcgi_param\s+PHP_ADMIN_VALUE\s+\"open_basedir=.*?\";\s*\n?",
                    "",
                    content,
                )
                if enabled:
                    insert_line = f'        fastcgi_param PHP_ADMIN_VALUE "open_basedir={open_basedir_value}";\n'
                    content = re.sub(
                        r"(?im)^(\s*fastcgi_param\s+SCRIPT_FILENAME\s+\$document_root\$fastcgi_script_name;\s*\n)",
                        r"\1" + insert_line,
                        content,
                        count=1,
                    )
                nginx_file.write_text(content, encoding="utf-8")

            self._last_operation_message = (
                "Updated open_basedir setting. Restart web server to apply."
            )
            self._last_operation_error = False
            self.operationFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False

    @Slot(str, result=bool)
    def siteWriteAccessLogEnabled(self, site_id: str) -> bool:
        try:
            site = self._container.site_service.get_site(site_id)
            if site is None:
                return True
            paths = self._container.config_service.site_config_paths(site)
            apache_path = paths.get("apache")
            nginx_path = paths.get("nginx")
            apache_enabled = True
            nginx_enabled = True
            if apache_path and Path(apache_path).exists():
                text = Path(apache_path).read_text(encoding="utf-8")
                apache_enabled = re.search(r"(?im)^\s*CustomLog\s+", text) is not None
            if nginx_path and Path(nginx_path).exists():
                text = Path(nginx_path).read_text(encoding="utf-8")
                nginx_enabled = re.search(r"(?im)^\s*access_log\s+off\s*;\s*$", text) is None
            return apache_enabled and nginx_enabled
        except Exception:
            return True

    @Slot(str, result=bool)
    def sitePasswordAccessEnabled(self, site_id: str) -> bool:
        try:
            site = self._container.site_service.get_site(site_id)
            if site is None:
                return False
            paths = self._container.config_service.site_config_paths(site)
            apache_path = paths.get("apache")
            nginx_path = paths.get("nginx")
            apache_enabled = False
            nginx_enabled = False
            if apache_path and Path(apache_path).exists():
                text = Path(apache_path).read_text(encoding="utf-8")
                apache_enabled = re.search(r"(?im)^\s*AuthType\s+Basic\s*$", text) is not None
            if nginx_path and Path(nginx_path).exists():
                text = Path(nginx_path).read_text(encoding="utf-8")
                nginx_enabled = re.search(r"(?im)^\s*auth_basic\s+\".+\";\s*$", text) is not None
            return apache_enabled or nginx_enabled
        except Exception:
            return False

    @Slot(str, result=str)
    def sitePasswordAccessUsername(self, site_id: str) -> str:
        try:
            auth_path = self._site_auth_file_path(site_id)
            if not auth_path.exists():
                return ""
            first = auth_path.read_text(encoding="utf-8").splitlines()
            if not first:
                return ""
            return first[0].split(":", 1)[0].strip()
        except Exception:
            return ""

    def _site_auth_file_path(self, site_id: str) -> Path:
        auth_dir = self._container.runtime_paths.config_dir / "auth"
        auth_dir.mkdir(parents=True, exist_ok=True)
        return auth_dir / f"{site_id}.htpasswd"

    def _htpasswd_sha1(self, password: str) -> str:
        digest = hashlib.sha1(password.encode("utf-8")).digest()
        return "{SHA}" + base64.b64encode(digest).decode("ascii")

    @Slot(str, bool, bool, str, str, result=bool)
    def saveSiteDirectorySecuritySettings(
        self,
        site_id: str,
        write_access_log: bool,
        password_access: bool,
        auth_username: str,
        auth_password: str,
    ) -> bool:
        try:
            site = self._container.site_service.get_site(site_id)
            if site is None:
                raise ValueError("Site not found.")
            paths = self._container.config_service.site_config_paths(site)
            apache_path = paths.get("apache")
            nginx_path = paths.get("nginx")
            auth_file = self._site_auth_file_path(site_id)
            username = str(auth_username or "").strip()
            password = str(auth_password or "")
            if password_access and not username:
                raise ValueError("Username is required when Password access is enabled.")

            if password_access:
                if password:
                    hashed = self._htpasswd_sha1(password)
                    auth_file.write_text(f"{username}:{hashed}\n", encoding="utf-8")
                elif not auth_file.exists():
                    raise ValueError("Password is required the first time Password access is enabled.")
            else:
                auth_file.unlink(missing_ok=True)

            if apache_path and Path(apache_path).exists():
                apache_file = Path(apache_path)
                apache_content = apache_file.read_text(encoding="utf-8")
                apache_content = re.sub(r"(?im)^\s*#?\s*CustomLog\s+\".+?\"\s+common\s*$", "", apache_content)
                logs_dir = self._container.config_service.apache_logs_dir()
                custom_log_line = f'    CustomLog "{logs_dir / f"{site.id}-access.log"}" common\n'
                if write_access_log:
                    apache_content = re.sub(
                        r'(?im)^(\s*ErrorLog\s+".+?"\s*\n)',
                        r"\1" + custom_log_line,
                        apache_content,
                        count=1,
                    )

                apache_content = re.sub(r"(?im)^\s*AuthType\s+Basic\s*$\n?", "", apache_content)
                apache_content = re.sub(r"(?im)^\s*AuthName\s+\".*?\"\s*$\n?", "", apache_content)
                apache_content = re.sub(r"(?im)^\s*AuthUserFile\s+\".*?\"\s*$\n?", "", apache_content)
                apache_content = re.sub(r"(?im)^\s*Require\s+valid-user\s*$\n?", "", apache_content)
                if password_access:
                    auth_block = (
                        f'        AuthType Basic\n'
                        f'        AuthName "Restricted"\n'
                        f'        AuthUserFile "{auth_file}"\n'
                        f'        Require valid-user\n'
                    )
                    apache_content = re.sub(
                        r'(?im)^(\s*<Directory\s+".+?"\s*>\s*\n)(\s*AllowOverride\s+All\s*\n)\s*Require\s+all\s+granted\s*$',
                        r"\1\2" + auth_block,
                        apache_content,
                        count=1,
                    )
                apache_file.write_text(apache_content, encoding="utf-8")

            if nginx_path and Path(nginx_path).exists():
                nginx_file = Path(nginx_path)
                nginx_content = nginx_file.read_text(encoding="utf-8")
                nginx_content = re.sub(r"(?im)^\s*access_log\s+.+?;\s*$", "", nginx_content)
                access_log_line = f'    access_log "{self._container.config_service.nginx_logs_dir() / f"{site.id}-access.log"}";\n'
                if write_access_log:
                    nginx_content = re.sub(
                        r'(?im)^(\s*error_log\s+".+?"\s*;\s*\n)',
                        r"\1" + access_log_line,
                        nginx_content,
                        count=1,
                    )
                else:
                    nginx_content = re.sub(
                        r'(?im)^(\s*error_log\s+".+?"\s*;\s*\n)',
                        r"\1    access_log off;\n",
                        nginx_content,
                        count=1,
                    )

                nginx_content = re.sub(r"(?im)^\s*auth_basic\s+\".*?\";\s*$\n?", "", nginx_content)
                nginx_content = re.sub(r"(?im)^\s*auth_basic_user_file\s+.+?;\s*$\n?", "", nginx_content)
                if password_access:
                    auth_lines = (
                        '        auth_basic "Restricted";\n'
                        f'        auth_basic_user_file "{auth_file}";\n'
                    )
                    nginx_content = re.sub(
                        r"(?ms)^(\s*location\s*/\s*\{\n)",
                        r"\1" + auth_lines,
                        nginx_content,
                        count=1,
                    )
                nginx_file.write_text(nginx_content, encoding="utf-8")

            self._last_operation_message = (
                "Updated directory security settings. Restart web server to apply."
            )
            self._last_operation_error = False
            self.operationFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False

    @Slot(str, str, int, result=str)
    def siteResponseLogPath(self, site_id: str, tab_name: str, lines: int) -> str:
        del lines
        try:
            site = self._container.site_service.get_site(site_id)
            if site is None:
                return ""
            settings = self._container.settings_service.get_settings()
            server = settings.active_web_server.value
            is_error = str(tab_name or "").strip().lower().startswith("error")
            suffix = "error" if is_error else "access"
            if server == "nginx":
                logs_dir = self._container.config_service.nginx_logs_dir()
            else:
                logs_dir = self._container.config_service.apache_logs_dir()
            primary = logs_dir / f"{site.id}-{suffix}.log"
            ssl_variant = logs_dir / f"{site.id}-ssl-{suffix}.log"
            if primary.exists():
                return str(primary)
            if ssl_variant.exists():
                return str(ssl_variant)
            return str(primary)
        except Exception:
            return ""

    @Slot(str, str, int, result=str)
    def siteResponseLogContent(self, site_id: str, tab_name: str, lines: int) -> str:
        try:
            cleaned_lines = max(1, min(int(lines), 2000))
            site = self._container.site_service.get_site(site_id)
            if site is None:
                return ""
            settings = self._container.settings_service.get_settings()
            server = settings.active_web_server.value
            is_error = str(tab_name or "").strip().lower().startswith("error")
            suffix = "error" if is_error else "access"
            logs_dir = (
                self._container.config_service.nginx_logs_dir()
                if server == "nginx"
                else self._container.config_service.apache_logs_dir()
            )
            primary = logs_dir / f"{site.id}-{suffix}.log"
            ssl_variant = logs_dir / f"{site.id}-ssl-{suffix}.log"
            candidates = [primary, ssl_variant]
            existing = [candidate for candidate in candidates if candidate.exists()]

            if not existing:
                is_error = str(tab_name or "").strip().lower().startswith("error")
                if not is_error and not self.siteWriteAccessLogEnabled(site_id):
                    return "Access log is disabled for this site. Enable 'Write access log' in Directory and save."
                return f"Log file not found yet: {primary}"

            rows: list[str] = []
            for path in existing:
                text = path.read_text(encoding="utf-8", errors="replace")
                rows.extend(text.splitlines())
            return "\n".join(rows[-cleaned_lines:])
        except Exception as exc:
            return f"Unable to load log: {exc}"

    @Slot(str, str, result=bool)
    def testSiteActiveConfigDraft(self, site_id: str, draft_content: str) -> bool:
        try:
            config_path = self.siteActiveConfigPath(site_id)
            if not config_path:
                raise ValueError("Site config path is unavailable.")
            path = Path(config_path)
            if not path.exists():
                raise ValueError("Site config file does not exist.")

            original = path.read_text(encoding="utf-8")
            path.write_text(str(draft_content), encoding="utf-8")
            try:
                settings = self._container.settings_service.get_settings()
                if settings.active_web_server.value == "nginx":
                    try:
                        sites = self._container.site_service.list_sites()
                        node_projects = self._container.node_project_service.list_projects()
                        proxies = self._container.proxy_service.list_proxies()
                        self._container.config_service.write_nginx_stack_config(
                            sites,
                            node_projects=node_projects,
                            proxies=proxies,
                            port=settings.apache_port,
                        )
                    except Exception:
                        pass
                    command = [
                        str(self._container.binary_locator.nginx_binary()),
                        "-t",
                        "-c",
                        str(self._container.config_service.nginx_main_config_path()),
                        "-p",
                        str(self._container.binary_locator.nginx_home()),
                    ]
                    result = subprocess.run(command, capture_output=True, text=True, check=False)
                    output = (result.stdout or "").strip()
                    error = (result.stderr or "").strip()
                    if result.returncode == 0:
                        self._last_operation_message = ("Nginx config test passed.\n" + (error or output)).strip()
                        self._last_operation_error = False
                    else:
                        self._last_operation_message = "Nginx config test failed.\n" + (error or output or f"Exit code {result.returncode}")
                        self._last_operation_error = True
                else:
                    command = [
                        str(self._container.binary_locator.apache_httpd()),
                        "-t",
                        "-f",
                        str(self._container.config_service.apache_main_config_path()),
                        "-d",
                        str(self._container.binary_locator.apache_home()),
                    ]
                    result = subprocess.run(command, capture_output=True, text=True, check=False)
                    output = (result.stdout or "").strip()
                    error = (result.stderr or "").strip()
                    if result.returncode == 0:
                        self._last_operation_message = ("Apache config test passed.\n" + output).strip()
                        self._last_operation_error = False
                    else:
                        self._last_operation_message = "Apache config test failed.\n" + (error or output or f"Exit code {result.returncode}")
                        self._last_operation_error = True
                self.operationFeedbackChanged.emit()
                return result.returncode == 0
            finally:
                path.write_text(original, encoding="utf-8")
        except Exception as exc:
            self._last_operation_message = f"Config test failed: {exc}"
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False

    @Slot(str, bool, result=bool)
    def deleteSite(self, site_id: str, move_to_trash: bool = False) -> bool:
        try:
            cleaned = site_id.strip()
            if not cleaned:
                raise ValueError("Site ID is required.")
            deleted = self._container.site_service.delete_site(cleaned, move_to_trash=move_to_trash)
            if not deleted:
                raise ValueError("Site not found.")
            self._last_operation_message = "Website removed."
            self._last_operation_error = False
            self.dataChanged.emit()
            self.operationFeedbackChanged.emit()
            return True
        except Exception as exc:
            self._last_operation_message = str(exc)
            self._last_operation_error = True
            self.operationFeedbackChanged.emit()
            return False
