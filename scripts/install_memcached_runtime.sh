#!/bin/sh

set -eu

usage() {
    cat <<'EOF'
Usage:
  scripts/install_memcached_runtime.sh
  scripts/install_memcached_runtime.sh --formula memcached [options]

Install or stage a Homebrew Memcached runtime into this repo's prebuild layout:
  prebuild/memcached/memcached-<version>

Options:
  --formula <name>      Homebrew formula to install/stage. Default: memcached
  --keg-version <ver>   Stage a specific installed Homebrew keg version
  --list-installed-versions
                        Print installed keg versions for the selected formula and exit
  --engine <name>       Override detected engine. Default: memcached
  --version <version>   Override detected version
  --prefix <path>       Override target path
  --overwrite           Remove an existing target directory first
  --skip-install        Do not run brew install; only stage an already installed formula
  --skip-package        Skip the macOS self-contained packaging step
  --package-output <p>  Override packaged output directory
  --skip-deploy         Skip copying the packaged runtime into the app-managed runtime root
  --deploy-root <path>  Override deploy root. Default: <repo>/dist/runtime/memcached
  --help                Show this help

Examples:
  scripts/install_memcached_runtime.sh
  scripts/install_memcached_runtime.sh --formula memcached --overwrite
EOF
}

abspath() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s\n' "$(pwd)/$1" ;;
    esac
}

formula="memcached"
keg_version=""
engine=""
version=""
prefix=""
overwrite="0"
skip_install="0"
skip_package="0"
package_output=""
skip_deploy="0"
deploy_root=""
selected_was_linked="0"
packaged_dir=""
did_package="0"
list_versions_only="0"

linked_keg() {
    brew info --json=v2 "$1" 2>/dev/null | python3 -c 'import json,sys; data=json.load(sys.stdin); formulae=data.get("formulae", []); value=formulae[0].get("linked_keg") if formulae else None; print("" if value in (None, "", 0) else str(value))' 2>/dev/null || true
}

is_linked() {
    [ -n "$(linked_keg "$1")" ]
}

restore_homebrew_links() {
    if [ "$selected_was_linked" != "1" ]; then
        brew unlink "$formula" >/dev/null 2>&1 || true
    fi
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --formula)
            formula="${2:-}"
            shift 2
            ;;
        --engine)
            engine="${2:-}"
            shift 2
            ;;
        --keg-version)
            keg_version="${2:-}"
            shift 2
            ;;
        --list-installed-versions)
            list_versions_only="1"
            shift
            ;;
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
        --skip-install)
            skip_install="1"
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

if ! command -v brew >/dev/null 2>&1; then
    printf 'Homebrew is required for this script.\n' >&2
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    printf 'python3 is required for this script.\n' >&2
    exit 1
fi

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
selected_was_linked="0"
if is_linked "$formula"; then
    selected_was_linked="1"
fi

trap restore_homebrew_links EXIT

