#!/bin/sh

set -eu

usage() {
    cat <<'EOF'
Usage:
  scripts/install_postgresql_runtime.sh
  scripts/install_postgresql_runtime.sh --formula postgresql@16 [options]

Install or stage a Homebrew PostgreSQL runtime into this repo's prebuild layout:
  prebuild/database/postgresql-<version>

Options:
  --formula <name>      Homebrew formula to install/stage.
                        Examples: postgresql, postgresql@17, postgresql@16, postgresql@15
  --version <version>   Override detected version
  --prefix <path>       Override target path
  --overwrite           Remove an existing target directory first
  --skip-install        Do not run brew install; only stage an already installed formula
  --homebrew-bottle     Stage the Homebrew bottle directly instead of building a relocatable runtime
  --skip-package        Skip the macOS self-contained packaging step
  --package-output <p>  Override packaged output directory
  --skip-deploy         Skip copying the packaged runtime into the app-managed runtime root
  --deploy-root <path>  Override deploy root. Default: <repo>/dist/runtime/database
  --help                Show this help

Examples:
  scripts/install_postgresql_runtime.sh
  scripts/install_postgresql_runtime.sh --formula postgresql@17 --overwrite
  scripts/install_postgresql_runtime.sh --formula postgresql@16 --overwrite
EOF
}

abspath() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s\n' "$(pwd)/$1" ;;
    esac
}

formula=""
version=""
prefix=""
overwrite="0"
skip_install="0"
homebrew_bottle="0"
skip_package="0"
package_output=""
skip_deploy="0"
deploy_root=""
packaged_dir=""
original_argc="$#"

interactive_pick_formula() {
    if ! command -v python3 >/dev/null 2>&1; then
        printf 'python3 is required for interactive selection.\n' >&2
        exit 1
    fi

    python3 <<'PY'
import json
import os
import subprocess
import termios
import tty

FORMULAS = [
    "postgresql",
    "postgresql@18",
    "postgresql@17",
    "postgresql@16",
    "postgresql@15",
    "postgresql@14",
    "postgresql@13",
]

def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)

def load_options():
    options = []

    for name in FORMULAS:
        result = run(["brew", "info", "--json=v2", name])
        if result.returncode != 0:
            continue

        try:
            payload = json.loads(result.stdout)
        except Exception:
            continue

        formulae = payload.get("formulae", [])
        if not formulae:
            continue

        formula = formulae[0]
        version = formula.get("versions", {}).get("stable", "")
        deprecated = formula.get("deprecated", False)
        disabled = formula.get("disabled", False)

        if not version:
            continue

        label = f"PostgreSQL {version}"

        if deprecated:
            label += " [deprecated]"

        if disabled:
            label += " [disabled]"

        options.append((name, label))

    def sort_key(item):
        name, _ = item
        raw_version = name.split("@", 1)[1] if "@" in name else ""
        if raw_version:
            try:
                version_key = tuple(int(part) for part in raw_version.split("."))
            except Exception:
                version_key = (0,)
        else:
            version_key = (999, 999)
        return tuple(-part for part in version_key)

    return sorted(options, key=sort_key)

def write(fd, text):
    os.write(fd, text.replace("\n", "\r\n").encode("utf-8", "replace"))

def draw(fd, options, index):
    write(fd, "\033[H\033[2J")
    write(fd, "Select PostgreSQL runtime and press Enter\n\n")
    for i, (_, label) in enumerate(options):
        prefix = "> " if i == index else "  "
        write(fd, f"{prefix}{label}\n")
    write(fd, "\nEnter = confirm, q = cancel\n")

def read_key(fd):
    ch = os.read(fd, 1)

    if not ch:
        return ""

    if ch != b"\x1b":
        return ch.decode("utf-8", "replace")

    seq = os.read(fd, 1)

    if not seq:
        return "ESC"

    if seq != b"[":
        return "ESC"

    final = os.read(fd, 1)

    if final == b"A":
        return "UP"

    if final == b"B":
        return "DOWN"

    return "ESC"

options = load_options()

if not options:
    raise SystemExit("No PostgreSQL runtime options found. Run: brew search postgresql")

fd = os.open("/dev/tty", os.O_RDWR)
old = termios.tcgetattr(fd)
index = 0

try:
    write(fd, "\033[?1049h\033[?25l")
    tty.setraw(fd)

    while True:
        draw(fd, options, index)
        ch = read_key(fd)

        if ch in ("q", "\x03", "ESC"):
            raise SystemExit(1)

        if ch in ("\r", "\n"):
            os.write(1, (options[index][0] + "\n").encode("utf-8"))
            break

        if ch == "UP" and index > 0:
            index -= 1
        elif ch == "DOWN" and index < len(options) - 1:
            index += 1
finally:
    termios.tcsetattr(fd, termios.TCSADRAIN, old)
    write(fd, "\033[?25h\033[?1049l")
    os.close(fd)
