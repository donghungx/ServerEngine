#!/bin/sh

set -eu

usage() {
    cat <<'EOF'
Usage:
  scripts/package_postgresql_runtime_macos.sh --source <path> [options]

Package a staged PostgreSQL Homebrew runtime into a self-contained macOS runtime.

Options:
  --source <path>       Source runtime directory.
  --output <path>       Output directory. Default: dist/runtime/database/<source-basename>
  --overwrite           Remove existing output directory first
  --help                Show this help

Examples:
  scripts/package_postgresql_runtime_macos.sh --source prebuild/database/postgresql-17.6 --overwrite
EOF
}

abspath() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s\n' "$(pwd)/$1" ;;
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

is_homebrew_library() {
    case "$1" in
        /opt/homebrew/*|/usr/local/*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

find_homebrew_icu_data() {
    for prefix in \
        /opt/homebrew/opt/icu4c@78 \
        /opt/homebrew/opt/icu4c \
        /usr/local/opt/icu4c@78 \
        /usr/local/opt/icu4c
    do
        if [ -d "$prefix/lib" ]; then
            for file in "$prefix"/lib/libicudata*.dylib; do
                [ -f "$file" ] || continue
                printf '%s\n' "$file"
                return 0
            done
        fi
    done

    if command -v brew >/dev/null 2>&1; then
        for formula in icu4c@78 icu4c; do
            prefix="$(brew --prefix "$formula" 2>/dev/null || true)"
            if [ -n "$prefix" ] && [ -d "$prefix/lib" ]; then
                for file in "$prefix"/lib/libicudata*.dylib; do
                    [ -f "$file" ] || continue
                    printf '%s\n' "$file"
                    return 0
                done
            fi
        done
    fi

    return 1
}

ensure_icu_data_library() {
    if [ -f "$output/lib/libicudata.78.dylib" ]; then
        return 0
    fi

    needs_icu_data="$(find "$output/lib" -type f 2>/dev/null | while IFS= read -r file; do
        [ -n "$file" ] || continue
        file "$file" 2>/dev/null | grep -Eq 'Mach-O.*(dynamically linked shared library|bundle|executable)' || continue
        if otool -L "$file" 2>/dev/null | awk 'NR > 1 {print $1}' | grep -Eq '@loader_path/libicudata\.[0-9]+\.dylib'; then
            printf '1\n'
            break
        fi
    done || true)"

    if [ "$needs_icu_data" != "1" ]; then
        return 0
    fi

    icu_data_source="$(find_homebrew_icu_data || true)"
    if [ -z "$icu_data_source" ] || [ ! -f "$icu_data_source" ]; then
        printf 'Warning: libicudata runtime missing and no Homebrew ICU data library was found.\n' >&2
        return 0
    fi

    printf 'Restoring ICU data library: %s\n' "$icu_data_source"
    cp -p "$icu_data_source" "$output/lib/"
    chmod u+w "$output/lib/$(basename "$icu_data_source")" 2>/dev/null || true

    icu_data_base="$(basename "$icu_data_source")"
    if [ "$icu_data_base" != "libicudata.78.dylib" ] && [ ! -e "$output/lib/libicudata.78.dylib" ]; then
        ln -s "$icu_data_base" "$output/lib/libicudata.78.dylib"
    fi
    if [ "$icu_data_base" != "libicudata.dylib" ] && [ ! -e "$output/lib/libicudata.dylib" ]; then
        ln -s "$icu_data_base" "$output/lib/libicudata.dylib"
    fi
}

collect_direct_dependencies() {
    target="$1"

    otool -L "$target" 2>/dev/null | awk 'NR > 1 {print $1}' | while IFS= read -r dep; do
        [ -n "$dep" ] || continue
        is_system_library "$dep" && continue

        case "$dep" in
            @rpath/*|@loader_path/*|@executable_path/*)
                continue
                ;;
        esac

        is_homebrew_library "$dep" || continue
        printf '%s\n' "$dep"
    done
}

rewrite_binary_dependency() {
    target="$1"
    old_path="$2"
    new_name="$3"

    install_name_tool -change "$old_path" "@loader_path/../lib/$new_name" "$target" 2>/dev/null || true
    install_name_tool -change "$old_path" "@loader_path/$new_name" "$target" 2>/dev/null || true
}

fix_binary_or_library() {
    target="$1"

    chmod u+w "$target" 2>/dev/null || true

    case "$target" in
        *.dylib)
            install_name_tool -id "@loader_path/$(basename "$target")" "$target" 2>/dev/null || true
            ;;
    esac

    collect_direct_dependencies "$target" | while IFS= read -r dep; do
        [ -n "$dep" ] || continue
        copy_file_once "$dep" "$output/lib"
        rewrite_binary_dependency "$target" "$dep" "$(basename "$dep")"
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

printf 'Copying PostgreSQL runtime:\n'
printf '  from: %s\n' "$source"
printf '  to:   %s\n' "$output"

cp -R "$source" "$output"

mkdir -p "$output/bin"
mkdir -p "$output/lib"
mkdir -p "$output/conf"
mkdir -p "$output/data/main"
mkdir -p "$output/logs"
mkdir -p "$output/tmp"

if [ ! -x "$output/bin/postgres" ]; then
    printf 'Expected PostgreSQL server binary missing: %s/bin/postgres\n' "$output" >&2
    exit 1
fi

if [ ! -x "$output/bin/initdb" ]; then
    printf 'Expected PostgreSQL initdb binary missing: %s/bin/initdb\n' "$output" >&2
    exit 1
fi

if [ ! -x "$output/bin/psql" ]; then
    printf 'Expected PostgreSQL client binary missing: %s/bin/psql\n' "$output" >&2
    exit 1
fi

printf '\nCollecting direct Homebrew dylib dependencies...\n'

find "$output/bin" -type f | while IFS= read -r file; do
    if file "$file" 2>/dev/null | grep -Eq 'Mach-O.*(executable|dynamically linked shared library)'; then
        fix_binary_or_library "$file"
    fi
done

if [ -d "$output/lib/postgresql" ]; then
    find "$output/lib/postgresql" -type f | while IFS= read -r file; do
        if file "$file" 2>/dev/null | grep -Eq 'Mach-O.*(bundle|dynamically linked shared library|executable)'; then
            fix_binary_or_library "$file"
        fi
    done
fi

changed="1"
while [ "$changed" = "1" ]; do
    changed="0"
    before="$(find "$output/lib" -type f 2>/dev/null | wc -l | tr -d ' ')"

    find "$output/lib" -type f | while IFS= read -r file; do
        if file "$file" 2>/dev/null | grep -Eq 'Mach-O.*(dynamically linked shared library|bundle|executable)'; then
            fix_binary_or_library "$file"
        fi
    done

    after="$(find "$output/lib" -type f 2>/dev/null | wc -l | tr -d ' ')"

    if [ "$after" != "$before" ]; then
        changed="1"
    fi
done

ensure_icu_data_library

printf '\nRewriting copied library dependency paths...\n'

find "$output/lib" -type f | while IFS= read -r file; do
    if file "$file" 2>/dev/null | grep -Eq 'Mach-O.*(dynamically linked shared library|bundle|executable)'; then
        chmod u+w "$file" 2>/dev/null || true

        case "$file" in
            *.dylib)
                install_name_tool -id "@loader_path/$(basename "$file")" "$file" 2>/dev/null || true
                ;;
        esac

        otool -L "$file" 2>/dev/null | awk 'NR > 1 {print $1}' | while IFS= read -r dep; do
            [ -n "$dep" ] || continue
            is_system_library "$dep" && continue

            case "$dep" in
                @loader_path/*|@rpath/*|@executable_path/*)
                    continue
                    ;;
            esac

            dep_base="$(basename "$dep")"

            if [ -f "$output/lib/$dep_base" ]; then
                install_name_tool -change "$dep" "@loader_path/$dep_base" "$file" 2>/dev/null || true
            fi
        done
    fi
done

printf '\nRewriting binary dependency paths...\n'

find "$output/bin" -type f | while IFS= read -r file; do
    if file "$file" 2>/dev/null | grep -Eq 'Mach-O.*(executable|dynamically linked shared library)'; then
        chmod u+w "$file" 2>/dev/null || true

        otool -L "$file" 2>/dev/null | awk 'NR > 1 {print $1}' | while IFS= read -r dep; do
            [ -n "$dep" ] || continue
            is_system_library "$dep" && continue

            case "$dep" in
                @loader_path/*|@rpath/*|@executable_path/*)
                    continue
                    ;;
            esac

            dep_base="$(basename "$dep")"

            if [ -f "$output/lib/$dep_base" ]; then
                install_name_tool -change "$dep" "@loader_path/../lib/$dep_base" "$file" 2>/dev/null || true
            fi
        done
    fi
done

cat > "$output/run_postgres.sh" <<'EOF'
#!/bin/sh
set -eu

runtime_root="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
data_dir="$runtime_root/data/main"
log_file="$runtime_root/logs/postgresql.log"
share_dir="$runtime_root/share/postgresql"
export TZ=UTC

if [ ! -f "$share_dir/postgres.bki" ]; then
    found_share_bki="$(find "$runtime_root/share" -maxdepth 2 -name postgres.bki -print 2>/dev/null | head -n 1 || true)"
    share_dir="$(dirname "$found_share_bki")"
fi

mkdir -p "$runtime_root/data"
mkdir -p "$runtime_root/logs"
mkdir -p "$runtime_root/tmp"

if [ ! -f "$data_dir/PG_VERSION" ]; then
    "$runtime_root/bin/initdb" -D "$data_dir" -L "$share_dir" -U postgres
fi

exec "$runtime_root/bin/postgres" \
    -D "$data_dir" \
    -h 127.0.0.1 \
    -p 5432 \
    -k "$runtime_root/tmp"
EOF

chmod +x "$output/run_postgres.sh"

cat > "$output/init_postgres.sh" <<'EOF'
#!/bin/sh
set -eu

runtime_root="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
data_dir="$runtime_root/data/main"
share_dir="$runtime_root/share/postgresql"
export TZ=UTC

if [ ! -f "$share_dir/postgres.bki" ]; then
    found_share_bki="$(find "$runtime_root/share" -maxdepth 2 -name postgres.bki -print 2>/dev/null | head -n 1 || true)"
    share_dir="$(dirname "$found_share_bki")"
fi

mkdir -p "$runtime_root/data"
mkdir -p "$runtime_root/logs"
mkdir -p "$runtime_root/tmp"

if [ -f "$data_dir/PG_VERSION" ]; then
    printf 'PostgreSQL data directory already initialized:\n'
    printf '  %s\n' "$data_dir"
    exit 0
fi

"$runtime_root/bin/initdb" -D "$data_dir" -L "$share_dir" -U postgres
EOF

chmod +x "$output/init_postgres.sh"

cat > "$output/runtime.json" <<EOF
{
  "engine": "postgresql",
  "serverBinary": "bin/postgres",
  "initBinary": "bin/initdb",
  "clientBinary": "bin/psql",
  "controlBinary": "bin/pg_ctl",
  "dataDir": "data/main",
  "logFile": "logs/postgresql.log",
  "socketDir": "tmp",
  "defaultHost": "127.0.0.1",
  "defaultPort": 5432,
  "runScript": "run_postgres.sh",
  "initScript": "init_postgres.sh"
}
EOF

printf '\nVerifying packaged PostgreSQL binary...\n'

if "$output/bin/postgres" --version >/dev/null 2>&1; then
    "$output/bin/postgres" --version
else
    printf 'Warning: postgres --version failed. Check missing dylibs with:\n' >&2
    printf '  otool -L %s/bin/postgres\n' "$output" >&2
fi

printf '\nDone.\n'
printf 'Packaged runtime:\n'
printf '  %s\n' "$output"
printf 'Server binary:\n'
printf '  %s\n' "$output/bin/postgres"
printf 'Run script:\n'
printf '  %s\n' "$output/run_postgres.sh"
