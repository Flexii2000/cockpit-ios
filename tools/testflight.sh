#!/usr/bin/env bash
# Archiviert eine App fuer App Store Connect und laedt sie zu TestFlight hoch.
#
#   tools/testflight.sh <Healthy|Vault|Fokus|Einkaufsliste>            # archivieren + hochladen
#   tools/testflight.sh <App> --export-only                            # nur .ipa bauen, nichts hochladen
#
# Warum ueberhaupt: ein Entwickler-Install (install-device.sh) braucht auf dem
# Zielgeraet den Entwicklermodus, das Geraet im Developer-Konto und den Mac
# per Kabel - bei jedem Update. Fuer ein zweites Handy (Joana) ist TestFlight
# der Weg: einmal hochladen, sie installiert ueber die TestFlight-App, Updates
# kommen per Fingertipp. Ein Build laeuft dort 90 Tage.
#
# Zugang: ein App-Store-Connect-API-Schluessel. Er liegt NICHT im Repo:
#   ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8   (nur einmal ladbar)
#   ~/.appstoreconnect/config                            (ASC_KEY_ID=..., ASC_ISSUER_ID=...)
# Issuer ID und Key ID stehen in App Store Connect unter Benutzer und Zugriff >
# Integrationen > App Store Connect API. Ohne Issuer ID laeuft nur --export-only
# ueber das in Xcode angemeldete Konto.
#
# Voraussetzungen, die das Skript NICHT erledigen kann:
#   * der App-Eintrag in App Store Connect (Meine Apps > +, mit der Bundle-ID) -
#     die offizielle API kennt keinen Aufruf dafuer
#   * Tester eintragen (TestFlight > Interne Tests) - einmalig
#
# Build-Nummer: Jahr-Monat-Tag-Stunde-Minute. Jeder Upload braucht eine neue,
# hoehere; die Uhrzeit liefert das ohne Buchfuehrung. Die sichtbare Version
# (MARKETING_VERSION) bleibt in project.yml.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-}"
MODE="${2:-}"
case "$APP" in
    Healthy|Vault|Fokus|Einkaufsliste) ;;
    *) echo "Erste Angabe muss Healthy, Vault, Fokus oder Einkaufsliste sein." >&2; exit 1 ;;
esac

CONFIG="$HOME/.appstoreconnect/config"
[ -f "$CONFIG" ] && . "$CONFIG"
ASC_KEY_ID="${ASC_KEY_ID:-}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-}"
KEY="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"

# Das Array bleibt leer, wenn nur das Xcode-Konto zur Verfuegung steht; die
# Ausdehnung unten ist die Schreibweise, die Bashs 3.2 mit set -u vertraegt.
AUTH=()
if [ -n "$ASC_KEY_ID" ] && [ -n "$ASC_ISSUER_ID" ] && [ -f "$KEY" ]; then
    AUTH=(-authenticationKeyPath "$KEY" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
elif [ "$MODE" != "--export-only" ]; then
    echo "Kein vollstaendiger API-Zugang (ASC_KEY_ID, ASC_ISSUER_ID in $CONFIG, Schluessel unter $KEY)." >&2
    echo "Zum Ausprobieren ohne Upload: $0 $APP --export-only" >&2
    exit 1
fi

BUILD="$(date +%Y%m%d%H%M)"
ARCHIVE="build/archive/$APP.xcarchive"
EXPORT="build/export/$APP"
rm -rf "$ARCHIVE" "$EXPORT"

echo "== $APP archivieren (Build $BUILD) =="
tools/bootstrap.sh > /dev/null
xcodebuild archive -project Cockpit.xcodeproj -scheme "$APP" \
    -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} \
    CURRENT_PROJECT_VERSION="$BUILD" -quiet

DESTINATION=upload
[ "$MODE" = "--export-only" ] && DESTINATION=export
PLIST="build/archive/ExportOptions-$APP.plist"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>$DESTINATION</string>
    <key>teamID</key><string>ZWFV263P59</string>
    <key>signingStyle</key><string>automatic</string>
    <key>uploadSymbols</key><true/>
    <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

echo "== $APP exportieren ($DESTINATION) =="
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$PLIST" -exportPath "$EXPORT" \
    -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} -quiet

if [ "$DESTINATION" = "export" ]; then
    ls -la "$EXPORT"/*.ipa
    echo "Nur exportiert - nichts hochgeladen."
else
    echo "Hochgeladen: $APP Build $BUILD. In App Store Connect unter TestFlight erscheint er nach ein paar Minuten"
    echo "(erst 'Wird verarbeitet', dann fuer interne Tester frei)."
fi
