#!/bin/sh

set -eu

usage() {
    cat <<'EOF'
Usage:
  scripts/install_php_runtime.sh
  scripts/install_php_runtime.sh --version 8.5.0 [options]

Build an official PHP source release directly into this repo's prebuild layout:
  prebuild/php/php<version>

The built and packaged runtime is shared by both web-server modes in the app:
  - Apache uses the bundled PHP runtime
  - Nginx starts per-version FastCGI backends from bin/php-cgi

Options:
  --version <version>        PHP version to build. Required.
  --prefix <path>            Install directory. Default: prebuild/php/php<version>
  --jobs <n>                 Parallel make jobs. Default: detected CPU count or 4
  --archive-url <url>        Override official download URL
  --source-dir <path>        Reuse an already extracted PHP source directory
  --work-dir <path>          Build workspace. Default: .build/php-src
  --force-download           Redownload archive even if already cached
  --overwrite                Remove an existing target directory before install
  --skip-package             Skip the macOS self-contained packaging step
  --package-output <path>    Override packaged output directory
  --configure-flags "<...>"  Extra configure flags appended at the end
  --minimal                  Build a smaller runtime with fewer bundled features
  --extensions "<list>"      Comma-separated PECL extensions to bundle.
                             Supported: redis,memcached,apcu,imagick,xdebug,intl
                             Example: --extensions "memcached,redis,intl"
  --skip-extension-check     Do not fail when selected bundled extensions are missing
  --force-legacy-intl        On PHP 5.x/7.x, allow selecting intl anyway
  --help                     Show this help

Examples:
  scripts/install_php_runtime.sh
  scripts/install_php_runtime.sh --version 8.5.0
  scripts/install_php_runtime.sh --version 8.4.8 --jobs 8
  scripts/install_php_runtime.sh --version 8.5.0 --configure-flags "--with-pear --enable-pcntl"

Notes:
  - This builds from official php.net source tarballs.
  - You still need the native build dependencies installed on macOS.
  - By default this script now tries to build a "max available" dev runtime from
    detected Homebrew libraries.
  - On macOS, the script also packages the runtime into a self-contained bundle
    unless --skip-package is used.
EOF
}

# Bundled extension controls (can be overridden by CLI flags).
# Use "all" for default set.
# Example:
#   PHP_BUNDLED_EXTENSIONS="memcached,redis,intl" scripts/install_php_runtime.sh --version 7.4.33
PHP_BUNDLED_EXTENSIONS="${PHP_BUNDLED_EXTENSIONS:-all}"
PHP_SKIP_EXTENSION_CHECK="${PHP_SKIP_EXTENSION_CHECK:-0}"
PHP_FORCE_LEGACY_INTL="${PHP_FORCE_LEGACY_INTL:-0}"
intl_requires_cxx17=0
openssl_requires_php80_patch=0

abspath() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s\n' "$(pwd)/$1" ;;
    esac
}

detect_jobs() {
    if command -v sysctl >/dev/null 2>&1; then
        sysctl -n hw.ncpu 2>/dev/null || printf '4\n'
    elif command -v getconf >/dev/null 2>&1; then
        getconf _NPROCESSORS_ONLN 2>/dev/null || printf '4\n'
    else
        printf '4\n'
    fi
}

brew_prefix_for() {
    formula="$1"
    if command -v brew >/dev/null 2>&1; then
        prefix="$(brew --prefix "$formula" 2>/dev/null || true)"
        if [ -n "$prefix" ] && [ -d "$prefix" ]; then
            printf '%s\n' "$prefix"
            return 0
        fi
    fi
    for prefix in "/opt/homebrew/opt/$formula" "/usr/local/opt/$formula"; do
        if [ -d "$prefix" ]; then
            printf '%s\n' "$prefix"
            return 0
        fi
    done
}

ensure_brew_formula_prefix() {
    formula="$1"
    prefix="$(brew_prefix_for "$formula" || true)"
    if [ -z "$prefix" ] && command -v brew >/dev/null 2>&1; then
        printf 'Installing missing Homebrew formula: %s\n' "$formula" >&2
        brew install "$formula" >&2
        prefix="$(brew_prefix_for "$formula" || true)"
    fi
    printf '%s\n' "$prefix"
}

append_flag() {
    current="$1"
    new_value="$2"
    if [ -n "$new_value" ]; then
        printf '%s %s' "$current" "$new_value"
    else
        printf '%s' "$current"
    fi
}

append_pkg_config_path() {
    prefix="$1"
    current="$2"
    candidate="$prefix/lib/pkgconfig"
    if [ -d "$candidate" ]; then
        if [ -n "$current" ]; then
            printf '%s:%s' "$candidate" "$current"
        else
            printf '%s' "$candidate"
        fi
    else
        printf '%s' "$current"
    fi
}

