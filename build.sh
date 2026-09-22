#!/bin/bash
# Builds "Todo List.app" from source. No Xcode project, no dependencies —
# just the Swift compiler from the Command Line Tools.
#
#   ./build.sh            build into build/
#   ./build.sh --install  build, then replace /Applications/Todo List.app and launch it
set -euo pipefail

INSTALL=false
[[ "${1:-}" == "--install" ]] && INSTALL=true

cd "$(dirname "$0")"

# Override to install under another name, e.g. APP_NAME=Tasks ./build.sh --install
APP_NAME="${APP_NAME:-Todo List}"
EXECUTABLE="TodoList"
BUNDLE_ID="com.jasonpitchford.todolist"
VERSION="1.0"

BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP/Contents/MacOS"
RES_DIR="$APP/Contents/Resources"

echo "==> Cleaning"
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"

echo "==> Compiling Swift sources"
xcrun swiftc \
  -O \
  -swift-version 5 \
  -target "$(uname -m)-apple-macos13.0" \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  Sources/*.swift \
  -o "$MACOS_DIR/$EXECUTABLE"

echo "==> Rendering app icon"
ICONSET="$BUILD_DIR/AppIcon.iconset"
xcrun swift tools/MakeIcon.swift "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$RES_DIR/AppIcon.icns"
rm -rf "$ICONSET"

echo "==> Writing Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>       <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>        <string>$EXECUTABLE</string>
    <key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key>           <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>    <string>13.0</string>
    <key>LSApplicationCategoryType</key> <string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key>   <true/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP"

# Make Finder pick up the fresh icon and bundle metadata.
touch "$APP"

echo "==> Built $APP"

if $INSTALL; then
  # The login item and the hotkey belong to whichever copy is running, so
  # quit the old one before swapping it out.
  echo "==> Installing to /Applications"
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || true
  # Launching again before the old copy has exited fails with error -600.
  for _ in {1..50}; do
    pgrep -f "/Applications/$APP_NAME.app/" >/dev/null || break
    sleep 0.1
  done
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" /Applications/
  open "/Applications/$APP_NAME.app"
  echo "==> Installed and launched /Applications/$APP_NAME.app"
fi
