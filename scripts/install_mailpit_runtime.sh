#!/bin/sh

set -eu

usage() {
    cat <<'EOF'
Usage:
  scripts/install_mailpit_runtime.sh

Install or stage a Mailpit runtime into this repo's prebuild layout:
  prebuild/mailpit/mailpit-<version>

Options:
  --version <version>   Mailpit version, for example 1.26.2. Default: latest
  --prefix <path>       Override target path
  --overwrite           Remove an existing target directory first
  --skip-package        Skip the macOS self-contained packaging step
  --package-output <p>  Override packaged output directory
  --skip-deploy         Skip copying packaged runtime into the app-managed runtime root
  --deploy-root <path>  Override deploy root. Default: <repo>/dist/runtime/mailpit
  --help                Show this help

Examples:
  scripts/install_mailpit_runtime.sh --overwrite
  scripts/install_mailpit_runtime.sh --version 1.26.2 --overwrite
EOF
}

abspath() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s\n' "$(pwd)/$1" ;;
    esac
}

version=""
prefix=""
overwrite="0"
skip_package="0"
package_output=""
skip_deploy="0"
deploy_root=""
packaged_dir=""

while [ "$#" -gt 0 ]; do
    case "$1" in
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

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

if ! command -v curl >/dev/null 2>&1; then
    printf 'curl is required for this script.\n' >&2
    exit 1
fi

if ! command -v tar >/dev/null 2>&1; then
    printf 'tar is required for this script.\n' >&2
    exit 1
fi

if [ -z "$version" ]; then
    version="$(curl -fsSL https://api.github.com/repos/axllent/mailpit/releases/latest \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"].lstrip("v"))')"
fi

arch="$(uname -m)"
case "$arch" in
    arm64)
        asset="mailpit-darwin-arm64.tar.gz"
        ;;
    x86_64)
        asset="mailpit-darwin-amd64.tar.gz"
        ;;
    *)
        printf 'Unsupported macOS architecture: %s\n' "$arch" >&2
        exit 1
        ;;
esac

runtime_name="mailpit-$version"

if [ -z "$prefix" ]; then
    prefix="$repo_root/prebuild/mailpit/$runtime_name"
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

mkdir -p "$prefix/bin"
mkdir -p "$prefix/data"
mkdir -p "$prefix/logs"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

url="https://github.com/axllent/mailpit/releases/download/v$version/$asset"

printf 'Downloading Mailpit %s\n' "$version"
printf '  %s\n' "$url"

curl -fL "$url" -o "$tmp_dir/mailpit.tar.gz"
tar -xzf "$tmp_dir/mailpit.tar.gz" -C "$tmp_dir"

if [ ! -f "$tmp_dir/mailpit" ]; then
    found="$(find "$tmp_dir" -type f -name mailpit | head -n 1 || true)"
    if [ -z "$found" ]; then
        printf 'Mailpit binary not found in downloaded archive.\n' >&2
        exit 1
    fi
    cp "$found" "$prefix/bin/mailpit"
else
    cp "$tmp_dir/mailpit" "$prefix/bin/mailpit"
fi

chmod +x "$prefix/bin/mailpit"

printf '\nDone.\n'
printf 'Installed runtime: %s\n' "$prefix"
printf 'Detected engine: mailpit\n'
printf 'Detected version: %s\n' "$version"
printf 'Server binary:\n'
printf '  %s\n' "$prefix/bin/mailpit"

if [ "$skip_package" != "1" ]; then
    package_script="$repo_root/scripts/package_mailpit_runtime_macos.sh"
    if [ -f "$package_script" ]; then
        printf '\nPackaging self-contained macOS runtime...\n'
        if [ -n "$package_output" ]; then
            packaged_dir="$package_output"
            /bin/sh "$package_script" --source "$prefix" --overwrite --output "$packaged_dir"
        else
            packaged_dir="$repo_root/dist/runtime/mailpit/$(basename "$prefix")"
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
        deploy_root="$repo_root/dist/runtime/mailpit"
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
