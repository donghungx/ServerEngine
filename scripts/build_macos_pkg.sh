#!/bin/sh

set -eu

usage() {
    cat <<'EOF'
Usage:
  scripts/build_macos_pkg.sh [options]

Build a macOS installer package that:
  - installs Server Engine.app into /Applications
  - copies packaged runtimes from ~/Library/Application Support/Server Engine
    into the logged-in user's Application Support via postinstall

Options:
  --app <path>           Existing .app bundle. Default: dist/app/Server Engine.app
  --runtime-root <path>  Packaged runtime root. Default: ~/Library/Application Support/Server Engine
  --output <path>        Output .pkg path. Default: dist/pkg/ServerEngine-macos-<arch>-<version>.pkg
  --identifier <id>      Package identifier. Default: com.serverengine.installer
  --version <version>    Package version. Default: parsed from pyproject.toml
  --icon <path>          Optional .icns icon path for app build
  --app-sign-identity <name>  Optional Developer ID Application identity for .app signing
  --runtime-sign-identity <name>  Developer ID Application identity for staged runtime/helper signing
  --services <csv>       Runtime folders to include from runtime root.
                         Default: php,database,server,redis,memcached,mailpit,tools,node
  --runtime-items <csv>  Specific runtime folders relative to runtime root.
                         Example: php/php7.3.33,php/php8.2.29,node/node20.20.2
                         When set, this overrides --services.
  --skip-app-build       Do not build the .app first
  --clean                Remove previous temporary package staging first (default)
  --no-clean             Skip removing previous temporary package staging
  --help                 Show this help
EOF
}

abspath() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s\n' "$(pwd)/$1" ;;
    esac
}

app_path=""
runtime_root=""
output_path=""
identifier="com.serverengine.installer"
version=""
icon_path=""
app_sign_identity=""
runtime_sign_identity=""
skip_app_build="0"
clean="1"
services_csv="php,database,server,redis,memcached,mailpit,tools,node"
runtime_items_csv=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --app)
            app_path="$(abspath "${2:-}")"
            shift 2
            ;;
        --runtime-root)
            runtime_root="$(abspath "${2:-}")"
            shift 2
            ;;
        --output)
            output_path="$(abspath "${2:-}")"
            shift 2
            ;;
        --identifier)
            identifier="${2:-}"
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
        --runtime-sign-identity)
            runtime_sign_identity="${2:-}"
            shift 2
            ;;
        --services)
            services_csv="${2:-}"
            shift 2
            ;;
        --runtime-items)
            runtime_items_csv="${2:-}"
            shift 2
            ;;
        --skip-app-build)
            skip_app_build="1"
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

if [ -z "$version" ]; then
    version="$(python3 - <<'PY'
from pathlib import Path
import re
from datetime import datetime, timezone

pyproject_path = Path("pyproject.toml")
init_path = Path("src/server_engine/__init__.py")
text = pyproject_path.read_text(encoding="utf-8")
match = re.search(r'^version\s*=\s*"([^"]+)"', text, re.MULTILINE)
current = match.group(1) if match else "0.1.0"
parts = current.split(".")
if len(parts) != 3 or not all(part.isdigit() for part in parts):
    raise SystemExit(f"Unsupported version format: {current}")
major, minor, patch = (int(parts[0]), int(parts[1]), int(parts[2]))
next_version = f"{major}.{minor}.{patch + 1}"
updated = re.sub(
    r'^version\s*=\s*"([^"]+)"',
    f'version = "{next_version}"',
    text,
    count=1,
    flags=re.MULTILINE,
)
pyproject_path.write_text(updated, encoding="utf-8")

build_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

init_text = init_path.read_text(encoding="utf-8")
if '__build_at__' in init_text:
    init_text = re.sub(r'__build_at__\s*=\s*"[^"]*"', f'__build_at__ = "{build_at}"', init_text)
else:
    init_text = init_text.rstrip() + '\n__build_at__ = "' + build_at + '"\n'
init_text = re.sub(r'__version__\s*=\s*"[^"]*"', f'__version__ = "{next_version}"', init_text)
init_path.write_text(init_text, encoding="utf-8")

print(next_version)
PY
)"
else
    python3 - "$version" <<'PY'
from pathlib import Path
import re
from datetime import datetime, timezone
import sys