build_pecl_extension() {
    ext_name="$1"
    ext_version="$2"
    php_bin="$prefix/bin/php"
    phpize_bin="$prefix/bin/phpize"
    php_config_bin="$prefix/bin/php-config"
    if [ ! -x "$php_bin" ] || [ ! -x "$phpize_bin" ] || [ ! -x "$php_config_bin" ]; then
        printf 'Skipping %s: php/phpize/php-config not available in runtime.\n' "$ext_name"
        return 1
    fi
    if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1 || ! command -v make >/dev/null 2>&1; then
        printf 'Skipping %s: curl/tar/make are required.\n' "$ext_name"
        return 1
    fi

    ext_build_root="$work_dir/php-ext-build/$version/$ext_name"
    rm -rf "$ext_build_root"
    mkdir -p "$ext_build_root"
    archive="$ext_name-$ext_version.tgz"
    archive_path="$ext_build_root/$archive"
    url="https://pecl.php.net/get/$archive"

    printf 'Building PHP extension %s (%s)\n' "$ext_name" "$ext_version"
    curl -fL "$url" -o "$archive_path"
    tar -xzf "$archive_path" -C "$ext_build_root"

    src_dir="$ext_build_root/$ext_name-$ext_version"
    if [ ! -d "$src_dir" ]; then
        src_dir="$(find "$ext_build_root" -maxdepth 2 -type d -name "$ext_name-*" | head -n 1 || true)"
    fi
    if [ -z "$src_dir" ] || [ ! -d "$src_dir" ]; then
        printf 'Skipping %s: source directory missing after extract.\n' "$ext_name"
        return 1
    fi

    old_cppflags="${CPPFLAGS:-}"
    old_ldflags="${LDFLAGS:-}"
    old_pkg_config_path="${PKG_CONFIG_PATH:-}"
    old_php_autoconf="${PHP_AUTOCONF:-}"
    old_php_autoheader="${PHP_AUTOHEADER:-}"
    old_autom4te="${AUTOM4TE:-}"
    old_php_zlib_dir="${PHP_ZLIB_DIR:-}"

    perl_bin="/usr/bin/perl"
    if [ ! -x "$perl_bin" ]; then
        perl_bin="$(command -v perl || true)"
    fi
    if [ -z "$perl_bin" ] || [ ! -x "$perl_bin" ]; then
        printf 'Skipping %s: perl not found for autotools wrappers.\n' "$ext_name"
        return 1
    fi

    autoconf_bin="$(command -v autoconf || true)"
    autoheader_bin="$(command -v autoheader || true)"
    autom4te_bin="$(command -v autom4te || true)"
    tool_wrap_dir="$ext_build_root/.toolwrap"
    mkdir -p "$tool_wrap_dir"

    if [ -n "$autoconf_bin" ] && [ -f "$autoconf_bin" ]; then
        cat >"$tool_wrap_dir/autoconf" <<EOF
#!/bin/sh
exec "$perl_bin" "$autoconf_bin" "\$@"
EOF
        chmod +x "$tool_wrap_dir/autoconf"
        PHP_AUTOCONF="$tool_wrap_dir/autoconf"
    elif [ -x /usr/bin/autoconf ]; then
        PHP_AUTOCONF="/usr/bin/autoconf"
    fi

    if [ -n "$autoheader_bin" ] && [ -f "$autoheader_bin" ]; then
        cat >"$tool_wrap_dir/autoheader" <<EOF
#!/bin/sh
exec "$perl_bin" "$autoheader_bin" "\$@"
EOF
        chmod +x "$tool_wrap_dir/autoheader"
        PHP_AUTOHEADER="$tool_wrap_dir/autoheader"
    elif [ -x /usr/bin/autoheader ]; then
        PHP_AUTOHEADER="/usr/bin/autoheader"
    fi

    if [ -n "$autom4te_bin" ] && [ -f "$autom4te_bin" ]; then
        cat >"$tool_wrap_dir/autom4te" <<EOF
#!/bin/sh
exec "$perl_bin" "$autom4te_bin" "\$@"
EOF
        chmod +x "$tool_wrap_dir/autom4te"
        AUTOM4TE="$tool_wrap_dir/autom4te"
    fi
    export PHP_AUTOCONF PHP_AUTOHEADER AUTOM4TE

    if [ "$ext_name" = "redis" ]; then
        case "$version" in
            8.5.*)
                redis_common="$src_dir/common.h"
                if [ -f "$redis_common" ]; then
                    perl -0pi -e 's/#include <ext\/standard\/php_smart_string\.h>/#include <Zend\/zend_smart_string.h>/' "$redis_common"
                fi
                ;;
        esac
    fi

    if [ "$ext_name" = "memcached" ]; then
        case "$version" in
            8.5.*)
                memcached_private="$src_dir/php_memcached_private.h"
                if [ -f "$memcached_private" ]; then
                    perl -0pi -e 's/#include <ext\/standard\/php_smart_string\.h>/#include <Zend\/zend_smart_string.h>/' "$memcached_private"
                fi
                memcached_source="$src_dir/php_memcached.c"
                if [ -f "$memcached_source" ]; then
                    perl -0pi -e 's/\bzend_exception_get_default\(\)/zend_ce_exception/g' "$memcached_source"
                fi
                ;;
        esac
        libmemcached_prefix=""
        memcached_zlib_prefix=""
        ensure_brew_formula() {
            formula="$1"
            path="$(brew --prefix "$formula" 2>/dev/null || true)"
            if [ -n "$path" ] && [ -d "$path" ]; then
                printf '%s\n' "$path"
                return 0
            fi
            printf 'Installing missing Homebrew formula: %s\n' "$formula" >&2
            if brew install "$formula" >/dev/null 2>&1; then
                path="$(brew --prefix "$formula" 2>/dev/null || true)"
                if [ -n "$path" ] && [ -d "$path" ]; then
                    printf '%s\n' "$path"
                    return 0
                fi
            fi
            return 1
        }
        if command -v brew >/dev/null 2>&1; then
            libmemcached_prefix="$(ensure_brew_formula libmemcached || true)"
            memcached_zlib_prefix="$(ensure_brew_formula zlib || true)"
        fi
        for candidate in "$libmemcached_prefix" "/opt/homebrew/opt/libmemcached" "/usr/local/opt/libmemcached"; do
            if [ -n "$candidate" ] && [ -d "$candidate/include" ] && [ -d "$candidate/lib" ]; then
                libmemcached_prefix="$candidate"
                break
            fi
        done
        for candidate in "$memcached_zlib_prefix" "/opt/homebrew/opt/zlib" "/usr/local/opt/zlib" "/usr"; do
            if [ -n "$candidate" ] && [ -d "$candidate" ] && { [ -f "$candidate/include/zlib.h" ] || [ -f "$candidate/include/zlib/zlib.h" ]; }; then
                memcached_zlib_prefix="$candidate"
                break
            fi
        done
        if [ -z "$memcached_zlib_prefix" ] || [ ! -d "$memcached_zlib_prefix" ]; then
            if command -v xcrun >/dev/null 2>&1; then
                sdk_root="$(xcrun --show-sdk-path 2>/dev/null || true)"
                if [ -n "$sdk_root" ] && [ -d "$sdk_root/usr" ]; then
                    if [ -f "$sdk_root/usr/include/zlib.h" ] || [ -f "$sdk_root/usr/include/zlib/zlib.h" ]; then
                        memcached_zlib_prefix="$sdk_root/usr"
                    fi
                fi
            fi
        fi
        if [ -n "$libmemcached_prefix" ] && [ -d "$libmemcached_prefix" ]; then
            CPPFLAGS="${CPPFLAGS:-} -I$libmemcached_prefix/include"
            LDFLAGS="${LDFLAGS:-} -L$libmemcached_prefix/lib"
            if [ -n "${PKG_CONFIG_PATH:-}" ]; then
                PKG_CONFIG_PATH="$libmemcached_prefix/lib/pkgconfig:$PKG_CONFIG_PATH"
            else
                PKG_CONFIG_PATH="$libmemcached_prefix/lib/pkgconfig"
            fi
            export CPPFLAGS LDFLAGS PKG_CONFIG_PATH
        else
            printf 'Missing libmemcached prefix required for memcached extension build.\n' >&2
            return 1
        fi
        if [ -n "$memcached_zlib_prefix" ] && [ -d "$memcached_zlib_prefix" ]; then
            CPPFLAGS="${CPPFLAGS:-} -I$memcached_zlib_prefix/include"
            LDFLAGS="${LDFLAGS:-} -L$memcached_zlib_prefix/lib"
            PHP_ZLIB_DIR="$memcached_zlib_prefix"
            export CPPFLAGS LDFLAGS PHP_ZLIB_DIR
        else
            printf 'Missing zlib prefix required for memcached extension build.\n' >&2
            return 1
        fi
    fi
    if [ "$ext_name" = "imagick" ]; then
        case "$version" in
            8.4.*|8.5.*)
                imagick_source="$src_dir/imagick.c"
                if [ -f "$imagick_source" ]; then
                    perl -0pi -e 's/#include "ext\/standard\/php_smart_string\.h"/#include "Zend\/zend_smart_string.h"/' "$imagick_source"
                    perl -0pi -e 's/\bphp_strtolower\(/zend_str_tolower(/g' "$imagick_source"
                fi
                ;;
        esac
    fi

    if [ "$ext_name" = "imagick" ] && command -v brew >/dev/null 2>&1; then
        imagemagick_prefix="$(brew --prefix imagemagick 2>/dev/null || true)"
        if [ -z "$imagemagick_prefix" ] || [ ! -d "$imagemagick_prefix" ]; then
            printf 'Installing missing Homebrew formula: imagemagick\n' >&2
            brew install imagemagick >/dev/null 2>&1 || true
            imagemagick_prefix="$(brew --prefix imagemagick 2>/dev/null || true)"
        fi
        if [ -n "$imagemagick_prefix" ] && [ -d "$imagemagick_prefix" ]; then
            CPPFLAGS="${CPPFLAGS:-} -I$imagemagick_prefix/include"
            LDFLAGS="${LDFLAGS:-} -L$imagemagick_prefix/lib"
            if [ -n "${PKG_CONFIG_PATH:-}" ]; then
                PKG_CONFIG_PATH="$imagemagick_prefix/lib/pkgconfig:$PKG_CONFIG_PATH"
            else
                PKG_CONFIG_PATH="$imagemagick_prefix/lib/pkgconfig"
            fi
            export CPPFLAGS LDFLAGS PKG_CONFIG_PATH
        else
            printf 'Missing imagemagick prefix required for imagick extension build.\n' >&2
            return 1
        fi
    fi

    (
        cd "$src_dir"
        "$phpize_bin"
        if [ "$ext_name" = "memcached" ]; then
            libmemcached_cfg_arg="--with-libmemcached-dir=no"
            if [ -n "${libmemcached_prefix:-}" ] && [ -d "$libmemcached_prefix" ]; then
                libmemcached_cfg_arg="--with-libmemcached-dir=$libmemcached_prefix"
            fi
            ./configure --with-php-config="$php_config_bin" "$libmemcached_cfg_arg" --disable-memcached-sasl --with-zlib-dir="$memcached_zlib_prefix"
        else
            ./configure --with-php-config="$php_config_bin"
        fi
        if [ -f Makefile ]; then
            perl -0pi -e 's/\s+\\\s+(-DZEND_COMPILE_DL_EXT=1)/ $1/g' Makefile
        fi
        if [ -f Makefile.objects ]; then
            perl -0pi -e 's/\s+\\\s+(-DZEND_COMPILE_DL_EXT=1)/ $1/g' Makefile.objects
        fi
        make -j"$jobs"
        make install
    )

    CPPFLAGS="$old_cppflags"
    LDFLAGS="$old_ldflags"
    PKG_CONFIG_PATH="$old_pkg_config_path"
    PHP_AUTOCONF="$old_php_autoconf"
    PHP_AUTOHEADER="$old_php_autoheader"
    AUTOM4TE="$old_autom4te"
    PHP_ZLIB_DIR="$old_php_zlib_dir"
    export CPPFLAGS LDFLAGS PKG_CONFIG_PATH PHP_AUTOCONF PHP_AUTOHEADER AUTOM4TE PHP_ZLIB_DIR
    return 0
}

