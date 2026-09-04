#!/usr/bin/env bash
# Baut alle drei Apps fuer den Simulator und laesst die Unit-Tests laufen.
# Das ist der einzige gueltige Beleg dafuer, dass etwas funktioniert -
# "sieht richtig aus" zaehlt nicht (siehe CLAUDE.md).
#
#   tools/verify.sh            # alle drei
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

APPS="${1:-Healthy Vault Fokus}"
for APP in $APPS; do
    echo "== $APP =="
    if [ "$APP" = "Healthy" ]; then
        # Die Unit-Tests haengen an Healthy (sie pruefen Shared und Core).
        # Bewusst NUR die: UI-Tests dauern Minuten - dafuer gibt es uitest.sh.
        xcodebuild test -project Cockpit.xcodeproj -scheme Healthy \
            -only-testing:CockpitTests -destination "$DEST" | pretty
    else
        xcodebuild build -project Cockpit.xcodeproj -scheme "$APP" \
            -destination "$DEST" | pretty
    fi
done
