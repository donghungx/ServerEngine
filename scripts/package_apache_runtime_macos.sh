#!/bin/sh

set -eu

usage() {
    cat <<'EOF'
Usage:
  scripts/package_apache_runtime_macos.sh --source prebuild/server/apache-2.4.62 [options]

Convert a macOS Apache runtime into a self-contained distributable bundle by:
  - copying the runtime to an output directory
  - copying non-system dylib dependencies into lib/
  - rewriting load paths with install_name_tool

Options:
  --source <path>     Source Apache runtime directory. Required.
  --output <path>     Output directory. Default: ~/Library/Application Support/Server Engine/bin/server/<runtime-name>
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

if [ -z "$output_dir" ]; then
    repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
    output_dir="$HOME/Library/Application Support/Server Engine/bin/server/$(basename "$source_dir")"
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

list_rpaths() {
    target="$1"
    otool -l "$target" 2>/dev/null | awk '
        $1 == "cmd" && $2 == "LC_RPATH" { in_rpath=1; next }
        in_rpath && $1 == "path" { print $2; in_rpath=0 }
    '
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

should_bundle_path() {
    dep="$1"
    if is_static_archive_ref "$dep"; then
        return 1
    fi
    case "$dep" in
        /System/*|/usr/lib/*)
            return 1
            ;;
        /*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

resolve_special_path() {
    base_dir="$1"
    path_expr="$2"
    output_bin="$output_dir/bin"

    case "$path_expr" in
        @loader_path/*)
            printf '%s/%s\n' "$base_dir" "${path_expr#@loader_path/}"
            ;;
        @executable_path/*)
            printf '%s/%s\n' "$output_bin" "${path_expr#@executable_path/}"
            ;;
        *)
            printf '%s\n' "$path_expr"
            ;;
    esac
}

resolve_dep_path() {
    target="$1"
    dep="$2"
    target_dir="$(dirname "$target")"

    case "$dep" in
        /System/*|/usr/lib/*)
            return 1
            ;;
        /*)
            [ -f "$dep" ] && printf '%s\n' "$dep"
            return 0
            ;;
        @loader_path/*|@executable_path/*)
            candidate="$(resolve_special_path "$target_dir" "$dep")"
            if [ -f "$candidate" ]; then
                printf '%s\n' "$candidate"
                return 0
            fi
            dep_name="$(basename "$dep")"
            fallback="$output_dir/lib/$dep_name"
            if [ -f "$fallback" ]; then
                printf '%s\n' "$fallback"
                return 0
            fi
            return 0
            ;;
        @rpath/*)
            dep_suffix="${dep#@rpath/}"
            for raw_rpath in $(list_rpaths "$target"); do
                resolved_rpath="$(resolve_special_path "$target_dir" "$raw_rpath")"
                candidate="$resolved_rpath/$dep_suffix"
                if [ -f "$candidate" ]; then
                    printf '%s\n' "$candidate"
                    return 0
                fi
            done
            for fallback in "$target_dir" "$output_dir/lib" "$output_dir/bin"; do
                candidate="$fallback/$dep_suffix"
                if [ -f "$candidate" ]; then
                    printf '%s\n' "$candidate"
                    return 0
                fi
            done
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
    if is_static_archive_ref "$dep"; then
        return
    fi
    if [ ! -f "$dep" ]; then
        printf 'Warning: dependency not found, skipping: %s\n' "$dep" >&2
        return
    fi
    if grep -Fxq "$dep" "$visited_file"; then
        return
    fi
    printf '%s\n' "$dep" >> "$visited_file"
    printf '%s\n' "$dep" >> "$deps_file"
}

for target in $(queue_binary_tree "$output_dir"); do
    if ! is_macho_file "$target"; then
        continue
    fi
    while IFS= read -r dep; do
        resolved_dep="$(resolve_dep_path "$target" "$dep" || true)"
        if [ -n "$resolved_dep" ] && should_bundle_path "$resolved_dep"; then
            queue_dependency "$resolved_dep"
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
        resolved_nested_dep="$(resolve_dep_path "$current_dep" "$nested_dep" || true)"
        if [ -n "$resolved_nested_dep" ] && should_bundle_path "$resolved_nested_dep"; then
            queue_dependency "$resolved_nested_dep"
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
        resolved_dep="$(resolve_dep_path "$target" "$dep" || true)"
        if [ -n "$resolved_dep" ] && should_bundle_path "$resolved_dep"; then
            dep_name="$(basename "$resolved_dep")"
            case "$target" in
                "$output_dir/bin/"*)
                    new_ref="@executable_path/../lib/$dep_name"
                    ;;
                *)
                    target_dir="$(dirname "$target")"
                    rel_to_lib="$(python3 - "$target_dir" "$output_dir/lib" <<'PY'
import os
import sys

target_dir = sys.argv[1]
lib_dir = sys.argv[2]
print(os.path.relpath(lib_dir, target_dir))
PY
)"
                    case "$rel_to_lib" in
                        .)
                            new_ref="@loader_path/$dep_name"
                            ;;
                        *)
                            new_ref="@loader_path/$rel_to_lib/$dep_name"
                            ;;
                    esac
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

printf 'Packaged Apache runtime:\n'
printf '  source: %s\n' "$source_dir"
printf '  output: %s\n' "$output_dir"
