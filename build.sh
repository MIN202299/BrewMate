#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

echo "==> swift build -c release"
swift build -c release

APP="BrewMate.app"
BIN_NAME="BrewMate"
BIN_PATH=".build/release/$BIN_NAME"

if [ ! -f "$BIN_PATH" ]; then
    echo "Build produced no binary at $BIN_PATH" >&2
    exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/$BIN_NAME"
cp Sources/BrewMate/Resources/Info.plist "$APP/Contents/Info.plist"

# 若没有 .icns 或 iconset 比 icns 更新，则重新生成
if [ ! -f assets/BrewMate.icns ] \
   || [ tools/make_icon.swift -nt assets/BrewMate.icns ]; then
    echo "==> regenerate icon"
    swift tools/make_icon.swift
    iconutil -c icns assets/BrewMate.iconset -o assets/BrewMate.icns
fi
cp assets/BrewMate.icns "$APP/Contents/Resources/BrewMate.icns"

echo "==> ad-hoc codesign"
codesign --force --deep --sign - "$APP"

echo ""
echo "Built: $(pwd)/$APP"
echo "Run:   open \"$(pwd)/$APP\""
echo "Install: mv \"$(pwd)/$APP\" /Applications/"
