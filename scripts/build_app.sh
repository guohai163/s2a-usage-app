#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/CodexUsage.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MODULE_CACHE_DIR="$BUILD_DIR/module-cache"
SDK_PATH="$(xcrun --show-sdk-path)"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$MODULE_CACHE_DIR"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" swiftc \
  "$ROOT_DIR"/Sources/CodexUsageApp/main.swift \
  "$ROOT_DIR"/Sources/CodexUsageApp/Models/*.swift \
  "$ROOT_DIR"/Sources/CodexUsageApp/Services/*.swift \
  "$ROOT_DIR"/Sources/CodexUsageApp/UI/*.swift \
  "$ROOT_DIR"/Sources/CodexUsageApp/Utilities/*.swift \
  -o "$MACOS_DIR/CodexUsage" \
  -target arm64-apple-macosx15.0 \
  -sdk "$SDK_PATH" \
  -framework AppKit \
  -framework Foundation

cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
cp "$ROOT_DIR/Resources/default-menu-render.json" "$RESOURCES_DIR/default-menu-render.json"

echo "Built: $APP_DIR"
