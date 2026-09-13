#!/bin/sh

set -eu

usage() {
    cat <<'EOF'
Usage:
  scripts/install_wp_cli_runtime.sh --version 2.12.0 [options]

Install WP-CLI into:
  dist/runtime/tools/wp-cli/wp-cli-<version>/wp-cli.phar

Options:
  --version <version>       Required WP-CLI version. Example: 2.12.0
  --runtime-name <name>     Override runtime folder name. Default: wp-cli-<version>
  --output <path>           Override staged output directory
  --overwrite               Remove existing target directory first
  --skip-verify             Skip basic verification
  --help                    Show this help
EOF
}

abspath() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s\n' "$(pwd)/$1" ;;
    esac
}

version=""
runtime_name=""
output=""
overwrite="0"
skip_verify="0"
repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --version)
            version="${2:-}"
            shift 2
            ;;
        --runtime-name)
            runtime_name="${2:-}"
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
        --skip-verify)
            skip_verify="1"
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

if [ -z "$version" ]; then
    printf 'Missing required --version.\n\n' >&2
    usage >&2
    exit 1
fi

if [ -z "$runtime_name" ]; then
    runtime_name="wp-cli-$version"
fi

if [ -z "$output" ]; then
    output="$repo_root/dist/runtime/tools/wp-cli/$runtime_name"
fi

if [ -e "$output" ]; then
    if [ "$overwrite" = "1" ]; then
        rm -rf "$output"
    else
        printf 'Target directory already exists: %s\n' "$output" >&2
        printf 'Use --overwrite to replace it.\n' >&2
        exit 1
    fi
fi

mkdir -p "$output"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

url="https://github.com/wp-cli/wp-cli/releases/download/v$version/wp-cli-$version.phar"
tmp_file="$tmp_dir/wp-cli.phar"

printf 'Downloading WP-CLI %s...\n' "$version"
printf '  %s\n' "$url"

if command -v curl >/dev/null 2>&1; then
    curl -fL "$url" -o "$tmp_file"
elif command -v python3 >/dev/null 2>&1; then
    python3 - "$url" "$tmp_file" <<'PY'
import sys
import urllib.request

url = sys.argv[1]
target = sys.argv[2]

with urllib.request.urlopen(url, timeout=60) as response:
    data = response.read()

with open(target, "wb") as f:
    f.write(data)
PY
else
    printf 'curl or python3 is required.\n' >&2
    exit 1
fi

if [ ! -s "$tmp_file" ]; then
    printf 'Downloaded WP-CLI file is empty.\n' >&2
    exit 1
fi

if [ "$skip_verify" != "1" ]; then
    if ! grep -a "WP-CLI" "$tmp_file" >/dev/null 2>&1; then
        printf 'Downloaded file does not look like WP-CLI.\n' >&2
        exit 1
    fi
fi

cp "$tmp_file" "$output/wp-cli.phar"
chmod 755 "$output/wp-cli.phar"

cat > "$output/runtime.json" <<EOF
{
  "name": "WP-CLI",
  "version": "$version",
  "runtime_name": "$runtime_name",
  "binary": "wp-cli.phar"
}
EOF

info_file="$output/wp-cli-info.txt"

if command -v php >/dev/null 2>&1; then
    php "$output/wp-cli.phar" --info > "$info_file" 2>&1 || true
else
    cat > "$info_file" <<EOF
PHP was not found in PATH during install.

Test manually with:
php "$output/wp-cli.phar" --info
EOF
fi

printf '\nDone.\n'
printf 'Installed WP-CLI runtime:\n'
printf '  %s\n' "$output"
printf '\nRun with:\n'
printf '  php "%s/wp-cli.phar" --info\n' "$output"

if command -v php >/dev/null 2>&1; then
    printf '\nTesting WP-CLI:\n'
    php "$output/wp-cli.phar" --info || true
fi
