#!/bin/sh

set -eu

usage() {
    cat <<'EOF'
Usage:
  scripts/build_macos_dmg.sh [options]

Build a macOS DMG for Server Engine.app.

Options:
  --app <path>                 Existing .app bundle. Default: dist/app/Server Engine.app
  --output <path>              Output .dmg path. Default: dist/dmg/ServerEngine-macos-<arch>-<version>.dmg
  --volume-name <name>         Mounted DMG volume name. Default: Server Engine
  --version <version>          Version for default output file name (optional)
  --sign-identity <name>       Optional Developer ID Application identity to sign DMG
  --notarize                   Submit DMG for notarization (--wait)
  --apple-id <id>              Apple ID for notarytool
  --team-id <id>               Team ID for notarytool
  --password <secret>          App-specific password for notarytool
  --check-env                  Print build Python and tool environment, then exit
  --clean                      Remove previous temporary build output first (default)
  --no-clean                   Skip cleanup first
  --help                       Show this help
EOF
}

abspath() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s\n' "$(pwd)/$1" ;;
    esac
}

app_path=""
output_path=""
volume_name="Server Engine"
version=""
sign_identity=""
enable_notarize="0"
apple_id=""
team_id=""
password=""
clean="1"
check_env="0"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --app)
            app_path="$(abspath "${2:-}")"
            shift 2
            ;;
        --output)
            output_path="$(abspath "${2:-}")"
            shift 2
            ;;
        --volume-name)
            volume_name="${2:-}"
            shift 2
            ;;
        --version)
            version="${2:-}"
            shift 2
            ;;
        --sign-identity)
            sign_identity="${2:-}"
            shift 2
            ;;
        --notarize)
            enable_notarize="1"
            shift
            ;;
        --apple-id)
            apple_id="${2:-}"
            shift 2
            ;;
        --team-id)
            team_id="${2:-}"
            shift 2
            ;;
        --password)
            password="${2:-}"
            shift 2
            ;;
        --check-env)
            check_env="1"
            shift
            ;;
        --clean)
            clean="1"
            shift
            ;;
        --no-clean)
            clean="0"
            shift
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

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$repo_root"

if [ -x "$repo_root/.venv/bin/python" ]; then
    PYTHON_BIN="$repo_root/.venv/bin/python"
else
    PYTHON_BIN="$(command -v python3 || true)"
fi

if [ -z "$PYTHON_BIN" ]; then
    printf 'python3 is required, or create .venv/bin/python.\n' >&2
    exit 1
fi

printf 'DMG Python:\n'
printf '  %s\n' "$PYTHON_BIN"
"$PYTHON_BIN" --version
"$PYTHON_BIN" -c 'import sysconfig; print("  Python MACOSX_DEPLOYMENT_TARGET:", sysconfig.get_config_var("MACOSX_DEPLOYMENT_TARGET"))'

printf 'DMG tools:\n'
printf '  hdiutil: %s\n' "$(command -v hdiutil || true)"
printf '  codesign: %s\n' "$(command -v codesign || true)"
printf '  xcrun: %s\n' "$(command -v xcrun || true)"

if [ "$check_env" = "1" ]; then
    exit 0
fi

if [ -z "$app_path" ]; then
    app_path="$repo_root/dist/app/Server Engine.app"
fi

if [ ! -d "$app_path" ]; then
    printf 'App bundle not found: %s\n' "$app_path" >&2
    exit 1
fi

if [ -z "$version" ]; then
    version="$("$PYTHON_BIN" - <<'PY'
from pathlib import Path
import re

text = Path("pyproject.toml").read_text(encoding="utf-8")
match = re.search(r'^version\s*=\s*"([^"]+)"', text, re.MULTILINE)
print(match.group(1) if match else "0.1.0")
PY
)"
fi

if [ -z "$output_path" ]; then
    machine="$(uname -m)"
    case "$machine" in
        arm64|aarch64)
            dmg_arch="arm64"
            ;;
        x86_64|amd64)
            dmg_arch="x64"
            ;;
        *)
            dmg_arch="$machine"
            ;;
    esac
    output_path="$repo_root/dist/dmg/ServerEngine-macos-$dmg_arch-$version.dmg"
fi

build_root="$repo_root/.build/dmg"
stage_root="$build_root/stage"

if [ "$clean" = "1" ]; then
    rm -rf "$build_root"
fi

rm -rf "$stage_root"
mkdir -p "$stage_root"
mkdir -p "$(dirname "$output_path")"

printf 'Checking app bundle before DMG build:\n'
printf '  %s\n' "$app_path"

/usr/bin/codesign --verify --deep --strict --verbose=4 "$app_path"

if command -v spctl >/dev/null 2>&1; then
    /usr/sbin/spctl -a -vvv -t exec "$app_path" || true
fi

cp -R "$app_path" "$stage_root/"
ln -s /Applications "$stage_root/Applications"

if [ -f "$output_path" ]; then
    rm -f "$output_path"
fi

hdiutil create \
    -volname "$volume_name" \
    -srcfolder "$stage_root" \
    -ov \
    -format UDZO \
    "$output_path"

if [ -n "$sign_identity" ]; then
    /usr/bin/codesign \
        --force \
        --timestamp \
        --options runtime \
        --sign "$sign_identity" \
        "$output_path"

    /usr/bin/codesign --verify --verbose=4 "$output_path"
fi

if [ "$enable_notarize" = "1" ]; then
    if [ -z "$apple_id" ] || [ -z "$team_id" ] || [ -z "$password" ]; then
        printf 'Notarization requires --apple-id, --team-id, and --password.\n' >&2
        exit 1
    fi

    xcrun notarytool submit "$output_path" \
        --apple-id "$apple_id" \
        --team-id "$team_id" \
        --password "$password" \
        --wait

    xcrun stapler staple "$output_path"
fi

printf '\nBuilt DMG:\n'
printf '  %s\n' "$output_path"