pecl_version_for() {
    ext_name="$1"
    php_version="$2"
    case "$ext_name" in
        redis)
            case "$php_version" in
                5.*|7.*) printf '5.3.7\n' ;;
                8.5.*) printf '6.3.0\n' ;;
                *) printf '6.1.0\n' ;;
            esac
            ;;
        memcached)
            printf '3.2.0\n'
            ;;
        apcu)
            printf '5.1.23\n'
            ;;
        imagick)
            case "$php_version" in
                8.4.*|8.5.*) printf '3.8.0RC2\n' ;;
                *) printf '3.7.0\n' ;;
            esac
            ;;
        xdebug)
            case "$php_version" in
                5.*|7.*) printf '3.1.6\n' ;;
                8.5.*) printf '3.5.1\n' ;;
                8.4.*) printf '3.4.7\n' ;;
                *) printf '3.3.2\n' ;;
            esac
            ;;
        *)
            printf '\n'
            ;;
    esac
}

remove_gd_flags() {
    printf '%s' "$1" | \
        sed 's/ --enable-gd / /g' | \
        sed 's/ --with-jpeg=[^ ]*//g' | \
        sed 's/ --with-freetype=[^ ]*//g' | \
        sed 's/ --with-webp=[^ ]*//g'
}

supports_gd_autobuild() {
    case "$1" in
        5.*|7.*)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