target_version = sys.argv[1].strip()
if not re.fullmatch(r"\d+\.\d+\.\d+", target_version):
    raise SystemExit(f"Unsupported version format: {target_version}")

build_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
pyproject_path = Path("pyproject.toml")
init_path = Path("src/server_engine/__init__.py")
text = pyproject_path.read_text(encoding="utf-8")
updated = re.sub(
    r'^version\s*=\s*"([^"]+)"',
    f'version = "{target_version}"',
    text,
    count=1,
    flags=re.MULTILINE,
)
pyproject_path.write_text(updated, encoding="utf-8")
init_text = init_path.read_text(encoding="utf-8")
init_text = re.sub(r'__version__\s*=\s*"[^"]*"', f'__version__ = "{target_version}"', init_text)
if '__build_at__' in init_text:
    init_text = re.sub(r'__build_at__\s*=\s*"[^"]*"', f'__build_at__ = "{build_at}"', init_text)
else:
    init_text = init_text.rstrip() + '\n__build_at__ = "' + build_at + '"\n'
init_path.write_text(init_text, encoding="utf-8")
PY
fi

build_at="$(python3 - <<'PY'
from pathlib import Path
import re
text = Path("src/server_engine/__init__.py").read_text(encoding="utf-8")
match = re.search(r'__build_at__\s*=\s*"([^"]*)"', text)
print(match.group(1) if match else "")
PY
)"

if [ -z "$app_path" ]; then
    app_path="$repo_root/dist/app/Server Engine.app"
fi

if [ -z "$runtime_root" ]; then
    runtime_root="$HOME/Library/Application Support/Server Engine"
fi

if [ -z "$output_path" ]; then
    machine="$(uname -m)"
    case "$machine" in
        arm64|aarch64) pkg_arch="arm64" ;;
        x86_64|amd64) pkg_arch="x64" ;;
        *) pkg_arch="$machine" ;;
    esac
    output_path="$repo_root/dist/pkg/ServerEngine-macos-$pkg_arch-$version.pkg"
fi

build_root="$repo_root/.build/pkg"
payload_root="$build_root/root"
scripts_root="$build_root/scripts"
resources_root="$repo_root/scripts/pkg_resources/install"
component_pkg="$build_root/ServerEngine-Install.component.pkg"
distribution_xml="$build_root/Distribution.xml"

if ! command -v pkgbuild >/dev/null 2>&1; then
    printf 'pkgbuild is required on macOS.\n' >&2
    exit 1
fi
if ! command -v productbuild >/dev/null 2>&1; then
    printf 'productbuild is required on macOS.\n' >&2
    exit 1
fi

if [ "$skip_app_build" != "1" ]; then
    app_build_cmd="/bin/sh \"$repo_root/scripts/build_macos_app.sh\" --version \"$version\" --no-bundle-runtime"
    if [ -n "$icon_path" ]; then
        app_build_cmd="$app_build_cmd --icon \"$icon_path\""
    fi
    if [ -n "$app_sign_identity" ]; then
        app_build_cmd="$app_build_cmd --app-sign-identity \"$app_sign_identity\""
    fi
    if [ "$clean" = "1" ]; then
        app_build_cmd="$app_build_cmd --clean"
        SERVER_ENGINE_BUILD_AT="$build_at" eval "$app_build_cmd"
    else
        app_build_cmd="$app_build_cmd --no-clean"
        SERVER_ENGINE_BUILD_AT="$build_at" eval "$app_build_cmd"
    fi
fi

if [ ! -d "$app_path" ]; then
    printf 'App bundle not found: %s\n' "$app_path" >&2
    exit 1
fi

printf 'Checking app bundle before PKG build:\n'
printf '  %s\n' "$app_path"
/usr/bin/codesign --verify --deep --strict --verbose=4 "$app_path"

if [ ! -d "$runtime_root" ]; then
    printf 'Runtime root not found: %s\n' "$runtime_root" >&2
    exit 1
fi

