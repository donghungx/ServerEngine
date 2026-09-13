#!/bin/sh

set -eu

confirm_uninstall() {
    console_user="$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null || true)"
    if [ -z "$console_user" ] || [ "$console_user" = "root" ] || [ "$console_user" = "loginwindow" ]; then
        return 0
    fi

    prompt='This will permanently remove Server Engine and ALL local data, including websites, runtime files, logs, and database files. This cannot be undone. Continue?'
    if ! /usr/bin/osascript -e "display dialog \"$prompt\" with title \"Confirm Full Uninstall\" buttons {\"Cancel\", \"Wipe Everything\"} default button \"Cancel\" with icon caution" >/dev/null 2>&1; then
        exit 1
    fi
}

stop_server_engine_processes() {
    # Ask app to quit gracefully first.
    /usr/bin/osascript -e 'tell application "Server Engine" to quit' >/dev/null 2>&1 || true
    /bin/sleep 1

    # Stop app processes.
    /usr/bin/pkill -x "Server Engine" >/dev/null 2>&1 || true
    /usr/bin/pkill -f "/Applications/Server Engine.app" >/dev/null 2>&1 || true

    # Stop managed runtime/service processes from any user home.
    /usr/bin/pkill -f "/Library/Application Support/Server Engine/bin/" >/dev/null 2>&1 || true
    /usr/bin/pkill -f "Server Engine/bin/" >/dev/null 2>&1 || true

    # Give processes a moment, then force kill leftovers.
    /bin/sleep 1
    /usr/bin/pkill -9 -x "Server Engine" >/dev/null 2>&1 || true
    /usr/bin/pkill -9 -f "/Applications/Server Engine.app" >/dev/null 2>&1 || true
    /usr/bin/pkill -9 -f "/Library/Application Support/Server Engine/bin/" >/dev/null 2>&1 || true
    /usr/bin/pkill -9 -f "Server Engine/bin/" >/dev/null 2>&1 || true
}

confirm_uninstall
stop_server_engine_processes

exit 0
