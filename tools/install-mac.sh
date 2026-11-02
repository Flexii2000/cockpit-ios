#!/usr/bin/env bash
# Baut eine Mac-App als Release, legt sie nach /Applications und startet sie.
#
#   tools/install-mac.sh AWSUsageBar       # AWS-Kosten in der Menueleiste (01.11.)
#   tools/install-mac.sh ClaudeUsageBar    # Claude-Nutzung in der Menueleiste (02.11.)
#
# Release, damit keine Debug-Schalter wirken. Signiert mit dem
# Apple-Development-Zertifikat aus project.yml - dieselbe Signatur bei jedem
# Update, sonst fragte macOS nach jedem Bau wieder nach dem Schluesselbund-Eintrag.
#
# AWSUsageBar: beim ersten Start „fh_private“ lesen lassen („Immer erlauben“).
# ClaudeUsageBar: im Ausklappfenster „Bei Claude anmelden“.
#
# Liegt unter demselben Namen eine fremde App in /Applications (die Claude Usage
# Bar von claudeusagebar.com heisst genauso), bricht das Skript ab, statt sie zu
# loeschen - mit --replace-foreign ersetzt es sie.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-AWSUsageBar}"
case "$APP" in
    AWSUsageBar) BUNDLE_ID=com.fherrmann.awsusagebar ;;
    ClaudeUsageBar) BUNDLE_ID=com.fherrmann.claudeusagebar ;;
    *) echo "Erste Angabe muss AWSUsageBar oder ClaudeUsageBar sein." >&2; exit 1 ;;
esac
REPLACE_FOREIGN=0
[ "${2:-}" = "--replace-foreign" ] && REPLACE_FOREIGN=1

TARGET="/Applications/$APP.app"
if [ -d "$TARGET" ]; then
    FOUND=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$TARGET/Contents/Info.plist" 2>/dev/null || echo "?")
    if [ "$FOUND" != "$BUNDLE_ID" ] && [ "$REPLACE_FOREIGN" != 1 ]; then
        echo "$TARGET ist eine andere App ($FOUND) - nichts ersetzt." >&2
        echo "Ersetzen: tools/install-mac.sh $APP --replace-foreign" >&2
        exit 1
    fi
fi

tools/bootstrap.sh > /dev/null
xcodebuild build -project Cockpit.xcodeproj -scheme "$APP" -configuration Release \
    -destination 'platform=macOS' -derivedDataPath build/mac-release -quiet
BUILT="build/mac-release/Build/Products/Release/$APP.app"
codesign --verify --strict "$BUILT"

# Die laufende Fassung beenden - sonst ersetzt ditto die Dateien unter ihr.
pkill -x "$APP" 2>/dev/null && sleep 1 || true
rm -rf "$TARGET"
ditto "$BUILT" "$TARGET"
open "$TARGET"
echo "$TARGET"
