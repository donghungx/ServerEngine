#!/bin/sh

set -eu

usage() {
    cat <<'EOF'
Usage:
  scripts/build_macos_app.sh [options]

Build a macOS .app bundle for Server Engine using Nuitka.

Options:
  --name <name>          App bundle name. Default: Server Engine
  --dist-dir <path>      Output directory for the built app. Default: dist/app
  --build-dir <path>     Nuitka build output directory. Default: .build/nuitka
  --bundle-id <id>       macOS bundle identifier. Default: com.serverengine.app
  --version <version>    App version. Default: parsed from pyproject.toml
  --icon <path>          Optional .icns icon path
  --app-sign-identity <name>  Optional Developer ID Application identity for codesign
  --runtime-root <path>  Runtime root to bundle. Default: dist/runtime
  --sparkle-framework <path>  Optional Sparkle.framework to embed into app
  --sparkle-feed-url <url>    Optional Sparkle appcast feed URL (SUFeedURL)
  --sparkle-public-ed-key <k> Optional Sparkle EdDSA public key (SUPublicEDKey)
  --bundle-runtime       Copy selected runtime payload into Contents/Resources/runtime (default)
  --no-bundle-runtime    Do not copy runtime/helper payload into the app bundle
  --services <csv>       Runtime folders to include from runtime root/bin
                         Default: php,database,server,redis,memcached,mailpit,tools,node
  --runtime-items <csv>  Specific runtime folders relative to runtime root/bin.
                         Example: php/php8.2.29,node/node20.20.2
                         When set, this overrides --services.
  --helper-sign-identity <name>  Optional signing identity for privileged helper
                                 Default: same as --app-sign-identity
  --clean                Remove previous build outputs first (default)
  --no-clean             Skip removing previous build outputs
  --help                 Show this help
EOF
}

abspath() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s\n' "$(pwd)/$1" ;;
    esac
}

app_name="Server Engine"
dist_dir=""
build_dir=""
bundle_id="com.serverengine.app"
helper_id=""
version=""
icon_path=""
app_sign_identity=""
clean="1"
runtime_root=""
sparkle_framework=""
sparkle_feed_url=""
sparkle_public_ed_key=""
services_csv=""
runtime_items_csv=""
runtime_items_mode="0"
helper_sign_identity=""
bundle_runtime="1"

remove_path() {
    target="$1"
    if [ ! -e "$target" ]; then
        return 0
    fi
    if rm -rf "$target" 2>/dev/null; then
        return 0
    fi
    if [ -t 0 ] && command -v sudo >/dev/null 2>&1; then
        printf 'Removing stale build output with sudo: %s\n' "$target"
        if sudo rm -rf "$target"; then
            return 0
        fi
    fi
    # GUI/non-interactive fallback: use macOS admin prompt.
    if command -v osascript >/dev/null 2>&1; then
        printf 'Removing stale build output via macOS admin prompt: %s\n' "$target"
        if osascript - "$target" >/dev/null 2>&1 <<'APPLESCRIPT'
on run argv
    set targetPath to item 1 of argv
    do shell script "rm -rf " & quoted form of targetPath with administrator privileges
end run
APPLESCRIPT
        then
            return 0
        fi
    fi
    printf 'Unable to remove build output: %s\n' "$target" >&2
    printf 'Fix ownership once, then retry:\n' >&2
    printf '  sudo chown -R "$(id -un)":staff "%s"\n' "$target" >&2
    exit 1
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --name)
            app_name="${2:-}"
            shift 2
            ;;
        --dist-dir)
            dist_dir="$(abspath "${2:-}")"
            shift 2
            ;;
        --build-dir)
            build_dir="$(abspath "${2:-}")"
            shift 2
            ;;
        --bundle-id)
            bundle_id="${2:-}"
            shift 2
            ;;
        --version)
            version="${2:-}"
            shift 2
            ;;
        --icon)
            icon_path="$(abspath "${2:-}")"
            shift 2
            ;;
        --app-sign-identity)
            app_sign_identity="${2:-}"
            shift 2
            ;;
        --runtime-root)
            runtime_root="$(abspath "${2:-}")"
            shift 2
            ;;
        --sparkle-framework)
            sparkle_framework="$(abspath "${2:-}")"
            shift 2
            ;;
        --sparkle-feed-url)
            sparkle_feed_url="${2:-}"
            shift 2
            ;;
        --sparkle-public-ed-key)
            sparkle_public_ed_key="${2:-}"
            shift 2
            ;;
        --bundle-runtime)
            bundle_runtime="1"
            shift
            ;;
        --no-bundle-runtime)
            bundle_runtime="0"
            shift
            ;;
        --services)
            services_csv="${2:-}"
            shift 2
            ;;
        --runtime-items)
            runtime_items_csv="${2:-}"
            runtime_items_mode="1"
            shift 2
            ;;
        --helper-sign-identity)
            helper_sign_identity="${2:-}"
            shift 2
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

