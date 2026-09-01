#!/usr/bin/env bash
# Erzeugt Cockpit.xcodeproj aus project.yml. Idempotent - nach jeder
# Aenderung an project.yml oder nach neuen Quelldateien einfach nochmal.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! xcodebuild -version >/dev/null 2>&1; then
    cat <<'MSG' >&2
Xcode fehlt (oder zeigt noch auf die Command Line Tools).

  1. Xcode aus dem App Store installieren
  2. sudo xcode-select -s /Applications/Xcode.app
  3. xcodebuild -runFirstLaunch

Ohne Xcode gibt es kein iOS-SDK und keinen Simulator - dieses Projekt laesst
sich dann weder erzeugen noch bauen.
MSG
    exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "XcodeGen fehlt. Installieren mit:  brew install xcodegen" >&2
    exit 1
fi

xcodegen generate
echo "Cockpit.xcodeproj erzeugt. Weiter mit:  open Cockpit.xcodeproj"
