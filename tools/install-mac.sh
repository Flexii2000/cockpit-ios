#!/usr/bin/env bash
# Baut die Mac-App als Release, legt sie nach /Applications und startet sie.
#
#   tools/install-mac.sh AWSUsageBar
#
# Bisher gibt es nur die eine (AWSUsageBar, seit 01.11.: AWS-Kosten in der
# Menueleiste). Release, damit keine COCKPIT_-Umleitung wirkt und die App den
# echten Dienst fragt. Signiert mit dem Apple-Development-Zertifikat aus
# project.yml - dieselbe Signatur bei jedem Update, sonst fragte macOS nach
# jedem Bau wieder nach dem Schluesselbund-Eintrag fh_private.
#
# Beim ersten Start fragt macOS, ob AWSUsageBar den Eintrag „fh_private“ lesen
# darf: „Immer erlauben“. „Beim Anmelden starten“ steht im Ausklappfenster.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-AWSUsageBar}"
case "$APP" in
    AWSUsageBar) ;;
    *) echo "Erste Angabe muss AWSUsageBar sein." >&2; exit 1 ;;
esac

tools/bootstrap.sh > /dev/null
xcodebuild build -project Cockpit.xcodeproj -scheme "$APP" -configuration Release \
    -destination 'platform=macOS' -derivedDataPath build/mac-release -quiet
BUILT="build/mac-release/Build/Products/Release/$APP.app"
codesign --verify --strict "$BUILT"

# Die laufende Fassung beenden - sonst ersetzt ditto die Dateien unter ihr.
pkill -x "$APP" 2>/dev/null && sleep 1 || true
rm -rf "/Applications/$APP.app"
ditto "$BUILT" "/Applications/$APP.app"
open "/Applications/$APP.app"
echo "/Applications/$APP.app"