PY
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --formula)
            formula="${2:-}"
            shift 2
            ;;
        --version)
            version="${2:-}"
            shift 2
            ;;
        --prefix)
            prefix="$(abspath "${2:-}")"
            shift 2
            ;;
        --overwrite)
            overwrite="1"
            shift
            ;;
        --skip-install)
            skip_install="1"
            shift
            ;;
        --homebrew-bottle)
            homebrew_bottle="1"
            shift
            ;;
        --skip-package)
            skip_package="1"
            shift
            ;;
        --package-output)
            package_output="$(abspath "${2:-}")"
            shift 2
            ;;
        --skip-deploy)
            skip_deploy="1"
            shift
            ;;
        --deploy-root)
            deploy_root="$(abspath "${2:-}")"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown argument: %s\n\n' "$1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [ "$original_argc" -eq 0 ] && [ -z "$formula" ]; then
    selected_formula="$(interactive_pick_formula || true)"
    if [ -z "$selected_formula" ]; then
        printf 'No PostgreSQL runtime selected.\n' >&2
        exit 1
    fi
    formula="$selected_formula"
    overwrite="1"
fi

if [ -z "$formula" ]; then
    printf 'Missing required argument: --formula\n\n' >&2
    usage >&2
    exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
    printf 'Homebrew is required for this script.\n' >&2
    exit 1
fi

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

brew_prefix_for() {
    brew --prefix "$1" 2>/dev/null || true
}

append_dependency_flags() {
    dep_prefix="$(brew_prefix_for "$1")"
    [ -n "$dep_prefix" ] || return 0
    [ -d "$dep_prefix" ] || return 0

    CPPFLAGS="${CPPFLAGS:-} -I$dep_prefix/include"
    LDFLAGS="${LDFLAGS:-} -L$dep_prefix/lib"
    PKG_CONFIG_PATH="$dep_prefix/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    export CPPFLAGS LDFLAGS PKG_CONFIG_PATH
}

build_from_source() {
    source_version="$1"
    target_prefix="$2"
    work_root="${TMPDIR:-/tmp}/server-engine-postgresql-build"
    source_archive="$work_root/postgresql-$source_version.tar.bz2"
    source_dir="$work_root/postgresql-$source_version"
    source_url="https://ftp.postgresql.org/pub/source/v$source_version/postgresql-$source_version.tar.bz2"

    if ! command -v curl >/dev/null 2>&1; then
        printf 'curl is required to download PostgreSQL source.\n' >&2
        exit 1
    fi

    mkdir -p "$work_root"

    if [ ! -f "$source_archive" ]; then
        printf 'Downloading PostgreSQL source: %s\n' "$source_url"
        curl -L "$source_url" -o "$source_archive"
    fi

    rm -rf "$source_dir"
    tar -xjf "$source_archive" -C "$work_root"

    append_dependency_flags openssl@3
    append_dependency_flags readline
    append_dependency_flags zlib
    append_dependency_flags lz4
    append_dependency_flags zstd
    append_dependency_flags icu4c
    append_dependency_flags icu4c@78

    configure_flags="
        --prefix=$target_prefix
        --bindir=$target_prefix/bin
        --libdir=$target_prefix/lib
        --datadir=$target_prefix/share/postgresql
        --sysconfdir=$target_prefix/conf
        --with-openssl
        --with-readline
        --with-zlib
    "

    if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists icu-uc 2>/dev/null; then
        configure_flags="$configure_flags --with-icu"
    fi

    if [ -n "$(brew_prefix_for lz4)" ]; then
        configure_flags="$configure_flags --with-lz4"
    fi

    if [ -n "$(brew_prefix_for zstd)" ]; then
        configure_flags="$configure_flags --with-zstd"
    fi

    printf 'Building relocatable PostgreSQL runtime from source.\n'
    printf '  source: %s\n' "$source_dir"
    printf '  prefix: %s\n' "$target_prefix"

    (
        cd "$source_dir"
        # shellcheck disable=SC2086
        ./configure $configure_flags
        make -j"$(sysctl -n hw.ncpu 2>/dev/null || printf '4')"
        make install
    )
}

if [ "$skip_install" != "1" ] && [ "$homebrew_bottle" = "1" ]; then
    printf 'Reinstalling Homebrew formula: %s\n' "$formula"
    brew reinstall "$formula"
fi

formula_json="$(brew info --json=v2 "$formula" 2>/dev/null || true)"
stable_version="$(printf '%s' "$formula_json" | python3 -c 'import json,sys; data=json.load(sys.stdin); formulae=data.get("formulae", []); print(formulae[0]["versions"]["stable"] if formulae else "")' 2>/dev/null || true)"

if [ -z "$version" ]; then
    version="$stable_version"
    if [ -z "$version" ]; then
        printf 'Could not detect version for %s from Homebrew metadata.\n' "$formula" >&2
        exit 1
    fi
fi

engine="postgresql"

if [ -z "$prefix" ]; then
    prefix="$repo_root/prebuild/database/$engine-$version"
fi

if [ -e "$prefix" ] || [ -L "$prefix" ]; then
    if [ "$overwrite" = "1" ]; then
        printf 'Removing existing target directory: %s\n' "$prefix"
        rm -rf "$prefix"
    else
        printf 'Target directory already exists: %s\n' "$prefix" >&2
        printf 'Use --overwrite to replace it.\n' >&2
        exit 1
    fi