is_legacy_php() {
    case "$1" in
        5.*|7.*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

icu_major_version() {
    prefix="$1"
    major=""
    if [ -n "$prefix" ] && command -v pkg-config >/dev/null 2>&1; then
        if PKG_CONFIG_PATH="$(append_pkg_config_path "$prefix" "${PKG_CONFIG_PATH:-}")" pkg-config --exists icu-i18n 2>/dev/null; then
            major="$(PKG_CONFIG_PATH="$(append_pkg_config_path "$prefix" "${PKG_CONFIG_PATH:-}")" pkg-config --modversion icu-i18n 2>/dev/null | sed -n 's/^\([0-9][0-9]*\).*/\1/p')"
        fi
    fi
    if [ -z "$major" ]; then
        major="$(basename "$prefix" | sed -n 's/^icu4c@\([0-9][0-9]*\)$/\1/p')"
    fi
    printf '%s\n' "$major"
}

requires_external_oniguruma() {
    case "$1" in
        5.*|7.0.*|7.1.*|7.2.*|7.3.*)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

requires_external_libzip() {
    case "$1" in
        5.*|7.0.*|7.1.*|7.2.*|7.3.*)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

supports_sodium() {
    case "$1" in
        5.*|7.0.*|7.1.*)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

remove_openssl_flags() {
    printf '%s' "$1" | \
        sed 's/ --with-openssl=[^ ]*//g' | \
        sed 's/ --with-openssl / /g' | \
        sed '/^--with-openssl$/d'
}

interactive_pick_version() {
    if ! command -v python3 >/dev/null 2>&1; then
        printf 'python3 is required for interactive version selection.\n' >&2
        exit 1
    fi

    python3 <<'PY'
import json
import os
import re
import sys
import termios
import tty
import urllib.request

URL = "https://www.php.net/releases/index.php"

def fetch_versions():
    with urllib.request.urlopen(URL, timeout=20) as response:
        html = response.read().decode("utf-8", "replace")
    matches = re.findall(r"php-([0-9]+\.[0-9]+\.[0-9]+)\.tar\.gz", html)
    versions = sorted(set(matches), key=lambda item: tuple(int(part) for part in item.split(".")), reverse=True)

    filtered = []
    seen_branches = set()
    for version in versions:
        major, minor, patch = (int(part) for part in version.split("."))
        if major < 5:
            continue
        branch = (major, minor)
        if branch in seen_branches:
            continue
        seen_branches.add(branch)
        filtered.append(version)

    return filtered

def write(fd, text):
    normalized = text.replace("\n", "\r\n")
    os.write(fd, normalized.encode("utf-8", "replace"))

def draw(fd, versions, index):
    write(fd, "\033[H\033[2J")
    write(fd, "Select PHP version with Up/Down and press Enter\n\n")
    start = max(0, index - 10)
    end = min(len(versions), start + 20)
    if end - start < 20:
        start = max(0, end - 20)
    for i in range(start, end):
        prefix = "> " if i == index else "  "
        write(fd, f"{prefix}{versions[i]}\n")
    write(fd, "\nEnter = confirm, q = cancel\n")

def read_line(fd):
    chunks = []
    while True:
        ch = os.read(fd, 1)
        if not ch or ch in (b"\n", b"\r"):
            break
        chunks.append(ch)
    return b"".join(chunks).decode("utf-8", "replace").strip().lower()

def read_key(fd):
    ch = os.read(fd, 1)
    if not ch:
        return ""
    if ch != b"\x1b":
        return ch.decode("utf-8", "replace")

    seq = os.read(fd, 1)
    if not seq:
        return "ESC"
    if seq != b"[":
        return "ESC"

    final = os.read(fd, 1)
    if final == b"A":
        return "UP"
    if final == b"B":
        return "DOWN"
    return "ESC"

def main():
    try:
        versions = fetch_versions()
    except Exception as exc:
        raise SystemExit(f"Failed to fetch PHP version list: {exc}")

    if not versions:
        raise SystemExit("No PHP versions were returned by php.net.")

    fd = os.open("/dev/tty", os.O_RDWR)
    old = termios.tcgetattr(fd)
    index = 0
    try:
        write(fd, "\033[?1049h\033[?25l")
        tty.setraw(fd)
        while True:
            draw(fd, versions, index)
            ch = read_key(fd)
            if ch in ("q", "\x03", "ESC"):
                sys.exit(1)
            if ch in ("\r", "\n"):
                write(fd, "\033[2J\033[H")
                write(fd, f"Selected PHP {versions[index]}\n")
                write(fd, "Build and overwrite existing target if needed? [Y/n]: ")
                termios.tcsetattr(fd, termios.TCSADRAIN, old)
                answer = read_line(fd)
                if answer in ("", "y", "yes"):
                    os.write(1, (versions[index] + "\n").encode("utf-8"))
                    return
                sys.exit(1)
            if ch == "UP" and index > 0:
                index -= 1
            elif ch == "DOWN" and index < len(versions) - 1:
                index += 1
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
        write(fd, "\033[?25h\033[?1049l")
        os.close(fd)

main()
PY
}

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
original_argc="$#"
version=""
prefix=""
jobs="$(detect_jobs)"
archive_url=""
source_dir=""
work_dir="$repo_root/.build/php-src"
force_download="0"
overwrite="0"
extra_flags=""
minimal="0"
auto_dependency_flags=""
cppflags="${CPPFLAGS:-}"
ldflags="${LDFLAGS:-}"
pkg_config_path="${PKG_CONFIG_PATH:-}"
skip_package="0"
package_output=""
selected_extensions="$PHP_BUNDLED_EXTENSIONS"
skip_extension_check="$PHP_SKIP_EXTENSION_CHECK"
force_legacy_intl="$PHP_FORCE_LEGACY_INTL"

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
        --jobs)
            jobs="${2:-}"
            shift 2
            ;;
        --archive-url)
            archive_url="${2:-}"
            shift 2
            ;;
        --source-dir)
            source_dir="$(abspath "${2:-}")"
            shift 2
            ;;
        --work-dir)
            work_dir="$(abspath "${2:-}")"
            shift 2
            ;;
        --force-download)
            force_download="1"
            shift
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
        --configure-flags)
            extra_flags="${2:-}"
            shift 2
            ;;
        --minimal)
            minimal="1"
            shift
            ;;
        --extensions)
            selected_extensions="${2:-}"
            shift 2
            ;;
        --skip-extension-check)
            skip_extension_check="1"
            shift
            ;;
        --force-legacy-intl)
            force_legacy_intl="1"
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

if [ "$original_argc" -eq 0 ] && [ -z "$version" ]; then
    selected_version="$(interactive_pick_version || true)"
    if [ -z "$selected_version" ]; then
        printf 'No PHP version selected.\n' >&2
        exit 1
    fi
    version="$selected_version"
    overwrite="1"
fi

if [ -z "$version" ]; then
    printf 'Missing required argument: --version\n\n' >&2
    usage >&2
    exit 1
fi

if [ -z "$prefix" ]; then
    prefix="$repo_root/prebuild/php/php$version"
fi

if [ -z "$archive_url" ]; then
    archive_url="https://www.php.net/distributions/php-$version.tar.gz"
fi

