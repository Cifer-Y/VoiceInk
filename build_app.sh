#!/bin/bash
set -euo pipefail

APP_NAME="VoiceInk"
BUNDLE_ID="com.cifer.VoiceInk"
APP_DIR="${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "Building ${APP_NAME}..."

# Build release binary
swift build -c release

# Find the binary
BINARY_PATH=$(swift build -c release --show-bin-path)/${APP_NAME}

if [ ! -f "${BINARY_PATH}" ]; then
    echo "Error: Binary not found at ${BINARY_PATH}"
    exit 1
fi

echo "Binary built at: ${BINARY_PATH}"

# Clean previous bundle
rm -rf "${APP_DIR}"

# Create app bundle structure
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# Copy binary
cp "${BINARY_PATH}" "${MACOS_DIR}/${APP_NAME}"

# Copy icon if exists
if [ -f "VoiceInk.icns" ]; then
    cp "VoiceInk.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

# Generate Info.plist
cat > "${CONTENTS_DIR}/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>VoiceInk needs microphone access to record your speech for transcription.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>VoiceInk uses on-device speech recognition to transcribe your voice into text.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>VoiceInk needs to simulate keyboard events to paste transcribed text.</string>
</dict>
</plist>
PLIST

# Ad-hoc code sign
codesign --force --deep --sign - "${APP_DIR}"

echo ""
echo "✅ ${APP_DIR} built and signed successfully."
echo "   To install: cp -r ${APP_DIR} /Applications/"
echo "   To run: open ${APP_DIR}"
