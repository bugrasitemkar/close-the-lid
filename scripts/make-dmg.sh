#!/bin/bash
# Packages dist/Close The Lid.app into dist/CloseTheLid.dmg (drag-to-Applications layout).
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/Close The Lid.app"
DMG="dist/CloseTheLid.dmg"
[ -d "$APP" ] || ./scripts/build-app.sh

STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Close The Lid" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
echo "Created $DMG"