normalize_extensions() {
    input="$1"
    if [ -z "$input" ] || [ "$input" = "all" ]; then
        if is_legacy_php "$version"; then
            printf 'redis memcached apcu imagick xdebug\n'
        else
            printf 'redis memcached apcu imagick xdebug intl\n'
        fi
        return 0
    fi

    old_ifs="$IFS"
    IFS=','
    set -- $input
    IFS="$old_ifs"

    result=""
    for raw in "$@"; do
        ext="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
        case "$ext" in
            redis|memcached|apcu|imagick|xdebug)
                result="$result $ext"
                ;;
            intl)
                if is_legacy_php "$version" && [ "$force_legacy_intl" != "1" ]; then
                    printf 'Skipping intl for legacy PHP %s (set --force-legacy-intl to include it).\n' "$version"
                else
                    result="$result $ext"
                fi
                ;;
            "")
                ;;
            *)
                printf 'Unsupported extension in --extensions: %s\n' "$raw" >&2
                exit 1
                ;;
        esac
    done
    # shellcheck disable=SC2086
    set -- $result
    if [ "$#" -eq 0 ]; then
        printf 'No valid extensions selected.\n' >&2
        exit 1
    fi
    printf '%s\n' "$*"
}

has_selected_extension() {
    wanted="$1"
    for ext in $enabled_extensions; do
        if [ "$ext" = "$wanted" ]; then
            return 0
        fi
    done
    return 1
}

enabled_extensions="$(normalize_extensions "$selected_extensions")"

archive_path="$work_dir/php-$version.tar.gz"
extracted_dir="$work_dir/php-$version"

mkdir -p "$work_dir"
mkdir -p "$repo_root/prebuild/php"

if [ -z "$source_dir" ]; then
    if [ "$force_download" = "1" ] || [ ! -f "$archive_path" ]; then
        printf 'Downloading PHP %s source...\n' "$version"
        curl -fL "$archive_url" -o "$archive_path"
    else
        printf 'Using cached archive: %s\n' "$archive_path"
    fi

    if [ -d "$extracted_dir" ]; then
        rm -rf "$extracted_dir"
    fi

    printf 'Extracting source archive...\n'
    tar -xzf "$archive_path" -C "$work_dir"
    source_dir="$extracted_dir"
else
    if [ ! -d "$source_dir" ]; then
        printf 'Source directory not found: %s\n' "$source_dir" >&2
        exit 1
    fi
fi

if [ -d "$prefix" ]; then
    if [ "$overwrite" = "1" ]; then
        printf 'Removing existing target directory: %s\n' "$prefix"
        rm -rf "$prefix"
    else
        printf 'Target directory already exists: %s\n' "$prefix" >&2
        printf 'Remove it first, pass a different --prefix, or use --overwrite.\n' >&2
        exit 1
    fi
fi

mkdir -p "$prefix/conf"

if command -v brew >/dev/null 2>&1; then
    if ! command -v autoconf >/dev/null 2>&1; then
        printf 'Installing missing Homebrew formula: autoconf\n' >&2
        brew install autoconf >&2
    fi
    if ! command -v autoconf >/dev/null 2>&1; then
        printf 'autoconf is required to build PECL extensions.\n' >&2
        printf 'Install it with: brew install autoconf\n' >&2
        exit 1
    fi
    if ! command -v pkg-config >/dev/null 2>&1; then
        pkg_config_prefix="$(brew --prefix pkg-config 2>/dev/null || brew --prefix pkgconf 2>/dev/null || true)"
        if [ -n "$pkg_config_prefix" ] && [ -x "$pkg_config_prefix/bin/pkg-config" ]; then
            PATH="$pkg_config_prefix/bin:$PATH"
            export PATH
        else
            printf 'Installing missing Homebrew formula: pkg-config\n'
            brew install pkg-config
        fi
    fi
    if ! command -v pkg-config >/dev/null 2>&1; then
        printf 'pkg-config is required to configure PHP (libxml and other dependencies).\n' >&2
        printf 'Install it with: brew install pkg-config\n' >&2
        exit 1
    fi
    iconv_prefix="$(brew_prefix_for libiconv)"
    curl_prefix="$(brew_prefix_for curl)"
    case "$version" in
        8.0.*)
            openssl_prefix="$(brew_prefix_for openssl@1.1)"
            if [ -z "$openssl_prefix" ]; then
                openssl_prefix="$(brew_prefix_for openssl@3)"
            fi
            ;;
        *)
            if is_legacy_php "$version"; then
                openssl_prefix="$(brew_prefix_for openssl@1.1)"
            else
                openssl_prefix="$(brew_prefix_for openssl@3)"
            fi
            ;;
    esac
    case "$version:$openssl_prefix" in
        8.0.*:*openssl@3*|8.0.*:*/openssl/3.*)
            openssl_requires_php80_patch=1
            ;;
    esac
    sqlite_prefix="$(brew_prefix_for sqlite)"
    zlib_prefix="$(brew_prefix_for zlib)"
    libzip_prefix="$(brew_prefix_for libzip)"
    if is_legacy_php "$version"; then
        icu_prefix="$(brew_prefix_for icu4c@74)"
        if [ -z "$icu_prefix" ]; then
            icu_prefix="$(brew_prefix_for icu4c@76)"
        fi
        if [ -z "$icu_prefix" ]; then
            icu_prefix="$(brew_prefix_for icu4c)"
        fi
    else
        icu_prefix="$(brew_prefix_for icu4c)"
    fi
    jpeg_prefix="$(ensure_brew_formula_prefix jpeg-turbo)"
    png_prefix="$(ensure_brew_formula_prefix libpng)"
    freetype_prefix="$(ensure_brew_formula_prefix freetype)"
    webp_prefix="$(ensure_brew_formula_prefix webp)"
    xsl_prefix="$(brew_prefix_for libxslt)"
    gettext_prefix="$(ensure_brew_formula_prefix gettext)"
    libsodium_prefix="$(ensure_brew_formula_prefix libsodium)"
    bz2_prefix="$(brew_prefix_for bzip2)"
    ldap_prefix="$(brew_prefix_for openldap)"
    readline_prefix="$(brew_prefix_for readline)"
    oniguruma_prefix="$(brew_prefix_for oniguruma)"

    [ -n "$iconv_prefix" ] && auto_dependency_flags="$auto_dependency_flags --with-iconv=$iconv_prefix"
    [ -n "$curl_prefix" ] && auto_dependency_flags="$auto_dependency_flags --with-curl=$curl_prefix"
    [ -n "$openssl_prefix" ] && auto_dependency_flags="$auto_dependency_flags --with-openssl=$openssl_prefix"
    [ -n "$sqlite_prefix" ] && auto_dependency_flags="$auto_dependency_flags --with-sqlite3=$sqlite_prefix --with-pdo-sqlite=$sqlite_prefix"
    [ -n "$zlib_prefix" ] && auto_dependency_flags="$auto_dependency_flags --with-zlib=$zlib_prefix"
    [ -n "$libzip_prefix" ] && auto_dependency_flags="$auto_dependency_flags --with-zip"
    if [ -n "$icu_prefix" ]; then
        icu_major="$(icu_major_version "$icu_prefix")"
        if is_legacy_php "$version"; then
            if [ -n "$icu_major" ] && [ "$icu_major" -ge 78 ] 2>/dev/null; then
                printf 'Skipping --enable-intl for PHP %s: ICU %s is too new for ext/intl.\n' "$version" "$icu_major"
                icu_prefix=""
            else
                auto_dependency_flags="$auto_dependency_flags --enable-intl=shared"
            fi
        else
            if [ -n "$icu_major" ] && [ "$icu_major" -ge 78 ] 2>/dev/null; then
                intl_requires_cxx17=1
            fi
            auto_dependency_flags="$auto_dependency_flags --enable-intl"
        fi
    fi
    [ -n "$xsl_prefix" ] && auto_dependency_flags="$auto_dependency_flags --with-xsl=$xsl_prefix"
    [ -n "$gettext_prefix" ] && auto_dependency_flags="$auto_dependency_flags --with-gettext=$gettext_prefix"
    [ -n "$libsodium_prefix" ] && auto_dependency_flags="$auto_dependency_flags --with-sodium=$libsodium_prefix"
    [ -n "$bz2_prefix" ] && auto_dependency_flags="$auto_dependency_flags --with-bz2=$bz2_prefix"
    [ -n "$ldap_prefix" ] && auto_dependency_flags="$auto_dependency_flags --with-ldap=$ldap_prefix"
    [ -n "$readline_prefix" ] && auto_dependency_flags="$auto_dependency_flags --with-readline=$readline_prefix"

    if supports_gd_autobuild "$version" && \
        [ -n "$jpeg_prefix" ] && [ -n "$png_prefix" ] && [ -n "$freetype_prefix" ] && [ -n "$webp_prefix" ]; then
        auto_dependency_flags="$auto_dependency_flags --enable-gd --with-jpeg=$jpeg_prefix --with-freetype=$freetype_prefix --with-webp=$webp_prefix"
    fi

    for prefix_item in \
        "$iconv_prefix" \
        "$curl_prefix" \
        "$openssl_prefix" \
        "$sqlite_prefix" \
        "$zlib_prefix" \
        "$libzip_prefix" \
        "$icu_prefix" \
        "$jpeg_prefix" \
        "$png_prefix" \
        "$freetype_prefix" \
        "$webp_prefix" \
        "$xsl_prefix" \
        "$gettext_prefix" \
        "$libsodium_prefix" \
        "$bz2_prefix" \
        "$ldap_prefix" \
        "$readline_prefix" \
        "$oniguruma_prefix"
    do
        if [ -n "$prefix_item" ]; then
            cppflags="$(append_flag "$cppflags" "-I$prefix_item/include")"
            ldflags="$(append_flag "$ldflags" "-L$prefix_item/lib")"
            pkg_config_path="$(append_pkg_config_path "$prefix_item" "$pkg_config_path")"
        fi
    done
