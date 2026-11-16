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
PKG="build/DevTasks-${VERSION}.pkg"

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

echo "==> building installer ${PKG}"
rm -rf build/pkgroot build/pkg && mkdir -p build/pkgroot/Applications build/pkg
ditto --norsrc --noextattr build/DevTasks.app build/pkgroot/Applications/DevTasks.app
xattr -cr build/pkgroot
codesign --verify --deep build/pkgroot/Applications/DevTasks.app
pkgbuild --analyze --root build/pkgroot build/pkg/components.plist >/dev/null
# Always install to /Applications, even if another copy of the app exists elsewhere on disk.
plutil -replace 0.BundleIsRelocatable -bool NO build/pkg/components.plist
pkgbuild --root build/pkgroot --component-plist build/pkg/components.plist \
  --identifier dev.local.devtasks.pkg --version "$VERSION" --install-location / \
  --scripts packaging/scripts build/pkg/DevTasks-component.pkg >/dev/null
sed "s/__VERSION__/${VERSION}/g" packaging/distribution.xml > build/pkg/distribution.xml
productbuild --distribution build/pkg/distribution.xml --resources packaging/resources \
  --package-path build/pkg "$PKG" >/dev/null
ls -lh "$ZIP" "$PKG"

if [ -n "${DRY_RUN:-}" ]; then echo "dry run: not publishing"; exit 0; fi

echo "==> publishing ${TAG}"
{ [ -f packaging/whats-new.md ] && { echo "## What's new"; echo; cat packaging/whats-new.md; echo; }; } > build/release-notes.md || true
cat >> build/release-notes.md <<MD
## Install

Download **DevTasks-${VERSION}.pkg** below and double-click it. The installer puts DevTasks in Applications,
adds the \`devtasks\` command and the Claude Code skill, then opens the app. No Xcode needed. macOS 14+.

**First time only:** DevTasks isn't signed with a paid Apple Developer ID, so macOS says it can't verify the developer.
Click **Done**, open **System Settings > Privacy & Security**, click **Open Anyway** next to DevTasks, then open the .pkg again.

## Update

Already have DevTasks 1.2 or newer? Use **DevTasks > Check for Updates** (or \`devtasks update\`).
Your tasks and notes are kept in \`~/Library/Application Support/DevTasks\` and are never touched.

The \`.zip\` is used by the in-app updater; you don't need to download it.
MD
git tag "$TAG"
git push origin "$TAG"
gh release create "$TAG" "$PKG" "$ZIP" --title "DevTasks ${VERSION}" --notes-file build/release-notes.md