brew_cellar="$(brew --cellar "$formula" 2>/dev/null || true)"
if [ "$list_versions_only" = "1" ]; then
    if [ -z "$brew_cellar" ] || [ ! -d "$brew_cellar" ]; then
        printf 'No installed versions found for formula: %s\n' "$formula"
        exit 0
    fi
    found_any="0"
    for dir in "$brew_cellar"/*; do
        if [ -d "$dir" ]; then
            found_any="1"
            basename "$dir"
        fi
    done
    if [ "$found_any" = "0" ]; then
        printf 'No installed versions found for formula: %s\n' "$formula"
    fi
    exit 0
fi

if [ "$skip_install" != "1" ]; then
    printf 'Reinstalling Homebrew formula: %s\n' "$formula"
    brew reinstall "$formula"
fi

if [ -n "$keg_version" ]; then
    if [ -z "$brew_cellar" ] || [ ! -d "$brew_cellar/$keg_version" ]; then
        printf 'Requested keg version not installed: %s\n' "$keg_version" >&2
        printf 'Run with --list-installed-versions to see available versions.\n' >&2
        exit 1
    fi
    brew_prefix="$brew_cellar/$keg_version"
else
    brew_prefix="$(brew --prefix "$formula" 2>/dev/null || true)"
fi

if [ -z "$brew_prefix" ] || [ ! -d "$brew_prefix" ]; then
    printf 'Formula prefix not found for %s\n' "$formula" >&2
    exit 1
fi
brew_prefix="$(CDPATH= cd -- "$brew_prefix" && pwd -P)"

formula_json="$(brew info --json=v2 "$formula" 2>/dev/null || true)"
stable_version="$(printf '%s' "$formula_json" | python3 -c 'import json,sys; data=json.load(sys.stdin); formulae=data.get("formulae", []); print(formulae[0]["versions"]["stable"] if formulae else "")' 2>/dev/null || true)"

if [ -z "$engine" ]; then
    case "$formula" in
        memcached*|*memcached*)
            engine="memcached"
            ;;
        *)
            printf 'Could not detect engine from formula %s. Pass --engine.\n' "$formula" >&2
            exit 1
            ;;
    esac
fi

if [ -z "$version" ]; then
    if [ -n "$keg_version" ]; then
        version="$keg_version"
    else
        version="$stable_version"
    fi
    if [ -z "$version" ]; then
        printf 'Could not detect version for %s from Homebrew metadata.\n' "$formula" >&2
        exit 1
    fi
fi

if [ -z "$prefix" ]; then
    prefix="$repo_root/prebuild/memcached/$engine-$version"
fi

if [ ! -d "$brew_prefix/bin" ]; then
    printf 'Invalid Homebrew runtime prefix, missing bin/: %s\n' "$brew_prefix" >&2
    exit 1
fi

if [ ! -x "$brew_prefix/bin/memcached" ]; then
    printf 'Expected Memcached server binary missing: %s/bin/memcached\n' "$brew_prefix" >&2
    exit 1
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

mkdir -p "$(dirname "$prefix")"
mkdir -p "$prefix"

printf 'Staging runtime from %s\n' "$brew_prefix"
cp -R "$brew_prefix"/. "$prefix"

mkdir -p "$prefix/conf"
mkdir -p "$prefix/data"
mkdir -p "$prefix/logs"

printf '\nDone.\n'
printf 'Installed runtime: %s\n' "$prefix"
printf 'Detected engine: %s\n' "$engine"
printf 'Detected version: %s\n' "$version"
printf 'Server binary:\n'
printf '  %s\n' "$prefix/bin/memcached"
printf 'CLI binary:\n'
if [ -x "$prefix/bin/memcached-tool" ]; then
    printf '  %s\n' "$prefix/bin/memcached-tool"
else
    printf '  not found\n'
fi

if [ "$skip_package" != "1" ]; then
    package_script="$repo_root/scripts/package_memcached_runtime_macos.sh"
    if [ -f "$package_script" ]; then
        printf '\nPackaging self-contained macOS runtime...\n'
        if [ -n "$package_output" ]; then
            packaged_dir="$package_output"
            /bin/sh "$package_script" --source "$prefix" --overwrite --output "$packaged_dir"
        else
            packaged_dir="$repo_root/dist/runtime/memcached/$(basename "$prefix")"
            /bin/sh "$package_script" --source "$prefix" --overwrite --output "$packaged_dir"
        fi
        did_package="1"
    else
        printf '\nPackaging skipped: %s not found.\n' "$package_script" >&2
    fi
else
    printf '\nPackaging skipped by --skip-package.\n'
fi

if [ "$skip_deploy" != "1" ] && [ "$did_package" = "1" ]; then
    if [ -z "$deploy_root" ]; then
        deploy_root="$repo_root/dist/runtime/memcached"
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
elif [ "$skip_deploy" != "1" ] && [ "$did_package" != "1" ]; then
    printf '\nDeploy skipped because packaged runtime output is not available.\n'
fi

restore_homebrew_links
trap - EXIT
