#!/bin/bash
# Builds DevTasks.app from source. Requires Xcode or the Command Line Tools
# (install with: xcode-select --install).
#   ./build.sh            -> build/DevTasks.app
#   ./build.sh --install  -> also copies it to /Applications
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="DevTasks"
APP="build/${APP_NAME}.app"

echo "==> compiling (release)"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/${APP_NAME}"

echo "==> assembling ${APP}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/${APP_NAME}"
cp Resources/fa-solid-900.ttf "$APP/Contents/Resources/"
cp Resources/fa-brands-400.ttf "$APP/Contents/Resources/"
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
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
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
  echo "==> installing to /Applications"
  rm -rf "/Applications/${APP_NAME}.app"
  cp -R "$APP" /Applications/
  echo "done: /Applications/${APP_NAME}.app"

  # CLI: `devtasks` on PATH, pointing at the installed app binary.
  BIN_DIR=/usr/local/bin
  [ -w "$BIN_DIR" ] || BIN_DIR="$HOME/.local/bin"
  mkdir -p "$BIN_DIR"
  ln -sf "/Applications/${APP_NAME}.app/Contents/MacOS/${APP_NAME}" "$BIN_DIR/devtasks"
  echo "cli:  $BIN_DIR/devtasks"
  case ":$PATH:" in *":$BIN_DIR:"*) ;; *) echo "      note: add $BIN_DIR to your PATH" ;; esac

  # Claude Code skill (only if Claude Code is set up on this Mac).
  if [ -d "$HOME/.claude" ]; then
    mkdir -p "$HOME/.claude/skills"
    rm -rf "$HOME/.claude/skills/devtasks"
    cp -R agent/skills/devtasks "$HOME/.claude/skills/devtasks"
    echo "skill: ~/.claude/skills/devtasks"
  fi
else
  echo "done: $(pwd)/${APP}"
  echo "run:  open \"${APP}\"   (or ./build.sh --install)"
fi
