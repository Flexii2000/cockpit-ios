#!/usr/bin/env bash
# Startet die App im Simulator - mit Zugang, damit man die Oberflaeche mit
# echten Daten sieht statt mit Fehlermeldungen.
#
#   tools/run-simulator.sh [food|weight|finance|setup] [screenshot.png]
#
# Die Token kommen aus dem macOS-Schluesselbund und stehen NIRGENDWO im Repo:
#
#   security add-generic-password -a cockpit-ios -s fh_private \
#       -w '<token>' -T /usr/bin/security -U
#   security add-generic-password -a cockpit-ios -s weight_app_token \
#       -w '<token>' -T /usr/bin/security -U
#
# Uebergeben werden sie als Umgebungsvariablen; die App liest sie nur im
# Debug-Build (siehe Access.seedFromEnvironment).
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE="${DEVICE:-iPhone 17}"
TAB="${1:-food}"
SHOT="${2:-}"
BUNDLE="com.fherrmann.cockpit"

PRIVATE=$(security find-generic-password -a cockpit-ios -s fh_private -w) || {
    echo "Kein fh_private im Schluesselbund - siehe Kopf dieses Skripts." >&2
    exit 1
}
WEIGHT=$(security find-generic-password -a cockpit-ios -s weight_app_token -w) || {
    echo "Kein weight_app_token im Schluesselbund - siehe Kopf dieses Skripts." >&2
    exit 1
}

tools/bootstrap.sh > /dev/null
xcodebuild build -project Cockpit.xcodeproj -scheme Cockpit \
    -destination "platform=iOS Simulator,name=$DEVICE" \
    -derivedDataPath build/sim -quiet

xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl install booted build/sim/Build/Products/Debug-iphonesimulator/Cockpit.app
xcrun simctl terminate booted "$BUNDLE" 2>/dev/null || true

SIMCTL_CHILD_COCKPIT_FH_PRIVATE_TOKEN="$PRIVATE" \
SIMCTL_CHILD_COCKPIT_WEIGHT_TOKEN="$WEIGHT" \
SIMCTL_CHILD_COCKPIT_TAB="$TAB" \
    xcrun simctl launch booted "$BUNDLE" > /dev/null

if [ -n "$SHOT" ]; then
    # Kurz warten: die Tabs laden ihre Daten erst nach dem Erscheinen, ein
    # sofortiger Screenshot zeigt nur den Ladezustand.
    sleep 6
    xcrun simctl io booted screenshot "$SHOT"
    echo "$SHOT"
fi
