#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/build/Codex Usage.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/module-cache
PYTHON_PATH="$(command -v python3)"
"$PYTHON_PATH" -c 'import sys; assert sys.version_info >= (3, 9), "Python 3.9+ required"'
for arch in arm64 x86_64; do
    swiftc Sources/main.swift -target "${arch}-apple-macosx13.0" -o "build/CodexUsage-${arch}" -framework AppKit -framework SwiftUI -module-cache-path "$PWD/build/module-cache" -O
done
lipo -create build/CodexUsage-arm64 build/CodexUsage-x86_64 -output "$APP/Contents/MacOS/CodexUsage"
strip -S "$APP/Contents/MacOS/CodexUsage"
mkdir -p build/AppIcon.iconset
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Assets/AppIcon.png --out "build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" Assets/AppIcon.png --out "build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cp scripts/fetch_usage.py "$APP/Contents/Resources/fetch_usage.py"
"$PYTHON_PATH" - "$APP/Contents/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as file:
    plistlib.dump({'CFBundleExecutable': 'CodexUsage', 'CFBundleIdentifier': 'local.codexusage.menubar',
                  'CFBundleName': 'Codex Usage', 'CFBundleDisplayName': 'Codex Usage',
                  'CFBundleIconFile': 'AppIcon', 'CFBundleVersion': '3', 'CFBundleShortVersionString': '1.1',
                  'CFBundlePackageType': 'APPL', 'LSUIElement': True,
                  'LSMinimumSystemVersion': '13.0', 'NSHighResolutionCapable': True}, file)
PY
# Finder metadata can be added by synced project folders and blocks signing.
xattr -dr com.apple.FinderInfo "$APP" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$APP" 2>/dev/null || true
codesign --force --sign - "$APP"
printf 'Built %s\n' "$APP"