fi

if requires_external_oniguruma "$version" && [ "$minimal" != "1" ]; then
    if [ -z "${oniguruma_prefix:-}" ]; then
        printf 'Missing Homebrew dependency: oniguruma\n' >&2
        printf 'Install it with:\n' >&2
        printf '  brew install oniguruma\n' >&2
        exit 1
    fi
fi

if requires_external_libzip "$version" && [ "$minimal" != "1" ]; then
    if [ -z "${libzip_prefix:-}" ]; then
        printf 'Missing Homebrew dependency: libzip\n' >&2
        printf 'Install it with:\n' >&2
        printf '  brew install libzip\n' >&2
        exit 1
    fi
fi

if has_selected_extension intl && [ "$minimal" != "1" ]; then
    if [ -z "${icu_prefix:-}" ]; then
        printf 'Missing Homebrew dependency for intl extension: icu4c\n' >&2
        printf 'Install it with:\n' >&2
        printf '  brew install icu4c\n' >&2
        exit 1
    fi
fi

if [ -z "${iconv_prefix:-}" ] && [ "$minimal" != "1" ]; then
    printf 'Missing Homebrew dependency: libiconv\n' >&2
    printf 'Install it with:\n' >&2
    printf '  brew install libiconv\n' >&2
    exit 1
fi

common_flags="
--prefix=$prefix
--with-config-file-path=$prefix/conf
--enable-cgi
--with-zlib
--enable-mbstring
--enable-exif
--with-curl
--enable-bcmath
--enable-calendar
--enable-ftp
--enable-sockets
--enable-soap
--enable-opcache
--enable-pcntl
--enable-shmop
--enable-sysvshm
--enable-sysvsem
--enable-sysvmsg
--with-mysqli=mysqlnd
--with-pdo-mysql=mysqlnd
--with-pdo-sqlite
--with-sqlite3
--with-zip
--enable-fileinfo
--with-gettext
--enable-xml
--enable-dom
--enable-simplexml
--enable-xmlreader
--enable-xmlwriter
"

if supports_sodium "$version"; then
    common_flags="$common_flags
--with-sodium
"
fi

if ! is_legacy_php "$version" || [ -n "${openssl_prefix:-}" ]; then
    common_flags="$common_flags
--with-openssl
"
fi

printf 'Configuring PHP %s...\n' "$version"
configure_log="$work_dir/php-$version-configure.log"
make_log="$work_dir/php-$version-make.log"
run_configure() {
    current_flags="$1"
    status_file="$work_dir/php-$version-configure.status"
    rm -f "$status_file"
    (
        cd "$source_dir"
        export CPPFLAGS="$cppflags"
        export LDFLAGS="$ldflags"
        export PKG_CONFIG_PATH="$pkg_config_path"
        # shellcheck disable=SC2086
        ./configure $common_flags $current_flags $extra_flags
        printf '%s\n' "$?" >"$status_file"
    ) 2>&1 | tee "$configure_log"
    status="$(cat "$status_file" 2>/dev/null || printf '1')"
    rm -f "$status_file"
    [ "$status" -eq 0 ]
}

