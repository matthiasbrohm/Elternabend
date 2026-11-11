#!/bin/bash
# Baut „Elternabend Abgleich.app“ (für Apple-Chips und Intel) und packt sie als ZIP nach build/.
# Läuft auf einem Mac mit Xcode – bei uns über GitHub Actions (.github/workflows/mac-app.yml).
set -euo pipefail
cd "$(dirname "$0")"
VERSION="$(tr -d '[:space:]' < VERSION)"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/ElternabendAbgleich"

APP="build/Elternabend Abgleich.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ElternabendAbgleich"
sed "s/@VERSION@/$VERSION/g" Info.plist > "$APP/Contents/Info.plist"

# Programmsymbol aus icon.png (1024 × 1024)
ICONSET="build/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z "$s" "$s" icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z "$d" "$d" icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

# Ohne Apple-Entwicklerkonto: nur „ad hoc“ signiert (beim ersten Öffnen einmal bestätigen)
codesign --force --sign - "$APP"
codesign --verify --verbose "$APP"
lipo -archs "$APP/Contents/MacOS/ElternabendAbgleich"

(cd build && ditto -c -k --keepParent "Elternabend Abgleich.app" "Elternabend-Abgleich-$VERSION.zip")
ls -la build
