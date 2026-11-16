#!/bin/bash
# Builds DevTasks.app from source. Requires Xcode or the Command Line Tools
# (install with: xcode-select --install).
#   ./build.sh               -> build/DevTasks.app (this Mac's architecture)
#   ./build.sh --install     -> also installs the app, the `devtasks` CLI and the Claude skill
#   UNIVERSAL=1 ./build.sh   -> one app that runs on Apple Silicon and Intel
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="DevTasks"
APP="build/${APP_NAME}.app"
VERSION="${APP_VERSION:-$(cat VERSION 2>/dev/null || echo 0.0.0)}"

mkdir -p build
if [ "${UNIVERSAL:-0}" = "1" ]; then
  echo "==> compiling arm64 + x86_64 (release, v${VERSION})"
  swift build -c release --triple arm64-apple-macosx14.0
  swift build -c release --triple x86_64-apple-macosx14.0
  lipo -create -output "build/${APP_NAME}.bin" \
    ".build/arm64-apple-macosx/release/${APP_NAME}" \
    ".build/x86_64-apple-macosx/release/${APP_NAME}"
else
  echo "==> compiling (release, v${VERSION})"
  swift build -c release
  cp "$(swift build -c release --show-bin-path)/${APP_NAME}" "build/${APP_NAME}.bin"
fi

echo "==> assembling ${APP}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mv "build/${APP_NAME}.bin" "$APP/Contents/MacOS/${APP_NAME}"
cp Resources/fa-solid-900.ttf Resources/fa-brands-400.ttf "$APP/Contents/Resources/"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>dev.local.devtasks</string>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

echo "==> signing (ad-hoc)"
codesign --force --deep --sign - "$APP" >/dev/null

if [ "${1:-}" = "--install" ]; then
  ./install.sh "$APP" agent/skills/devtasks
else
  echo "done: $(pwd)/${APP}"
  echo "run:  open \"${APP}\"   (or ./build.sh --install)"
fi
