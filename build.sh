#!/bin/bash
# Builds "MailLi.app" (מייל לי for Mac) next to this script.
#   ./build.sh          → app for this Mac only (fast)
#   ./build.sh --dist   → universal app (Apple Silicon + Intel) and MailLi.dmg to share
set -euo pipefail
cd "$(dirname "$0")"

DIST=0
[ "${1:-}" = "--dist" ] && DIST=1
VERSION="1.1"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ $DIST = 1 ]; then
  for arch in arm64 x86_64; do
    swift build -c release --triple "$arch-apple-macosx14.0"
    cp "$(swift build -c release --triple "$arch-apple-macosx14.0" --show-bin-path)/MailLi" "$TMP/MailLi-$arch"
  done
  lipo -create "$TMP/MailLi-arm64" "$TMP/MailLi-x86_64" -output "$TMP/MailLi"
else
  swift build -c release
  cp "$(swift build -c release --show-bin-path)/MailLi" "$TMP/MailLi"
fi

APP="MailLi.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$TMP/MailLi" "$APP/Contents/MacOS/MailLi"
strip -x "$APP/Contents/MacOS/MailLi" 2>/dev/null || true
# App icon from our own artwork (dist/art/icon_1024.png, drawn by dist/make_art.swift).
if [ -f dist/art/icon_1024.png ]; then
  ICONSET="$TMP/AppIcon.iconset"; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s dist/art/icon_1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) dist/art/icon_1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  mkdir -p Resources && iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>MailLi</string>
  <key>CFBundleDisplayName</key><string>מייל לי</string>
  <key>CFBundleIdentifier</key><string>local.mailli.mac</string>
  <key>CFBundleExecutable</key><string>MailLi</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleDevelopmentRegion</key><string>he</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.education</string>
  <key>NSHumanReadableCopyright</key><string>Unofficial Mac client for the MailLi service. Not affiliated with Googale.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature (no Apple Developer ID): macOS will ask the user to allow it once.
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $(pwd)/$APP ($(lipo -archs "$APP/Contents/MacOS/MailLi"))"

if [ $DIST = 1 ]; then
  # DMG with a drag-to-Applications window (background picture + icon layout).
  VOL="מייל לי"
  [ -d "/Volumes/$VOL" ] && hdiutil detach "/Volumes/$VOL" -force >/dev/null 2>&1 || true
  STAGE="$TMP/dmg"
  mkdir -p "$STAGE/.background"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  cp "dist/קראו אותי - התקנה.txt" "$STAGE/"
  tiffutil -cathidpicheck dist/art/dmg_background.png "dist/art/dmg_background@2x.png" \
    -out "$STAGE/.background/background.tiff" >/dev/null

  hdiutil create -volname "$VOL" -srcfolder "$STAGE" -fs HFS+ -format UDRW -size 20m -ov "$TMP/rw.dmg" >/dev/null
  DEV="$(hdiutil attach -readwrite -noverify -noautoopen "$TMP/rw.dmg" | awk '/Apple_HFS/ {print $1}')"
  if ! osascript dist/dmg_layout.applescript "$VOL"; then
    echo "WARNING: could not arrange the DMG window (allow Terminal to control Finder and run again)."
  fi
  # Disk icon goes on after the layout (Finder removes it while arranging the window).
  cp Resources/AppIcon.icns "/Volumes/$VOL/.VolumeIcon.icns"
  SetFile -a C "/Volumes/$VOL" || true
  sync
  hdiutil detach "$DEV" >/dev/null
  rm -f MailLi.dmg
  hdiutil convert "$TMP/rw.dmg" -format UDZO -imagekey zlib-level=9 -o MailLi.dmg >/dev/null
  echo "Built $(pwd)/MailLi.dmg ($(du -h MailLi.dmg | cut -f1))"
fi