if [ -z "$dist_dir" ]; then
    dist_dir="$repo_root/dist/app"
fi

if [ -z "$build_dir" ]; then
    build_dir="$repo_root/.build/nuitka"
fi

if [ -z "$runtime_root" ]; then
    runtime_root="$repo_root/dist/runtime"
fi
if [ -z "$services_csv" ]; then
    services_csv="php,database,server,redis,memcached,mailpit,tools,node"
fi
if [ -z "$helper_sign_identity" ]; then
    helper_sign_identity="$app_sign_identity"
fi

if [ -z "$helper_id" ]; then
    helper_id="$bundle_id.helper"
fi

if [ -z "$version" ]; then
    version="$(python3 - <<'PY'
from pathlib import Path
import re

text = Path("pyproject.toml").read_text(encoding="utf-8")
match = re.search(r'^version\s*=\s*"([^"]+)"', text, re.MULTILINE)
print(match.group(1) if match else "0.1.0")
PY
)"
fi

if ! command -v python3 >/dev/null 2>&1; then
    printf 'python3 is required.\n' >&2
    exit 1
fi

if ! python3 -m nuitka --version >/dev/null 2>&1; then
    printf 'Nuitka is required. Install it in the active environment first.\n' >&2
    exit 1
fi

if ! python3 - <<'PY'
import importlib.util

missing = [
    name for name in ("pyte", "ptyprocess")
    if importlib.util.find_spec(name) is None
]

if missing:
    print(",".join(missing))
    raise SystemExit(1)

print("ok")
PY
then
    printf 'Missing terminal Python package in build env.\n' >&2
    printf 'Install terminal dependencies:\n' >&2
    printf '  pip install pyte ptyprocess\n' >&2
    exit 1
fi

if ! python3 - <<'PY'
import importlib.util
has_crypto = importlib.util.find_spec("cryptography") is not None
has_nacl = importlib.util.find_spec("nacl") is not None
has_certifi = importlib.util.find_spec("certifi") is not None
if not has_certifi or not (has_crypto or has_nacl):
    raise SystemExit(1)
print("ok")
PY
then
    printf 'Missing required Python package in build env.\n' >&2
    printf 'Install certifi and at least one signature backend:\n' >&2
    printf '  pip install certifi cryptography   (or pip install certifi pynacl)\n' >&2
    exit 1
fi

if [ "$clean" = "1" ]; then
    remove_path "$dist_dir"
    remove_path "$build_dir"
fi

mkdir -p "$dist_dir" "$build_dir"
# Use an isolated output folder per run to avoid stale/colliding Nuitka artifacts.
build_run_id="$(date +%s)-$$"
build_output_dir="$build_dir/output-$build_run_id"
rm -rf "$build_output_dir" "$build_dir/output"
mkdir -p "$build_output_dir"

entry_script="$repo_root/src/server_engine/main.py"
qml_dir="$repo_root/src/server_engine/gui/qml"

set -- \
    --standalone \
    --macos-create-app-bundle \
    --assume-yes-for-downloads \
    --output-dir="$build_output_dir" \
    --remove-output \
    --jobs=8 \
    --show-progress \
    --python-flag=no_site \
    --follow-imports \
    --enable-plugin=pyside6 \
    --include-qt-plugins=qml,platforms,platforminputcontexts,styles,imageformats,iconengines,tls,networkinformation,generic,renderers,renderplugins \
    --include-package=server_engine \
    --include-package=certifi \
    --include-package-data=certifi \
    --include-package=cryptography \
    --include-package=nacl \
    --include-package=pyte \
    --include-package=ptyprocess \
    --include-module=ptyprocess.ptyprocess \
    --include-package-data=pyte \
    --include-package-data=ptyprocess \
    --include-module=cryptography.hazmat.primitives.asymmetric.ed25519 \
    --include-module=nacl.signing \
    --include-data-dir="$qml_dir=server_engine/gui/qml" \
    --noinclude-data-files="PySide6/Qt/qml/Qt/labs/assetdownloader/**" \
    --noinclude-dlls="*assetdownloader*" \
    --noinclude-dlls="*/Qt/labs/assetdownloader/*" \
    --noinclude-dlls="*.a" \
    --noinclude-dlls="*.a(*" \
    --macos-app-name="$app_name" \
    --macos-app-version="$version" \
    --macos-app-protected-resource="NSCameraUsageDescription:Server Engine does not require camera access." \
    --macos-app-protected-resource="NSMicrophoneUsageDescription:Server Engine does not require microphone access." \
    --macos-app-mode=gui \
    --macos-signed-app-name="$bundle_id" \
    --output-filename=ServerEngine \
    "$entry_script"

