#!/bin/sh

set -eu

usage() {
    cat <<'EOF'
Usage:
  scripts/install_openssl_runtime.sh
  scripts/install_openssl_runtime.sh --formula openssl@3 [options]

Install or stage a Homebrew OpenSSL runtime into this repo's tool layout:
  dist/runtime/openssl/<runtime-name>

Options:
  --formula <name>      Homebrew formula to install/stage.
                        Examples: openssl@3, openssl@1.1
  --version <version>   Override detected version
  --runtime-name <name> Override runtime folder name. Default: openssl-<version>
  --prefix <path>       Override source prefix (skip brew detection)
  --output <path>       Override staged output directory
  --overwrite           Remove existing target directory first
  --skip-install        Do not run brew reinstall; only stage existing formula/prefix
  --skip-deploy         Skip copying into app-managed runtime root
  --deploy-root <path>  Override deploy root.
                        Default: <repo>/dist/runtime/openssl
  --help                Show this help
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
runtime_name=""
prefix=""
output=""
overwrite="0"
skip_install="0"
skip_deploy="0"
deploy_root=""
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
    "openssl@3",
    "openssl@1.1",
]

def load_options():
    options = []
    for candidate in FORMULAS:
        result = subprocess.run(
            ["brew", "info", "--json=v2", candidate],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            continue
        try:
            payload = json.loads(result.stdout)
        except json.JSONDecodeError:
            continue
        for formula in payload.get("formulae", []):
            name = formula["name"]
            stable = formula.get("versions", {}).get("stable", "")
            label = f"{name} {stable}".strip()
            options.append((name, label))
    return options

def write(fd, text):
    os.write(fd, text.replace("\n", "\r\n").encode("utf-8", "replace"))

def draw(fd, options, index):
    write(fd, "\033[H\033[2J")
    write(fd, "Select OpenSSL runtime and press Enter\n\n")
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
    raise SystemExit("No OpenSSL runtime options found from Homebrew.")

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
    if [ -n "$formula" ] && [ "$selected_was_linked" != "1" ]; then
        brew unlink "$formula" >/dev/null 2>&1 || true
    fi
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
        --runtime-name)
            runtime_name="${2:-}"
            shift 2
            ;;
        --prefix)
            prefix="$(abspath "${2:-}")"
            shift 2
            ;;
        --output)
            output="$(abspath "${2:-}")"
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

if [ "$original_argc" -eq 0 ] && [ -z "$formula" ] && [ -z "$prefix" ]; then
    selected_formula="$(interactive_pick_formula || true)"
    if [ -z "$selected_formula" ]; then
        printf 'No OpenSSL runtime selected.\n' >&2
        exit 1
    fi
    formula="$selected_formula"
    overwrite="1"
fi

if [ -z "$prefix" ]; then
    if [ -z "$formula" ]; then
        formula="openssl@3"
    fi

    if ! command -v brew >/dev/null 2>&1; then
        printf 'Homebrew is required for this script unless --prefix is provided.\n' >&2
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
    prefix="$(CDPATH= cd -- "$brew_prefix" && pwd -P)"

    if [ -z "$version" ]; then
        formula_json="$(brew info --json=v2 "$formula" 2>/dev/null || true)"
        version="$(printf '%s' "$formula_json" | python3 -c 'import json,sys; data=json.load(sys.stdin); f=data.get("formulae", []); print(f[0].get("versions", {}).get("stable", "") if f else "")' 2>/dev/null || true)"
    fi
else
    prefix="$(abspath "$prefix")"
    if [ ! -d "$prefix" ]; then
        printf 'Provided prefix does not exist: %s\n' "$prefix" >&2
        exit 1
    fi
fi

if [ -z "$version" ]; then
    version="$(basename "$prefix" | sed 's/^openssl[@-]*//')"
fi
if [ -z "$version" ]; then
    version="3"
fi

if [ -z "$runtime_name" ]; then
    runtime_name="openssl-$version"
fi

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
if [ -z "$output" ]; then
    output="$repo_root/dist/runtime/openssl/$runtime_name"
fi
if [ -z "$deploy_root" ]; then
    deploy_root="$repo_root/dist/runtime/openssl"
fi

if [ -e "$output" ] || [ -L "$output" ]; then
    if [ "$overwrite" = "1" ]; then
        printf 'Removing existing target directory: %s\n' "$output"
        rm -rf "$output"
    else
        printf 'Target directory already exists: %s\n' "$output" >&2
        printf 'Use --overwrite to replace it.\n' >&2
        exit 1
    fi
fi

mkdir -p "$(dirname "$output")"
cp -R "$prefix" "$output"

# IMPORTANT: Homebrew OpenSSL binaries keep absolute Cellar paths embedded in
# their Mach-O load commands after copying. DYLD_LIBRARY_PATH is not reliable
# for this app launch context, so every staged binary/library must be relinked
# to the libraries inside this runtime before it is deployed or signed.
if command -v install_name_tool >/dev/null 2>&1 && command -v otool >/dev/null 2>&1; then
    for artifact in "$output/bin/openssl" "$output/lib/libssl.3.dylib" "$output/lib/libcrypto.3.dylib"; do
        [ -f "$artifact" ] || continue
        otool -L "$artifact" | tail -n +2 | sed 's/^[[:space:]]*//' | cut -d ' ' -f 1 | while IFS= read -r dependency; do
            case "$dependency" in
                */libssl.3.dylib|*/libcrypto.3.dylib)
                    library_name="$(basename "$dependency")"
                    if [ "$artifact" = "$output/bin/openssl" ]; then
                        replacement="@loader_path/../lib/$library_name"
                    else
                        replacement="@loader_path/$library_name"
                    fi
                    install_name_tool -change "$dependency" "$replacement" "$artifact"
                    ;;
            esac
        done
    done
    install_name_tool -id '@rpath/libssl.3.dylib' "$output/lib/libssl.3.dylib" 2>/dev/null || true
    install_name_tool -id '@rpath/libcrypto.3.dylib' "$output/lib/libcrypto.3.dylib" 2>/dev/null || true
else
    printf 'install_name_tool and otool are required to make OpenSSL portable on macOS.\n' >&2
    exit 1
fi

# Do not allow a broken Homebrew-linked runtime to leave the staging area.
if otool -L "$output/bin/openssl" | grep -E '/opt/homebrew/(Cellar|opt)/openssl' >/dev/null 2>&1; then
    printf 'OpenSSL is still linked to Homebrew paths after relinking: %s\n' "$output/bin/openssl" >&2
    exit 1
fi

for req in "$output/bin/openssl" "$output/lib"; do
    if [ ! -e "$req" ]; then
        printf 'Staged OpenSSL runtime looks incomplete (missing %s).\n' "$req" >&2
        exit 1
    fi
done

printf '\nDone.\n'
printf 'Installed OpenSSL runtime:\n'
printf '  %s\n' "$output"
printf 'Source prefix:\n'
printf '  %s\n' "$prefix"

if [ "$skip_deploy" != "1" ]; then
    deploy_target="$deploy_root/$runtime_name"
    printf '\nDeploying OpenSSL runtime into app runtime root...\n'
    mkdir -p "$deploy_root"
    rm -rf "$deploy_target"
    cp -R "$output" "$deploy_target"
    printf 'Deployed runtime:\n'
    printf '  %s\n' "$deploy_target"
fi

trap - EXIT