reset_source_tree() {
    if [ -n "$archive_path" ] && [ -f "$archive_path" ] && [ -n "$extracted_dir" ]; then
        rm -rf "$extracted_dir"
        tar -xzf "$archive_path" -C "$work_dir"
        source_dir="$extracted_dir"
        patch_legacy_source_files
    fi
}

patch_legacy_source_files() {
    if [ "$openssl_requires_php80_patch" = "1" ]; then
        openssl_source="$source_dir/ext/openssl/openssl.c"
        if [ -f "$openssl_source" ] && ! grep -q "ServerEngine OpenSSL 3 PHP 8.0 compatibility" "$openssl_source"; then
            perl -0pi -e 's/(#include <openssl\/ssl\.h>\n)/$1\n\/* ServerEngine OpenSSL 3 PHP 8.0 compatibility. *\/\n#ifndef RSA_SSLV23_PADDING\n#define RSA_SSLV23_PADDING RSA_PKCS1_PADDING\n#endif\n/' "$openssl_source"
        fi
    fi

    if is_legacy_php "$version"; then
        zlib_source="$source_dir/ext/zlib/zlib.c"
        dom_iterators_source="$source_dir/ext/dom/dom_iterators.c"
        fileinfo_funcs_source="$source_dir/ext/fileinfo/libmagic/funcs.c"
        mb_utf8_mobile_source="$source_dir/ext/mbstring/libmbfl/filters/mbfilter_utf8_mobile.c"
        reentrancy_source="$source_dir/main/reentrancy.c"
        if [ -f "$zlib_source" ]; then
            perl -0pi -e 's/\n(\s*)ZEND_MODULE_GLOBALS_CTOR_N\(zlib\),/\n$1(void (*)(void *)) ZEND_MODULE_GLOBALS_CTOR_N(zlib),/' "$zlib_source"
        fi
        if [ -f "$dom_iterators_source" ]; then
            perl -0pi -e 's/static void itemHashScanner \(void \*payload, void \*data, xmlChar \*name\)/static void itemHashScanner (void *payload, void *data, const xmlChar *name)/' "$dom_iterators_source"
        fi
        if [ -f "$fileinfo_funcs_source" ]; then
            perl -0pi -e 's/(?<!protected int\n)\nfile_replace\(struct magic_set \*ms, const char \*pat, const char \*rep\)/\nprotected int\nfile_replace(struct magic_set *ms, const char *pat, const char *rep)/' "$fileinfo_funcs_source"
            perl -0pi -e 's/\nprotected int\nprotected int\nfile_replace/\nprotected int\nfile_replace/' "$fileinfo_funcs_source"
        fi
        if [ -f "$mb_utf8_mobile_source" ]; then
            perl -0pi -e 's/\nextern int mbfl_filt_conv_utf8_wchar_flush\(mbfl_convert_filter \*filter\);/\nextern int mbfl_filt_conv_utf8_wchar_flush(mbfl_convert_filter *filter);\nextern int mbfl_filt_put_invalid_char(int c, mbfl_convert_filter *filter);/' "$mb_utf8_mobile_source"
        fi
        if [ -f "$reentrancy_source" ]; then
            perl -0pi -e 's/readdir_r\(dirp, entry\);/readdir_r(dirp, entry, result);/' "$reentrancy_source"
        fi
    fi
}

patch_makefile_for_local_build() {
    if [ -f "$source_dir/Makefile" ]; then
        if ! grep -q "PHP_PHARCMD_SETTINGS = .*pcre\\.jit=0" "$source_dir/Makefile"; then
            perl -0pi -e 's/^(PHP_PHARCMD_SETTINGS = .*)$/$1 -d pcre.jit=0/m' "$source_dir/Makefile"
        fi
    fi

    if is_legacy_php "$version" && [ -f "$source_dir/Makefile" ]; then
        if ! grep -q 'EXTRA_LIBS = .* -lresolv' "$source_dir/Makefile"; then
            perl -0pi -e 's/^(EXTRA_LIBS = .*)$/$1 -lresolv/m' "$source_dir/Makefile"
        fi
        perl -0pi -e 's/ q\{ -d pcre\.jit=0\}//g' "$source_dir/Makefile"
        perl -0pi -e 's/\s+ext\/pcre\/pcrelib\/pcre_jit_compile\.lo(?= )//g' "$source_dir/Makefile"
    fi
}

patch_intl_makefile_for_modern_icu() {
    if [ "$intl_requires_cxx17" = "1" ] && [ -f "$source_dir/Makefile" ]; then
        if grep -q -- '-std=c++11\|-std=gnu++11\|-std=c++14\|-std=gnu++14' "$source_dir/Makefile"; then
            printf 'Patching PHP intl C++ standard to C++17 for modern ICU headers.\n'
            perl -0pi -e 's/-std=(?:gnu\+\+|c\+\+)(?:11|14)/-std=c++17/g' "$source_dir/Makefile"
        fi
    fi
}

if [ "$minimal" = "1" ]; then
    common_flags="
--prefix=$prefix
--with-config-file-path=$prefix/conf
--enable-cgi
--with-zlib
"
fi

patch_legacy_source_files

run_make() {
    status_file="$work_dir/php-$version-make.status"
    rm -f "$status_file"
    (
        cd "$source_dir"
        patch_makefile_for_local_build
        patch_intl_makefile_for_modern_icu
        make -j"$jobs"
        printf '%s\n' "$?" >"$status_file"
    ) 2>&1 | tee "$make_log"
    status="$(cat "$status_file" 2>/dev/null || printf '1')"
    rm -f "$status_file"
    [ "$status" -eq 0 ]
}

if ! run_configure "$auto_dependency_flags"; then
    if grep -q "GD build test failed" "$configure_log"; then
        printf '\nGD configure test failed. Retrying without GD support...\n'
        auto_dependency_flags="$(remove_gd_flags "$auto_dependency_flags")"
        reset_source_tree
        if ! run_configure "$auto_dependency_flags"; then
            printf '\nConfigure still failed after disabling GD.\n' >&2
            printf 'See log: %s\n' "$configure_log" >&2
            exit 1
        fi
    else
        exit 1
    fi
fi

