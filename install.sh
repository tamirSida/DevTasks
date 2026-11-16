#!/bin/bash
# Installs DevTasks: the app into /Applications, the `devtasks` CLI on your PATH,
# and the Claude Code skill (if Claude Code is set up).
#
# From a downloaded release zip:   cd DevTasks && ./install.sh
# From source this runs as part of ./build.sh --install
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
APP="${1:-$DIR/DevTasks.app}"
SKILL="${2:-$DIR/agent/skills/devtasks}"
[ -d "$APP" ] || { echo "DevTasks.app not found at $APP"; exit 1; }

# Quit a running copy so it can be replaced.
osascript -e 'quit app "DevTasks"' >/dev/null 2>&1 || true

echo "==> installing to /Applications"
rm -rf /Applications/DevTasks.app
cp -R "$APP" /Applications/
# Downloaded apps without an Apple Developer ID signature are blocked by Gatekeeper; clear the download flag.
xattr -dr com.apple.quarantine /Applications/DevTasks.app 2>/dev/null || true
echo "app:   /Applications/DevTasks.app"

BIN_DIR=/usr/local/bin
[ -w "$BIN_DIR" ] || BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
ln -sf /Applications/DevTasks.app/Contents/MacOS/DevTasks "$BIN_DIR/devtasks"
echo "cli:   $BIN_DIR/devtasks"
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) echo "       note: add $BIN_DIR to your PATH (echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.zshrc)";; esac

if [ -d "$HOME/.claude" ] && [ -d "$SKILL" ]; then
  mkdir -p "$HOME/.claude/skills"
  rm -rf "$HOME/.claude/skills/devtasks"
  cp -R "$SKILL" "$HOME/.claude/skills/devtasks"
  echo "skill: ~/.claude/skills/devtasks"
fi
echo "done. open it with: open -a DevTasks"
