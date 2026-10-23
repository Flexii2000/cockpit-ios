#!/usr/bin/env bash
# Baut alle sechs Apps fuer den Simulator und laesst die Unit-Tests laufen -
# dazu die Uhr-Apps von Healthy (HealthyWatch, seit 14.10.) und Sport (SportWatch, seit 23.10.).
# Das ist der einzige gueltige Beleg dafuer, dass etwas funktioniert -
# "sieht richtig aus" zaehlt nicht (siehe CLAUDE.md).
#
#   tools/verify.sh            # alle sechs
#   tools/verify.sh Vault      # nur eine (schneller, wenn man an einer arbeitet)
set -euo pipefail
cd "$(dirname "$0")/.."

# Immer neu erzeugen, nicht nur wenn die .xcodeproj fehlt: sonst baut man
# gegen einen alten Projektstand weiter, waehrend die Aenderung an
# project.yml nie ankommt - und sucht den Fehler im Code.
tools/bootstrap.sh >/dev/null

SIM=$(xcrun simctl list devices available \
      | grep -oE '^\s+iPhone [^(]+' | head -1 | xargs)
if [ -z "$SIM" ]; then
    echo "Kein iPhone-Simulator verfuegbar. In Xcode unter" >&2
    echo "Settings > Components eine iOS-Plattform installieren." >&2
    exit 1
fi
echo "Simulator: $SIM"
DEST="platform=iOS Simulator,name=$SIM"
pretty() { command -v xcbeautify >/dev/null 2>&1 && xcbeautify || cat; }

APPS="${1:-Healthy HealthyWatch Vault Fokus Einkaufsliste coHabit Sport SportWatch}"
for APP in $APPS; do
    echo "== $APP =="
    if [ "$APP" = "Healthy" ]; then
        # Die Unit-Tests haengen an Healthy (sie pruefen Shared und Core).
        # Bewusst NUR die: UI-Tests dauern Minuten - dafuer gibt es uitest.sh.
        xcodebuild test -project Cockpit.xcodeproj -scheme Healthy \
            -only-testing:CockpitTests -destination "$DEST" | pretty
    elif [ "$APP" = "HealthyWatch" ] || [ "$APP" = "SportWatch" ]; then
        # Die Uhr fuer sich, gegen irgendeinen Uhren-Simulator - es braucht
        # keinen gestarteten. Fehlt die watchOS-Plattform:
        # xcodebuild -downloadPlatform watchOS
        xcodebuild build -project Cockpit.xcodeproj -scheme "$APP" \
            -destination 'generic/platform=watchOS Simulator' | pretty
    elif [ "$APP" = "Fokus" ]; then
        # Die Evaluation (seit 14.10. in Fokus) hat eigene Unit-Tests mit Fokus
        # als Wirt, samt der Uebernahme aus Healthy.
        xcodebuild test -project Cockpit.xcodeproj -scheme Fokus \
            -only-testing:FokusTests -destination "$DEST" | pretty
    elif [ "$APP" = "Sport" ]; then
        # Gym (seit 23.10. hier), Padel und das Zaehlen auf der Uhr - Sport ist der Wirt.
        xcodebuild test -project Cockpit.xcodeproj -scheme Sport \
            -only-testing:SportTests -destination "$DEST" | pretty
    elif [ "$APP" = "coHabit" ]; then
        # coHabit hat eigene Unit-Tests mit coHabit als Wirt: CohabitShared
        # und der App-Code liegen nur dort.
        xcodebuild test -project Cockpit.xcodeproj -scheme coHabit \
            -only-testing:CohabitTests -destination "$DEST" | pretty
    else
        xcodebuild build -project Cockpit.xcodeproj -scheme "$APP" \
            -destination "$DEST" | pretty
    fi
done