# Optional PyObjC/Sparkle modules:
# include them only when present in the active Python environment.
if python3 - <<'PY' >/dev/null 2>&1
import importlib.util
raise SystemExit(0 if importlib.util.find_spec("AppKit") else 1)
PY
then
    set -- --include-module=AppKit --include-module=Foundation --include-module=objc "$@"
fi

if [ -n "$icon_path" ]; then
    set -- --macos-app-icon="$icon_path" "$@"
fi

printf 'Building macOS app bundle...\n'
assetdownloader_path="$(python3 - <<'PY'
import importlib.util
from pathlib import Path
spec = importlib.util.find_spec("PySide6")
if spec and spec.submodule_search_locations:
    root = Path(list(spec.submodule_search_locations)[0])
    p = root / "Qt" / "qml" / "Qt" / "labs" / "assetdownloader"
    if p.exists():
        print(p)
PY
)"
assetdownloader_backup=""
restore_assetdownloader() {
    if [ -n "${assetdownloader_backup:-}" ] && [ -d "$assetdownloader_backup" ] && [ -n "${assetdownloader_path:-}" ]; then
        rm -rf "$assetdownloader_path"
        mv "$assetdownloader_backup" "$assetdownloader_path"
    fi
}
trap restore_assetdownloader EXIT INT TERM
if [ -n "$assetdownloader_path" ] && [ -d "$assetdownloader_path" ]; then
    assetdownloader_backup="$build_dir/assetdownloader-backup-$$"
    rm -rf "$assetdownloader_backup"
    mv "$assetdownloader_path" "$assetdownloader_backup"
    printf 'Temporarily excluded PySide6 Qt labs assetdownloader for Nuitka compatibility:\n'
    printf '  %s\n' "$assetdownloader_path"
fi

PYTHONPATH="$repo_root/src${PYTHONPATH:+:$PYTHONPATH}" python3 -m nuitka "$@"
restore_assetdownloader
trap - EXIT INT TERM

app_path="$dist_dir/$app_name.app"
generated_app="$(find "$build_output_dir" -maxdepth 1 -type d -name '*.app' | head -n 1)"
if [ -n "$generated_app" ] && [ -d "$generated_app" ]; then
    rm -rf "$app_path"
    cp -R "$generated_app" "$app_path"
fi

if [ ! -d "$app_path" ]; then
    printf 'Expected app bundle not found: %s\n' "$app_path" >&2
    exit 1
fi

plist_path="$app_path/Contents/Info.plist"
if [ -f "$plist_path" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$plist_path" >/dev/null 2>&1 || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $version" "$plist_path" >/dev/null 2>&1 || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" "$plist_path" >/dev/null 2>&1 || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $version" "$plist_path" >/dev/null 2>&1 || true
fi

if [ -f "$plist_path" ] && [ -n "$sparkle_feed_url" ]; then
    /usr/libexec/PlistBuddy -c "Set :SUFeedURL $sparkle_feed_url" "$plist_path" >/dev/null 2>&1 || \
    /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $sparkle_feed_url" "$plist_path" >/dev/null 2>&1 || true
fi

if [ -f "$plist_path" ] && [ -n "$sparkle_public_ed_key" ]; then
    /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $sparkle_public_ed_key" "$plist_path" >/dev/null 2>&1 || \
    /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $sparkle_public_ed_key" "$plist_path" >/dev/null 2>&1 || true
fi

if [ -n "$sparkle_framework" ]; then
    if [ ! -d "$sparkle_framework" ]; then
        printf 'Sparkle framework not found: %s\n' "$sparkle_framework" >&2
        exit 1
    fi
    case "$sparkle_framework" in
        *.framework) ;;
        *)
            printf '--sparkle-framework must point to Sparkle.framework.\n' >&2
            exit 1
            ;;
    esac

    frameworks_dir="$app_path/Contents/Frameworks"
    target_framework="$frameworks_dir/Sparkle.framework"
    mkdir -p "$frameworks_dir"
    rm -rf "$target_framework"
    cp -R "$sparkle_framework" "$target_framework"
    printf 'Embedded Sparkle framework:\n  %s\n' "$target_framework"
