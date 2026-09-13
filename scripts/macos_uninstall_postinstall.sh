#!/bin/sh

set -eu

remove_user_paths() {
    user_home="$1"
    [ -n "$user_home" ] || return 0
    [ -d "$user_home" ] || return 0

    app_support_root="$user_home/Library/Application Support/Server Engine"
    logs_root="$user_home/Library/Logs/Server Engine"
    prefs_file="$user_home/Library/Preferences/com.serverengine.app.plist"

    if [ -d "$app_support_root" ]; then
        /bin/rm -rf "$app_support_root"
    fi
    if [ -d "$logs_root" ]; then
        /bin/rm -rf "$logs_root"
    fi
    if [ -f "$prefs_file" ]; then
        /bin/rm -f "$prefs_file"
    fi
}

stop_server_engine_processes() {
    /usr/bin/osascript -e 'tell application "Server Engine" to quit' >/dev/null 2>&1 || true
    /bin/sleep 1
    /usr/bin/pkill -x "Server Engine" >/dev/null 2>&1 || true
    /usr/bin/pkill -f "/Applications/Server Engine.app" >/dev/null 2>&1 || true
    /usr/bin/pkill -f "Server Engine/bin/" >/dev/null 2>&1 || true
}

remove_dock_icon_for_home() {
    user_home="$1"
    user_name="$2"
    [ -n "$user_home" ] || return 0
    [ -d "$user_home" ] || return 0

    dock_plist="$user_home/Library/Preferences/com.apple.dock.plist"
    [ -f "$dock_plist" ] || return 0

    persistent_count="$(/usr/libexec/PlistBuddy -c "Print persistent-apps" "$dock_plist" 2>/dev/null | /usr/bin/grep -c 'Dict {' || true)"
    [ -n "$persistent_count" ] || persistent_count="0"

    index=$((persistent_count - 1))
    while [ "$index" -ge 0 ]; do
        dock_url="$(/usr/libexec/PlistBuddy -c "Print persistent-apps:$index:tile-data:file-data:_CFURLString" "$dock_plist" 2>/dev/null || true)"
        case "$dock_url" in
            *"Server Engine.app"*)
                /usr/libexec/PlistBuddy -c "Delete persistent-apps:$index" "$dock_plist" >/dev/null 2>&1 || true
                ;;
        esac
        index=$((index - 1))
    done

    /usr/bin/defaults delete "$dock_plist" mod-count >/dev/null 2>&1 || true

    if [ -n "$user_name" ] && [ "$user_name" != "root" ] && [ "$user_name" != "loginwindow" ]; then
        /usr/bin/pkill -u "$user_name" Dock >/dev/null 2>&1 || true
    fi
}

stop_server_engine_processes

# Remove app bundle.
if [ -d "/Applications/Server Engine.app" ]; then
    /bin/rm -rf "/Applications/Server Engine.app"
fi

# Remove installed privileged helper if present.
/bin/rm -f "/Library/PrivilegedHelperTools/com.serverengine.privileged-helper" >/dev/null 2>&1 || true

# Remove for current console user first.
console_user="$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null || true)"
if [ -n "$console_user" ] && [ "$console_user" != "root" ] && [ "$console_user" != "loginwindow" ]; then
    console_home="$(/usr/bin/dscl . -read "/Users/$console_user" NFSHomeDirectory 2>/dev/null | /usr/bin/awk '{print $2}')"
    if [ -z "$console_home" ]; then
        console_home="/Users/$console_user"
    fi
    remove_user_paths "$console_home"
    remove_dock_icon_for_home "$console_home" "$console_user"
fi

# Remove from any local home that contains Server Engine data.
for candidate in /Users/*; do
    [ -d "$candidate" ] || continue
    case "$candidate" in
        "/Users/Shared") continue ;;
    esac
    if [ -d "$candidate/Library/Application Support/Server Engine" ] || [ -d "$candidate/Library/Logs/Server Engine" ] || [ -f "$candidate/Library/Preferences/com.apple.dock.plist" ]; then
        remove_user_paths "$candidate"
        candidate_user="$(/usr/bin/basename "$candidate")"
        remove_dock_icon_for_home "$candidate" "$candidate_user"
    fi
done

exit 0
