#!/bin/sh

set -eu

usage() {
    cat <<'EOF'
Usage:
  scripts/install_mongodb_runtime.sh
  scripts/install_mongodb_runtime.sh --formula mongodb-community@7.0 [options]

Install or stage a Homebrew MongoDB runtime into this repo's prebuild layout:
  prebuild/database/mongodb-<version>

Options:
  --formula <name>      Homebrew formula to install/stage.
                        Examples: mongodb-community, mongodb-community@8.0, mongodb-community@7.0
  --version <version>   Override detected version
  --prefix <path>       Override target path
  --overwrite           Remove an existing target directory first
  --skip-install        Do not run brew install; only stage an already installed formula
  --skip-tools          Do not install or stage mongosh / mongodb-database-tools
  --skip-package        Skip the macOS self-contained packaging step
  --package-output <p>  Override packaged output directory
  --skip-deploy         Skip copying the packaged runtime into the app-managed runtime root
  --deploy-root <path>  Override deploy root. Default: <repo>/dist/runtime/database
  --help                Show this help

Examples:
  scripts/install_mongodb_runtime.sh
  scripts/install_mongodb_runtime.sh --formula mongodb-community@7.0 --overwrite
  scripts/install_mongodb_runtime.sh --formula mongodb-community@8.0 --overwrite
EOF
}

abspath() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s\n' "$(pwd)/$1" ;;
    esac
}

ensure_formula_installed() {
    formula_name="$1"
    required_binary="$2"

    printf 'Installing Homebrew formula: %s\n' "$formula_name"

    if ! brew reinstall "$formula_name"; then
        formula_prefix="$(brew --prefix "$formula_name" 2>/dev/null || true)"

        if [ -n "$formula_prefix" ] && [ -x "$formula_prefix/bin/$required_binary" ]; then
            printf 'Homebrew link step failed, but formula is installed and usable for packaging:\n'
            printf '  %s\n' "$formula_prefix"
        else
            printf 'Homebrew reinstall failed and usable binary was not found:\n' >&2
            printf '  formula: %s\n' "$formula_name" >&2
            printf '  binary: %s\n' "$required_binary" >&2
            exit 1
        fi
    fi
}

