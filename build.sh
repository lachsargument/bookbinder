#!/bin/bash
set -e

APP_NAME="Bookbinder"
BUNDLE_ID="Salmonization.Bookbinder"
APP_VERSION="1.1"
BUILD_VERSION="2"

APP_BUNDLE="${APP_NAME}.app"
MACOS_DIR="${APP_BUNDLE}/Contents/MacOS"
SOURCES=(main.swift Core.swift)

rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}"

# universal binary (Apple Silicon + Intel)
swiftc -O "${SOURCES[@]}" -target arm64-apple-macos13 -o "${APP_NAME}_arm64"
swiftc -O "${SOURCES[@]}" -target x86_64-apple-macos13 -o "${APP_NAME}_x86_64"
lipo -create -output "${MACOS_DIR}/${APP_NAME}" "${APP_NAME}_arm64" "${APP_NAME}_x86_64"
rm "${APP_NAME}_arm64" "${APP_NAME}_x86_64"

cat <<PLIST > "${APP_BUNDLE}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "=> Built ${APP_BUNDLE}"

# drag-to-Applications DMG
DMG_NAME="${APP_NAME}-${APP_VERSION}.dmg"
STAGE_DIR=".dmg-stage"

rm -rf "${STAGE_DIR}" "${DMG_NAME}"
mkdir -p "${STAGE_DIR}"
cp -R "${APP_BUNDLE}" "${STAGE_DIR}/"
ln -s /Applications "${STAGE_DIR}/Applications"
hdiutil create -volname "${APP_NAME}" -srcfolder "${STAGE_DIR}" -ov -format UDZO "${DMG_NAME}"
rm -rf "${STAGE_DIR}"

echo "=> Built ${DMG_NAME}"
