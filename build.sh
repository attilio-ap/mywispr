#!/bin/bash
# Builds MyWispr, bundles it as a .app, ad-hoc signs it and installs it to /Applications.
#
# Usage:
#   ./build.sh               build and install to /Applications
#   ./build.sh --no-install  build only, leaving MyWispr.app in the project folder
set -euo pipefail

INSTALL=1
if [ "${1:-}" = "--no-install" ]; then
    INSTALL=0
fi

echo "=== Building MyWispr for macOS (Apple Silicon) ==="

# Quit any running instance so the binary is not locked while we overwrite it.
if pgrep -x "MyWispr" > /dev/null; then
    echo "Closing the running MyWispr instance..."
    killall "MyWispr" 2>/dev/null || true
    sleep 0.5
fi

SOURCES="main.swift AppState.swift Localization.swift Theme.swift KeyboardManager.swift SpeechManager.swift OllamaManager.swift PasteManager.swift OverlayWindow.swift DashboardView.swift Logger.swift"
OUTPUT_BINARY="MyWispr"
APP_NAME="MyWispr.app"

SDK_PATH=$(xcrun --show-sdk-path --sdk macosx)

echo "Compiling..."
swiftc -O \
    -sdk "$SDK_PATH" \
    -target arm64-apple-macosx13.0 \
    $SOURCES \
    -o "$OUTPUT_BINARY"

echo "Assembling the bundle ($APP_NAME)..."
rm -rf "$APP_NAME"
mkdir -p "$APP_NAME/Contents/MacOS"
mv "$OUTPUT_BINARY" "$APP_NAME/Contents/MacOS/"

if [ ! -f "Info.plist" ]; then
    echo "Error: Info.plist not found."
    exit 1
fi
cp Info.plist "$APP_NAME/Contents/"

mkdir -p "$APP_NAME/Contents/Resources"

if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "$APP_NAME/Contents/Resources/"
    echo "Application icon bundled."
fi

# Localized permission strings. macOS resolves these against the SYSTEM language
# before the app runs, so they cannot follow the in-app language toggle.
if [ -d "Resources" ]; then
    cp -R Resources/*.lproj "$APP_NAME/Contents/Resources/"
    echo "Localizations bundled: $(ls -d Resources/*.lproj | xargs -n1 basename | tr '\n' ' ')"
fi

# Ad-hoc signature. This is REQUIRED for the Accessibility permission to stick:
# macOS keys the TCC grant to the code signature, so an unsigned binary would
# lose its permission on every rebuild.
echo "Ad-hoc signing..."
codesign --force --deep --sign - "$APP_NAME"

if [ "$INSTALL" -eq 1 ]; then
    echo "Installing to /Applications..."
    rm -rf "/Applications/$APP_NAME"
    cp -R "$APP_NAME" "/Applications/"
    # Remove the local copy so macOS does not list two MyWispr entries in
    # System Settings > Accessibility.
    rm -rf "$APP_NAME"
    echo ""
    echo "=== Build complete ==="
    echo "Launch with: open /Applications/$APP_NAME"
else
    echo ""
    echo "=== Build complete ==="
    echo "Bundle left at: ./$APP_NAME"
fi

echo ""
echo "NOTE: after a rebuild, open"
echo "  System Settings > Privacy & Security > Accessibility"
echo "and toggle MyWispr off and on again to refresh the TCC permission cache."
