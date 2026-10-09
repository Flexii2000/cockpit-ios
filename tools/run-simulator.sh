#!/usr/bin/env bash
# Startet die App im Simulator - mit Zugang, damit man die Oberflaeche mit
# echten Daten sieht statt mit Fehlermeldungen.
#
#   tools/run-simulator.sh <Healthy|Vault|Fokus|Einkaufsliste|coHabit> [tab] [screenshot.png]
#
# Tabs: Healthy dashboard|food|weight|evaluation|shopping|widget|recovery|logbook
# (recovery, logbook = Dashboard samt dieser Seite), Vault grades|finance,
# Fokus todo|forest|widget, Einkaufsliste (hat nur die eine Seite),
# coHabit today|timeline|stats|profile|new|widget;
# `setup` oeffnet in den ersten vier Apps das Zugang-Blatt.
#
# coHabit braucht keinen der Token unten, sondern einen eigenen je Person -
# aus COCKPIT_COHABIT_TOKEN oder aus dem Schluesselbund (Dienst cohabit_token).
# Gegen einen lokal gestarteten Dienst (Backend-Repo ../habits) umleiten:
#
#   COCKPIT_URL_COHABIT=http://127.0.0.1:48792/cohabit/api \
#   COCKPIT_COHABIT_TOKEN=<Token einer Demo-Person> \
#   tools/run-simulator.sh coHabit today bild.png
#
# COCKPIT_TODAY_MODE=list zeigt „Heute" als Liste, COCKPIT_STATS_RANGE=week|year
# die Statistik fuer eine Woche oder ein Jahr; COCKPIT_TEST_PHOTO=1 laesst den
# Galerie-Knopf im Beweisfoto-Blatt ein erzeugtes Bild liefern (UI-Tests);
# COCKPIT_LINK=cohabit://cohabit/<id> oeffnet beim Start einen Deep Link - auch
# ohne Zugang: cohabit://setup?token=… meldet dann an.
# COCKPIT_CLASSIC=1 legt den Schalter „Klassische Liste" (Profil) beim Start
# um - „Heute" zeigt dann die alte Habit-Liste der Fokus-App; 0 schaltet ihn
# aus. Ohne die Variable bleibt er, wie er war (er ueberlebt jeden Start).
# COCKPIT_TIMELINE_HIDDEN=c-1,c-2 blendet diese Co-Habits im Timeline-Filter
# beim Start aus, none keins; ohne Wert bleibt die gemerkte Auswahl.
# COCKPIT_URL_KLIPY=http://127.0.0.1:48793/api/v1 schickt die GIF-Suche an
# tools/klipy-stub.py statt an KLIPY (ohne echten Schluessel antwortet KLIPY nicht).
#
# Die Token kommen aus dem macOS-Schluesselbund und stehen NIRGENDWO im Repo:
#
#   security add-generic-password -a cockpit-ios -s fh_private \
#       -w '<token>' -T /usr/bin/security -U
#   security add-generic-password -a cockpit-ios -s weight_app_token \
#       -w '<token>' -T /usr/bin/security -U
#   security add-generic-password -a cockpit-ios -s shopping_token \
#       -w '<token>' -T /usr/bin/security -U     # optional, fuer den Einkaufs-Tab
#
# Uebergeben werden sie als Umgebungsvariablen; die App liest sie nur im
# Debug-Build (siehe Access.seedFromEnvironment).
#
# Die NOTEN brauchen ausserdem ein Passwort, und das gehoert nicht in den
# Schluesselbund dieses Rechners - es ist Felix' Anmeldung, nicht die eines
# Dienstes. Fuer einen Blick auf den Tab deshalb den Dienst lokal starten und
# umleiten (ATS laesst Schleifenadressen durch):
#
#   COCKPIT_URL_GRADES=http://127.0.0.1:48230/grades \
#   COCKPIT_GRADES_TOKEN=... COCKPIT_GRADES_USER=felix COCKPIT_GRADES_PASSWORD=... \
#   COCKPIT_NO_LOCK=1 tools/run-simulator.sh grades bild.png
#
# COCKPIT_NO_LOCK=1 ist dabei noetig: im Simulator ist kein Gesicht hinterlegt,
# sonst bleibt der Sperrbildschirm stehen.
#
# HABITS genauso umleitbar (COCKPIT_URL_HABITS=http://127.0.0.1:48190/habits),
# z. B. auf einen lokal mit ./gradlew bootRun gestarteten Dienst; der
# Privat-Token wird dann auch fuer diesen Rechner als Cookie gesetzt.
# COCKPIT_FH_PRIVATE_TOKEN (und COCKPIT_WEIGHT_TOKEN) gehen dem Schluesselbund
# vor - ein lokaler Dienst kennt nur seinen eigenen, z. B. local-private.
#
# COCKPIT_NO_HEALTH=1 laesst die Health-Anbindung aus. Ohne das verdeckt der
# Berechtigungsdialog jeden Screenshot des Gewicht-Tabs, und wegklicken laesst
# er sich nicht - simctl kennt keinen Health-Dienst.
#
# COCKPIT_RANGE=allTime stellt den Gewicht-Tab auf einen Zeitraum
# (month, last90, last180, year, threeYears, allTime).
#
# COCKPIT_EVALUATION_DEMO=1 fuellt den Evaluation-Tab mit einem Jahr erfundener
# Antworten auf drei Platzhalter-Fragen - nur im Speicher, nie in der Datei.
# Mit COCKPIT_NO_LOCK=1, sonst steht dort der Sperrbildschirm.
#
# COCKPIT_DASHBOARD_DEMO=1 zeigt in Healthy erfundene Werte: das Dashboard,
# die Recovery-Seite, das Logbook (Platzhalter „Verhalten A") und die Energie
# (Zeilen im Essen-Tab, Kacheln und Kurve im Gewicht-Tab) - nur im Speicher,
# nie gesendet. Der Simulator bekommt keine
# Health-Daten; ohne das waere nichts davon zu sehen:
#
#   COCKPIT_DASHBOARD_DEMO=1 COCKPIT_NO_HEALTH=1 tools/run-simulator.sh Healthy dashboard bild.png
#
# Gegen einen lokal gestarteten Weight Tracker oder Kalorienzaehler
# (COCKPIT_URL_WEIGHT=http://127.0.0.1:48180, COCKPIT_URL_FOOD=…) samt dessen
# Token in COCKPIT_WEIGHT_TOKEN bzw. COCKPIT_FH_PRIVATE_TOKEN.
#
# COCKPIT_SELECT=2026-08-15 waehlt einen Tag im Diagramm vor, damit die
# Sprechblase im Bild ist - eine Ziehgeste kann der Simulator nicht.
#
# COCKPIT_NO_SCREENTIME=1 laesst im Wald-Tab (Fokus) die Bildschirmzeit aus -
# im Simulator gibt es keine; so laesst sich eine Session trotzdem pflanzen.
# COCKPIT_NO_SHORTCUTS=1 laesst dabei den Sprung in die Kurzbefehle-App aus.
# COCKPIT_FOREST_RUNNING=45 zeigt dort eine laufende Session mit 45 Minuten Rest.
# COCKPIT_FOREST_RANGE=month stellt den Wald auf einen Ausschnitt (today, week, month, year).
# COCKPIT_FOREST_HOUR=19.5 stellt die Uhr der Insel (Stunde in UTC) - Daemmerung, Nacht.
#
# COCKPIT_DAY=2026-08-10 stellt den Essen-Tab auf einen bestimmten Tag. Nuetzlich
# fuer einen leeren Tag: an einem vollen liegt der Verlauf unterhalb des
# Bildschirms, und scrollen kann simctl nicht.
#
# COCKPIT_SCAN=4000417025005 liefert im Essen-Tab sofort diesen Produktcode, als
# waere er gescannt worden: das Scanner-Blatt geht auf, gibt ihn ohne Kamera ab,
# und danach oeffnet sich das Eintrag-Blatt mit dem Produkt aus Open Food Facts.
# Im Simulator gibt es keine Kamera.
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE="${DEVICE:-iPhone 17}"
APP="${1:-Healthy}"
TAB="${2:-}"
SHOT="${3:-}"
case "$APP" in
    Healthy) BUNDLE="com.fherrmann.cockpit" ;;
    Vault)   BUNDLE="com.fherrmann.vault" ;;
    Fokus)   BUNDLE="com.fherrmann.fokus" ;;
    Einkaufsliste) BUNDLE="com.fherrmann.einkauf" ;;
    coHabit) BUNDLE="com.fherrmann.cohabit" ;;
    *) echo "Erste Angabe muss Healthy, Vault, Fokus, Einkaufsliste oder coHabit sein." >&2; exit 1 ;;
