#!/bin/sh

set -eu

usage() {
    cat <<'EOF'
Usage:
  scripts/install_apache_runtime.sh
  scripts/install_apache_runtime.sh --formula httpd [options]

Install or stage a Homebrew Apache runtime into this repo's prebuild layout:
  prebuild/server/<engine>-<version>

Options:
  --formula <name>      Homebrew formula to install/stage.
                        Examples: httpd, httpd@2.4
  --engine <name>       Override detected engine. Default: apache
  --version <version>   Override detected version
  --prefix <path>       Override target path
  --overwrite           Remove an existing target directory first
  --skip-install        Do not run brew install; only stage an already installed formula
  --skip-package        Skip the macOS self-contained packaging step
  --package-output <p>  Override packaged output directory
  --skip-deploy         Skip copying the packaged runtime into the app-managed runtime root
  --deploy-root <path>  Override deploy root. Default: <repo>/dist/runtime/server
  --help                Show this help

Examples:
  scripts/install_apache_runtime.sh
  scripts/install_apache_runtime.sh --formula httpd --overwrite
  scripts/install_apache_runtime.sh --formula httpd@2.4 --overwrite
EOF
}

abspath() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s\n' "$(pwd)/$1" ;;
    esac
}

formula=""
engine=""
version=""
prefix=""
overwrite="0"
skip_install="0"
skip_package="0"
package_output=""
skip_deploy="0"
deploy_root=""
packaged_dir=""
original_argc="$#"
selected_was_linked="0"

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
    "httpd",
]

def load_options():
    result = subprocess.run(
        ["brew", "info", "--json=v2", *FORMULAS],
        check=True,
        capture_output=True,
        text=True,
    )
    payload = json.loads(result.stdout)
    options = []
    for formula in payload.get("formulae", []):
        name = formula["name"]
        version = formula["versions"]["stable"]
        deprecated = formula.get("deprecated", False)
        disabled = formula.get("disabled", False)
        label = f"Apache {version}"
        if deprecated:
            label += " [deprecated]"
        if disabled:
            label += " [disabled]"
        options.append((name, label))
    return options

def write(fd, text):
    os.write(fd, text.replace("\n", "\r\n").encode("utf-8", "replace"))

def draw(fd, options, index):
    write(fd, "\033[H\033[2J")
    write(fd, "Select Apache runtime and press Enter\n\n")
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
    raise SystemExit("No Apache runtime options found from Homebrew.")

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

linked_keg() {
    brew info --json=v2 "$1" 2>/dev/null | python3 -c 'import json,sys; data=json.load(sys.stdin); formulae=data.get("formulae", []); value=formulae[0].get("linked_keg") if formulae else None; print("" if value in (None, "", 0) else str(value))' 2>/dev/null || true
}

is_linked() {
    [ -n "$(linked_keg "$1")" ]
}

restore_homebrew_links() {
    if [ "$selected_was_linked" != "1" ]; then
        brew unlink "$formula" >/dev/null 2>&1 || true
    fi
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --formula)
            formula="${2:-}"
            shift 2
            ;;
        --engine)
            engine="${2:-}"
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
        printf 'No Apache runtime selected.\n' >&2
        exit 1
    fi
    formula="$selected_formula"
    overwrite="1"
fi

if [ -z "$formula" ]; then
    formula="httpd"
fi

if ! command -v brew >/dev/null 2>&1; then
    printf 'Homebrew is required for this script.\n' >&2
    exit 1
fi

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
selected_was_linked="0"
if is_linked "$formula"; then
    selected_was_linked="1"
fi

trap restore_homebrew_links EXIT

if [ "$skip_install" != "1" ]; then
    printf 'Reinstalling Homebrew formula: %s\n' "$formula"
    brew reinstall "$formula"
fi

brew_prefix="$(brew --prefix "$formula" 2>/dev/null || true)"
if [ -z "$brew_prefix" ] || [ ! -d "$brew_prefix" ]; then
    printf 'Formula prefix not found for %s\n' "$formula" >&2
    exit 1
