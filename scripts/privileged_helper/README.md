# Privileged Helper Scaffold (Phase 1 + 2)

This folder contains the native helper source used for hosts updates without repeated password prompts once wired through macOS privileged-helper install flow.

Current scope:
- `ServerEnginePrivilegedHelper.c` implements restricted commands only:
  - `write-hosts --input <path> [--hosts-path /etc/hosts]`
  - `flush-dns`
- App-side Python bridge is in:
  - `src/server_engine/infrastructure/privileged_helper.py`
  - `src/server_engine/infrastructure/hosts.py` (uses helper first, falls back to `osascript`)

## Build helper binary (local test only)

```bash
clang -O -o server-engine-privileged-helper ServerEnginePrivilegedHelper.c
```

Place resulting binary at (bundled/source location):

```text
dist/helper/server-engine-privileged-helper
```

Or override path with:

```bash
export SERVER_ENGINE_PRIVILEGED_HELPER_PATH="/absolute/path/to/server-engine-privileged-helper"
```

## Important

Current app behavior:
- On first hosts write requiring elevation, app attempts one-time helper install to:
  - `/Library/PrivilegedHelperTools/com.serverengine.privileged-helper`
- It prompts for admin once for install/chown/chmod (setuid root).
- Subsequent hosts updates call helper directly without repeating password prompt.

Still recommended for production hardening:
- migrate to `SMJobBless` + launchd service
- signed helper handshake
- stricter request authentication between app and helper
