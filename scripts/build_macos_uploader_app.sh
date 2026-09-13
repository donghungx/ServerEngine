#!/bin/sh

set -eu

usage() {
    cat <<'EOF'
Usage:
  scripts/build_macos_uploader_app.sh [options]

Build the Runtime Uploader GUI as a macOS .app bundle.

Options:
  --clean        Remove previous build output first
  --help         Show this help
EOF
}

clean="0"

while [ "$#" -gt 0 ]; do
    case "$1" in
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
            exit 1
            ;;
    esac
done

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

script_path="$repo_root/scripts/runtime_uploader_gui.py"
build_root="$repo_root/.build/runtime-uploader"
dist_root="$repo_root/dist/uploader"
venv_dir="$repo_root/.venv-runtime-uploader"

if [ "$clean" = "1" ]; then
    rm -rf "$build_root"
    rm -rf "$dist_root"
fi

mkdir -p "$dist_root"

if [ ! -d "$venv_dir" ]; then
    python3 -m venv "$venv_dir"
fi

. "$venv_dir/bin/activate"

python -m pip install --upgrade pip
python -m pip install pyinstaller

printf 'Building Runtime Uploader.app...\n'

pyinstaller \
    --noconfirm \
    --windowed \
    --clean \
    --name "Runtime Uploader" \
    --distpath "$dist_root" \
    --workpath "$build_root" \
    --specpath "$build_root" \
    "$script_path"

printf '\nBuilt app:\n'
printf '  %s\n' "$dist_root/Runtime Uploader.app"