esac

if [ "$APP" = "coHabit" ]; then
    PRIVATE=""
    WEIGHT=""
    COHABIT="${COCKPIT_COHABIT_TOKEN:-$(security find-generic-password -a cockpit-ios -s cohabit_token -w 2>/dev/null || true)}"
    [ -n "$COHABIT" ] || echo "Kein coHabit-Token - die App zeigt den Start mit „Link einfügen“." >&2
else
    COHABIT=""
    # Aus der Umgebung vor dem Schluesselbund - gegen einen lokal gestarteten
    # Dienst gilt dessen Token (COCKPIT_FH_PRIVATE_TOKEN=local-private), nicht
    # der vom Server.
    PRIVATE="${COCKPIT_FH_PRIVATE_TOKEN:-}"
    [ -n "$PRIVATE" ] || PRIVATE=$(security find-generic-password -a cockpit-ios -s fh_private -w) || {
        echo "Kein fh_private im Schluesselbund - siehe Kopf dieses Skripts." >&2
        exit 1
    }
    WEIGHT="${COCKPIT_WEIGHT_TOKEN:-}"
    [ -n "$WEIGHT" ] || WEIGHT=$(security find-generic-password -a cockpit-ios -s weight_app_token -w) || {
        echo "Kein weight_app_token im Schluesselbund - siehe Kopf dieses Skripts." >&2
        exit 1
    }
