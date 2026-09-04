#!/usr/bin/env bash
# Faehrt die Oberflaeche automatisiert durch und legt Screenshots ab.
#
#   tools/uitest.sh <Healthy|Vault|Fokus|Einkauf>             # alle UI-Tests der App
#   tools/uitest.sh <Healthy|Vault|Fokus|Einkauf> testSwipe   # nur einer
#
# Der Grund: simctl kann weder tippen noch wischen noch scrollen. Alles, was
# hinter einer Geste oder unterhalb des ersten Bildschirms liegt, ist nur von
# hier aus zu sehen. Die Bilder landen in build/screenshots/, die Zuordnung
# steht dort in manifest.json.
#
# Die Zugangstoken kommen wie beim Simulator-Skript aus dem Schluesselbund und
# werden ueber launchEnvironment durchgereicht - im Repo steht keins.
#
# ⚠️ Sie muessen mit TEST_RUNNER_ davor exportiert werden. xcodebuild reicht
# NUR so praefixierte Variablen an den Testlaeufer weiter und streicht das
# Praefix dabei weg. Ohne das sieht der Test leere Token - und der Lauf ist
# trotzdem gruen, solange im Simulator noch welche vom letzten
# run-simulator.sh im Keychain liegen. Genau so lief der Harness eine Weile:
# richtig aussehend, aber auf Resten.
#
# Fuer den Noten-Test zusaetzlich (siehe Kopf von run-simulator.sh):
#   COCKPIT_URL_GRADES, COCKPIT_GRADES_TOKEN, COCKPIT_GRADES_USER,
#   COCKPIT_GRADES_PASSWORD - fehlen sie, ueberspringt er sich.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-}"
FILTER="${2:-}"
DEVICE="${DEVICE:-iPhone 17}"
case "$APP" in Healthy|Vault|Fokus|Einkauf) ;; *) echo "Erste Angabe muss Healthy, Vault, Fokus oder Einkauf sein." >&2; exit 1 ;; esac
BUNDLE_NAME="${APP}UITests"

export TEST_RUNNER_COCKPIT_FH_PRIVATE_TOKEN
export TEST_RUNNER_COCKPIT_WEIGHT_TOKEN
TEST_RUNNER_COCKPIT_FH_PRIVATE_TOKEN=$(security find-generic-password -a cockpit-ios -s fh_private -w)
TEST_RUNNER_COCKPIT_WEIGHT_TOKEN=$(security find-generic-password -a cockpit-ios -s weight_app_token -w)
# Freiwillig: ohne Einkaufs-Token ueberspringt sich der Einkaufs-Test.
export TEST_RUNNER_COCKPIT_SHOPPING_TOKEN
TEST_RUNNER_COCKPIT_SHOPPING_TOKEN=$(security find-generic-password -a cockpit-ios -s shopping_token -w 2>/dev/null || true)

# Der Noten-Zugang kommt aus der Umgebung, nicht aus dem Schluesselbund: das
# Passwort ist Felix' Anmeldung und kein Dienstgeheimnis.
export TEST_RUNNER_COCKPIT_URL_GRADES="${COCKPIT_URL_GRADES:-}"
export TEST_RUNNER_COCKPIT_GRADES_TOKEN="${COCKPIT_GRADES_TOKEN:-}"
export TEST_RUNNER_COCKPIT_GRADES_USER="${COCKPIT_GRADES_USER:-}"
export TEST_RUNNER_COCKPIT_GRADES_PASSWORD="${COCKPIT_GRADES_PASSWORD:-}"
export TEST_RUNNER_COCKPIT_URL_HABITS="${COCKPIT_URL_HABITS:-}"

tools/bootstrap.sh > /dev/null
rm -rf build/uitest.xcresult build/screenshots

ARGS=(-project Cockpit.xcodeproj -scheme "$APP"
      -destination "platform=iOS Simulator,name=$DEVICE"
      -resultBundlePath build/uitest.xcresult)
if [ -n "$FILTER" ]; then
    ARGS+=(-only-testing:"$BUNDLE_NAME/$BUNDLE_NAME/$FILTER")
else
    ARGS+=(-only-testing:"$BUNDLE_NAME")
fi

set +e
xcodebuild test "${ARGS[@]}" | tail -40
STATUS=${PIPESTATUS[0]}
set -e

xcrun xcresulttool export attachments \
    --path build/uitest.xcresult \
    --output-path build/screenshots > /dev/null

# Ohne diese Pruefung sieht ein Lauf ganz ohne Bilder aus wie ein Erfolg.
COUNT=$(ls build/screenshots/*.png 2>/dev/null | wc -l | xargs)
if [ "$COUNT" = "0" ]; then
    echo "Kein einziger Screenshot - steht lifetime = .keepAlways?" >&2
    exit 1
fi
echo "$COUNT Bilder in build/screenshots/ (Zuordnung: manifest.json)"
exit $STATUS
