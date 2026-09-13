clear php runtimes cache list 
sqlite3 "/Users/donghungbui/Library/Application Support/Server Engine/server_engine.db" \
  "DELETE FROM app_cache WHERE key = 'runtime_inventory.php';"

  after need code sign


  RUNTIME="/Users/donghungbui/Library/Application Support/Server Engine/bin/php/php8.5.0"

find "$RUNTIME" -type f \( -perm -111 -o -name '*.dylib' \) -exec codesign --force --sign - {} \;

codesign --force --deep --sign - "$RUNTIME"


## Local development setup (donghungx)

Python 3.12 is the default `python` / `python3` in zsh via `~/.zshrc`.
The project dependencies are installed in `.venv` with an editable install.
Global launchers in `~/.local/bin` use that environment automatically.

Run once in an already-open terminal:

```sh
source ~/.zshrc
```

Then run from any directory (no activation or PYTHONPATH required):

```sh
server-engine-gui
server-engine --help
```

The GUI launcher defaults to INFO logging, stdout logging,
`SERVER_ENGINE_LICENSE_INSECURE_SSL=1`, and
`SERVER_ENGINE_ALLOW_REMOVE_DEFAULT_RUNTIME=1`, matching the development
command below. Override individual values before the command when needed.
These flags apply only to the GUI launcher.

For IDE configuration, select:
`/Users/donghungx/Documents/GitHub/ServerEngine/.venv/bin/python`.
For dependency changes, run `.venv/bin/python -m pip install -e '.[dev]'`
from the repository. The launchers reference this checkout; update them if
the project is moved. The global Python itself does not contain the app's
dependencies; use the launchers to run the app.

---

1)
Build helper once
source .venv/bin/activate
scripts/build_privileged_helper.sh
2)
Run app (your command is correct)
source .venv/bin/activate
SERVER_ENGINE_LOG_LEVEL=INFO \
SERVER_ENGINE_LOG_STDOUT=1 \
SERVER_ENGINE_LICENSE_INSECURE_SSL=1 \
SERVER_ENGINE_ALLOW_REMOVE_DEFAULT_RUNTIME=1 \
PYTHONPATH=src python -m server_engine.main




Use one of these:
source .venv/bin/activate
pip install -e .
python -m server_engine.main


Or without installing:


SERVER_ENGINE_LOG_LEVEL=DEBUG to get more info

source .venv/bin/activate
SERVER_ENGINE_LOG_LEVEL=DEBUG \
SERVER_ENGINE_LOG_STDOUT=1 \
SERVER_ENGINE_LICENSE_INSECURE_SSL=1 \
SERVER_ENGINE_ALLOW_REMOVE_DEFAULT_RUNTIME=1 \
SERVER_ENGINE_ROOT_OSASCRIPT=1 \
SERVER_ENGINE_SPARKLE_FRAMEWORK_PATH="/opt/homebrew/Caskroom/sparkle/2.9.2/Sparkle.framework" \
SERVER_ENGINE_SPARKLE_FEED_URL="https://ninacoder.top/wp-json/server-engine/v1/app-update/appcast.xml" \
PYTHONPATH=src python -m server_engine.main


source .venv/bin/activate
SERVER_ENGINE_LICENSE_RESET=1 \
SERVER_ENGINE_LOG_LEVEL=DEBUG \
SERVER_ENGINE_LOG_STDOUT=1 \
SERVER_ENGINE_LICENSE_INSECURE_SSL=1 \
PYTHONPATH=src python -m server_engine.main









For the console script:
source .venv/bin/activate
pip install -e .
server-engine-gui
If you want the GUI to actually launch, you also need PySide6 installed:
pip install -e .
If that still fails, paste the next error.



BUILD APP (with app icon)
source .venv/bin/activate
pip install pyinstaller
chmod +x scripts/build_macos_app.sh --icon assets/AppIcon.icns



BUILD PKG (with app icon)
source .venv/bin/activate
pip install pyinstaller
chmod +x scripts/build_macos_app.sh scripts/build_macos_pkg.sh
scripts/build_macos_pkg.sh --clean --icon assets/AppIcon.icns



