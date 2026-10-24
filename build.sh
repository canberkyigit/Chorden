#!/bin/bash
# Builds Chorden.app.   ./build.sh          → build/Chorden.app (for this Mac's CPU)
#                     ./build.sh install  → also copies it to /Applications
#                     ./build.sh dist     → universal (Apple Silicon + Intel) build/Chorden.zip for releases
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-}"
APP=build/Chorden.app
BIN="$APP/Contents/MacOS/Chorden"
FLAGS=(-O -wmo -D RELEASE)
ARCHS=("$(uname -m)")
[[ "$MODE" == "dist" ]] && ARCHS=(arm64 x86_64)

if [[ ! -f Resources/AppIcon.icns ]]; then
    echo "→ Generating icon"
    rm -rf build/AppIcon.iconset
    mkdir -p build
    swift tools/make_icon.swift build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi

echo "→ Compiling (${ARCHS[*]})"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
SLICES=()
for arch in "${ARCHS[@]}"; do
    swiftc "${FLAGS[@]}" -swift-version 5 -target "$arch-apple-macos13.0" \
        -Xlinker -dead_strip \
        Sources/*.swift -o "build/Chorden-$arch"
    SLICES+=("build/Chorden-$arch")
done
lipo -create "${SLICES[@]}" -output "$BIN"
rm -f "${SLICES[@]}"
strip -x "$BIN"

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/Samples "$APP/Contents/Resources/Samples"
codesign --force --sign - "$APP" 2>/dev/null

echo "✓ Built $APP ($(du -sh "$APP" | cut -f1))"

if [[ "$MODE" == "install" ]]; then
    osascript -e 'quit app "Chorden"' 2>/dev/null || true
    rm -rf /Applications/Chorden.app
    cp -R "$APP" /Applications/
    echo "✓ Installed to /Applications/Chorden.app"
fi

if [[ "$MODE" == "dist" ]]; then
    rm -f build/Chorden.zip
    ditto -c -k --keepParent "$APP" build/Chorden.zip
    echo "✓ Packaged build/Chorden.zip ($(du -sh build/Chorden.zip | cut -f1))"
fi
