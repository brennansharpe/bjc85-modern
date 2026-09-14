#!/bin/sh
set -eu
PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_DIR="$PROJECT_ROOT/build/BJC-85 Scanner.app"
PROCESS_CHECK=0
/usr/bin/pgrep -f "$APP_DIR/Contents/MacOS/BJC85Scanner" >/dev/null || PROCESS_CHECK=$?
if [ "$PROCESS_CHECK" -eq 0 ]; then
    echo 'Quit BJC-85 Scanner before rebuilding it.' >&2
    exit 1
elif [ "$PROCESS_CHECK" -ne 1 ]; then
    echo 'Cannot verify that the scanner app is stopped; build from a terminal with process-list access.' >&2
    exit 1
fi
HELPER_CHECK=0
/usr/bin/pgrep -f "$APP_DIR/Contents/Helpers/" >/dev/null || HELPER_CHECK=$?
[ "$HELPER_CHECK" -eq 1 ] || { echo 'Stop the native scanner service and helper processes before rebuilding.' >&2; exit 1; }
USB_CHECK=0
/usr/bin/pgrep -x bjc85-is12 >/dev/null || USB_CHECK=$?
[ "$USB_CHECK" -eq 1 ] || { echo 'Wait for native scanner commands to finish before rebuilding.' >&2; exit 1; }
cmake --build "$PROJECT_ROOT/build" --target bjc85-is12 -j 4
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Helpers" "$APP_DIR/Contents/Frameworks"
mkdir -p "$APP_DIR/Contents/Resources/Licenses"
cp /opt/homebrew/opt/libusb/COPYING "$APP_DIR/Contents/Resources/Licenses/libusb-COPYING.txt"
cp /opt/homebrew/opt/libusb/AUTHORS "$APP_DIR/Contents/Resources/Licenses/libusb-AUTHORS.txt"
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library -target arm64-apple-macos14.0 \
    -module-cache-path "$PROJECT_ROOT/build/swift-module-cache" \
    -framework AppKit -framework ImageIO -framework UniformTypeIdentifiers \
    "$PROJECT_ROOT/app/BJC85Scanner.swift" "$PROJECT_ROOT/app/ScanExport.swift" \
    "$PROJECT_ROOT/app/LiveScanPreview.swift" -o "$APP_DIR/Contents/MacOS/BJC85Scanner"
cp "$PROJECT_ROOT/build/bjc85-is12" "$APP_DIR/Contents/Helpers/bjc85-is12"
/usr/bin/install -m 755 /opt/homebrew/opt/libusb/lib/libusb-1.0.0.dylib "$APP_DIR/Contents/Frameworks/libusb-1.0.0.dylib"
/usr/bin/install_name_tool -id @rpath/libusb-1.0.0.dylib "$APP_DIR/Contents/Frameworks/libusb-1.0.0.dylib"
/usr/bin/install_name_tool -change /opt/homebrew/opt/libusb/lib/libusb-1.0.0.dylib \
    @executable_path/../Frameworks/libusb-1.0.0.dylib "$APP_DIR/Contents/Helpers/bjc85-is12"
/usr/bin/xcrun clang -arch arm64 -mmacosx-version-min=14.0 -Wall -Wextra -Werror \
    -c "$PROJECT_ROOT/src/escl_publish.c" -o "$PROJECT_ROOT/build/escl_publish.o"
/usr/bin/xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 \
    -module-cache-path "$PROJECT_ROOT/build/swift-module-cache" \
    -import-objc-header "$PROJECT_ROOT/src/escl_publish.h" -framework Network -framework ImageIO \
    "$PROJECT_ROOT/src/escl_bridge.swift" "$PROJECT_ROOT/build/escl_publish.o" \
    -o "$APP_DIR/Contents/Helpers/is12-escl-bridge"
PLIST="$APP_DIR/Contents/Info.plist"
cat > "$PLIST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.bjc85.scanner</string>
<key>CFBundleName</key><string>BJC-85 Scanner</string>
<key>CFBundleExecutable</key><string>BJC85Scanner</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
/usr/bin/plutil -insert BJC85ProjectRoot -string "$PROJECT_ROOT" "$PLIST"
/usr/bin/codesign --force --sign - "$APP_DIR/Contents/Frameworks/libusb-1.0.0.dylib"
/usr/bin/codesign --force --sign - "$APP_DIR/Contents/Helpers/bjc85-is12"
/usr/bin/codesign --force --sign - "$APP_DIR/Contents/Helpers/is12-escl-bridge"
/usr/bin/codesign --force --sign - "$APP_DIR"
/usr/bin/codesign --verify --deep --strict "$APP_DIR"
/usr/bin/file "$APP_DIR/Contents/MacOS/BJC85Scanner" "$APP_DIR/Contents/Helpers/bjc85-is12"
