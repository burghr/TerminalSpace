#!/bin/sh
# Makes build/TerminalSpace.dmg from a TerminalSpace.app: a disk image with the
# app, an Applications link, and a background that says what to do. Signs the
# disk image with the Developer ID. With --notarize, Apple notarizes the disk
# image and the ticket is stapled to it.
#
# Usage: Scripts/make-dmg.sh [--notarize] [path/to/TerminalSpace.app]
# The default app is build/TerminalSpace.app. Notarize the app first (the
# notarize-mac-app skill), so that the app in the image has its own ticket.
# The file name has no version, so that the link
# releases/latest/download/TerminalSpace.dmg always gives the newest image.
#
# Uses only macOS tools: hdiutil makes the image, and Finder (through
# AppleScript) sets the window layout. The first run can ask for permission to
# control Finder. Adapted from scripts/make-dmg.sh in iOdus.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NOTARIZE=0
if [ "${1:-}" = "--notarize" ]; then NOTARIZE=1; shift; fi
APP=${1:-"$ROOT/build/TerminalSpace.app"}
NOTARY_PROFILE=${NOTARY_PROFILE:-iodus-notary}
[ -d "$APP" ] || { echo "Missing $APP. Run ./build.sh first." >&2; exit 1; }

IDENTITY=${IDENTITY:-$(security find-identity -v -p codesigning |
  sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}
[ -n "$IDENTITY" ] || { echo "No Developer ID Application identity in the keychain." >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
mkdir -p "$ROOT/build"
DMG="$ROOT/build/TerminalSpace.dmg"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "== Background"
swift "$ROOT/Scripts/dmg/background.swift" "$WORK/background.png" 1
swift "$ROOT/Scripts/dmg/background.swift" "$WORK/background@2x.png" 2
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$WORK/background.tiff" >/dev/null

echo "== Disk image $DMG ($VERSION)"
VOLUME="TerminalSpace $VERSION"
if [ -d "/Volumes/$VOLUME" ]; then
  echo "A disk named $VOLUME is mounted. Eject it first." >&2; exit 1
fi
STAGE="$WORK/stage"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/TerminalSpace.app"
ln -s /Applications "$STAGE/Applications"
cp "$WORK/background.tiff" "$STAGE/.background/background.tiff"
hdiutil create -quiet -srcfolder "$STAGE" -volname "$VOLUME" -fs HFS+ -format UDRW "$WORK/rw.dmg"
hdiutil attach -quiet -readwrite -noverify -noautoopen "$WORK/rw.dmg"
MOUNT="/Volumes/$VOLUME"

# The window: 640 x 400 points (the size of background.swift), icons at the
# arrow ends. Finder writes this layout to .DS_Store on the image.
osascript <<OSA
tell application "Finder"
  tell disk "$VOLUME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    try
      set pathbar visible of container window to false
    end try
    set sidebar width of container window to 0
    set bounds of container window to {200, 120, 840, 520}
    set options to icon view options of container window
    set arrangement of options to not arranged
    set icon size of options to 128
    set text size of options to 13
    set background picture of options to file ".background:background.tiff"
    set position of item "TerminalSpace.app" of container window to {170, 200}
    set position of item "Applications" of container window to {470, 200}
    update without registering applications
    delay 1
    close
    -- Open again and set the size once more: Finder saves the size of the
    -- last window state in .DS_Store.
    open
    set bounds of container window to {200, 120, 840, 520}
    delay 2
    close
  end tell
end tell
OSA
chflags hidden "$MOUNT/.background"
sync
hdiutil detach -quiet "$MOUNT" || { sleep 3; hdiutil detach -force -quiet "$MOUNT"; }
rm -f "$DMG"
hdiutil convert -quiet "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG"

echo "== Sign with: $IDENTITY"
codesign --force --timestamp -s "$IDENTITY" "$DMG"
codesign --verify --strict "$DMG" && echo "Signature OK"

if [ "$NOTARIZE" = 1 ]; then
  echo "== Notarize (profile $NOTARY_PROFILE)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature -vv "$DMG"
fi
ls -lh "$DMG"
