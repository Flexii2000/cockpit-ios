#!/usr/bin/env bash
# Baut die App signiert und installiert sie auf dem iPhone.
#
#   tools/install-device.sh <Healthy|Vault|Fokus|Einkaufsliste>            # bauen und installieren
#   tools/install-device.sh <Healthy|Vault|Fokus|Einkaufsliste> --launch   # danach auch starten
#   tools/install-device.sh all                                      # alle vier
#
# Das Geraet wird selbst gesucht: es muss einmal mit Xcode gekoppelt worden
# sein, danach reicht dasselbe WLAN - ein Kabel ist nur beim ersten Mal noetig.
# Ist der Bildschirm gesperrt oder das iPhone nicht im Netz, sagt das Skript
# das und bricht ab.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-}"
LAUNCH=false
[ "${2:-}" = "--launch" ] && LAUNCH=true
if [ "$APP" = "all" ]; then
    for each in Healthy Vault Fokus Einkaufsliste; do "$0" "$each" ${2:-}; done
    exit 0
fi
case "$APP" in
    Healthy) BUNDLE="com.fherrmann.cockpit" ;;
    Vault)   BUNDLE="com.fherrmann.vault" ;;
    Fokus)   BUNDLE="com.fherrmann.fokus" ;;
    Einkaufsliste) BUNDLE="com.fherrmann.einkauf" ;;
    *) echo "Erste Angabe muss Healthy, Vault, Fokus, Einkaufsliste oder all sein." >&2; exit 1 ;;
esac

JSON=$(mktemp)
trap 'rm -f "$JSON"' EXIT
xcrun devicectl list devices --json-output "$JSON" > /dev/null

# Bevorzugt ein Geraet mit offenem Tunnel; sonst das erste gekoppelte, damit
# die Fehlermeldung wenigstens einen Namen nennen kann.
read -r DEVICE_ID DEVICE_STATE DEVICE_NAME <<EOF
$(python3 - "$JSON" <<'PY'
import json, sys
best = None
for device in json.load(open(sys.argv[1])).get("result", {}).get("devices", []):
    if device.get("hardwareProperties", {}).get("platform") != "iOS":
        continue
    connection = device.get("connectionProperties", {})
    if connection.get("pairingState") != "paired":
        continue
    ready = connection.get("tunnelState") == "connected"
    entry = (device["identifier"],
             "bereit" if ready else "nicht-erreichbar",
             device.get("deviceProperties", {}).get("name", "iPhone"))
    if ready:
        best = entry
        break
    best = best or entry
print(" ".join(best) if best else "  ")
PY
)
EOF

if [ -z "${DEVICE_ID:-}" ]; then
    echo "Kein gekoppeltes iPhone gefunden." >&2
    echo "Einmal per Kabel anschliessen und in Xcode unter Window > Devices" >&2
    echo "\"Connect via network\" anhaken - danach geht es drahtlos." >&2
    exit 1
fi

# Kein Vorab-Abbruch anhand von tunnelState: der Tunnel wird bei Bedarf
# aufgebaut, "disconnected" heisst also NICHT unerreichbar. Wer hier zu frueh
# aufgibt, weist ein Geraet ab, das gleich geantwortet haette.
echo "Ziel: $DEVICE_NAME ($DEVICE_STATE)"
tools/bootstrap.sh > /dev/null
xcodebuild build -project Cockpit.xcodeproj -scheme "$APP" \
    -destination 'generic/platform=iOS' -allowProvisioningUpdates \
    -derivedDataPath build/device -quiet

# Den Tunnel unmittelbar vorher wecken. Er faellt zwischen zwei Kommandos
# wieder zu, und die Installation meldet dann "unable to locate a device" -
# obwohl eine Abfrage Sekunden vorher noch durchging. Eine billige Abfrage
# direkt davor ist der Unterschied zwischen "geht nicht" und "geht".
xcrun devicectl device info details --device "$DEVICE_ID" > /dev/null 2>&1 || true

if ! xcrun devicectl device install app --device "$DEVICE_ID" \
        "build/device/Build/Products/Debug-iphoneos/$APP.app"; then
    echo >&2
    echo "Installation fehlgeschlagen. Haeufigster Grund: $DEVICE_NAME ist" >&2
    echo "gesperrt oder nicht im selben WLAN. Entsperren und noch einmal -" >&2
    echo "oder Kabel anstecken." >&2
    exit 1
fi

# Kontrolle, dass die Erweiterung wirklich mitgekommen ist. Fehlt der
# dependencies-Eintrag in project.yml, baut sie zwar, wird aber nicht
# eingebettet: die Installation meldet Erfolg, die App startet, und in der
# Widget-Galerie steht nichts.
PLUGINS="build/device/Build/Products/Debug-iphoneos/$APP.app/PlugIns"
if [ -d "$PLUGINS" ]; then
    echo "Erweiterungen: $(ls "$PLUGINS" | tr '\n' ' ')"
elif [ "$APP" != "Vault" ] && [ "$APP" != "Einkaufsliste" ]; then
    echo "WARNUNG: keine PlugIns im Bundle - das Widget ist nicht eingebettet." >&2
fi

if $LAUNCH; then
    # Beim ersten Mal mit einem neuen Zertifikat verweigert iOS den Start, bis
    # das Entwicklerprofil am Geraet bestaetigt wurde:
    # Einstellungen > Allgemein > VPN & Geraeteverwaltung.
    xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE"
fi
