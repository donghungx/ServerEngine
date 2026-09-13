#!/bin/sh

set -eu

usage() {
    cat <<'EOF'
Usage:
  scripts/sync_runtime_bin_to_project.sh [--source <path>] [--dest <path>] [--clean]

Copies runtime bin content from installed Server Engine runtime into project staging runtime folder.

Defaults:
  --source ~/Library/Application Support/Server Engine/bin
  --dest   ./runtime

Examples:
  scripts/sync_runtime_bin_to_project.sh --clean
  scripts/sync_runtime_bin_to_project.sh --dest .build/pkg/scripts/runtime --clean
EOF
}

abspath() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s\n' "$(pwd)/$1" ;;
    esac
}

source_dir="$HOME/Library/Application Support/Server Engine/bin"
dest_dir="$(pwd)/runtime"
clean="0"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --source)
            source_dir="$(abspath "${2:-}")"
            shift 2
            ;;
        --dest)
            dest_dir="$(abspath "${2:-}")"
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
            printf 'Unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [ ! -d "$source_dir" ]; then
    printf 'Source bin directory not found: %s\n' "$source_dir" >&2
    exit 1
fi

if [ "$clean" = "1" ] && [ -d "$dest_dir" ]; then
    rm -rf "$dest_dir"
fi

mkdir -p "$dest_dir"

# Always clear existing project runtime items before re-copying.
for name in php database server redis memcached mailpit node tools; do
    rm -rf "$dest_dir/$name"
done
rm -f "$dest_dir/server-engine-privileged-helper"

# Core runtime categories under bin/.
for name in php database server redis memcached mailpit node tools; do
    if [ -d "$source_dir/$name" ]; then
        cp -R "$source_dir/$name" "$dest_dir/$name"
        printf 'Copied: %s\n' "$name"
    fi
done

# Privileged helper is expected at bin root and should be packaged too.
if [ -f "$source_dir/server-engine-privileged-helper" ]; then
    cp "$source_dir/server-engine-privileged-helper" "$dest_dir/server-engine-privileged-helper"
    chmod 755 "$dest_dir/server-engine-privileged-helper" || true
    printf 'Copied: server-engine-privileged-helper\n'
fi

printf '\nRuntime sync complete.\nSource: %s\nDest:   %s\n' "$source_dir" "$dest_dir"
