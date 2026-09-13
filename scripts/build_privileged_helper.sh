#!/bin/sh

set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
src_file="$repo_root/scripts/privileged_helper/ServerEnginePrivilegedHelper.c"
info_plist="$repo_root/scripts/privileged_helper/ServerEnginePrivilegedHelper-Info.plist"
launchd_plist="$repo_root/scripts/privileged_helper/ServerEnginePrivilegedHelper-Launchd.plist"
default_out="$repo_root/dist/helper/server-engine-privileged-helper"
out_file="${1:-$default_out}"

if [ ! -f "$src_file" ]; then
    printf 'Helper source not found: %s\n' "$src_file" >&2
    exit 1
fi

if ! command -v clang >/dev/null 2>&1; then
    printf 'clang is required to build privileged helper.\n' >&2
    exit 1
fi
if [ ! -f "$info_plist" ] || [ ! -f "$launchd_plist" ]; then
    printf 'Missing helper plist(s):\n  %s\n  %s\n' "$info_plist" "$launchd_plist" >&2
    exit 1
fi

/bin/mkdir -p "$(dirname "$out_file")"
/usr/bin/clang \
    -O \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$info_plist" \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __launchd_plist -Xlinker "$launchd_plist" \
    "$src_file" \
    -o "$out_file"
/bin/chmod 755 "$out_file"

printf 'Built privileged helper:\n  %s\n' "$out_file"
