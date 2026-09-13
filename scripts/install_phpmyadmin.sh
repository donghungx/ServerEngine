#!/bin/sh

set -eu

usage() {
    cat <<'EOF'
Usage:
  scripts/install_phpmyadmin.sh
  scripts/install_phpmyadmin.sh --version 5.2.2 [options]

Download and stage a phpMyAdmin release into this repo's tool runtime layout:
  dist/runtime/phpmyadmin/<version>

If run with no arguments, an interactive phpMyAdmin version selector is shown.

Options:
  --version <version>      phpMyAdmin version to download
  --url <url>              Override release archive URL
  --archive <path>         Use an existing archive instead of downloading
  --output <path>          Override staged output directory
  --overwrite              Remove an existing target directory first
  --skip-download          Do not download; requires --archive
  --skip-deploy            Skip copying into the app-managed runtime root
  --deploy-root <path>     Override deploy root.
                           Default: <repo>/dist/runtime/phpmyadmin
  --help                   Show this help

Examples:
  scripts/install_phpmyadmin.sh
  scripts/install_phpmyadmin.sh --version 5.2.2 --overwrite
  scripts/install_phpmyadmin.sh --version 4.9.9 --overwrite
  scripts/install_phpmyadmin.sh --archive /tmp/phpMyAdmin-5.2.2-all-languages.tar.gz --version 5.2.2 --overwrite
EOF
}

abspath() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s\n' "$(pwd)/$1" ;;
    esac
}

download_file() {
    target_url="$1"
    target_path="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -L --fail --output "$target_path" "$target_url"
        return
    fi

    if command -v wget >/dev/null 2>&1; then
        wget -O "$target_path" "$target_url"
        return
    fi

    printf 'curl or wget is required to download phpMyAdmin.\n' >&2
    exit 1
}

interactive_pick_version() {
    tty_path="/dev/tty"

    versions="5.2.3
5.1.4
5.0.4
4.9.11
4.8.5
4.7.9"

    printf '\nSelect phpMyAdmin version:\n\n' >"$tty_path"

    i=1
    printf '%s\n' "$versions" | while IFS= read -r item; do
        printf '  %s) %s\n' "$i" "$item" >"$tty_path"
        i=$((i + 1))
    done

    printf '\nEnter choice [1-6]: ' >"$tty_path"
    read choice <"$tty_path"

    case "$choice" in
        1) selected_version="5.2.3" ;;
        2) selected_version="5.1.4" ;;
        3) selected_version="5.0.4" ;;
        4) selected_version="4.9.11" ;;
        5) selected_version="4.8.5" ;;
        6) selected_version="4.7.9" ;;
        *)
            printf 'Invalid selection.\n' >&2
            return 1
            ;;
    esac

    printf 'Selected phpMyAdmin %s\n' "$selected_version" >"$tty_path"
    printf 'Install and overwrite existing target if needed? [Y/n]: ' >"$tty_path"
    read answer <"$tty_path"

    case "$answer" in
        ""|y|Y|yes|YES)
            printf '%s\n' "$selected_version"
            ;;
        *)
            return 1
            ;;
    esac
}

original_argc="$#"
version=""
url=""
archive=""
output=""
overwrite="0"
skip_download="0"
skip_deploy="0"
deploy_root=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --version)
            version="${2:-}"
            shift 2
            ;;
        --url)
            url="${2:-}"
            shift 2
            ;;
        --archive)
            archive="$(abspath "${2:-}")"
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
        --skip-download)
            skip_download="1"
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

if [ "$original_argc" -eq 0 ] && [ -z "$version" ]; then
    selected_version="$(interactive_pick_version || true)"

    if [ -z "$selected_version" ]; then
        printf 'No phpMyAdmin version selected.\n' >&2
        exit 1
    fi

    version="$selected_version"
    overwrite="1"
fi

if [ -z "$version" ]; then
    printf 'phpMyAdmin version is required.\n' >&2
    usage >&2
    exit 1
fi

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

if [ -z "$output" ]; then
    output="$repo_root/dist/runtime/phpmyadmin/$version"
fi

if [ -z "$deploy_root" ]; then
    deploy_root="$repo_root/dist/runtime/phpmyadmin"
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

if [ -z "$url" ]; then
    url="https://files.phpmyadmin.net/phpMyAdmin/$version/phpMyAdmin-$version-all-languages.tar.gz"
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/server-engine-pma.XXXXXX")"

cleanup() {
    rm -rf "$work_dir"
}

trap cleanup EXIT INT TERM

archive_path="$archive"

if [ -z "$archive_path" ]; then
    archive_path="$work_dir/phpMyAdmin-$version-all-languages.tar.gz"
fi

if [ "$skip_download" = "1" ]; then
    if [ -z "$archive" ] || [ ! -f "$archive_path" ]; then
        printf '%s\n' '--skip-download requires a valid --archive path.' >&2
        exit 1
    fi
else
    printf 'Downloading phpMyAdmin %s\n' "$version"
    printf '  %s\n' "$url"
    download_file "$url" "$archive_path"
fi

if [ ! -f "$archive_path" ]; then
    printf 'Archive not found: %s\n' "$archive_path" >&2
    exit 1
fi

extract_dir="$work_dir/extracted"
mkdir -p "$extract_dir"

case "$archive_path" in
    *.tar.gz|*.tgz)
        tar -xzf "$archive_path" -C "$extract_dir"
        ;;
    *.zip)
        if ! command -v unzip >/dev/null 2>&1; then
            printf 'unzip is required to extract zip archives.\n' >&2
            exit 1
        fi
        unzip -q "$archive_path" -d "$extract_dir"
        ;;
    *)
        printf 'Unsupported phpMyAdmin archive format: %s\n' "$archive_path" >&2
        exit 1
        ;;
esac

source_dir="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)"

if [ -z "$source_dir" ] || [ ! -f "$source_dir/index.php" ]; then
    printf 'Could not locate extracted phpMyAdmin application directory.\n' >&2
    exit 1
fi

mkdir -p "$(dirname "$output")"
cp -R "$source_dir" "$output"

mkdir -p "$output/tmp"
mkdir -p "$output/upload"
mkdir -p "$output/save"

printf '\nDone.\n'
printf 'Installed phpMyAdmin runtime:\n'
printf '  %s\n' "$output"
printf 'Version:\n'
printf '  %s\n' "$version"
printf 'Archive source:\n'
printf '  %s\n' "$archive_path"

if [ "$skip_deploy" != "1" ]; then
    deploy_target="$deploy_root/$version"

    printf '\nDeploying phpMyAdmin into app runtime root...\n'

    mkdir -p "$deploy_root"
    rm -rf "$deploy_target"
    cp -R "$output" "$deploy_target"

    printf 'Deployed runtime:\n'
    printf '  %s\n' "$deploy_target"
fi

trap - EXIT INT TERM
cleanup
