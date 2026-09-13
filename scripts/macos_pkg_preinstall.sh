#!/bin/sh

set -eu

stop_server_engine_processes() {
    app_support_root="$1"
    app_runtime_bin="$app_support_root/bin"
    state_file="$app_support_root/runtime/process_state.json"

    kill_pid_gracefully() {
        target_pid="$1"
        [ -n "$target_pid" ] || return 0
        /bin/kill "$target_pid" >/dev/null 2>&1 || true
        /bin/sleep 0.3
        /bin/kill -9 "$target_pid" >/dev/null 2>&1 || true
    }

    stop_known_ports_for_server_engine() {
        for port in 80 443 3306 6379 11211 1025 8025; do
            pids="$(/usr/sbin/lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null || true)"
            [ -n "$pids" ] || continue
            for pid in $pids; do
                cmd="$(/bin/ps -o command= -p "$pid" 2>/dev/null || true)"
                case "$cmd" in
                    *"$app_support_root"*|*"/Applications/Server Engine.app"*)
                        kill_pid_gracefully "$pid"
                        ;;
                esac
            done
        done
    }

    # Ask the UI app to quit first only when the installed app exists.
    # This avoids macOS "locate application" prompts on first-time installs.
    if [ -d "/Applications/Server Engine.app" ]; then
        /usr/bin/osascript -e 'tell application id "com.serverengine.app" to quit' >/dev/null 2>&1 || true
    fi
    /bin/sleep 1
    /usr/bin/pkill -x "Server Engine" >/dev/null 2>&1 || true
    /usr/bin/pkill -f "/Applications/Server Engine.app" >/dev/null 2>&1 || true

    # Stop PIDs recorded by previous app run metadata.
    if [ -f "$state_file" ]; then
        pids_from_state="$(/usr/bin/python3 - <<PY
import json
from pathlib import Path
path = Path("$state_file")
try:
    payload = json.loads(path.read_text(encoding="utf-8"))
except Exception:
    payload = {}
pids = []
for item in payload.values():
    pid = item.get("pid")
    if isinstance(pid, int):
        pids.append(str(pid))
print(" ".join(pids))
PY
)"
        if [ -n "$pids_from_state" ]; then
            for pid in $pids_from_state; do
                kill_pid_gracefully "$pid"
            done
        fi
    fi

    # Stop any stack processes launched from the managed runtime root.
    pids="$(/usr/bin/pgrep -f "$app_runtime_bin" 2>/dev/null || true)"
    if [ -n "$pids" ]; then
        /bin/kill $pids >/dev/null 2>&1 || true
        /bin/sleep 1
        pids_remaining="$(/usr/bin/pgrep -f "$app_runtime_bin" 2>/dev/null || true)"
        if [ -n "$pids_remaining" ]; then
            /bin/kill -9 $pids_remaining >/dev/null 2>&1 || true
        fi
    fi

    # Kill any remaining listeners owned by Server Engine on known ports.
    stop_known_ports_for_server_engine

    # Clear stale state; new app run will rebuild it.
    /bin/rm -f "$state_file" >/dev/null 2>&1 || true
}

console_user="$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null || true)"
if [ -z "$console_user" ] || [ "$console_user" = "root" ] || [ "$console_user" = "loginwindow" ]; then
    exit 0
fi

user_home="$(/usr/bin/dscl . -read "/Users/$console_user" NFSHomeDirectory 2>/dev/null | /usr/bin/awk '{print $2}')"
if [ -z "$user_home" ]; then
    user_home="/Users/$console_user"
fi

app_support_root="$user_home/Library/Application Support/Server Engine"
stop_server_engine_processes "$app_support_root"

exit 0
