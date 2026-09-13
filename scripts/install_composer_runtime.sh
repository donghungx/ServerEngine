#!/bin/sh

set -eu

usage() {
    cat <<'EOF'
Usage:
  scripts/install_composer_runtime.sh --version 2.8.9 [options]

Install Composer into:
  dist/runtime/tools/composer/composer-<version>/composer.phar

Options:
  --version <version>       Required Composer version. Example: 2.8.9
  --runtime-name <name>     Override runtime folder name. Default: composer-<version>
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
    runtime_name="composer-$version"
fi

if [ -z "$output" ]; then
    output="$repo_root/dist/runtime/tools/composer/$runtime_name"
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

url="https://getcomposer.org/download/$version/composer.phar"
tmp_file="$tmp_dir/composer.phar"

printf 'Downloading Composer %s...\n' "$version"
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
    printf 'Downloaded Composer file is empty.\n' >&2
    exit 1
fi

if [ "$skip_verify" != "1" ]; then
    if ! grep -a "Composer" "$tmp_file" >/dev/null 2>&1; then
        printf 'Downloaded file does not look like Composer.\n' >&2
        exit 1
    fi
fi

cp "$tmp_file" "$output/composer.phar"
chmod 755 "$output/composer.phar"

php_bin=""
php_version=""
composer_version_detected=""

if command -v php >/dev/null 2>&1; then
    php_bin="$(command -v php)"
    php_version="$(php -r 'echo PHP_VERSION;' 2>/dev/null || true)"
    composer_version_detected="$(php "$output/composer.phar" --version 2>/dev/null || true)"
fi

cat > "$output/runtime.json" <<EOF
{
  "name": "Composer",
  "version": "$version",
  "runtime_name": "$runtime_name",
  "binary": "composer.phar",
  "php_binary_detected": "$php_bin",
  "php_version_detected": "$php_version",
  "composer_version_detected": "$composer_version_detected"
}
EOF

info_file="$output/composer-info.txt"

if [ -n "$php_bin" ]; then
    {
        php "$output/composer.phar" --version || true
        printf '\n'
        php "$output/composer.phar" diagnose || true
    } > "$info_file" 2>&1
else
    cat > "$info_file" <<EOF
PHP was not found in PATH during install.

Test manually with:
php "$output/composer.phar" --version
php "$output/composer.phar" diagnose
EOF
fi

printf '\nDone.\n'
printf 'Installed Composer runtime:\n'
printf '  %s\n' "$output"
printf '\nFiles:\n'
printf '  %s\n' "$output/composer.phar"
printf '  %s\n' "$output/runtime.json"
printf '  %s\n' "$output/composer-info.txt"
printf '\nRun with:\n'
printf '  php "%s/composer.phar" --version\n' "$output"

trap - EXIT
rm -rf "$tmp_dir"
