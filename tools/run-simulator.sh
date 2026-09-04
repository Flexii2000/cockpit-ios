#!/usr/bin/env bash
# Startet die App im Simulator - mit Zugang, damit man die Oberflaeche mit
# echten Daten sieht statt mit Fehlermeldungen.
#
#   tools/run-simulator.sh <Healthy|Vault|Fokus> [tab] [screenshot.png]
#
# Tabs: Healthy food|weight|widget, Vault grades|finance, Fokus habits|widget;
# `setup` oeffnet in jeder App das Zugang-Blatt.
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
#
# Die NOTEN brauchen ausserdem ein Passwort, und das gehoert nicht in den
# Schluesselbund dieses Rechners - es ist Felix' Anmeldung, nicht die eines
# Dienstes. Fuer einen Blick auf den Tab deshalb den Dienst lokal starten und
# umleiten (ATS laesst Schleifenadressen durch):
#
#   COCKPIT_URL_GRADES=http://127.0.0.1:48230/grades \
#   COCKPIT_GRADES_TOKEN=... COCKPIT_GRADES_USER=felix COCKPIT_GRADES_PASSWORD=... \
#   COCKPIT_NO_LOCK=1 tools/run-simulator.sh grades bild.png
#
# COCKPIT_NO_LOCK=1 ist dabei noetig: im Simulator ist kein Gesicht hinterlegt,
# sonst bleibt der Sperrbildschirm stehen.
#
# HABITS genauso umleitbar (COCKPIT_URL_HABITS=http://127.0.0.1:48190/habits),
# z. B. auf einen lokal mit ./gradlew bootRun gestarteten Dienst; der
# Privat-Token wird dann auch fuer diesen Rechner als Cookie gesetzt.
#
# COCKPIT_NO_HEALTH=1 laesst die Health-Anbindung aus. Ohne das verdeckt der
# Berechtigungsdialog jeden Screenshot des Gewicht-Tabs, und wegklicken laesst
# er sich nicht - simctl kennt keinen Health-Dienst.
#
# COCKPIT_RANGE=allTime stellt den Gewicht-Tab auf einen Zeitraum
# (month, last90, year, allTime).
#
# COCKPIT_SELECT=2026-08-15 waehlt einen Tag im Diagramm vor, damit die
# Sprechblase im Bild ist - eine Ziehgeste kann der Simulator nicht.
#
# COCKPIT_DAY=2026-08-10 stellt den Essen-Tab auf einen bestimmten Tag. Nuetzlich
# fuer einen leeren Tag: an einem vollen liegt der Verlauf unterhalb des
# Bildschirms, und scrollen kann simctl nicht.
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE="${DEVICE:-iPhone 17}"
APP="${1:-Healthy}"
TAB="${2:-}"
SHOT="${3:-}"
case "$APP" in
    Healthy) BUNDLE="com.fherrmann.cockpit" ;;
    Vault)   BUNDLE="com.fherrmann.vault" ;;
    Fokus)   BUNDLE="com.fherrmann.fokus" ;;
    *) echo "Erste Angabe muss Healthy, Vault oder Fokus sein." >&2; exit 1 ;;
esac

PRIVATE=$(security find-generic-password -a cockpit-ios -s fh_private -w) || {
    echo "Kein fh_private im Schluesselbund - siehe Kopf dieses Skripts." >&2
    exit 1
}
WEIGHT=$(security find-generic-password -a cockpit-ios -s weight_app_token -w) || {
    echo "Kein weight_app_token im Schluesselbund - siehe Kopf dieses Skripts." >&2
    exit 1
}

tools/bootstrap.sh > /dev/null
xcodebuild build -project Cockpit.xcodeproj -scheme "$APP" \
    -destination "platform=iOS Simulator,name=$DEVICE" \
    -derivedDataPath build/sim -quiet

xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl install booted "build/sim/Build/Products/Debug-iphonesimulator/$APP.app"
xcrun simctl terminate booted "$BUNDLE" 2>/dev/null || true

SIMCTL_CHILD_COCKPIT_FH_PRIVATE_TOKEN="$PRIVATE" \
SIMCTL_CHILD_COCKPIT_WEIGHT_TOKEN="$WEIGHT" \
SIMCTL_CHILD_COCKPIT_TAB="$TAB" \
SIMCTL_CHILD_COCKPIT_DAY="${COCKPIT_DAY:-}" \
SIMCTL_CHILD_COCKPIT_NO_HEALTH="${COCKPIT_NO_HEALTH:-}" \
SIMCTL_CHILD_COCKPIT_RANGE="${COCKPIT_RANGE:-}" \
SIMCTL_CHILD_COCKPIT_SELECT="${COCKPIT_SELECT:-}" \
SIMCTL_CHILD_COCKPIT_FORCE_LOCK="${COCKPIT_FORCE_LOCK:-}" \
SIMCTL_CHILD_COCKPIT_NO_LOCK="${COCKPIT_NO_LOCK:-}" \
SIMCTL_CHILD_COCKPIT_NO_PUSH="${COCKPIT_NO_PUSH:-}" \
SIMCTL_CHILD_COCKPIT_URL_GRADES="${COCKPIT_URL_GRADES:-}" \
SIMCTL_CHILD_COCKPIT_URL_HABITS="${COCKPIT_URL_HABITS:-}" \
SIMCTL_CHILD_COCKPIT_GRADES_TOKEN="${COCKPIT_GRADES_TOKEN:-}" \
SIMCTL_CHILD_COCKPIT_GRADES_USER="${COCKPIT_GRADES_USER:-}" \
SIMCTL_CHILD_COCKPIT_GRADES_PASSWORD="${COCKPIT_GRADES_PASSWORD:-}" \
    xcrun simctl launch booted "$BUNDLE" > /dev/null

if [ -n "$SHOT" ]; then
    # Kurz warten: die Tabs laden ihre Daten erst nach dem Erscheinen, ein
    # sofortiger Screenshot zeigt nur den Ladezustand.
    sleep 6
    xcrun simctl io booted screenshot "$SHOT"
    echo "$SHOT"
fi