printf 'Building PHP %s with %s job(s)...\n' "$version" "$jobs"
if ! run_make; then
    if is_legacy_php "$version" && grep -q "ext/openssl/" "$make_log"; then
        printf '\nLegacy PHP OpenSSL build failed. Retrying without PHP openssl extension...\n'
        common_flags="$(remove_openssl_flags "$common_flags")"
        auto_dependency_flags="$(remove_openssl_flags "$auto_dependency_flags")"
        reset_source_tree
        if ! run_configure "$auto_dependency_flags"; then
            printf '\nConfigure failed while retrying without PHP openssl extension.\n' >&2
            printf 'See log: %s\n' "$configure_log" >&2
            exit 1
        fi
        if ! run_make; then
            printf '\nBuild still failed after disabling PHP openssl extension.\n' >&2
            printf 'See log: %s\n' "$make_log" >&2
            exit 1
        fi
    else
        printf '\nBuild failed.\n' >&2
        printf 'See log: %s\n' "$make_log" >&2
        exit 1
    fi
fi

printf 'Installing into %s...\n' "$prefix"
(
    cd "$source_dir"
    patch_makefile_for_local_build
    make install
)

    if [ -f "$source_dir/php.ini-production" ]; then
    cp "$source_dir/php.ini-production" "$prefix/conf/php.ini"
elif [ -f "$source_dir/php.ini-development" ]; then
    cp "$source_dir/php.ini-development" "$prefix/conf/php.ini"
elif [ ! -f "$prefix/conf/php.ini" ]; then
    : > "$prefix/conf/php.ini"
fi

printf '\nDone.\n'
printf 'Installed runtime: %s\n' "$prefix"
printf 'Expected binaries:\n'
printf '  %s\n' "$prefix/bin/php"
printf '  %s\n' "$prefix/bin/php-cgi"
printf 'Config file:\n'
printf '  %s\n' "$prefix/conf/php.ini"

if [ "$minimal" != "1" ]; then
    printf '\nBundling selected PHP extensions: %s\n' "$enabled_extensions"
    redis_ext_ver="$(pecl_version_for redis "$version")"
    memcached_ext_ver="$(pecl_version_for memcached "$version")"
    apcu_ext_ver="$(pecl_version_for apcu "$version")"
    imagick_ext_ver="$(pecl_version_for imagick "$version")"
    xdebug_ext_ver="$(pecl_version_for xdebug "$version")"

    if has_selected_extension redis; then
        build_pecl_extension redis "$redis_ext_ver"
    fi
    if has_selected_extension memcached; then
        build_pecl_extension memcached "$memcached_ext_ver"
    fi
    if has_selected_extension apcu; then
        build_pecl_extension apcu "$apcu_ext_ver"
    fi
    if has_selected_extension imagick; then
        build_pecl_extension imagick "$imagick_ext_ver"
    fi
    if has_selected_extension xdebug; then
        build_pecl_extension xdebug "$xdebug_ext_ver"
    fi

    ext_dir="$("$prefix/bin/php-config" --extension-dir 2>/dev/null || true)"
    if [ -z "$ext_dir" ] || [ ! -d "$ext_dir" ]; then
        printf '\nCould not detect PHP extension directory via php-config.\n' >&2
        exit 1
    fi
    runtime_modules="$($prefix/bin/php -m 2>/dev/null || true)"
    missing_extensions=""
    for ext_name in $enabled_extensions; do
        case "$ext_name" in
            intl)
                # intl may be shared (intl.so) or built-in depending on PHP configure behavior.
                if [ ! -f "$ext_dir/intl.so" ]; then
                    if ! "$prefix/bin/php" -m 2>/dev/null | grep -qi '^intl$'; then
                        missing_extensions="$missing_extensions intl.so"
                    fi
                fi
                ;;
            *)
                ext_file="$ext_name.so"
                if [ ! -f "$ext_dir/$ext_file" ]; then
                    missing_extensions="$missing_extensions $ext_file"
                fi
                ;;
        esac
    done
    if [ -n "$missing_extensions" ]; then
        if [ "$skip_extension_check" = "1" ]; then
            printf '\nSkipping extension verification failures (--skip-extension-check):\n' >&2
            # shellcheck disable=SC2086
            for ext_file in $missing_extensions; do
                printf '  - %s\n' "$ext_file" >&2
            done
        else
            printf '\nMissing selected bundled extensions in %s:\n' "$ext_dir" >&2
            # shellcheck disable=SC2086
            for ext_file in $missing_extensions; do
                printf '  - %s\n' "$ext_file" >&2
            done
            exit 1
        fi
    fi

    runtime_modules="$($prefix/bin/php -m 2>/dev/null || true)"
    required_modules="bcmath curl dom fileinfo gd gettext intl mbstring mysqli openssl PDO pdo_mysql pdo_sqlite session SimpleXML sodium xml xmlreader xmlwriter zip"
    missing_modules=""
    for module in $required_modules; do
        if [ "$module" = "sodium" ] && ! supports_sodium "$version"; then
            continue
        fi
        if ! printf '%s\n' "$runtime_modules" | grep -Eqi "^${module}$"; then
            missing_modules="$missing_modules $module"
        fi
    done
    if [ -n "$missing_modules" ]; then
        printf '\nRequired PHP modules missing from %s:\n' "$prefix" >&2
        # shellcheck disable=SC2086
        for module in $missing_modules; do
            printf '  - %s\n' "$module" >&2
        done
        exit 1
    fi
fi

if [ "$skip_package" != "1" ]; then
    package_script="$repo_root/scripts/package_php_runtime_macos.sh"
    packaged_target="$package_output"
    if [ -z "$packaged_target" ]; then
        packaged_target="$repo_root/dist/runtime/php/$(basename "$prefix")"
    fi
    if [ -f "$package_script" ]; then
        printf '\nPackaging self-contained macOS runtime...\n'
        if [ -n "$package_output" ]; then
            /bin/sh "$package_script" --source "$prefix" --overwrite --output "$package_output"
        else
            /bin/sh "$package_script" --source "$prefix" --overwrite --output "$packaged_target"
        fi
        if [ ! -x "$packaged_target/bin/php-cgi" ]; then
            printf '\nPackaged runtime verification failed: missing %s\n' "$packaged_target/bin/php-cgi" >&2
            exit 1
        fi
        printf 'Packaged runtime ready for Apache and Nginx: %s\n' "$packaged_target"
    else
        printf '\nPackaging skipped: %s not found.\n' "$package_script" >&2
    fi
else
    printf '\nPackaging skipped by --skip-package.\n'
fi

printf '\nNext step:\n'
printf '  Tune php.ini if needed, then copy the packaged runtime into your production app runtime path.\n'
