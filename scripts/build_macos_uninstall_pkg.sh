#!/bin/sh

set -eu

usage() {
    cat <<'EOF'
Usage:
  scripts/build_macos_uninstall_pkg.sh [options]

Build a macOS uninstaller package that removes:
  - /Applications/Server Engine.app
  - ~/Library/Application Support/Server Engine
  - ~/Library/Logs/Server Engine
  - ~/Library/Preferences/com.serverengine.app.plist

Options:
  --output <path>      Output .pkg path. Default: dist/pkg/ServerEngine-Uninstall.pkg
  --identifier <id>    Package identifier. Default: com.serverengine.uninstaller
  --version <version>  Package version. Default: parsed from pyproject.toml
  --clean              Remove previous temporary package staging first
  --help               Show this help
EOF
}

abspath() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s\n' "$(pwd)/$1" ;;
    esac
}

output_path=""
identifier="com.serverengine.uninstaller"
version=""
clean="0"

while [ "$#" -gt 0 ]; do
    case "$1" in
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
        --clean)
            clean="1"
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

if [ -z "$output_path" ]; then
    output_path="$repo_root/dist/pkg/ServerEngine-Uninstall.pkg"
fi

build_root="$repo_root/.build/pkg-uninstall"
payload_root="$build_root/root"
scripts_root="$build_root/scripts"
resources_root="$repo_root/scripts/pkg_resources/uninstall"
component_pkg="$build_root/ServerEngine-Uninstall.component.pkg"
distribution_xml="$build_root/Distribution.xml"

if ! command -v pkgbuild >/dev/null 2>&1; then
    printf 'pkgbuild is required on macOS.\n' >&2
    exit 1
fi
if ! command -v productbuild >/dev/null 2>&1; then
    printf 'productbuild is required on macOS.\n' >&2
    exit 1
fi

if [ "$clean" = "1" ]; then
    rm -rf "$build_root"
fi

rm -rf "$payload_root" "$scripts_root"
mkdir -p "$payload_root/private/tmp/server-engine-uninstaller" "$scripts_root" "$(dirname "$output_path")"

cp "$repo_root/scripts/macos_uninstall_postinstall.sh" "$scripts_root/postinstall"
chmod +x "$scripts_root/postinstall"
cp "$repo_root/scripts/macos_uninstall_preinstall.sh" "$scripts_root/preinstall"
chmod +x "$scripts_root/preinstall"
printf 'server-engine-uninstaller\n' > "$payload_root/private/tmp/server-engine-uninstaller/.keep"

if [ -f "$output_path" ]; then
    rm -f "$output_path"
fi
if [ -f "$component_pkg" ]; then
    rm -f "$component_pkg"
fi

cat > "$distribution_xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
  <title>Server Engine Uninstaller</title>
  <welcome file="welcome.html"/>
  <readme file="readme.html"/>
  <conclusion file="conclusion.html"/>
  <options customize="never" require-scripts="true" rootVolumeOnly="true"/>
  <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
  <choices-outline>
    <line choice="default">
      <line choice="uninstall.choice"/>
    </line>
  </choices-outline>
  <choice id="default"/>
  <choice id="uninstall.choice" title="Uninstall Server Engine">
    <pkg-ref id="$identifier.component"/>
  </choice>
  <pkg-ref id="$identifier.component" version="$version">$(basename "$component_pkg")</pkg-ref>
</installer-gui-script>
EOF

printf 'Building uninstaller package...\n'
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

printf '\nBuilt uninstaller package:\n'
printf '  %s\n' "$output_path"
