#!/bin/zsh
# Build TerminalSpace.app in ./build.
# With --run, also stop the running copy (it saves its terminals first), then open the new build.
set -euo pipefail
cd "$(dirname "$0")"

# If the Xcode license is not accepted, use the Command Line Tools.
if ! xcrun --find swift >/dev/null 2>&1 && [[ -d /Library/Developer/CommandLineTools ]]; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi

swift build -c release
BIN="$(swift build -c release --show-bin-path)/TerminalSpace"

APP=build/TerminalSpace.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TerminalSpace"
# To change the icon, edit Scripts/make-icon.swift, then run: swift Scripts/make-icon.swift
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>TerminalSpace</string>
    <key>CFBundleIdentifier</key><string>com.coconetlabs.terminalspace</string>
    <key>CFBundleExecutable</key><string>TerminalSpace</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
# Tell Finder and the Dock that the bundle changed, so they show the current icon.
touch "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--run" ]]; then
    if pkill -TERM -x TerminalSpace; then
        # Wait until the old copy stops, so that it finishes its save.
        for _ in {1..50}; do pgrep -x TerminalSpace >/dev/null || break; sleep 0.1; done
    fi
    open "$APP"
    echo "Opened $APP"
fi
