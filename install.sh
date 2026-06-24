#!/bin/bash
#
# Build AudioPriority (Release) and install it into /Applications.
#
# Installing to a stable location matters: "Launch at Login" registers the
# *running* bundle's path via SMAppService, so the app must live somewhere
# permanent (not Xcode's DerivedData) for the login item to keep working.
#
# Usage:  ./install.sh          # build + install + launch
#         ./install.sh --no-run # build + install only

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEME="AudioPriority"
APP_NAME="AudioPriority.app"
DEST="/Applications/${APP_NAME}"

echo "▶ Building ${SCHEME} (Release)…"
DERIVED="$(mktemp -d)"
xcodebuild \
  -project "${PROJECT_DIR}/AudioPriority.xcodeproj" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -derivedDataPath "${DERIVED}" \
  build \
  >/dev/null

BUILT="${DERIVED}/Build/Products/Release/${APP_NAME}"
if [[ ! -d "${BUILT}" ]]; then
  echo "✗ Build did not produce ${BUILT}" >&2
  exit 1
fi

echo "▶ Installing to ${DEST}…"
# If a previous copy is running, quit it so the bundle can be replaced.
osascript -e 'tell application "AudioPriority" to quit' 2>/dev/null || true
sleep 1
rm -rf "${DEST}"
cp -R "${BUILT}" "${DEST}"

# Refresh Launch Services so Finder/Spotlight pick up the new icon & bundle.
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
  -f "${DEST}" >/dev/null 2>&1 || true

echo "✓ Installed ${DEST}"

if [[ "${1:-}" != "--no-run" ]]; then
  echo "▶ Launching…"
  open "${DEST}"
fi

rm -rf "${DERIVED}"
echo "Done. AudioPriority lives in your menu bar (no Dock icon)."