BUILD PKG NON SSL
source .venv/bin/activate
pip install pyinstaller
chmod +x scripts/build_macos_app.sh scripts/build_macos_pkg.sh
SERVER_ENGINE_LICENSE_INSECURE_SSL=1 scripts/build_macos_pkg.sh --clean

And for installed-app runtime test (important), also set it in launchd before opening app:

launchctl setenv SERVER_ENGINE_LICENSE_INSECURE_SSL 1
open -a "Server Engine"

Unset after testing:
launchctl unsetenv SERVER_ENGINE_LICENSE_INSECURE_SSL









scripts/build_php_runtime.sh --version <your-version> --overwrite
scripts/build_php_runtime.sh --version 7.4.33 --overwrite

fast check

PHP_DIR="prebuild/php/php7.4.33"
"$PHP_DIR/bin/php-config" --extension-dir
"$PHP_DIR/bin/php" -m | egrep "redis|memcached|apcu|imagick|intl|xdebug|Zend OPcache"
ls -1 "$("$PHP_DIR/bin/php-config" --extension-dir)" | egrep "redis.so|memcached.so|apcu.so|imagick.so|intl.so|xdebug.so|opcache.so"




scripts/build_php_runtime.sh --version 5.6.40



python scripts/runtime_uploader_gui.py



mkdir -p build/AppIcon.iconset
sips -z 16 16     assets/app-icon.png --out build/AppIcon.iconset/icon_16x16.png
sips -z 32 32     assets/app-icon.png --out build/AppIcon.iconset/icon_16x16@2x.png
sips -z 32 32     assets/app-icon.png --out build/AppIcon.iconset/icon_32x32.png
sips -z 64 64     assets/app-icon.png --out build/AppIcon.iconset/icon_32x32@2x.png
sips -z 128 128   assets/app-icon.png --out build/AppIcon.iconset/icon_128x128.png
sips -z 256 256   assets/app-icon.png --out build/AppIcon.iconset/icon_128x128@2x.png
sips -z 256 256   assets/app-icon.png --out build/AppIcon.iconset/icon_256x256.png
sips -z 512 512   assets/app-icon.png --out build/AppIcon.iconset/icon_256x256@2x.png
sips -z 512 512   assets/app-icon.png --out build/AppIcon.iconset/icon_512x512.png
sips -z 1024 1024 assets/app-icon.png --out build/AppIcon.iconset/icon_512x512@2x.png
iconutil -c icns build/AppIcon.iconset -o assets/AppIcon.icns




./scripts/build_macos_app.sh --check-env







magick assets/icon.png \
  -trim +repage \
  -resize 880x880 \
  -background none \
  -gravity center \
  -extent 1024x1024 \
  assets/app-icon.png


sudo touch /Applications/Server\ Engine.app

mkdir -p build/AppIcon.iconset
sips -z 16 16     assets/app-icon.png --out build/AppIcon.iconset/icon_16x16.png
sips -z 32 32     assets/app-icon.png --out build/AppIcon.iconset/icon_16x16@2x.png
sips -z 32 32     assets/app-icon.png --out build/AppIcon.iconset/icon_32x32.png
sips -z 64 64     assets/app-icon.png --out build/AppIcon.iconset/icon_32x32@2x.png
sips -z 128 128   assets/app-icon.png --out build/AppIcon.iconset/icon_128x128.png
sips -z 256 256   assets/app-icon.png --out build/AppIcon.iconset/icon_128x128@2x.png
sips -z 256 256   assets/app-icon.png --out build/AppIcon.iconset/icon_256x256.png
sips -z 512 512   assets/app-icon.png --out build/AppIcon.iconset/icon_256x256@2x.png
sips -z 512 512   assets/app-icon.png --out build/AppIcon.iconset/icon_512x512.png
sips -z 1024 1024 assets/app-icon.png --out build/AppIcon.iconset/icon_512x512@2x.png
iconutil -c icns build/AppIcon.iconset -o assets/AppIcon.icns




