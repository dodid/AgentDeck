#!/usr/bin/env bash
set -euo pipefail

DEVICE_ID=${1:?usage: ios-simulator-lifecycle.sh DEVICE_ID APP_BUNDLE}
APP_BUNDLE=${2:?usage: ios-simulator-lifecycle.sh DEVICE_ID APP_BUNDLE}
BUNDLE_ID=${AGENTDECK_IOS_BUNDLE_ID:-com.candiapps.ClawChat}

[[ -d "$APP_BUNDLE" ]] || { echo "App bundle not found: $APP_BUNDLE" >&2; exit 1; }
xcrun simctl boot "$DEVICE_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$DEVICE_ID" -b
xcrun simctl uninstall "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true

# A clean install must launch and create its application container.
xcrun simctl install "$DEVICE_ID" "$APP_BUNDLE"
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID"
DATA_CONTAINER=$(xcrun simctl get_app_container "$DEVICE_ID" "$BUNDLE_ID" data)
MARKER_DIR="$DATA_CONTAINER/Library/Application Support/AgentDeck"
MARKER_FILE="$MARKER_DIR/upgrade-lifecycle-marker.json"
mkdir -p "$MARKER_DIR"
printf '{"preserve":"across-upgrade"}\n' > "$MARKER_FILE"

# Installing a candidate over the existing bundle models an App Store upgrade.
xcrun simctl install "$DEVICE_ID" "$APP_BUNDLE"
UPGRADED_CONTAINER=$(xcrun simctl get_app_container "$DEVICE_ID" "$BUNDLE_ID" data)
MARKER_FILE="$UPGRADED_CONTAINER/Library/Application Support/AgentDeck/upgrade-lifecycle-marker.json"
[[ -f "$MARKER_FILE" ]]
grep -q 'across-upgrade' "$MARKER_FILE"
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID"

# Uninstall plus install must produce a genuinely fresh container.
xcrun simctl uninstall "$DEVICE_ID" "$BUNDLE_ID"
xcrun simctl install "$DEVICE_ID" "$APP_BUNDLE"
FRESH_CONTAINER=$(xcrun simctl get_app_container "$DEVICE_ID" "$BUNDLE_ID" data)
[[ ! -f "$FRESH_CONTAINER/Library/Application Support/AgentDeck/upgrade-lifecycle-marker.json" ]]
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID"

printf 'AgentDeck simulator fresh-install and upgrade lifecycle passed on %s\n' "$DEVICE_ID"
