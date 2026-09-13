#!/bin/sh

set -eu

usage() {
    cat <<'EOF'
Usage:
  scripts/install_node_runtime.sh [options]

Download and stage Node.js runtimes into this repo's prebuild layout:
  prebuild/node/node<version>

By default (no options), the script opens an interactive major-version picker
and installs the latest patch release for selected majors.

Options:
  --major <n>           Node major version to install. Repeatable.
                        Example: --major 16 --major 18 --major 20
  --majors <list>       Comma-separated major list. Example: 16,18,20
  --overwrite           Remove existing target runtime directory first
  --skip-deploy         Skip copying runtime to app-managed runtime root
  --skip-package        Skip packaging runtime into <repo>/dist/runtime/node
  --deploy-root <path>  Override deploy root.
                        Default: <repo>/dist/runtime/node
  --target-root <path>  Override staging root. Default: prebuild/node
  --package-output-root <path>
                        Override packaged output root. Default: <repo>/dist/runtime/node
  --help                Show this help

Examples:
  scripts/install_node_runtime.sh
  scripts/install_node_runtime.sh --major 16 --major 18 --major 20 --overwrite
  scripts/install_node_runtime.sh --majors 16,18,20 --skip-deploy
EOF
}

abspath() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s\n' "$(pwd)/$1" ;;
    esac
}

if ! command -v python3 >/dev/null 2>&1; then
    printf 'python3 is required.\n' >&2
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    printf 'curl is required.\n' >&2
    exit 1
fi

if ! command -v tar >/dev/null 2>&1; then
    printf 'tar is required.\n' >&2
    exit 1
fi

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
target_root="$repo_root/prebuild/node"
deploy_root="$repo_root/dist/runtime/node"
package_output_root="$repo_root/dist/runtime/node"
overwrite="0"
skip_deploy="0"
skip_package="0"
majors=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --major)
            value="${2:-}"
            shift 2
            if [ -z "$value" ]; then
                printf '--major requires a value.\n' >&2
                exit 1
            fi
            if [ -n "$majors" ]; then
                majors="$majors,$value"
            else
                majors="$value"
            fi
            ;;
        --majors)
            majors="${2:-}"
            shift 2
            ;;
        --overwrite)
            overwrite="1"
            shift
            ;;
        --skip-deploy)
            skip_deploy="1"
            shift
            ;;
        --skip-package)
            skip_package="1"
            shift
            ;;
        --deploy-root)
            deploy_root="$(abspath "${2:-}")"
            shift 2
            ;;
        --target-root)
            target_root="$(abspath "${2:-}")"
            shift 2
            ;;
        --package-output-root)
            package_output_root="$(abspath "${2:-}")"
            shift 2
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

platform="$(uname -s | tr '[:upper:]' '[:lower:]')"
if [ "$platform" != "darwin" ]; then
    printf 'This installer currently supports macOS only.\n' >&2
    exit 1
fi

machine="$(uname -m)"
case "$machine" in
    arm64|aarch64) node_arch="arm64" ;;
    x86_64|amd64) node_arch="x64" ;;
    *)
        printf 'Unsupported CPU architecture: %s\n' "$machine" >&2
        exit 1
        ;;
esac

index_json="$(python3 - <<'PY'
import tempfile
tmp = tempfile.NamedTemporaryFile(prefix="node-index-", suffix=".json", delete=False)
print(tmp.name)
tmp.close()
PY
)"
cleanup() {
    rm -f "$index_json"
}
trap cleanup EXIT

printf 'Fetching Node.js release index...\n'
curl -fsSL "https://nodejs.org/dist/index.json" -o "$index_json"

if [ -z "$majors" ]; then
    majors="$(python3 - "$index_json" <<'PY'
import json
import os
import sys
import termios
import tty

index_path = sys.argv[1]
with open(index_path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

majors = []
seen = set()
for entry in data:
    version = str(entry.get("version", "")).strip()
    if not version.startswith("v"):
        continue
    major = version[1:].split(".", 1)[0]
    if not major.isdigit():
        continue
    if int(major) < 16:
        continue
    if major in seen:
        continue
    seen.add(major)
    majors.append(major)

majors = sorted(majors, key=lambda value: int(value))
if not majors:
    raise SystemExit("No supported Node majors found from index.")

selected = [False for _ in majors]
cursor = len(majors) - 1

def write(fd, text):
    os.write(fd, text.replace("\n", "\r\n").encode("utf-8", "replace"))

def draw(fd):
    write(fd, "\033[H\033[2J")
    write(fd, "Select Node major versions (Space to toggle, Enter to confirm)\n\n")
    for idx, major in enumerate(majors):
        pointer = "> " if idx == cursor else "  "
        mark = "[x]" if selected[idx] else "[ ]"
        write(fd, f"{pointer}{mark} {major}\n")
    write(fd, "\nKeys: ↑/↓ move  Space toggle  Enter confirm  q cancel\n")

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

fd = os.open("/dev/tty", os.O_RDWR)
old = termios.tcgetattr(fd)
try:
    write(fd, "\033[?1049h\033[?25l")
    tty.setraw(fd)
    while True:
        draw(fd)
        key = read_key(fd)
        if key in ("q", "\x03", "ESC"):
            raise SystemExit(1)
        if key in ("\r", "\n"):
            picked = [major for idx, major in enumerate(majors) if selected[idx]]
            if not picked:
                picked = [majors[cursor]]
            os.write(1, (",".join(picked) + "\n").encode("utf-8"))
            break
        if key == "UP" and cursor > 0:
            cursor -= 1
        elif key == "DOWN" and cursor < len(majors) - 1:
            cursor += 1
        elif key == " ":
            selected[cursor] = not selected[cursor]
finally:
    termios.tcsetattr(fd, termios.TCSADRAIN, old)
    write(fd, "\033[?25h\033[?1049l")
    os.close(fd)
PY
)"
    if [ -z "$majors" ]; then
        printf 'No Node major selected.\n' >&2
        exit 1
    fi