fi

mkdir -p "$(dirname "$prefix")"
mkdir -p "$prefix"

if [ "$homebrew_bottle" = "1" ]; then
    brew_prefix="$(brew --prefix "$formula" 2>/dev/null || true)"
    if [ -z "$brew_prefix" ] || [ ! -d "$brew_prefix" ]; then
        printf 'Formula prefix not found for %s\n' "$formula" >&2
        exit 1
    fi
    brew_prefix="$(CDPATH= cd -- "$brew_prefix" && pwd -P)"

    if [ ! -d "$brew_prefix/bin" ]; then
        printf 'Invalid Homebrew runtime prefix, missing bin/: %s\n' "$brew_prefix" >&2
        exit 1
    fi

    if [ ! -x "$brew_prefix/bin/postgres" ]; then
        printf 'Expected PostgreSQL server binary missing: %s/bin/postgres\n' "$brew_prefix" >&2
        exit 1
    fi

    if [ ! -x "$brew_prefix/bin/initdb" ]; then
        printf 'Expected PostgreSQL initdb binary missing: %s/bin/initdb\n' "$brew_prefix" >&2
        exit 1
    fi

    if [ ! -x "$brew_prefix/bin/psql" ]; then
        printf 'Expected PostgreSQL client binary missing: %s/bin/psql\n' "$brew_prefix" >&2
        exit 1
    fi

    printf 'Staging runtime from %s\n' "$brew_prefix"
    cp -R "$brew_prefix"/. "$prefix"
else
    build_from_source "$version" "$prefix"
fi

mkdir -p "$prefix/conf"
mkdir -p "$prefix/data"
mkdir -p "$prefix/logs"
mkdir -p "$prefix/tmp"

cat > "$prefix/conf/runtime.env" <<EOF
PGHOST=127.0.0.1
PGPORT=5432
PGDATA=data/main
PGLOG=logs/postgresql.log
EOF

cat > "$prefix/runtime.json" <<EOF
{
  "engine": "postgresql",
  "version": "$version",
  "serverBinary": "bin/postgres",
  "initBinary": "bin/initdb",
  "clientBinary": "bin/psql",
  "controlBinary": "bin/pg_ctl",
  "dataDir": "data/main",
  "logFile": "logs/postgresql.log",
  "defaultPort": 5432
}
EOF

printf '\nDone.\n'
printf 'Installed runtime: %s\n' "$prefix"
printf 'Detected engine: %s\n' "$engine"
printf 'Detected version: %s\n' "$version"
printf 'Server binary:\n'
printf '  %s\n' "$prefix/bin/postgres"
printf 'Init binary:\n'
printf '  %s\n' "$prefix/bin/initdb"
printf 'Client binary:\n'
printf '  %s\n' "$prefix/bin/psql"
printf 'Control binary:\n'
if [ -x "$prefix/bin/pg_ctl" ]; then
    printf '  %s\n' "$prefix/bin/pg_ctl"
else
    printf '  not found\n'
fi

if [ "$skip_package" != "1" ]; then
    package_script="$repo_root/scripts/package_postgresql_runtime_macos.sh"

    if [ ! -f "$package_script" ]; then
        package_script="$repo_root/scripts/package_database_runtime_macos.sh"
    fi

    if [ -f "$package_script" ]; then
        printf '\nPackaging self-contained macOS runtime...\n'
        if [ -n "$package_output" ]; then
            packaged_dir="$package_output"
            /bin/sh "$package_script" --source "$prefix" --overwrite --output "$packaged_dir"
        else
            packaged_dir="$repo_root/dist/runtime/database/$(basename "$prefix")"
            /bin/sh "$package_script" --source "$prefix" --overwrite --output "$packaged_dir"
        fi
    else
        printf '\nPackaging skipped: no PostgreSQL packaging script found.\n' >&2
    fi
else
    printf '\nPackaging skipped by --skip-package.\n'
fi

if [ "$skip_package" != "1" ] && [ "$skip_deploy" != "1" ]; then
    if [ -z "$deploy_root" ]; then
        deploy_root="$repo_root/dist/runtime/database"
    fi

    deploy_target="$deploy_root/$(basename "$packaged_dir")"
    packaged_abs="$(CDPATH= cd -- "$(dirname "$packaged_dir")" && pwd)/$(basename "$packaged_dir")"
    deploy_abs="$(CDPATH= cd -- "$(dirname "$deploy_target")" && pwd)/$(basename "$deploy_target")"
    if [ "$packaged_abs" = "$deploy_abs" ]; then
        printf '\nDeploy skipped: packaged runtime is already in app runtime root.\n'
        printf 'Packaged runtime:\n'
        printf '  %s\n' "$packaged_dir"
    else
        printf '\nDeploying packaged runtime into app runtime root...\n'
        mkdir -p "$deploy_root"
        rm -rf "$deploy_target"
        cp -R "$packaged_dir" "$deploy_target"
        printf 'Deployed runtime:\n'
        printf '  %s\n' "$deploy_target"
    fi
fi