fi
# Der Einkaufs-Token ist freiwillig: ohne ihn fehlt in Healthy der Tab, und
# Einkaufsliste zeigt das Zugang-Blatt - beides ein gueltiger Zustand.
# Aus der Umgebung vor dem Schluesselbund: gegen einen lokal gestarteten
# Dienst (COCKPIT_URL_SHOPPING) gilt dessen Token, nicht der vom Server.
SHOPPING="${COCKPIT_SHOPPING_TOKEN:-$(security find-generic-password -a cockpit-ios -s shopping_token -w 2>/dev/null || true)}"

tools/bootstrap.sh > /dev/null
xcodebuild build -project Cockpit.xcodeproj -scheme "$APP" \
    -destination "platform=iOS Simulator,name=$DEVICE" \
    -derivedDataPath build/sim -quiet

xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl install "$DEVICE" "build/sim/Build/Products/Debug-iphonesimulator/$APP.app"
xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true

SIMCTL_CHILD_COCKPIT_FH_PRIVATE_TOKEN="$PRIVATE" \
SIMCTL_CHILD_COCKPIT_WEIGHT_TOKEN="$WEIGHT" \
SIMCTL_CHILD_COCKPIT_SHOPPING_TOKEN="$SHOPPING" \
SIMCTL_CHILD_COCKPIT_URL_SHOPPING="${COCKPIT_URL_SHOPPING:-}" \
SIMCTL_CHILD_COCKPIT_TAB="$TAB" \
SIMCTL_CHILD_COCKPIT_DAY="${COCKPIT_DAY:-}" \
SIMCTL_CHILD_COCKPIT_NO_HEALTH="${COCKPIT_NO_HEALTH:-}" \
SIMCTL_CHILD_COCKPIT_RANGE="${COCKPIT_RANGE:-}" \
SIMCTL_CHILD_COCKPIT_EVALUATION_DEMO="${COCKPIT_EVALUATION_DEMO:-}" \
SIMCTL_CHILD_COCKPIT_DASHBOARD_DEMO="${COCKPIT_DASHBOARD_DEMO:-}" \
SIMCTL_CHILD_COCKPIT_URL_WEIGHT="${COCKPIT_URL_WEIGHT:-}" \
SIMCTL_CHILD_COCKPIT_URL_FOOD="${COCKPIT_URL_FOOD:-}" \
SIMCTL_CHILD_COCKPIT_SELECT="${COCKPIT_SELECT:-}" \
SIMCTL_CHILD_COCKPIT_SCAN="${COCKPIT_SCAN:-}" \
SIMCTL_CHILD_COCKPIT_FORCE_LOCK="${COCKPIT_FORCE_LOCK:-}" \
SIMCTL_CHILD_COCKPIT_NO_LOCK="${COCKPIT_NO_LOCK:-}" \
SIMCTL_CHILD_COCKPIT_NO_PUSH="${COCKPIT_NO_PUSH:-}" \
SIMCTL_CHILD_COCKPIT_URL_GRADES="${COCKPIT_URL_GRADES:-}" \
SIMCTL_CHILD_COCKPIT_URL_HABITS="${COCKPIT_URL_HABITS:-}" \
SIMCTL_CHILD_COCKPIT_URL_TODO="${COCKPIT_URL_TODO:-}" \
SIMCTL_CHILD_COCKPIT_TODO_AREA="${COCKPIT_TODO_AREA:-}" \
SIMCTL_CHILD_COCKPIT_NO_SCREENTIME="${COCKPIT_NO_SCREENTIME:-}" \
SIMCTL_CHILD_COCKPIT_NO_SHORTCUTS="${COCKPIT_NO_SHORTCUTS:-}" \
SIMCTL_CHILD_COCKPIT_FOREST_RUNNING="${COCKPIT_FOREST_RUNNING:-}" \
SIMCTL_CHILD_COCKPIT_FOREST_RANGE="${COCKPIT_FOREST_RANGE:-}" \
SIMCTL_CHILD_COCKPIT_FOREST_HOUR="${COCKPIT_FOREST_HOUR:-}" \
SIMCTL_CHILD_COCKPIT_GRADES_TOKEN="${COCKPIT_GRADES_TOKEN:-}" \
SIMCTL_CHILD_COCKPIT_GRADES_USER="${COCKPIT_GRADES_USER:-}" \
SIMCTL_CHILD_COCKPIT_GRADES_PASSWORD="${COCKPIT_GRADES_PASSWORD:-}" \
SIMCTL_CHILD_COCKPIT_COHABIT_TOKEN="$COHABIT" \
SIMCTL_CHILD_COCKPIT_URL_COHABIT="${COCKPIT_URL_COHABIT:-}" \
SIMCTL_CHILD_COCKPIT_URL_KLIPY="${COCKPIT_URL_KLIPY:-}" \
SIMCTL_CHILD_COCKPIT_TODAY_MODE="${COCKPIT_TODAY_MODE:-}" \
SIMCTL_CHILD_COCKPIT_CLASSIC="${COCKPIT_CLASSIC:-}" \
SIMCTL_CHILD_COCKPIT_TIMELINE_HIDDEN="${COCKPIT_TIMELINE_HIDDEN:-}" \
SIMCTL_CHILD_COCKPIT_STATS_RANGE="${COCKPIT_STATS_RANGE:-}" \
SIMCTL_CHILD_COCKPIT_TEST_PHOTO="${COCKPIT_TEST_PHOTO:-}" \
SIMCTL_CHILD_COCKPIT_LINK="${COCKPIT_LINK:-}" \
    xcrun simctl launch "$DEVICE" "$BUNDLE" > /dev/null

if [ -n "$SHOT" ]; then
    # Kurz warten: die Tabs laden ihre Daten erst nach dem Erscheinen, ein
    # sofortiger Screenshot zeigt nur den Ladezustand.
    sleep 6
    xcrun simctl io "$DEVICE" screenshot "$SHOT"
    echo "$SHOT"
fi
