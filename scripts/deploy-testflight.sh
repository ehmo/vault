#!/usr/bin/env bash
set -euo pipefail

# Deploy Vault to TestFlight (Release archive + upload)
#
# Usage: ./scripts/deploy-testflight.sh [--bump]
#   --bump  Auto-increment CURRENT_PROJECT_VERSION before building
#
# Config:
WORKSPACE="apps/ios/Vault.xcworkspace"
SCHEME="Vault"
TEAM_ID="UFV835UGV6"
ASC_APP_ID="6758529311"
ARCHIVE_PATH="/tmp/Vault.xcarchive"
EXPORT_PATH="/tmp/VaultExport"
EXPORT_PLIST="/tmp/VaultExportOptions.plist"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

TUIST_PROJECT_SWIFT="apps/ios/Project.swift"
PBXPROJ="apps/ios/Vault.xcodeproj/project.pbxproj"

# --- Bump build number if requested ---
if [[ "${1:-}" == "--bump" ]]; then
  CURRENT=$(grep -m1 'buildNumber = ' "$TUIST_PROJECT_SWIFT" | sed 's/[^0-9]//g')
  NEXT=$((CURRENT + 1))
  echo "==> Bumping build number: $CURRENT -> $NEXT"
  # Update Project.swift (source of truth)
  sed -i '' "s/let buildNumber = \"$CURRENT\"/let buildNumber = \"$NEXT\"/" "$TUIST_PROJECT_SWIFT"
  # Regenerate Xcode project from Tuist manifests
  echo "==> Regenerating Xcode project..."
  (cd apps/ios && tuist generate --no-open)
else
  NEXT=$(grep -m1 'buildNumber = ' "$TUIST_PROJECT_SWIFT" | sed 's/[^0-9]//g')
  echo "==> Using existing build number: $NEXT"
fi

# --- Write ExportOptions.plist ---
cat > "$EXPORT_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

# --- Clean + Archive ---
echo "==> Archiving (Release)..."
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"
xcodebuild clean archive \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=iOS" \
  -allowProvisioningUpdates \
  -quiet

# --- Export IPA ---
echo "==> Exporting IPA..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -allowProvisioningUpdates 2>&1 | tail -3

IPA_PATH="$EXPORT_PATH/Vault.ipa"
if [[ ! -f "$IPA_PATH" ]]; then
  echo "ERROR: IPA not found at $IPA_PATH" >&2
  exit 1
fi

# --- Upload ---
echo "==> Uploading build $NEXT to TestFlight..."
asc builds upload --app "$ASC_APP_ID" --ipa "$IPA_PATH"

echo "==> Done. Build $NEXT uploaded to TestFlight."
echo "    Check status: asc builds list --app $ASC_APP_ID --limit 1 --pretty"