copy_formula_bins() {
    formula_name="$1"
    tool_prefix="$(brew --prefix "$formula_name" 2>/dev/null || true)"

    if [ -z "$tool_prefix" ] || [ ! -d "$tool_prefix/bin" ]; then
        printf 'Tool formula not staged because prefix was not found: %s\n' "$formula_name" >&2
        return 0
    fi

    printf 'Staging tool binaries from %s\n' "$tool_prefix"

    for binary in "$tool_prefix"/bin/*; do
        if [ -f "$binary" ] && [ -x "$binary" ]; then
            cp "$binary" "$prefix/bin/$(basename "$binary")"
        fi
    done
}

copy_mongosh_runtime() {
    mongosh_cellar="$(brew --cellar mongosh 2>/dev/null || true)"
    mongosh_version="$(brew list --versions mongosh 2>/dev/null | awk 'NR == 1 {print $2}' || true)"

    if [ -z "$mongosh_cellar" ] || [ -z "$mongosh_version" ]; then
        printf 'mongosh runtime was not staged because the keg path was not found.\n' >&2
        return 0
    fi

    mongosh_prefix="$mongosh_cellar/$mongosh_version"

    if [ ! -d "$mongosh_prefix/libexec" ]; then
        printf 'mongosh runtime was not staged because libexec was not found: %s\n' "$mongosh_prefix" >&2
        return 0
    fi

    printf 'Staging mongosh runtime from %s\n' "$mongosh_prefix"

    rm -f "$prefix/bin/mongosh"
    cp -R "$mongosh_prefix/libexec" "$prefix/libexec"

    cat > "$prefix/bin/mongosh" <<'EOF'
#!/bin/sh
set -eu

runtime_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
exec "$runtime_root/libexec/bin/mongosh" "$@"
EOF
    chmod +x "$prefix/bin/mongosh"
}

formula=""
version=""
prefix=""
overwrite="0"
skip_install="0"
skip_tools="0"
skip_package="0"
package_output=""
skip_deploy="0"
deploy_root=""
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
    "mongodb-community",
    "mongodb-community@8.0",
    "mongodb-community@7.0",
    "mongodb-community@6.0",
    "mongodb-community@5.0",
    "mongodb-community@4.4",
]

def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)

def ensure_tap():
    subprocess.run(
        ["brew", "tap", "mongodb/brew"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )

def load_options():
    ensure_tap()
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

        label = f"MongoDB {version}"

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
    write(fd, "Select MongoDB runtime and press Enter\n\n")

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
    raise SystemExit("No MongoDB runtime options found. Run: brew tap mongodb/brew && brew search mongodb-community")

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
        --skip-tools)
            skip_tools="1"
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
        printf 'No MongoDB runtime selected.\n' >&2
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
    printf 'Homebrew is required for this build/staging script.\n' >&2
    exit 1
fi

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

if [ "$skip_install" != "1" ]; then
    printf 'Ensuring MongoDB Homebrew tap is available...\n'
    brew tap mongodb/brew

    ensure_formula_installed "$formula" "mongod"

    if [ "$skip_tools" != "1" ]; then
        ensure_formula_installed "mongosh" "mongosh"
        ensure_formula_installed "mongodb-database-tools" "mongodump"
    fi
fi

brew_prefix="$(brew --prefix "$formula" 2>/dev/null || true)"

if [ -z "$brew_prefix" ] || [ ! -d "$brew_prefix" ]; then
    printf 'Formula prefix not found for %s\n' "$formula" >&2
    exit 1
fi

brew_prefix="$(CDPATH= cd -- "$brew_prefix" && pwd -P)"

formula_json="$(brew info --json=v2 "$formula" 2>/dev/null || true)"
stable_version="$(printf '%s' "$formula_json" | python3 -c 'import json,sys; data=json.load(sys.stdin); formulae=data.get("formulae", []); print(formulae[0]["versions"]["stable"] if formulae else "")' 2>/dev/null || true)"

if [ -z "$version" ]; then
    version="$stable_version"

    if [ -z "$version" ]; then
        printf 'Could not detect version for %s from Homebrew metadata.\n' "$formula" >&2
        exit 1
    fi
fi

engine="mongodb"

if [ -z "$prefix" ]; then
    prefix="$repo_root/prebuild/database/$engine-$version"
fi

if [ ! -d "$brew_prefix/bin" ]; then
    printf 'Invalid Homebrew runtime prefix, missing bin/: %s\n' "$brew_prefix" >&2
    exit 1
fi

if [ ! -x "$brew_prefix/bin/mongod" ]; then
    printf 'Expected MongoDB server binary missing: %s/bin/mongod\n' "$brew_prefix" >&2
    exit 1
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

printf 'Staging runtime from %s\n' "$brew_prefix"
cp -R "$brew_prefix"/. "$prefix"

if [ "$skip_tools" != "1" ]; then
    mkdir -p "$prefix/bin"
    copy_formula_bins "mongosh"
    copy_formula_bins "mongodb-database-tools"
    copy_mongosh_runtime
fi

mkdir -p "$prefix/conf"

if [ -f "$(brew --prefix)/etc/mongod.conf" ]; then
    cp "$(brew --prefix)/etc/mongod.conf" "$prefix/conf/mongod.conf"
elif [ ! -f "$prefix/conf/mongod.conf" ]; then
    cat > "$prefix/conf/mongod.conf" <<'EOF'
storage:
  dbPath: data/db
systemLog:
  destination: file
  path: logs/mongod.log
  logAppend: true
net:
  bindIp: 127.0.0.1
  port: 27017
processManagement:
  fork: false
EOF
fi

mkdir -p "$prefix/data/db"
mkdir -p "$prefix/logs"

printf '\nDone.\n'
printf 'Installed runtime: %s\n' "$prefix"
printf 'Detected engine: %s\n' "$engine"
printf 'Detected version: %s\n' "$version"

printf 'Server binary:\n'
printf '  %s\n' "$prefix/bin/mongod"

printf 'Router binary:\n'
if [ -x "$prefix/bin/mongos" ]; then
    printf '  %s\n' "$prefix/bin/mongos"
else
    printf '  not found\n'
fi

printf 'Client binary:\n'
if [ -x "$prefix/bin/mongosh" ]; then
    printf '  mongosh: %s\n' "$prefix/bin/mongosh"
else
    printf '  mongosh: not found\n'
fi

printf 'Backup/import binaries:\n'

if [ -x "$prefix/bin/mongodump" ]; then
    printf '  mongodump: %s\n' "$prefix/bin/mongodump"
else
    printf '  mongodump: not found\n'
fi

if [ -x "$prefix/bin/mongorestore" ]; then
    printf '  mongorestore: %s\n' "$prefix/bin/mongorestore"
else
    printf '  mongorestore: not found\n'
fi

if [ -x "$prefix/bin/mongoimport" ]; then
    printf '  mongoimport: %s\n' "$prefix/bin/mongoimport"
else
    printf '  mongoimport: not found\n'
fi

if [ -x "$prefix/bin/mongoexport" ]; then
    printf '  mongoexport: %s\n' "$prefix/bin/mongoexport"
else
    printf '  mongoexport: not found\n'
fi

if [ -x "$prefix/bin/bsondump" ]; then
    printf '  bsondump: %s\n' "$prefix/bin/bsondump"
else
    printf '  bsondump: not found\n'
fi

printf 'Config file:\n'
printf '  %s\n' "$prefix/conf/mongod.conf"

if [ "$skip_package" != "1" ]; then
    package_script="$repo_root/scripts/package_mongodb_runtime_macos.sh"

    if [ -f "$package_script" ]; then
        printf '\nPackaging self-contained macOS runtime...\n'

        if [ -n "$package_output" ]; then
            /bin/sh "$package_script" --source "$prefix" --overwrite --output "$package_output"
        else
            /bin/sh "$package_script" --source "$prefix" --overwrite
        fi
    else
        printf '\nPackaging skipped: %s not found.\n' "$package_script" >&2
    fi
else
    printf '\nPackaging skipped by --skip-package.\n'
fi

if [ "$skip_package" != "1" ] && [ "$skip_deploy" != "1" ]; then
    if [ -n "$package_output" ]; then
        packaged_dir="$package_output"
    else
        packaged_dir="$repo_root/dist/runtime/database/$(basename "$prefix")"
    fi

    if [ -z "$deploy_root" ]; then
        deploy_root="$repo_root/dist/runtime/database"
    fi

    deploy_target="$deploy_root/$(basename "$packaged_dir")"

    packaged_abs="$(CDPATH= cd -- "$(dirname "$packaged_dir")" && pwd)/$(basename "$packaged_dir")"
    deploy_abs="$(CDPATH= cd -- "$(dirname "$deploy_target")" && pwd)/$(basename "$deploy_target")"

    if [ "$packaged_abs" = "$deploy_abs" ]; then
        printf '\nDeploy skipped: packaged runtime is already in deploy root.\n'
        printf 'Deployed runtime:\n'
        printf '  %s\n' "$deploy_target"
    else
        printf '\nDeploying packaged runtime into app runtime root...\n'
        mkdir -p "$deploy_root"
        rm -rf "$deploy_target"
        cp -R "$packaged_dir" "$deploy_target"

        printf 'Deployed runtime:\n'
        printf '  %s\n' "$deploy_target"
    fi
fi
