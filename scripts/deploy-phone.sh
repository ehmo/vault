#!/usr/bin/env bash
set -euo pipefail

# Deploy Vault to physical iPhone via USB (Debug build)
#
# Usage: ./scripts/deploy-phone.sh [--launch]
#
# Config (edit if device changes):
DEVICE_UDID="00008140-001A00141163001C"
DEVICE_NAME="Test device 1"
PROJECT="apps/ios/Vault.xcodeproj"
SCHEME="Vault"
DERIVED_DATA="/tmp/VaultDevice"
BUNDLE_ID="app.vaultaire.ios"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "==> Building Debug for device ($DEVICE_NAME)..."
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "platform=iOS,name=$DEVICE_NAME" \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  ONLY_ACTIVE_ARCH=YES \
  -quiet

APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphoneos/Vault.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: Build output not found at $APP_PATH"
  exit 1
fi

echo "==> Installing on device..."
xcrun devicectl device install app \
  --device "$DEVICE_UDID" \
  "$APP_PATH"

if [[ "${1:-}" == "--launch" ]]; then
  echo "==> Launching app..."
  xcrun devicectl device process launch \
    --device "$DEVICE_UDID" \
    "$BUNDLE_ID"
fi

echo "==> Done. Vault installed on $DEVICE_NAME."
