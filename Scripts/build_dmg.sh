#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_PATH="$BUILD_DIR/Build/Products/Release/FileHound.app"
DMG_DIR="$BUILD_DIR/dmg"
DMG_PATH="$DMG_DIR/FileHound.dmg"

mkdir -p "$DMG_DIR"

xcodebuild \
  -project "$ROOT_DIR/FileHound.xcodeproj" \
  -scheme FileHound \
  -configuration Release \
  -destination 'platform=macOS' \
  build

create_pretty_dmg.sh "$APP_PATH" "$DMG_PATH"

printf 'DMG created at %s\n' "$DMG_PATH"