fi

resolved="$(python3 - "$index_json" "$majors" "$node_arch" <<'PY'
import json
import sys

index_path, majors_csv, arch = sys.argv[1], sys.argv[2], sys.argv[3]
requested = []
seen = set()
for part in majors_csv.split(","):
    value = part.strip()
    if not value:
        continue
    if not value.isdigit():
        raise SystemExit(f"Invalid major value: {value}")
    if value in seen:
        continue
    seen.add(value)
    requested.append(value)

if not requested:
    raise SystemExit("No valid majors provided.")

with open(index_path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

for major in requested:
    selected = None
    for entry in data:
        version = str(entry.get("version", "")).strip()
        if not version.startswith("v"):
            continue
        version_no_v = version[1:]
        if not version_no_v.startswith(major + "."):
            continue
        files = entry.get("files", []) or []
        if f"osx-{arch}-tar" not in files:
            continue
        selected = version_no_v
        break
    if selected is None:
        raise SystemExit(f"No downloadable macOS runtime found for major {major} ({arch}).")
    print(f"{major}:{selected}")
PY
)"

if [ -z "$resolved" ]; then
    printf 'Could not resolve Node versions from index.\n' >&2
    exit 1
fi

mkdir -p "$target_root"
if [ "$skip_deploy" != "1" ]; then
    mkdir -p "$deploy_root"
fi
if [ "$skip_package" != "1" ]; then
    mkdir -p "$package_output_root"
fi

printf 'Installing Node runtimes for architecture: %s\n' "$node_arch"
printf '%s\n' "$resolved" | while IFS=: read -r major version; do
    [ -n "$major" ] || continue
    [ -n "$version" ] || continue

    runtime_name="node$version"
    target_dir="$target_root/$runtime_name"
    archive_name="node-v$version-darwin-$node_arch.tar.gz"
    download_url="https://nodejs.org/dist/v$version/$archive_name"

    if [ -d "$target_dir" ]; then
        if [ "$overwrite" = "1" ]; then
            rm -rf "$target_dir"
        else
            printf 'Runtime already exists, skipping: %s\n' "$target_dir"
            continue
        fi
    fi

    temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/node-runtime.XXXXXX")"
    archive_path="$temp_dir/$archive_name"
    extract_dir="$temp_dir/extracted"
    mkdir -p "$extract_dir"

    python3 - "$download_url" "$archive_path" "$version" "$major" <<'PY'
import sys
import urllib.request

url, dest, version, major = sys.argv[1:5]
req = urllib.request.Request(url, headers={"User-Agent": "server-engine-node-installer/1.0"})
with urllib.request.urlopen(req) as response, open(dest, "wb") as out:
    total_raw = response.headers.get("Content-Length")
    total = int(total_raw) if total_raw and total_raw.isdigit() else 0
    downloaded = 0
    last_percent = -1
    chunk_size = 1024 * 256
    if total > 0:
        print(f"Download progress (Node {version}, major {major}): 0%", flush=True)
        last_percent = 0
    while True:
        chunk = response.read(chunk_size)
        if not chunk:
            break
        out.write(chunk)
        downloaded += len(chunk)
        if total > 0:
            percent = int((downloaded * 100) / total)
            if percent != last_percent:
                last_percent = percent
                print(f"Download progress (Node {version}, major {major}): {percent}%", flush=True)
    if total <= 0:
        mb = downloaded / (1024 * 1024)
        print(f"Download progress (Node {version}, major {major}): {mb:.1f} MB", flush=True)
PY

    printf 'Extracting %s...\n' "$archive_name"
    tar -xzf "$archive_path" -C "$extract_dir"
    extracted_root="$extract_dir/node-v$version-darwin-$node_arch"
    if [ ! -d "$extracted_root" ]; then
        rm -rf "$temp_dir"
        printf 'Extracted runtime root missing: %s\n' "$extracted_root" >&2
        exit 1
    fi

    mkdir -p "$(dirname "$target_dir")"
    cp -R "$extracted_root" "$target_dir"

    if [ "$skip_deploy" != "1" ]; then
        deploy_dir="$deploy_root/$runtime_name"
        if [ -d "$deploy_dir" ] && [ "$overwrite" = "1" ]; then
            rm -rf "$deploy_dir"
        fi
        if [ ! -d "$deploy_dir" ]; then
            cp -R "$target_dir" "$deploy_dir"
        fi
    fi

    if [ "$skip_package" != "1" ]; then
        package_script="$repo_root/scripts/package_node_runtime_macos.sh"
        packaged_dir="$package_output_root/$runtime_name"
        if [ ! -f "$package_script" ]; then
            printf 'Node package script not found: %s\n' "$package_script" >&2
            exit 1
        fi
        /bin/sh "$package_script" --source "$target_dir" --output "$packaged_dir" --overwrite
    fi

    rm -rf "$temp_dir"
    printf 'Installed: %s\n' "$target_dir"
done

printf '\nDone.\n'
printf 'Staged runtimes root: %s\n' "$target_root"
if [ "$skip_deploy" != "1" ]; then
    printf 'Deployed runtimes root: %s\n' "$deploy_root"
fi
if [ "$skip_package" != "1" ]; then
    printf 'Packaged runtimes root: %s\n' "$package_output_root"
fi
