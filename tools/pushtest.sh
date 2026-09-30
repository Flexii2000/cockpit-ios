#!/usr/bin/env bash
# Prueft, ob ein Tipp auf eine Benachrichtigung die App ueberlebt.
#
#   tools/pushtest.sh <Healthy|Vault|coHabit> [payload.json]
#
# Der UI-Test kann keine Benachrichtigung erzeugen - das macht dieses Skript
# von aussen mit `simctl push`, waehrend der Test schon wartet. Ohne Nutzlast
# wird die des Kalorienzaehlers genommen (kein `kind`, so wie sie live kommt).
set -euo pipefail
cd "$(dirname "$0")/.."
DEVICE="${DEVICE:-iPhone 17}"
APP="${1:-}"
PAYLOAD="${2:-}"
case "$APP" in
    Healthy) BUNDLE="com.fherrmann.cockpit"
             DEFAULT='{"aps":{"alert":{"title":"Vorschlag ist fertig","body":"Haferbrei – antippen zum Übernehmen."},"sound":"default"}}' ;;
    Vault)   BUNDLE="com.fherrmann.vault"
             DEFAULT='{"aps":{"alert":{"title":"Neue Note 1,7","body":"Datenbanken · Abschlussnote jetzt 1,35"},"sound":"default"},"kind":"grade"}' ;;
    # coHabit: ein Stupser, wie ihn der Dienst schickt - mit Link (Vertrag §4).
    coHabit) BUNDLE="com.fherrmann.cohabit"
             DEFAULT='{"aps":{"alert":{"title":"Lena hat dich angestupst","body":"Heute noch Laufen?"},"sound":"default","thread-id":"c-1"},"kind":"nudge","title":"Lena hat dich angestupst","body":"Heute noch Laufen?","cohabitId":"c-1","link":"cohabit://today"}' ;;
    *) echo "Erste Angabe muss Healthy, Vault oder coHabit sein." >&2; exit 1 ;;
esac
if [ -z "$PAYLOAD" ]; then
    PAYLOAD="$(mktemp -t push).json"
    echo "$DEFAULT" > "$PAYLOAD"
fi

export TEST_RUNNER_COCKPIT_PUSH_TEST=1
# Den Titel aus der Nutzlast an den Test reichen - der wartet auf genau ihn.
TEST_RUNNER_COCKPIT_PUSH_TITLE="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["aps"]["alert"]["title"])' "$PAYLOAD")"
export TEST_RUNNER_COCKPIT_PUSH_TITLE
# Der Test startet, laesst die App erscheinen, drueckt Home und wartet dann bis
# zu 90 s auf die Benachrichtigung. Die Zeit hier deckt Bauen und Start ab.
tools/uitest.sh "$APP" testTappingAPushNotificationDoesNotCrashTheApp &
TEST_PID=$!
sleep 45
xcrun simctl push "$DEVICE" "$BUNDLE" "$PAYLOAD"
wait $TEST_PID
