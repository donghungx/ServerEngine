#!/bin/sh

set -eu

usage() {
    cat <<'EOF'
Usage:
  scripts/sparkle_prepare_release.sh [options]

Generate Sparkle signature + release metadata JSON for a DMG.

Options:
  --dmg <path>                 Path to .dmg (required)
  --app <path>                 Path to .app (default: dist/app/Server Engine.app)
  --private-key-file <path>    Sparkle exported private key file (optional)
  --sign-update <path>         sign_update binary path (optional)
  --version <value>            Override short version
  --build <value>              Override build version
  --min-system-version <value> Override minimum system version
  --channel <value>            Release channel (default: stable)
  --arch <value>               Architecture label (default: derived from file name / uname -m)
  --output-json <path>         Metadata JSON output (default: <dmg>.sparkle.json)
  --help                       Show this help
EOF
}

abspath() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s\n' "$(pwd)/$1" ;;
    esac
}

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
dmg_path=""
app_path="$repo_root/dist/app/Server Engine.app"
private_key_file=""
sign_update_bin=""
version_override=""
build_override=""
min_system_override=""
channel="stable"
arch_override=""
output_json=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dmg)
            dmg_path="$(abspath "${2:-}")"
            shift 2
            ;;
        --app)
            app_path="$(abspath "${2:-}")"
            shift 2
            ;;
        --private-key-file)
            private_key_file="$(abspath "${2:-}")"
            shift 2
            ;;
        --sign-update)
            sign_update_bin="$(abspath "${2:-}")"
            shift 2
            ;;
        --version)
            version_override="${2:-}"
            shift 2
            ;;
        --build)
            build_override="${2:-}"
            shift 2
            ;;
        --min-system-version)
            min_system_override="${2:-}"
            shift 2
            ;;
        --channel)
            channel="${2:-}"
            shift 2
            ;;
        --arch)
            arch_override="${2:-}"
            shift 2
            ;;
        --output-json)
            output_json="$(abspath "${2:-}")"
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

if [ -z "$dmg_path" ]; then
    printf '--dmg is required.\n' >&2
    exit 1
fi
if [ ! -f "$dmg_path" ]; then
    printf 'DMG not found: %s\n' "$dmg_path" >&2
    exit 1
fi
if [ ! -d "$app_path" ]; then
    printf 'App not found: %s\n' "$app_path" >&2
    exit 1
fi

if [ -z "$sign_update_bin" ]; then
    for candidate in \
        "$repo_root/.build/sparkle/bin/sign_update" \
        "$repo_root/vendor/Sparkle/bin/sign_update" \
        "/opt/homebrew/bin/sign_update" \
        "/usr/local/bin/sign_update"
    do
        if [ -x "$candidate" ]; then
            sign_update_bin="$candidate"
            break
        fi
    done
fi

if [ -z "$sign_update_bin" ] || [ ! -x "$sign_update_bin" ]; then
    printf 'sign_update not found. Provide --sign-update <path>.\n' >&2
    exit 1
fi

if [ -n "$private_key_file" ] && [ ! -f "$private_key_file" ]; then
    printf 'private key file not found: %s\n' "$private_key_file" >&2
    exit 1
fi

plist="$app_path/Contents/Info.plist"
if [ ! -f "$plist" ]; then
    printf 'Info.plist not found: %s\n' "$plist" >&2
    exit 1
fi

plist_get() {
    key="$1"
    /usr/bin/defaults read "$plist" "$key" 2>/dev/null || true
}

version="${version_override:-$(plist_get CFBundleShortVersionString)}"
build="${build_override:-$(plist_get CFBundleVersion)}"
min_system_version="${min_system_override:-$(plist_get LSMinimumSystemVersion)}"
bundle_id="$(plist_get CFBundleIdentifier)"

if [ -z "$version" ] || [ -z "$build" ]; then
    printf 'Missing version/build. Set --version and --build or fix app Info.plist.\n' >&2
    exit 1
fi

if [ -z "$arch_override" ]; then
    case "$(uname -m)" in
        arm64|aarch64) arch="arm64" ;;
        x86_64|amd64) arch="x64" ;;
        *) arch="$(uname -m)" ;;
    esac
    case "$(basename "$dmg_path")" in
        *arm64*) arch="arm64" ;;
        *x64*|*x86_64*) arch="x64" ;;
        *universal*) arch="universal" ;;
    esac
else
    arch="$arch_override"
fi

if [ -n "$private_key_file" ]; then
    ed_signature="$("$sign_update_bin" --ed-key-file "$private_key_file" -p "$dmg_path")"
else
    ed_signature="$("$sign_update_bin" -p "$dmg_path")"
fi
ed_signature="$(printf '%s' "$ed_signature" | tr -d '\r\n')"
if [ -z "$ed_signature" ]; then
    printf 'Failed to create Sparkle signature.\n' >&2
    exit 1
fi

file_size="$(/usr/bin/stat -f '%z' "$dmg_path")"
sha256="$(/usr/bin/shasum -a 256 "$dmg_path" | awk '{print $1}')"
pub_date_iso8601="$(/bin/date -u +"%Y-%m-%dT%H:%M:%SZ")"

if [ -z "$output_json" ]; then
    output_json="${dmg_path}.sparkle.json"
fi

SPARKLE_APP_ID="${bundle_id:-com.serverengine.app}" \
SPARKLE_CHANNEL="$channel" \
SPARKLE_VERSION="$version" \
SPARKLE_BUILD="$build" \
SPARKLE_MIN_SYSTEM_VERSION="$min_system_version" \
SPARKLE_ARCH="$arch" \
SPARKLE_FILE_NAME="$(basename "$dmg_path")" \
SPARKLE_FILE_PATH="$dmg_path" \
SPARKLE_FILE_SIZE="$file_size" \
SPARKLE_SHA256="$sha256" \
SPARKLE_ED_SIGNATURE="$ed_signature" \
SPARKLE_PUB_DATE="$pub_date_iso8601" \
python3 - "$output_json" <<'PY'
import json
import os
import sys
from pathlib import Path

out_path = Path(sys.argv[1])
payload = {
    "app_id": os.environ["SPARKLE_APP_ID"],
    "channel": os.environ["SPARKLE_CHANNEL"],
    "version": os.environ["SPARKLE_VERSION"],
    "build": os.environ["SPARKLE_BUILD"],
    "min_system_version": os.environ.get("SPARKLE_MIN_SYSTEM_VERSION", ""),
    "os": "macos",
    "arch": os.environ["SPARKLE_ARCH"],
    "file_name": os.environ["SPARKLE_FILE_NAME"],
    "file_path": os.environ["SPARKLE_FILE_PATH"],
    "file_size": int(os.environ["SPARKLE_FILE_SIZE"]),
    "sha256": os.environ["SPARKLE_SHA256"],
    "sparkle_ed_signature": os.environ["SPARKLE_ED_SIGNATURE"],
    "pub_date_iso8601": os.environ["SPARKLE_PUB_DATE"],
}
out_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
print(f"Metadata JSON: {out_path}")
print(f"Sparkle signature: {payload['sparkle_ed_signature']}")
print(f"SHA256: {payload['sha256']}")
print(f"File size: {payload['file_size']}")
PY
