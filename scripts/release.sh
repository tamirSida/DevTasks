#!/bin/bash
# Builds a universal DevTasks.app, zips it with install.sh + the Claude skill,
# and publishes it as a GitHub Release (needs the gh CLI, logged in).
#   scripts/release.sh            -> uses the version in VERSION
#   scripts/release.sh 1.2.0      -> sets VERSION to 1.2.0 first
#   DRY_RUN=1 scripts/release.sh  -> build the zip only, don't publish
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -n "${1:-}" ]; then echo "${1#v}" > VERSION; fi
VERSION="$(cat VERSION)"
TAG="v${VERSION}"
ZIP="build/DevTasks-${VERSION}-macOS.zip"

if [ -z "${DRY_RUN:-}" ]; then
  [ -z "$(git status --porcelain)" ] || { echo "commit your changes first (git status is not clean)"; exit 1; }
  ! git rev-parse "$TAG" >/dev/null 2>&1 || { echo "tag $TAG already exists; bump the version"; exit 1; }
fi

UNIVERSAL=1 APP_VERSION="$VERSION" ./build.sh

echo "==> packaging ${ZIP}"
STAGE="build/stage/DevTasks"
rm -rf build/stage "$ZIP"
mkdir -p "$STAGE/agent/skills"
cp -R build/DevTasks.app "$STAGE/"
cp install.sh "$STAGE/"
cp -R agent/skills/devtasks "$STAGE/agent/skills/"
cat > "$STAGE/README.txt" <<TXT
DevTasks ${VERSION}

Install (Terminal):
  cd ~/Downloads/DevTasks
  ./install.sh

This copies the app to /Applications, adds the \`devtasks\` command and the Claude Code skill.
Works on Apple Silicon and Intel Macs, macOS 14 or newer.
Source and docs: https://github.com/tamirSida/DevTasks
TXT
ditto -c -k --norsrc --noextattr --keepParent "$STAGE" "$ZIP"
ls -lh "$ZIP"

if [ -n "${DRY_RUN:-}" ]; then echo "dry run: not publishing"; exit 0; fi

echo "==> publishing ${TAG}"
NOTES=$(cat <<MD
## Install

1. Download **DevTasks-${VERSION}-macOS.zip** below and double-click it to unzip.
2. In Terminal:
   \`\`\`bash
   cd ~/Downloads/DevTasks
   ./install.sh
   \`\`\`

That installs the app to /Applications, the \`devtasks\` CLI, and the Claude Code skill.
Universal build (Apple Silicon + Intel), macOS 14+.

The app is not signed with an Apple Developer ID, so \`install.sh\` clears the macOS download flag.
If you only drag the app to Applications instead, macOS will block it: open **System Settings > Privacy & Security** and click **Open Anyway**.

Your tasks are kept in \`~/Library/Application Support/DevTasks\`, so updating never touches them.
MD
)
git tag "$TAG"
git push origin "$TAG"
gh release create "$TAG" "$ZIP" --title "DevTasks ${VERSION}" --notes "$NOTES"