Real architecture check


find "dist/app/Server Engine.app" -type f | while IFS= read -r f; do
    if file "$f" | grep -q "Mach-O"; then
        echo "$f"
        file "$f"
        echo
    fi
done








Good. That gives you the answer.

Do **not** build the `.app` with:

```sh
/opt/homebrew/bin/python3
```

because right now that points to:

```text
Python 3.14.5
MACOSX_DEPLOYMENT_TARGET=26
```

Use one of these instead:

```text
/opt/homebrew/bin/python3.12  → target 14
/opt/homebrew/bin/python3.13  → target 14
/opt/homebrew/bin/python3.11  → target 13
```

For your app, I’d use **Python 3.12** first. It is more stable than 3.13/3.14 for packaging, Nuitka, PySide6, cryptography, and native modules.

Run this:

```sh
deactivate 2>/dev/null || true
rm -rf .venv
/opt/homebrew/bin/python3.12 -m venv .venv
source .venv/bin/activate
python --version
python -c 'import sysconfig; print(sysconfig.get_config_var("MACOSX_DEPLOYMENT_TARGET"))'
python -m pip install -U pip setuptools wheel
python -m pip install -r requirements.txt
python -m pip install nuitka
```

Then verify `math.so` before building:

```sh
python - <<'PY'
import math
print(math.__file__)
PY

otool -l "$(python - <<'PY'
import math
print(math.__file__)
PY
)" | grep -A 4 LC_BUILD_VERSION
```

You should see something like:

```text
minos 14.0
```

Then build:

```sh
MACOSX_DEPLOYMENT_TARGET=14.0 scripts/build_macos_app.sh
```

After build, check the app:

```sh
otool -l "dist/app/Server Engine.app/Contents/MacOS/math.so" | grep -A 4 LC_BUILD_VERSION
```

You want:

```text
minos 14.0
```

not:

```text
minos 26.0
```

Also check every bundled Mach-O:

```sh
find "dist/app/Server Engine.app" -type f | while IFS= read -r f; do
    if file "$f" | grep -q "Mach-O"; then
        echo "---- $f"
        file "$f"
        otool -l "$f" | awk '
            /LC_BUILD_VERSION/ { show=1 }
            show && /platform/ { print }
            show && /minos/ { print }
            show && /sdk/ { print; show=0 }
            /LC_VERSION_MIN_MACOSX/ { old=1 }
            old && /version/ { print; old=0 }
        '
    fi
done
```

If anything still says:

```text
minos 26.0
```

then that specific dependency was installed as a macOS 26 binary and needs to be replaced/reinstalled under the Python 3.12 venv.

One more important thing: update your build script so it never accidentally uses Homebrew’s default `python3`.

Change uses of:

```sh
python3
```

to:

```sh
python
```

inside the script, then always activate the venv before building.

For example:

```sh
source .venv/bin/activate
MACOSX_DEPLOYMENT_TARGET=14.0 scripts/build_macos_app.sh
```

Right now, because you have Python 3.12 available with target `14`, your fix is straightforward: recreate `.venv` with Python 3.12, reinstall dependencies, rebuild, then audit the `.app`.


when i run app (modify hosts) i see Server Engine  is trying to install a new helper tool. I enter password then i see /Library/PrivilegedHelperTools/com.serverengine.app.helper . I think that good, But after that The fucking Osasript box show and ask for password?????. then i fucking make app modify hosts again (restart apache) i see "Server Engine  is trying to install a new helper tool" again. fuck, after that osa come again too. That mean helper installed but is not being used and keep install again




/Users/lechchut/Documents/GitHub/ServerEngine/scripts/build_macos_app.sh --icon /Users/lechchut/Documents/GitHub/ServerEngine/assets/AppIcon.icns --version 1.0.1 --app-sign-identity 'Developer ID Application: Rana Noman (G54PTLH399)' --helper-sign-identity 'Developer ID Application: Rana Noman (G54PTLH399)' --no-clean
