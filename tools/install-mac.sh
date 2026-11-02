#!/usr/bin/env bash
# Baut eine Mac-App als Release, legt sie nach /Applications und startet sie.
#
#   tools/install-mac.sh CloudUsageBar     # AWS- und Verda-Kosten in der Menueleiste (seit 01.11.)
#   tools/install-mac.sh ClaudeUsageBar    # Claude-Nutzung in der Menueleiste (02.11.)
#
# Release, damit keine Debug-Schalter wirken. Signiert mit dem
# Apple-Development-Zertifikat aus project.yml - dieselbe Signatur bei jedem
# Update, sonst fragte macOS nach jedem Bau wieder nach dem Schluesselbund-Eintrag.
#
# CloudUsageBar: beim ersten Start den Token lesen lassen („Immer erlauben“) -
# den der Vorgaengerin AWSUsageBar oder „fh_private“. „Beim Anmelden starten“
# einmal neu setzen: es haengt an der App, und die hat eine neue Bundle-ID.
# ClaudeUsageBar: im Ausklappfenster „Bei Claude anmelden“.
#
# Liegt unter demselben Namen eine fremde App in /Applications (die Claude Usage
# Bar von claudeusagebar.com heisst genauso), bricht das Skript ab, statt sie zu
# loeschen - mit --replace-foreign ersetzt es sie.
#
# CloudUsageBar ersetzt die AWSUsageBar (bis 02.11.): liegt sie mit Felix'
# Bundle-ID in /Applications, wird sie beendet und entfernt - sonst zeigten zwei
# Wolken in der Menueleiste dasselbe. Ihren Schluesselbund-Eintrag laesst das
# Skript stehen; aus ihm liest die neue App den Token.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-CloudUsageBar}"
case "$APP" in
    CloudUsageBar) BUNDLE_ID=com.fherrmann.cloudusagebar ;;
    ClaudeUsageBar) BUNDLE_ID=com.fherrmann.claudeusagebar ;;
    *) echo "Erste Angabe muss CloudUsageBar oder ClaudeUsageBar sein." >&2; exit 1 ;;
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

if [ "$APP" = "CloudUsageBar" ]; then
    OLD="/Applications/AWSUsageBar.app"
    if [ -d "$OLD" ]; then
        OLD_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$OLD/Contents/Info.plist" 2>/dev/null || echo "?")
        if [ "$OLD_ID" = "com.fherrmann.awsusagebar" ]; then
            pkill -x AWSUsageBar 2>/dev/null && sleep 1 || true
            rm -rf "$OLD"
            echo "AWSUsageBar beendet und entfernt (abgeloest durch CloudUsageBar)."
        else
            echo "$OLD ist eine andere App ($OLD_ID) - stehen gelassen." >&2
        fi
    fi
fi

open "$TARGET"
echo "$TARGET"
