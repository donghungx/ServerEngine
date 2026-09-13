#!/bin/sh

set -eu

usage() {
    cat <<'EOF'
Usage:
  scripts/package_node_runtime_macos.sh --source prebuild/node/node22.22.3 [options]

Package a macOS Node.js runtime into:
  ~/Library/Application Support/Server Engine/bin/node/<runtime-name>

Options:
  --source <path>     Source Node runtime directory. Required.
  --output <path>     Output directory. Default: ~/Library/Application Support/Server Engine/bin/node/<runtime-name>
  --overwrite         Remove output directory first if it already exists
  --help              Show this help
EOF
}

abspath() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s\n' "$(pwd)/$1" ;;
    esac
}

source_dir=""
output_dir=""
overwrite="0"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --source)
            source_dir="$(abspath "${2:-}")"
            shift 2
            ;;
        --output)
            output_dir="$(abspath "${2:-}")"
            shift 2
            ;;
        --overwrite)
            overwrite="1"
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

if [ -z "$source_dir" ]; then
    printf 'Missing required argument: --source\n\n' >&2
    usage >&2
    exit 1
fi

if [ ! -d "$source_dir" ]; then
    printf 'Source runtime not found: %s\n' "$source_dir" >&2
    exit 1
fi

if [ ! -x "$source_dir/bin/node" ]; then
    printf 'Node binary not found: %s/bin/node\n' "$source_dir" >&2
    exit 1
fi

if [ -z "$output_dir" ]; then
    repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
    output_dir="$HOME/Library/Application Support/Server Engine/bin/node/$(basename "$source_dir")"
fi

if [ -d "$output_dir" ]; then
    if [ "$overwrite" = "1" ]; then
        rm -rf "$output_dir"
    else
        printf 'Output directory already exists: %s\n' "$output_dir" >&2
        printf 'Use --overwrite to replace it.\n' >&2
        exit 1
    fi
fi

mkdir -p "$(dirname "$output_dir")"
cp -R "$source_dir" "$output_dir"

chmod +x "$output_dir/bin/node"
if [ -f "$output_dir/bin/npm" ]; then
    chmod +x "$output_dir/bin/npm"
fi
if [ -f "$output_dir/bin/npx" ]; then
    chmod +x "$output_dir/bin/npx"
fi

printf 'Packaged Node runtime:\n'
printf '  source: %s\n' "$source_dir"
printf '  output: %s\n' "$output_dir"
