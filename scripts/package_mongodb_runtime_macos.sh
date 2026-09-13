#!/bin/sh

set -eu

usage() {
    cat <<'EOF'
Usage:
  scripts/package_mongodb_runtime_macos.sh --source <path> [options]

Package a staged MongoDB Homebrew runtime into a self-contained macOS runtime.

Options:
  --source <path>       Source runtime directory.
  --output <path>       Output directory. Default: dist/runtime/database/<source-basename>
  --overwrite           Remove existing output directory first
  --help                Show this help

Examples:
  scripts/package_mongodb_runtime_macos.sh --source prebuild/database/mongodb-7.0.26 --overwrite
  scripts/package_mongodb_runtime_macos.sh --source prebuild/database/mongodb-8.0.4 --overwrite
EOF
}

abspath() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s\n' "$(pwd)/$1" ;;
    esac
}

is_macho() {
    file "$1" 2>/dev/null | grep -Eq 'Mach-O.*(executable|dynamically linked shared library|bundle)'
}

is_system_library() {
    case "$1" in
        /System/*|/usr/lib/*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_external_library() {
    case "$1" in
        /opt/homebrew/*|/usr/local/*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

copy_file_once() {
    src="$1"
    dest_dir="$2"

    [ -f "$src" ] || return 0

    mkdir -p "$dest_dir"

    base="$(basename "$src")"
    dest="$dest_dir/$base"

    if [ ! -f "$dest" ]; then
        cp -p "$src" "$dest"
        chmod u+w "$dest" 2>/dev/null || true
    fi
}

binary_uses_library() {
    target="$1"
    library="$2"

    otool -L "$target" 2>/dev/null | awk 'NR > 1 {print $1}' | grep -qx "$library"
}

resolve_rpath_dependency() {
    target="$1"
    dep="$2"
    dep_name="${dep#@rpath/}"

    otool -l "$target" 2>/dev/null | awk '$1 == "path" {print $2}' | while IFS= read -r rpath; do
        [ -n "$rpath" ] || continue

        case "$rpath" in
            @loader_path*)
                loader_dir="$(dirname "$target")"
                candidate="$loader_dir/${rpath#@loader_path/}/$dep_name"
                ;;
            @executable_path*)
                executable_dir="$(dirname "$target")"
                candidate="$executable_dir/${rpath#@executable_path/}/$dep_name"
                ;;
            *)
                candidate="$rpath/$dep_name"
                ;;
        esac

        if [ -f "$candidate" ]; then
            abspath "$candidate"
            exit 0
        fi
    done
}

rewrite_dependency_for_target() {
    target="$1"
    old_path="$2"
    new_path="$3"

    binary_uses_library "$target" "$old_path" || return 0

    install_name_tool -change "$old_path" "$new_path" "$target" 2>/dev/null || true
}

collect_dependencies_for_target() {
    target="$1"

    otool -L "$target" 2>/dev/null | awk 'NR > 1 {print $1}' | while IFS= read -r dep; do
        [ -n "$dep" ] || continue
        is_system_library "$dep" && continue

        case "$dep" in
            @loader_path/*|@executable_path/*)
                continue
                ;;
            @rpath/*)
                resolved="$(resolve_rpath_dependency "$target" "$dep" || true)"
                if [ -n "$resolved" ] && is_external_library "$resolved"; then
                    printf '%s|%s\n' "$dep" "$resolved"
                fi
                ;;
            *)
                if is_external_library "$dep"; then
                    printf '%s|%s\n' "$dep" "$dep"
                fi
                ;;
        esac
    done
}

fix_binary_or_library() {
    target="$1"

    chmod u+w "$target" 2>/dev/null || true

    case "$target" in
        *.dylib)
            install_name_tool -id "@loader_path/$(basename "$target")" "$target" 2>/dev/null || true
            ;;
    esac

    collect_dependencies_for_target "$target" | while IFS='|' read -r original resolved; do
        [ -n "$original" ] || continue
        [ -n "$resolved" ] || continue

        copy_file_once "$resolved" "$output/lib"

        dep_base="$(basename "$resolved")"

        case "$target" in
            "$output/bin"/*)
                rewrite_dependency_for_target "$target" "$original" "@loader_path/../lib/$dep_base"
                ;;
            "$output/lib"/*)
                rewrite_dependency_for_target "$target" "$original" "@loader_path/$dep_base"
                ;;
            *)
                rewrite_dependency_for_target "$target" "$original" "@loader_path/$dep_base"
                ;;
        esac
    done
}

fix_all_macho_files_once() {
    find "$output/bin" "$output/lib" -type f 2>/dev/null | while IFS= read -r file; do
        if is_macho "$file"; then
            fix_binary_or_library "$file"
        fi
    done
}

verify_tool() {
    tool="$1"

    if [ ! -x "$output/bin/$tool" ]; then
        printf '  %s: not found\n' "$tool"
        return 0
    fi

    if "$output/bin/$tool" --version >/dev/null 2>&1; then
        printf '  %s: ok\n' "$tool"
    else
        printf '  %s: warning, --version failed\n' "$tool" >&2
        printf '    check: otool -L %s/bin/%s\n' "$output" "$tool" >&2
    fi
}

verify_no_homebrew_links() {
    find "$output/bin" "$output/lib" -type f 2>/dev/null | while IFS= read -r file; do
        if is_macho "$file"; then
            if otool -L "$file" 2>/dev/null | grep -E '/opt/homebrew/|/usr/local/' >/dev/null 2>&1; then
                printf 'Unresolved Homebrew dependency in: %s\n' "$file" >&2
                otool -L "$file" >&2
            fi
        fi
    done
}

source=""
output=""
overwrite="0"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --source)
            source="$(abspath "${2:-}")"
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

if [ -z "$source" ]; then
    printf 'Missing required argument: --source\n\n' >&2
    usage >&2
    exit 1
fi

if [ ! -d "$source" ]; then
    printf 'Source directory not found: %s\n' "$source" >&2
    exit 1
fi

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

if [ -z "$output" ]; then
    output="$repo_root/dist/runtime/database/$(basename "$source")"
fi

if [ -e "$output" ] || [ -L "$output" ]; then
    if [ "$overwrite" = "1" ]; then
        printf 'Removing existing output directory: %s\n' "$output"
        rm -rf "$output"
    else
        printf 'Output directory already exists: %s\n' "$output" >&2
        printf 'Use --overwrite to replace it.\n' >&2
        exit 1
    fi
fi

mkdir -p "$(dirname "$output")"

printf 'Copying MongoDB runtime:\n'
printf '  from: %s\n' "$source"
printf '  to:   %s\n' "$output"

cp -R "$source" "$output"

mkdir -p "$output/bin"
mkdir -p "$output/lib"
mkdir -p "$output/conf"
mkdir -p "$output/data/db"
mkdir -p "$output/logs"
mkdir -p "$output/tmp"

if [ ! -x "$output/bin/mongod" ]; then
    printf 'Expected MongoDB server binary missing: %s/bin/mongod\n' "$output" >&2
    exit 1
fi

if [ ! -f "$output/conf/mongod.conf" ]; then
    cat > "$output/conf/mongod.conf" <<'EOF'
storage:
  dbPath: data/db
systemLog:
  destination: file
  path: logs/mongod.log
  logAppend: true
net:
  bindIp: 127.0.0.1
  port: 27017
processManagement:
  fork: false
EOF
fi

printf '\nCollecting and rewriting bundled dylib dependencies...\n'

previous_count="-1"
current_count="$(find "$output/lib" -type f 2>/dev/null | wc -l | tr -d ' ')"

while [ "$current_count" != "$previous_count" ]; do
    previous_count="$current_count"
    fix_all_macho_files_once
    current_count="$(find "$output/lib" -type f 2>/dev/null | wc -l | tr -d ' ')"
done

fix_all_macho_files_once

if command -v xattr >/dev/null 2>&1; then
    xattr -dr com.apple.quarantine "$output" 2>/dev/null || true
fi

cat > "$output/run_mongod.sh" <<'EOF'
#!/bin/sh
set -eu

runtime_root="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
config="$runtime_root/conf/mongod.conf"

cd "$runtime_root"

exec "$runtime_root/bin/mongod" --config "$config"
EOF

chmod +x "$output/run_mongod.sh"

cat > "$output/runtime.json" <<EOF
{
  "engine": "mongodb",
  "serverBinary": "bin/mongod",
  "routerBinary": "bin/mongos",
  "clientBinary": "bin/mongosh",
  "dumpBinary": "bin/mongodump",
  "restoreBinary": "bin/mongorestore",
  "importBinary": "bin/mongoimport",
  "exportBinary": "bin/mongoexport",
  "bsonDumpBinary": "bin/bsondump",
  "config": "conf/mongod.conf",
  "dataDir": "data/db",
  "logDir": "logs",
  "runScript": "run_mongod.sh"
}
EOF

printf '\nVerifying packaged MongoDB tools...\n'

verify_tool "mongod"
verify_tool "mongosh"
verify_tool "mongodump"
verify_tool "mongorestore"
verify_tool "mongoimport"
verify_tool "mongoexport"
verify_tool "bsondump"

printf '\nChecking for unresolved Homebrew library links...\n'
verify_no_homebrew_links

printf '\nDone.\n'
printf 'Packaged runtime:\n'
printf '  %s\n' "$output"
printf 'Server binary:\n'
printf '  %s\n' "$output/bin/mongod"
printf 'Run script:\n'
printf '  %s\n' "$output/run_mongod.sh"