# Server Engine

Server Engine is a macOS desktop application and Python backend for managing a private local PHP web development stack. It is designed as an original implementation with a long-lived Python core, a PySide6 desktop interface for phase 1, and a clean contract for a future SwiftUI frontend.

## Product Direction

The codebase is structured as a product foundation rather than a prototype:

- domain models already cover sites, settings, services, logs, database metadata, backups, and runtime paths
- service orchestration is separated from GUI callbacks
- infrastructure concerns are isolated behind repositories, process/state gateways, path providers, and filesystem abstractions
- the CLI and GUI both call the same service layer
- the Python core can later be driven by SwiftUI through the CLI JSON contract or a future local API

## Current Phase 1 Scope

Implemented now:

- application bootstrap and runtime directory layout
- SQLite-backed persistence for sites and settings
- site create, update, delete, list, and detail retrieval
- durable domain models with validation
- Apache-first stack service abstraction with real subprocess lifecycle when a bundled `httpd` is present
- bundled runtime discovery from `~/Library/Application Support/Server Engine`
- per-site PHP version selection with bundled PHP runtimes
- bundled database runtime discovery with global active-version selection
- config generation scaffolding for Apache, Nginx, and PHP-FPM
- settings service
- logs service scaffolding
- hosts management abstraction
- database service contract with placeholder operations
- CLI entrypoint with site and stack commands
- PySide6 desktop shell with site list, detail panel, settings dialog, and logs panel
- pytest coverage for core phase-1 logic

Placeholder for later phases:

- real bundled Nginx, PHP-FPM, and MariaDB process execution
- real hosts file editing
- database import/export execution
- multi-PHP runtime support
- SSL certificates
- backup archives and snapshots
- deployment helpers

## Architecture

Project layout:

```text
src/server_engine/
  bootstrap.py
  main.py
  core/
    models.py
  services/
    site_service.py
    settings_service.py
    stack_service.py
    config_service.py
    log_service.py
    database_service.py
    health_service.py
  infrastructure/
    paths.py
    sqlite.py
    process_manager.py
    hosts.py
    repositories/
      site_repository.py
      settings_repository.py
  cli/
    app.py
  gui/
    app.py
    controller.py
    main_window.py
```

Layer boundaries:

- `core`: durable product models and validation rules
- `services`: application use cases and orchestration
- `infrastructure`: SQLite, filesystem paths, runtime state storage, process gateway, hosts abstraction
- `cli`: command interface intended to remain stable for future SwiftUI integration
- `gui`: PySide6 shell that delegates to services through a controller

## Runtime Layout

The app is built around a bundled/private stack strategy. Runtime directories are created under:

```text
~/Library/Application Support/Server Engine/
  bin/
  config/
    nginx/
    php/
    database/
    sites/
  logs/
  data/
  backups/
  runtime/
  temp/
  server_engine.db
```

Set `SERVER_ENGINE_HOME` to override the runtime root during development or tests.
When the default Application Support path is not writable, the source build falls back to `.server-engine-runtime/` in the current working directory.

## Prebuilt Apache Layout

The repository now supports a checked-in private Apache runtime at:

```text
prebuild/
  apache/
    current/
      bin/
        httpd
        apachectl
      modules/
      conf/
        mime.types
```

Lookup order for Apache is:

1. `SERVER_ENGINE_APACHE_HOME`
2. `prebuild/apache/current` inside the repo
3. `<runtime-root>/bin/apache/current`

That means during development you can drop a private Apache build into `prebuild/apache/current` and the CLI will use it directly. Later, the installer can copy the same folder into the final app/runtime location.

## Bundled PHP Runtime Layout

Build-time source runtimes are staged in:

```text
prebuild/
  php/
    php5.4.45/
    php5.6.40/
    php7.3.33/
    php7.4.33/
    php8.1.13/
    php8.2.0/
```

Packaged/distribution runtimes are produced in:

```text
dist/
  runtime/
    php/
      php7.4.33/
      php8.1.34/
      ...
```

