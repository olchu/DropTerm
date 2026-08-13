#!/bin/zsh

set -euo pipefail

ROOT_DIR=${0:A:h:h}
DERIVED_DATA_PATH=${DERIVED_DATA_PATH:-/private/tmp/DropTerm-DMG}
DIST_DIR=${DIST_DIR:-$ROOT_DIR/dist}
APP_PATH=$DERIVED_DATA_PATH/Build/Products/Release/DropTerm.app
STAGING_DIR=$(mktemp -d /private/tmp/DropTerm-staging.XXXXXX)
DMG_PATH=$DIST_DIR/DropTerm.dmg

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

mkdir -p "$DIST_DIR"

xcodebuild \
  -project "$ROOT_DIR/DropTerm.xcodeproj" \
  -scheme DropTerm \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -destination 'generic/platform=macOS' \
  build

ditto "$APP_PATH" "$STAGING_DIR/DropTerm.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname DropTerm \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "$DMG_PATH"