helper_source="$repo_root/scripts/privileged_helper/ServerEnginePrivilegedHelper.c"
helper_info_plist="$repo_root/scripts/privileged_helper/ServerEnginePrivilegedHelper-Info.plist"
helper_launchd_plist="$repo_root/scripts/privileged_helper/ServerEnginePrivilegedHelper-Launchd.plist"
helper_runtime_path="$runtime_root/bin/server-engine-privileged-helper"
helper_build_output="$build_root/server-engine-privileged-helper"
helper_output="$helper_runtime_path"
if [ -f "$helper_source" ]; then
    if ! command -v clang >/dev/null 2>&1; then
        printf 'clang is required to build privileged helper.\n' >&2
        exit 1
    fi
    /bin/mkdir -p "$build_root"
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
    helper_output="$helper_build_output"
elif [ -f "$helper_runtime_path" ]; then
    helper_output="$helper_runtime_path"
fi
if [ ! -f "$helper_output" ]; then
    printf 'Missing required helper binary. Checked:\n  %s\n  %s\n' "$helper_build_output" "$helper_runtime_path" >&2
    printf 'Build it first or keep scripts/privileged_helper/ServerEnginePrivilegedHelper.c available for auto-build.\n' >&2
    exit 1
fi

selected_runtime_items=""
resolve_runtime_item_source() {
    rel="$1"
    if [ -d "$runtime_root/bin/$rel" ] || [ -f "$runtime_root/bin/$rel" ]; then
        printf '%s\n' "$runtime_root/bin/$rel"
        return 0
    fi
    if [ -d "$runtime_root/$rel" ] || [ -f "$runtime_root/$rel" ]; then
        printf '%s\n' "$runtime_root/$rel"
        return 0
    fi
    return 1
}
if [ -n "$runtime_items_csv" ]; then
    items_norm="$(printf '%s' "$runtime_items_csv" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
    if [ -z "$items_norm" ]; then
        printf 'No runtime items selected. Use --runtime-items <csv>.\n' >&2
        exit 1
    fi
    for rel in $(printf '%s' "$items_norm" | tr ',' ' '); do
        [ -n "$rel" ] || continue
        case "$rel" in
            /*|*..*|*//*)
                printf 'Unsafe runtime item path: %s\n' "$rel" >&2
                exit 1
                ;;
        esac
        service="$(printf '%s' "$rel" | cut -d/ -f1)"
        case " php database server redis memcached mailpit tools node " in
            *" $service "*) ;;
            *)
                printf 'Unknown runtime item service: %s\n' "$service" >&2
                exit 1
                ;;
        esac
        source_item_path="$(resolve_runtime_item_source "$rel" || true)"
        if [ -z "$source_item_path" ]; then
            printf 'Missing selected runtime item: %s\n' "$runtime_root/$rel" >&2
            exit 1
        fi
        case " $selected_runtime_items " in
            *" $rel "*) ;;
            *) selected_runtime_items="$selected_runtime_items $rel" ;;
        esac
    done
    if [ -z "$selected_runtime_items" ]; then
        printf 'No valid runtime items selected.\n' >&2
        exit 1
    fi
fi

services_norm="$(printf '%s' "$services_csv" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
if [ -z "$selected_runtime_items" ] && [ -z "$services_norm" ]; then
    printf 'No runtime services selected. Use --services <csv>.\n' >&2
    exit 1
fi

valid_services="php database server redis memcached mailpit tools node"
selected_services=""
if [ -z "$selected_runtime_items" ]; then
    for service in $(printf '%s' "$services_norm" | tr ',' ' '); do
        [ -n "$service" ] || continue
        case " $valid_services " in
            *" $service "*) ;;
            *)
                printf 'Unknown runtime service in --services: %s\n' "$service" >&2
                exit 1
                ;;
        esac
        case " $selected_services " in
            *" $service "*) continue ;;
            *) selected_services="$selected_services $service" ;;
        esac
    done
fi

if [ -z "$selected_services" ] && [ -z "$selected_runtime_items" ]; then
    printf 'No valid runtime services selected.\n' >&2
    exit 1
fi

if [ -n "$selected_services" ]; then
    for required_dir in $selected_services; do
        if [ "$required_dir" = "tools" ]; then
            source_dir="$runtime_root/bin/tools"
        else
            source_dir="$runtime_root/bin/$required_dir"
        fi
        if [ ! -d "$source_dir" ]; then
            printf 'Missing selected runtime directory: %s\n' "$source_dir" >&2
            exit 1
        fi
    done
fi

if [ "$clean" = "1" ]; then
    rm -rf "$build_root"
fi

rm -rf "$payload_root" "$scripts_root"
mkdir -p "$scripts_root" "$payload_root/private/tmp/server-engine-installer"
mkdir -p "$(dirname "$output_path")"
cp "$repo_root/scripts/macos_pkg_postinstall.sh" "$scripts_root/postinstall"
chmod +x "$scripts_root/postinstall"
cp "$repo_root/scripts/macos_pkg_preinstall.sh" "$scripts_root/preinstall"
chmod +x "$scripts_root/preinstall"

mkdir -p "$scripts_root/app"
cp -R "$app_path" "$scripts_root/app/"

mkdir -p "$scripts_root/runtime"
mkdir -p "$scripts_root/runtime/bin"
if [ -n "$selected_runtime_items" ]; then
    for rel in $selected_runtime_items; do
        parent_rel="$(dirname "$rel")"
        mkdir -p "$scripts_root/runtime/$parent_rel"
        source_item_path="$(resolve_runtime_item_source "$rel" || true)"
        if [ -z "$source_item_path" ]; then
            printf 'Missing selected runtime item during copy: %s\n' "$rel" >&2
            exit 1
        fi
        cp -R "$source_item_path" "$scripts_root/runtime/$parent_rel/"
    done
else
    for service in $selected_services; do
        if [ "$service" = "tools" ]; then
            source_dir="$runtime_root/bin/tools"
        else
            source_dir="$runtime_root/bin/$service"
        fi
        cp -R "$source_dir" "$scripts_root/runtime/"
    done
fi
if [ -f "$helper_output" ]; then
    /bin/cp "$helper_output" "$scripts_root/runtime/bin/server-engine-privileged-helper"
fi

if [ -z "$runtime_sign_identity" ]; then
    printf 'Missing --runtime-sign-identity. Runtime/helper must be signed before packaging.\n' >&2
    exit 1
fi
if ! command -v codesign >/dev/null 2>&1; then
    printf 'codesign is required for runtime/helper signing.\n' >&2
    exit 1
fi

helper_in_pkg="$scripts_root/runtime/bin/server-engine-privileged-helper"
if [ -f "$helper_in_pkg" ]; then
    printf 'Signing staged privileged helper: %s\n' "$helper_in_pkg"
    /usr/bin/codesign \
        --force \
        --timestamp \
        --options runtime \
        --sign "$runtime_sign_identity" \
        "$helper_in_pkg"
fi

printf 'Signing Mach-O files in staged runtime payload...\n'
find "$scripts_root/runtime" -type f | while IFS= read -r runtime_file; do
    [ "$runtime_file" = "$helper_in_pkg" ] && continue
    if /usr/bin/file -b "$runtime_file" 2>/dev/null | grep -q 'Mach-O'; then
        /usr/bin/codesign \
            --force \
            --timestamp \
            --options runtime \
            --sign "$runtime_sign_identity" \
            "$runtime_file"
    fi
done

printf 'server-engine-installer\n' > "$payload_root/private/tmp/server-engine-installer/.keep"

if [ -f "$output_path" ]; then
    rm -f "$output_path"
fi
if [ -f "$component_pkg" ]; then
    rm -f "$component_pkg"
fi

cat > "$distribution_xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
  <title>Server Engine Installer</title>
  <welcome file="welcome.html"/>
  <readme file="readme.html"/>
  <license file="license.txt"/>
  <conclusion file="conclusion.html"/>
  <options customize="never" require-scripts="true"/>
  <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
  <choices-outline>
    <line choice="default">
      <line choice="install.choice"/>
    </line>
  </choices-outline>
  <choice id="default"/>
  <choice id="install.choice" title="Install Server Engine">
    <pkg-ref id="$identifier.component"/>
  </choice>
  <pkg-ref id="$identifier.component" version="$version">$(basename "$component_pkg")</pkg-ref>
</installer-gui-script>
EOF

printf 'Building installer package...\n'
pkgbuild \
    --root "$payload_root" \
    --scripts "$scripts_root" \
    --identifier "$identifier.component" \
    --version "$version" \
    --install-location "/" \
    "$component_pkg"

productbuild \
    --distribution "$distribution_xml" \
    --resources "$resources_root" \
    --package-path "$build_root" \
    "$output_path"

printf '\nBuilt installer package:\n'
printf '  %s\n' "$output_path"