Each runtime is expected to contain:

```text
bin/php
bin/php-cgi
bin/php-config
conf/
lib/php/extensions/<api>/*.so
```

The app discovers bundled PHP versions from:

```text
~/Library/Application Support/Server Engine/bin/php
```

Sites store a selected PHP version, and Apache/Nginx route `.php` requests to that version's bundled `php-cgi`.

### Build A Bundled PHP Runtime

You can build an official PHP source release directly into the repo layout with:

```bash
chmod +x scripts/install_php_runtime.sh
scripts/install_php_runtime.sh --version 8.5.0
```

That installs into:

```text
prebuild/php/php8.5.0/
```

Useful options:

```bash
scripts/install_php_runtime.sh --version 8.5.0 --jobs 8
scripts/install_php_runtime.sh --version 8.5.0 --minimal
scripts/install_php_runtime.sh --version 8.5.0 --configure-flags "--enable-pcntl --with-pear"
scripts/install_php_runtime.sh --version 7.4.33 --overwrite --extensions "redis,memcached,apcu,imagick,xdebug"
scripts/install_php_runtime.sh --version 8.1.34 --overwrite --extensions "redis,memcached,apcu,imagick,xdebug,intl"
```

Notes:

- the script downloads official source from `php.net`
- it installs directly into `prebuild/php/php<version>`
- it writes a starter `conf/php.ini` after install
- on macOS it also packages a self-contained distributable runtime automatically
- native build dependencies still need to exist on the machine
- extension selection is configurable with:
  - `--extensions "redis,memcached,apcu,imagick,xdebug,intl"`
  - `--skip-extension-check`
  - `--force-legacy-intl` (for PHP 5.x/7.x only)
- for legacy PHP (`5.x/7.x`), `intl` is skipped by default unless explicitly forced

### Package A PHP Runtime For macOS Distribution

The `prebuild/` folder is for development. `scripts/build_php_runtime.sh` already runs the
packaging step automatically on macOS. If you need to rerun packaging only, use:

```bash
chmod +x scripts/package_php_runtime_macos.sh
scripts/package_php_runtime_macos.sh --source prebuild/php/php8.5.0 --overwrite
```

That produces something like:

```text
~/Library/Application Support/Server Engine/bin/php/php8.5.0/
```

## PHP Extension Toggle Behavior

In PHP Runtime settings, the `Extensions` section is prebundled-only:

- enabling/disabling writes extension directives in runtime `php.ini`
- no in-app PECL compile/install is attempted
- if `.so` is not bundled in the selected runtime, toggle will fail with a bundled-runtime error

Cache safety rule in extension toggles:

- only one cache extension can be active at once among `redis`, `memcached`, `apcu`, `opcache`
- enabling one auto-disables the others after confirmation

## macOS App And Installer

For shipping, the intended flow is:

1. build packaged runtimes into `~/Library/Application Support/Server Engine/...`
2. build `Server Engine.app`
3. build a `.pkg` installer
4. installer copies:
   - `Server Engine.app` into `/Applications`
   - packaged runtimes into `~/Library/Application Support/Server Engine/bin/...`

Build the app bundle:

```bash
chmod +x scripts/build_macos_app.sh
scripts/build_macos_app.sh
```

That produces:

```text
dist/app/Server Engine.app
```

Build the installer package:

```bash
chmod +x scripts/build_macos_pkg.sh
scripts/build_macos_pkg.sh
```

That produces something like:

```text
dist/pkg/ServerEngine-0.1.0.pkg
```

Installer behavior:

- installs `Server Engine.app` into `/Applications`
- copies packaged runtimes from `~/Library/Application Support/Server Engine`
  into the logged-in user's Application Support runtime root
- creates missing runtime folders under `~/Library/Application Support/Server Engine`

Important:

- `pkgbuild` and `PyInstaller` are required on the build machine
- current scripts build an unsigned `.app` and unsigned `.pkg`
- for client distribution, you still need code signing and likely notarization

## Prebuilt Database Layout

