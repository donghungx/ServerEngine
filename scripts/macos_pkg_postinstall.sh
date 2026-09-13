#!/bin/sh

set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
app_source="$script_dir/app/Server Engine.app"
runtime_source="$script_dir/runtime"

clear_quarantine_tree() {
    target="$1"
    [ -e "$target" ] || return 0
    /usr/bin/xattr -dr com.apple.quarantine "$target" >/dev/null 2>&1 || true
}

adhoc_sign_tree() {
    target="$1"
    [ -d "$target" ] || return 0
    if ! command -v /usr/bin/codesign >/dev/null 2>&1; then
        return 0
    fi
    /usr/bin/find "$target" -type f | while IFS= read -r file; do
        case "$file" in
            *.dylib|*.so|*/bin/*)
                if /usr/bin/file "$file" | /usr/bin/grep -Eq 'Mach-O'; then
                    /usr/bin/codesign --force --sign - "$file" >/dev/null 2>&1 || true
                fi
                ;;
        esac
    done
}

should_adhoc_sign="${SERVER_ENGINE_POSTINSTALL_ADHOC_SIGN:-0}"

if [ -d "$app_source" ]; then
    /bin/mkdir -p /Applications
    /usr/bin/ditto "$app_source" "/Applications/Server Engine.app"
    clear_quarantine_tree "/Applications/Server Engine.app"
fi

console_user="$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null || true)"
if [ -z "$console_user" ] || [ "$console_user" = "root" ] || [ "$console_user" = "loginwindow" ]; then
    exit 0
fi

user_home="$(/usr/bin/dscl . -read "/Users/$console_user" NFSHomeDirectory 2>/dev/null | /usr/bin/awk '{print $2}')"
if [ -z "$user_home" ]; then
    user_home="/Users/$console_user"
fi

app_support_root="$user_home/Library/Application Support/Server Engine"
bin_root="$app_support_root/bin"
tools_root="$bin_root/tools"

/bin/mkdir -p \
    "$bin_root/php" \
    "$bin_root/database" \
    "$bin_root/server" \
    "$bin_root/redis" \
    "$bin_root/memcached" \
    "$bin_root/mailpit" \
    "$bin_root/node" \
    "$tools_root"
/bin/mkdir -p \
    "$app_support_root/config" \
    "$app_support_root/logs" \
    "$app_support_root/data" \
    "$app_support_root/backups" \
    "$app_support_root/runtime" \
    "$app_support_root/temp"

if [ -f "$runtime_source/bin/server-engine-privileged-helper" ]; then
    /bin/cp "$runtime_source/bin/server-engine-privileged-helper" "$bin_root/server-engine-privileged-helper"
    /bin/chmod 755 "$bin_root/server-engine-privileged-helper"
fi

for category in php database server redis memcached mailpit node tools; do
    if [ -d "$runtime_source/$category" ]; then
        if [ "$category" = "php" ]; then
            backup_root="$app_support_root/temp/php-ini-backup"
            /bin/rm -rf "$backup_root"
            /bin/mkdir -p "$backup_root"
            if [ -d "$bin_root/php" ]; then
                for existing_runtime in "$bin_root/php"/php*; do
                    [ -d "$existing_runtime" ] || continue
                    runtime_name="$(/usr/bin/basename "$existing_runtime")"
                    existing_ini="$existing_runtime/conf/php.ini"
                    if [ -f "$existing_ini" ]; then
                        /bin/mkdir -p "$backup_root/$runtime_name/conf"
                        /bin/cp "$existing_ini" "$backup_root/$runtime_name/conf/php.ini"
                    fi
                done
            fi

            /usr/bin/ditto "$runtime_source/$category" "$bin_root/$category"

            for backed_runtime in "$backup_root"/php*; do
                [ -d "$backed_runtime" ] || continue
                runtime_name="$(/usr/bin/basename "$backed_runtime")"
                backed_ini="$backed_runtime/conf/php.ini"
                target_ini="$bin_root/php/$runtime_name/conf/php.ini"
                if [ -f "$backed_ini" ] && [ -d "$bin_root/php/$runtime_name/conf" ]; then
                    /bin/cp "$backed_ini" "$target_ini"
                fi
            done
            /bin/rm -rf "$backup_root"
        elif [ "$category" = "tools" ]; then
            /usr/bin/ditto "$runtime_source/$category" "$tools_root"
        else
            /usr/bin/ditto "$runtime_source/$category" "$bin_root/$category"
        fi
    fi
done

/usr/sbin/chown -R "$console_user:staff" "$app_support_root"
clear_quarantine_tree "$app_support_root"
if [ "$should_adhoc_sign" = "1" ]; then
    adhoc_sign_tree "$bin_root"
    # tools_root now lives under bin_root; avoid re-signing the same tree twice.
    if [ "$tools_root" != "$bin_root/tools" ]; then
        adhoc_sign_tree "$tools_root"
    fi
fi
clear_quarantine_tree "$app_support_root"

exit 0
