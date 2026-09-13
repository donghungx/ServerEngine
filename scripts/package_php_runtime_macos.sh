#!/bin/sh

set -eu

usage() {
    cat <<'EOF'
Usage:
  scripts/package_php_runtime_macos.sh --source prebuild/php/php8.5.0 [options]

Convert a macOS PHP runtime into a self-contained distributable bundle by:
  - copying the runtime to an output directory
  - copying non-system dylib dependencies into lib/
  - rewriting load paths with install_name_tool

The packaged runtime is shared by both web-server modes in the app:
  - Apache uses the bundled PHP runtime directly
  - Nginx uses the bundled bin/php-cgi for FastCGI backends

Options:
  --source <path>     Source PHP runtime directory. Required.
  --output <path>     Output directory. Default: dist/runtime/php/<runtime-name>
  --overwrite         Remove output directory first if it already exists
  --help              Show this help

Examples:
  scripts/package_php_runtime_macos.sh --source prebuild/php/php8.5.0 --overwrite
  scripts/package_php_runtime_macos.sh --source prebuild/php/php8.5.0 --output dist/runtime/php/php8.5.0 --overwrite
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

if [ ! -x "$source_dir/bin/php" ]; then
    printf 'Source runtime is missing bin/php: %s\n' "$source_dir/bin/php" >&2
    exit 1
fi

if [ ! -x "$source_dir/bin/php-cgi" ]; then
    printf 'Source runtime is missing bin/php-cgi: %s\n' "$source_dir/bin/php-cgi" >&2
    exit 1
fi

if [ -z "$output_dir" ]; then
    repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
    output_dir="$repo_root/dist/runtime/php/$(basename "$source_dir")"
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

if ! command -v otool >/dev/null 2>&1 || ! command -v install_name_tool >/dev/null 2>&1; then
    printf 'This script requires otool and install_name_tool on macOS.\n' >&2
    exit 1
fi

mkdir -p "$(dirname "$output_dir")"
cp -R "$source_dir" "$output_dir"
mkdir -p "$output_dir/lib"

tmp_dir="$(mktemp -d)"
deps_file="$tmp_dir/deps.txt"
visited_file="$tmp_dir/visited.txt"
: > "$deps_file"
: > "$visited_file"

list_deps() {
    target="$1"
    otool -L "$target" | tail -n +2 | awk '{print $1}'
}

resolve_dep_path() {
    dep="$1"
    target="$2"
    target_dir="$(dirname "$target")"
    case "$dep" in
        @loader_path/*)
            printf '%s\n' "$target_dir/${dep#@loader_path/}"
            ;;
        @executable_path/*)
            if [ -n "$output_dir" ]; then
                printf '%s\n' "$output_dir/bin/${dep#@executable_path/}"
            else
                printf '%s\n' "$dep"
            fi
            ;;
        @rpath/*)
            printf '%s\n' "$target_dir/$(basename "$dep")"
            ;;
        *)
            printf '%s\n' "$dep"
            ;;
    esac
}

is_macho_file() {
    target="$1"
    file "$target" 2>/dev/null | grep -q 'Mach-O'
}

is_static_archive_ref() {
    dep="$1"
    case "$dep" in
        *.a|*.a\(*\))
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

should_bundle() {
    dep="$1"
    if is_static_archive_ref "$dep"; then
        return 1
    fi
    case "$dep" in
        /System/*|/usr/lib/*)
            return 1
            ;;
        @executable_path/*|@loader_path/*|@rpath/*)
            return 0
            ;;
        /*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

queue_binary_tree() {
    find "$1" -type f \( -perm -111 -o -name "*.dylib" -o -name "*.so" \)
}

queue_dependency() {
    dep="$1"
    resolved_dep="$2"
    if is_static_archive_ref "$dep"; then
        return
    fi
    if [ ! -f "$resolved_dep" ]; then
        printf 'Warning: dependency not found, skipping: %s\n' "$resolved_dep" >&2
        return
    fi
    if grep -Fxq "$resolved_dep" "$visited_file"; then
        return
    fi
    printf '%s\n' "$resolved_dep" >> "$visited_file"
    printf '%s\n' "$resolved_dep" >> "$deps_file"
}

for target in $(queue_binary_tree "$output_dir"); do
    if ! is_macho_file "$target"; then
        continue
    fi
    while IFS= read -r dep; do
        if should_bundle "$dep"; then
            queue_dependency "$dep" "$(resolve_dep_path "$dep" "$target")"
        fi
    done <<EOF
$(list_deps "$target")
EOF
done

while [ -s "$deps_file" ]; do
    current_dep="$(head -n 1 "$deps_file")"
    tail -n +2 "$deps_file" > "$deps_file.next"
    mv "$deps_file.next" "$deps_file"

    dep_name="$(basename "$current_dep")"
    bundled_dep="$output_dir/lib/$dep_name"

    if [ ! -f "$bundled_dep" ]; then
        cp "$current_dep" "$bundled_dep"
        chmod u+w "$bundled_dep"
        install_name_tool -id "@loader_path/$dep_name" "$bundled_dep"
    fi

    while IFS= read -r nested_dep; do
        if should_bundle "$nested_dep"; then
            queue_dependency "$nested_dep" "$(resolve_dep_path "$nested_dep" "$current_dep")"
        fi
    done <<EOF
$(list_deps "$current_dep")
EOF
done

rewrite_target() {
    target="$1"
    if ! is_macho_file "$target"; then
        return
    fi
    chmod u+w "$target" 2>/dev/null || true
    while IFS= read -r dep; do
        if should_bundle "$dep"; then
            dep_name="$(basename "$dep")"
            case "$target" in
                "$output_dir/bin/"*)
                    new_ref="@executable_path/../lib/$dep_name"
                    ;;
                *)
                    new_ref="@loader_path/../lib/$dep_name"
                    ;;
            esac
            install_name_tool -change "$dep" "$new_ref" "$target"
        fi
    done <<EOF
$(list_deps "$target")
EOF
}

for target in $(queue_binary_tree "$output_dir"); do
    rewrite_target "$target"
done

rm -rf "$tmp_dir"

if [ ! -x "$output_dir/bin/php" ]; then
    printf 'Packaged runtime is missing bin/php: %s\n' "$output_dir/bin/php" >&2
    exit 1
fi

if [ ! -x "$output_dir/bin/php-cgi" ]; then
    printf 'Packaged runtime is missing bin/php-cgi: %s\n' "$output_dir/bin/php-cgi" >&2
    exit 1
fi

printf 'Packaged PHP runtime:\n'
printf '  source: %s\n' "$source_dir"
printf '  output: %s\n' "$output_dir"
printf '  verified: %s and %s\n' "$output_dir/bin/php" "$output_dir/bin/php-cgi"
