#!/bin/bash
set -euo pipefail

# Publish Vault to TestFlight
# Usage: ./scripts/publish-testflight.sh [--group "Group Name"]
#
# Prerequisites:
#   - Apple Distribution certificate installed in keychain
#   - Provisioning profiles for all targets (Vault, ShareExtension)
#   - Release build configs set to manual signing with distribution profiles
#   - ExportOptions.plist with app-store-connect method

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ARCHIVE_DIR="$PROJECT_DIR/build/archive"
EXPORT_DIR="$PROJECT_DIR/build/export"
ARCHIVE_PATH="$ARCHIVE_DIR/Vault.xcarchive"
EXPORT_OPTIONS="$PROJECT_DIR/ExportOptions.plist"
APP_ID="6758529311"
GROUP="${1:-Internal Testers}"

# Strip --group flag if passed
if [[ "$GROUP" == "--group" ]]; then
    GROUP="${2:-Internal Testers}"
fi

echo "==> Cleaning build directory..."
rm -rf "$PROJECT_DIR/build"
mkdir -p "$ARCHIVE_DIR" "$EXPORT_DIR"

echo "==> Archiving Vault (Release)..."
xcodebuild archive \
    -project "$PROJECT_DIR/Vault.xcodeproj" \
    -scheme Vault \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    DEVELOPMENT_TEAM=UFV835UGV6 \
    2>&1 | tail -20

if [[ ! -d "$ARCHIVE_PATH" ]]; then
    echo "ERROR: Archive failed — $ARCHIVE_PATH not found" >&2
    exit 1
fi
echo "==> Archive created: $ARCHIVE_PATH"

echo "==> Exporting and uploading to App Store Connect..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -exportPath "$EXPORT_DIR" \
    -allowProvisioningUpdates \
    2>&1 | tail -20

echo "==> Done! Build uploaded to App Store Connect."
echo "    Distribute to '$GROUP' via: asc testflight beta-groups add-build --app $APP_ID --group '$GROUP' --build <BUILD_ID>"