fi
brew_prefix="$(CDPATH= cd -- "$brew_prefix" && pwd -P)"

formula_json="$(brew info --json=v2 "$formula" 2>/dev/null || true)"
stable_version="$(printf '%s' "$formula_json" | python3 -c 'import json,sys; data=json.load(sys.stdin); formulae=data.get("formulae", []); print(formulae[0]["versions"]["stable"] if formulae else "")' 2>/dev/null || true)"

if [ -z "$engine" ]; then
    case "$formula" in
        httpd*)
            engine="apache"
            ;;
        *)
            printf 'Could not detect engine from formula %s. Pass --engine.\n' "$formula" >&2
            exit 1
            ;;
    esac
fi

if [ -z "$version" ]; then
    version="$stable_version"
    if [ -z "$version" ]; then
        printf 'Could not detect version for %s from Homebrew metadata.\n' "$formula" >&2
        exit 1
    fi
fi

if [ -z "$prefix" ]; then
    prefix="$repo_root/prebuild/server/$engine-$version"
fi

if [ ! -d "$brew_prefix/bin" ]; then
    printf 'Invalid Homebrew runtime prefix, missing bin/: %s\n' "$brew_prefix" >&2
    exit 1
fi

server_binary=""
if [ -x "$brew_prefix/bin/httpd" ]; then
    server_binary="$brew_prefix/bin/httpd"
elif [ -x "$brew_prefix/bin/apachectl" ]; then
    server_binary="$brew_prefix/bin/apachectl"
else
    printf 'Expected Apache server binary missing under %s/bin\n' "$brew_prefix" >&2
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

mkdir -p "$prefix/conf"
mkdir -p "$prefix/logs"
mkdir -p "$prefix/run"
if [ ! -f "$prefix/conf/httpd.conf" ] && [ -f "$brew_prefix/etc/httpd/httpd.conf" ]; then
    cp "$brew_prefix/etc/httpd/httpd.conf" "$prefix/conf/httpd.conf"
fi

printf '\nDone.\n'
printf 'Installed runtime: %s\n' "$prefix"
printf 'Detected engine: %s\n' "$engine"
printf 'Detected version: %s\n' "$version"
printf 'Server binary:\n'
if [ -x "$prefix/bin/httpd" ]; then
    printf '  %s\n' "$prefix/bin/httpd"
elif [ -x "$prefix/bin/apachectl" ]; then
    printf '  %s\n' "$prefix/bin/apachectl"
else
    printf '  not found\n'
fi
printf 'Control binary:\n'
if [ -x "$prefix/bin/apachectl" ]; then
    printf '  %s\n' "$prefix/bin/apachectl"
else
    printf '  not found\n'
fi
printf 'Config file:\n'
if [ -f "$prefix/conf/httpd.conf" ]; then
    printf '  %s\n' "$prefix/conf/httpd.conf"
else
    printf '  not found\n'
fi

if [ "$skip_package" != "1" ]; then
    package_script="$repo_root/scripts/package_apache_runtime_macos.sh"
    if [ -f "$package_script" ]; then
        printf '\nPackaging self-contained macOS runtime...\n'
        if [ -n "$package_output" ]; then
            packaged_dir="$package_output"
            /bin/sh "$package_script" --source "$prefix" --overwrite --output "$packaged_dir"
        else
            packaged_dir="$repo_root/dist/runtime/server/$(basename "$prefix")"
            /bin/sh "$package_script" --source "$prefix" --overwrite --output "$packaged_dir"
        fi
    else
        printf '\nPackaging skipped: %s not found.\n' "$package_script" >&2
    fi
else
    printf '\nPackaging skipped by --skip-package.\n'
fi

if [ "$skip_package" != "1" ] && [ "$skip_deploy" != "1" ]; then
    if [ -z "$deploy_root" ]; then
        deploy_root="$repo_root/dist/runtime/server"
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

restore_homebrew_links
trap - EXIT