fi

if [ -f "$plist_path" ]; then
    /usr/libexec/PlistBuddy -c "Delete :SMPrivilegedExecutables" "$plist_path" >/dev/null 2>&1 || true
    /usr/libexec/PlistBuddy -c "Add :SMPrivilegedExecutables dict" "$plist_path" >/dev/null 2>&1 || true

    helper_team_id="YOURTEAMID"
    if [ -n "$app_sign_identity" ]; then
        team_id="$(/usr/bin/security find-identity -v -p codesigning | awk -v ident="$app_sign_identity" '
            index($0, ident) {
                if (match($0, /\([A-Z0-9]{10}\)/)) {
                    print substr($0, RSTART + 1, RLENGTH - 2)
                    exit
                }
            }
        ')"

        if [ -n "$team_id" ]; then
            helper_team_id="$team_id"
        else
            printf 'WARNING: Could not detect Team ID for SMPrivilegedExecutables.\n' >&2
        fi
    fi

    helper_requirement="identifier \\\"$helper_id\\\" and anchor apple generic and certificate leaf[subject.OU] = \\\"$helper_team_id\\\""
    /usr/libexec/PlistBuddy -c "Add :SMPrivilegedExecutables:$helper_id string $helper_requirement" "$plist_path" >/dev/null 2>&1 || true
fi

runtime_source_bin="$runtime_root/bin"
if [ ! -d "$runtime_source_bin" ]; then
    # Also support runtime roots that already point at the bin layout
    # (php/, database/, server/, ... directly under runtime_root).
    runtime_source_bin="$runtime_root"
fi
bundled_runtime_root="$app_path/Contents/Resources/runtime"
helper_source="$repo_root/scripts/privileged_helper/ServerEnginePrivilegedHelper.c"
helper_info_plist="$repo_root/scripts/privileged_helper/ServerEnginePrivilegedHelper-Info.plist"
helper_launchd_plist="$repo_root/scripts/privileged_helper/ServerEnginePrivilegedHelper-Launchd.plist"
helper_build_output="$build_dir/$helper_id"
helper_binary=""
if [ "$bundle_runtime" != "1" ]; then
    rm -rf "$bundled_runtime_root"
    printf 'Skipping bundled runtime payload.\n'
fi
if [ -f "$helper_source" ]; then
    if ! command -v clang >/dev/null 2>&1; then
        printf 'clang is required to build privileged helper.\n' >&2
        exit 1
    fi

    if [ ! -f "$helper_info_plist" ] || [ ! -f "$helper_launchd_plist" ]; then
        printf 'Missing helper plist(s) required for SMJobBless:\n  %s\n  %s\n' "$helper_info_plist" "$helper_launchd_plist" >&2
        exit 1
    fi
    /usr/bin/clang \
        -O \
        -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$helper_info_plist" \
        -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __launchd_plist -Xlinker "$helper_launchd_plist" \
        "$helper_source" \
        -o "$helper_build_output"
    /bin/chmod 755 "$helper_build_output"
    helper_binary="$helper_build_output"
elif [ -f "$runtime_source_bin/$helper_id" ]; then
    helper_binary="$runtime_source_bin/$helper_id"
elif [ -f "$runtime_root/$helper_id" ]; then
    helper_binary="$runtime_root/$helper_id"
fi