Bundled database runtimes live in:

```text
prebuild/
  database/
    mysql-5.7.39/
    mariadb-11.4/
```

The app treats the database runtime as a global stack setting:

- one active database runtime at a time
- separate versioned runtime folders
- generated `my.cnf` under `config/database`
- separate data directory per runtime under `data/database/<runtime-id>`

This keeps future updates simple: add a new version folder, select it in settings, then migrate data later.

### Install A Bundled Database Runtime

You can stage a Homebrew database runtime directly into the repo layout with:

```bash
chmod +x scripts/install_database_runtime.sh
scripts/install_database_runtime.sh --formula mariadb --overwrite
```

That installs into something like:

```text
prebuild/database/mariadb-11.8.3/
```

Examples:

```bash
scripts/install_database_runtime.sh --formula mariadb --overwrite
scripts/install_database_runtime.sh --formula mariadb@11.4 --overwrite
scripts/install_database_runtime.sh --formula mysql --overwrite
```

Notes:

- the script uses Homebrew as the source of the database runtime
- it stages the runtime into `prebuild/database/<engine>-<version>`
- the app then discovers that version automatically on the next launch
- data migration between database versions is still a separate concern

## Installation

```bash
python -m venv .venv
source .venv/bin/activate
pip install -e .[dev]
```

## Run The GUI

```bash
server-engine-gui
```

or

```bash
python -m server_engine.main
```

Source-mode run (recommended in repo):

```bash
source .venv/bin/activate
PYTHONPATH=src python -m server_engine.main
```

Runtime mode overrides:

```bash
SERVER_ENGINE_RUNTIME_MODE=dist PYTHONPATH=src python -m server_engine.main
SERVER_ENGINE_RUNTIME_MODE=installed PYTHONPATH=src python -m server_engine.main
```

## Run The CLI

Examples:

```bash
server-engine stack status --json
server-engine stack paths --json
server-engine stack start apache
server-engine stack stop apache
server-engine php list --json
server-engine database list --json
server-engine database show --json
server-engine site list
server-engine site add --name demo --domain demo.engine --project-path /path/to/project
server-engine site add --name demo81 --domain demo81.engine --project-path /path/to/project --php-version 8.1
server-engine site show <site-id> --json
server-engine config apache --json
server-engine config paths --json
```

Direct source-mode examples:

```bash
PYTHONPATH=src python3 -m server_engine.cli.app --json stack paths
PYTHONPATH=src python3 -m server_engine.cli.app --json php list
PYTHONPATH=src python3 -m server_engine.cli.app --json database list
PYTHONPATH=src python3 -m server_engine.cli.app --json stack start apache
PYTHONPATH=src python3 -m server_engine.cli.app --json stack status apache
PYTHONPATH=src python3 -m server_engine.cli.app --json stack stop apache
```

## Tests

```bash
pytest
```

## SwiftUI Compatibility

The Python core is not written as a PySide application. The stable boundary is the service layer and the CLI contract on top of it.

Recommended future migration path:

1. keep `core`, `services`, and `infrastructure` intact
2. expand CLI commands to cover all stack and site operations with machine-readable JSON
3. let SwiftUI invoke the CLI and decode JSON responses
4. optionally replace the CLI bridge with a local API layer once the contract stabilizes

This keeps business logic in Python while allowing the desktop shell to move to native macOS UI later.

## Roadmap

### Phase 1

- foundational product architecture
- site CRUD
- SQLite persistence
- stack status model
- placeholder process orchestration
- GUI shell
- CLI shell
- config generation scaffolding

### Phase 2

- actual bundled Apache module/runtime validation
- PHP-FPM and MariaDB process management
- port conflict validation
- per-site config writes and reload flow
- hosts file editing workflow
- preset-aware site bootstrapping

### Phase 3

- multiple PHP versions
- SSL and local certificate flow
- database import/export execution
- backup archives and restore
- app updates and stack package management

### Phase 4

- native SwiftUI frontend
- optional local API bridge
- deployment helpers
- environment snapshots
