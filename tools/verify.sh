#!/usr/bin/env bash
# Baut die App fuer den Simulator und laesst die Tests laufen.
# Das ist der einzige gueltige Beleg dafuer, dass etwas funktioniert -
# "sieht richtig aus" zaehlt nicht (siehe CLAUDE.md).
set -euo pipefail
cd "$(dirname "$0")/.."

[ -d Cockpit.xcodeproj ] || tools/bootstrap.sh

# Simulator nicht fest verdrahten: die Namen aendern sich mit jeder
# iOS-Version, und ein fest eingetragenes "iPhone 16" laesst das Skript
# ein halbes Jahr spaeter grundlos scheitern.
SIM=$(xcrun simctl list devices available \
      | grep -oE '^\s+iPhone [^(]+' | head -1 | xargs)
if [ -z "$SIM" ]; then
    echo "Kein iPhone-Simulator verfuegbar. In Xcode unter" >&2
    echo "Settings > Components eine iOS-Plattform installieren." >&2
    exit 1
fi
echo "Simulator: $SIM"

xcodebuild test \
    -project Cockpit.xcodeproj \
    -scheme Cockpit \
    -destination "platform=iOS Simulator,name=$SIM" \
    | (command -v xcbeautify >/dev/null 2>&1 && xcbeautify || cat)