if [ "$bundle_runtime" = "1" ] && [ -d "$runtime_source_bin" ]; then
    rm -rf "$bundled_runtime_root"
    mkdir -p "$bundled_runtime_root"

    selected_runtime_items=""
    if [ -n "$runtime_items_csv" ]; then
        items_norm="$(printf '%s' "$runtime_items_csv" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
        for rel in $(printf '%s' "$items_norm" | tr ',' ' '); do
            [ -n "$rel" ] || continue
            case "$rel" in
                /*|*..*|*//*)
                    printf 'Unsafe runtime item path: %s\n' "$rel" >&2
                    exit 1
                    ;;
            esac
            source_path="$runtime_source_bin/$rel"
            if [ ! -e "$source_path" ]; then
                printf 'Missing selected runtime item: %s\n' "$source_path" >&2
                exit 1
            fi
            case " $selected_runtime_items " in
                *" $rel "*) ;;
                *) selected_runtime_items="$selected_runtime_items $rel" ;;
            esac
        done
    fi

    if [ "$runtime_items_mode" = "1" ]; then
        if [ -z "$selected_runtime_items" ]; then
            printf 'No runtime items resolved from --runtime-items: %s\n' "$runtime_items_csv" >&2
            exit 1
        fi
        for rel in $selected_runtime_items; do
            parent_rel="$(dirname "$rel")"
            mkdir -p "$bundled_runtime_root/$parent_rel"
            cp -R "$runtime_source_bin/$rel" "$bundled_runtime_root/$parent_rel/"
        done
    else
        services_norm="$(printf '%s' "$services_csv" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
        for service in $(printf '%s' "$services_norm" | tr ',' ' '); do
            [ -n "$service" ] || continue
            case "$service" in
                php|database|server|redis|memcached|mailpit|tools|node) ;;
                *)
                    printf 'Unknown runtime service in --services: %s\n' "$service" >&2
                    exit 1
                    ;;
            esac
            source_dir="$runtime_source_bin/$service"
            if [ ! -d "$source_dir" ]; then
                printf 'Missing selected runtime directory: %s\n' "$source_dir" >&2
                exit 1
            fi
            cp -R "$source_dir" "$bundled_runtime_root/"
        done
    fi
    printf 'Bundled runtime payload:\n  %s\n' "$bundled_runtime_root"
elif [ "$bundle_runtime" = "1" ]; then
    printf 'Runtime root bin not found, skipping bundled runtime payload: %s\n' "$runtime_source_bin"
fi

helper_launchservices_dir="$app_path/Contents/Library/LaunchServices"
helper_in_app="$helper_launchservices_dir/$helper_id"

if [ -n "$helper_binary" ] && [ -f "$helper_binary" ]; then
    rm -rf "$helper_launchservices_dir"
    mkdir -p "$helper_launchservices_dir"
    cp "$helper_binary" "$helper_in_app"
    /bin/chmod 755 "$helper_in_app"

    printf 'Bundled privileged helper:\n'
    printf '  %s\n' "$helper_in_app"
fi

if [ -n "$app_sign_identity" ]; then
    if ! command -v codesign >/dev/null 2>&1; then
        printf 'codesign is required for app signing.\n' >&2
        exit 1
    fi
    runtime_payload_root="$app_path/Contents/Resources/runtime"
    helper_launchservices_dir="$app_path/Contents/Library/LaunchServices"
    helper_in_app="$helper_launchservices_dir/$helper_id"
    if [ -f "$helper_in_app" ]; then
        printf 'Signing privileged helper in app: %s\n' "$helper_in_app"
        /usr/bin/codesign \
            --force \
            --timestamp \
            --options runtime \
            --sign "$helper_sign_identity" \
            "$helper_in_app"
    fi

    if [ -d "$runtime_payload_root" ]; then
        printf 'Signing Mach-O files in runtime payload...\n'
        find "$runtime_payload_root" -type f | while IFS= read -r runtime_file; do
            [ "$runtime_file" = "$helper_in_app" ] && continue
            if /usr/bin/file -b "$runtime_file" 2>/dev/null | grep -q 'Mach-O'; then
                /usr/bin/codesign \
                    --force \
                    --timestamp \
                    --options runtime \
                    --sign "$app_sign_identity" \
                    "$runtime_file"
            fi
        done
    fi

    frameworks_root="$app_path/Contents/Frameworks"
    if [ -d "$frameworks_root" ]; then
        printf 'Signing Mach-O files in app frameworks...\n'
        find "$frameworks_root" -type f | while IFS= read -r framework_file; do
            if /usr/bin/file -b "$framework_file" 2>/dev/null | grep -q 'Mach-O'; then
                /usr/bin/codesign \
                    --force \
                    --timestamp \
                    --options runtime \
                    --sign "$app_sign_identity" \
                    "$framework_file"
            fi
        done
        find "$frameworks_root" -maxdepth 2 -type d -name '*.framework' | while IFS= read -r framework_dir; do
            /usr/bin/codesign \
                --force \
                --timestamp \
                --options runtime \
                --sign "$app_sign_identity" \
                "$framework_dir"
        done
    fi

    printf 'Signing app bundle (final): %s\n' "$app_sign_identity"
    /usr/bin/codesign \
        --force \
        --timestamp \
        --options runtime \
        --sign "$app_sign_identity" \
        "$app_path"

    printf 'Verifying signed app bundle...\n'
    /usr/bin/codesign --verify --deep --strict --verbose=4 "$app_path"
fi

printf '\nBuilt app bundle:\n'
printf '  %s\n' "$app_path"
