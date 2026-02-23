#!/usr/bin/env bash
set -euo pipefail

# Deploy Vault to physical iPhone via USB (Debug build)
#
# Usage: ./scripts/deploy-phone.sh [--launch] [--device 1|2]
#
# Devices:
#   --device 1: Test device 1 (default) - 00008140-001A00141163001C
#   --device 2: Test device 2 - YOUR_UDID_HERE
#
# Examples:
#   ./scripts/deploy-phone.sh --launch                    # Deploy to device 1
#   ./scripts/deploy-phone.sh --launch --device 2       # Deploy to device 2

PROJECT="apps/ios/Vault.xcodeproj"
SCHEME="Vault"
DERIVED_DATA="/tmp/VaultDevice"
BUNDLE_ID="app.vaultaire.ios"

# Device configs
# NOTE: Use hardware UDID (00008140-...) for xcodebuild
# Device 1: Test device 1, iPhone 16
# Device 2: Test device 2, iPhone 16
DEVICE1_UDID="00008140-001A00141163001C"
DEVICE1_NAME="Test device 1"
DEVICE2_UDID="00008140-001975DC3678801C"
DEVICE2_NAME="Test device 2"

# Parse arguments
LAUNCH=false
DEVICE_NUM=1

while [[ $# -gt 0 ]]; do
	case $1 in
	--launch)
		LAUNCH=true
		shift
		;;
	--device)
		DEVICE_NUM="$2"
		shift 2
		;;
	*)
		echo "Unknown option: $1"
		echo "Usage: $0 [--launch] [--device 1|2]"
		exit 1
		;;
	esac
done

# Set device based on selection
if [[ "$DEVICE_NUM" == "1" ]]; then
	DEVICE_UDID="$DEVICE1_UDID"
	DEVICE_NAME="$DEVICE1_NAME"
elif [[ "$DEVICE_NUM" == "2" ]]; then
	DEVICE_UDID="$DEVICE2_UDID"
	DEVICE_NAME="$DEVICE2_NAME"
else
	echo "ERROR: Invalid device number. Use 1 or 2."
	exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "==> Building Debug for device $DEVICE_NUM ($DEVICE_NAME)..."
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
	echo "ERROR: Build output not found at $APP_PATH" >&2
	exit 1
fi

echo "==> Installing on $DEVICE_NAME..."
xcrun devicectl device install app \
	--device "$DEVICE_UDID" \
	"$APP_PATH"

if [[ "$LAUNCH" == true ]]; then
	echo "==> Launching app..."
	xcrun devicectl device process launch \
		--device "$DEVICE_UDID" \
		"$BUNDLE_ID"
fi

echo "==> Done. Vault installed on $DEVICE_NAME."
